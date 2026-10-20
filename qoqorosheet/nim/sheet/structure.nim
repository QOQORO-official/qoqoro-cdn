## Rows and columns — insert, delete, hide, show, size —, delete cells, sort,
## and the right-click menus, included into view.nim. Luckysheet's menu
## (#luckysheet-rightclick-menu, rowColumnOperation.js) with Excel's rules:
## references follow inserts and deletes everywhere in the workbook (deleted
## ones become #REF!), Insert adds as many rows / columns as are selected,
## sort orders numbers < text < booleans < errors with blanks last.

# ------------------------------------------------------------ undo states --

proc stateOf(s: Sheet): SheetState =
  SheetState(cells: s.cells, merges: s.merges, colWidths: s.colWidths, rowHeights: s.rowHeights,
    hiddenRows: s.hiddenRows, hiddenCols: s.hiddenCols, rowsTotal: s.rowsTotal, colsTotal: s.colsTotal,
    frozenRows: s.frozenRows, frozenCols: s.frozenCols, filter: s.filter, filterRows: s.filterRows,
    condRules: s.condRules, validations: s.validations, notes: s.notes, links: s.links, pictures: s.pictures,
    protected: s.protected, protectHash: s.protectHash)

proc restoreState(s: Sheet, st: SheetState) =
  s.cells = st.cells; s.merges = st.merges; s.colWidths = st.colWidths; s.rowHeights = st.rowHeights
  s.hiddenRows = st.hiddenRows; s.hiddenCols = st.hiddenCols; s.rowsTotal = st.rowsTotal; s.colsTotal = st.colsTotal
  s.frozenRows = st.frozenRows; s.frozenCols = st.frozenCols; s.filter = st.filter; s.filterRows = st.filterRows
  s.condRules = st.condRules; s.validations = st.validations; s.notes = st.notes; s.links = st.links
  s.pictures = st.pictures; s.protected = st.protected; s.protectHash = st.protectHash
  s.recomputeUsed()

proc remapExtras(s: Sheet, rows: bool, f: proc(i: int): int, span: proc(a, b: int): (int, int)) =
  ## Notes, links, rule / validation / filter ranges after lines move: `f` maps
  ## an index (-1 deleted), `span` a range's ends (b < a: gone).
  for t in [addr s.notes, addr s.links]:
    var moved = initTable[int64, string]()
    for k, text in t[]:
      let (r, c) = (rowOf(k), colOf(k))
      let i = f(if rows: r else: c)
      if i >= 0: moved[if rows: key(i, c) else: key(r, i)] = text
    t[] = moved
  template remapRange(x: untyped): bool =
    let (p, q) = if rows: span(x.r1, x.r2) else: span(x.c1, x.c2)
    if rows: (x.r1 = p; x.r2 = q) else: (x.c1 = p; x.c2 = q)
    q >= p
  var rules: seq[CondRule]
  for x0 in s.condRules:
    var x = x0
    if remapRange(x): rules.add x
  s.condRules = rules
  var dvs: seq[Validation]
  for x0 in s.validations:
    var x = x0
    if remapRange(x): dvs.add x
  s.validations = dvs
  if s.filter.on:
    var fl = s.filter
    if not remapRange(fl) or (rows and f(s.filter.r1) < 0): s.filter = AutoFilter(); s.filterRows.clear()
    else:
      if not rows:
        var hid = initTable[int, seq[string]]()
        for c, vals in fl.hidden:
          if f(c) >= 0: hid[f(c)] = vals
        fl.hidden = hid
      s.filter = fl
  if rows:
    var fr = initHashSet[int]()
    for r in s.filterRows:
      if f(r) >= 0: fr.incl f(r)
    s.filterRows = fr

proc structural(v: SheetView, body: proc(), guard = true) =
  ## A change of the sheet's structure, undoable as one step (every sheet's
  ## state before and after: references elsewhere change too). A protected
  ## sheet refuses it (Excel), unless `guard` is off (freeze, filter).
  if guard and v.sheet.protected:
    v.protectedMessage(); return
  let before = v.wb.sheets.mapIt(stateOf(it))
  body()
  for s in v.wb.sheets: s.recomputeUsed()
  let after = v.wb.sheets.mapIt(stateOf(it))
  v.commitAction(@[Change(sheet: v.wb.active, snapshot: true, statesBefore: before, statesAfter: after)])
  v.removeDropIcon()
  v.applyExtent()
  v.refreshFormulaBar(); v.showSelection(); v.requestDraw()

