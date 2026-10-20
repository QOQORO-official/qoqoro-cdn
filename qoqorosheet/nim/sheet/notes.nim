## Notes and hyperlinks, included into view.nim.
## Notes: Excel's notes (Luckysheet's postil.js): New / Edit Note opens a
## yellow box beside the cell, a red triangle marks it (drawn by drawMain),
## hovering shows it, Show All Notes keeps them up, Delete Note removes it.
## Links: Excel's Insert Link dialog (Ctrl+K; hyperlinkCtrl.js) — a web
## address or a place in this workbook (#Sheet1!A1) — the link look, a click
## follows it, the hover tip says where it goes.

var
  notesShown: bool             ## Show All Notes
  hoverKey: int64 = -1

proc noteBoxHtml(text: string): string =
  esc(text).replace("\n", "<br>")

proc placeNote(v: SheetView, r, c: int, text: string, editable = false): Node =
  ## a note's box: right of the cell, its top level with the cell's
  let layer = byId("luckysheet-postil-showBoxs")
  if layer.isNil: return Node(0)
  let (x, y, w, _) = v.cellBox(r, c)
  let box = el("div", "qs-note luckysheet-mousedown-cancel")
  box.setAttribute("data-key", $key(r, c))
  box.setAttribute("style", "position:absolute;z-index:40;left:" & px(x + w + 12) & ";top:" & px(y) &
    ";min-width:140px;max-width:260px;min-height:50px;padding:4px 6px;background:#ffffe1;border:1px solid #6b6b6b;box-shadow:2px 2px 4px rgba(0,0,0,.25);font:12px Tahoma,Arial,sans-serif;color:#000;white-space:normal;word-break:break-word")
  if editable:
    box.setProp("innerHTML", "<textarea class=\"luckysheet-mousedown-cancel\" style=\"width:220px;height:80px;border:0;outline:0;background:transparent;font:12px Tahoma,Arial,sans-serif;resize:both\"></textarea>")
    box.query("textarea").setProp("value", text)
  else: box.setProp("innerHTML", noteBoxHtml(text))
  discard layer.add box
  box

proc clearNoteBoxes(keepEditing = true) =
  for n in document.queryAll("#luckysheet-postil-showBoxs .qs-note"):
    if keepEditing and not n.query("textarea").isNil: continue
    n.remove()

proc showNotes(v: SheetView) =
  ## the notes on screen: all of them (Show All Notes) or the hovered one
  clearNoteBoxes()
  let s = v.sheet
  for k, text in s.notes:
    if notesShown or k == hoverKey: discard v.placeNote(rowOf(k), colOf(k), text)

proc setNote(v: SheetView, r, c: int, text: string) =
  let s = v.sheet
  v.structural(proc() =
    if text.strip.len == 0: s.notes.del key(r, c) else: s.notes[key(r, c)] = text)

proc editNote*(v: SheetView) =
  ## New Note / Edit Note: a box to type in; leaving it keeps the text
  let s = v.sheet
  let (r, c) = (v.ar, v.ac)
  clearNoteBoxes(false)
  let box = v.placeNote(r, c, s.notes.getOrDefault(key(r, c)), editable = true)
  if box.isNil: return
  let area = box.query("textarea")
  area.focus()
  var done = false
  proc finish() =
    if done: return
    done = true
    let text = area.value
    box.remove()
    if text != s.notes.getOrDefault(key(r, c)): v.setNote(r, c, text)
    v.showNotes(); v.requestDraw()
  area.on("blur", proc(e: Event) = finish())
  area.on("keydown", proc(e: Event) =
    e.stopPropagation()
    if e.key == "Escape": e.preventDefault(); area.blur())

proc deleteNote(v: SheetView) =
  let (r1, c1, r2, c2) = v.selRect()
  let s = v.sheet
  var any = false
  for k in s.notes.keys:
    if rowOf(k) in r1 .. r2 and colOf(k) in c1 .. c2: any = true
  if not any: return
  v.structural(proc() =
    var keep = initTable[int64, string]()
    for k, t in s.notes:
      if not (rowOf(k) in r1 .. r2 and colOf(k) in c1 .. c2): keep[k] = t
    s.notes = keep)
  v.showNotes()

proc noteMenu(v: SheetView, anchor: Node) =
  let has = v.sheet.notes.hasKey(key(v.ar, v.ac))
  v.openRibbonMenu(anchor, @[((if has: "Edit Note" else: "New Note"), "edit", false), ("Delete Note", "delete", false),
    ("Show All Notes", "all", notesShown)], proc(m: string) =
      case m
      of "edit": v.editNote()
      of "delete": v.deleteNote()
      of "all": v.toggleAllNotes()
      else: discard)

