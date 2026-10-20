## The toolbar as an Excel-style ribbon, included into view.nim: Luckysheet's
## own toolbar buttons (their look and icons) gathered into Excel's tabs and
## named groups, the way QoWrite's ribbon (qnote-nim-wasm/nim-src/ribbon.nim)
## does: collapsed, a tab's groups run on one line; expanded (▾ / ▴), each
## group stacks its rows over its name. When the window is narrow the least
## important commands fold away instead of the bar scrolling.
##
## Commands Excel has but this sheet does not do yet are shown greyed.

const
  RibbonKey = "qoqorosheet-ribbon-expanded"
  # (tab, label, groups: (name, rows of element ids))
  RibbonTabs = [
    ("file", "File", @[
      ("File", @[@["qs-cmd-open", "qs-cmd-save"], @["qs-cmd-save-server"]]),
      ("Export", @[@["qs-cmd-csv", "qs-cmd-opju"], @["luckysheet-icon-print"]])]),
    ("home", "Home", @[
      ("Undo", @[@["luckysheet-icon-undo"], @["luckysheet-icon-redo"]]),
      ("Clipboard", @[@["luckysheet-icon-paintformat"]]),
      ("Font", @[@["luckysheet-icon-font-family", "luckysheet-icon-font-size"],
                 @["luckysheet-icon-bold", "luckysheet-icon-italic", "luckysheet-icon-underline", "luckysheet-icon-strikethrough",
                   "luckysheet-icon-border-all", "luckysheet-icon-border-menu", "luckysheet-icon-cell-color", "luckysheet-icon-cell-color-menu",
                   "luckysheet-icon-text-color", "luckysheet-icon-text-color-menu"]]),
      ("Alignment", @[@["luckysheet-icon-valign", "luckysheet-icon-valign-menu", "luckysheet-icon-textwrap", "luckysheet-icon-textwrap-menu"],
                      @["luckysheet-icon-align", "luckysheet-icon-align-menu", "luckysheet-icon-rotation", "luckysheet-icon-rotation-menu",
                        "luckysheet-icon-merge-button", "luckysheet-icon-merge-menu"]]),
      ("Number", @[@["luckysheet-icon-fmt-other"],
                   @["luckysheet-icon-currency", "luckysheet-icon-percent", "luckysheet-icon-fmt-decimal-increase", "luckysheet-icon-fmt-decimal-decrease"]]),
      ("Editing", @[@["luckysheet-icon-function", "luckysheet-icon-function-menu"], @["luckysheet-icon-autofilter", "luckysheet-icon-seachmore"]])]),
    ("insert", "Insert", @[
      ("Tables", @[@["luckysheet-pivot-btn-title"], @["qs-cmd-pivot-refresh"]]),
      ("Illustrations", @[@["luckysheet-insertImg-btn-title"]]),
      ("Links", @[@["luckysheet-insertLink-btn-title"]]),
      ("Comments", @[@["luckysheet-icon-postil"]])]),
    ("formulas", "Formulas", @[
      ("Function Library", @[@["qs-cmd-sum", "qs-cmd-average", "qs-cmd-count"], @["qs-cmd-max", "qs-cmd-min"]])]),
    ("data", "Data", @[
      ("Sort & Filter", @[@["qs-cmd-sort-asc", "qs-cmd-sort-desc"], @["qs-cmd-filter", "qs-cmd-filter-clear"]]),
      ("Data Tools", @[@["luckysheet-icon-conditionformat", "luckysheet-dataVerification-btn-title"], @["qs-cmd-cf-manage"]])]),
    ("review", "Review", @[
      ("Find", @[@["qs-cmd-find"], @["qs-cmd-replace"]]),
      ("Notes", @[@["qs-cmd-note-new", "qs-cmd-note-delete"], @["qs-cmd-notes-all"]]),
      ("Protect", @[@["luckysheet-icon-protection", "qs-cmd-protect"], @["qs-cmd-lock"]])]),
    ("misc", "Misc", @[
      ("Programs", @[@["qs-cmd-program"]]),
      ("Charts", @[@["qs-cmd-chart"]]),
      ("Diagrams", @[@["qs-cmd-diagram"]]),
      ("Window", @[@["luckysheet-freezen-btn-horizontal", "luckysheet-icon-freezen-menu"], @["qs-cmd-freeze-row", "qs-cmd-freeze-col"]])])]
  # not done yet (stage 7): greyed, like Excel's unavailable commands
  RibbonDisabled: seq[string] = @[]
  # 1 folds last, 9 first; unlisted: 5
  RibbonPriority = {"luckysheet-icon-undo": 1, "luckysheet-icon-redo": 1, "luckysheet-icon-bold": 1, "luckysheet-icon-italic": 1,
    "luckysheet-icon-font-size": 1, "luckysheet-icon-font-family": 2, "luckysheet-icon-underline": 2, "luckysheet-icon-fmt-other": 2,
    "luckysheet-icon-text-color": 2, "luckysheet-icon-cell-color": 2, "luckysheet-icon-merge-button": 3, "luckysheet-icon-align": 3,
    "luckysheet-icon-border-all": 3, "luckysheet-icon-function": 3, "luckysheet-icon-strikethrough": 6, "luckysheet-icon-paintformat": 4,
    "luckysheet-icon-fmt-decimal-increase": 6, "luckysheet-icon-fmt-decimal-decrease": 6, "luckysheet-icon-rotation": 9,
    "luckysheet-icon-textwrap": 8, "luckysheet-icon-autofilter": 8, "luckysheet-icon-seachmore": 8}.toTable
  Fonts = ["Times New Roman", "Arial", "Tahoma", "Verdana", "Calibri", "Cambria", "Courier New", "Georgia", "Segoe UI", "Meiryo", "Yu Gothic", "MS Gothic"]
  Sizes = [9, 10, 11, 12, 14, 16, 18, 20, 22, 24, 26, 28, 36, 48, 72]
  Formats = [("Automatic", ""), ("Plain text", "@"), ("Number", "#,##0.00"), ("Percent", "0.00%"), ("Scientific", "0.00E+00"),
    ("Currency", "¥#,##0.00"), ("Accounting", "¥#,##0.00;-¥#,##0.00"), ("Date", "yyyy-mm-dd"), ("Time", "hh:mm:ss"),
    ("Date time", "yyyy-mm-dd hh:mm:ss"), ("Integer", "0"), ("One decimal", "0.0")]
  Palette = ["#000000", "#434343", "#666666", "#999999", "#b7b7b7", "#cccccc", "#d9d9d9", "#efefef", "#f3f3f3", "#ffffff",
    "#980000", "#ff0000", "#ff9900", "#ffff00", "#00ff00", "#00ffff", "#4a86e8", "#0000ff", "#9900ff", "#ff00ff",
    "#e6b8af", "#f4cccc", "#fce5cd", "#fff2cc", "#d9ead3", "#d0e0e3", "#c9daf8", "#cfe2f3", "#d9d2e9", "#ead1dc",
    "#dd7e6b", "#ea9999", "#f9cb9c", "#ffe599", "#b6d7a8", "#a2c4c9", "#a4c2f4", "#9fc5e8", "#b4a7d6", "#d5a6bd",
    "#cc4125", "#e06666", "#f6b26b", "#ffd966", "#93c47d", "#76a5af", "#6d9eeb", "#6fa8dc", "#8e7cc3", "#c27ba0",
    "#a61c00", "#cc0000", "#e69138", "#f1c232", "#6aa84f", "#45818e", "#3c78d8", "#3d85c6", "#674ea7", "#a64d79"]
  RibbonCss = """
#qs-ribbon-tabs{display:flex;align-items:stretch;gap:2px;padding:0 8px;height:32px;box-sizing:border-box;background:#1e1e2e;border-bottom:1px solid #2d2d44;font:13px "Segoe UI",Arial,sans-serif;user-select:none}
#qs-ribbon-tabs .qs-tab{display:flex;align-items:center;padding:0 12px;color:#bac2de;cursor:pointer;border:0;border-bottom:2px solid transparent;outline:none;box-shadow:none;background:none}
#qs-ribbon-tabs .qs-tab:hover{color:#cdd6f4;background:#2d2d44}
#qs-ribbon-tabs .qs-tab.active{color:#f38ba8;border-bottom-color:#f38ba8;font-weight:600}
#luckysheet-wa-editor.qs-ribbon{position:relative;display:flex;align-items:stretch;flex-wrap:nowrap;overflow:hidden;white-space:nowrap;padding-right:44px}
#luckysheet-wa-editor .qs-panel{display:none;align-items:stretch}
#luckysheet-wa-editor .qs-panel.active{display:flex}
#luckysheet-wa-editor .qr-group{display:flex;flex-direction:column;justify-content:center;flex:0 0 auto;padding:0 6px}
#luckysheet-wa-editor .qr-group+.qr-group{border-left:1px solid #e0e0e0}
#luckysheet-wa-editor .qr-group.qr-empty,#luckysheet-wa-editor .qr-folded{display:none!important}
#luckysheet-wa-editor .qr-items{display:flex;align-items:center}
#luckysheet-wa-editor .qr-row{display:contents}
#luckysheet-wa-editor .qr-label{display:none}
#qs-ribbon-toggle{position:absolute;right:6px;top:50%;transform:translateY(-50%);height:24px;min-width:26px;border:1px solid #d4d4d4;border-radius:3px;background:#fff;color:#555;cursor:pointer;font-size:12px}
.qs-ribbon-expanded #luckysheet-wa-editor .qr-items{flex:1;flex-direction:column;align-items:flex-start;justify-content:center;gap:2px}
.qs-ribbon-expanded #luckysheet-wa-editor .qr-row{display:flex;align-items:center}
.qs-ribbon-expanded #luckysheet-wa-editor .qr-label{display:block;padding:1px 0 2px;font:11px "Segoe UI",Arial,sans-serif;text-align:center;color:#777}
.qs-ribbon-expanded #luckysheet-wa-editor.qs-ribbon{height:auto!important;padding-top:3px}
.qs-ribbon-expanded #qs-ribbon-toggle{top:auto;bottom:3px;transform:none}
#luckysheet-wa-editor .qs-disabled{opacity:.38;pointer-events:none}
#luckysheet-wa-editor .qs-text-cmd .luckysheet-toolbar-menu-button-caption{padding:0 6px;font:12px "Segoe UI",Arial,sans-serif}
.qs-palette{display:grid;grid-template-columns:repeat(10,18px);gap:3px;padding:8px}
.qs-palette div{width:18px;height:18px;border:1px solid rgba(0,0,0,.15);cursor:pointer;box-sizing:border-box}
.qs-palette div:hover{outline:2px solid #0188fb}
"""

