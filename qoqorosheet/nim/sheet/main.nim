## QoqoroSheet (Nim WebAssembly) — entry point.
##
## The page (wasm/index.html) loads qweb.js, which instantiates this module
## and calls qw_main(). window.sheetApp is the automation surface the page's
## glue uses: loading and exporting workbooks (xlsx/csv conversion stays in
## JS with SheetJS), and the Luckysheet-shaped calls that js/sheetLuau.js
## makes, so Luau programs run unchanged.

import std/[json, tables, strutils]
import ../web/qweb
import model, formula, view, files

{.pragma: wexport, exportc,
  codegenDecl: "__attribute__((export_name(\"$2\"))) $1 $2$3".}

proc NimMain() {.importc, cdecl.}
proc bindweb_js_domain_guard(p: pointer, len: int32): int32 {.importc, cdecl.}

var started = false
var v: SheetView
var serverPath = ""     ## the vault file the workbook came from (Save writes it back)

proc boot() =
  if not started:
    if bindweb_js_domain_guard(nil, 0) != 1:
      {.emit: "__builtin_trap();".}
    started = true
    NimMain()

# ------------------------------------------------------- JSON <-> cells --

const HAligns = [haCenter, haLeft, haRight]        # Luckysheet ht: 0 center, 1 left, 2 right
const VAligns = [vaMiddle, vaTop, vaBottom]        # vt: 0 middle, 1 top, 2 bottom

const BorderNames = ["", "thin", "medium", "thick", "dashed", "dotted", "double", "hair"]

proc borderFromJson(j: JsonNode): Border =
  ## "thin" or ["thin", "#ff0000"]
  let kindName = if j.kind == JString: j.getStr elif j.kind == JArray and j.len > 0: j[0].getStr else: ""
  for i, n in BorderNames:
    if i > 0 and n == kindName: result.kind = BorderKind(i)
  if j.kind == JArray and j.len > 1 and j[1].kind == JString: result.color = j[1].getStr

proc borderToJson(b: Border): JsonNode =
  if b.color.len > 0: %*[BorderNames[ord(b.kind)], b.color] else: %BorderNames[ord(b.kind)]

proc styleFromJson(base: Style, j: JsonNode): Style =
  ## Luckysheet-style keys (bl, it, un, cl, fs, ff, fc, bg, ht, vt) and the
  ## number format (z / numFmt). A null value resets that property.
  result = base
  if j == nil or j.kind != JObject: return
  template flag(k: string, field: untyped) =
    if j.hasKey(k): result.field = j[k].kind in {JInt, JFloat} and j[k].getFloat != 0 or j[k].kind == JBool and j[k].getBool
  flag("bl", bold); flag("it", italic); flag("un", underline); flag("cl", strike); flag("tb", wrap)
  if j.hasKey("fs"): result.fontSize = (if j["fs"].kind in {JInt, JFloat}: j["fs"].getFloat else: 0.0)
  if j.hasKey("ff"): result.font = (if j["ff"].kind == JString: j["ff"].getStr else: "")
  if j.hasKey("fc"): result.color = (if j["fc"].kind == JString: j["fc"].getStr else: "")
  if j.hasKey("bg"): result.fill = (if j["bg"].kind == JString: j["bg"].getStr else: "")
  if j.hasKey("ht"):
    let n = if j["ht"].kind in {JInt, JFloat}: j["ht"].getInt else: -1
    result.hAlign = if n in 0..2: HAligns[n] else: haGeneral
  if j.hasKey("vt"):
    let n = if j["vt"].kind in {JInt, JFloat}: j["vt"].getInt else: -1
    result.vAlign = if n in 0..2: VAligns[n] else: vaDefault
  for k in ["z", "numFmt"]:
    if j.hasKey(k): result.numFmt = (if j[k].kind == JString and j[k].getStr != "General": j[k].getStr else: "")
  # borders: {"bd": {"l": "thin", "r": ["thick", "#c00000"], "t": …, "b": …}}; null clears them
  if j.hasKey("bd"):
    let bd = j["bd"]
    if bd.kind != JObject:
      result.left = Border(); result.right = Border(); result.top = Border(); result.bottom = Border()
    else:
      if bd.hasKey("l"): result.left = borderFromJson(bd["l"])
      if bd.hasKey("r"): result.right = borderFromJson(bd["r"])
      if bd.hasKey("t"): result.top = borderFromJson(bd["t"])
      if bd.hasKey("b"): result.bottom = borderFromJson(bd["b"])

