## QoqoroSheet's grid on the Luckysheet app's own page.
##
## wasm/index.html is Luckysheet's built DOM and stylesheets (see
## nim/PARITY.md §0); this module drives that DOM by its ids, the way
## Luckysheet's controllers do, and draws #luckysheetTableContent the way
## global/draw.js does. Each behaviour notes the Luckysheet source it follows.
##
## Coordinates: "content" x/y run from the sheet's top-left cell (Luckysheet's
## visibledatacolumn / visibledatarow); #luckysheet-cell-main scrolls the
## overlays by the same offsets the two scrollbar strips hold.

import std/[tables, strutils, math, json, sequtils, algorithm, unicode]
import ../host, ../canvas, ../web/qweb
import model, formula, dropcell

proc qg_measure_box(fontId: int32, p: ptr char, len: int32, dst: ptr float64) {.importc, cdecl.}

const
  RowHeaderW* = 46.0        ## Store.rowHeaderWidth
  ColHeaderH* = 20.0        ## Store.columnHeaderHeight
  ScrollBar = 12.0          ## Store.cellMainSrollBarSize
  GridLine = "#dfdfdf"      ## luckysheetdefaultstyle.strokeStyle
  SpaceW = 2.0              ## getCellTextInfo space_width / space_height
  DefaultFontSize = 10.0    ## Store.defaultFontSize (pt)
  ## luckysheetdefaultFont(): locale en fontarray[0] first
  FontStack = "\"Times New Roman\", \"Helvetica Neue\", Helvetica, Arial, \"PingFang SC\", \"Hiragino Sans GB\", \"Heiti SC\",  \"WenQuanYi Micro Hei\", sans-serif"

type
  SheetState = object          ## a sheet's content (structural undo)
    cells: Table[int64, Cell]
    merges: seq[Merge]
    colWidths, rowHeights: Table[int, float64]
    hiddenRows, hiddenCols: HashSet[int]
    rowsTotal, colsTotal: int
    frozenRows, frozenCols: int
    filter: AutoFilter
    filterRows: HashSet[int]
    condRules: seq[CondRule]
    validations: seq[Validation]
    notes, links: Table[int64, string]
    pictures: seq[Picture]
    protected: bool
    protectHash: string

  Change = object
    sheet, r, c: int
    before, after: Cell
    isMerge: bool                     ## a merge change: the sheet's merges before/after
    mergesBefore, mergesAfter: seq[Merge]
    sizeKind: int                     ## 1 a column width, 2 a row height (index in c / r)
    snapshot: bool                    ## a structural change: every sheet's state before / after
    statesBefore, statesAfter: seq[SheetState]
    sizeBefore, sizeAfter: float64    ## NaN: the default size
  Action = seq[Change]

  Range* = object                     ## one entry of Luckysheet's luckysheet_select_save
    r1*, c1*, r2*, c2*: int

  FuncParam = object
    name, detail, example: string
    optional, repeat: bool
  FuncInfo = object             ## one entry of wasm/functions.json
    name, abstract, detail: string
    params: seq[FuncParam]

  DragLoop = ref object      ## one requestAnimationFrame(mouseRender) loop and the mousemove it was started by
    x, y: float64
    alive: bool

  SheetView* = ref object
    wb*: Workbook
    # Luckysheet's DOM
    root*, canvas, cellMain, sbX, sbY, sbXInner, sbYInner, colsHC, rowsH, colsCells, rowHeaderDiv: Node
    rowsHSel, colsHSel, rowsHHover, colsHHover, colsChangeSize, rowsChangeSize, colsMenuBtn: Node
    selBoxs, selMain, selFocus, sheettable, bottomBar, addRowInput: Node
    inputBox, editor*, fxBar, nameBox, sheetBar, gridContainer, gridWindow: Node
    ctx: Node
    rec: Ctx
    dpr: float64
    cellMainW, cellMainH, tableW, tableH: float64   ## Store.cellmainWidth/Height, luckysheetTableContentHW
    infobarH, toolbarH, calcbarH, sheetBarH, statBarH: float64
    scrollX*, scrollY*: float64
    # selection: earlier ranges (Ctrl+click), and the current one: focus (ar, ac), moving corner (cr, cc)
    extraRanges*: seq[Range]
    ar*, ac*, cr*, cc*: int
    editing*: bool
    editFromFormulaBar: bool
    selecting: int           ## 0 none, 1 cells, 4 column headers, 5 row headers, 6 moving cells, 7 fill handle, 8 pointing a formula range
    contextMode: string      ## the open right-click menu: "cell", "row" or "column"
    pasting: bool            ## inside a paste (its commit keeps copy mode)
    editMode: int            ## Excel: 1 Enter mode (typing replaced the cell), 2 Edit mode (F2 / double-click)
    pointActive: bool        ## Point mode: the reference at pointStart ..< pointEnd (UTF-16) follows arrows / the mouse
    pointStart, pointEnd: int
    pointAnchor, pointFocus: (int, int)
    funcs: seq[FuncInfo]
    searchBox, helpBox: Node
    searchItems: seq[string]
    searchActive: int
    searchToken: (int, int)
    helpExpanded: bool       ## the argument help shows its details (off: the signature, like Excel)
    moveIndex, extendIndex: (int, int)   ## luckysheet_cell_selected_move_index / _extend_index
    extendTimer: int32
    selMove, selExtend, dropIcon, dropMenu: Node
    dropCopy, dropApply: (int, int, int, int)    ## luckysheetDropCell.copyRange / applyRange
    dropDir: FillDir
    dropType: FillType
    dropAuto: bool           ## the type came from the drag, not the menu (Excel: a lone number copies)
    resizing: int            ## 0, 1 column, 2 row
    resizeIndex: int
    resizeStart, resizeOrig: float64
    resizePre: float64       ## luckysheet_cols/rows_change_size_start[0]: the left / top of that column / row
    scrollStatus: bool       ## Store.luckysheet_scroll_status: a drag that auto-scrolls
    dragLoops: seq[DragLoop] ## mouseRender loops, one per mousemove (handler.js:2100-3606)
    sizeLine, rowCountShow, colCountShow: Node
    undo, redo: seq[Action]
    framePending: bool
    fileName*: string
    onChange*: proc()        ## after any edit (the host may mark the document dirty)
    hostCall*: proc(name: string, args: JsonNode)   ## page actions (open, save, csv, program…)
    toolbarGroups: seq[seq[Node]]   ## Store.toobarObject.toobarElements
    toolbarWidths: seq[float64]     ## Store.toobarObject.toobarWidths
    moreBtn, toggleTopBar, moreDiv: Node
    sizedW, sizedH: float64         ## the container size sizeAuto last laid out
    extent: (float64, float64)      ## the applied (ch_width, rh_height)
    ribbonMenu: Node         ## the open ribbon dropdown
    ribbonItems: Table[string, seq[string]]   ## tab -> its commands, least important first
    ribbonTab: string
    ribbonOpen: bool         ## expanded: groups stacked with their names (QoWrite / Excel)
    painting: bool           ## Format Painter armed
    painterStyles: seq[seq[int32]]
    lastTextColor, lastFillColor, lastBorder: string
    menuSheet: int           ## the sheet the open tab menu is for
    hideInfobar: bool               ## luckysheetConfigsetting.showinfobar, inverted
    onOpenFile*: proc(file: Node)                   ## the top bar's file input picked a file

proc byId(id: string): Node = document.invoke("getElementById", id).toNode

proc clearFormulaUI(v: SheetView)
proc restoreState(s: Sheet, st: SheetState)
proc renderEditor(v: SheetView, text: string, caret: int)
proc endCopyMode*(v: SheetView)
proc showCopyAnts(v: SheetView)
proc ribbonLayout(v: SheetView)
proc rebuildTabs*(v: SheetView)
proc activate*(v: SheetView, index: int)
proc isFormulaText(v: SheetView): bool
proc refreshToolbar*(v: SheetView)
proc refreshStatus*(v: SheetView)
proc finishPainter(v: SheetView)
proc finishPainterCancel(v: SheetView)
proc applyCss(st: var Style, css: string)
proc activeEd(v: SheetView): Node
proc setCaret(v: SheetView, offset: int)
proc u16Len(s: string): int
proc openChartDialog*(v: SheetView)
proc openProgram*(v: SheetView)
proc openDiagram*(v: SheetView)
proc protectedMessage(v: SheetView)
proc toggleFilter*(v: SheetView)
proc insertPicture*(v: SheetView)
proc linkDialog*(v: SheetView)
proc validationDialog*(v: SheetView)
proc editNote*(v: SheetView)
proc deleteNote(v: SheetView)
proc noteMenu(v: SheetView, anchor: Node)
proc openFind*(v: SheetView, replace = false)
proc openCfMenu(v: SheetView, anchor: Node)
proc pivotDialog*(v: SheetView)
proc refreshPivot*(v: SheetView)
proc protectSheet(v: SheetView)
proc toggleLock(v: SheetView)
proc printSheet(v: SheetView)
proc freezeCommand(v: SheetView, mode: string)
proc setWrap(v: SheetView, on: bool)
proc setRotation(v: SheetView, angle: int)
proc toggleAllNotes(v: SheetView)
proc clearFilterChoices(v: SheetView)
proc manageRules(v: SheetView)
proc rangeLocked(v: SheetView, r1, c1, r2, c2: int): bool
proc refreshProtectButton(v: SheetView)
proc applyAction(v: SheetView, act: Action, forward: bool)
proc tooltipInfo(v: SheetView, title, content: string)
proc entryRejected(v: SheetView, cell: Cell): bool
proc stopAlert(v: SheetView, text: string)
proc placeDvButton(v: SheetView)

proc sheet*(v: SheetView): Sheet = v.wb.sheets[v.wb.active]

# --------------------------------------------------------------- selection --

proc expandToMerges*(s: Sheet, r1, c1, r2, c2: int): (int, int, int, int) =
  ## The smallest range containing r1..r2 x c1..c2 and every merge it touches
  ## (menuButton.mergeMoveMain).
  var (a, b, e, f) = (r1, c1, r2, c2)
  var changed = s.merges.len > 0
  while changed:
    changed = false
    for m in s.merges:
      if m.r2 >= a and m.r1 <= e and m.c2 >= b and m.c1 <= f:
        if m.r1 < a: a = m.r1; changed = true
        if m.c1 < b: b = m.c1; changed = true
        if m.r2 > e: e = m.r2; changed = true
        if m.c2 > f: f = m.c2; changed = true
  (a, b, e, f)

proc selRect*(v: SheetView): (int, int, int, int) =
  v.sheet.expandToMerges(min(v.ar, v.cr), min(v.ac, v.cc), max(v.ar, v.cr), max(v.ac, v.cc))

proc snapAnchor*(v: SheetView) =
  ## The focus of a merged range is its top-left cell (mergeborer).
  let i = v.sheet.mergeAt(v.ar, v.ac)
  if i >= 0:
    let m = v.sheet.merges[i]
    if v.cr == v.ar and v.cc == v.ac: v.cr = m.r1; v.cc = m.c1
    v.ar = m.r1; v.ac = m.c1

proc stepFrom0(s: Sheet, r, c, dr, dc: int): (int, int)

proc stepFrom(s: Sheet, r, c, dr, dc: int): (int, int) =
  ## One cell on, over merged ranges and hidden rows / columns (Excel).
  result = s.stepFrom0(r, c, dr, dc)
  while (dr != 0 and s.rowHidden(result[0]) and result[0] + dr >= 0 and result[0] + dr < s.rowCount) or
        (dc != 0 and s.colHidden(result[1]) and result[1] + dc >= 0 and result[1] + dc < s.colCount):
    result = s.stepFrom0(result[0], result[1], dr, dc)
  # only hidden lines that way: stay (Excel)
  if (dr != 0 and s.rowHidden(result[0])) or (dc != 0 and s.colHidden(result[1])): result = (r, c)

proc stepFrom0(s: Sheet, r, c, dr, dc: int): (int, int) =
  ## One cell on from (r, c), stepping over a merged range as a whole.
  var rr = r
  var cc = c
  let i = s.mergeAt(r, c)
  if i >= 0:
    let m = s.merges[i]
    if dr > 0: rr = m.r2
    if dr < 0: rr = m.r1
    if dc > 0: cc = m.c2
    if dc < 0: cc = m.c1
  (rr + dr, cc + dc)

# ------------------------------------------------------------- display text --

proc displayText*(wb: Workbook, cell: Cell): string =
  let st = wb.styles[cell.style]
  case cell.value.kind
  of vkNum: (if st.numFmt.len > 0: formatNumber(cell.value.num, st.numFmt) else: fmtGeneral(cell.value.num))
  else: toText(cell.value)

proc fontOf(st: Style): string =
  ## Luckysheet's cell font: "<italic> <bold> normal <size>pt <family>".
  (if st.italic: "italic " else: "normal ") & (if st.bold: "bold " else: "normal ") & "normal " &
    $(if st.fontSize > 0: st.fontSize else: DefaultFontSize) & "pt " &
    (if st.font.len > 0: "\"" & st.font & "\", " else: "") & FontStack

proc measureBox(font, text: string): (float64, float64, float64) =
  ## width, actualBoundingBoxAscent, actualBoundingBoxDescent
  var res: array[3, float64]
  let id = strId(font)
  if text.len == 0: qg_measure_box(id, nil, 0, addr res[0])
  else: qg_measure_box(id, unsafeAddr text[0], int32(text.len), addr res[0])
  (res[0], res[1], res[2])

proc measureCell(font, text: string): (float64, float64, float64) =
  ## getMeasureText (getRowlen.js:301-325): under the alphabetic baseline a
  ## text without descenders still takes the descent of "gjpqy".
  result = measureBox(font, text)
  if result[2] <= measureBox(font, "abcdABCD")[2]:
    result[2] = measureBox(font, "gjpqy")[2]

# ------------------------------------------------------------------ layout --

proc offsetH(n: Node): float64 = (if n.isNil: 0.0 else: n.getNum("offsetHeight"))

proc measureToolbar(v: SheetView) =
  ## toolbar.js createToolbar / resize.js:430-475: every toolbar group (a
  ## button, its "-menu" half and its separator) and the left offsets they
  ## have with all of them inline. The page's snapshot may hold some in the
  ## "More" box; they go back first.
  let editor = byId("luckysheet-wa-editor")
  v.moreDiv = byId("luckysheet-icon-morebtn-div")
  v.moreBtn = byId("luckysheet-icon-morebtn")
  v.toggleTopBar = byId("luckysheet-icon-toggle-topbar")
  if editor.isNil or editor.getNum("clientWidth") <= 0: return   # hidden (an iframe not shown yet): later
  if not v.moreBtn.isNil: v.moreBtn.remove()
  if not v.toggleTopBar.isNil: v.toggleTopBar.remove()
  if not v.moreDiv.isNil:
    for n in v.moreDiv.queryAll(":scope > *"):
      editor.appendChild(createTextNode(" "))
      editor.appendChild(n)
  v.toolbarGroups.setLen(0)
  for n in editor.queryAll(":scope > *"):
    let id = n.getStr("id")
    if v.toolbarGroups.len > 0 and (id.endsWith("-menu") or id.startsWith("toolbar-separator-")):
      v.toolbarGroups[^1].add n
    else:
      v.toolbarGroups.add @[n]
  let left0 = v.root.rect.left
  v.toolbarWidths.setLen(0)
  for i, g in v.toolbarGroups:
    let r = g[0].rect
    v.toolbarWidths.add r.left - left0
    if i == v.toolbarGroups.high: v.toolbarWidths.add r.left - left0 + g[0].getNum("offsetWidth") + 5

proc layoutToolbar(v: SheetView, gridW: float64) =
  ## luckysheetsizeauto (resize.js:105-160): groups from the first that does
  ## not fit (gridW - 90) move into #luckysheet-icon-morebtn-div, and a "More"
  ## button follows the "Toggle top bar" one.
  let editor = byId("luckysheet-wa-editor")
  if editor.isNil or v.toolbarGroups.len == 0: return
  if not v.moreDiv.isNil:
    v.moreDiv.style("visibility", "hidden")
    for n in v.moreDiv.queryAll(":scope > *"):
      editor.appendChild(createTextNode(" "))
      editor.appendChild(n)
  if not v.moreBtn.isNil: v.moreBtn.remove()
  if not v.toggleTopBar.isNil: v.toggleTopBar.remove()
  var moreIndex = 0
  var isMore = false
  for i in countdown(v.toolbarWidths.high, 0):
    if v.toolbarWidths[i] < gridW - 90:
      moreIndex = i
      isMore = moreIndex < v.toolbarWidths.len - 1
      break
  if not v.moreDiv.isNil:
    for i in moreIndex ..< v.toolbarGroups.len:
      for n in v.toolbarGroups[i]: v.moreDiv.appendChild(n)
  if not v.toggleTopBar.isNil: editor.appendChild(v.toggleTopBar)
  if isMore and not v.moreBtn.isNil:
    editor.appendChild(v.moreBtn)
    v.moreBtn.query(".luckysheet-toolbar-button-inner-box").setProp("innerHTML",
      "<div class=\"luckysheet-toolbar-menu-button-caption luckysheet-inline-block\" style=\"user-select: none;\">More</div>" &
      "<div class=\"luckysheet-toolbar-menu-button-dropdown luckysheet-inline-block iconfont-luckysheet luckysheet-iconfont-xiayige\" style=\"user-select: none;font-size:12px;\"></div>")

proc toggleMore(v: SheetView) =
  ## #luckysheet-icon-morebtn click (resize.js:165-215)
  if v.moreDiv.isNil: return
  v.moreDiv.style("left", "")
  let containerLeft = v.root.rect.left
  if v.moreDiv.rect.left < containerLeft: v.moreDiv.style("left", $containerLeft & "px")
  let right = window.getNum("innerWidth") - v.moreBtn.rect.left - v.moreBtn.getNum("clientWidth")
  v.moreDiv.style("right", if right < 0: "0" else: $right & "px")
  v.moreDiv.style("top", $(v.infobarH + v.toolbarH + v.root.rect.top) & "px")
  let opening = v.moreDiv.getStr("style.visibility") == "hidden"
  v.moreDiv.style("visibility", if opening: "visible" else: "hidden")
  let (caption, icon) = if opening: ("Close", "luckysheet-iconfont-shangyige") else: ("More", "luckysheet-iconfont-xiayige")
  v.moreBtn.query(".luckysheet-toolbar-button-inner-box").setProp("innerHTML",
    "<div class=\"luckysheet-toolbar-menu-button-caption luckysheet-inline-block\" style=\"user-select: none;\">" & caption & "</div>" &
    "<div class=\"luckysheet-toolbar-menu-button-dropdown luckysheet-inline-block iconfont-luckysheet " & icon & "\" style=\"user-select: none;font-size:12px;\"></div>")