proc textButton(id, label, tip: string): Node =
  ## A toolbar button in Luckysheet's markup with a text caption.
  result = el("div", "luckysheet-toolbar-button luckysheet-inline-block qs-text-cmd")
  result.setAttribute("id", id)
  result.setAttribute("role", "button")
  result.setAttribute("data-tips", tip)
  result.setAttribute("title", tip)
  result.setProp("innerHTML", "<div class=\"luckysheet-toolbar-button-outer-box luckysheet-inline-block\"><div class=\"luckysheet-toolbar-button-inner-box luckysheet-inline-block\">" &
    "<div class=\"luckysheet-toolbar-menu-button-caption luckysheet-inline-block\">" & label & "</div></div></div>")

# ------------------------------------------------------------------- menus --

proc closeRibbonMenu(v: SheetView) =
  if not v.ribbonMenu.isNil: v.ribbonMenu.remove(); v.ribbonMenu = Node(0)

proc openRibbonMenu(v: SheetView, anchor: Node, items: seq[(string, string, bool)], pick: proc(value: string), extra = "") =
  ## A Luckysheet dropdown under `anchor`: (label, value, checked) items.
  v.closeRibbonMenu()
  let menu = el("div", "luckysheet-cols-menu luckysheet-rightgclick-menu luckysheet-menuButton luckysheet-mousedown-cancel")
  var html = extra
  for (label, value, checked) in items:
    html.add "<div class=\"luckysheet-cols-menuitem luckysheet-mousedown-cancel\" data-value=\"" & value.multiReplace(("&", "&amp;"), ("\"", "&quot;")) &
      "\"><div class=\"luckysheet-cols-menuitem-content luckysheet-mousedown-cancel\" style=\"padding: 3px 0px 3px 2px;\">" &
      "<span style=\"margin-right:3px;width:13px;display:inline-block;\" class=\"icon luckysheet-mousedown-cancel\">" &
      (if checked: "<i class=\"fa fa-check luckysheet-mousedown-cancel\"></i>" else: "") & "</span>" & label & "</div></div>"
  menu.setProp("innerHTML", html)
  discard document.query("body").add menu
  for item_1 in menu.queryAll(".luckysheet-cols-menuitem"):
    let item_0 = item_1
    closureScope:
      let item = item_0
      let value = item.invoke("getAttribute", "data-value").toStr
      item.on("mousedown", proc(e: Event) = e.preventDefault())          # keeps an editor's selection
      item.on("click", proc(e: Event) =
        v.closeRibbonMenu()
        pick(value)
        if not v.editing: v.editor.focus(true))
  let r = anchor.rect
  menu.style("display", "block")
  menu.style("left", px(min(r.left, window.getNum("innerWidth") - menu.getNum("offsetWidth") - 4)))
  menu.style("top", px(r.top + r.height))
  v.ribbonMenu = menu