proc styleToJson(st: Style): JsonNode =
  result = newJObject()
  if st.bold: result["bl"] = %1
  if st.italic: result["it"] = %1
  if st.underline: result["un"] = %1
  if st.strike: result["cl"] = %1
  if st.fontSize > 0: result["fs"] = %st.fontSize
  if st.font.len > 0: result["ff"] = %st.font
  if st.color.len > 0: result["fc"] = %st.color
  if st.fill.len > 0: result["bg"] = %st.fill
  case st.hAlign
  of haCenter: result["ht"] = %0
  of haLeft: result["ht"] = %1
  of haRight: result["ht"] = %2
  else: discard
  case st.vAlign
  of vaMiddle: result["vt"] = %0
  of vaTop: result["vt"] = %1
  of vaBottom: result["vt"] = %2
  else: discard
  if st.numFmt.len > 0: result["z"] = %st.numFmt
  var bd = newJObject()
  for (k, b) in [("l", st.left), ("r", st.right), ("t", st.top), ("b", st.bottom)]:
    if b.kind != bkNone: bd[k] = borderToJson(b)
  if bd.len > 0: result["bd"] = bd

proc valueFromJson(j: JsonNode, errorText = false): Value =
  if j == nil: return emptyVal()
  case j.kind
  of JInt, JFloat: numVal(j.getFloat)
  of JBool: boolVal(j.getBool)
  of JString:
    if errorText and j.getStr.startsWith("#"): errVal(j.getStr)
    elif j.getStr.len == 0: emptyVal()
    else: strVal(j.getStr)
  of JObject:
    if j.hasKey("v"): valueFromJson(j["v"], errorText) else: emptyVal()
  else: emptyVal()

proc valueToJson(val: Value): JsonNode =
  case val.kind
  of vkNum: %val.num
  of vkStr, vkErr: %val.str
  of vkBool: %val.b
  else: newJNull()

proc cellFromJson(wb: Workbook, old: Cell, j: JsonNode): Cell =
  ## A cell from a plain value ("=..." is a formula) or {v, m, f, t, z, s, bl, …}.
  result = Cell(style: old.style)
  if j == nil or j.kind == JNull: return
  if j.kind == JString and j.getStr.len > 1 and j.getStr[0] == '=':
    result.setFormula(j.getStr); return
  if j.kind != JObject:
    result.value = valueFromJson(j); return
  let isErr = j.hasKey("t") and j["t"].kind == JString and j["t"].getStr == "e"
  result.value = valueFromJson(j, isErr)
  let f = if j.hasKey("f") and j["f"].kind == JString: j["f"].getStr else: ""
  if f.len > 0:
    result.setFormula(if f.startsWith("="): f else: "=" & f)
    result.value = valueFromJson(j, isErr)         # cached result until the next recalc
  var st = wb.styles[old.style]
  st = styleFromJson(st, j)
  if j.hasKey("s"): st = styleFromJson(st, j["s"])
  result.style = wb.styleId(st)
  # Luckysheet's rich text: ct {t: "inlineStr", s: [{v, bl, it, un, cl, fc, ff, fs}, …]}
  let ct = j{"ct"}
  if ct != nil and ct.kind == JObject and ct{"t"}.getStr == "inlineStr" and ct{"s"} != nil and ct["s"].kind == JArray:
    for part in ct["s"]:
      var run = toRun(st, part{"v"}.getStr)
      run.bold = part{"bl"}.getInt(ord(st.bold)) == 1
      run.italic = part{"it"}.getInt(ord(st.italic)) == 1
      run.underline = part{"un"}.getInt(ord(st.underline)) == 1
      run.strike = part{"cl"}.getInt(ord(st.strike)) == 1
      if part{"fc"}.getStr.len > 0: run.color = part["fc"].getStr
      if part{"ff"}.getStr.len > 0: run.font = part["ff"].getStr
      if part{"fs"}.kind in {JInt, JFloat}: run.fontSize = part["fs"].getFloat
      result.rich.add run
    if result.rich.len > 0: result.value = strVal(richText(result.rich))

