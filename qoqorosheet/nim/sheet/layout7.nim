## Freeze panes, wrap, rotation, sheet protection and print, included into
## view.nim (Luckysheet's freezen.js, menuButton.js textwrap / rotation menus,
## protection.js, and Excel's rules for each).

# ---------------------------------------------------------------- freeze --

proc setFreeze*(v: SheetView, rows, cols: int) =
  ## Excel's Freeze Panes (freezen.js): rows above / columns left of the split.
  let s = v.sheet
  v.structural(proc() =
    s.frozenRows = max(0, rows); s.frozenCols = max(0, cols), guard = false)
  v.sbX.setProp("scrollLeft", 0); v.sbY.setProp("scrollTop", 0)
  v.onScroll()

proc freezeCommand(v: SheetView, mode: string) =
  let (r1, c1, _, _) = v.selRect()
  case mode
  of "panes":
    if r1 == 0 and c1 == 0: v.setFreeze(v.sheet.rowAt(v.sbY.getNum("scrollTop") + 0.01) + 10, 0)
    else: v.setFreeze(r1, c1)
  of "row": v.setFreeze(1, 0)
  of "column": v.setFreeze(0, 1)
  else: v.setFreeze(0, 0)

# ------------------------------------------------------- wrap / rotation --

proc setWrap(v: SheetView, on: bool) =
  v.styleSelection(proc(st: var Style) = st.wrap = on)

proc setRotation(v: SheetView, angle: int) =
  v.styleSelection(proc(st: var Style) = st.rotation = angle)

# ------------------------------------------------------------ protection --

proc rangeLocked(v: SheetView, r1, c1, r2, c2: int): bool =
  ## Excel: on a protected sheet, cells are locked unless formatted otherwise
  let s = v.sheet
  if not s.protected: return false
  let area = (r2 - r1 + 1) * (c2 - c1 + 1)
  var unlocked = 0
  for k, cell in s.cells:
    let (r, c) = (rowOf(k), colOf(k))
    if r >= r1 and r <= r2 and c >= c1 and c <= c2 and v.wb.styles[cell.style].unlocked: inc unlocked
  unlocked < area

proc protectedMessage(v: SheetView) =
  v.tooltipInfo("Protected sheet", "The cell or chart you're trying to change is on a protected sheet. To make a change, unprotect the sheet (Review &gt; Unprotect Sheet). You might be asked for a password.")

proc protectSheet(v: SheetView) =
  ## Review > Protect Sheet / Unprotect Sheet (protection.js), with Excel's password
  let s = v.sheet
  if s.protected:
    if s.protectHash.len == 0:
      s.protected = false
      v.refreshProtectButton()
      return
    discard v.openDialog("qs-unprotect", "Unprotect Sheet", dlgRow("Password", "<input type=\"password\" name=\"pw\" style=\"width:200px;height:24px\">"),
      @[("ok", "OK"), ("cancel", "Cancel")], proc(b: string, box: Node): bool =
        if b != "ok": return true
        if passwordHash(box.field("pw")) != s.protectHash:
          v.tooltipInfo("Unprotect Sheet", "The password you supplied is not correct."); return false
        s.protected = false; s.protectHash = ""
        if v.onChange != nil: v.onChange()
        v.refreshProtectButton()
        true)
    return
  discard v.openDialog("qs-protect", "Protect Sheet", "<p style=\"margin:0 0 6px;color:#555\">Locked cells cannot be changed while the sheet is protected (Format Cells: Lock cell).</p>" &
    dlgRow("Password (optional)", "<input type=\"password\" name=\"pw\" style=\"width:200px;height:24px\">") &
    dlgRow("Confirm", "<input type=\"password\" name=\"pw2\" style=\"width:200px;height:24px\">"),
    @[("ok", "OK"), ("cancel", "Cancel")], proc(b: string, box: Node): bool =
      if b != "ok": return true
      if box.field("pw") != box.field("pw2"):
        v.tooltipInfo("Protect Sheet", "The passwords do not match."); return false
      s.protected = true
      s.protectHash = passwordHash(box.field("pw"))
      if v.onChange != nil: v.onChange()
      v.refreshProtectButton()
      true)