proc openPalette(v: SheetView, anchor: Node, pick: proc(color: string)) =
  v.closeRibbonMenu()
  let menu = el("div", "luckysheet-cols-menu luckysheet-rightgclick-menu luckysheet-menuButton luckysheet-mousedown-cancel")
  var html = "<div class=\"luckysheet-cols-menuitem luckysheet-mousedown-cancel\" data-value=\"\"><div class=\"luckysheet-cols-menuitem-content luckysheet-mousedown-cancel\" style=\"padding: 3px 8px;\">Reset</div></div><div class=\"qs-palette\">"
  for c in Palette: html.add "<div data-value=\"" & c & "\" title=\"" & c & "\" style=\"background:" & c & "\"></div>"
  html.add "</div>"
  menu.setProp("innerHTML", html)
  discard document.query("body").add menu
  for item_1 in menu.queryAll("[data-value]"):
    let item_0 = item_1
    closureScope:
      let item = item_0
      let value = item.invoke("getAttribute", "data-value").toStr
      item.on("mousedown", proc(e: Event) = e.preventDefault())
      item.on("click", proc(e: Event) =
        v.closeRibbonMenu()
        pick(value)
        if not v.editing: v.editor.focus(true))
  let r = anchor.rect
  menu.style("display", "block")
  menu.style("left", px(r.left)); menu.style("top", px(r.top + r.height))
  v.ribbonMenu = menu

# ---------------------------------------------------------------- commands --

proc setNumberFormat(v: SheetView, fmt: string) =
  v.styleSelection(proc(st: var Style) = st.numFmt = fmt)
  v.refreshToolbar()

proc decimalsOf(v: SheetView): int =
  ## The decimals the active cell shows (General: as many as its value has).
  let cell = v.sheet.cellAt(v.ar, v.ac)
  let fmt = v.wb.styles[cell.style].numFmt
  if fmt.len > 0 and fmt notin ["General", "@"]:
    let f = fmt.split(';')[0]
    let dot = f.find('.')
    if dot < 0: return 0
    var n = 0
    for ch in f[dot + 1 .. ^1]:
      if ch in {'0', '#'}: inc n else: break
    return n
  if cell.value.kind == vkNum:
    let t = fmtGeneral(cell.value.num)
    let dot = t.find('.')
    if dot >= 0: return t.len - dot - 1
  0

proc changeDecimals(v: SheetView, delta: int) =
  ## Excel's Increase / Decrease Decimal: the active cell's format with one more / fewer.
  let n = max(0, v.decimalsOf() + delta)
  let fmt = v.wb.styles[v.sheet.cellAt(v.ar, v.ac).style].numFmt
  var base = if fmt.len == 0 or fmt in ["General", "@"]: "0" else: fmt.split(';')[0]
  # keep what is around the digits (¥, %, thousands)
  let dot = base.find('.')
  var intPart = if dot >= 0: base[0 ..< dot] else: base
  var after = ""
  if dot >= 0:
    var j = dot + 1
    while j < base.len and base[j] in {'0', '#'}: inc j
    after = base[j .. ^1]
  else:
    var j = intPart.len - 1
    while j >= 0 and intPart[j] notin {'0', '#'}: dec j
    after = intPart[j + 1 .. ^1]; intPart = intPart[0 .. j]
  let newFmt = intPart & (if n > 0: "." & repeat('0', n) else: "") & after
  v.setNumberFormat(newFmt)