proc adjustAll(v: SheetView, target: Sheet, rows: bool, at, n: int, band = (-1, -1)) =
  ## Every formula of the workbook after a change of `target`'s lines.
  for sh in v.wb.sheets:
    for k, cell in sh.cells.mpairs:
      if cell.formula.len == 0: continue
      let f = adjustFormula(cell.formula, sh.name, target.name, rows, at, n, band)
      if f != cell.formula: cell.setFormula(f)

proc shiftIndex(i, at, n: int): int = (if i >= at: i + n else: i)

proc insertLines*(v: SheetView, rows: bool, at, n: int) =
  ## Excel's Insert: n rows (columns) before `at`.
  let s = v.sheet
  v.structural(proc() =
    var cells = initTable[int64, Cell]()
    for k, cell in s.cells:
      let (r, c) = (rowOf(k), colOf(k))
      let (nr, nc) = if rows: (shiftIndex(r, at, n), c) else: (r, shiftIndex(c, at, n))
      if nr < MaxRows and nc < MaxCols: cells[key(nr, nc)] = cell
    s.cells = cells
    if rows:
      var h = initTable[int, float64]()
      for r, x in s.rowHeights: h[shiftIndex(r, at, n)] = x
      s.rowHeights = h
      var hid = initHashSet[int]()
      for r in s.hiddenRows: hid.incl shiftIndex(r, at, n)
      s.hiddenRows = hid
      s.rowsTotal = s.rowCount + n
    else:
      var w = initTable[int, float64]()
      for c, x in s.colWidths: w[shiftIndex(c, at, n)] = x
      s.colWidths = w
      var hid = initHashSet[int]()
      for c in s.hiddenCols: hid.incl shiftIndex(c, at, n)
      s.hiddenCols = hid
      s.colsTotal = s.colCount + n
    var merges: seq[Merge]
    for m in s.merges:
      var x = m
      if rows:
        if x.r1 >= at: x.r1 += n; x.r2 += n
        elif x.r2 >= at: x.r2 += n                     # spans the insert: grows
      else:
        if x.c1 >= at: x.c1 += n; x.c2 += n
        elif x.c2 >= at: x.c2 += n
      merges.add x
    s.merges = merges
    s.remapExtras(rows, proc(i: int): int = shiftIndex(i, at, n),
      proc(p, q: int): (int, int) = (shiftIndex(p, at, n), (if q >= at: q + n else: q)))
    v.adjustAll(s, rows, at, n))

proc deleteLines*(v: SheetView, rows: bool, a, b: int) =
  ## Excel's Delete: rows (columns) a..b; the sheet keeps its size.
  let s = v.sheet
  let n = b - a + 1
  proc keep(i: int): int = (if i < a: i elif i > b: i - n else: -1)
  v.structural(proc() =
    var cells = initTable[int64, Cell]()
    for k, cell in s.cells:
      let (r, c) = (rowOf(k), colOf(k))
      let i = keep(if rows: r else: c)
      if i < 0: continue
      cells[if rows: key(i, c) else: key(r, i)] = cell
    s.cells = cells
    if rows:
      var h = initTable[int, float64]()
      for r, x in s.rowHeights:
        if keep(r) >= 0: h[keep(r)] = x
      s.rowHeights = h
      var hid = initHashSet[int]()
      for r in s.hiddenRows:
        if keep(r) >= 0: hid.incl keep(r)
      s.hiddenRows = hid
    else:
      var w = initTable[int, float64]()
      for c, x in s.colWidths:
        if keep(c) >= 0: w[keep(c)] = x
      s.colWidths = w
      var hid = initHashSet[int]()
      for c in s.hiddenCols:
        if keep(c) >= 0: hid.incl keep(c)
      s.hiddenCols = hid
    var merges: seq[Merge]
    for m in s.merges:
      let (p, q) = if rows: (m.r1, m.r2) else: (m.c1, m.c2)
      if p >= a and q <= b: continue                     # deleted with its lines
      let np = if p < a: p elif p > b: p - n else: a
      let nq = if q < a: q elif q > b: q - n else: a - 1
      var x = m
      if rows: x.r1 = np; x.r2 = nq else: x.c1 = np; x.c2 = nq
      if x.r2 > x.r1 or x.c2 > x.c1: merges.add x
    s.merges = merges
    s.remapExtras(rows, keep, proc(p, q: int): (int, int) =
      ((if p < a: p elif p > b: p - n else: a), (if q < a: q elif q > b: q - n else: a - 1)))
    v.adjustAll(s, rows, a, -n))

