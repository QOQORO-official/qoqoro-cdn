## Find and Replace (Ctrl+F / Ctrl+H), included into view.nim: Excel's dialog
## (searchReplace.js's in Luckysheet): Find Next from the active cell row by
## row, Find All with a list to go to, Replace (the current match) and
## Replace All; Match case, Match entire cell contents, search in the sheet
## or the workbook, look in values or formulas.

type Hit = tuple[sheet, r, c: int]

proc cellSearchText(v: SheetView, cell: Cell, formulas: bool): string =
  if formulas and cell.formula.len > 0: cell.formula else: v.wb.displayText(cell)

proc matches(text, what: string, matchCase, whole: bool): bool =
  if what.len == 0: return false
  let a = if matchCase: text else: text.toLowerAscii
  let b = if matchCase: what else: what.toLowerAscii
  if whole: a == b else: b in a

proc findAll(v: SheetView, what: string, matchCase, whole, workbook, formulas: bool): seq[Hit] =
  ## row by row (Excel's "By Rows"), sheet by sheet from the active one
  var order: seq[int]
  if workbook:
    for i in 0 ..< v.wb.sheets.len: order.add (v.wb.active + i) mod v.wb.sheets.len
  else: order = @[v.wb.active]
  for si in order:
    let s = v.wb.sheets[si]
    var keys: seq[int64]
    for k, cell in s.cells:
      if cell.value.kind != vkEmpty and matches(v.cellSearchText(cell, formulas), what, matchCase, whole): keys.add k
    keys.sort()
    for k in keys: result.add (si, rowOf(k), colOf(k))

proc goToHit(v: SheetView, h: Hit) =
  if h.sheet != v.wb.active: v.activate(h.sheet)
  v.moveTo(h.r, h.c)

proc replaceIn(text, what, by: string, matchCase, whole: bool): string =
  if whole: return by
  if matchCase: return text.replace(what, by)
  # case-insensitive replace
  let low = text.toLowerAscii
  let w = what.toLowerAscii
  var i = 0
  while i < text.len:
    if low.continuesWith(w, i): result.add by; i += what.len
    else: result.add text[i]; inc i

proc openFind*(v: SheetView, replace = false) =
  var last = storageGet("qoqorosheet-find")[1]
  let body = dlgRow("Find what", dlgInput("what", last, 240)) &
    "<div class=\"qs-replace\" style=\"display:" & (if replace: "block" else: "none") & "\">" & dlgRow("Replace with", dlgInput("by", "", 240)) & "</div>" &
    dlgRow("Within", dlgSelect("within", @[("sheet", "Sheet"), ("workbook", "Workbook")], "sheet")) &
    dlgRow("Look in", dlgSelect("lookin", @[("values", "Values"), ("formulas", "Formulas")], if replace: "formulas" else: "values")) &
    dlgRow("", dlgCheck("case", "Match case") & dlgCheck("whole", "Match entire cell contents")) &
    "<div class=\"qs-find-list\" style=\"max-height:180px;overflow:auto;margin-top:6px;font-size:12px\"></div>"
  var buttons = @[("next", "Find Next"), ("all", "Find All")]
  if replace: buttons.add @[("replace", "Replace"), ("replaceall", "Replace All")]
  buttons.add ("close", "Close")
  let title = if replace: "Find and Replace" else: "Find"
  discard v.openDialog("qs-find", title, body, buttons, proc(b: string, box: Node): bool =
    if b == "close": return true
    let what = box.field("what")
    discard storageSet("qoqorosheet-find", what)
    let matchCase = box.field("case").len > 0
    let whole = box.field("whole").len > 0
    let workbook = box.field("within") == "workbook"
    let formulas = box.field("lookin") == "formulas"
    let hits = v.findAll(what, matchCase, whole, workbook, formulas)
    let list = box.query(".qs-find-list")
    proc notFound() =
      v.tooltipInfo(title, "We couldn't find what you were looking for.")
    case b
    of "next":
      if hits.len == 0: notFound(); return false
      # the first match after the active cell (row by row), wrapping
      var pick = hits[0]
      for h in hits:
        if h.sheet == v.wb.active and (h.r > v.ar or h.r == v.ar and h.c > v.ac): pick = h; break
      v.goToHit(pick)
    of "all":
      if hits.len == 0: notFound(); list.setProp("innerHTML", ""); return false
      var html = "<div style=\"color:#555;margin-bottom:4px\">" & $hits.len & " cell(s) found</div>"
      for i, h in hits:
        let s = v.wb.sheets[h.sheet]
        html.add "<div class=\"qs-hit\" data-i=\"" & $i & "\" style=\"display:flex;gap:10px;padding:2px 4px;cursor:pointer\"><span style=\"width:80px\">" &
          esc(s.name) & "</span><span style=\"width:50px\">" & cellName(h.r, h.c) & "</span><span>" & esc(v.wb.displayText(s.cellAt(h.r, h.c))) & "</span></div>"
      list.setProp("innerHTML", html)
      for row_1 in list.queryAll(".qs-hit"):
        let row_0 = row_1
        closureScope:
          let row = row_0
          let i = parseInt(row.invoke("getAttribute", "data-i").toStr)
          let hit = hits[i]
          row.on("click", proc(e: Event) = v.goToHit(hit))
    of "replace":
      let by = box.field("by")
      let s = v.sheet
      let cell = s.cellAt(v.ar, v.ac)
      if cell.value.kind != vkEmpty and matches(v.cellSearchText(cell, formulas), what, matchCase, whole):
        if v.rangeLocked(v.ar, v.ac, v.ar, v.ac): v.protectedMessage(); return false
        var act: Action
        let text = replaceIn(v.cellSearchText(cell, true), what, by, matchCase, whole)
        v.setCellRaw(v.wb.active, v.ar, v.ac, parseInput(v.wb, text, cell), act)
        v.commitAction(act)
        v.requestDraw()
      # then on to the next one (Excel)
      let more = v.findAll(what, matchCase, whole, workbook, formulas)
      for h in more:
        if h.sheet == v.wb.active and (h.r > v.ar or h.r == v.ar and h.c > v.ac): v.goToHit(h); return false
      if more.len > 0: v.goToHit(more[0])
    of "replaceall":
      if hits.len == 0: notFound(); return false
      let by = box.field("by")
      var act: Action
      for h in hits:
        let s = v.wb.sheets[h.sheet]
        let cell = s.cellAt(h.r, h.c)
        let text = replaceIn(v.cellSearchText(cell, true), what, by, matchCase, whole)
        v.setCellRaw(h.sheet, h.r, h.c, parseInput(v.wb, text, cell), act)
      v.commitAction(act)
      v.requestDraw()
      v.tooltipInfo(title, "All done. We made " & $hits.len & " replacement(s).")
    else: discard
    false, 440)