proc autoSum(v: SheetView, fn: string) =
  ## Excel's AutoSum: the numbers right above (or left of) the active cell, in
  ## Enter mode with the range as the reference being pointed at.
  let s = v.sheet
  if v.editing: v.endEdit(true)
  let (r1, c1, r2, c2) = v.selRect()
  var target = (v.ar, v.ac)
  proc isNum(r, c: int): bool = r >= 0 and c >= 0 and s.cellAt(r, c).value.kind == vkNum
  var rng = ""
  if r1 != r2 or c1 != c2:
    # a range selected: the result goes under it
    target = (r2 + 1, c1)
    rng = cellName(r1, c1) & ":" & cellName(r2, c1)
  else:
    var a = v.ar - 1
    while a >= 0 and isNum(a, v.ac): dec a
    if a < v.ar - 1: rng = cellName(a + 1, v.ac) & ":" & cellName(v.ar - 1, v.ac)
    else:
      var b = v.ac - 1
      while b >= 0 and isNum(v.ar, b): dec b
      if b < v.ac - 1: rng = cellName(v.ar, b + 1) & ":" & cellName(v.ar, v.ac - 1)
  v.extraRanges.setLen(0)
  v.ar = target[0]; v.ac = target[1]; v.cr = target[0]; v.cc = target[1]
  v.showSelection()
  v.beginEdit("=" & fn & "(" & rng & ")", mode = 1)
  if rng.len > 0:
    v.pointActive = true
    v.pointStart = u16Len("=" & fn & "(")
    v.pointEnd = v.pointStart + u16Len(rng)
    v.setCaret(v.pointEnd)
  else:
    v.setCaret(u16Len("=" & fn & "("))
  v.showRangeBoxes(v.edText)
  v.updateHelp()

proc mergeMode(v: SheetView, mode: string) =
  ## Merge all / across (each row) / down (each column) / unmerge.
  let (r1, c1, r2, c2) = v.selRect()
  let s = v.sheet
  case mode
  of "all": v.toggleMerge()
  of "unmerge":
    if s.hasMerge(r1, c1, r2, c2): v.toggleMerge()
  of "across", "down":
    var act: Action
    let before = s.merges
    s.removeMerges(r1, c1, r2, c2)
    if mode == "across":
      for r in r1 .. r2:
        if c2 > c1: s.addMerge(Merge(r1: r, c1: c1, r2: r, c2: c2))
    else:
      for c in c1 .. c2:
        if r2 > r1: s.addMerge(Merge(r1: r1, c1: c, r2: r2, c2: c))
    act.add Change(sheet: v.wb.active, isMerge: true, mergesBefore: before, mergesAfter: s.merges)
    v.commitAction(act)
    v.showSelection(); v.requestDraw()
  else: discard

proc startPainter(v: SheetView) =
  ## Format Painter: the styles of the selection, laid on the next selection.
  let (r1, c1, r2, c2) = v.selRect()
  var styles: seq[seq[int32]]
  for r in r1 .. r2:
    var row: seq[int32]
    for c in c1 .. c2: row.add v.sheet.cellAt(r, c).style
    styles.add row
  v.painterStyles = styles
  v.painting = true
  v.cellMain.style("cursor", "copy")
  let b = byId("luckysheet-icon-paintformat")
  if not b.isNil: b.addClass("luckysheet-toolbar-button-hover")

proc finishPainter(v: SheetView) =
  if not v.painting: return
  v.painting = false
  v.cellMain.style("cursor", "")
  let b = byId("luckysheet-icon-paintformat")
  if not b.isNil: b.removeClass("luckysheet-toolbar-button-hover")
  let (r1, c1, r2, c2) = v.selRect()
  let h = v.painterStyles.len
  let w = v.painterStyles[0].len
  # a single click takes the copied block's size (Excel)
  let (e2, f2) = if r1 == r2 and c1 == c2: (r1 + h - 1, c1 + w - 1) else: (r2, c2)
  var act: Action
  for r in r1 .. e2:
    for c in c1 .. f2:
      var cell = v.sheet.cellAt(r, c)
      cell.style = v.painterStyles[(r - r1) mod h][(c - c1) mod w]
      v.setCellRaw(v.wb.active, r, c, cell, act)
  v.commitAction(act)
  v.cr = e2; v.cc = f2
  v.showSelection(); v.requestDraw()

proc finishPainterCancel(v: SheetView) =
  v.painting = false
  v.cellMain.style("cursor", "")
  let b = byId("luckysheet-icon-paintformat")
  if not b.isNil: b.removeClass("luckysheet-toolbar-button-hover")

# ------------------------------------------------------- toolbar state ----

proc refreshToolbar*(v: SheetView) =
  ## menuButton.menuButtonFocus: the buttons show the active cell's style.
  let st = v.activeStyle
  v.refreshProtectButton()
  for (id, on) in [("luckysheet-icon-textwrap", st.wrap), ("qs-cmd-filter", v.sheet.filter.on),
                   ("luckysheet-freezen-btn-horizontal", v.sheet.frozenRows > 0 or v.sheet.frozenCols > 0)]:
    let b = byId(id)
    if not b.isNil: b.toggleClass("luckysheet-toolbar-button-hover", on)
  for (id, on) in [("luckysheet-icon-bold", st.bold), ("luckysheet-icon-italic", st.italic),
                   ("luckysheet-icon-underline", st.underline), ("luckysheet-icon-strikethrough", st.strike)]:
    let b = byId(id)
    if not b.isNil: b.toggleClass("luckysheet-toolbar-button-hover", on)
  let ff = byId("luckysheet-icon-font-family")
  if not ff.isNil:
    let cap = ff.query(".luckysheet-toolbar-menu-button-caption")
    if not cap.isNil: cap.setProp("textContent", if st.font.len > 0: st.font else: "Times New Roman")
  let fs = byId("luckysheet-icon-font-size")
  if not fs.isNil:
    let inp = fs.query("input")
    let size = if st.fontSize > 0: st.fontSize else: DefaultFontSize
    let text = if size == floor(size): $int(size) else: $size
    if not inp.isNil: inp.setProp("value", text)
    else:
      let cap = fs.query(".luckysheet-toolbar-menu-button-caption")
      if not cap.isNil: cap.setProp("textContent", text)
  let fo = byId("luckysheet-icon-fmt-other")
  if not fo.isNil:
    var name = "Automatic"
    for (label, f) in Formats:
      if f == st.numFmt: name = label
    if name == "Automatic" and st.numFmt.len > 0: name = "Custom"
    let cap = fo.query(".luckysheet-toolbar-menu-button-caption")
    if not cap.isNil: cap.setProp("textContent", name)