proc deleteCells*(v: SheetView, shiftUp: bool) =
  ## Delete cells, shift up (left): only the selection's columns (rows) move.
  let (r1, c1, r2, c2) = v.selRect()
  let s = v.sheet
  if s.hasPartMerge(r1, c1, if shiftUp: s.rowCount - 1 else: r2, if shiftUp: c2 else: s.colCount - 1):
    v.tooltipInfo("Cannot perform this operation on merged cells", ""); return
  v.structural(proc() =
    var cells = initTable[int64, Cell]()
    for k, cell in s.cells:
      var (r, c) = (rowOf(k), colOf(k))
      if shiftUp and c >= c1 and c <= c2:
        if r >= r1 and r <= r2: continue
        if r > r2: r -= r2 - r1 + 1
      elif not shiftUp and r >= r1 and r <= r2:
        if c >= c1 and c <= c2: continue
        if c > c2: c -= c2 - c1 + 1
      cells[key(r, c)] = cell
    s.cells = cells
    if shiftUp: v.adjustAll(s, true, r1, -(r2 - r1 + 1), (c1, c2))
    else: v.adjustAll(s, false, c1, -(c2 - c1 + 1), (r1, r2)))

proc setHidden*(v: SheetView, rows: bool, a, b: int, hide: bool) =
  let s = v.sheet
  v.structural(proc() =
    for i in a .. b:
      if rows:
        if hide: s.hiddenRows.incl i else: s.hiddenRows.excl i
      else:
        if hide: s.hiddenCols.incl i else: s.hiddenCols.excl i)

proc setLineSize*(v: SheetView, rows: bool, a, b: int, size: float64) =
  let s = v.sheet
  v.structural(proc() =
    for i in a .. b:
      if rows: s.rowHeights[i] = size else: s.colWidths[i] = size)

# ------------------------------------------------------------------- sort --

proc currentRegion(s: Sheet, r, c: int): (int, int, int, int) =
  ## Excel's current region: the block of filled cells around (r, c).
  var (a, b, e, f) = (r, c, r, c)
  var grew = true
  proc filled(rr, cc: int): bool = rr >= 0 and cc >= 0 and s.hasCell(rr, cc) and s.cellAt(rr, cc).value.kind != vkEmpty
  while grew:
    grew = false
    for cc in b - 1 .. f + 1:
      if filled(a - 1, cc): dec a; grew = true; break
    for cc in b - 1 .. f + 1:
      if filled(e + 1, cc): inc e; grew = true; break
    for rr in a - 1 .. e + 1:
      if filled(rr, b - 1): dec b; grew = true; break
    for rr in a - 1 .. e + 1:
      if filled(rr, f + 1): inc f; grew = true; break
  (max(a, 0), max(b, 0), e, f)

proc sortRank(v: Value): int =
  case v.kind
  of vkNum: 0
  of vkStr: (if v.str.len == 0: 9 else: 1)
  of vkBool: 2
  of vkErr: 3
  else: 9                                            # blanks: last either way

proc compareValues(a, b: Value): int =
  let ra = sortRank(a)
  let rb = sortRank(b)
  if ra != rb: return cmp(ra, rb)
  case a.kind
  of vkNum: cmp(a.num, b.num)
  of vkStr: cmp(a.str.toLowerAscii, b.str.toLowerAscii)
  of vkBool: cmp(ord(a.b), ord(b.b))
  else: 0

