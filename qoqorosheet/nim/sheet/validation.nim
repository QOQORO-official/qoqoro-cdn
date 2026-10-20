## Data Validation, included into view.nim: Excel's dialog (Allow: any value,
## list, whole number, decimal, date, text length; the operator and values;
## the error message), the list's in-cell arrow and dropdown
## (#luckysheet-dataVerification-dropdown-btn / -List, dataVerificationCtrl.js),
## and the Stop alert when an entry breaks the rule (Retry / Cancel).

const DvOps = [("between", "between"), ("notBetween", "not between"), ("equal", "equal to"), ("notEqual", "not equal to"),
  ("greaterThan", "greater than"), ("lessThan", "less than"), ("greaterThanOrEqual", "greater than or equal to"),
  ("lessThanOrEqual", "less than or equal to")]

proc validationDialog*(v: SheetView) =
  let s = v.sheet
  let (r1, c1, r2, c2) = v.selRect()
  let at = s.validationAt(v.ar, v.ac)
  let dv = if at >= 0: s.validations[at] else: Validation(kind: dvAny, op: "between", allowBlank: true)
  let kinds = @[("any", "Any value"), ("list", "List"), ("whole", "Whole number"), ("decimal", "Decimal"), ("date", "Date"), ("length", "Text length")]
  let kindName = case dv.kind
    of dvList: "list"
    of dvWhole: "whole"
    of dvDecimal: "decimal"
    of dvDate: "date"
    of dvTextLength: "length"
    else: "any"
  let body = dlgRow("Allow", dlgSelect("kind", kinds, kindName)) &
    "<div class=\"qs-dv-list\">" & dlgRow("Source", dlgInput("list", dv.list, 220, "Yes,No  or  =$A$1:$A$5")) & "</div>" &
    "<div class=\"qs-dv-num\">" & dlgRow("Data", dlgSelect("op", DvOps.toSeq, if dv.op.len > 0: dv.op else: "between")) &
    dlgRow("Minimum / value", dlgInput("v1", dv.v1, 160)) & dlgRow("Maximum", dlgInput("v2", dv.v2, 160)) & "</div>" &
    dlgRow("", dlgCheck("blank", "Ignore blank", dv.allowBlank)) &
    dlgRow("Error message", dlgInput("error", dv.error, 220, "This value doesn't match the data validation restrictions defined for this cell.")) &
    dlgRow("Applies to", dlgInput("range", rangeText(r1, c1, r2, c2), 160))
  let box = v.openDialog("qs-dv", "Data Validation", body, @[("ok", "OK"), ("clear", "Clear All"), ("cancel", "Cancel")], proc(b: string, box: Node): bool =
    if b == "cancel": return true
    let (ok, a, bb, c, d) = parseRangeText(box.field("range"))
    if not ok: v.tooltipInfo("Data Validation", "Enter a range such as A1:B10."); return false
    var nv = Validation(r1: a, c1: bb, r2: c, c2: d, op: box.field("op"), v1: box.field("v1").strip, v2: box.field("v2").strip,
      list: box.field("list").strip, allowBlank: box.field("blank").len > 0, error: box.field("error"))
    nv.kind = case box.field("kind")
      of "list": dvList
      of "whole": dvWhole
      of "decimal": dvDecimal
      of "date": dvDate
      of "length": dvTextLength
      else: dvAny
    if nv.kind == dvList and nv.list.len == 0: v.tooltipInfo("Data Validation", "Enter the list's items or a range."); return false
    v.structural(proc() =
      # a new rule replaces what it covers (Excel)
      s.validations = s.validations.filterIt(it.r1 < a or it.r2 > c or it.c1 < bb or it.c2 > d)
      if b == "ok" and nv.kind != dvAny: s.validations.add nv)
    v.placeOverlays()
    true, 420)
  let kind = box.query("[name=kind]")
  proc sync() =
    let k = kind.value
    box.query(".qs-dv-list").style("display", if k == "list": "block" else: "none")
    box.query(".qs-dv-num").style("display", if k in ["whole", "decimal", "date", "length"]: "block" else: "none")
  kind.on("change", proc(e: Event) = sync())
  sync()

proc entryRejected(v: SheetView, cell: Cell): bool =
  ## Excel's Stop alert: the entry breaks the active cell's validation
  let s = v.sheet
  let at = s.validationAt(v.ar, v.ac)
  if at < 0: return false
  not v.isValid(s.validations[at], cell)