proc toggleAllNotes(v: SheetView) =
  notesShown = not notesShown
  v.showNotes()
  let b = byId("qs-cmd-notes-all")
  if not b.isNil: b.toggleClass("luckysheet-toolbar-button-hover", notesShown)

# ----------------------------------------------------------------- links --

proc followLink(v: SheetView, target: string) =
  if target.startsWith("#"):
    # a place in this workbook: #Sheet!A1 or #A1
    var t = target[1 .. ^1]
    var sheet = v.wb.active
    let bang = t.rfind('!')
    if bang >= 0:
      let name = t[0 ..< bang].strip(chars = {'\''})
      for i, s in v.wb.sheets:
        if cmpIgnoreCase(s.name, name) == 0: sheet = i
      t = t[bang + 1 .. ^1]
    let (ok, r1, c1, r2, c2) = parseRangeText(t)
    if not ok: v.tooltipInfo("Hyperlink", "Reference isn't valid."); return
    if sheet != v.wb.active: v.activate(sheet)
    v.moveTo(r1, c1)
    v.cr = r2; v.cc = c2
    v.showSelection()
  else:
    let url = if target.contains("://") or target.startsWith("mailto:"): target else: "https://" & target
    discard window.invoke("open", url, "_blank", "noopener")

proc linkDialog*(v: SheetView) =
  ## Insert > Link (Ctrl+K)
  let s = v.sheet
  let (r, c) = (v.ar, v.ac)
  if v.rangeLocked(r, c, r, c): v.protectedMessage(); return
  let cur = s.links.getOrDefault(key(r, c))
  let shown = v.wb.displayText(s.cellAt(r, c))
  let body = dlgRow("Text to display", dlgInput("text", shown, 260)) &
    dlgRow("Address", dlgInput("url", cur, 260, "https://…  or  #Sheet1!A1"))
  var buttons = @[("ok", "OK"), ("cancel", "Cancel")]
  if cur.len > 0: buttons.insert(("remove", "Remove Link"), 1)
  discard v.openDialog("qs-link", if cur.len > 0: "Edit Hyperlink" else: "Insert Hyperlink", body, buttons, proc(b: string, box: Node): bool =
    if b == "cancel": return true
    let url = box.field("url").strip
    let text = box.field("text")
    if b == "ok" and url.len == 0: v.tooltipInfo("Hyperlink", "Enter an address."); return false
    v.structural(proc() =
      if b == "remove": s.links.del key(r, c)
      else:
        s.links[key(r, c)] = url
        let old = s.cellAt(r, c)
        let t = if text.len > 0: text else: url
        if t != v.wb.displayText(old) or old.value.kind == vkEmpty:
          var cell = Cell(style: old.style, value: strVal(t))
          s.putCell(r, c, cell))
    v.requestDraw()
    true, 400)

var linkPress: (int, int, float64) = (-1, -1, 0.0)

proc linkMouseDown(v: SheetView, r, c: int) =
  linkPress = if v.sheet.links.hasKey(key(r, c)): (r, c, construct("Date").invoke("getTime").toNum) else: (-1, -1, 0.0)

proc linkMouseUp(v: SheetView, r, c: int) =
  ## Excel: a click follows the link; holding the button just selects
  let (pr, pc, t) = linkPress
  linkPress = (-1, -1, 0.0)
  if pr != r or pc != c or pr < 0: return
  if construct("Date").invoke("getTime").toNum - t > 600: return
  let target = v.sheet.links.getOrDefault(key(r, c))
  if target.len > 0: v.followLink(target)

proc onCellHover(v: SheetView, e: Event) =
  ## notes show while hovered; a link's tip says where it goes
  if v.selecting != 0 or v.resizing != 0: return
  let (x, y) = v.contentPoint(e)
  let (r, c) = v.hitCell(x, y)
  let s = v.sheet
  let k = key(r, c)
  let mi = s.mergeAt(r, c)
  let owner = if mi >= 0: key(s.merges[mi].r1, s.merges[mi].c1) else: k
  let noteKey = if s.notes.hasKey(owner): owner else: -1'i64
  if noteKey != hoverKey:
    hoverKey = noteKey
    v.showNotes()
  let target = s.links.getOrDefault(owner)
  v.cellMain.setAttribute("title", if target.len > 0: target & " - Click once to follow. Click and hold to select this cell." else: "")
  v.cellMain.style("cursor", if target.len > 0: "pointer" else: "")