proc sizeAuto*(v: SheetView) =
  ## luckysheetsizeauto + changeSheetContainerSize (controllers/resize.js).
  let container = v.root
  for n in document.queryAll("#luckysheet_info_detail, #luckysheet .top-bar"):
    n.style("display", if v.hideInfobar: "none" else: "")
  let gridW = container.getNum("clientWidth")
  v.ribbonLayout()
  let gridH = container.getNum("clientHeight")
  v.sizedW = gridW; v.sizedH = gridH
  v.infobarH = offsetH(document.query("#luckysheet_info_detail"))
  if v.infobarH == 0: v.infobarH = offsetH(container.query(".top-bar"))
  v.toolbarH = offsetH(container.query(".luckysheet-wa-editor")) + offsetH(byId("qs-ribbon-tabs"))   # the ribbon's tab strip is part of the toolbar
  v.calcbarH = offsetH(container.query(".luckysheet-wa-calculate"))
  v.sheetBarH = offsetH(byId("luckysheet-sheet-area"))
  v.statBarH = offsetH(container.query(".luckysheet-stat-area"))
  if not v.gridContainer.isNil:
    v.gridContainer.style("top", $(v.toolbarH + v.infobarH + v.calcbarH) & "px")
  let wrap = container.query(".luckysheet")
  if not wrap.isNil:
    wrap.style("height", $(gridH - 2) & "px"); wrap.style("width", $(gridW - 2) & "px")
  v.cellMainH = gridH - (v.infobarH + v.toolbarH + v.calcbarH + ColHeaderH + v.sheetBarH + v.statBarH)
  v.cellMainW = gridW - RowHeaderW
  v.colsHC.style("width", $v.cellMainW & "px")
  v.cellMain.style("width", $v.cellMainW & "px")
  v.cellMain.style("height", $v.cellMainH & "px")
  v.rowsH.style("height", $(v.cellMainH - ScrollBar) & "px")
  v.sbY.style("height", $(v.cellMainH + ColHeaderH - ScrollBar - 3) & "px")
  v.sbX.style("height", $ScrollBar & "px")
  v.sbY.style("width", $ScrollBar & "px")
  v.sbX.style("width", $v.cellMainW & "px")
  v.sbX.style("left", $(RowHeaderW - 2) & "px")
  v.tableW = v.cellMainW + RowHeaderW - ScrollBar
  v.tableH = v.cellMainH + ColHeaderH - ScrollBar
  let dpr = max(1.0, window.getNum("devicePixelRatio"))
  v.dpr = dpr
  v.canvas.setProp("width", int(ceil(v.tableW * dpr)))
  v.canvas.setProp("height", int(ceil(v.tableH * dpr)))
  v.canvas.style("width", $v.tableW & "px")
  v.canvas.style("height", $v.tableH & "px")
  if not v.gridWindow.isNil: v.gridWindow.style("bottom", $v.sheetBarH & "px")

proc sheetExtent(s: Sheet): (float64, float64) =
  ## Store.ch_width, Store.rh_height (rhchInit) — Excel's: the sheet ends with
  ## its last row / column, no margin (the view always fills the window).
  (s.colX(s.colCount), s.rowY(s.rowCount))

proc applyExtent(v: SheetView) =
  ## The content sizes createdom.js sets: scroll strips, header strips, flow table.
  let (chW, rhH) = v.sheet.sheetExtent
  v.extent = (chW, rhH)
  v.sbXInner.style("width", $chW & "px")
  v.sbYInner.style("height", $(rhH + ColHeaderH - ScrollBar - 3) & "px")
  v.sheettable.style("width", $(chW - 1) & "px")
  v.sheettable.style("height", $rhH & "px")
  if not v.rowHeaderDiv.isNil: v.rowHeaderDiv.style("height", $rhH & "px")
  if not v.colsCells.isNil: v.colsCells.style("width", $chW & "px")

proc parseInput*(wb: Workbook, text: string, old: Cell): Cell
include rules

# ------------------------------------------------------------- freeze panes --
# Rows above / columns left of the split (Sheet.frozenRows / frozenCols) stay
# put. Content coordinates are unchanged; the scrolled part shows content from
# the split + the scroll offset, so a scroll of 0 puts the first scrolled row
# right under the frozen ones (Excel's, and freezen.js's, model).

proc frozenW(v: SheetView): float64 = (let s = v.sheet; if s.frozenCols > 0: s.colX(s.frozenCols) else: 0.0)
proc frozenH(v: SheetView): float64 = (let s = v.sheet; if s.frozenRows > 0: s.rowY(s.frozenRows) else: 0.0)

proc cx(v: SheetView, mx: float64): float64 =
  ## the content x under a grid-relative mouse x
  if v.sheet.frozenCols > 0 and mx < v.frozenW: mx else: mx + v.sbX.getNum("scrollLeft")
proc cy(v: SheetView, my: float64): float64 =
  if v.sheet.frozenRows > 0 and my < v.frozenH: my else: my + v.sbY.getNum("scrollTop")

proc scrX(v: SheetView, x: float64): float64 =
  ## the grid-relative screen x of a content x
  if v.sheet.frozenCols > 0 and x < v.frozenW: x else: x - v.sbX.getNum("scrollLeft")
proc scrY(v: SheetView, y: float64): float64 =
  if v.sheet.frozenRows > 0 and y < v.frozenH: y else: y - v.sbY.getNum("scrollTop")

proc ax(v: SheetView, x: float64): float64 =
  ## an overlay's x (the overlay layers scroll with the cells): frozen
  ## columns ride along with the scroll, the rest stops at the split
  if v.sheet.frozenCols == 0: return x
  let sl = v.sbX.getNum("scrollLeft")
  let fw = v.frozenW
  if x < fw: x + sl else: max(x, fw + sl)
proc ay(v: SheetView, y: float64): float64 =
  if v.sheet.frozenRows == 0: return y
  let st = v.sbY.getNum("scrollTop")
  let fh = v.frozenH
  if y < fh: y + st else: max(y, fh + st)

proc placeOverlays(v: SheetView)

# ------------------------------------------------------------------ drawing --

proc draw*(v: SheetView)

proc requestDraw*(v: SheetView) =
  if v.framePending: return
  v.framePending = true
  requestAnimationFrame(proc(now: float64) =
    v.framePending = false
    v.draw())

proc visibleRows(v: SheetView): (int, int) =
  ## luckysheet_searcharray(visibledatarow, scrollTop .. scrollTop + drawHeight)
  let s = v.sheet
  let first = min(s.rowAt(v.scrollY + v.frozenH), s.rowCount - 1)
  var last = min(s.rowAt(v.scrollY + v.tableH), s.rowCount - 1)
  (first, max(first, last))

proc visibleCols(v: SheetView): (int, int) =
  let s = v.sheet
  let first = min(s.colAt(v.scrollX + v.frozenW), s.colCount - 1)
  var last = min(s.colAt(v.scrollX + v.tableW), s.colCount - 1)
  (first, max(first, last))

proc rangeBox*(v: SheetView, r1, c1, r2, c2: int): (float64, float64, float64, float64) =
  ## seletedHighlistByindex: left col_pre, width col - col_pre - 1 — in the
  ## overlay layer's coordinates (freezen.scrollAdapt for frozen panes; a
  ## box wholly behind the frozen part goes off-screen).
  let s = v.sheet
  let x = v.ax(s.colX(c1))
  let y = v.ay(s.rowY(r1))
  let x2 = v.ax(s.colX(c2 + 1))
  let y2 = v.ay(s.rowY(r2 + 1))
  if x2 <= x or y2 <= y: return (-100000.0, -100000.0, 0.0, 0.0)
  (x, y, x2 - x - 1, y2 - y - 1)

proc cellBox*(v: SheetView, r, c: int): (float64, float64, float64, float64) =
  ## A cell's box (what overlays and charts use): left = visibledatacolumn[c-1],
  ## width = len (the grid line is not part of it).
  v.rangeBox(r, c, r, c)

proc drawRowTitle(v: SheetView, c: Ctx, r0, r1: int, sy: float64, band = (0.0, Inf), clear = true) =
  ## luckysheetDrawgridRowTitle (draw.js:22-204); `band`: the screen rows it
  ## may paint (the frozen / scrolled part)
  let s = v.sheet
  let offsetTop = ColHeaderH
  let drawHeight = v.tableH
  if clear: c.clearRect(0, offsetTop, RowHeaderW - 1, drawHeight)
  c.font = "normal normal normal " & $DefaultFontSize & "pt " & FontStack
  c.textBaseline = "middle"
  c.save()
  let top = offsetTop - 1 + band[0]
  c.beginPath(); c.rect(0, top, RowHeaderW - 1, min(drawHeight - 2 - band[0], band[1] - band[0])); c.clip()
  for r in r0 .. r1:
    if s.rowHidden(r): continue
    let startR = s.rowY(r) - sy - 1
    let endR = s.rowY(r + 1) - sy
    let firstOffset = if r == r0: -2.0 else: 0.0
    let lastOffset = if r == r1: -2.0 else: 0.0
    c.fillStyle = "#ffffff"
    c.fillRect(0, startR + offsetTop + firstOffset, RowHeaderW - 1, endR - startR + 1 + lastOffset - firstOffset)
    c.fillStyle = "#000000"
    let label = $(r + 1)
    let tw = measureText(c.font, label)
    c.textAlign = "left"
    c.fillText(label, (RowHeaderW - tw) / 2, startR + (endR - startR) / 2 + offsetTop)
    c.strokeStyle = GridLine
    c.lineWidth = 1
    c.beginPath()
    c.moveTo(RowHeaderW - 2 + 0.5, startR + offsetTop - 2)
    c.lineTo(RowHeaderW - 2 + 0.5, endR + offsetTop - 2)
    c.stroke()
    c.beginPath()
    c.moveTo(-1, endR + offsetTop - 2 + 0.5)
    c.lineTo(RowHeaderW - 1, endR + offsetTop - 2 + 0.5)
    c.stroke()
  c.restore()

proc drawColumnTitle(v: SheetView, c: Ctx, c0, c1: int, sx: float64, band = (0.0, Inf), clear = true) =
  ## luckysheetDrawgridColumnTitle (draw.js:206-380)
  let s = v.sheet
  let offsetLeft = RowHeaderW
  let drawWidth = v.tableW
  if clear: c.clearRect(offsetLeft, 0, drawWidth, ColHeaderH - 1)
  c.font = "normal normal normal " & $DefaultFontSize & "pt " & FontStack
  c.textBaseline = "middle"
  c.save()
  let left = offsetLeft - 1 + band[0]
  c.beginPath(); c.rect(left, 0, min(drawWidth - band[0], band[1] - band[0]), ColHeaderH - 1); c.clip()
  for col in c0 .. c1:
    if s.colHidden(col): continue
    let startC = s.colX(col) - sx
    let endC = s.colX(col + 1) - sx
    c.fillStyle = "#ffffff"
    c.fillRect(startC + offsetLeft - 1, 0, endC - startC, ColHeaderH - 1)
    c.fillStyle = "#000000"
    let label = colName(col)
    let tw = measureText(c.font, label)
    c.textAlign = "left"
    c.fillText(label, round(startC + (endC - startC) / 2 + offsetLeft - tw / 2), round(ColHeaderH / 2))
    c.strokeStyle = GridLine
    c.lineWidth = 1
    c.beginPath()
    c.moveTo(endC + offsetLeft - 2 + 0.5, 0)
    c.lineTo(endC + offsetLeft - 2 + 0.5, ColHeaderH - 2)
    c.stroke()
    c.beginPath()
    c.moveTo(startC + offsetLeft - 1, ColHeaderH - 2 + 0.5)
    c.lineTo(endC + offsetLeft - 1, ColHeaderH - 2 + 0.5)
    c.stroke()
  c.restore()

proc borderLine(c: Ctx, b: Border, x1, y1, x2, y2: float64, horizontal: bool) =
  ## menuButton.setLineDash: Hair [1,2], Dotted [2], Dashed [3], Medium 2 px
  ## (half a pixel up/left), Thick 3 px, the rest 1 px.
  if b.kind == bkNone: return
  c.strokeStyle = (if b.color.len > 0: b.color else: "#000000")
  case b.kind
  of bkHair: c.setLineDash([1.0, 2.0])
  of bkDotted: c.setLineDash([2.0])
  of bkDashed: c.setLineDash([3.0])
  else: c.setLineDash([0.0])
  c.beginPath()
  case b.kind
  of bkMedium:
    if horizontal: c.moveTo(x1, y1 - 0.5); c.lineTo(x2, y2 - 0.5)
    else: c.moveTo(x1 - 0.5, y1); c.lineTo(x2 - 0.5, y2)
    c.lineWidth = 2
  of bkThick:
    c.moveTo(x1, y1); c.lineTo(x2, y2)
    c.lineWidth = 3
  else:
    c.moveTo(x1, y1); c.lineTo(x2, y2)
    c.lineWidth = 1
  c.stroke()

proc cellParts(v: SheetView, cell: Cell, st: Style): seq[(string, Style)] =
  ## what a cell shows: its runs (rich text) or its formatted value
  if cell.rich.len > 0 and cell.formula.len == 0:
    for run in cell.rich:
      if run.text.len > 0: result.add (run.text, runStyle(st, run))
  else:
    let text = v.wb.displayText(cell)
    if text.len > 0: result.add (text, st)

proc partsWidth(parts: seq[(string, Style)]): float64 =
  for (text, ps) in parts: result += measureCell(fontOf(ps), text)[0]

proc wrapLines(parts: seq[(string, Style)], width: float64): seq[seq[(string, Style)]] =
  ## Excel's wrap: words that fit go on a line, a longer word breaks by
  ## characters; a line break always starts a new line.
  var line: seq[(string, Style)]
  var lineW = 0.0
  proc push(text: string, ps: Style) =
    if line.len > 0 and line[^1][1] == ps: line[^1][0].add text
    else: line.add (text, ps)
  for (text, ps) in parts:
    let font = fontOf(ps)
    var tokens: seq[string]
    var cur = ""
    for ch in text.runes:
      let t = $ch
      if t == "\n":
        if cur.len > 0: tokens.add cur
        tokens.add "\n"; cur = ""
      else:
        cur.add t
        if t == " ": tokens.add cur; cur = ""
    if cur.len > 0: tokens.add cur
    for tok in tokens:
      if tok == "\n":
        result.add line; line = @[]; lineW = 0; continue
      let w = measureCell(font, tok)[0]
      if lineW + w <= width or lineW == 0 and w <= width:
        push(tok, ps); lineW += w
      elif w <= width:
        result.add line; line = @[]; lineW = 0
        if tok != " ": push(tok, ps); lineW = w
      else:
        # a word longer than the line: by characters
        for ch in tok.runes:
          let cw = measureCell(font, $ch)[0]
          if lineW + cw > width and lineW > 0:
            result.add line; line = @[]; lineW = 0
          push($ch, ps); lineW += cw
  if line.len > 0 or result.len == 0: result.add line

