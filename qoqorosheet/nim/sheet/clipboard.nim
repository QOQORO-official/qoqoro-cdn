## Copy, cut and paste, included into view.nim. Excel's behaviour with
## Luckysheet's marching ants (select.js selectionCopyShow):
##  * copy puts tab-separated text and an HTML table (inline styles, merges as
##    colspan / rowspan) on the clipboard, so Excel, Sheets and Word keep the
##    formatting;
##  * cut moves the cells when they are pasted (formulas unchanged); copy
##    pastes formulas shifted, styles and merges, tiled over a selection that
##    is an exact multiple of the copied range;
##  * an HTML table from Excel / Google Sheets / a web page pastes with its
##    styles (classes from its <style>, inline styles, b / i / u tags), Excel's
##    x:num values and mso-number-format formats, and merges;
##  * Esc, or any edit, ends copy mode.

type ClipState = object
  active, cut: bool
  sheet: int
  r1, c1, r2, c2: int
  text: string                ## the text/plain we put on the clipboard (recognises our own paste)
  cells: seq[seq[Cell]]
  merges: seq[Merge]          ## relative to (r1, c1)

var clip: ClipState

# --------------------------------------------------------------- the ants --

proc showCopyAnts(v: SheetView) =
  let box = byId("luckysheet-selection-copy")
  if box.isNil: return
  box.dropChildren()
  if not clip.active or clip.sheet != v.wb.active: return
  let (x, y, w, h) = v.rangeBox(clip.r1, clip.c1, clip.r2, clip.c2)
  let d = el("div", "luckysheet-selection-copy")
  d.setAttribute("style", "display: block; left: " & px(x) & "; width: " & px(w) & "; top: " & px(y) & "; height: " & px(h) & ";")
  d.setProp("innerHTML", "<div class=\"luckysheet-selection-copy-top luckysheet-copy\"></div><div class=\"luckysheet-selection-copy-right luckysheet-copy\"></div>" &
    "<div class=\"luckysheet-selection-copy-bottom luckysheet-copy\"></div><div class=\"luckysheet-selection-copy-left luckysheet-copy\"></div><div class=\"luckysheet-selection-copy-hc\"></div>")
  discard box.add d

proc endCopyMode*(v: SheetView) =
  if not clip.active: return
  clip.active = false
  v.showCopyAnts()

# ------------------------------------------------------------------- copy --

proc cssColor(c: string): string = (if c.len > 0: c else: "")

proc cellCss(wb: Workbook, st: Style): string =
  if st.bold: result.add "font-weight:bold;"
  if st.italic: result.add "font-style:italic;"
  if st.underline and st.strike: result.add "text-decoration:underline line-through;"
  elif st.underline: result.add "text-decoration:underline;"
  elif st.strike: result.add "text-decoration:line-through;"
  if st.color.len > 0: result.add "color:" & st.color & ";"
  if st.fill.len > 0: result.add "background:" & st.fill & ";"
  if st.font.len > 0: result.add "font-family:" & st.font & ";"
  if st.fontSize > 0: result.add "font-size:" & $st.fontSize & "pt;"
  case st.hAlign
  of haLeft: result.add "text-align:left;"
  of haCenter: result.add "text-align:center;"
  of haRight: result.add "text-align:right;"
  else: discard
  case st.vAlign
  of vaTop: result.add "vertical-align:top;"
  of vaMiddle: result.add "vertical-align:middle;"
  of vaBottom: result.add "vertical-align:bottom;"
  else: discard
  for (side, b) in [("left", st.left), ("right", st.right), ("top", st.top), ("bottom", st.bottom)]:
    if b.kind != bkNone:
      let w = if b.kind == bkThick: "3px" elif b.kind == bkMedium: "2px" else: "1px"
      let kind = if b.kind in {bkDashed}: "dashed" elif b.kind in {bkDotted, bkHair}: "dotted" else: "solid"
      result.add "border-" & side & ":" & w & " " & kind & " " & (if b.color.len > 0: b.color else: "#000000") & ";"

proc copyRanges(v: SheetView): bool =
  ## Excel: one range only.
  if v.extraRanges.len > 0:
    v.tooltipInfo("Cannot perform this operation on multiple selection areas, please select a single area", "")
    return false
  true

