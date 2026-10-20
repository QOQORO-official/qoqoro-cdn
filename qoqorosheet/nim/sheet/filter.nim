## AutoFilter, included into view.nim: Luckysheet's filter (filter.js) — the
## purple buttons on the header row (.luckysheet-filter-options) and its menu
## (#luckysheet-filter-menu: sort, the values with their counts, search,
## Check all / Clear / Inverse, Confirm / Cancel / Clear filter) — with Excel's
## rules: the rows a column's unticked values are on hide; sorting sorts the
## rows under the header.

const Blanks = "(Blanks)"

proc filterText(v: SheetView, r, c: int): string =
  let t = v.wb.displayText(v.sheet.cellAt(r, c))
  if t.len == 0: Blanks else: t

proc applyFilter(v: SheetView) =
  ## the rows hidden by every column's unticked values
  let s = v.sheet
  s.filterRows.clear()
  if not s.filter.on: return
  for r in s.filter.r1 + 1 .. s.filter.r2:
    for c, vals in s.filter.hidden:
      if vals.len > 0 and v.filterText(r, c) in vals:
        s.filterRows.incl r; break

proc filterButtonsKey(v: SheetView): string =
  let s = v.sheet
  if not s.filter.on: return ""
  $v.wb.active & "|" & $s.filter.r1 & "," & $s.filter.c1 & "," & $s.filter.r2 & "," & $s.filter.c2 & "|" &
    $s.filter.hidden.len & $v.sbX.getNum("scrollLeft") & "," & $v.sbY.getNum("scrollTop") & "|" & $s.colX(s.filter.c2 + 1) & "," & $s.rowY(s.filter.r1 + 1) &
    "|" & $s.frozenRows & $s.frozenCols & (block:
      var t = ""
      for c, vals in s.filter.hidden: t.add $c & ":" & $vals.len & ";"
      t)

var filterShown = "-"

proc placeFilterButtons(v: SheetView) =
  ## createFilterOptions: the range's outline and one button per column
  let key = v.filterButtonsKey()
  if key == filterShown: return
  filterShown = key
  for id in ["luckysheet-filter-selected-sheet0", "luckysheet-filter-options-sheet0"]:
    let old = byId(id)
    if not old.isNil: old.remove()
  let s = v.sheet
  if not s.filter.on: return
  let f = s.filter
  let (x, y, w, h) = v.rangeBox(f.r1, f.c1, min(f.r2, s.rowCount - 1), f.c2)
  let outline = el("div", "luckysheet-cell-selected luckysheet-filter-selected")
  outline.setAttribute("id", "luckysheet-filter-selected-sheet0")
  outline.setAttribute("style", "left:" & px(x) & ";width:" & px(w) & ";top:" & px(y) & ";height:" & px(h) &
    ";display:block;border-color:#897BFF;z-index:20;background:none;pointer-events:none;")
  discard v.cellMain.add outline
  let box = el("div", "luckysheet-filter-options-c")
  box.setAttribute("id", "luckysheet-filter-options-sheet0")
  for c in f.c1 .. f.c2:
    if s.colHidden(c): continue
    let (bx, by, bw, _) = v.rangeBox(f.r1, c, f.r1, c)
    let active = f.hidden.getOrDefault(c).len > 0
    let b = el("div", "luckysheet-filter-options" & (if active: " luckysheet-filter-options-active" else: ""))
    b.setAttribute("data-cindex", $c)
    b.setAttribute("style", "left:" & px(bx + bw - 19) & ";top:" & px(by + 2) & ";display:block;")
    b.setProp("innerHTML", if active: "<i class=\"fa fa-filter luckysheet-mousedown-cancel\" aria-hidden=\"true\"></i>"
                           else: "<i class=\"fa fa-caret-down luckysheet-mousedown-cancel\" aria-hidden=\"true\"></i>")
    discard box.add b
  discard v.cellMain.add box