proc drawMain(v: SheetView, c: Ctx, r0, r1, c0, c1: int, sx, sy: float64, bandX, bandY: (float64, float64), stats: seq[CfStats]) =
  ## luckysheetDrawMain + nullCellRender / cellRender (draw.js:383-1800) for
  ## one pane: `sx`, `sy` its scroll, `bandX`, `bandY` the screen part it owns.
  let s = v.sheet
  let offsetLeft = RowHeaderW
  let offsetTop = ColHeaderH
  c.save()
  block:
    let x0 = if bandX[0] == 0: 0.0 else: offsetLeft + bandX[0] - 1
    let y0 = if bandY[0] == 0: 0.0 else: offsetTop + bandY[0] - 1
    let x1 = min(v.tableW, offsetLeft + bandX[1] - 1)
    let y1 = min(v.tableH, offsetTop + bandY[1] - 1)
    c.beginPath(); c.rect(x0, y0, x1 - x0, y1 - y0); c.clip()
  c.fillStyle = "#ffffff"
  c.fillRect(offsetLeft - 1, offsetTop - 1, s.colX(c1 + 1) - sx, s.rowY(r1 + 1) - sy)
  let anyMerge = s.merges.len > 0
  let anyRules = s.condRules.len > 0
  proc startR(r: int): float64 = s.rowY(r) - sy - 1
  proc endR(r: int): float64 = s.rowY(r + 1) - sy
  proc startC(col: int): float64 = s.colX(col) - sx
  proc endC(col: int): float64 = s.colX(col + 1) - sx

  proc shownStyle(r, col: int, cell: Cell): (Style, CfOut) =
    ## the cell's style with its conditional formats and hyperlink look
    var st = v.wb.styles[cell.style]
    var o = CfOut(bar: NaN)
    if anyRules and cell.value.kind != vkEmpty:
      o = v.cfFor(stats, r, col, cell)
      if o.fill.len > 0: st.fill = o.fill
      if o.color.len > 0: st.color = o.color
      if o.bold: st.bold = true
    if s.links.len > 0 and s.links.hasKey(key(r, col)) and st.color.len == 0:
      st.color = "#0563c1"; st.underline = true          # Excel's Hyperlink style
    (st, o)

  proc fillCell(st: Style, x0, y0, x1, y1: float64, isMerge = false) =
    c.fillStyle = (if st.fill.len > 0: st.fill else: "#FFFFFF")
    c.fillRect(x0 + offsetLeft + 1, y0 + offsetTop + 1, x1 - x0 - (if isMerge: 1.0 else: 0.0) - 1, y1 - y0 - 1)

  proc drawBar(o: CfOut, x0, y0, x1, y1: float64) =
    ## a data bar (Excel's gradient fill), left to right
    if o.bar != o.bar or o.bar <= 0: return
    let w = (x1 - x0 - 4) * clamp(o.bar, 0.0, 1.0)
    let bx = x0 + offsetLeft + 1
    let by = y0 + offsetTop + 2
    let g = c.createLinearGradient(bx, 0, bx + max(w, 1.0), 0)
    g.addColorStop(0, o.barColor)
    g.addColorStop(1, "#ffffff")
    c.setFillGradient(g)
    c.fillRect(bx, by, w, y1 - y0 - 4)
    c.strokeStyle = o.barColor
    c.lineWidth = 1
    c.setLineDash([0.0])
    c.strokeRect(bx + 0.5, by + 0.5, max(0.0, w - 1), y1 - y0 - 5)

  proc drawText(cell: Cell, st: Style, x0, y0, x1, y1: float64, clipX0 = NaN, clipX1 = NaN) =
    ## cellRender's text: clip to (start_c, start_r + 1, w - 2, h - 2) — or the
    ## overflow span — and getCellTextInfo's plain layout with space 2. A rich
    ## cell draws its runs one after another, each in its own font, on one
    ## baseline; wrapped text goes on lines; rotated text turns about the
    ## cell's centre (Excel's textRotation; 255 stacks the letters).
    let parts = v.cellParts(cell, st)
    if parts.len == 0: return
    let cellW = x1 - x0 - 2
    let cellH = y1 - y0 - 2
    let posX = x0 + offsetLeft
    let posY = y0 + offsetTop + 1
    let h = case st.hAlign
      of haCenter: 0
      of haRight: 2
      of haLeft: 1
      else:                                        # Excel's General: numbers right, booleans and errors centred, text left
        (if cell.rich.len > 0: 1 elif cell.value.kind == vkNum: 2 elif cell.value.kind in {vkBool, vkErr}: 0 else: 1)
    c.save()
    c.beginPath()
    if clipX0 == clipX0: c.rect(clipX0 + offsetLeft, posY, clipX1 - clipX0 - 2, cellH)
    else: c.rect(posX, posY, cellW, cellH)
    c.clip()
    c.textAlign = "left"
    c.textBaseline = "alphabetic"
    proc drawRun(text: string, ps: Style, x, y, w, asc, desc: float64) =
      c.font = fontOf(ps)
      c.fillStyle = (if ps.color.len > 0: ps.color else: "#000000")
      c.fillText(text, x, y)
      if ps.strike or ps.underline:
        c.strokeStyle = c.fillStyle
        c.lineWidth = 1
        c.setLineDash([0.0])
        c.beginPath()
        if ps.strike:                              # cancelLine at top - asc/2 + 1
          c.moveTo(x, y - asc / 2 + 1); c.lineTo(x + w, y - asc / 2 + 1)
        if ps.underline:                           # underLine at top + desc
          c.moveTo(x, y + desc + 1); c.lineTo(x + w, y + desc + 1)
        c.stroke()
    if st.rotation != 0 and not st.wrap:
      let cxm = posX + cellW / 2
      let cym = posY + cellH / 2
      if st.rotation == 255:
        # stacked: one letter under another
        var letters: seq[(string, Style, float64, float64, float64)]
        var total = 0.0
        for (text, ps) in parts:
          for ch in text.runes:
            let (w, a, d) = measureCell(fontOf(ps), $ch)
            letters.add ($ch, ps, w, a, d); total += a + d
        var y = cym - total / 2
        for (t, ps, w, a, d) in letters:
          drawRun(t, ps, cxm - w / 2, y + a, w, a, d)
          y += a + d
      else:
        var tw, asc, desc = 0.0
        var widths: seq[float64]
        for (text, ps) in parts:
          let (w, a, d) = measureCell(fontOf(ps), text)
          widths.add w; tw += w; asc = max(asc, a); desc = max(desc, d)
        c.translate(cxm, cym)
        c.rotate(-float64(st.rotation) * PI / 180)
        var x = -tw / 2
        for i, (text, ps) in parts:
          drawRun(text, ps, x, (asc - desc) / 2, widths[i], asc, desc)
          x += widths[i]
      c.restore()
      return
    let lines = if st.wrap: wrapLines(parts, cellW - 2 * SpaceW) else: @[parts]
    var metrics: seq[(float64, float64, float64, seq[float64])]   # width, asc, desc, part widths
    var blockH = 0.0
    for line in lines:
      var tw, asc, desc = 0.0
      var ws: seq[float64]
      for (text, ps) in line:
        let (w, a, d) = measureCell(fontOf(ps), text)
        ws.add w; tw += w; asc = max(asc, a); desc = max(desc, d)
      if line.len == 0:
        let (_, a, d) = measureCell(fontOf(st), "M")
        asc = a; desc = d
      metrics.add (tw, asc, desc, ws)
      blockH += asc + desc + (if st.wrap: 2.0 else: 0.0)
    if st.wrap and blockH > 0: blockH -= 2
    var y = case st.vAlign                         # "vt" default "0": middle
      of vaTop: SpaceW
      of vaBottom: (cellH - SpaceW) - blockH
      else: cellH / 2 - blockH / 2
    for li, line in lines:
      let (tw, asc, desc, ws) = metrics[li]
      let left = case h
        of 0: cellW / 2 - tw / 2
        of 2: cellW - SpaceW - tw
        else: SpaceW
      var x = posX + left
      for i, (text, ps) in line:
        drawRun(text, ps, x, posY + y + asc, ws[i], asc, desc)
        x += ws[i]
      y += asc + desc + 2
    c.restore()

  # Overflow (Excel; Luckysheet's getCellOverflowMap with tb "1"): text that
  # does not fit runs on over empty neighbours — left / General text to the
  # right, right-aligned to the left, centred both ways; numbers do not.
  proc isEmptyAt(r, col: int): bool =
    let k = key(r, col)
    (not s.cells.hasKey(k) or (s.cells[k].value.kind == vkEmpty and s.cells[k].formula.len == 0)) and
      (not anyMerge or s.mergeAt(r, col) < 0)
  for r in r0 .. r1:
    if s.rowHidden(r): continue
    let yS = startR(r)
    let yE = endR(r)
    var spans: seq[(int, int, int)]               # owner, from, to
    let lo = max(0, c0 - 30)
    let hi = min(s.colCount - 1, c1 + 30)
    for col in lo .. hi:
      let k = key(r, col)
      if not s.cells.hasKey(k): continue
      let cell = s.cells[k]
      if cell.value.kind != vkStr or s.colHidden(col): continue
      let st = v.wb.styles[cell.style]
      if st.wrap or st.rotation != 0 or (anyMerge and s.mergeAt(r, col) >= 0): continue
      let need = partsWidth(v.cellParts(cell, st)) + 2 * SpaceW
      var have = s.colX(col + 1) - s.colX(col) - 2
      if need <= have: continue
      var a = col
      var b = col
      case st.hAlign
      of haRight:
        while have < need and a - 1 >= 0 and isEmptyAt(r, a - 1): dec a; have += s.colX(a + 1) - s.colX(a)
      of haCenter:
        var grew = true
        while have < need and grew:
          grew = false
          if b + 1 < s.colCount and isEmptyAt(r, b + 1): inc b; have += s.colX(b + 1) - s.colX(b); grew = true
          if a - 1 >= 0 and isEmptyAt(r, a - 1): dec a; have += s.colX(a + 1) - s.colX(a); grew = true
      else:
        while have < need and b + 1 < s.colCount and isEmptyAt(r, b + 1): inc b; have += s.colX(b + 1) - s.colX(b)
      if a != col or b != col: spans.add (col, a, b)
    proc inSpan(col: int): bool =
      ## a grid line after `col` that overflowing text covers
      for (_, a, b) in spans:
        if col >= a and col < b: return true
    for col in c0 .. c1:
      if s.colHidden(col): continue
      let xS = startC(col)
      let xE = endC(col)
      let k = key(r, col)
      let inMerge = anyMerge and s.mergeAt(r, col) >= 0
      if not inMerge:
        let cell = s.cells.getOrDefault(k)
        let (st, o) = shownStyle(r, col, cell)
        fillCell(st, xS, yS, xE, yE)
        drawBar(o, xS, yS, xE, yE)
      # right and bottom grid lines (nullCellRender/cellRender), not inside merges
      let mi = if anyMerge: s.mergeAt(r, col) else: -1
      c.strokeStyle = GridLine
      c.lineWidth = 1
      c.setLineDash([0.0])
      if (mi < 0 or s.merges[mi].c2 == col) and not inSpan(col):
        c.beginPath()
        c.moveTo(xE + offsetLeft - 2 + 0.5, yS + offsetTop)
        c.lineTo(xE + offsetLeft - 2 + 0.5, yE + offsetTop)
        c.stroke()
      if mi < 0 or s.merges[mi].r2 == r:
        c.beginPath()
        c.moveTo(xS + offsetLeft - 1, yE + offsetTop - 2 + 0.5)
        c.lineTo(xE + offsetLeft - 1, yE + offsetTop - 2 + 0.5)
        c.stroke()
    for col in c0 .. c1:
      if s.colHidden(col): continue
      let k = key(r, col)
      if not s.cells.hasKey(k) or (anyMerge and s.mergeAt(r, col) >= 0): continue
      var spanned = false
      for (owner, _, _) in spans:
        if owner == col: spanned = true
      if spanned: continue
      let cell = s.cells[k]
      drawText(cell, shownStyle(r, col, cell)[0], startC(col), yS, endC(col), yE)
    for (owner, a, b) in spans:
      if b < c0 or a > c1: continue
      let cell = s.cells[key(r, owner)]
      drawText(cell, shownStyle(r, owner, cell)[0], startC(owner), yS, endC(owner), yE, startC(a), endC(b))
  # merged ranges: one cell, drawn after the others (mcArr)
  for m in s.merges:
    if m.r2 < r0 or m.r1 > r1 or m.c2 < c0 or m.c1 > c1: continue
    let cell = s.cellAt(m.r1, m.c1)
    let xS = startC(m.c1)
    let yS = startR(m.r1)
    let xE = endC(m.c2) - 1
    let yE = endR(m.r2) - 1
    let (st, o) = shownStyle(m.r1, m.c1, cell)
    fillCell(st, xS, yS, xE, yE, isMerge = true)
    drawBar(o, xS, yS, xE, yE)
    drawText(cell, st, xS, yS, xE, yE)
  # borders (borderInfo), after the cells
  for r in r0 .. r1:
    if s.rowHidden(r): continue
    for col in c0 .. c1:
      if s.colHidden(col): continue
      let k = key(r, col)
      if not s.cells.hasKey(k): continue
      let st = v.wb.styles[s.cells[k].style]
      if st.left.kind == bkNone and st.right.kind == bkNone and st.top.kind == bkNone and st.bottom.kind == bkNone: continue
      let xS = startC(col) + offsetLeft - 1
      let xE = endC(col) + offsetLeft - 2 + 0.5
      let yS = startR(r) + offsetTop + 0.5
      let yE = endR(r) + offsetTop - 2 + 0.5
      borderLine(c, st.top, xS, yS, xE + 0.5, yS, true)
      borderLine(c, st.bottom, xS, yE, xE + 0.5, yE, true)
      borderLine(c, st.left, xS + 0.5, yS - 0.5, xS + 0.5, yE + 0.5, false)
      borderLine(c, st.right, xE, yS - 0.5, xE, yE + 0.5, false)
  c.setLineDash([0.0])
  # notes: Excel's red triangle in the top-right corner (postil.js's indicator)
  for k in s.notes.keys:
    let (r, col) = (rowOf(k), colOf(k))
    if r < r0 or r > r1 or col < c0 or col > c1 or s.rowHidden(r) or s.colHidden(col): continue
    var cEnd = col
    let mi = if anyMerge: s.mergeAt(r, col) else: -1
    if mi >= 0: cEnd = s.merges[mi].c2
    let x = endC(cEnd) + offsetLeft - 2
    let y = startR(r) + offsetTop + 1
    c.fillStyle = "#ff0000"
    c.beginPath(); c.moveTo(x - 6, y); c.lineTo(x, y); c.lineTo(x, y + 6); c.closePath(); c.fill()
  c.restore()

proc showSelection*(v: SheetView)

proc fillView(v: SheetView) =
  ## Excel: rows and columns run to the window's edges whatever the scroll;
  ## the scrollbar itself only reaches the data (+ a margin) and what the
  ## wheel or the arrow keys went to.
  let s = v.sheet
  let needY = v.sbY.getNum("scrollTop") + v.cellMainH + v.frozenH
  while s.rowY(s.rowCount) < needY and s.rowCount < MaxRows: s.viewRows = s.rowCount + 10
  let needX = v.sbX.getNum("scrollLeft") + v.cellMainW + v.frozenW
  while s.colX(s.colCount) < needX and s.colCount < MaxCols: s.viewCols = s.colCount + 4

proc reach(v: SheetView, r, c: int) =
  ## the sheet goes on to (r, c) and a window past it, for the wheel and arrows
  let s = v.sheet
  let (h, w) = (v.cellMainH, v.cellMainW)
  if r >= s.rowCount - 1:
    s.viewRows = min(MaxRows, r + 2)
    while s.rowY(s.rowCount) < s.rowY(r + 1) + h and s.rowCount < MaxRows: s.viewRows = s.rowCount + 10
  if c >= s.colCount - 1:
    s.viewCols = min(MaxCols, c + 2)
    while s.colX(s.colCount) < s.colX(c + 1) + w and s.colCount < MaxCols: s.viewCols = s.colCount + 4
  if s.sheetExtent != v.extent: v.applyExtent()

proc draw*(v: SheetView) =
  ## luckysheetrefreshgrid: main, then the row and column titles.
  let s = v.sheet
  let c = v.rec
  v.fillView()
  if v.sheet.sheetExtent != v.extent: v.applyExtent()
  v.scrollX = v.sbX.getNum("scrollLeft")
  v.scrollY = v.sbY.getNum("scrollTop")
  let (r0, r1) = v.visibleRows()
  let (c0, c1) = v.visibleCols()
  c.reset()
  c.setTransform(v.dpr, 0, 0, v.dpr, 0, 0)
  c.clearRect(0, 0, v.tableW, v.tableH)
  let fr = s.frozenRows
  let fc = s.frozenCols
  let fw = v.frozenW
  let fh = v.frozenH
  let stats = v.cfPrepare()
  let sx = v.scrollX
  let sy = v.scrollY
  # four panes (freezen.js): scrolled, frozen columns, frozen rows, the corner
  v.drawMain(c, r0, r1, c0, c1, sx, sy, (fw, Inf), (fh, Inf), stats)
  if fc > 0: v.drawMain(c, r0, r1, 0, fc - 1, 0, sy, (0.0, fw), (fh, Inf), stats)
  if fr > 0: v.drawMain(c, 0, fr - 1, c0, c1, sx, 0, (fw, Inf), (0.0, fh), stats)
  if fr > 0 and fc > 0: v.drawMain(c, 0, fr - 1, 0, fc - 1, 0, 0, (0.0, fw), (0.0, fh), stats)
  v.drawRowTitle(c, r0, r1, sy, (fh, Inf))
  if fr > 0: v.drawRowTitle(c, 0, fr - 1, 0, (0.0, fh), clear = false)
  v.drawColumnTitle(c, c0, c1, sx, (fw, Inf))
  if fc > 0: v.drawColumnTitle(c, 0, fc - 1, 0, (0.0, fw), clear = false)
  # the split lines (Excel's thin dark line)
  c.strokeStyle = "#9c9c9c"
  c.lineWidth = 1
  c.setLineDash([0.0])
  if fr > 0:
    c.beginPath(); c.moveTo(0, ColHeaderH + fh - 1.5); c.lineTo(v.tableW, ColHeaderH + fh - 1.5); c.stroke()
  if fc > 0:
    c.beginPath(); c.moveTo(RowHeaderW + fw - 1.5, 0); c.lineTo(RowHeaderW + fw - 1.5, v.tableH); c.stroke()
  c.finish()
  v.placeOverlays()
  replay(v.ctx, addr c.buf)
  flush()

# ------------------------------------------------------------ overlays (DOM) --

proc px(x: float64): string = $x & "px"

proc countShow(v: SheetView, r1, c1, r2, c2: int) =
  ## luckysheet_count_show (select.js:487-537): the current range's row and
  ## column counts, from 4 up (locale en: no "row" / "column" word).
  let (left, top, width, height) = v.rangeBox(r1, c1, r2, c2)
  let rowl = r2 - r1 + 1
  let coll = c2 - c1 + 1
  let scrollWidth = v.cellMain.getNum("scrollLeft")
  let scrollHeight = v.cellMain.getNum("scrollTop")
  if v.rowCountShow.isNil or v.colCountShow.isNil: return
  if rowl >= 4:
    var leftv = left - 25
    if leftv < 0: leftv = left + 5
    if leftv < scrollWidth: leftv = scrollWidth + 10
    var topv = top + height / 2
    if height > v.tableH: topv = scrollHeight + v.tableH / 2
    var html = ""
    for ch in $rowl: html.add "<div>" & ch & "</div>"
    html.add "<div></div>"
    v.rowCountShow.setAttribute("style", "left: " & px(leftv) & "; top: " & px(topv) & "; display: block; width: 11px;")
    v.rowCountShow.setProp("innerHTML", html)
  else: v.rowCountShow.style("display", "none")
  if coll >= 4:
    var topv = top - 25
    if topv < 0: topv = top + 5
    if topv < scrollHeight: topv = scrollHeight + 10
    var leftv = left + width / 2
    if width > v.tableW: leftv = scrollWidth + v.tableW / 2
    v.colCountShow.setAttribute("style", "left: " & px(leftv) & "; top: " & px(topv) & "; display: block;")
    v.colCountShow.setProp("textContent", $coll)
  else: v.colCountShow.style("display", "none")

proc showSelection*(v: SheetView) =
  ## selectHightlightShow + selectTitlesShow (controllers/select.js).
  v.showCopyAnts()
  v.placeDvButton()
  v.refreshToolbar()
  v.refreshStatus()
  let s = v.sheet
  var ranges = v.extraRanges
  let (a, b, e, f) = v.selRect()
  ranges.add Range(r1: a, c1: b, r2: e, c2: f)
  # extra boxes for ranges after the first
  for n in v.selBoxs.queryAll(".luckysheet-cell-selected"):
    if not n.same(v.selMain): n.remove()
  for i, rg in ranges:
    let (x, y, w, h) = v.rangeBox(rg.r1, rg.c1, rg.r2, rg.c2)
    if i == 0:
      let only = ranges.len == 1
      v.selMain.style("left", px(x)); v.selMain.style("width", px(w))
      v.selMain.style("top", px(y)); v.selMain.style("height", px(h))
      v.selMain.style("display", "block")
      v.selMain.style("border", if only: "1px solid #0188fb" else: "1px solid rgba(1, 136, 251, 0.15)")
      for n in v.selMain.queryAll(".luckysheet-cs-draghandle"): n.style("display", if only: "block" else: "none")
      for n in v.selMain.queryAll(".luckysheet-cs-fillhandle"): n.style("display", if only: "block" else: "none")
      for n in v.selMain.queryAll(".luckysheet-cs-touchhandle"): n.style("display", "none")
    else:
      let box = el("div", "luckysheet-cell-selected")
      box.setAttribute("style", "left: " & px(x) & "; width: " & px(w) & "; top: " & px(y) & "; height: " & px(h) &
        "; border: 1px solid rgba(1, 136, 251, 0.15); display: block;")
      discard v.selBoxs.add box
  # focus: the last range's focus cell (whole merge when merged)
  let mi = s.mergeAt(v.ar, v.ac)
  let (fx, fy, fw, fh) = if mi >= 0: (let m = s.merges[mi]; v.rangeBox(m.r1, m.c1, m.r2, m.c2)) else: v.cellBox(v.ar, v.ac)
  v.selFocus.style("left", px(fx)); v.selFocus.style("width", px(fw))
  v.selFocus.style("top", px(fy)); v.selFocus.style("height", px(fh))
  v.selFocus.style("display", "block")
  v.countShow(a, b, e, f)
  # row / column titles: merged spans of all ranges
  proc spans(pairs: seq[(int, int)]): seq[(int, int)] =
    var sorted = pairs
    sorted.sort(proc(x, y: (int, int)): int = cmp(x[0], y[0]))
    for (p, q) in sorted:
      if result.len > 0 and p <= result[^1][1] + 1: result[^1][1] = max(result[^1][1], q)
      else: result.add (p, q)
  v.rowsHSel.dropChildren()
  for (p, q) in spans(ranges.mapIt((it.r1, min(it.r2, s.rowCount - 1)))):
    let top = v.ay(s.rowY(p))
    let bottom = v.ay(s.rowY(q + 1))
    if bottom <= top: continue
    let box = el("div", "luckysheet-rows-h-selected")
    box.setAttribute("style", "top: " & px(top) & "; height: " & px(bottom - top - 1) & "; display: block; background-color: rgba(76, 76, 76, 0.1);")
    discard v.rowsHSel.add box
  v.colsHSel.dropChildren()
  for (p, q) in spans(ranges.mapIt((it.c1, min(it.c2, s.colCount - 1)))):
    let left = v.ax(s.colX(p))
    let right = v.ax(s.colX(q + 1))
    if right <= left: continue
    let box = el("div", "luckysheet-cols-h-selected")
    box.setAttribute("style", "left: " & px(left) & "; width: " & px(right - left - 1) & "; display: block; background-color: rgba(76, 76, 76, 0.1);")
    discard v.colsHSel.add box