proc copySelection*(v: SheetView, cut = false): (string, string) =
  ## (text/plain, text/html) of the selection; the selection becomes the copied range.
  let (r1, c1, r2, c2) = v.selRect()
  let s = v.sheet
  var tsv, html = ""
  html = "<table style=\"border-collapse:collapse\">"
  var covered: seq[(int, int)]
  clip = ClipState(active: true, cut: cut, sheet: v.wb.active, r1: r1, c1: c1, r2: r2, c2: c2)
  for m in s.merges:
    if m.r1 >= r1 and m.r2 <= r2 and m.c1 >= c1 and m.c2 <= c2:
      clip.merges.add Merge(r1: m.r1 - r1, c1: m.c1 - c1, r2: m.r2 - r1, c2: m.c2 - c1)
  for r in r1 .. r2:
    var row: seq[Cell]
    if r > r1: tsv.add "\r\n"
    html.add "<tr>"
    for c in c1 .. c2:
      let cell = s.cellAt(r, c)
      row.add cell
      if c > c1: tsv.add '\t'
      var t = v.wb.displayText(cell)
      let quoted = if '\t' in t or '\n' in t or '"' in t: "\"" & t.replace("\"", "\"\"") & "\"" else: t
      tsv.add quoted
      if (r, c) in covered: continue
      var span = ""
      let mi = s.mergeAt(r, c)
      if mi >= 0:
        let m = s.merges[mi]
        if m.r1 == r and m.c1 == c:
          if m.c2 > m.c1: span.add " colspan=\"" & $(min(m.c2, c2) - c + 1) & "\""
          if m.r2 > m.r1: span.add " rowspan=\"" & $(min(m.r2, r2) - r + 1) & "\""
          for rr in r .. min(m.r2, r2):
            for cc in c .. min(m.c2, c2):
              if rr != r or cc != c: covered.add (rr, cc)
      let num = if cell.value.kind == vkNum: " x:num=\"" & $cell.value.num & "\"" else: ""
      let inner = if cell.rich.len > 0 and cell.formula.len == 0: richHtml(v.wb.styles[cell.style], cell.rich)
                  else: t.multiReplace(("&", "&amp;"), ("<", "&lt;"), (">", "&gt;"), ("\n", "<br>"))
      html.add "<td" & span & num & " style=\"" & cellCss(v.wb, v.wb.styles[cell.style]) & "\">" & inner & "</td>"
    clip.cells.add row
    html.add "</tr>"
  html.add "</table>"
  clip.text = tsv
  v.showCopyAnts()
  (tsv, html)

# ------------------------------------------------------------------- paste --

proc parseTsv(text: string): seq[seq[string]] =
  var row: seq[string]
  var field = ""
  var i = 0
  var quoted = false
  while i < text.len:
    let ch = text[i]
    if quoted:
      if ch == '"':
        if i + 1 < text.len and text[i + 1] == '"': field.add '"'; inc i
        else: quoted = false
      else: field.add ch
    elif ch == '"' and field.len == 0: quoted = true
    elif ch == '\t': row.add field; field = ""
    elif ch == '\n' or ch == '\r':
      if ch == '\r' and i + 1 < text.len and text[i + 1] == '\n': inc i
      row.add field; field = ""
      result.add row; row = @[]
    else: field.add ch
    inc i
  if field.len > 0 or row.len > 0:
    row.add field
    result.add row

type PasteCell = object
  text: string
  num: float64
  isNum: bool
  style: Style
  rowspan, colspan: int

proc applyCss(st: var Style, css: string) =
  ## The declarations of a cell's CSS that a sheet cell can hold.
  for decl in css.split(';'):
    let i = decl.find(':')
    if i < 0: continue
    let k = decl[0 ..< i].strip.toLowerAscii
    let val = decl[i + 1 .. ^1].strip
    let lv = val.toLowerAscii
    proc color(x: string): string =
      let t = x.strip
      if t.startsWith("#") or t.startsWith("rgb"): t else: ""
    case k
    of "font-weight": st.bold = lv in ["bold", "bolder"] or (lv.len > 0 and lv[0] in {'6'..'9'})
    of "font-style": st.italic = lv == "italic" or lv == "oblique"
    of "text-decoration", "text-decoration-line":
      st.underline = "underline" in lv
      st.strike = "line-through" in lv
    of "color": (let c = color(val); if c.len > 0: st.color = c)
    of "background", "background-color":
      let c = color(val.split(' ')[0])
      if c.len > 0 and c notin ["#ffffff", "#fff", "rgb(255, 255, 255)"]: st.fill = c
    of "text-align":
      st.hAlign = case lv
        of "left", "start": haLeft
        of "center": haCenter
        of "right", "end": haRight
        else: st.hAlign
    of "vertical-align":
      st.vAlign = case lv
        of "top": vaTop
        of "middle": vaMiddle
        of "bottom": vaBottom
        else: st.vAlign
    of "font-size":
      try:
        if lv.endsWith("pt"): st.fontSize = parseFloat(lv[0 ..< ^2])
        elif lv.endsWith("px"): st.fontSize = round(parseFloat(lv[0 ..< ^2]) * 0.75 * 2) / 2
      except ValueError: discard
    of "font-family":
      let f = val.split(',')[0].strip(chars = {' ', '"', '\''})
      if f.len > 0 and f.toLowerAscii notin ["sans-serif", "serif", "monospace"]: st.font = f
    of "mso-number-format":
      var f = val.strip(chars = {'"', '\'', ' '}).replace("\\", "")
      if f notin ["General", "@"] and f.len > 0 and f.len < 60: st.numFmt = f
    else: discard