# ------------------------------------------------------------- status bar --

proc refreshStatus*(v: SheetView) =
  ## Excel's status bar: Average, Count and Sum of the selection when it holds
  ## two values or more (Count alone without numbers).
  let box = byId("luckysheet-sta-content")
  if box.isNil: return
  let s = v.sheet
  var ranges = v.extraRanges
  let (a, b, c, d) = v.selRect()
  ranges.add Range(r1: a, c1: b, r2: c, c2: d)
  var count, numbers = 0
  var sum = 0.0
  for rg in ranges:
    let r2 = min(rg.r2, s.maxRow - 1)
    let c2 = min(rg.c2, s.maxCol - 1)
    for k, cell in s.cells:
      let (r, cc) = (rowOf(k), colOf(k))
      if r < rg.r1 or r > r2 or cc < rg.c1 or cc > c2: continue
      if cell.value.kind == vkEmpty: continue
      inc count
      if cell.value.kind == vkNum and not isDateFormat(v.wb.styles[cell.style].numFmt):
        inc numbers; sum += cell.value.num
  var html = ""
  if count >= 2:
    if numbers > 0:
      html.add "<span>Average: " & fmtGeneral(sum / float64(numbers)) & "</span>"
    html.add "<span>Count: " & $count & "</span>"
    if numbers > 0: html.add "<span>Sum: " & fmtGeneral(sum) & "</span>"
  box.setProp("innerHTML", html)

# ------------------------------------------------------------- the ribbon --

proc ribbonLayout(v: SheetView) =
  ## Fold the least important commands of the active tab until it fits.
  let editor = byId("luckysheet-wa-editor")
  if editor.isNil or v.ribbonItems.len == 0: return
  let panel = editor.query(".qs-panel.active")
  if panel.isNil: return
  for n in editor.queryAll(".qr-folded"): n.removeClass("qr-folded")
  for n in editor.queryAll(".qr-empty"): n.removeClass("qr-empty")
  let avail = editor.getNum("clientWidth") - 48
  let order = v.ribbonItems.getOrDefault(v.ribbonTab)
  var i = 0
  while panel.getNum("scrollWidth") > avail and i < order.len:
    let n = byId(order[i])
    if not n.isNil:
      n.addClass("qr-folded")
      let menu = byId(order[i] & "-menu")
      if not menu.isNil: menu.addClass("qr-folded")
    inc i
  for g in panel.queryAll(".qr-group"):
    if g.queryAll(".qr-row > *:not(.qr-folded)").len == 0: g.addClass("qr-empty")

proc showRibbonTab(v: SheetView, tab: string) =
  v.ribbonTab = tab
  for t in document.queryAll("#qs-ribbon-tabs .qs-tab"): t.toggleClass("active", t.invoke("getAttribute", "data-tab").toStr == tab)
  for p in document.queryAll("#luckysheet-wa-editor .qs-panel"): p.toggleClass("active", p.invoke("getAttribute", "data-tab").toStr == tab)
  v.ribbonLayout()