# ---------------------------------------------------------------- scrolling --

proc onScroll(v: SheetView) =
  ## luckysheetscrollevent (global/scroll.js)
  let sl = v.sbX.getNum("scrollLeft")
  let st = v.sbY.getNum("scrollTop")
  v.colsHC.setProp("scrollLeft", sl)
  v.rowsH.setProp("scrollTop", st)
  v.cellMain.setProp("scrollLeft", sl)
  v.cellMain.setProp("scrollTop", st)
  if not v.bottomBar.isNil: v.bottomBar.style("left", px(sl))
  v.scrollX = sl; v.scrollY = st
  if v.sheet.frozenRows > 0 or v.sheet.frozenCols > 0: v.showSelection()   # freezen.scrollAdapt
  v.placeOverlays()
  v.requestDraw()

proc scrollIntoView(v: SheetView, r, c: int) =
  ## frozen rows / columns never scroll; the rest scrolls past the split
  let s = v.sheet
  let fw = v.frozenW
  let fh = v.frozenH
  let x = s.colX(c) - fw
  let y = s.rowY(r) - fh
  let vw = v.cellMainW - ScrollBar
  let vh = v.cellMainH - ScrollBar
  let sl = v.sbX.getNum("scrollLeft")
  let st = v.sbY.getNum("scrollTop")
  if c >= s.frozenCols:
    if x < sl: v.sbX.setProp("scrollLeft", x)
    elif s.colX(c + 1) > sl + vw: v.sbX.setProp("scrollLeft", s.colX(c + 1) - vw)
  if r >= s.frozenRows:
    if y < st: v.sbY.setProp("scrollTop", y)
    elif s.rowY(r + 1) > st + vh:
      v.sbY.setProp("scrollTop", s.rowY(s.rowAt(s.rowY(r + 1) - vh) + 1) - fh)

proc onWheel(v: SheetView, e: Event) =
  ## #luckysheet-grid-window-1 mousewheel (handler.js:146-247): whole rows,
  ## 1-3 per notch by deltaFactor; horizontal 20 px.
  e.preventDefault()
  let s = v.sheet
  let dy = e.deltaY
  let dx = if e.deltaX != 0: e.deltaX elif e.shiftKey: dy else: 0.0
  let st = v.sbY.getNum("scrollTop")
  if dx != 0:
    let sl = v.sbX.getNum("scrollLeft") + (if dx > 0: 20.0 else: -20.0)
    if dx > 0: v.reach(0, s.colAt(sl + v.cellMainW + v.frozenW))
    v.sbX.setProp("scrollLeft", max(0.0, sl))
  elif dy != 0:
    let fh = v.frozenH
    let first = s.rowAt(st + fh + 0.01)
    let mag = abs(dy)
    let step = if mag < 40: 1 elif mag < 80: 2 else: 3
    let target = if dy > 0: min(first + step, MaxRows - 1) else: max(first - step, s.frozenRows)
    if dy > 0: v.reach(target + int(v.cellMainH / (DefaultRowHeight + 1)), 0)
    v.sbY.setProp("scrollTop", s.rowY(target) - fh)

# ---------------------------------------------------------------- editing --

proc refreshFormulaBar*(v: SheetView) =
  ## The name box (#luckysheet-helpbox-cell) and formula bar
  ## (#luckysheet-functionbox-cell) — fucntionboxshow.
  let (r1, c1, r2, c2) = v.selRect()
  v.nameBox.setProp("textContent", if r1 == r2 and c1 == c2 or v.sheet.mergeAt(v.ar, v.ac) >= 0 and
    (let m = v.sheet.merges[v.sheet.mergeAt(v.ar, v.ac)]; m.r1 == r1 and m.c1 == c1 and m.r2 == r2 and m.c2 == c2):
      cellName(v.ar, v.ac) else: cellName(r1, c1) & ":" & cellName(r2, c2))
  if not v.editing:
    let cell = v.sheet.cellAt(v.ar, v.ac)
    v.fxBar.setProp("textContent", if cell.formula.len > 0: cell.formula else: v.wb.displayText(cell))

proc commitAction(v: SheetView, act: Action) =
  if act.len == 0: return
  for ch in act:
    if ch.snapshot or ch.sheet >= v.wb.sheets.len or not v.wb.sheets[ch.sheet].protected: continue
    if ch.isMerge or ch.sizeKind != 0 or not v.wb.styles[ch.before.style].unlocked:
      v.applyAction(act, false)
      v.protectedMessage()
      v.requestDraw()
      return
  if not v.pasting: v.endCopyMode()   # Excel: an edit ends copy mode
  v.undo.add act
  if v.undo.len > 200: v.undo.delete(0)
  v.redo.setLen(0)
  recalc(v.wb)
  if v.onChange != nil: v.onChange()

proc setCellRaw*(v: SheetView, si, r, c: int, cell: Cell, act: var Action) =
  let s = v.wb.sheets[si]
  let before = s.cellAt(r, c)
  s.putCell(r, c, cell)
  act.add Change(sheet: si, r: r, c: c, before: before, after: s.cellAt(r, c))

proc parseInput*(wb: Workbook, text: string, old: Cell): Cell =
  ## What typing `text` into a cell stores: a formula, a number, a boolean or text.
  result = Cell(style: old.style)
  let t = text
  if t.len > 1 and t[0] == '=':
    result.setFormula(t)
  elif t.len == 0:
    result.value = emptyVal()
  else:
    let st = t.strip
    var isNum = false
    var n = 0.0
    if st.len > 0 and st[0] in {'0'..'9', '-', '+', '.'}:
      try:
        if st.endsWith("%"): n = parseFloat(st[0 ..< ^1].replace(",", "")) / 100
        else: n = parseFloat(st.replace(",", ""))
        isNum = true
      except ValueError: discard
    # Excel reads dates (2026-10-20, 2026/10/20, 10/20/2026) and times (14:30, 14:30:05)
    var date = -1.0
    var dateFmt = ""
    block dates:
      let parts = st.replace('/', '-').split('-')
      if parts.len == 3 and parts.allIt(it.len > 0 and it.allCharsInSet({'0'..'9'})):
        var y, m, d: int
        if parts[0].len == 4: (y, m, d) = (parseInt(parts[0]), parseInt(parts[1]), parseInt(parts[2])); dateFmt = "yyyy-mm-dd"
        elif parts[2].len == 4: (y, m, d) = (parseInt(parts[2]), parseInt(parts[0]), parseInt(parts[1])); dateFmt = "m/d/yyyy"
        else: break dates
        if m in 1..12 and d >= 1 and d <= daysIn(y, m):
          date = fromCivil(y, m, d)
      let tp = st.split(':')
      if date < 0 and tp.len in 2..3 and tp.allIt(it.len in 1..2 and it.allCharsInSet({'0'..'9'})):
        let h = parseInt(tp[0])
        let mi = parseInt(tp[1])
        let sec = if tp.len == 3: parseInt(tp[2]) else: 0
        if h < 24 and mi < 60 and sec < 60:
          date = (float64(h) * 3600 + float64(mi) * 60 + float64(sec)) / 86400
          dateFmt = if tp.len == 3: "hh:mm:ss" else: "hh:mm"
    if date >= 0:
      result.value = numVal(date)
      if wb.styles[old.style].numFmt.len == 0:
        var st2 = wb.styles[old.style]
        st2.numFmt = dateFmt
        result.style = wb.styleId(st2)
    elif isNum: result.value = numVal(n)
    elif cmpIgnoreCase(st, "TRUE") == 0: result.value = boolVal(true)
    elif cmpIgnoreCase(st, "FALSE") == 0: result.value = boolVal(false)
    else: result.value = strVal(t)

proc editorText(v: SheetView): string = v.editor.getStr("innerText").strip(leading = false, chars = {'\n'})

proc caretToEnd(n: Node) =
  let sel = window.invoke("getSelection").toNode
  if sel.isNil: return
  sel.call("selectAllChildren", n)
  sel.call("collapseToEnd")

proc parkEditor(v: SheetView) =
  ## The idle input box sits off-screen (luckysheet-input-box top: -10000px)
  ## with the editor focused, so typing starts an edit (luckysheetactiveCell).
  v.inputBox.removeAttribute("style")
  v.editor.setProp("textContent", "")
  for id in ["luckysheet-wa-functionbox-cancel", "luckysheet-wa-functionbox-confirm"]:
    let b = byId(id)
    if not b.isNil: b.removeClass("luckysheet-wa-calculate-active")

proc editRange(v: SheetView): (int, int, int, int) =
  let s = v.sheet
  let mi = s.mergeAt(v.ar, v.ac)
  if mi >= 0: (let m = s.merges[mi]; (m.r1, m.c1, m.r2, m.c2)) else: (v.ar, v.ac, v.ar, v.ac)

proc centerEditor(v: SheetView) =
  ## setCenterInputPosition (updateCell.js:264-310): a centred cell's box stays
  ## centred on the cell as its text grows.
  let s = v.sheet
  if v.wb.styles[s.cellAt(v.ar, v.ac).style].hAlign != haCenter: return
  let (_, c1, _, c2) = v.editRange()
  let colPre = s.colX(c1)
  let col = s.colX(c2 + 1)
  let left = v.scrX(colPre) + v.root.rect.left + RowHeaderW - 2
  let minW = col - colPre + 1 - 8
  let maxW = window.getNum("innerWidth") * 2 / 3
  let width = max(min(v.inputBox.rect.width - 8, maxW), minW)   # jQuery .width(): the content box
  v.inputBox.style("left", px(max(left - width / 2 + (col - colPre) / 2, 2.0) - 2))

proc runCss(base: Style, run: RichRun): string =
  ## A run's font as inline CSS for the editor (every property, so a run
  ## can undo the cell's own bold / italic).
  let st = runStyle(base, run)
  result = "font-weight:" & (if st.bold: "bold" else: "normal") & ";font-style:" & (if st.italic: "italic" else: "normal") &
    ";text-decoration:" & (if st.underline and st.strike: "underline line-through" elif st.underline: "underline" elif st.strike: "line-through" else: "none") & ";"
  if run.color.len > 0: result.add "color:" & run.color & ";"
  if run.fontSize > 0: result.add "font-size:" & $run.fontSize & "pt;"
  if run.font.len > 0: result.add "font-family:" & run.font & ";"

proc richHtml(base: Style, runs: seq[RichRun]): string =
  for run in runs:
    result.add "<span style=\"" & runCss(base, run) & "\">" &
      run.text.multiReplace(("&", "&amp;"), ("<", "&lt;"), (">", "&gt;"), ("\n", "<br>")) & "</span>"

proc editorRuns(v: SheetView, base: Style): seq[RichRun] =
  ## The editor's formatted text as runs: <b> <i> <u> <s> <font color>, inline
  ## styles (what the browser's bold / italic / … commands write), <br> and
  ## line <div>s; neighbouring runs of one font join.
  proc push(runs: var seq[RichRun], run: RichRun) =
    if run.text.len == 0: return
    if runs.len > 0 and runs[^1].sameFont(run): runs[^1].text.add run.text
    else: system.add(runs, run)
  proc walk(n: Node, cur: RichRun, runs: var seq[RichRun], first: var bool) =
    let kids = n.getNode("childNodes")
    let count = int(kids.getNum("length"))
    for i in 0 ..< count:
      let k = kids.invoke("item", i).toNode
      let t = int(k.getNum("nodeType"))
      if t == 3:
        var run = cur
        run.text = k.getStr("data")
        runs.push run
        first = false
      elif t == 1:
        let tag = k.getStr("tagName").toUpperAscii
        var run = cur
        run.text = ""
        if tag == "BR":
          run.text = "\n"; runs.push run; first = false; k.release(); continue
        if tag in ["DIV", "P"] and not first:
          run.text = "\n"; runs.push run
          run.text = ""
        case tag
        of "B", "STRONG": run.bold = true
        of "I", "EM": run.italic = true
        of "U": run.underline = true
        of "S", "STRIKE", "DEL": run.strike = true
        of "FONT":
          let col = k.invoke("getAttribute", "color").toStr
          if col.len > 0: run.color = col
        else: discard
        let css = k.invoke("getAttribute", "style").toStr
        if css.len > 0:
          var st = runStyle(base, run)
          st.applyCss(css)
          let fs = st.fontSize
          run = toRun(st, "")
          if fs == base.fontSize: run.fontSize = 0
          if st.color == base.color: run.color = ""
          if st.font == base.font: run.font = ""
        walk(k, run, runs, first)
      k.release()
    kids.release()
  var runs: seq[RichRun]
  var first = true
  walk(v.activeEd, toRun(base, "").withoutFontOverrides, runs, first)
  result = runs

proc beginEdit*(v: SheetView, initial = "", keep = false, mode = 0) =
  ## luckysheetupdateCell (controllers/updateCell.js): the input box over the
  ## cell, 2 px up and left, min-width w + 1 - 8, min-height h + 1 - 4.
  if v.editing: return
  block:
    let (a, b, c, d) = v.editRange()
    if v.rangeLocked(a, b, c, d): v.protectedMessage(); return
  v.editing = true
  v.editFromFormulaBar = false
  v.editMode = if mode != 0: mode elif keep: 2 else: 1
  v.pointActive = false
  let s = v.sheet
  let cell = s.cellAt(v.ar, v.ac)
  let text = if keep: (if cell.formula.len > 0: cell.formula else: v.wb.displayText(cell)) else: initial
  let mi = s.mergeAt(v.ar, v.ac)
  let (r1, c1, r2, c2) = if mi >= 0: (let m = s.merges[mi]; (m.r1, m.c1, m.r2, m.c2)) else: (v.ar, v.ac, v.ar, v.ac)
  let colPre = s.colX(c1)
  let col = s.colX(c2 + 1)
  let rowPre = s.rowY(r1)
  let row = s.rowY(r2 + 1)
  let rootRect = v.root.rect
  let sl = v.sbX.getNum("scrollLeft")
  let st = v.sbY.getNum("scrollTop")
  let left = v.scrX(colPre) + rootRect.left + RowHeaderW - 2
  let top = v.scrY(rowPre) + rootRect.top + v.infobarH + v.toolbarH + v.calcbarH + ColHeaderH - 2
  let winW = window.getNum("innerWidth")
  let winH = window.getNum("innerHeight")
  let stl = v.wb.styles[cell.style]
  let maxH = winH - v.scrY(rowPre) - 20 - 15 - v.toolbarH - v.infobarH - v.calcbarH - v.sheetBarH - v.statBarH
  let minW = col - colPre + 1 - 8
  let minH = min(row - rowPre + 1 - 4, maxH)
  # the box: white, 10pt (the editor inherits luckysheet-input-box's arial),
  # the cell's own fill (getStyleByCell), positioned by its alignment
  var css = "background-color: rgb(255, 255, 255); padding: 0px 2px; font-size: " & $DefaultFontSize &
    "pt; right: auto; overflow-y: auto; box-sizing: initial; display: flex;"
  # getStyleByCell + getFontStyleByCell (menuButton.js:5210, getdata.js:328)
  if stl.fill.len > 0: css.add " background: " & stl.fill & ";"
  case stl.hAlign
  of haCenter: css.add " text-align: center;"
  of haRight: css.add " text-align: right;"
  else: discard
  case stl.vAlign
  of vaMiddle: css.add " vertical-align: middle;"
  of vaTop: css.add " vertical-align: top;"
  of vaBottom: css.add " vertical-align: bottom;"
  else: discard
  if stl.underline: css.add " text-decoration:underline;"
  if stl.bold: css.add " font-weight: bold;"
  if stl.italic: css.add " font-style:italic;"
  if stl.font.len > 0: css.add " font-family: " & stl.font & ";"
  if stl.fontSize > 0: css.add " font-size: " & $stl.fontSize & "pt;"
  if stl.color.len > 0 and cmpIgnoreCase(stl.color, "#000000") != 0: css.add " color: " & stl.color & ";"
  if stl.strike: css.add " text-decoration: line-through;"
  let centre = stl.hAlign == haCenter
  var maxW = winW - v.scrX(colPre) - 20 - RowHeaderW
  if centre: maxW = winW * 2 / 3
  if stl.hAlign == haRight:
    maxW = v.scrX(col) + rootRect.left - 8
    css.add " right: " & px(winW - (rootRect.left + (RowHeaderW - 1)) - v.scrX(col)) & ";"
  else:
    css.add " left: " & px(left) & ";"
  css.add " top: " & px(top) & "; min-width: " & px(min(minW, maxW)) & "; min-height: " & px(minH) &
    "; max-width: " & px(maxW) & "; max-height: " & px(maxH) & ";"
  v.inputBox.setAttribute("style", css)
  if stl.hAlign == haRight: v.inputBox.style("left", "")
  for id in ["luckysheet-wa-functionbox-cancel", "luckysheet-wa-functionbox-confirm"]:
    let b = byId(id)
    if not b.isNil: b.addClass("luckysheet-wa-calculate-active")
  v.editor.focus(true)
  if keep and cell.rich.len > 0 and cell.formula.len == 0:
    # a rich cell edits as formatted text
    let html = richHtml(stl, cell.rich)
    v.editor.setProp("innerHTML", html)
    v.fxBar.setProp("innerHTML", html)
    v.setCaret(u16Len(richText(cell.rich)))
  else:
    v.renderEditor(text, int(text.toRunes.len + text.toRunes.filterIt(int32(it) > 0xFFFF).len))
  if centre: v.centerEditor()   # by its own width (updateCell.js:232-248)

proc endEdit*(v: SheetView, commit: bool) =
  if not v.editing: return
  var text = (if v.editFromFormulaBar: v.fxBar else: v.editor).getStr("textContent")
  let base = v.wb.styles[v.sheet.cellAt(v.ar, v.ac).style]
  var runs: seq[RichRun]
  if commit and not (text.len > 0 and text[0] == '='):
    runs = v.editorRuns(base)
    text = richText(runs)
  v.clearFormulaUI()
  v.editing = false
  v.editFromFormulaBar = false
  v.parkEditor()
  if commit:
    let old = v.sheet.cellAt(v.ar, v.ac)
    var act: Action
    var cell: Cell
    var uniform = true
    for r in runs:
      if not r.sameFont(runs[0]): uniform = false
    if runs.len == 0 or (uniform and runs[0].sameFont(toRun(base, "").withoutFontOverrides)):
      cell = parseInput(v.wb, text, old)                        # plain text
    elif uniform:
      # one font for the whole text: the cell's own style changes (Excel)
      var st = runStyle(base, runs[0])
      cell = parseInput(v.wb, text, Cell(style: v.wb.styleId(st)))
    else:
      cell = Cell(style: old.style, value: strVal(text), rich: runs)   # rich text is text
    if v.entryRejected(cell):
      v.refreshFormulaBar(); v.requestDraw()
      v.stopAlert(text)
      return
    v.setCellRaw(v.wb.active, v.ar, v.ac, cell, act)
    v.commitAction(act)
  v.refreshFormulaBar()
  v.editor.focus(true)
  v.requestDraw()

