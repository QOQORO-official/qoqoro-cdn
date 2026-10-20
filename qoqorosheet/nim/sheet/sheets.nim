## Sheet tabs: Luckysheet's sheet menu (#luckysheet-rightclick-sheet-menu,
## sheetmanage.js / sheetBar.js) with Excel's rules, included into view.nim.
## Rename in place (double-click), delete, copy, tab colour, hide / unhide,
## move left / right, and the ☰ list of every sheet. A renamed sheet's
## references follow it; a deleted one's become #REF!. Like Excel, deleting
## or moving a sheet cannot be undone (the undo history is cleared).

proc visibleCount(v: SheetView): int =
  for s in v.wb.sheets:
    if not s.hidden: inc result

proc forgetHistory(v: SheetView) =
  v.undo.setLen(0); v.redo.setLen(0)

proc validSheetName(v: SheetView, name: string, skip = -1): string =
  ## "" when fine, else why not (Excel's rules).
  if name.strip.len == 0: return "A sheet name cannot be empty."
  if name.len > 31: return "A sheet name can have at most 31 characters."
  for ch in name:
    if ch in {'\\', '/', '?', '*', '[', ']', ':'}: return "A sheet name cannot contain \\ / ? * [ ] :"
  if name[0] == '\'' or name[^1] == '\'': return "A sheet name cannot begin or end with an apostrophe."
  for i, s in v.wb.sheets:
    if i != skip and cmpIgnoreCase(s.name, name) == 0: return "That name is already taken. Try a different one."
  ""

proc renameSheet*(v: SheetView, index: int, newName: string): bool =
  let name = newName.strip
  let why = v.validSheetName(name, index)
  if why.len > 0:
    v.tooltipInfo(why, ""); return false
  let old = v.wb.sheets[index].name
  if old == name: return true
  for sh in v.wb.sheets:
    for k, cell in sh.cells.mpairs:
      if cell.formula.len > 0:
        let f = renameSheetRefs(cell.formula, old, name)
        if f != cell.formula: cell.setFormula(f)
  v.wb.sheets[index].name = name
  if v.onChange != nil: v.onChange()
  true

proc beginTabRename(v: SheetView, index: int) =
  ## Luckysheet's in-place rename: the tab's name becomes editable.
  let tab = byId("luckysheet-sheets-item" & $index)
  if tab.isNil: return
  let name = tab.query(".luckysheet-sheets-item-name")
  name.setAttribute("contenteditable", "true")
  name.addClass("luckysheet-mousedown-cancel")
  name.focus()
  let sel = window.invoke("getSelection").toNode
  if not sel.isNil: sel.call("selectAllChildren", name)
  var done = false
  proc finish(commit: bool) =
    if done: return
    done = true
    name.setAttribute("contenteditable", "false")
    if commit: discard v.renameSheet(index, name.getStr("textContent"))
    # rebuilt after this event: the tab being left (blur) is still in the page
    setTimeout(0, proc() =
      v.rebuildTabs()
      v.editor.focus(true))
  name.on("keydown", proc(e: Event) =
    e.stopPropagation()
    if e.key == "Enter": e.preventDefault(); finish(true)
    elif e.key == "Escape": e.preventDefault(); finish(false))
  name.on("blur", proc(e: Event) = finish(true))

proc deleteSheet*(v: SheetView, index: int) =
  if v.visibleCount() <= 1:
    v.tooltipInfo("A workbook must contain at least one visible worksheet.", ""); return
  if not window.invoke("confirm", "The sheet will be deleted permanently. Do you want to continue?").toBool: return
  let gone = v.wb.sheets[index].name
  v.wb.sheets.delete(index)
  for sh in v.wb.sheets:
    for k, cell in sh.cells.mpairs:
      if cell.formula.len > 0:
        let f = renameSheetRefs(cell.formula, gone, "")
        if f != cell.formula: cell.setFormula(f)
  recalc(v.wb)
  v.forgetHistory()
  var next = min(index, v.wb.sheets.high)
  while v.wb.sheets[next].hidden and next > 0: dec next
  if v.onChange != nil: v.onChange()
  v.activate(next)

proc copySheet*(v: SheetView, index: int) =
  ## Excel's Move or Copy → copy: "Name (2)" after it.
  let src = v.wb.sheets[index]
  var n = 2
  while v.wb.sheetNamed(src.name & " (" & $n & ")") != nil: inc n
  let s = Sheet(name: (src.name & " (" & $n & ")").substr(0, 30), cells: src.cells, colWidths: src.colWidths, rowHeights: src.rowHeights,
    maxRow: src.maxRow, maxCol: src.maxCol, merges: src.merges, rowsTotal: src.rowsTotal, colsTotal: src.colsTotal,
    hiddenRows: src.hiddenRows, hiddenCols: src.hiddenCols, tabColor: src.tabColor)
  v.wb.sheets.insert(s, index + 1)
  recalc(v.wb)
  v.forgetHistory()
  if v.onChange != nil: v.onChange()
  v.activate(index + 1)