proc loadWorkbook(j: JsonNode) =
  let wb = newWorkbook()
  for sj in j{"sheets"}.getElems:
    let s = wb.addSheet(sj{"name"}.getStr("Sheet" & $(wb.sheets.len + 1)))
    for item in sj{"cells"}.getElems:
      if item.len < 3: continue
      let r = item[0].getInt
      let c = item[1].getInt
      if r < 0 or c < 0 or r >= MaxRows or c >= MaxCols: continue
      s.putCell(r, c, cellFromJson(wb, Cell(), item[2]))
    for item in sj{"cols"}.getElems:
      if item.len >= 2 and item[1].getFloat > 0: s.colWidths[item[0].getInt] = item[1].getFloat
    for item in sj{"rows"}.getElems:
      if item.len >= 2 and item[1].getFloat > 0: s.rowHeights[item[0].getInt] = item[1].getFloat
    for item in sj{"merges"}.getElems:
      if item.len >= 4: s.addMerge(Merge(r1: item[0].getInt, c1: item[1].getInt, r2: item[2].getInt, c2: item[3].getInt))
    s.tabColor = sj{"color"}.getStr
    s.hidden = sj{"hide"}.getInt(0) == 1
  if wb.sheets.len == 0: discard wb.addSheet("Sheet1")
  wb.active = clamp(j{"active"}.getInt(0), 0, wb.sheets.len - 1)
  recalc(wb)
  v.wb = wb
  v.ar = 0; v.ac = 0; v.cr = 0; v.cc = 0
  v.activate(wb.active)

proc workbookJson(): JsonNode =
  result = %*{"sheets": [], "active": v.wb.active}
  for s in v.wb.sheets:
    var cells = newJArray()
    for k, cell in s.cells:
      var cj = newJObject()
      cj["v"] = valueToJson(cell.value)
      if cell.value.kind == vkErr: cj["t"] = %"e"
      if cell.formula.len > 0: cj["f"] = %cell.formula
      let m = displayText(v.wb, cell)
      if cell.value.kind == vkNum and m != fmtGeneral(cell.value.num): cj["m"] = %m
      if cell.style != 0: cj["s"] = styleToJson(v.wb.styles[cell.style])
      if cell.rich.len > 0:
        var parts = newJArray()
        for run in cell.rich:
          var pj = %*{"v": run.text, "bl": ord(run.bold), "it": ord(run.italic), "un": ord(run.underline), "cl": ord(run.strike)}
          if run.color.len > 0: pj["fc"] = %run.color
          if run.font.len > 0: pj["ff"] = %run.font
          if run.fontSize > 0: pj["fs"] = %run.fontSize
          parts.add pj
        cj["ct"] = %*{"fa": "General", "t": "inlineStr", "s": parts}
      cells.add %*[rowOf(k), colOf(k), cj]
    var cols = newJArray()
    for c, w in s.colWidths: cols.add %*[c, w]
    var rows = newJArray()
    for r, h in s.rowHeights: rows.add %*[r, h]
    var merges = newJArray()
    for m in s.merges: merges.add %*[m.r1, m.c1, m.r2, m.c2]
    result["sheets"].add %*{"name": s.name, "cells": cells, "cols": cols, "rows": rows, "merges": merges, "color": s.tabColor, "hide": ord(s.hidden)}

proc luckySheets(): JsonNode =
  ## Luckysheet's getAllSheets() shape, as js/sheetLuau.js reads it.
  result = newJArray()
  for i, s in v.wb.sheets:
    var data = newJArray()
    for r in 0 ..< s.maxRow:
      var row = newJArray()
      var last = -1
      for c in 0 ..< s.maxCol:
        if s.hasCell(r, c): last = c
      for c in 0 .. last:
        if not s.hasCell(r, c): row.add newJNull(); continue
        let cell = s.cellAt(r, c)
        var cj = %*{"v": valueToJson(cell.value), "m": displayText(v.wb, cell)}
        if cell.formula.len > 0: cj["f"] = %cell.formula
        row.add cj
      data.add row
    result.add %*{"name": s.name, "index": "s" & $i, "order": i,
                  "status": (if i == v.wb.active: "1" else: "0"), "data": data}

proc sheetIndex(opts: JsonNode): int =
  if opts != nil and opts.kind == JObject and opts.hasKey("order"): clamp(opts["order"].getInt, 0, v.wb.sheets.len - 1)
  else: v.wb.active

proc deleteRows(s: Sheet, r1, r2: int) =
  let n = r2 - r1 + 1
  var moved = initTable[int64, Cell]()
  for k, cell in s.cells:
    let r = rowOf(k)
    if r < r1: moved[k] = cell
    elif r > r2: moved[key(r - n, colOf(k))] = cell
  s.cells = moved
  var heights = initTable[int, float64]()
  for r, h in s.rowHeights:
    if r < r1: heights[r] = h
    elif r > r2: heights[r - n] = h
  s.rowHeights = heights
  var merges: seq[Merge]
  for m in s.merges:
    if m.r2 < r1: merges.add m
    elif m.r1 > r2: merges.add Merge(r1: m.r1 - n, c1: m.c1, r2: m.r2 - n, c2: m.c2)
  s.merges = merges
  s.recomputeUsed()