proc parseHtmlTable(html: string): seq[seq[PasteCell]] =
  ## The first <table> of `html`, by the browser's parser (DOMParser).
  let parser = construct("DOMParser")
  let doc = parser.invoke("parseFromString", html, "text/html").toNode
  defer: parser.release()
  if doc.isNil: return
  let table = doc.query("table")
  if table.isNil: return
  # class rules of its <style> (Excel's .xl65 { … })
  var rules: Table[string, string]
  for st in doc.queryAll("style"):
    let css = st.getStr("textContent")
    var i = 0
    while true:
      let open = css.find('{', i)
      if open < 0: break
      let close = css.find('}', open)
      if close < 0: break
      for sel in css[i ..< open].split(','):
        let s2 = sel.strip
        if s2.startsWith("."): rules[s2[1 .. ^1].strip] = rules.getOrDefault(s2[1 .. ^1].strip) & ";" & css[open + 1 ..< close]
        elif s2 in ["td", "th"]: rules["td"] = rules.getOrDefault("td") & ";" & css[open + 1 ..< close]
      i = close + 1
  for br in table.queryAll("br"): br.call("replaceWith", "\n")
  for tr in table.queryAll("tr"):
    var row: seq[PasteCell]
    for td in tr.queryAll(":scope > td, :scope > th"):
      var st = Style()
      st.applyCss(rules.getOrDefault("td"))
      for cls in strutils.splitWhitespace(td.getStr("className")): st.applyCss(rules.getOrDefault(cls))
      st.applyCss(td.invoke("getAttribute", "style").toStr)
      if not td.query("b, strong").isNil: st.bold = true
      if not td.query("i, em").isNil: st.italic = true
      if not td.query("u").isNil: st.underline = true
      if not td.query("s, strike, del").isNil: st.strike = true
      let font = td.query("font[color]")
      if not font.isNil: st.color = font.invoke("getAttribute", "color").toStr
      for inner in td.queryAll("[style]"): st.applyCss(inner.invoke("getAttribute", "style").toStr)
      var text = td.getStr("textContent").replace("\r", "").replace(" ", " ")
      var lines = text.split('\n').mapIt(strutils.splitWhitespace(it).join(" "))
      while lines.len > 1 and lines[^1].len == 0: discard lines.pop()
      while lines.len > 1 and lines[0].len == 0: lines.delete(0)
      text = lines.join("\n")
      var pc = PasteCell(text: text, style: st, rowspan: 1, colspan: 1)
      let xnum = td.invoke("getAttribute", "x:num").toStr
      if xnum.len > 0:
        try: pc.num = parseFloat(xnum); pc.isNum = true
        except ValueError: discard
      try: pc.colspan = max(1, parseInt(td.invoke("getAttribute", "colspan").toStr))
      except ValueError: discard
      try: pc.rowspan = max(1, parseInt(td.invoke("getAttribute", "rowspan").toStr))
      except ValueError: discard
      row.add pc
    result.add row
  doc.release()