proc buildRibbon(v: SheetView) =
  let editor = byId("luckysheet-wa-editor")
  if editor.isNil: return
  let style = el("style")
  style.setProp("textContent", RibbonCss)
  discard document.query("head").add style
  # the commands the ribbon adds (text buttons for the app's own actions)
  var made: Table[string, Node]
  for (id, label, tip) in [("qs-cmd-open", "Open", "Open an .xlsx / .csv file"), ("qs-cmd-save", "Download", "Download as .xlsx"),
      ("qs-cmd-save-server", "Save to server", "Save to the server"), ("qs-cmd-csv", "CSV", "Export the sheet as CSV"),
      ("qs-cmd-opju", "OPJU", "Export as an Origin project"), ("qs-cmd-chart", "Insert Chart", "Insert a chart from the selection"),
      ("qs-cmd-sum", "Σ Sum", "AutoSum"), ("qs-cmd-average", "Average", "Average"), ("qs-cmd-count", "Count", "Count numbers"),
      ("qs-cmd-max", "Max", "Maximum"), ("qs-cmd-min", "Min", "Minimum"), ("qs-cmd-program", "Custom Program", "Luau programs"),
      ("qs-cmd-diagram", "Diagram Editor", "Open the diagram editor"), ("qs-cmd-sort-asc", "Sort A→Z", "Sort A to Z"),
      ("qs-cmd-sort-desc", "Sort Z→A", "Sort Z to A"), ("qs-cmd-filter", "Filter", "Filter (Ctrl+Shift+L)"),
      ("qs-cmd-filter-clear", "Clear", "Clear the filter's choices"), ("qs-cmd-cf-manage", "Manage Rules", "Conditional formatting rules"),
      ("qs-cmd-find", "Find", "Find (Ctrl+F)"), ("qs-cmd-replace", "Replace", "Replace (Ctrl+H)"),
      ("qs-cmd-note-new", "New Note", "New / edit note (Shift+F2)"), ("qs-cmd-note-delete", "Delete Note", "Delete the notes in the selection"),
      ("qs-cmd-notes-all", "Show All Notes", "Show all notes"), ("qs-cmd-protect", "Protect Sheet", "Protect / unprotect the sheet"),
      ("qs-cmd-lock", "Lock Cell", "Locked cells cannot change on a protected sheet"), ("qs-cmd-pivot-refresh", "Refresh", "Refresh the PivotTable"),
      ("qs-cmd-freeze-row", "Freeze Top Row", "Freeze the top row"), ("qs-cmd-freeze-col", "Freeze First Column", "Freeze the first column")]:
    made[id] = textButton(id, label, tip)
  # tab strip above the toolbar
  let tabs = el("div")
  tabs.setAttribute("id", "qs-ribbon-tabs")
  for (tab_1, label_1, _) in RibbonTabs:
    let tab_0 = tab_1
    let label_0 = label_1
    closureScope:
      let tab = tab_0
      let label = label_0
      let t = el("div", "qs-tab")
      t.setAttribute("data-tab", tab)
      t.setProp("textContent", label)
      let tb = tab
      t.on("mousedown", proc(e: Event) =
        e.preventDefault()
        v.showRibbonTab(tb)
        v.sizeAuto(); v.showSelection(); v.requestDraw())
      discard tabs.add t
  editor.getNode("parentNode").call("insertBefore", tabs, editor)
  # panels and groups; the buttons move into them
  editor.addClass("qs-ribbon")
  for (tab, _, groups) in RibbonTabs:
    let panel = el("div", "qs-panel")
    panel.setAttribute("data-tab", tab)
    var order: seq[(int, int, string)]
    var position = 0
    for (name, rows) in groups:
      let g = el("div", "qr-group")
      g.setAttribute("role", "group"); g.setAttribute("aria-label", name)
      let items = g.add el("div", "qr-items")
      for row in rows:
        let rowNode = items.add el("div", "qr-row")
        for id in row:
          var n = byId(id)
          if n.isNil and made.hasKey(id): n = made[id]
          if n.isNil: continue
          discard rowNode.add n
          if id in RibbonDisabled: n.addClass("qs-disabled")
          if not id.endsWith("-menu"):
            inc position
            order.add (RibbonPriority.getOrDefault(id, 5), position, id)
      let label = g.add el("div", "qr-label")
      label.setProp("textContent", name)
      discard panel.add g
    order.sort(proc(a, b: (int, int, string)): int = (if a[0] != b[0]: cmp(b[0], a[0]) else: cmp(b[1], a[1])))
    v.ribbonItems[tab] = order.mapIt(it[2])
    discard editor.add panel
  # what is left of Luckysheet's bar (separators, More) goes
  for n in editor.queryAll(":scope > :not(.qs-panel)"): n.remove()
  let more = byId("luckysheet-icon-morebtn-div")
  if not more.isNil: more.style("display", "none")
  let toggle = el("button")
  toggle.setAttribute("id", "qs-ribbon-toggle")
  toggle.setAttribute("type", "button")
  discard editor.add toggle
  proc applyExpanded() =
    document.query("html").toggleClass("qs-ribbon-expanded", v.ribbonOpen)
    toggle.setProp("textContent", if v.ribbonOpen: "▴" else: "▾")
    toggle.setAttribute("title", if v.ribbonOpen: "Collapse the ribbon to one row" else: "Expand the ribbon to show every command")
  v.ribbonOpen = storageGet(RibbonKey)[1] == "1"
  applyExpanded()
  toggle.on("mousedown", proc(e: Event) = e.preventDefault())
  toggle.on("click", proc(e: Event) =
    v.ribbonOpen = not v.ribbonOpen
    discard storageSet(RibbonKey, if v.ribbonOpen: "1" else: "0")
    applyExpanded()
    v.sizeAuto(); v.ribbonLayout(); v.showSelection(); v.requestDraw())
  v.showRibbonTab("home")