# -------------------------------------------------------------------- files --

proc hostCall(name: string, args: varargs[JsArg]) =
  let host = window.getNode("QoqoroSheetHost")
  if not host.isNil: host.call(name, args)

proc install(wb: Workbook, name: string) =
  v.wb = wb
  v.fileName = name.split({'/', '\\'})[^1]
  v.ar = 0; v.ac = 0; v.cr = 0; v.cc = 0
  v.activate(wb.active)

proc openBytes(data, name, fromServer: string, request: int) =
  parseInBackground(name, data, proc(wb: Workbook) =
    install(wb, name)
    serverPath = fromServer
    hostCall("opened", request, name)
    v.programAfterOpen(name),
    proc(msg: string) = hostCall("failed", "Open", msg, request))

proc openUrl(url, name, fromServer: string, request: int) =
  ## A file at a URL (a blob: URL from the host page, or /api/spreadsheet).
  fetchBytes(url, proc(ok: bool, data: string) =
    if ok: openBytes(data, name, fromServer, request)
    else: hostCall("failed", "Open", if data.len > 0: data else: "could not read " & name, request))

proc openFileNode(file: Node) =
  let name = file.getStr("name")
  readBlob(file, brBytes, proc(ok: bool, data: string) =
    if ok: openBytes(data, name, "", 0)
    else: hostCall("failed", "Open", "could not read " & name, 0))

proc openPicker() =
  ## The top bar's #xlsxUpload input when present, else a temporary one.
  let page = document.invoke("getElementById", "xlsxUpload").toNode
  if not page.isNil: page.click(); return
  let input = el("input")
  input.setAttribute("type", "file")
  input.setAttribute("accept", ".xlsx,.csv,.tsv,.txt")
  input.on("change", proc(e: Event) =
    let file = input.getNode("files").invoke("item", 0).toNode
    if not file.isNil: openFileNode(file))
  input.click()

proc baseName(): string =
  let n = if v.fileName.len > 0: v.fileName else: "sheet.xlsx"
  let dot = n.rfind('.')
  if dot > 0: n[0 ..< dot] else: n

proc save(path: string, request: int) =
  let target = if path.len > 0: path else: serverPath
  if target.len > 0:
    saveToServer(v.wb, target, proc() =
      serverPath = target
      hostCall("saved", target, request),
      proc(msg: string) = hostCall("failed", "Save", msg, request))
  else:
    writeInBackground(v.wb, 'x', proc(data: string) =
      downloadBytes(data, baseName() & ".xlsx", mimeFor(".xlsx"))
      hostCall("saved", "", request),
      proc(msg: string) = hostCall("failed", "Save", msg, request))

proc exportFile(kind: char, request: int) =
  ## The workbook as a Blob for the host page (QoqoroSheetFiles.bytes).
  writeInBackground(v.wb, kind, proc(data: string) =
    hostCall("exported", request, newBlob(data, mimeFor(if kind == 'c': ".csv" else: ".xlsx"))),
    proc(msg: string) = hostCall("failed", "Export", msg, request))

proc exportOpju(format = "native") =
  ## Every sheet as an Origin workbook (row 1: the column labels), built by
  ## the server's OPJU codec (/api/opju/export, as opjuIO.js posts it). When a
  ## real Origin project cannot hold the sheets, the portable container is
  ## offered instead, never silently.
  var books = newJArray()
  for s in v.wb.sheets:
    if s.name == "__sheetapp_charts__": continue
    var cells = newJArray()
    var maxR, maxC = -1
    for k, cell in s.cells:
      let val = case cell.value.kind
        of vkNum: %cell.value.num
        of vkStr: %cell.value.str
        of vkBool: %cell.value.b
        else: newJNull()
      if val.kind == JNull: continue
      cells.add %*{"r": rowOf(k), "c": colOf(k), "v": val}
      maxR = max(maxR, rowOf(k)); maxC = max(maxC, colOf(k))
    books.add %*{"name": s.name.substr(0, 30), "worksheetName": "Sheet1", "cells": cells, "rowCount": maxR + 1, "columnCount": maxC + 1}
  if books.len == 0: hostCall("failed", "OPJU export", "There are no sheets to export.", 0); return
  let file = baseName() & ".opju"
  fetchPostJson("/api/opju/export", $ %*{"filename": file, "workbooks": books, "format": format}, proc(ok: bool, data: string) =
    if ok:
      downloadBytes(data, file, "application/octet-stream")
      return
    var msg = if data.len > 0: data else: "OPJU export failed"
    var code = ""
    try:
      let j = parseJson(data)
      msg = j{"error"}.getStr(msg); code = j{"code"}.getStr
    except CatchableError: discard
    if format == "native" and code in ["native-shape", "native-unavailable"] and
       window.invoke("confirm", msg & "\n\nDownload SheetApp's portable container instead? It keeps every sheet and any text cells, but OriginPro cannot open it.").toBool:
      exportOpju("portable")
    else: hostCall("failed", "OPJU export", msg, 0))