proc moveSheet*(v: SheetView, index, dir: int) =
  let to = index + dir
  if to < 0 or to > v.wb.sheets.high: return
  swap(v.wb.sheets[index], v.wb.sheets[to])
  v.forgetHistory()
  if v.wb.active == index: v.wb.active = to
  elif v.wb.active == to: v.wb.active = index
  if v.onChange != nil: v.onChange()
  v.rebuildTabs()

proc hideSheet*(v: SheetView, index: int) =
  if v.visibleCount() <= 1:
    v.tooltipInfo("A workbook must contain at least one visible worksheet.", ""); return
  v.wb.sheets[index].hidden = true
  if v.onChange != nil: v.onChange()
  if v.wb.active == index:
    var next = index
    while next < v.wb.sheets.high and v.wb.sheets[next].hidden: inc next
    while v.wb.sheets[next].hidden and next > 0: dec next
    v.activate(next)
  else: v.rebuildTabs()

proc closeSheetMenus(v: SheetView) =
  for id in ["luckysheet-rightclick-sheet-menu", "luckysheetsheetconfigcolor_sub"]:
    let m = byId(id)
    if not m.isNil: m.style("display", "none")

proc showSheetMenu*(v: SheetView, index: int, x, y: float64) =
  let menu = byId("luckysheet-rightclick-sheet-menu")
  if menu.isNil: return
  v.menuSheet = index
  var hiddenAny = false
  for s in v.wb.sheets:
    if s.hidden: hiddenAny = true
  byId("luckysheetsheetconfigshow").toggleClass("qs-disabled", not hiddenAny)
  byId("luckysheetsheetconfigmoveleft").toggleClass("qs-disabled", index == 0)
  byId("luckysheetsheetconfigmoveright").toggleClass("qs-disabled", index == v.wb.sheets.high)
  menu.style("display", "block")
  let h = menu.getNum("offsetHeight")
  menu.style("left", px(x))
  menu.style("top", px(max(0.0, y - h)))       # above the tab, as Luckysheet opens it

proc bindSheetMenu(v: SheetView) =
  let menu = byId("luckysheet-rightclick-sheet-menu")
  if menu.isNil: return
  let css = el("style")
  css.setProp("textContent", "#luckysheet-rightclick-sheet-menu .qs-disabled{opacity:.4;pointer-events:none}")
  discard document.query("head").add css
  proc item(id: string, action: proc(index: int, n: Node)) =
    let n = byId(id)
    if n.isNil: return
    n.on("click", proc(e: Event) =
      let i = v.menuSheet
      if id != "luckysheetsheetconfigcolor": v.closeSheetMenus()
      action(i, n))
  item("luckysheetsheetconfigdelete", proc(i: int, n: Node) = v.deleteSheet(i))
  item("luckysheetsheetconfigcopy", proc(i: int, n: Node) = v.copySheet(i))
  item("luckysheetsheetconfigrename", proc(i: int, n: Node) = v.beginTabRename(i))
  item("luckysheetsheetconfighide", proc(i: int, n: Node) = v.hideSheet(i))
  item("luckysheetsheetconfigmoveleft", proc(i: int, n: Node) = v.moveSheet(i, -1))
  item("luckysheetsheetconfigmoveright", proc(i: int, n: Node) = v.moveSheet(i, 1))
  item("luckysheetsheetconfigcolor", proc(i: int, n: Node) =
    v.closeSheetMenus()
    v.openPalette(n, proc(c: string) =
      v.wb.sheets[i].tabColor = c
      if v.onChange != nil: v.onChange()
      v.rebuildTabs()))
  item("luckysheetsheetconfigshow", proc(i: int, n: Node) =
    var items: seq[(string, string, bool)]
    for k, s in v.wb.sheets:
      if s.hidden: items.add (s.name, $k, false)
    v.openRibbonMenu(n, items, proc(value: string) =
      let k = parseInt(value)
      v.wb.sheets[k].hidden = false
      if v.onChange != nil: v.onChange()
      v.activate(k)))
  # ☰: every visible sheet, to go to
  let list = byId("luckysheet-sheets-m")
  if not list.isNil:
    list.on("click", proc(e: Event) =
      var items: seq[(string, string, bool)]
      for k, s in v.wb.sheets:
        if not s.hidden: items.add (s.name, $k, k == v.wb.active)
      v.openRibbonMenu(list, items, proc(value: string) = v.activate(parseInt(value)))
      # open upwards: the list sits at the bottom
      if not v.ribbonMenu.isNil:
        let r = list.rect
        v.ribbonMenu.style("top", px(max(0.0, r.top - v.ribbonMenu.getNum("offsetHeight")))))
  document.on("mousedown", proc(e: Event) =
    if not e.target.matches("#luckysheet-rightclick-sheet-menu, #luckysheet-rightclick-sheet-menu *"): v.closeSheetMenus())