proc toggleLock(v: SheetView) =
  ## Format Cells > Protection > Locked, for the selection
  let on = not v.activeStyle.unlocked
  let s = v.sheet
  if s.protected: v.protectedMessage(); return
  v.styleSelection(proc(st: var Style) = st.unlocked = on)
  v.refreshProtectButton()

proc refreshProtectButton(v: SheetView) =
  let s = v.sheet
  let p = byId("qs-cmd-protect")
  if not p.isNil:
    let cap = p.query(".luckysheet-toolbar-menu-button-caption")
    if not cap.isNil: cap.setProp("textContent", if s.protected: "Unprotect Sheet" else: "Protect Sheet")
  let icon = byId("luckysheet-icon-protection")
  if not icon.isNil:
    icon.setAttribute("title", if s.protected: "Unprotect Sheet" else: "Protect Sheet")
    icon.toggleClass("luckysheet-toolbar-button-hover", s.protected)
  let lock = byId("qs-cmd-lock")
  if not lock.isNil: lock.toggleClass("luckysheet-toolbar-button-hover", not v.activeStyle.unlocked)

# ----------------------------------------------------------------- print --

proc printSheet(v: SheetView) =
  ## Excel's Print: the selection when it is more than a cell, else the used
  ## range, as a table with the cells' formats, in the browser's print dialog.
  let s = v.sheet
  var (r1, c1, r2, c2) = v.selRect()
  if r1 == r2 and c1 == c2:
    if s.maxRow == 0: v.tooltipInfo("Print", "There is nothing to print."); return
    (r1, c1, r2, c2) = (0, 0, s.maxRow - 1, s.maxCol - 1)
  r2 = min(r2, s.maxRow - 1); c2 = min(c2, s.maxCol - 1)
  var html = "<!doctype html><html><head><meta charset=\"utf-8\"><title>" & esc(s.name) & "</title><style>" &
    "body{margin:12mm;font:10pt 'Times New Roman',Arial,sans-serif}table{border-collapse:collapse}" &
    "td{border:1px solid #d9d9d9;padding:1px 4px;white-space:nowrap;vertical-align:bottom}img{position:absolute}</style></head><body><table>"
  for r in r1 .. r2:
    if s.rowHidden(r): continue
    html.add "<tr style=\"height:" & $(s.rowHeight(r) + 1) & "px\">"
    for c in c1 .. c2:
      if s.colHidden(c): continue
      let mi = s.mergeAt(r, c)
      var span = ""
      if mi >= 0:
        let m = s.merges[mi]
        if m.r1 != r or m.c1 != c: continue
        span = " rowspan=\"" & $(min(m.r2, r2) - r + 1) & "\" colspan=\"" & $(min(m.c2, c2) - c + 1) & "\""
      let cell = s.cellAt(r, c)
      let st = v.wb.styles[cell.style]
      var css = cellCss(v.wb, st) & "min-width:" & $s.colWidth(c) & "px;max-width:" & $s.colWidth(c) & "px;overflow:hidden;"
      if st.wrap: css.add "white-space:normal;"
      if st.hAlign == haGeneral and cell.value.kind == vkNum: css.add "text-align:right;"
      let text = if cell.rich.len > 0: richHtml(st, cell.rich) else: esc(v.wb.displayText(cell))
      html.add "<td" & span & " style=\"" & css & "\">" & text & "</td>"
    html.add "</tr>"
  html.add "</table></body></html>"
  let frame = el("iframe")
  frame.setAttribute("style", "position:fixed;right:0;bottom:0;width:0;height:0;border:0")
  discard document.query("body").add frame
  frame.setAttribute("srcdoc", html)
  frame.on("load", proc(e: Event) =
    let w = frame.getNode("contentWindow")
    w.call("focus"); w.call("print")
    setTimeout(1000, proc() = frame.remove()))