proc moveTo*(v: SheetView, r, c: int, extend = false) =
  let rr = clamp(r, 0, MaxRows - 1)
  let cc = clamp(c, 0, MaxCols - 1)
  v.reach(rr, cc)
  v.extraRanges.setLen(0)
  if extend:
    v.cr = rr; v.cc = cc
  else:
    v.ar = rr; v.ac = cc; v.cr = rr; v.cc = cc
    v.snapAnchor()
  v.scrollIntoView(rr, cc)
  v.refreshFormulaBar()
  v.showSelection()
  v.requestDraw()

proc jump(v: SheetView, r, c, dr, dc: int): (int, int) =
  ## Ctrl+arrow: to the edge of the current block of filled cells.
  let s = v.sheet
  var rr = r
  var cc = c
  let filled = s.hasCell(r, c)
  let nextFilled = s.hasCell(r + dr, c + dc)
  if filled and nextFilled:
    while rr + dr >= 0 and cc + dc >= 0 and rr + dr < s.rowCount and cc + dc < s.colCount and s.hasCell(rr + dr, cc + dc):
      rr += dr; cc += dc
  else:
    rr += dr; cc += dc
    while rr >= 0 and cc >= 0 and rr < max(s.maxRow, 1) + 1 and cc < max(s.maxCol, 1) + 1 and not s.hasCell(rr, cc):
      rr += dr; cc += dc
    if rr < 0 or cc < 0 or not s.hasCell(rr, cc):
      rr = if dr > 0: MaxRows - 1 elif dr < 0: 0 else: r      # Excel: the sheet's last row / column
      cc = if dc > 0: MaxCols - 1 elif dc < 0: 0 else: c
  (clamp(rr, 0, MaxRows - 1), clamp(cc, 0, MaxCols - 1))