# --------------------------------------------------------------- automation --

proc reply(j: JsonNode): ApiReply = ApiReply(kind: apiValue, json: $j)
proc err(msg: string): ApiReply = ApiReply(kind: apiError, json: msg)

proc automation(path: string, op: int, argsJson: string): ApiReply =
  let member = if path.startsWith("sheetApp."): path[9 .. ^1] else: path
  if op == 0:
    case member
    of "", "sheetApp": return ApiReply(kind: apiObject)
    of "fileName": return reply(%v.fileName)
    of "activeSheet": return reply(%v.wb.active)
    of "sheetCount": return reply(%v.wb.sheets.len)
    of "selection":
      let (r1, c1, r2, c2) = v.selRect()
      return reply(%*{"row": [r1, r2], "column": [c1, c2]})
    of "root": return ApiReply(kind: apiNode, node: v.root)
    of "serverPath": return reply(%serverPath)
    of "usingWorker": return reply(%usingWorker())
    else: return ApiReply(kind: apiFunction)
  if op == 2:
    let a = parseJson(argsJson)
    if member == "fileName": v.fileName = a[0].getStr; return reply(newJNull())
    return err("cannot assign " & member)
  try:
    let a = parseJson(argsJson)
    template arg(i: int): JsonNode = (if i < a.len: a[i] else: newJNull())
    case member
    of "loadWorkbook":
      loadWorkbook(arg(0))
      if arg(1).kind == JString: v.fileName = arg(1).getStr
      return reply(%true)
    of "workbookJson": return reply(workbookJson())
    of "getAllSheets": return reply(luckySheets())
    of "sheetState":
      # a sheet's stage 7 state, for tests and programs
      let s = v.wb.sheets[sheetIndex(arg(0))]
      let st = v.wb.styles[s.cellAt(v.ar, v.ac).style]
      var rows = newJArray()
      for r in s.filterRows: rows.add %r
      return reply(%*{"frozenRows": s.frozenRows, "frozenCols": s.frozenCols, "filter": s.filter.on, "filterRows": rows,
        "rules": s.condRules.len, "validations": s.validations.len, "notes": s.notes.len, "links": s.links.len,
        "pictures": s.pictures.len, "protected": s.protected, "pivot": s.pivot.source,
        "active": {"wrap": st.wrap, "rotation": st.rotation, "locked": not st.unlocked}})
    of "setCellValue":
      let si = sheetIndex(arg(3))
      let r = arg(0).getInt
      let c = arg(1).getInt
      if r < 0 or c < 0 or r >= MaxRows or c >= MaxCols: return err("cell out of range")
      let s = v.wb.sheets[si]
      let val = arg(2)
      var cell: Cell
      if val.kind == JObject and val.hasKey("v") and val["v"].kind == JString and val["v"].getStr == "" and
         not (val.hasKey("f") and val["f"].kind == JString and val["f"].getStr.len > 0) and
         val.hasKey("bg") and val["bg"].kind == JNull:
        cell = Cell()                                  # Luau's Clear: value, formula and format
      else:
        cell = cellFromJson(v.wb, s.cellAt(r, c), val)
      s.putCell(r, c, cell)
      if arg(3).kind != JObject or arg(3){"isRefresh"}.getBool(true): (recalc(v.wb); v.requestDraw())
      return reply(%true)
    of "getCellValue":
      let s = v.wb.sheets[sheetIndex(arg(2))]
      return reply(valueToJson(s.cellAt(arg(0).getInt, arg(1).getInt).value))
    of "setSheetAdd":
      # Luckysheet's shape: {sheetObject: {name, celldata: [{r, c, v}], config: {columnlen: {col: px}}}}
      let so = arg(0){"sheetObject"}
      var name = so{"name"}.getStr("Sheet" & $(v.wb.sheets.len + 1))
      var n = 2
      let base = name
      while v.wb.sheetNamed(name) != nil: name = base & " (" & $n & ")"; inc n
      let s = v.wb.addSheet(name)
      for item in so{"celldata"}.getElems:
        let r = item{"r"}.getInt(-1)
        let c = item{"c"}.getInt(-1)
        if r < 0 or c < 0 or r >= MaxRows or c >= MaxCols: continue
        s.putCell(r, c, cellFromJson(v.wb, Cell(), item{"v"}))
      for k, w in so{"config"}{"columnlen"}.getFields:
        try: s.colWidths[parseInt(k)] = w.getFloat
        except ValueError: discard
      recalc(v.wb)
      v.rebuildTabs()
      # Luckysheet returns the new sheet
      let order = v.wb.sheets.len - 1
      return reply(%*{"name": name, "order": order, "index": "s" & $order, "status": "0"})
    of "setSheetActive":
      v.activate(arg(0).getInt)
      return reply(%true)
    of "refresh":
      recalc(v.wb)
      v.refreshFormulaBar()
      v.requestDraw()
      return reply(%true)
    of "deleteRowOrColumn":
      if arg(0).getStr == "row":
        deleteRows(v.wb.sheets[sheetIndex(arg(3))], arg(1).getInt, arg(2).getInt)
        recalc(v.wb)
        v.requestDraw()
      return reply(%true)
    of "cellRect":
      let (x, y, w, h) = v.cellBox(arg(0).getInt, arg(1).getInt)
      return reply(%*{"x": x, "y": y, "w": w, "h": h})
    of "setSelection":
      v.ar = arg(0).getInt; v.ac = arg(1).getInt
      v.cr = arg(2).getInt(v.ar); v.cc = arg(3).getInt(v.ac)
      v.extraRanges.setLen(0)
      v.snapAnchor()
      v.refreshFormulaBar(); v.showSelection(); v.requestDraw()
      return reply(%true)
    of "openUrl":
      openUrl(arg(0).getStr, arg(1).getStr("sheet.xlsx"), arg(2).getStr, arg(3).getInt)
      return reply(%true)
    of "save":
      save(arg(0).getStr, arg(1).getInt)
      return reply(%true)
    of "exportFile":
      exportFile(if arg(0).getStr == "csv": 'c' else: 'x', arg(1).getInt)
      return reply(%true)
    of "toggleMerge":
      v.toggleMerge()
      return reply(%true)
    of "applyBorders":
      v.applyBorders(arg(0).getStr)
      return reply(%true)
    of "undo":
      v.doUndo()
      return reply(%true)
    of "focus":
      v.editor.focus(true)
      return reply(%true)
    else: return err("unknown member: " & member)
  except CatchableError as e:
    return err(e.msg)