proc sortBlock(v: SheetView, top, r2, c1, c2, key: int, descending: bool) =
  ## rows top..r2 of columns c1..c2 ordered by column `key` (Excel's order)
  let s = v.sheet
  var order = toSeq(top .. r2)
  order.sort(proc(x, y: int): int =
    let a = s.cellAt(x, key).value
    let b = s.cellAt(y, key).value
    let ra = sortRank(a)
    let rb = sortRank(b)
    if ra == 9 or rb == 9: return cmp(ra, rb)        # blanks stay last
    result = compareValues(a, b)
    if descending: result = -result)
  var act: Action
  var rowsData: seq[seq[Cell]]
  for r in order:
    var row: seq[Cell]
    for c in c1 .. c2: row.add s.cellAt(r, c)
    rowsData.add row
  for i, r in order:
    let dest = top + i
    for j, c in toSeq(c1 .. c2):
      var cell = rowsData[i][j]
      if cell.formula.len > 0 and dest != r: cell.setFormula(shiftFormula(cell.formula, dest - r, 0))
      v.setCellRaw(v.wb.active, dest, c, cell, act)
  v.commitAction(act)

proc sortSelection*(v: SheetView, descending: bool) =
  ## Sort A→Z / Z→A by the active cell's column (Excel): a lone cell sorts its
  ## current region; a first row of text over numbers is taken as headers.
  let s = v.sheet
  var (r1, c1, r2, c2) = v.selRect()
  if r1 == r2 and c1 == c2: (r1, c1, r2, c2) = s.currentRegion(v.ar, v.ac)
  r2 = min(r2, max(s.maxRow - 1, r1)); c2 = min(c2, max(s.maxCol - 1, c1))
  if r2 <= r1: return
  if s.hasMerge(r1, c1, r2, c2):
    v.tooltipInfo("Cannot perform this operation on merged cells", ""); return
  let key = clamp(v.ac, c1, c2)
  var top = r1
  block header:
    let h = s.cellAt(r1, key).value
    let below = s.cellAt(r1 + 1, key).value
    if h.kind == vkStr and below.kind in {vkNum, vkBool}: top = r1 + 1
  if r2 <= top: return
  v.sortBlock(top, r2, c1, c2, key, descending)
  v.extraRanges.setLen(0)
  v.ar = r1; v.ac = c1; v.cr = r2; v.cc = c2
  v.refreshFormulaBar(); v.showSelection(); v.requestDraw()

# ------------------------------------------------------------ the menus ----

proc hideContextMenu(v: SheetView) =
  for id in ["luckysheet-rightclick-menu", "luckysheetCellsHandleDel_sub"]:
    let m = byId(id)
    if not m.isNil: m.style("display", "none")

proc placeMenu(menu: Node, x, y: float64) =
  ## showrightclickmenu: at the pointer, flipped when it would leave the window.
  menu.style("display", "block")
  let w = menu.getNum("offsetWidth")
  let h = menu.getNum("offsetHeight")
  var left = x
  var top = y
  if left + w > window.getNum("innerWidth"): left = max(0.0, x - w)
  if top + h > window.getNum("innerHeight"): top = max(0.0, y - h)
  menu.style("left", px(left)); menu.style("top", px(top))

proc menuMode(v: SheetView, e: Event): string =
  ## "column" / "row" for a header or a whole column / row selection, else "cell".
  if e.target.matches("#luckysheet-cols-h-c, #luckysheet-cols-h-c *"): return "column"
  if e.target.matches("#luckysheet-rows-h, #luckysheet-rows-h *"): return "row"
  let (r1, c1, r2, c2) = v.selRect()
  if r1 == 0 and r2 >= v.sheet.rowCount - 1: return "column"
  if c1 == 0 and c2 >= v.sheet.colCount - 1: return "row"
  "cell"