proc pasteInternal(v: SheetView) =
  ## Our own copy / cut.
  let s = v.sheet
  let src = v.wb.sheets[min(clip.sheet, v.wb.sheets.high)]
  let h = clip.r2 - clip.r1 + 1
  let w = clip.c2 - clip.c1 + 1
  let (t1, u1, t2, u2) = v.selRect()
  # Excel tiles the copy over a selection that is an exact multiple of it
  var reps = (1, 1)
  if not clip.cut and (t2 - t1 + 1) mod h == 0 and (u2 - u1 + 1) mod w == 0:
    reps = ((t2 - t1 + 1) div h, (u2 - u1 + 1) div w)
  let (br, bc) = (t1, u1)
  if s.hasPartMerge(br, bc, br + h * reps[0] - 1, bc + w * reps[1] - 1):
    v.tooltipInfo("Cannot perform this operation on merged cells", ""); return
  var act: Action
  let mergesBefore = s.merges
  var merges = s.merges
  if clip.cut:
    # the source empties first (and loses its merges)
    for r in clip.r1 .. clip.r2:
      for c in clip.c1 .. clip.c2:
        if src.hasCell(r, c): v.setCellRaw(clip.sheet, r, c, Cell(), act)
    if src == s:
      merges = merges.filterIt(not (it.r1 >= clip.r1 and it.r2 <= clip.r2 and it.c1 >= clip.c1 and it.c2 <= clip.c2))
    else:
      let before = src.merges
      src.merges = src.merges.filterIt(not (it.r1 >= clip.r1 and it.r2 <= clip.r2 and it.c1 >= clip.c1 and it.c2 <= clip.c2))
      act.add Change(sheet: clip.sheet, isMerge: true, mergesBefore: before, mergesAfter: src.merges)
  let lastR = br + h * reps[0] - 1
  let lastC = bc + w * reps[1] - 1
  merges = merges.filterIt(not (it.r2 >= br and it.r1 <= lastR and it.c2 >= bc and it.c1 <= lastC))
  for i in 0 ..< reps[0]:
    for j in 0 ..< reps[1]:
      let r0 = br + i * h
      let c0 = bc + j * w
      for dr in 0 ..< h:
        for dc in 0 ..< w:
          var cell = clip.cells[dr][dc]
          if cell.formula.len > 0 and not clip.cut:
            cell.setFormula(shiftFormula(cell.formula, r0 + dr - (clip.r1 + dr), c0 + dc - (clip.c1 + dc)))
          v.setCellRaw(v.wb.active, r0 + dr, c0 + dc, cell, act)
      for m in clip.merges:
        merges.add Merge(r1: m.r1 + r0, c1: m.c1 + c0, r2: m.r2 + r0, c2: m.c2 + c0)
  s.merges = merges
  act.add Change(sheet: v.wb.active, isMerge: true, mergesBefore: mergesBefore, mergesAfter: merges)
  v.extraRanges.setLen(0)
  v.ar = br; v.ac = bc; v.cr = lastR; v.cc = lastC
  v.commitAction(act)
  if clip.cut: v.endCopyMode()      # a cut pastes once (Excel)

proc pasteExternal(v: SheetView, text, html: string) =
  let s = v.sheet
  var act: Action
  let (br, bc, _, _) = v.selRect()
  var h, w = 0
  let mergesBefore = s.merges
  var newMerges: seq[Merge]
  let table = if html.len > 0 and "<table" in html.toLowerAscii: parseHtmlTable(html) else: @[]
  if table.len > 0:
    var taken: seq[(int, int)]
    for i, row in table:
      var c = 0
      for pc in row:
        while (i, c) in taken: inc c
        let r = br + i
        let col = bc + c
        var cell = parseInput(v.wb, pc.text, Cell(style: v.wb.styleId(pc.style)))
        if pc.isNum and pc.text.len > 0 and pc.text[0] != '=': cell.value = numVal(pc.num)
        v.setCellRaw(v.wb.active, r, col, cell, act)
        if pc.rowspan > 1 or pc.colspan > 1:
          newMerges.add Merge(r1: r, c1: col, r2: r + pc.rowspan - 1, c2: col + pc.colspan - 1)
          for rr in i ..< i + pc.rowspan:
            for cc in c ..< c + pc.colspan:
              if rr != i or cc != c: taken.add (rr, cc)
        w = max(w, c + pc.colspan)
        h = max(h, i + pc.rowspan)
        c += pc.colspan
  else:
    let rows = parseTsv(text)
    for i, row in rows:
      for j, field in row:
        let old = s.cellAt(br + i, bc + j)
        v.setCellRaw(v.wb.active, br + i, bc + j, parseInput(v.wb, field, old), act)
      w = max(w, row.len)
    h = rows.len
  if h == 0 or w == 0: return
  var merges = s.merges.filterIt(not (it.r2 >= br and it.r1 <= br + h - 1 and it.c2 >= bc and it.c1 <= bc + w - 1))
  merges.add newMerges
  s.merges = merges
  act.add Change(sheet: v.wb.active, isMerge: true, mergesBefore: mergesBefore, mergesAfter: merges)
  v.extraRanges.setLen(0)
  v.ar = br; v.ac = bc; v.cr = br + h - 1; v.cc = bc + w - 1
  v.commitAction(act)

proc paste*(v: SheetView, text: string, html = "") =
  ## A paste: ours when the clipboard holds what we copied (Excel: copy mode on).
  if not v.copyRanges(): return
  if clip.active and text == clip.text and clip.cells.len > 0: v.pasteInternal()
  else:
    v.endCopyMode()
    v.pasteExternal(text, html)
  v.applyExtent()
  v.refreshFormulaBar()
  v.showSelection()
  v.showCopyAnts()
  v.requestDraw()