# ----------------------------------------------------------------- exports --

proc qw_main() {.wexport.} =
  boot()
  apiHandler = automation
  let wb = newWorkbook()
  discard wb.addSheet("Sheet1")
  v = newSheetView(wb)
  v.hostCall = proc(name: string, args: JsonNode) =
    case name
    of "open": openPicker()
    of "save": save("", 0)
    of "saveServer":
      var path = serverPath
      if path.len == 0:
        let (ok, name) = prompt("Save to server as", baseName() & ".xlsx")
        if not ok or name.strip.len == 0: return
        path = name.strip
      save(path, 0)
    of "opju": exportOpju()
    of "csv":
      writeInBackground(v.wb, 'c', proc(data: string) =
        downloadBytes(data, baseName() & ".csv", mimeFor(".csv")),
        proc(msg: string) = hostCall("failed", "CSV export", msg, 0))
    else:
      let host = window.getNode("QoqoroSheetHost")
      if not host.isNil: host.call(name, jsJson($args))
  v.onOpenFile = proc(file: Node) = openFileNode(file)
  v.onChange = proc() =
    let host = window.getNode("QoqoroSheetHost")
    if not host.isNil: host.call("changed")
  expose("sheetApp")
  let host = window.getNode("QoqoroSheetHost")
  if not host.isNil: host.call("ready")
  flush()

proc qw_worker_main(kind: int32) {.wexport.} =
  boot()
  if kind == FileWorker: workerMain()
  flush()