proc clearSelection*(v: SheetView, formats = false) =
  ## Delete: the contents of every selected range (formats too when asked).
  var ranges = v.extraRanges
  let (a, b, c0, d) = v.selRect()
  ranges.add Range(r1: a, c1: b, r2: c0, c2: d)
  var act: Action
  let s = v.sheet
  for rg in ranges:
    for r in rg.r1 .. min(rg.r2, s.maxRow):
      for c in rg.c1 .. min(rg.c2, s.maxCol):
        if s.hasCell(r, c):
          let old = s.cellAt(r, c)
          v.setCellRaw(v.wb.active, r, c, Cell(style: if formats: 0'i32 else: old.style), act)
  v.commitAction(act)
  v.refreshFormulaBar()
  v.requestDraw()

proc applyAction(v: SheetView, act: Action, forward: bool) =
  for i in 0 ..< act.len:
    let ch = act[if forward: i else: act.len - 1 - i]
    if ch.isMerge: v.wb.sheets[ch.sheet].merges = (if forward: ch.mergesAfter else: ch.mergesBefore)
    elif ch.snapshot:
      let states = if forward: ch.statesAfter else: ch.statesBefore
      for i, st in states:
        if i < v.wb.sheets.len: restoreState(v.wb.sheets[i], st)
    elif ch.sizeKind != 0:
      let s = v.wb.sheets[ch.sheet]
      let value = if forward: ch.sizeAfter else: ch.sizeBefore
      if ch.sizeKind == 1:
        if value != value: s.colWidths.del(ch.c) else: s.colWidths[ch.c] = value
      else:
        if value != value: s.rowHeights.del(ch.r) else: s.rowHeights[ch.r] = value
    else: v.wb.sheets[ch.sheet].putCell(ch.r, ch.c, if forward: ch.after else: ch.before)
  recalc(v.wb)

proc doUndo*(v: SheetView) =
  if v.undo.len == 0: return
  let act = v.undo.pop()
  v.applyAction(act, false)
  v.redo.add act
  if v.onChange != nil: v.onChange()
  v.refreshFormulaBar(); v.showSelection(); v.requestDraw()

proc doRedo*(v: SheetView) =
  if v.redo.len == 0: return
  let act = v.redo.pop()
  v.applyAction(act, true)
  v.undo.add act
  if v.onChange != nil: v.onChange()
  v.refreshFormulaBar(); v.showSelection(); v.requestDraw()

proc styleSelection*(v: SheetView, change: proc(st: var Style)) =
  if v.sheet.protected and not v.editing:
    let (a, b, c, d) = v.selRect()
    if v.rangeLocked(a, b, c, d): v.protectedMessage(); return
  let (r1, c1, r2, c2) = v.selRect()
  if (r2 - r1 + 1) * (c2 - c1 + 1) > 200_000: return
  var act: Action
  for r in r1 .. r2:
    for c in c1 .. c2:
      var cell = v.sheet.cellAt(r, c)
      let base = v.wb.styles[cell.style]
      var st = base
      change(st)
      cell.style = v.wb.styleId(st)
      for run in cell.rich.mitems:
        var rs = runStyle(base, run)
        change(rs)
        let nr = toRun(rs, run.text)
        run.bold = nr.bold; run.italic = nr.italic; run.underline = nr.underline; run.strike = nr.strike
      v.setCellRaw(v.wb.active, r, c, cell, act)
  v.commitAction(act)
  v.requestDraw()

proc activeStyle*(v: SheetView): Style = v.wb.styles[v.sheet.cellAt(v.ar, v.ac).style]

proc toggleMerge*(v: SheetView) =
  ## Merge the selection (keeping only its upper-left value),
  ## or unmerge it when it already holds merged ranges.
  let s = v.sheet
  let (r1, c1, r2, c2) = v.selRect()
  if r2 - r1 > 5000 or c2 - c1 > 500: return
  var act: Action
  var has = false
  for m in s.merges:
    if m.r2 >= r1 and m.r1 <= r2 and m.c2 >= c1 and m.c1 <= c2: has = true
  let before = s.merges
  if has:
    s.removeMerges(r1, c1, r2, c2)
  else:
    if r1 == r2 and c1 == c2: return
    var others = false
    for r in r1 .. r2:
      for c in c1 .. c2:
        if (r != r1 or c != c1) and s.hasCell(r, c) and v.wb.displayText(s.cellAt(r, c)).len > 0: others = true
    if others and not window.invoke("confirm", "Merging keeps only the upper-left value. Merge anyway?").toBool: return
    for r in r1 .. r2:
      for c in c1 .. c2:
        if (r != r1 or c != c1) and s.hasCell(r, c):
          v.setCellRaw(v.wb.active, r, c, Cell(style: s.cellAt(r, c).style), act)
    s.addMerge(Merge(r1: r1, c1: c1, r2: r2, c2: c2))
  act.add Change(sheet: v.wb.active, isMerge: true, mergesBefore: before, mergesAfter: s.merges)
  v.ar = r1; v.ac = c1; v.cr = r2; v.cc = c2
  v.snapAnchor()
  v.commitAction(act)
  v.refreshFormulaBar()
  v.showSelection()
  v.requestDraw()

proc applyBorders*(v: SheetView, mode: string) =
  ## all, outside, top, bottom, left, right, thick (outside), none
  let (r1, c1, r2, c2) = v.selRect()
  if (r2 - r1 + 1) * (c2 - c1 + 1) > 200_000: return
  let thin = Border(kind: bkThin)
  let thick = Border(kind: bkThick)
  var act: Action
  for r in r1 .. r2:
    for c in c1 .. c2:
      var cell = v.sheet.cellAt(r, c)
      var st = v.wb.styles[cell.style]
      case mode
      of "none": st.left = Border(); st.right = Border(); st.top = Border(); st.bottom = Border()
      of "all": st.left = thin; st.right = thin; st.top = thin; st.bottom = thin
      of "outside", "thick":
        let b = if mode == "thick": thick else: thin
        if r == r1: st.top = b
        if r == r2: st.bottom = b
        if c == c1: st.left = b
        if c == c2: st.right = b
      of "top": (if r == r1: st.top = thin)
      of "bottom": (if r == r2: st.bottom = thin)
      of "left": (if c == c1: st.left = thin)
      of "right": (if c == c2: st.right = thin)
      else: discard
      let id = v.wb.styleId(st)
      if id != cell.style:
        cell.style = id
        v.setCellRaw(v.wb.active, r, c, cell, act)
  v.commitAction(act)
  v.requestDraw()

proc fillDown*(v: SheetView, right = false) =
  ## Ctrl+D / Ctrl+R: copy the first row (column) of the selection over the rest.
  let (r1, c1, r2, c2) = v.selRect()
  var act: Action
  let s = v.sheet
  if right:
    for r in r1 .. r2:
      let src = s.cellAt(r, c1)
      for c in c1 + 1 .. c2:
        var cell = src
        if cell.formula.len > 0: cell.setFormula(shiftFormula(src.formula, 0, c - c1))
        v.setCellRaw(v.wb.active, r, c, cell, act)
  else:
    for c in c1 .. c2:
      let src = s.cellAt(r1, c)
      for r in r1 + 1 .. r2:
        var cell = src
        if cell.formula.len > 0: cell.setFormula(shiftFormula(src.formula, r - r1, 0))
        v.setCellRaw(v.wb.active, r, c, cell, act)
  v.commitAction(act)
  v.requestDraw()

include editor

# ------------------------------------------------------------------ mouse --

proc mousePosition(v: SheetView, cx, cy: float64): (float64, float64) =
  ## mouseposition (global/location.js:72): from the container's corner past
  ## the row header and the bars above the column header.
  let r = v.root.rect
  (cx - r.left - RowHeaderW, cy - r.top - v.infobarH - v.toolbarH - v.calcbarH - ColHeaderH)

proc contentPoint(v: SheetView, e: Event): (float64, float64) =
  ## mouseposition plus #luckysheet-cell-main's scroll.
  let (x, y) = v.mousePosition(e.clientX, e.clientY)
  (v.cx(x), v.cy(y))

proc hitCell(v: SheetView, x, y: float64): (int, int) =
  let s = v.sheet
  (clamp(s.rowAt(max(0.0, y)), 0, s.rowCount - 1), clamp(s.colAt(max(0.0, x)), 0, s.colCount - 1))

proc firstRange(v: SheetView): (int, int, int, int) =
  ## luckysheet_select_save[0]
  if v.extraRanges.len > 0: (let r = v.extraRanges[0]; (r.r1, r.c1, r.r2, r.c2)) else: v.selRect()

proc hasPartMerge(s: Sheet, r1, c1, r2, c2: int): bool =
  ## hasPartMC: a merge that the range cuts through
  for m in s.merges:
    let meets = m.r2 >= r1 and m.r1 <= r2 and m.c2 >= c1 and m.c1 <= c2
    let inside = m.r1 >= r1 and m.r2 <= r2 and m.c1 >= c1 and m.c2 <= c2
    if meets and not inside: return true

proc hasMerge(s: Sheet, r1, c1, r2, c2: int): bool =
  for m in s.merges:
    if m.r2 >= r1 and m.r1 <= r2 and m.c2 >= c1 and m.c1 <= c2: return true

proc tooltipInfo(v: SheetView, title, content: string) =
  ## tooltip.info (global/tooltip.js:8-30): a modal with a Close button.
  let mask = byId("luckysheet-modal-dialog-mask")
  if not mask.isNil: mask.style("display", "block")
  let old = byId("luckysheet-info")
  if not old.isNil: old.remove()
  let box = el("div", "luckysheet-modal-dialog")
  box.setAttribute("id", "luckysheet-info")
  box.setAttribute("style", "z-index:100003")
  box.setAttribute("tabindex", "0"); box.setAttribute("role", "dialog"); box.setAttribute("dir", "ltr")
  box.setProp("innerHTML", " <div class=\"luckysheet-modal-dialog-title luckysheet-modal-dialog-title-draggable\"> <span class=\"luckysheet-modal-dialog-title-text\" role=\"heading\">" &
    title & "</span>\t <span class=\"luckysheet-modal-dialog-title-close\" role=\"button\" tabindex=\"0\"><i class=\"fa fa-times\" aria-hidden=\"true\"></i></span> </div> <div class=\"luckysheet-modal-dialog-content\">" &
    content & "</div> <div class=\"luckysheet-modal-dialog-buttons\">\t <button class=\"btn btn-default luckysheet-model-close-btn\">&nbsp;&nbsp;Close&nbsp;&nbsp;</button> </div>")
  discard document.query("body").add box
  box.query(".luckysheet-modal-dialog-content").style("min-width", "300px")
  let w = box.getNum("offsetWidth")
  let h = box.getNum("offsetHeight")
  box.style("left", px((window.getNum("innerWidth") - w) / 2))
  box.style("top", px((window.getNum("innerHeight") - h) / 3))
  box.style("display", "block")
  for b_1 in box.queryAll(".luckysheet-modal-dialog-title-close, .luckysheet-model-close-btn"):
    let b_0 = b_1
    closureScope:
      let b = b_0
      b.on("click", proc(e: Event) =
        box.style("display", "none")
        if not mask.isNil: mask.style("display", "none"))

proc removeDropIcon(v: SheetView) =
  if not v.dropIcon.isNil: v.dropIcon.remove(); v.dropIcon = Node(0)
  if not v.dropMenu.isNil: v.dropMenu.style("display", "none")

proc applyDrop(v: SheetView) =
  ## luckysheetDropCell.update(): fill the apply range from the copy range.
  let cells = dropFill(v.wb, v.sheet, v.dropCopy, v.dropApply, v.dropDir, v.dropType, v.dropAuto)
  var act: Action
  for (r, c, cell) in cells: v.setCellRaw(v.wb.active, r, c, cell, act)
  v.commitAction(act)
  v.refreshFormulaBar(); v.showSelection(); v.requestDraw()

proc showDropMenu(v: SheetView)

proc createDropIcon(v: SheetView) =
  ## luckysheetDropCell.createIcon (dropCell.js:272-382): the auto fill
  ## options button at the corner of the filled range.
  let s = v.sheet
  let (_, _, cr2, cc2) = v.dropCopy
  let (_, _, ar2, ac2) = v.dropApply
  let (row, col) = if ar2 >= cr2 and ac2 >= cc2: (ar2, ac2) else: (cr2, cc2)
  v.removeDropIcon()
  let icon = el("div")
  icon.setAttribute("id", "luckysheet-dropCell-icon")
  icon.setAttribute("style", "position: absolute;padding: 2px;background-color: #f1f1f1;z-index: 990;cursor: pointer;")
  icon.setProp("innerHTML", "<div id=\"icon_dropCell\"></div>")
  discard v.cellMain.add icon
  icon.style("left", px(s.colX(col + 1))); icon.style("top", px(s.rowY(row + 1)))
  icon.on("mouseover", proc(e: Event) = icon.style("background-color", "#ffe8e8"))
  icon.on("mouseleave", proc(e: Event) = icon.style("background-color", "#f1f1f1"))
  icon.on("mousedown", proc(e: Event) =
    e.stopPropagation(); e.preventDefault()
    v.showDropMenu())
  v.dropIcon = icon

proc showDropMenu(v: SheetView) =
  ## The fill type list (typeListHtml), en locale.
  const Labels = ["Copy", "Sequence", "Only format", "Not format", "Day", "Work Day", "Month", "Year", "Chinese numbers"]
  if not v.dropMenu.isNil: v.dropMenu.remove()
  let menu = el("div", "luckysheet-cols-menu luckysheet-rightgclick-menu luckysheet-mousedown-cancel")
  menu.setAttribute("id", "luckysheet-dropCell-typeList")
  var html = ""
  for i, label in Labels:
    html.add "<div class=\"luckysheet-cols-menuitem luckysheet-mousedown-cancel\" data-type=\"" & $i & "\">" &
      "<div class=\"luckysheet-cols-menuitem-content luckysheet-mousedown-cancel\" style=\"padding: 3px 2px;\">" &
      "<span style=\"margin-right:5px;width:13px;display:inline-block;\" class=\"icon luckysheet-mousedown-cancel\"></span>" & label & "</div></div>"
  menu.setProp("innerHTML", html)
  discard document.query("body").add menu
  let (r1, c1, r2, c2) = v.dropCopy
  let k = fillKinds(v.wb, v.sheet, r1, c1, r2, c2)
  var hide: seq[int]
  if not (k[0] or k[1] or k[2] or k[3] or k[4] or k[5] or k[6]): hide.add [1, 4, 5, 6, 7, 8]
  if not k[2]: hide.add [4, 5, 6, 7]
  if not k[3]: hide.add 8
  for i in hide: menu.query("[data-type=\"" & $i & "\"]").style("display", "none")
  let ir = v.dropIcon.rect
  var left = ir.left
  var top = ir.top + 25
  menu.style("display", "block")
  let mw = menu.getNum("clientWidth")
  let mh = menu.getNum("clientHeight")
  if left + mw > window.getNum("innerWidth"): left -= mw
  if top + mh > window.getNum("innerHeight"): top = top - mh - 38
  if top < 0: top = 0
  menu.style("left", px(left)); menu.style("top", px(top))
  let icon = v.dropIcon
  icon.on("mouseleave", proc(e: Event) = icon.style("background-color", "#ffe8e8"))
  menu.query("[data-type=\"" & $ord(v.dropType) & "\"] span").setProp("innerHTML", "<i class=\"fa fa-check luckysheet-mousedown-cancel\"></i>")
  for item_1 in menu.queryAll(".luckysheet-cols-menuitem"):
    let item_0 = item_1
    closureScope:
      let item = item_0
      let t = parseInt(item.invoke("getAttribute", "data-type").toStr)
      item.on("click", proc(e: Event) =
        v.dropType = FillType(t)
        v.dropAuto = false
        v.applyDrop()
        menu.style("display", "none")
        icon.style("background-color", "#f1f1f1"))
  v.dropMenu = menu

proc autoFillDown(v: SheetView) =
  ## The fill handle's dblclick (handler.js:4716-4830): fill down as far as
  ## the column left (and/or right) of the range has values.
  let s = v.sheet
  let (r0, c0, r1, c1) = v.firstRange()
  var state = false
  var step = 0
  proc has(r, c: int): bool = s.hasCell(r, c) and s.cellAt(r, c).value.kind != vkEmpty
  for r in r1 + 1 ..< s.rowCount:
    var filled: bool
    if c0 - 1 >= 0 and c1 + 1 < s.colCount: filled = has(r, c0 - 1) or has(r, c1 + 1)
    elif c0 - 1 >= 0: filled = has(r, c0 - 1)
    elif c1 + 1 < s.colCount: filled = has(r, c1 + 1)
    else: break
    if not filled:
      if r == r1 + 1: state = false
      break
    state = true; inc step
  if not state or step == 0: return
  v.dropCopy = (r0, c0, r1, c1)
  v.dropType = defaultFillType(fillKinds(v.wb, s, r0, c0, r1, c1)); v.dropAuto = true
  v.dropApply = (r1 + 1, c0, r1 + step, c1)
  v.dropDir = fdDown
  v.extraRanges.setLen(0)
  v.ar = r0; v.ac = c0; v.cr = r1 + step; v.cc = c1
  v.applyDrop()
  v.createDropIcon()
  v.selMove.style("display", "none")

proc autofitColumns(v: SheetView, e: Event) =
  ## luckysheetcolsdbclick (rowColumnOperation.js:2446-2560): the column
  ## under the pointer — or every column of the selections containing it —
  ## gets its widest text + 6 over the visible rows and as many again below;
  ## nothing changes for a column whose text fits the default width.
  v.resizing = 0
  v.sizeLine.style("display", "none")
  v.colsChangeSize.style("opacity", "0")
  let s = v.sheet
  let x = v.cx(v.mousePosition(e.clientX, e.clientY)[0])
  let colIndex = clamp(s.colAt(max(0.0, x)), 0, s.colCount - 1)
  let st = v.cellMain.getNum("scrollTop")
  let rowSt = clamp(s.rowAt(st), 0, s.rowCount - 1)
  var rowEd = clamp(s.rowAt(st + v.tableH), 0, s.rowCount - 1)
  rowEd += rowEd - rowSt
  if rowEd >= s.rowCount: rowEd = s.rowCount - 1
  var ranges = v.extraRanges
  let (a, b, c, d) = v.selRect()
  ranges.add Range(r1: a, c1: b, r2: c, c2: d)
  var done: seq[int]
  var act: Action
  proc fit(col: int) =
    if col in done: return
    var len = DefaultColWidth
    for r in rowSt .. rowEd:
      if not s.hasCell(r, col): continue
      let cell = s.cellAt(r, col)
      if cell.value.kind == vkEmpty: continue
      let text = v.wb.displayText(cell)
      let w = measureCell(fontOf(v.wb.styles[cell.style]), text)[0]
      if w + 6 > len: len = w + 6
    if len != DefaultColWidth:
      act.add Change(sheet: v.wb.active, sizeKind: 1, c: col, sizeBefore: s.colWidths.getOrDefault(col, NaN), sizeAfter: len)
      s.colWidths[col] = len
    done.add col
  for rg in ranges:
    if colIndex < rg.c1 or colIndex > rg.c2: fit(colIndex)
    else:
      for col in rg.c1 .. rg.c2: fit(col)
  v.commitAction(act)
  v.removeDropIcon()
  v.applyExtent(); v.showSelection(); v.requestDraw()

include clipboard
include structure
include ribbon
include sheets
include program
include charts
include diagram
include dialogs
include layout7
include filter
include condformat
include validation
include find
include notes
include pictures
include pivot

proc placeOverlays(v: SheetView) =
  ## the DOM floating over the cells after a scroll or a change: filter
  ## buttons, pictures, the list arrow, notes (each skips when unchanged)
  v.placeFilterButtons()
  v.renderPictures()
  v.placeDvButton()
  if v.sheet.notes.len > 0 or hoverKey >= 0: v.showNotes()


proc onCellMouseDown(v: SheetView, e: Event) =
  ## #luckysheet-cell-main mousedown (handler.js:296-1245)
  if e.target.matches(".luckysheet-mousedown-cancel, .luckysheet-mousedown-cancel *"): return
  let r = v.cellMain.rect
  if e.clientX - r.left >= v.cellMainW - ScrollBar or e.clientY - r.top >= v.cellMainH - ScrollBar: return
  let (x, y) = v.contentPoint(e)
  let (row, col) = v.hitCell(x, y)
  let (r1, c1, r2, c2) = v.selRect()
  if e.button == 2 and row >= r1 and row <= r2 and col >= c1 and col <= c2: return   # right-click inside keeps it
  if v.editing and e.button == 0 and (v.pointActive or v.canPoint()):
    # Excel's Point mode with the mouse: the click (drag) becomes a reference
    # in the formula; Ctrl adds another one after a comma.
    e.preventDefault()
    if v.pointActive and (e.ctrlKey or e.metaKey):
      let text = v.edText
      let at = u16ToByte(text, v.pointEnd)
      let t = text[0 ..< at] & "," & text[at .. ^1]
      v.pointActive = false
      v.renderEditor(t, v.pointEnd + 1)
    elif v.pointActive:
      v.setCaret(v.pointEnd)
    v.pointAt(row, col, row, col)
    v.selecting = 8; v.scrollStatus = true
    return
  v.removeDropIcon()
  v.deselectPicture()
  if v.editing: v.endEdit(true)
  if e.button == 0 and not e.shiftKey and not (e.ctrlKey or e.metaKey): v.linkMouseDown(row, col)
  if e.shiftKey:
    # extend from the focus cell
    v.cr = row; v.cc = col
  elif e.ctrlKey or e.metaKey:
    let (a, b, cc2, d) = v.selRect()
    v.extraRanges.add Range(r1: a, c1: b, r2: cc2, c2: d)
    v.ar = row; v.ac = col; v.cr = row; v.cc = col
    v.snapAnchor()
  else:
    v.extraRanges.setLen(0)
    v.ar = row; v.ac = col; v.cr = row; v.cc = col
    v.snapAnchor()
  # a partly hidden cell scrolls into view by its left/top edge (handler.js:405-412)
  let s = v.sheet
  if col >= s.frozenCols and s.colX(col) - v.frozenW < v.sbX.getNum("scrollLeft"): v.sbX.setProp("scrollLeft", s.colX(col) - v.frozenW)
  if row >= s.frozenRows and s.rowY(row) - v.frozenH < v.sbY.getNum("scrollTop"): v.sbY.setProp("scrollTop", s.rowY(row) - v.frozenH)
  if e.button == 0: v.selecting = 1; v.scrollStatus = true
  e.preventDefault()
  v.refreshFormulaBar()
  v.showSelection()
  v.editor.focus(true)

proc mouseRender(v: SheetView, cx, cy: float64) =
  ## handler.js mouseRender (2119-3604), for one loop's mouse position:
  ## auto-scroll past the edges, then the drag in progress.
  let (mx, my) = v.mousePosition(cx, cy)
  if v.scrollStatus and v.resizing == 0:
    let winH = v.cellMainH - 20
    let winW = v.cellMainW - 60
    if my < 0 or my > winH:
      let top = v.sbY.getNum("scrollTop")
      v.sbY.setProp("scrollTop", if my < 0: top + my / 2 else: top + (my - winH) / 2)
    if mx < 0 or mx > winW:
      let left = v.sbX.getNum("scrollLeft")
      v.sbX.setProp("scrollLeft", if mx < 0: left + mx / 2 else: left + (mx - winW) / 2)
  let s = v.sheet
  case v.selecting
  of 1:
    let (row, col) = v.hitCell(v.cx(mx), v.cy(my))
    if row != v.cr or col != v.cc:
      v.cr = row; v.cc = col
      v.refreshFormulaBar(); v.showSelection()
  of 4:
    let x = v.cx(mx)
    if x < 0: return
    let col = clamp(s.colAt(x), 0, s.colCount - 1)
    if col != v.cc:
      v.cc = col
      v.refreshFormulaBar(); v.showSelection()
  of 5:
    let y = v.cy(my)
    if y < 0: return
    let row = clamp(s.rowAt(y), 0, s.rowCount - 1)
    if row != v.cr:
      v.cr = row
      v.refreshFormulaBar(); v.showSelection()
  of 8:
    let (row, col) = v.hitCell(v.cx(mx), v.cy(my))
    if (row, col) != v.pointFocus:
      v.pointAt(v.pointAnchor[0], v.pointAnchor[1], row, col)
  of 6, 7:
    # moving cells (handler.js:2620-2690) / the fill handle (2691-2787)
    let ext = v.selecting == 7
    let sl = v.cellMain.getNum("scrollLeft") - (if ext: 5.0 else: 0.0)
    let st = v.cellMain.getNum("scrollTop") - (if ext: 5.0 else: 0.0)
    let x = v.cx(mx) - (if ext: 5.0 else: 0.0)
    let y = v.cy(my) - (if ext: 5.0 else: 0.0)
    let winH = window.getNum("innerHeight") + st - v.sheetBarH - v.statBarH
    let winW = window.getNum("innerWidth") + sl
    let rowIndex = clamp(s.rowAt(max(0.0, y)), 0, s.rowCount - 1)
    let colIndex = clamp(s.colAt(max(0.0, x)), 0, s.colCount - 1)
    let (f1, g1, f2, g2) = v.firstRange()
    let (ri, ci) = if ext: v.extendIndex else: v.moveIndex
    var rowS = if ext: f1 else: f1 - ri + rowIndex
    var rowE = if ext: f2 else: f2 - ri + rowIndex
    var colS = if ext: g1 else: g1 - ci + colIndex
    var colE = if ext: g2 else: g2 - ci + colIndex
    if rowS < 0 or y < 0: rowS = 0; rowE = f2 - f1
    if colS < 0 or x < 0: colS = 0; colE = g2 - g1
    # (Luckysheet compares an index with a pixel position here)
    if float64(rowE) >= s.rowY(s.rowCount) or y > winH: rowS = s.rowCount - 1 - f2 + f1; rowE = s.rowCount - 1
    if float64(colE) >= s.colX(s.colCount) or x > winW: colS = s.colCount - 1 - g2 + g1; colE = s.colCount - 1
    if not ext:
      let left = s.colX(colS)
      let top = s.rowY(rowS)
      let (bl, bt, bw, bh) = v.rangeBox(rowS, colS, rowE, colE)
      discard (left, top)
      v.selMove.setAttribute("style", "left: " & px(bl) & "; width: " & px(bw - 1) &
        "; top: " & px(bt) & "; height: " & px(bh - 1) & "; display: block;")
    else:
      var (left, top, width, height) = v.rangeBox(f1, g1, f2, g2)
      let rowPre = v.ay(s.rowY(rowIndex))
      let row = v.ay(s.rowY(rowIndex + 1))
      let colPre = v.ax(s.colX(colIndex))
      let col = v.ax(s.colX(colIndex + 1))
      let (lt, lh, ll, lw) = (top, height, left, width)
      if abs(ri - rowIndex) > abs(ci - colIndex):
        if not (rowIndex >= rowS and rowIndex <= rowE):
          if lt >= rowPre: top = rowPre; height = lt + lh - rowPre
          else: top = lt; height = row - lt - 1
      else:
        if not (colIndex >= colS and colIndex <= colE):
          if ll >= colPre: left = colPre; width = ll + lw - colPre
          else: left = ll; width = col - ll - 1
      v.selExtend.setAttribute("style", "left: " & px(left) & "; width: " & px(width) & "; top: " & px(top) &
        "; height: " & px(height) & "; display: block;")
  else: discard
  case v.resizing
  of 1:                                            # handler.js:2788-2805
    let sl = v.colsHC.getNum("scrollLeft")
    let x = mx + sl
    if x + 3 - v.resizePre > 30 and x < window.getNum("innerWidth") + sl - 100:
      v.sizeLine.style("left", px(x)); v.colsChangeSize.style("left", px(x - 2))
  of 2:                                            # handler.js:2806-2820
    let st = v.rowsH.getNum("scrollTop")
    let y = my + st
    if y + 3 - v.resizePre > 19 and y < window.getNum("innerHeight") + st - 200:
      v.sizeLine.style("top", px(y)); v.rowsChangeSize.style("top", px(y))
  else: discard

proc onDocMouseMove(v: SheetView, e: Event) =
  ## document mousemove (handler.js:2100-3607): while a drag is on, every move
  ## starts one more requestAnimationFrame(mouseRender) loop that renders its
  ## own position each frame until mouseup, so auto-scroll speeds up the more
  ## the mouse moves, as in Luckysheet.
  if v.selecting == 0 and v.resizing == 0 and not v.scrollStatus: return
  let loop = DragLoop(x: e.clientX, y: e.clientY, alive: true)
  v.dragLoops.add loop
  proc frame(now: float64) =
    if not loop.alive: return
    v.mouseRender(loop.x, loop.y)
    requestAnimationFrame(frame)
  requestAnimationFrame(frame)

proc selectedLines(v: SheetView, index: int, columns: bool): seq[int] =
  ## The whole columns (rows) selected, when `index` is one of them; else just it.
  let s = v.sheet
  var ranges = v.extraRanges
  let (a, b, c, d) = v.selRect()
  ranges.add Range(r1: a, c1: b, r2: c, c2: d)
  proc whole(rg: Range): bool =
    if columns: rg.r1 == 0 and rg.r2 >= s.rowCount - 1 else: rg.c1 == 0 and rg.c2 >= s.colCount - 1
  proc span(rg: Range): (int, int) = (if columns: (rg.c1, rg.c2) else: (rg.r1, rg.r2))
  for rg in ranges:
    if rg.whole and index in rg.span[0] .. rg.span[1]:
      for rg2 in ranges:
        if rg2.whole:
          for i in rg2.span[0] .. rg2.span[1]: result.add i
      return
  result = @[index]

proc finishResize(v: SheetView, e: Event) =
  ## document mouseup after a column / row size drag (handler.js:3912-4110):
  ## the size at the line, for every selected whole column / row containing
  ## it; undoable.
  let (mx, my) = v.mousePosition(e.clientX, e.clientY)
  let s = v.sheet
  v.sizeLine.style("display", "none")
  var act: Action
  if v.resizing == 1:
    v.colsChangeSize.style("opacity", "0")
    let sl = v.colsHC.getNum("scrollLeft")
    let x = mx + sl
    let winW = window.getNum("innerWidth")
    var size = x + 3 - v.resizePre
    if abs(size - s.colWidth(v.resizeIndex)) < 3: return
    if x + 3 - v.resizePre < 30: size = 30
    if x >= winW - 100 + sl: size = winW - 100 - v.resizePre + sl
    size = ceil(size)
    for c in v.selectedLines(v.resizeIndex, true):
      act.add Change(sheet: v.wb.active, sizeKind: 1, c: c, sizeBefore: s.colWidths.getOrDefault(c, NaN), sizeAfter: size)
      s.colWidths[c] = size
  else:
    v.rowsChangeSize.style("opacity", "0")
    let st = v.rowsH.getNum("scrollTop")
    let y = my + st
    let winH = window.getNum("innerHeight")
    var size = y + 3 - v.resizePre
    if y + 3 - v.resizePre < 19: size = 19
    if y >= winH - 200 + st: size = winH - 200 - v.resizePre + st
    size = ceil(size)
    for r in v.selectedLines(v.resizeIndex, false):
      act.add Change(sheet: v.wb.active, sizeKind: 2, r: r, sizeBefore: s.rowHeights.getOrDefault(r, NaN), sizeAfter: size)
      s.rowHeights[r] = size
  v.commitAction(act)
  v.removeDropIcon()
  v.applyExtent(); v.showSelection(); v.requestDraw()

proc finishMove(v: SheetView, e: Event) =
  ## mouseup after dragging the selection's border (handler.js:4122-4398):
  ## the cells (values, formulas as written, styles, merges) move.
  v.selMove.style("display", "none")
  let s = v.sheet
  let (mx, my) = v.mousePosition(e.clientX, e.clientY)
  let x = v.cx(mx)
  let y = v.cy(my)
  let winH = window.getNum("innerHeight") + v.cellMain.getNum("scrollTop") - v.sheetBarH - v.statBarH
  let winW = window.getNum("innerWidth") + v.cellMain.getNum("scrollLeft")
  let rowIndex = clamp(s.rowAt(max(0.0, y)), 0, s.rowCount - 1)
  let colIndex = clamp(s.colAt(max(0.0, x)), 0, s.colCount - 1)
  let (ri, ci) = v.moveIndex
  if rowIndex == ri and colIndex == ci: return
  let (l1, k1, l2, k2) = v.selRect()                  # the last range
  if s.hasPartMerge(l1, k1, l2, k2):
    v.tooltipInfo("<i class=\"fa fa-exclamation-triangle\"></i>", "Cannot perform this operation on merged cells"); return
  var rowS = l1 - ri + rowIndex
  var rowE = l2 - ri + rowIndex
  var colS = k1 - ci + colIndex
  var colE = k2 - ci + colIndex
  if rowS < 0 or y < 0: rowS = 0; rowE = l2 - l1
  if colS < 0 or x < 0: colS = 0; colE = k2 - k1
  if float64(rowE) >= s.rowY(s.rowCount) or y > winH: rowS = s.rowCount - 1 - l2 + l1; rowE = s.rowCount - 1
  if float64(colE) >= s.colX(s.colCount) or x > winW: colS = s.colCount - 1 - k2 + k1; colE = s.colCount - 1
  if s.hasPartMerge(rowS, colS, rowE, colE):
    v.tooltipInfo("<i class=\"fa fa-exclamation-triangle\"></i>", "Cannot perform this operation on merged cells"); return
  var data: seq[(int, int, Cell)]
  for r in l1 .. l2:
    for c in k1 .. k2: data.add (r - l1 + rowS, c - k1 + colS, s.cellAt(r, c))
  var act: Action
  let mergesBefore = s.merges
  var moved: seq[Merge]
  var kept: seq[Merge]
  for m in s.merges:
    if m.r1 >= l1 and m.r2 <= l2 and m.c1 >= k1 and m.c2 <= k2:
      moved.add Merge(r1: m.r1 - l1 + rowS, c1: m.c1 - k1 + colS, r2: m.r2 - l1 + rowS, c2: m.c2 - k1 + colS)
    else: kept.add m
  for r in l1 .. l2:
    for c in k1 .. k2:
      if s.hasCell(r, c): v.setCellRaw(v.wb.active, r, c, Cell(), act)
  for (r, c, cell) in data: v.setCellRaw(v.wb.active, r, c, cell, act)
  # merges the destination covered go; the moved ones land
  var after: seq[Merge]
  for m in kept:
    if not (m.r2 >= rowS and m.r1 <= rowE and m.c2 >= colS and m.c1 <= colE): after.add m
  after.add moved
  s.merges = after
  act.add Change(sheet: v.wb.active, isMerge: true, mergesBefore: mergesBefore, mergesAfter: after)
  # the focus keeps its corner (row_focus at the start -> row_s, else row_e)
  let focusTop = v.ar == l1
  let focusLeft = v.ac == k1
  v.extraRanges.setLen(0)
  v.ar = if focusTop: rowS else: rowE
  v.ac = if focusLeft: colS else: colE
  v.cr = if focusTop: rowE else: rowS
  v.cc = if focusLeft: colE else: colS
  v.commitAction(act)
  v.refreshFormulaBar(); v.showSelection(); v.requestDraw()

proc finishExtend(v: SheetView, e: Event) =
  ## mouseup after dragging the fill handle (handler.js:4400-4608).
  v.selExtend.style("display", "none")
  let s = v.sheet
  let (mx, my) = v.mousePosition(e.clientX, e.clientY)
  let x = v.cx(mx) - 5
  let y = v.cy(my) - 5
  let winH = window.getNum("innerHeight") + v.cellMain.getNum("scrollTop") - v.sheetBarH - v.statBarH
  let winW = window.getNum("innerWidth") + v.cellMain.getNum("scrollLeft")
  let rowIndex = clamp(s.rowAt(max(0.0, y)), 0, s.rowCount - 1)
  let colIndex = clamp(s.colAt(max(0.0, x)), 0, s.colCount - 1)
  let rowPre = s.rowY(rowIndex)
  let colPre = s.colX(colIndex)
  let (ri, ci) = v.extendIndex
  let (l1, k1, l2, k2) = v.selRect()
  var rowS = l1
  var rowE = l2
  var colS = k1
  var colE = k2
  if rowS < 0 or y < 0: rowS = 0; rowE = l2 - l1
  if colS < 0 or x < 0: colS = 0; colE = k2 - k1
  if float64(rowE) >= s.rowY(s.rowCount) or y > winH: rowS = s.rowCount - 1 - l2 + l1; rowE = s.rowCount - 1
  if float64(colE) >= s.colX(s.colCount) or x > winW: colS = s.colCount - 1 - k2 + k1; colE = s.colCount - 1
  v.dropCopy = (l1, k1, l2, k2)
  v.dropType = defaultFillType(fillKinds(v.wb, s, l1, k1, l2, k2)); v.dropAuto = true
  let (f1, g1, _, _) = v.firstRange()
  if abs(ri - rowIndex) > abs(ci - colIndex):
    if rowIndex >= rowS and rowIndex <= rowE: return
    if s.rowY(f1) >= rowPre:
      v.dropApply = (rowIndex, k1, l1 - 1, k2); v.dropDir = fdUp
      rowS -= l1 - rowIndex
    else:
      v.dropApply = (l2 + 1, k1, rowIndex, k2); v.dropDir = fdDown
      rowE += rowIndex - l2
  else:
    if colIndex >= colS and colIndex <= colE: return
    if s.colX(g1) >= colPre:
      v.dropApply = (l1, colIndex, l2, k1 - 1); v.dropDir = fdLeft
      colS -= k1 - colIndex
    else:
      v.dropApply = (l1, k2 + 1, l2, colIndex); v.dropDir = fdRight
      colE += colIndex - k2
  if s.hasMerge(rowS, colS, rowE, colE):
    v.tooltipInfo("Cannot perform this operation on merged cells", ""); return
  # the selection becomes the whole filled range, focus kept
  v.extraRanges.setLen(0)
  let focusTop = v.ar == l1
  let focusLeft = v.ac == k1
  v.ar = if focusTop: rowS else: rowE
  v.ac = if focusLeft: colS else: colE
  v.cr = if focusTop: rowE else: rowS
  v.cc = if focusLeft: colE else: colS
  v.applyDrop()
  v.createDropIcon()
  v.selMove.style("display", "none")

proc onDocMouseUp(v: SheetView, e: Event) =
  ## document mouseup (handler.js:3608-3720)
  for loop in v.dragLoops: loop.alive = false
  v.dragLoops.setLen(0)
  if v.selecting == 8: v.editor.focus(true)
  if v.selecting == 1 and v.painting: v.finishPainter()
  if v.selecting == 1 and not v.painting:
    let (x, y) = v.contentPoint(e)
    let (r, c) = v.hitCell(x, y)
    v.linkMouseUp(r, c)
  if v.selecting == 6: v.finishMove(e)
  elif v.selecting == 7: v.finishExtend(e)
  if v.resizing != 0: v.finishResize(e)
  v.selecting = 0
  v.resizing = 0
  v.scrollStatus = false

proc onColsHeaderMove(v: SheetView, e: Event) =
  ## #luckysheet-cols-h-c mousemove (rowColumnOperation.js:934-964)
  if v.selecting != 0 or v.resizing != 0:
    v.colsHHover.style("display", "none")
    v.colsMenuBtn.style("display", "none")
    return
  let s = v.sheet
  let x = v.cx(v.mousePosition(e.clientX, e.clientY)[0])
  let c = clamp(s.colAt(x), 0, s.colCount - 1)
  let colPre = s.colX(c)
  let col = s.colX(c + 1)
  v.colsHHover.style("left", px(colPre)); v.colsHHover.style("width", px(col - colPre - 1))
  v.colsHHover.style("display", "block")
  v.colsMenuBtn.style("left", px(col - 19)); v.colsMenuBtn.style("display", "block")
  v.colsChangeSize.style("left", px(col - 5))
  if x < col and x >= col - 5: v.colsMenuBtn.style("display", "none")

proc onRowsHeaderMove(v: SheetView, e: Event) =
  if v.selecting != 0 or v.resizing != 0:
    v.rowsHHover.style("display", "none")
    return
  let s = v.sheet
  let y = v.cy(v.mousePosition(e.clientX, e.clientY)[1])
  let r = clamp(s.rowAt(y), 0, s.rowCount - 1)
  let rowPre = s.rowY(r)
  let row = s.rowY(r + 1)
  v.rowsHHover.style("top", px(rowPre)); v.rowsHHover.style("height", px(row - rowPre - 1))
  v.rowsHHover.style("display", "block")
  if y < row - 1 and y >= row - 5: v.rowsChangeSize.style("top", px(row - 3))

proc onColsHeaderDown(v: SheetView, e: Event) =
  ## column title mousedown (rowColumnOperation.js:575): whole columns.
  if e.target.matches("#luckysheet-cols-change-size, .luckysheet-mousedown-cancel, .luckysheet-mousedown-cancel *"): return
  let s = v.sheet
  let x = v.cx(v.mousePosition(e.clientX, e.clientY)[0])
  let c = clamp(s.colAt(x), 0, s.colCount - 1)
  if v.editing: v.endEdit(true)
  if e.button == 2 and c >= min(v.ac, v.cc) and c <= max(v.ac, v.cc) and v.ar == 0 and v.cr == s.rowCount - 1: return
  if e.shiftKey: v.cc = c
  else:
    if e.ctrlKey or e.metaKey:
      let (a, b, cc2, d) = v.selRect()
      v.extraRanges.add Range(r1: a, c1: b, r2: cc2, c2: d)
    else: v.extraRanges.setLen(0)
    v.ac = c; v.cc = c
  v.ar = 0; v.cr = s.rowCount - 1
  v.selecting = 4; v.scrollStatus = true
  e.preventDefault()
  v.refreshFormulaBar(); v.showSelection()
  v.editor.focus(true)

proc onRowsHeaderDown(v: SheetView, e: Event) =
  ## row title mousedown (rowColumnOperation.js:34): whole rows.
  if e.target.matches("#luckysheet-rows-change-size, .luckysheet-mousedown-cancel, .luckysheet-mousedown-cancel *"): return
  let s = v.sheet
  let y = v.cy(v.mousePosition(e.clientX, e.clientY)[1])
  let r = clamp(s.rowAt(y), 0, s.rowCount - 1)
  if v.editing: v.endEdit(true)
  if e.button == 2 and r >= min(v.ar, v.cr) and r <= max(v.ar, v.cr) and v.ac == 0 and v.cc == s.colCount - 1: return
  if e.shiftKey: v.cr = r
  else:
    if e.ctrlKey or e.metaKey:
      let (a, b, cc2, d) = v.selRect()
      v.extraRanges.add Range(r1: a, c1: b, r2: cc2, c2: d)
    else: v.extraRanges.setLen(0)
    v.ar = r; v.cr = r
  v.ac = 0; v.cc = s.colCount - 1
  v.selecting = 5; v.scrollStatus = true
  e.preventDefault()
  v.refreshFormulaBar(); v.showSelection()
  v.editor.focus(true)

# --------------------------------------------------------------- keyboard --

proc arrowDelta(k: string): (int, int) =
  case k
  of "ArrowDown": (1, 0)
  of "ArrowUp": (-1, 0)
  of "ArrowLeft": (0, -1)
  else: (0, 1)

proc moveInSelection(v: SheetView, down: bool, back: bool) =
  ## Excel's Enter / Tab: with one cell selected, the next cell (the selection
  ## follows); with a range, the active cell walks the range, wrapping, and the
  ## range stays.
  let (r1, c1, r2, c2) = v.selRect()
  let s = v.sheet
  if (r1 == r2 and c1 == c2) or (s.mergeAt(r1, c1) >= 0 and (let m = s.merges[s.mergeAt(r1, c1)]; m.r1 == r1 and m.c1 == c1 and m.r2 == r2 and m.c2 == c2)):
    let (r, c) = s.stepFrom(v.ar, v.ac, (if down: (if back: -1 else: 1) else: 0), (if down: 0 else: (if back: -1 else: 1)))
    v.moveTo(r, c); return
  var r = v.ar
  var c = v.ac
  let step = if back: -1 else: 1
  if down:
    r += step
    if r > r2: r = r1; c += 1
    if r < r1: r = r2; c -= 1
    if c > c2: c = c1
    if c < c1: c = c2
  else:
    c += step
    if c > c2: c = c1; r += 1
    if c < c1: c = c2; r -= 1
    if r > r2: r = r1
    if r < r1: r = r2
  # keep the range: only the active cell moves
  let (a, b, e2, f) = (r1, c1, r2, c2)
  v.ar = r; v.ac = c
  v.cr = if r == a: e2 else: a
  v.cc = if c == b: f else: b
  # the moving corner must still span the range
  if v.ar == a: v.cr = e2
  elif v.ar == e2: v.cr = a
  else: v.cr = (if r - a < e2 - r: e2 else: a)
  if v.ac == b: v.cc = f
  elif v.ac == f: v.cc = b
  else: v.cc = (if c - b < f - c: f else: b)
  v.scrollIntoView(r, c)
  v.refreshFormulaBar(); v.showSelection(); v.requestDraw()

proc fillSelectionWith(v: SheetView, text: string) =
  ## Ctrl+Enter: the entry into every selected cell (formulas relative to each).
  let (r1, c1, r2, c2) = v.selRect()
  var act: Action
  let s = v.sheet
  for r in r1 .. r2:
    for c in c1 .. c2:
      var cell = parseInput(v.wb, text, s.cellAt(r, c))
      if cell.formula.len > 0: cell.setFormula(shiftFormula(cell.formula, r - v.ar, c - v.ac))
      v.setCellRaw(v.wb.active, r, c, cell, act)
  v.commitAction(act)

proc nowText(time: bool): string =
  let d = construct("Date")
  proc two(x: float64): string = (if x < 10: "0" else: "") & $int(x)
  result = if time: two(d.invoke("getHours").toNum) & ":" & two(d.invoke("getMinutes").toNum)
           else: $int(d.invoke("getFullYear").toNum) & "-" & two(d.invoke("getMonth").toNum + 1) & "-" & two(d.invoke("getDate").toNum)
  d.release()

proc isFormulaText(v: SheetView): bool =
  let t = v.edText
  t.len > 0 and t[0] == '='

proc insertAtCaret(v: SheetView, ins: string) =
  if not v.isFormulaText:
    # keep the text's formatting: the browser inserts at the caret
    discard execCommand(if ins == "\n": "insertLineBreak" else: "insertText", ins, ins != "\n")
    return
  let text = v.edText
  let caret = max(0, v.caretOffset)
  let at = u16ToByte(text, caret)
  v.renderEditor(text[0 ..< at] & ins & text[at .. ^1], caret + u16Len(ins))

proc onKeyDown(v: SheetView, e: Event) =
  ## Excel's keyboard (the user's choice over Luckysheet's keyboard.js).
  let k = e.key
  let ctrl = e.ctrlKey or e.metaKey
  if v.editing:
    if e.eventObject.getBool("isComposing"): return
    # keyboard.js:918: a typing key re-centres a centred box before the key lands
    if k.len == 1 or k in ["Backspace", "Delete"]: v.centerEditor()
    let listOpen = v.searchItems.len > 0
    case k
    of "Enter":
      e.preventDefault()
      if e.altKey: v.insertAtCaret("\n"); return             # a new line in the cell
      if ctrl:
        let text = v.edText
        v.endEdit(false)
        v.fillSelectionWith(text)
        v.refreshFormulaBar(); v.showSelection(); v.requestDraw()
        return
      v.endEdit(true)
      v.moveInSelection(true, e.shiftKey)
    of "Tab":
      e.preventDefault()
      if listOpen: v.acceptSearch(); return
      v.endEdit(true)
      v.moveInSelection(false, e.shiftKey)
    of "Escape":
      e.preventDefault()
      if listOpen: v.hideSearch(); return
      v.endEdit(false)
    of "F2":
      e.preventDefault()
      v.editMode = if v.editMode == 2: 1 else: 2
      v.pointActive = false
    of "F4":
      e.preventDefault(); v.toggleAbsolute()
    of "ArrowDown", "ArrowUp", "ArrowLeft", "ArrowRight":
      if listOpen and k in ["ArrowDown", "ArrowUp"]:
        e.preventDefault()
        v.searchActive = clamp(v.searchActive + (if k == "ArrowDown": 1 else: -1), 0, v.searchItems.high)
        v.renderSearch()
        return
      if v.editMode == 2: return                            # Edit mode: the caret moves
      let (dr, dc) = arrowDelta(k)
      if v.pointActive or v.canPoint():
        e.preventDefault(); v.pointMove(dr, dc, e.shiftKey)
      elif not v.editFromFormulaBar:
        e.preventDefault()
        v.endEdit(true)
        let (r, c) = v.sheet.stepFrom(v.ar, v.ac, dr, dc); v.moveTo(r, c)
    of ";", ":":
      if ctrl:
        e.preventDefault(); v.insertAtCaret(nowText(e.shiftKey or k == ":"))
    of "b", "B", "i", "I", "u", "U", "5":
      if ctrl:
        # Excel: in a cell's text, the selected part (or what is typed next)
        e.preventDefault()
        if not v.isFormulaText:
          discard execCommand(case k.toLowerAscii
            of "b": "bold"
            of "i": "italic"
            of "u": "underline"
            else: "strikeThrough")
    else: discard
    return
  if ctrl:
    case toLowerAscii(k)
    of "z": e.preventDefault(); v.doUndo()
    of "y": e.preventDefault(); v.doRedo()
    of "f": e.preventDefault(); v.openFind()
    of "h": e.preventDefault(); v.openFind(replace = true)
    of "k": e.preventDefault(); v.linkDialog()
    of "p": e.preventDefault(); v.printSheet()
    of "l":
      if e.shiftKey: e.preventDefault(); v.toggleFilter()
    of "b": e.preventDefault(); v.styleSelection(proc(st: var Style) = st.bold = not v.activeStyle.bold)
    of "i": e.preventDefault(); v.styleSelection(proc(st: var Style) = st.italic = not v.activeStyle.italic)
    of "u": e.preventDefault(); v.styleSelection(proc(st: var Style) = st.underline = not v.activeStyle.underline)
    of "5": e.preventDefault(); v.styleSelection(proc(st: var Style) = st.strike = not v.activeStyle.strike)
    of "d": e.preventDefault(); v.fillDown()
    of "r": e.preventDefault(); v.fillDown(right = true)
    of "a":
      e.preventDefault(); v.extraRanges.setLen(0)
      v.ar = 0; v.ac = 0; v.cr = v.sheet.rowCount - 1; v.cc = v.sheet.colCount - 1
      v.refreshFormulaBar(); v.showSelection()
    of " ":
      # Ctrl+Space: the active cell's whole column
      e.preventDefault(); v.extraRanges.setLen(0)
      v.ar = 0; v.cr = v.sheet.rowCount - 1; v.cc = v.ac
      v.refreshFormulaBar(); v.showSelection()
    of ";", ":":
      e.preventDefault()
      v.beginEdit(nowText(e.shiftKey or k == ":"))
    of "arrowdown", "arrowup", "arrowleft", "arrowright":
      e.preventDefault()
      let (dr, dc) = arrowDelta(k)
      let fromR = if e.shiftKey: v.cr else: v.ar
      let fromC = if e.shiftKey: v.cc else: v.ac
      let (r, c) = v.jump(fromR, fromC, dr, dc)
      v.moveTo(r, c, e.shiftKey)
    of "home": e.preventDefault(); v.moveTo(0, 0, e.shiftKey)
    of "end": e.preventDefault(); v.moveTo(max(v.sheet.maxRow - 1, 0), max(v.sheet.maxCol - 1, 0), e.shiftKey)
    of "pagedown", "pageup":
      e.preventDefault()
      let step = if toLowerAscii(k) == "pagedown": 1 else: -1
      var i = v.wb.active + step
      while i >= 0 and i < v.wb.sheets.len and v.wb.sheets[i].hidden: i += step
      if i >= 0 and i < v.wb.sheets.len: v.activate(i)
    else: discard
    return
  let pageRows = max(1, int(v.cellMainH / (DefaultRowHeight + 1)) - 1)
  let baseR = if e.shiftKey: v.cr else: v.ar
  let baseC = if e.shiftKey: v.cc else: v.ac
  case k
  of "ArrowDown", "ArrowUp", "ArrowLeft", "ArrowRight":
    e.preventDefault()
    if e.altKey and k == "ArrowDown": v.openDvList(); return       # a list's dropdown (Excel)
    let (dr, dc) = arrowDelta(k)
    let (r, c) = v.sheet.stepFrom(baseR, baseC, dr, dc)
    v.moveTo(r, c, e.shiftKey)
  of "PageDown": e.preventDefault(); v.moveTo(baseR + pageRows, baseC, e.shiftKey)
  of "PageUp": e.preventDefault(); v.moveTo(baseR - pageRows, baseC, e.shiftKey)
  of "Home": e.preventDefault(); v.moveTo(baseR, 0, e.shiftKey)
  of "Enter": e.preventDefault(); v.moveInSelection(true, e.shiftKey)
  of "Tab": e.preventDefault(); v.moveInSelection(false, e.shiftKey)
  of "F2":
    e.preventDefault()
    if e.shiftKey: v.editNote() else: v.beginEdit(keep = true)
  of "Delete":
    e.preventDefault()
    if not v.deleteSelectedPicture(): v.clearSelection()
  of "Escape":
    e.preventDefault(); v.endCopyMode()
    if v.painting: v.finishPainterCancel()
  of "Backspace":
    # Excel: empties the cell into the editor; Esc keeps the old content
    e.preventDefault(); v.beginEdit("", mode = 1)
  of " ":
    if e.shiftKey:
      # Shift+Space: the active cell's whole row
      e.preventDefault(); v.extraRanges.setLen(0)
      v.ac = 0; v.cc = v.sheet.colCount - 1; v.cr = v.ar
      v.refreshFormulaBar(); v.showSelection()
  else: discard

proc onEditorInput(v: SheetView, e: Event) =
  ## Typing: a first key while not editing starts Enter mode with it; while
  ## editing, the text is re-coloured, the list / help follow the caret.
  if e.eventObject.getBool("isComposing"): return      # an IME is composing: wait for compositionend
  if v.editing:
    let text = v.edText
    let caret = v.caretOffset
    v.pointActive = false
    if text.len > 0 and text[0] == '=': v.renderEditor(text, caret)   # formulas are coloured; text keeps its formatting
    else:
      let mirror = if v.editFromFormulaBar: v.editor else: v.fxBar
      mirror.setProp("innerHTML", v.activeEd.getStr("innerHTML"))
      v.showRangeBoxes(text)
    v.updateSearch()
    v.updateHelp()
    return
  let typed = v.editor.getStr("textContent")
  if typed.len == 0: return
  v.editor.setProp("textContent", "")
  v.beginEdit(typed)
  v.updateSearch()
  v.updateHelp()

# -------------------------------------------------------------- sheet bar --

proc activate*(v: SheetView, index: int) =
  if index < 0 or index >= v.wb.sheets.len: return
  if v.editing: v.endEdit(true)
  v.wb.active = index
  v.extraRanges.setLen(0)
  v.ar = 0; v.ac = 0; v.cr = 0; v.cc = 0
  v.sbX.setProp("scrollLeft", 0); v.sbY.setProp("scrollTop", 0)
  v.applyExtent()
  v.rebuildTabs()
  v.refreshFormulaBar()
  v.showSelection()
  v.onScroll()
  if v.hostCall != nil: v.hostCall("sheetActivated", %index)

proc rebuildTabs*(v: SheetView) =
  ## sheetHTML (controllers/constant.js:966) into #luckysheet-sheet-container-c.
  if v.sheetBar.isNil: return
  v.sheetBar.dropChildren()
  for i, s in v.wb.sheets:
    if s.hidden: continue
    closureScope:
      let tab = el("div", "luckysheet-sheets-item" & (if i == v.wb.active: " luckysheet-sheets-item-active" else: ""))
      tab.setAttribute("id", "luckysheet-sheets-item" & $i)
      tab.setAttribute("data-index", $i)
      let name = tab.add el("span", "luckysheet-sheets-item-name")
      name.setAttribute("spellcheck", "false")
      name.setAttribute("contenteditable", "false")
      name.setProp("textContent", s.name)
      discard tab.add createTextNode(" ")
      let menu = tab.add el("span", "luckysheet-sheets-item-menu luckysheet-mousedown-cancel")
      discard menu.add el("i", "fa fa-sort-desc luckysheet-mousedown-cancel")
      let color = tab.add el("div", "luckysheet-sheets-item-color")
      color.setAttribute("style", " position: absolute; width: 100%; height: 3px; bottom: 0px; left: 0px; background-color: " & s.tabColor & ";")
      let idx = i
      tab.on("mousedown", proc(e: Event) =
        if e.target.matches(".luckysheet-sheets-item-menu, .luckysheet-sheets-item-menu *, [contenteditable=true]"): return
        if e.button == 0 or (e.button == 2 and idx != v.wb.active): v.activate(idx))
      tab.on("dblclick", proc(e: Event) = v.beginTabRename(idx))
      tab.on("contextmenu", proc(e: Event) =
        e.preventDefault(); v.showSheetMenu(idx, e.clientX, e.clientY))
      menu.on("mousedown", proc(e: Event) =
        e.preventDefault(); e.stopPropagation()
        let r = tab.rect
        v.showSheetMenu(idx, r.left, r.top))
      discard v.sheetBar.add tab

proc addSheet(v: SheetView) =
  var n = v.wb.sheets.len + 1
  while v.wb.sheetNamed("Sheet" & $n) != nil: inc n
  discard v.wb.addSheet("Sheet" & $n)
  v.activate(v.wb.sheets.len - 1)

# ------------------------------------------------------------------ mount --

proc newSheetView*(wb: Workbook): SheetView =
  ## Binds Luckysheet's page (wasm/index.html) — nothing is created except the
  ## per-sheet DOM Luckysheet builds at runtime (tabs, extra selection boxes).
  let v = SheetView(wb: wb, rec: newCtx())
  v.root = byId("luckysheet")
  v.canvas = byId("luckysheetTableContent")
  v.cellMain = byId("luckysheet-cell-main")
  v.sbX = byId("luckysheet-scrollbar-x")
  v.sbY = byId("luckysheet-scrollbar-y")
  v.sbXInner = v.sbX.query("div")
  v.sbYInner = v.sbY.query("div")
  v.colsHC = byId("luckysheet-cols-h-c")
  v.rowsH = byId("luckysheet-rows-h")
  v.colsCells = byId("luckysheet-cols-h-cells_0")
  v.rowHeaderDiv = byId("luckysheetrowHeader_0")
  v.rowsHSel = byId("luckysheet-rows-h-selected")
  v.colsHSel = byId("luckysheet-cols-h-selected")
  v.rowsHHover = byId("luckysheet-rows-h-hover")
  v.colsHHover = byId("luckysheet-cols-h-hover")
  v.colsChangeSize = byId("luckysheet-cols-change-size")
  v.rowsChangeSize = byId("luckysheet-rows-change-size")
  v.colsMenuBtn = byId("luckysheet-cols-menu-btn")
  v.sizeLine = byId("luckysheet-change-size-line")
  v.rowCountShow = byId("luckysheet-row-count-show")
  v.colCountShow = byId("luckysheet-column-count-show")
  v.selBoxs = byId("luckysheet-cell-selected-boxs")
  v.selMain = byId("luckysheet-cell-selected")
  v.selFocus = byId("luckysheet-cell-selected-focus")
  v.sheettable = byId("luckysheet-sheettable_0")
  v.bottomBar = byId("luckysheet-bottom-controll-row")
  v.addRowInput = byId("luckysheet-bottom-add-row-input")
  v.inputBox = byId("luckysheet-input-box")
  v.editor = byId("luckysheet-rich-text-editor")
  v.fxBar = byId("luckysheet-functionbox-cell")
  v.nameBox = byId("luckysheet-helpbox-cell")
  v.sheetBar = byId("luckysheet-sheet-container-c")
  v.gridContainer = v.root.query(".luckysheet-grid-container")
  v.gridWindow = byId("luckysheet-grid-window-1")
  v.ctx = v.canvas.context2d()
  v.parkEditor()

  # scrolling
  v.sbX.on("scroll", proc(e: Event) = v.onScroll(), passive = true)
  v.sbY.on("scroll", proc(e: Event) = v.onScroll(), passive = true)
  v.gridWindow.on("wheel", proc(e: Event) = v.onWheel(e))
  # cells
  v.cellMain.on("mousedown", proc(e: Event) = v.onCellMouseDown(e))
  v.selMove = byId("luckysheet-cell-selected-move")
  v.selExtend = byId("luckysheet-cell-selected-extend")
  # the selection's border: move the cells (handler.js:4625-4668)
  for h_1 in v.selMain.queryAll(".luckysheet-cs-draghandle"):
    let h_0 = h_1
    closureScope:
      let h = h_0
      h.on("mousedown", proc(e: Event) =
        e.stopPropagation(); e.preventDefault()
        if v.editing: v.endEdit(true)
        v.selecting = 6; v.scrollStatus = true
        let s = v.sheet
        let (x, y) = v.contentPoint(e)
        let (row, col) = v.hitCell(x, y)
        v.moveIndex = (row, col)
        let left = s.colX(col)
        let top = s.rowY(row)
        v.selMove.setAttribute("style", "left: " & px(left) & "; width: " & px(s.colX(col + 1) - left - 1) &
          "; top: " & px(top) & "; height: " & px(s.rowY(row + 1) - top - 1) & "; display: block;"))
  # the fill handle: drag after 100 ms, double-click fills down (handler.js:4670-4830)
  let fill = v.selMain.query(".luckysheet-cs-fillhandle")
  if not fill.isNil:
    fill.on("mousedown", proc(e: Event) =
      e.stopPropagation(); e.preventDefault()
      if v.editing: v.endEdit(true)
      let (x0, y0) = v.contentPoint(e)
      v.extendTimer = setTimeout(100, proc() =
        v.selecting = 7; v.scrollStatus = true
        let s = v.sheet
        let (row, col) = v.hitCell(x0 - 5, y0 - 5)
        v.extendIndex = (row, col)
        let left = s.colX(col)
        let top = s.rowY(row)
        v.selExtend.setAttribute("style", "left: " & px(left) & "; width: " & px(s.colX(col + 1) - left - 1) &
          "; top: " & px(top) & "; height: " & px(s.rowY(row + 1) - top - 1) & "; display: block;")))
    fill.on("click", proc(e: Event) =
      clearTimeout(v.extendTimer); e.stopPropagation())
    fill.on("dblclick", proc(e: Event) =
      e.stopPropagation(); v.autoFillDown())
  # menus close on a press elsewhere
  document.on("mousedown", proc(e: Event) =
    if not v.dropMenu.isNil and not e.target.matches("#luckysheet-dropCell-typeList, #luckysheet-dropCell-typeList *"):
      v.dropMenu.style("display", "none"))
  v.cellMain.on("dblclick", proc(e: Event) =
    if v.editing: return
    if not e.target.matches(".luckysheet-mousedown-cancel, .luckysheet-mousedown-cancel *"): v.beginEdit(keep = true))
  document.on("mousemove", proc(e: Event) = v.onDocMouseMove(e))
  document.on("mouseup", proc(e: Event) = v.onDocMouseUp(e))
  # titles
  v.colsHC.on("mousedown", proc(e: Event) = v.onColsHeaderDown(e))
  v.colsHC.on("mousemove", proc(e: Event) = v.onColsHeaderMove(e))
  v.colsHC.on("mouseleave", proc(e: Event) =
    if v.resizing == 0:
      v.colsHHover.style("display", "none"); v.colsMenuBtn.style("display", "none"))
  v.rowsH.on("mousedown", proc(e: Event) = v.onRowsHeaderDown(e))
  v.rowsH.on("mousemove", proc(e: Event) = v.onRowsHeaderMove(e))
  v.rowsH.on("mouseleave", proc(e: Event) = v.rowsHHover.style("display", "none"))
  v.colsChangeSize.on("mousedown", proc(e: Event) =
    ## #luckysheet-cols-change-size mousedown (rowColumnOperation.js:1180-1215)
    e.preventDefault(); e.stopPropagation()
    if v.editing: v.endEdit(true)
    let s = v.sheet
    v.colsChangeSize.style("opacity", "1")
    let x = v.cx(v.mousePosition(e.clientX, e.clientY)[0])
    v.resizeIndex = clamp(s.colAt(max(0.0, x)), 0, s.colCount - 1)
    v.resizePre = s.colX(v.resizeIndex)
    v.resizing = 1; v.scrollStatus = true
    v.sizeLine.setAttribute("style", "height: " & px(v.cellMainH + v.cellMain.getNum("scrollTop")) &
      "; border-width: 0px 1px 0px 0px; top: 0px; left: " & px(s.colX(v.resizeIndex + 1) - 3) &
      "; width: 1px; display: block; cursor: ew-resize;")
    v.colsHHover.style("display", "none"); v.colsMenuBtn.style("display", "none"))
  v.colsChangeSize.on("dblclick", proc(e: Event) = v.autofitColumns(e))
  v.rowsChangeSize.on("mousedown", proc(e: Event) =
    ## #luckysheet-rows-change-size mousedown (rowColumnOperation.js:1116-1160)
    e.preventDefault(); e.stopPropagation()
    if v.editing: v.endEdit(true)
    let s = v.sheet
    v.rowsChangeSize.style("opacity", "1")
    let y = v.cy(v.mousePosition(e.clientX, e.clientY)[1])
    v.resizeIndex = clamp(s.rowAt(max(0.0, y)), 0, s.rowCount - 1)
    v.resizePre = s.rowY(v.resizeIndex)
    v.resizing = 2; v.scrollStatus = true
    v.sizeLine.setAttribute("style", "height: 1px; border-width: 0px 0px 1px; top: " & px(s.rowY(v.resizeIndex + 1) - 3) &
      "; left: 0px; width: " & px(v.cellMain.getNum("scrollLeft") + v.cellMainW) & "; display: block; cursor: ns-resize;")
    v.rowsHHover.style("display", "none"); v.colsMenuBtn.style("display", "none"))
  # the editor (idle: off-screen, focused)
  v.editor.on("keydown", proc(e: Event) = v.onKeyDown(e))
  v.editor.on("input", proc(e: Event) = v.onEditorInput(e))
  v.editor.on("compositionend", proc(e: Event) = v.onEditorInput(e))
  v.editor.on("mouseup", proc(e: Event) = (if v.editing: v.pointActive = false; v.updateSearch(); v.updateHelp()))
  # clipboard (clipboard.nim): copy / cut put text and an HTML table; cut moves on paste
  proc toClipboard(e: Event, cut: bool) =
    if v.editing: return
    e.preventDefault()
    if not v.copyRanges(): return
    let (text, html) = v.copySelection(cut)
    let data = e.eventObject.getNode("clipboardData")
    data.call("setData", "text/plain", text)
    data.call("setData", "text/html", html)
  v.editor.on("copy", proc(e: Event) = toClipboard(e, false))
  v.editor.on("cut", proc(e: Event) = toClipboard(e, true))
  v.editor.on("paste", proc(e: Event) =
    if v.editing: return
    e.preventDefault()
    let data = e.eventObject.getNode("clipboardData")
    # a picture on the clipboard becomes a picture (Luckysheet's image paste),
    # unless it comes with a table (Excel puts a picture of copied cells too)
    let picture = imageIn(data)
    if not picture.isNil and "<table" notin data.invoke("getData", "text/html").toStr.toLowerAscii:
      v.addPictureFile(picture)
      return
    v.pasting = true
    v.paste(data.invoke("getData", "text/plain").toStr, data.invoke("getData", "text/html").toStr)
    v.pasting = false)
  # formula bar
  # the formula bar: Edit mode in it (Excel), same keys, colours and pointing
  v.fxBar.on("focus", proc(e: Event) =
    if not v.editing:
      v.editing = true
      v.editFromFormulaBar = true
      v.editMode = 2
      v.pointActive = false
      v.showRangeBoxes(v.edText))
  v.fxBar.on("keydown", proc(e: Event) = v.onKeyDown(e))
  v.fxBar.on("input", proc(e: Event) = v.onEditorInput(e))
  v.fxBar.on("compositionend", proc(e: Event) = v.onEditorInput(e))
  # the name box: type A1 or A1:C5 and Enter to go there (Excel)
  v.nameBox.on("focus", proc(e: Event) =
    let sel = window.invoke("getSelection").toNode
    if not sel.isNil: sel.call("selectAllChildren", v.nameBox))
  v.nameBox.on("keydown", proc(e: Event) =
    case e.key
    of "Enter":
      e.preventDefault()
      let t = v.nameBox.getStr("textContent").strip.toUpperAscii
      let refs = formulaRefs("=" & t)
      if refs.len == 1 and refs[0].stop == t.len + 1 and refs[0].sheet.len == 0:
        let rf = refs[0]
        v.extraRanges.setLen(0)
        v.ar = rf.r1; v.ac = rf.c1; v.cr = min(rf.r2, v.sheet.rowCount - 1); v.cc = min(rf.c2, v.sheet.colCount - 1)
        v.scrollIntoView(v.ar, v.ac)
        v.showSelection(); v.requestDraw()
      v.refreshFormulaBar()
      v.editor.focus(true)
    of "Escape":
      e.preventDefault(); v.refreshFormulaBar(); v.editor.focus(true)
    else: discard)
  # formula bar ✕ / ✓ (handler.js #luckysheet-wa-functionbox-cancel / -confirm)
  onClick(byId("luckysheet-wa-functionbox-cancel"), proc() = (if v.editing: v.endEdit(false)))
  onClick(byId("luckysheet-wa-functionbox-confirm"), proc() = (if v.editing: v.endEdit(true)))
  # No "Add [100] more rows" bar (enableAddRow off): the sheet grows like Excel's
  # when data reaches near its bottom (model.rowCount), never by scrolling.
  if not v.bottomBar.isNil: v.bottomBar.style("display", "none")
  # sheet bar "+"
  onClick(byId("luckysheet-sheets-add"), proc() = v.addSheet())
  # toolbar buttons that act directly (the rest come with stage 6)
  let call = proc(name: string): proc() = (proc() = (if v.hostCall != nil: v.hostCall(name, newJNull())))
  onClick(byId("luckysheet-icon-undo"), proc() = v.doUndo())
  onClick(byId("luckysheet-icon-redo"), proc() = v.doRedo())
  proc styleButton(id, cmd: string) =
    ## a font-style button (its own scope: a closure per button)
    let b = byId(id)
    if b.isNil: return
    b.on("mousedown", proc(e: Event) = (if v.editing: e.preventDefault()))   # keep the editor's selection
    b.on("click", proc(e: Event) =
      if v.editing:
        if not v.isFormulaText: discard execCommand(cmd)
        return
      v.styleSelection(proc(st: var Style) =
        case cmd
        of "bold": st.bold = not v.activeStyle.bold
        of "italic": st.italic = not v.activeStyle.italic
        of "strikeThrough": st.strike = not v.activeStyle.strike
        else: st.underline = not v.activeStyle.underline))
  styleButton("luckysheet-icon-bold", "bold")
  styleButton("luckysheet-icon-italic", "italic")
  styleButton("luckysheet-icon-strikethrough", "strikeThrough")
  styleButton("luckysheet-icon-underline", "underline")

  # the app's top bar (Save_toServer.js bindToolbar)
  let upload = byId("xlsxUpload")
  if not upload.isNil:
    upload.on("change", proc(e: Event) =
      let file = upload.getNode("files").invoke("item", 0).toNode
      if not file.isNil and v.onOpenFile != nil: v.onOpenFile(file)
      upload.setProp("value", ""))
  onClick(byId("downloadFile"), call("save"))
  onClick(byId("exportCSV"), call("csv"))
  onClick(byId("saveToServer"), call("saveServer"))
  proc relayout() =
    v.sizeAuto(); v.showSelection(); v.requestDraw()
  window.on("resize", proc(e: Event) = relayout())
  # A page in an iframe that starts hidden (the QOQORO workspace's sheet pane)
  # gets no resize event when it is shown: watch the container's size.
  proc watch() =
    if v.root.getNum("clientWidth") != v.sizedW or v.root.getNum("clientHeight") != v.sizedH: relayout()
    setTimeout(400, watch)
  setTimeout(400, watch)

  v.moreDiv = byId("luckysheet-icon-morebtn-div")
  v.moreBtn = byId("luckysheet-icon-morebtn")
  v.toggleTopBar = byId("luckysheet-icon-toggle-topbar")
  v.lastTextColor = "#ff0000"; v.lastFillColor = "#ffff00"; v.lastBorder = "all"
  v.hideInfobar = true          # the app's top bar: its commands live in the ribbon (File, Insert, Formulas)
  v.buildRibbon()
  v.bindRibbon()
  v.bindSheetMenu()
  v.loadFunctions()
  v.bindContextMenu()
  v.bindProgram()
  v.bindFilter()
  v.bindPictureDrop()
  v.bindValidation()
  v.cellMain.on("mousemove", proc(e: Event) = v.onCellHover(e))
  v.cellMain.on("mouseleave", proc(e: Event) = (if hoverKey >= 0: hoverKey = -1; v.showNotes()))
  onClick(byId("insertChartBtn"), proc() = v.openChartDialog())
  onClick(byId("openDiagramEditor"), proc() = v.openDiagram())
  onClick(byId("exportOPJU"), call("opju"))
  v.sizeAuto()
  v.applyExtent()
  v.rebuildTabs()
  v.refreshFormulaBar()
  v.showSelection()
  v.onScroll()
  v.editor.focus(true)
  v