proc setFilter(v: SheetView, f: AutoFilter) =
  ## a filter change, undoable (Excel)
  let s = v.sheet
  v.structural(proc() =
    s.filter = f
    v.applyFilter(), guard = false)
  filterShown = "-"
  v.placeOverlays()

proc toggleFilter*(v: SheetView) =
  ## Data > Filter: on for the selection (a lone cell: its current region), or off
  let s = v.sheet
  if s.filter.on:
    v.setFilter(AutoFilter())
    return
  var (r1, c1, r2, c2) = v.selRect()
  if r1 == r2 and c1 == c2: (r1, c1, r2, c2) = s.currentRegion(v.ar, v.ac)
  r2 = min(r2, max(s.maxRow - 1, r1 + 1))
  c2 = min(c2, max(s.maxCol - 1, c1))
  v.setFilter(AutoFilter(on: true, r1: r1, c1: c1, r2: r2, c2: c2))

proc clearFilterChoices(v: SheetView) =
  ## Data > Clear: every row back, the filter stays
  var f = v.sheet.filter
  if not f.on or f.hidden.len == 0: return
  f.hidden.clear()
  v.setFilter(f)

var filterCol = -1

proc closeFilterMenu(v: SheetView) =
  let m = byId("luckysheet-filter-menu")
  if not m.isNil: m.style("display", "none")
  filterCol = -1

proc filterValues(v: SheetView, c: int): seq[(string, int)] =
  ## the column's values (other columns' filters applied), Excel's order
  let s = v.sheet
  let f = s.filter
  var counts = initTable[string, int]()
  var order: seq[(Value, string)]
  for r in f.r1 + 1 .. f.r2:
    var hiddenElsewhere = false
    for cc, vals in f.hidden:
      if cc != c and vals.len > 0 and v.filterText(r, cc) in vals: hiddenElsewhere = true; break
    if hiddenElsewhere: continue
    let t = v.filterText(r, c)
    if not counts.hasKey(t):
      order.add (s.cellAt(r, c).value, t)
      counts[t] = 0
    counts[t] = counts[t] + 1
  order.sort(proc(a, b: (Value, string)): int =
    if a[1] == Blanks: return 1
    if b[1] == Blanks: return -1
    compareValues(a[0], b[0]))
  for (_, t) in order: result.add (t, counts[t])

proc renderFilterList(v: SheetView, c: int, search: string) =
  let list = byId("luckysheet-filter-byvalue-select")
  let hidden = v.sheet.filter.hidden.getOrDefault(c)
  var html = "<div class=\"ListBox luckysheet-mousedown-cancel\" style=\"min-height:100px;max-height:240px;overflow-y:auto;overflow-x:hidden;\"><table cellspacing=\"0\" style=\"width:100%;\" class=\"luckysheet-mousedown-cancel\">"
  for (t, n) in v.filterValues(c):
    let shown = search.len == 0 or search.toLowerAscii in t.toLowerAscii
    let on = t notin hidden
    html.add "<div class=\"textBox luckysheet-mousedown-cancel cf\" data-check=\"" & $on & "\" data-filter=\"" & esc(t) & "\" title=\"" & esc(t) &
      "\" style=\"" & (if shown: "" else: "display:none") & "\"><input class=\"luckysheet-mousedown-cancel\" type=\"checkbox\"" & (if on: " checked=\"checked\"" else: "") &
      "/><label class=\"luckysheet-mousedown-cancel\">" & esc(t) & "</label><span class=\"luckysheet-mousedown-cancel count\">( " & $n & " )</span></div>"
  html.add "</table></div>"
  list.setProp("innerHTML", html)
  for row_1 in list.queryAll(".textBox"):
    let row_0 = row_1
    closureScope:
      let row = row_0
      row.on("click", proc(e: Event) =
        let box = row.query("input")
        if not e.target.matches("input"): box.setProp("checked", not box.checked)
        row.setAttribute("data-check", $box.checked))