proc stopAlert(v: SheetView, text: string) =
  ## Retry edits the entry again; Cancel drops it
  let s = v.sheet
  let at = s.validationAt(v.ar, v.ac)
  let msg = if at >= 0 and s.validations[at].error.len > 0: esc(s.validations[at].error)
            else: "This value doesn't match the data validation restrictions defined for this cell."
  discard v.openDialog("qs-dv-stop", "Microsoft Excel", "<p style=\"margin:4px 0\"><span style=\"color:#d00;font-size:18px;margin-right:8px\">⛔</span>" & msg & "</p>",
    @[("retry", "Retry"), ("cancel", "Cancel")], proc(b: string, box: Node): bool =
      if b == "retry":
        v.closeDialog(box)
        v.beginEdit(text)
        return false
      true)

# ------------------------------------------------------- the list dropdown --

proc closeDvList(v: SheetView) =
  let l = byId("luckysheet-dataVerification-dropdown-List")
  if not l.isNil: l.style("display", "none")

proc placeDvButton(v: SheetView) =
  ## the arrow beside the active cell when it has a list
  let btn = byId("luckysheet-dataVerification-dropdown-btn")
  if btn.isNil: return
  let s = v.sheet
  let at = s.validationAt(v.ar, v.ac)
  if at < 0 or s.validations[at].kind != dvList or v.editing:
    btn.style("display", "none"); return
  let (x, y, w, h) = v.cellBox(v.ar, v.ac)
  btn.setAttribute("style", "display:block;position:absolute;z-index:30;left:" & px(x + w + 2) & ";top:" & px(y + max(0.0, h - 18)) &
    ";width:16px;height:16px;background:#fff;border:1px solid #c6c6c6;cursor:pointer;text-align:center;line-height:14px;font-size:10px;color:#555")
  btn.setProp("innerHTML", "<i class=\"fa fa-caret-down luckysheet-mousedown-cancel\"></i>")
  btn.addClass("luckysheet-mousedown-cancel")

proc openDvList(v: SheetView) =
  let s = v.sheet
  let at = s.validationAt(v.ar, v.ac)
  if at < 0: return
  let list = byId("luckysheet-dataVerification-dropdown-List")
  let current = v.wb.displayText(s.cellAt(v.ar, v.ac))
  var html = ""
  for it in v.listItems(s.validations[at]):
    html.add "<div class=\"dropdown-List-item luckysheet-mousedown-cancel\" data-value=\"" & esc(it) & "\" style=\"padding:3px 8px;cursor:pointer;" &
      (if it == current: "background:#e8f0fe;" else: "") & "\">" & esc(it) & "</div>"
  list.setProp("innerHTML", html)
  let (x, y, w, h) = v.cellBox(v.ar, v.ac)
  list.setAttribute("style", "display:block;position:absolute;z-index:31;background:#fff;border:1px solid #c6c6c6;box-shadow:0 2px 6px rgba(0,0,0,.2);max-height:200px;overflow:auto;left:" &
    px(x) & ";top:" & px(y + h + 2) & ";min-width:" & px(w + 18))
  list.addClass("luckysheet-mousedown-cancel")
  for item_1 in list.queryAll(".dropdown-List-item"):
    let item_0 = item_1
    closureScope:
      let item = item_0
      item.on("mouseenter", proc(e: Event) = item.style("background", "#e8f0fe"))
      item.on("mouseleave", proc(e: Event) = item.style("background", ""))
      item.on("click", proc(e: Event) =
        let value = item.invoke("getAttribute", "data-value").toStr
        v.closeDvList()
        var act: Action
        v.setCellRaw(v.wb.active, v.ar, v.ac, parseInput(v.wb, value, v.sheet.cellAt(v.ar, v.ac)), act)
        v.commitAction(act)
        v.refreshFormulaBar(); v.requestDraw()
        v.editor.focus(true))

proc bindValidation(v: SheetView) =
  let btn = byId("luckysheet-dataVerification-dropdown-btn")
  if not btn.isNil:
    btn.on("mousedown", proc(e: Event) =
      e.preventDefault(); e.stopPropagation()
      let list = byId("luckysheet-dataVerification-dropdown-List")
      if list.getStr("style").contains("display: block") or list.getStr("style").contains("display:block"): v.closeDvList()
      else: v.openDvList())
  document.on("mousedown", proc(e: Event) =
    if not e.target.matches("#luckysheet-dataVerification-dropdown-List, #luckysheet-dataVerification-dropdown-List *, #luckysheet-dataVerification-dropdown-btn, #luckysheet-dataVerification-dropdown-btn *"):
      v.closeDvList())
