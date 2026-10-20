## A Luckysheet modal dialog (.luckysheet-modal-dialog, as tooltip.js and the
## feature dialogs build it), included into view.nim for the stage 7
## commands: a title, a form, buttons; the handler says whether it closes.

proc closeDialog(v: SheetView, box: Node) =
  box.remove()
  let mask = byId("luckysheet-modal-dialog-mask")
  if not mask.isNil: mask.style("display", "none")
  if not v.editing: v.editor.focus(true)

proc openDialog(v: SheetView, id, title, body: string, buttons: seq[(string, string)],
                onButton: proc(button: string, box: Node): bool, width = 360): Node =
  ## buttons: (value, label); the first is the primary one (Enter presses it).
  let old = byId(id)
  if not old.isNil: old.remove()
  if v.editing: v.endEdit(true)
  let mask = byId("luckysheet-modal-dialog-mask")
  if not mask.isNil: mask.style("display", "block")
  let box = el("div", "luckysheet-modal-dialog luckysheet-mousedown-cancel qs-dialog")
  box.setAttribute("id", id)
  box.setAttribute("style", "z-index:100003;display:block;min-width:" & $width & "px")
  var btns = ""
  for i, (value, label) in buttons:
    btns.add "<button class=\"btn " & (if i == 0: "btn-primary" else: "btn-default") & "\" data-btn=\"" & value & "\">" & label & "</button> "
  box.setProp("innerHTML", "<div class=\"luckysheet-modal-dialog-title luckysheet-modal-dialog-title-draggable\"><span class=\"luckysheet-modal-dialog-title-text\">" &
    title & "</span><span class=\"luckysheet-modal-dialog-title-close\" role=\"button\"><i class=\"fa fa-times\"></i></span></div>" &
    "<div class=\"luckysheet-modal-dialog-content\">" & body & "</div><div class=\"luckysheet-modal-dialog-buttons\">" & btns & "</div>")
  discard document.query("body").add box
  box.style("left", px(max(4.0, (window.getNum("innerWidth") - box.getNum("offsetWidth")) / 2)))
  box.style("top", px(max(4.0, (window.getNum("innerHeight") - box.getNum("offsetHeight")) / 3)))
  box.query(".luckysheet-modal-dialog-title-close").on("click", proc(e: Event) = v.closeDialog(box))
  for b_1 in box.queryAll("[data-btn]"):
    let b_0 = b_1
    closureScope:
      let b = b_0
      let value = b.invoke("getAttribute", "data-btn").toStr
      b.on("click", proc(e: Event) =
        if onButton(value, box): v.closeDialog(box))
  let first = if buttons.len > 0: buttons[0][0] else: ""
  box.on("keydown", proc(e: Event) =
    e.stopPropagation()
    if e.key == "Escape": v.closeDialog(box)
    elif e.key == "Enter" and not e.target.matches("textarea") and first.len > 0:
      e.preventDefault()
      if onButton(first, box): v.closeDialog(box))
  let input = box.query("input:not([type=checkbox]), select, textarea")
  if not input.isNil: input.focus()
  box

proc field(box: Node, name: string): string =
  ## a dialog field's value, by its name
  let n = box.query("[name=\"" & name & "\"]")
  if n.isNil: "" elif n.getStr("type") == "checkbox": (if n.checked: "1" else: "") else: n.value

proc dlgRow(label, control: string): string =
  "<div style=\"display:flex;align-items:center;gap:8px;margin:6px 0\"><span style=\"width:110px;color:#555\">" & label & "</span>" & control & "</div>"

proc dlgInput(name: string, value = "", width = 200, placeholder = ""): string =
  "<input type=\"text\" name=\"" & name & "\" value=\"" & esc(value) & "\" placeholder=\"" & esc(placeholder) &
    "\" class=\"luckysheet-mousedown-cancel\" style=\"width:" & $width & "px;height:24px;padding:0 6px;border:1px solid #d4d4d4\">"

proc dlgSelect(name: string, options: seq[(string, string)], value = ""): string =
  result = "<select name=\"" & name & "\" class=\"luckysheet-mousedown-cancel\" style=\"height:26px;border:1px solid #d4d4d4\">"
  for (val, label) in options:
    result.add "<option value=\"" & esc(val) & "\"" & (if val == value: " selected" else: "") & ">" & esc(label) & "</option>"
  result.add "</select>"

proc dlgCheck(name, label: string, on = false): string =
  "<label style=\"display:inline-flex;align-items:center;gap:4px;margin-right:12px\"><input type=\"checkbox\" name=\"" & name & "\"" &
    (if on: " checked" else: "") & "> " & label & "</label>"

proc rangeText(r1, c1, r2, c2: int): string =
  if r1 == r2 and c1 == c2: cellName(r1, c1) else: cellName(r1, c1) & ":" & cellName(r2, c2)

proc parseRangeText(t: string): (bool, int, int, int, int) =
  let refs = formulaRefs("=" & t.strip.toUpperAscii.replace("$", ""))
  if refs.len != 1: return (false, 0, 0, 0, 0)
  (true, refs[0].r1, refs[0].c1, refs[0].r2, refs[0].c2)