proc showContextMenu(v: SheetView, e: Event) =
  let menu = byId("luckysheet-rightclick-menu")
  if menu.isNil: return
  e.preventDefault()
  if v.editing: v.endEdit(true)
  let mode = v.menuMode(e)
  v.contextMode = mode
  let s = v.sheet
  let (r1, c1, r2, c2) = v.selRect()
  proc show(id: string, on: bool) =
    let n = byId(id)
    if not n.isNil: n.style("display", if on: "block" else: "none")
  show("luckysheetcopyfor", false)                       # Copy as: not here
  show("luckysheet-cols-rows-handleincell", mode == "cell")
  show("luckysheet-cols-rows-add", mode != "cell")
  show("luckysheet-cols-rows-shift", mode != "row")
  show("luckysheet-cols-rows-data", true)
  for n in menu.queryAll("#luckysheet-cols-rows-data > .luckysheet-cols-menuitem"):
    let id = n.getStr("id")
    n.style("display", if id in ["luckysheet-delete-text", "luckysheetfilter", "luckysheetInsertImage", "luckysheetInsertLink",
      "luckysheetDataVerification", "qs-menu-note"]: "block" else: "none")
  let noteItem = byId("qs-menu-note")
  if not noteItem.isNil:
    noteItem.query(".luckysheet-cols-menuitem-content").setProp("textContent",
      if s.notes.hasKey(key(v.ar, v.ac)): "Edit note" else: "Insert note")
  for n in menu.queryAll(".luckysheet-menuseparator"): n.style("display", "block")
  if mode != "cell":
    let col = mode == "column"
    for n in menu.queryAll(".luckysheet-cols-rows-shift-word"): n.setProp("textContent", if col: "Column" else: "Row")
    for n in menu.queryAll(".luckysheet-cols-rows-shift-size"): n.setProp("textContent", if col: "Width" else: "Height")
    for n in menu.queryAll(".luckysheet-cols-rows-shift-left"): n.setProp("textContent", if col: "Left" else: "Top")
    for n in menu.queryAll(".luckysheet-cols-rows-shift-right"): n.setProp("textContent", if col: "Right" else: "Bottom")
    # Excel inserts as many as are selected
    let count = if col: c2 - c1 + 1 else: r2 - r1 + 1
    for id in ["luckysheet-top-left-add-selected", "luckysheet-bottom-right-add-selected"]:
      let inp = byId(id).query("input")
      if not inp.isNil: inp.setProp("value", $min(count, 100))
    # the size box: the selection's common size, else empty
    var size = if col: s.colWidth(c1) else: s.rowHeight(r1)
    let (lo, hi) = if col: (c1, c2) else: (r1, r2)
    for i in lo .. hi:
      if (if col: s.colWidth(i) else: s.rowHeight(i)) != size: size = -1; break
    let inp = byId("luckysheet-column-row-width-selected").query("input")
    if not inp.isNil: inp.setProp("value", if size >= 0: $int(round(size)) else: "")
  placeMenu(menu, e.clientX, e.clientY)

proc menuLines(v: SheetView): (bool, int, int) =
  let (r1, c1, r2, c2) = v.selRect()
  if v.contextMode == "column": (false, c1, c2) else: (true, r1, r2)

proc menuNumber(id: string): int =
  let inp = byId(id).query("input")
  try: parseInt(inp.value.strip) except ValueError: -1