proc bindRibbon(v: SheetView) =
  ## What the buttons do (menuButton.js behaviours, Excel's rules).
  proc on(id: string, action: proc(n: Node)) =
    let n = byId(id)
    if n.isNil: return
    n.on("mousedown", proc(e: Event) = (if v.editing: e.preventDefault()))   # keep the editor's selection
    n.on("click", proc(e: Event) =
      e.stopPropagation()
      action(n))
  proc topBar(id: string): proc(n: Node) =
    (proc(n: Node) = (let t = byId(id); if not t.isNil: t.click()))
  on("qs-cmd-open", topBar("xlsxUpload"))
  on("qs-cmd-save", topBar("downloadFile"))
  on("qs-cmd-save-server", topBar("saveToServer"))
  on("qs-cmd-csv", topBar("exportCSV"))
  on("qs-cmd-opju", proc(n: Node) = (if v.hostCall != nil: v.hostCall("opju", newJNull())))
  on("qs-cmd-chart", proc(n: Node) = v.openChartDialog())
  on("qs-cmd-program", proc(n: Node) = v.openProgram())
  on("qs-cmd-diagram", proc(n: Node) = v.openDiagram())
  for (id_1, fn_1) in [("qs-cmd-sum", "SUM"), ("qs-cmd-average", "AVERAGE"), ("qs-cmd-count", "COUNT"), ("qs-cmd-max", "MAX"), ("qs-cmd-min", "MIN")]:
    let id_0 = id_1
    let fn_0 = fn_1
    closureScope:
      let id = id_0
      let fn = fn_0
      let f = fn
      on(id, proc(n: Node) = v.autoSum(f))
  on("qs-cmd-sort-asc", proc(n: Node) = v.sortSelection(false))
  on("qs-cmd-sort-desc", proc(n: Node) = v.sortSelection(true))
  on("luckysheet-icon-paintformat", proc(n: Node) = (if v.painting: v.finishPainterCancel() else: v.startPainter()))
  on("luckysheet-icon-currency", proc(n: Node) = v.setNumberFormat("¥#,##0.00"))
  on("luckysheet-icon-percent", proc(n: Node) = v.setNumberFormat("0%"))
  on("luckysheet-icon-fmt-decimal-increase", proc(n: Node) = v.changeDecimals(1))
  on("luckysheet-icon-fmt-decimal-decrease", proc(n: Node) = v.changeDecimals(-1))
  on("luckysheet-icon-fmt-other", proc(n: Node) =
    let cur = v.activeStyle.numFmt
    v.openRibbonMenu(n, Formats.mapIt((it[0] & "<span style=\"color:#999;margin-left:12px\">" & (if it[1].len > 0: it[1] else: "") & "</span>", it[1], it[1] == cur)),
      proc(f: string) = v.setNumberFormat(f)))
  on("luckysheet-icon-font-family", proc(n: Node) =
    let cur = v.activeStyle.font
    v.openRibbonMenu(n, Fonts.mapIt(("<span style=\"font-family:'" & it & "'\">" & it & "</span>", it, it == cur or (cur.len == 0 and it == "Times New Roman"))),
      proc(f: string) =
        if v.editing and not v.isFormulaText: discard execCommand("fontName", f, true)
        else: v.styleSelection(proc(st: var Style) = st.font = (if f == "Times New Roman": "" else: f))
        v.refreshToolbar()))
  let sizeBox = byId("luckysheet-icon-font-size")
  if not sizeBox.isNil:
    proc applySize(size: float64) =
      if size <= 0 or size > 409: return
      v.styleSelection(proc(st: var Style) = st.fontSize = (if size == DefaultFontSize: 0.0 else: size))
      v.refreshToolbar()
    sizeBox.on("mousedown", proc(e: Event) =
      if e.target.matches("input"): return
      e.preventDefault()
      e.stopPropagation()          # or the page's "close menus" handler shuts it at once
      let cur = v.activeStyle.fontSize
      v.openRibbonMenu(sizeBox, Sizes.mapIt(($it, $it, float64(it) == (if cur > 0: cur else: DefaultFontSize))),
        proc(s: string) = applySize(parseFloat(s))))
    let inp = sizeBox.query("input")
    if not inp.isNil:
      inp.on("keydown", proc(e: Event) =
        if e.key == "Enter":
          e.preventDefault()
          try: applySize(parseFloat(inp.value.strip)) except ValueError: discard
          v.editor.focus(true))
  # colours: the button repeats the last colour, its arrow opens the palette
  proc colorCommand(id: string, text: bool) =
    let indicator = proc(): Node = (let b = byId(id); if b.isNil: Node(0) else: b.query(".luckysheet-color-menu-button-indicator"))
    proc apply(color: string) =
      if text:
        if v.editing and not v.isFormulaText: discard execCommand("foreColor", (if color.len > 0: color else: "#000000"), true)
        else: v.styleSelection(proc(st: var Style) = st.color = color)
        v.lastTextColor = color
      else:
        v.styleSelection(proc(st: var Style) = st.fill = color)
        v.lastFillColor = color
      let ind = indicator()
      if not ind.isNil: ind.style("border-bottom-color", if color.len > 0: color else: (if text: "#000000" else: "#ffffff"))
    on(id, proc(n: Node) = apply(if text: v.lastTextColor else: v.lastFillColor))
    on(id & "-menu", proc(n: Node) = v.openPalette(n, proc(c: string) = apply(c)))
  colorCommand("luckysheet-icon-text-color", true)
  colorCommand("luckysheet-icon-cell-color", false)
  # borders
  on("luckysheet-icon-border-all", proc(n: Node) = v.applyBorders(v.lastBorder))
  on("luckysheet-icon-border-menu", proc(n: Node) =
    v.openRibbonMenu(n, @[("All borders", "all", false), ("Outside borders", "outside", false), ("Thick outside borders", "thick", false),
      ("Top border", "top", false), ("Bottom border", "bottom", false), ("Left border", "left", false), ("Right border", "right", false),
      ("No border", "none", false)], proc(m: string) = (v.lastBorder = m; v.applyBorders(m))))
  # merge
  on("luckysheet-icon-merge-button", proc(n: Node) = v.toggleMerge())
  on("luckysheet-icon-merge-menu", proc(n: Node) =
    v.openRibbonMenu(n, @[("Merge all", "all", false), ("Merge across", "across", false), ("Merge down", "down", false),
      ("Unmerge", "unmerge", false)], proc(m: string) = v.mergeMode(m)))
  # alignment
  proc alignMenu(id: string, horizontal: bool) =
    let items = if horizontal: @[("Left", "left", false), ("Center", "center", false), ("Right", "right", false)]
                else: @[("Top", "top", false), ("Middle", "middle", false), ("Bottom", "bottom", false)]
    proc pick(m: string) =
      v.styleSelection(proc(st: var Style) =
        case m
        of "left": st.hAlign = haLeft
        of "center": st.hAlign = haCenter
        of "right": st.hAlign = haRight
        of "top": st.vAlign = vaTop
        of "middle": st.vAlign = vaMiddle
        else: st.vAlign = vaBottom)
    on(id, proc(n: Node) = v.openRibbonMenu(n, items, pick))
    on(id & "-menu", proc(n: Node) = v.openRibbonMenu(n, items, pick))
  alignMenu("luckysheet-icon-align", true)
  alignMenu("luckysheet-icon-valign", false)
  # AutoSum and its list
  on("luckysheet-icon-function", proc(n: Node) = v.autoSum("SUM"))
  on("luckysheet-icon-function-menu", proc(n: Node) =
    v.openRibbonMenu(n, @[("Sum", "SUM", false), ("Average", "AVERAGE", false), ("Count", "COUNT", false), ("Max", "MAX", false),
      ("Min", "MIN", false)], proc(f: string) = v.autoSum(f)))
  # wrap and rotation (menuButton.js textwrap / rotation menus)
  on("luckysheet-icon-textwrap", proc(n: Node) = v.setWrap(not v.activeStyle.wrap))
  on("luckysheet-icon-textwrap-menu", proc(n: Node) =
    let w = v.activeStyle.wrap
    v.openRibbonMenu(n, @[("Overflow", "overflow", not w), ("Wrap Text", "wrap", w)], proc(m: string) = v.setWrap(m == "wrap")))
  let angles = @[("None", "0"), ("Angle Counterclockwise", "45"), ("Angle Clockwise", "-45"), ("Vertical Text", "255"),
    ("Rotate Text Up", "90"), ("Rotate Text Down", "-90")]
  proc rotationMenu(n: Node) =
    let cur = $v.activeStyle.rotation
    v.openRibbonMenu(n, angles.mapIt((it[0], it[1], it[1] == cur)), proc(m: string) = v.setRotation(parseInt(m)))
  on("luckysheet-icon-rotation", rotationMenu)
  on("luckysheet-icon-rotation-menu", rotationMenu)
  # sort & filter, find
  proc sortFilterMenu(n: Node) =
    v.openRibbonMenu(n, @[("Sort A to Z", "asc", false), ("Sort Z to A", "desc", false), ("Filter", "filter", v.sheet.filter.on),
      ("Clear", "clear", false)], proc(m: string) =
        case m
        of "asc": v.sortSelection(false)
        of "desc": v.sortSelection(true)
        of "filter": v.toggleFilter()
        else: v.clearFilterChoices())
  on("luckysheet-icon-autofilter", sortFilterMenu)
  on("qs-cmd-filter", proc(n: Node) = v.toggleFilter())
  on("qs-cmd-filter-clear", proc(n: Node) = v.clearFilterChoices())
  on("luckysheet-icon-seachmore", proc(n: Node) =
    v.openRibbonMenu(n, @[("Find…", "find", false), ("Replace…", "replace", false)], proc(m: string) = v.openFind(m == "replace")))
  on("qs-cmd-find", proc(n: Node) = v.openFind())
  on("qs-cmd-replace", proc(n: Node) = v.openFind(replace = true))
  # insert
  let upload = byId("luckysheet-imgUpload")
  if not upload.isNil: upload.style("display", "none")
  on("luckysheet-insertImg-btn-title", proc(n: Node) = v.insertPicture())
  on("luckysheet-pivot-btn-title", proc(n: Node) = v.pivotDialog())
  on("qs-cmd-pivot-refresh", proc(n: Node) = v.refreshPivot())
  on("luckysheet-insertLink-btn-title", proc(n: Node) = v.linkDialog())
  on("luckysheet-icon-postil", proc(n: Node) = v.noteMenu(n))
  # data tools
  on("luckysheet-icon-conditionformat", proc(n: Node) = v.openCfMenu(n))
  on("qs-cmd-cf-manage", proc(n: Node) = v.manageRules())
  on("luckysheet-dataVerification-btn-title", proc(n: Node) = v.validationDialog())
  # review
  on("qs-cmd-note-new", proc(n: Node) = v.editNote())
  on("qs-cmd-note-delete", proc(n: Node) = v.deleteNote())
  on("qs-cmd-notes-all", proc(n: Node) = v.toggleAllNotes())
  on("luckysheet-icon-protection", proc(n: Node) = v.protectSheet())
  on("qs-cmd-protect", proc(n: Node) = v.protectSheet())
  on("qs-cmd-lock", proc(n: Node) = v.toggleLock())
  on("luckysheet-icon-print", proc(n: Node) = v.printSheet())
  # freeze (freezen.js): the button freezes at the selection or unfreezes
  on("luckysheet-freezen-btn-horizontal", proc(n: Node) =
    v.freezeCommand(if v.sheet.frozenRows > 0 or v.sheet.frozenCols > 0: "none" else: "panes"))
  on("luckysheet-icon-freezen-menu", proc(n: Node) =
    let frozen = v.sheet.frozenRows > 0 or v.sheet.frozenCols > 0
    v.openRibbonMenu(n, @[((if frozen: "Unfreeze Panes" else: "Freeze Panes"), (if frozen: "none" else: "panes"), false),
      ("Freeze Top Row", "row", v.sheet.frozenRows == 1 and v.sheet.frozenCols == 0),
      ("Freeze First Column", "column", v.sheet.frozenCols == 1 and v.sheet.frozenRows == 0)], proc(m: string) = v.freezeCommand(m)))
  on("qs-cmd-freeze-row", proc(n: Node) = v.freezeCommand("row"))
  on("qs-cmd-freeze-col", proc(n: Node) = v.freezeCommand("column"))
  # the top bar toggle (menuButton.js:2606)
  on("luckysheet-icon-toggle-topbar", proc(n: Node) =
    v.hideInfobar = not v.hideInfobar
    v.sizeAuto(); v.showSelection(); v.requestDraw())
  document.on("mousedown", proc(e: Event) =
    if not v.ribbonMenu.isNil and not e.target.matches(".luckysheet-menuButton, .luckysheet-menuButton *"): v.closeRibbonMenu())