proc openFilterMenu(v: SheetView, button: Node) =
  let c = try: parseInt(button.invoke("getAttribute", "data-cindex").toStr) except ValueError: -1
  if c < 0: return
  let menu = byId("luckysheet-filter-menu")
  if menu.isNil: return
  filterCol = c
  # condition and colour filters: not here
  for id in ["luckysheet-filter-orderby-color", "luckysheet-filter-bycondition"]:
    let n = byId(id)
    if not n.isNil: n.style("display", "none")
  for n in menu.queryAll(".luckysheet-filter-bycondition"): n.style("display", "none")
  byId("luckysheet-filter-byvalue-input").setProp("value", "")
  v.renderFilterList(c, "")
  let r = button.rect
  placeMenu(menu, r.left, r.top + 20)

proc filterRowsAll(v: SheetView, mode: string) =
  for row in byId("luckysheet-filter-byvalue-select").queryAll(".textBox"):
    if row.getStr("style").contains("none"): continue
    let box = row.query("input")
    let on = case mode
      of "all": true
      of "clear": false
      else: not box.checked
    box.setProp("checked", on)
    row.setAttribute("data-check", $on)

proc confirmFilter(v: SheetView) =
  let c = filterCol
  if c < 0: return
  var f = v.sheet.filter
  var hidden: seq[string]
  for row in byId("luckysheet-filter-byvalue-select").queryAll(".textBox"):
    if not row.query("input").checked: hidden.add row.invoke("getAttribute", "data-filter").toStr
  if hidden.len > 0: f.hidden[c] = hidden else: f.hidden.del c
  v.closeFilterMenu()
  v.setFilter(f)

proc bindFilter(v: SheetView) =
  v.cellMain.on("mousedown", proc(e: Event) =
    let b = e.target.closest(".luckysheet-filter-options")
    if b.isNil: return
    e.stopPropagation(); e.preventDefault()
    v.openFilterMenu(b), capture = true)
  proc item(id: string, action: proc()) =
    let n = byId(id)
    if not n.isNil: n.on("click", proc(e: Event) = action())
  item("luckysheet-filter-orderby-asc", proc() =
    let f = v.sheet.filter
    let c = filterCol
    v.closeFilterMenu()
    if c >= 0: v.sortBlock(f.r1 + 1, f.r2, f.c1, f.c2, c, false); v.applyFilter(); v.requestDraw())
  item("luckysheet-filter-orderby-desc", proc() =
    let f = v.sheet.filter
    let c = filterCol
    v.closeFilterMenu()
    if c >= 0: v.sortBlock(f.r1 + 1, f.r2, f.c1, f.c2, c, true); v.applyFilter(); v.requestDraw())
  item("luckysheet-filter-byvalue-btn-all", proc() = v.filterRowsAll("all"))
  item("luckysheet-filter-byvalue-btn-clear", proc() = v.filterRowsAll("clear"))
  item("luckysheet-filter-byvalue-btn-contra", proc() = v.filterRowsAll("inverse"))
  item("luckysheet-filter-confirm", proc() = v.confirmFilter())
  item("luckysheet-filter-cancel", proc() = v.closeFilterMenu())
  item("luckysheet-filter-initial", proc() =
    var f = v.sheet.filter
    f.hidden.clear()
    v.closeFilterMenu()
    v.setFilter(f))
  let search = byId("luckysheet-filter-byvalue-input")
  if not search.isNil:
    search.on("input", proc(e: Event) =
      if filterCol < 0: return
      let t = search.value
      for row in byId("luckysheet-filter-byvalue-select").queryAll(".textBox"):
        let shown = t.len == 0 or t.toLowerAscii in row.invoke("getAttribute", "data-filter").toStr.toLowerAscii
        row.style("display", if shown: "" else: "none"))
    search.on("keydown", proc(e: Event) =
      e.stopPropagation()
      if e.key == "Enter": v.confirmFilter())
  document.on("mousedown", proc(e: Event) =
    if filterCol >= 0 and not e.target.matches("#luckysheet-filter-menu, #luckysheet-filter-menu *, .luckysheet-filter-options, .luckysheet-filter-options *"):
      v.closeFilterMenu())