proc bindContextMenu(v: SheetView) =
  let menu = byId("luckysheet-rightclick-menu")
  if menu.isNil: return
  v.gridContainer.on("contextmenu", proc(e: Event) =
    if e.target.matches(".luckysheet-cell-main, .luckysheet-cell-main *, #luckysheet-cols-h-c, #luckysheet-cols-h-c *, #luckysheet-rows-h, #luckysheet-rows-h *, #luckysheetTableContent"):
      v.showContextMenu(e)
    else: e.preventDefault())
  document.on("mousedown", proc(e: Event) =
    if not e.target.matches("#luckysheet-rightclick-menu, #luckysheet-rightclick-menu *, #luckysheetCellsHandleDel_sub, #luckysheetCellsHandleDel_sub *"):
      v.hideContextMenu())
  proc item(id: string, action: proc(e: Event)) =
    let n = byId(id)
    if n.isNil: return
    n.on("click", proc(e: Event) =
      if e.target.matches("input"): return
      v.hideContextMenu()
      action(e)
      v.editor.focus(true))
  item("luckysheet-copy-btn", proc(e: Event) =
    if not v.copyRanges(): return
    let (text, _) = v.copySelection()
    clipboardWrite(text))
  item("luckysheet-copy-paste", proc(e: Event) =
    if clip.active: (v.pasting = true; v.paste(clip.text); v.pasting = false)
    else: v.tooltipInfo("Use Ctrl+V to paste from the clipboard", ""))
  item("luckysheetColsRowsHandleAdd_row", proc(e: Event) =
    let (r1, _, r2, _) = v.selRect()
    v.insertLines(true, r1, r2 - r1 + 1))
  item("luckysheetColsRowsHandleAdd_column", proc(e: Event) =
    let (_, c1, _, c2) = v.selRect()
    v.insertLines(false, c1, c2 - c1 + 1))
  item("luckysheet-delRows", proc(e: Event) =
    let (r1, _, r2, _) = v.selRect()
    v.deleteLines(true, r1, r2))
  item("luckysheet-delCols", proc(e: Event) =
    let (_, c1, _, c2) = v.selRect()
    v.deleteLines(false, c1, c2))
  let delCell = byId("luckysheetCellsHandleDel")
  if not delCell.isNil:
    delCell.on("mouseenter", proc(e: Event) =
      let sub = byId("luckysheetCellsHandleDel_sub")
      if sub.isNil: return
      let r = delCell.rect
      placeMenu(sub, r.left + r.width, r.top))
  item("luckysheet-delCellsMoveUp", proc(e: Event) = v.deleteCells(true))
  item("luckysheet-delCellsMoveLeft", proc(e: Event) = v.deleteCells(false))
  proc addLines(before: bool) =
    let id = if before: "luckysheet-top-left-add-selected" else: "luckysheet-bottom-right-add-selected"
    let n = menuNumber(id)
    if n < 1 or n > 100:
      v.tooltipInfo("The increase range is limited to 1-100", ""); return
    let (rows, a, b) = v.menuLines()
    v.insertLines(rows, if before: a else: b + 1, n)
  item("luckysheet-top-left-add-selected", proc(e: Event) = addLines(true))
  item("luckysheet-bottom-right-add-selected", proc(e: Event) = addLines(false))
  for id_1 in ["luckysheet-top-left-add-selected", "luckysheet-bottom-right-add-selected"]:
    let id_0 = id_1
    closureScope:
      let id = id_0
      let inp = byId(id).query("input")
      if not inp.isNil:
        let before = id == "luckysheet-top-left-add-selected"
        inp.on("keydown", proc(e: Event) =
          if e.key == "Enter": e.preventDefault(); v.hideContextMenu(); addLines(before))
  item("luckysheet-del-selected", proc(e: Event) =
    let (rows, a, b) = v.menuLines()
    v.deleteLines(rows, a, b))
  item("luckysheet-hide-selected", proc(e: Event) =
    let (rows, a, b) = v.menuLines()
    v.setHidden(rows, a, b, true))
  item("luckysheet-show-selected", proc(e: Event) =
    let (rows, a, b) = v.menuLines()
    v.setHidden(rows, a, b, false))
  proc applySize() =
    let inp = byId("luckysheet-column-row-width-selected").query("input")
    let x = try: parseFloat(inp.value.strip) except ValueError: -1.0
    if x < 0 or x > 2038:
      v.tooltipInfo("Please enter a number between 0 and 2038", ""); return
    let (rows, a, b) = v.menuLines()
    v.setLineSize(rows, a, b, x)
  item("luckysheet-column-row-width-selected", proc(e: Event) = applySize())
  let sizeInput = byId("luckysheet-column-row-width-selected").query("input")
  if not sizeInput.isNil:
    sizeInput.on("keydown", proc(e: Event) =
      if e.key == "Enter": e.preventDefault(); v.hideContextMenu(); applySize())
  item("luckysheetorderbyasc", proc(e: Event) = v.sortSelection(false))
  item("luckysheetorderbydesc", proc(e: Event) = v.sortSelection(true))
  item("luckysheet-delete-text", proc(e: Event) = v.clearSelection())
  item("luckysheetfilter", proc(e: Event) = v.toggleFilter())
  item("luckysheetInsertImage", proc(e: Event) = v.insertPicture())
  item("luckysheetInsertLink", proc(e: Event) = v.linkDialog())
  item("luckysheetDataVerification", proc(e: Event) = v.validationDialog())
  block:
    # Insert note (Excel's context menu)
    let data = byId("luckysheet-cols-rows-data")
    if not data.isNil:
      let n = el("div", "luckysheet-cols-menuitem luckysheet-mousedown-cancel")
      n.setAttribute("id", "qs-menu-note")
      n.setProp("innerHTML", "<div class=\"luckysheet-cols-menuitem-content luckysheet-mousedown-cancel\">Insert note</div>")
      discard data.add n
  item("qs-menu-note", proc(e: Event) = v.editNote())
