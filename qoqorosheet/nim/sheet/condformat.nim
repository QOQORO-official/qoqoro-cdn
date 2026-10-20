## Conditional formatting commands, included into view.nim: Excel's
## Conditional Formatting menu (Highlight Cells Rules, Top/Bottom Rules, Data
## Bars, Color Scales, New Rule with a formula, Clear Rules, Manage Rules) on
## Luckysheet's dropdown and dialogs (conditionformat.js). Rules are drawn
## by rules.nim.

const
  CfFormats = [("red", "Light Red Fill with Dark Red Text", "#ffc7ce", "#9c0006"),
    ("yellow", "Yellow Fill with Dark Yellow Text", "#ffeb9c", "#9c5700"),
    ("green", "Green Fill with Dark Green Text", "#c6efce", "#006100"),
    ("redfill", "Light Red Fill", "#ffc7ce", ""), ("redtext", "Red Text", "", "#ff0000"),
    ("bold", "Bold", "", "")]
  CfKindNames = [ckGreater: "Greater Than", ckLess: "Less Than", ckBetween: "Between", ckEqual: "Equal To",
    ckTextContains: "Text that Contains", ckDuplicate: "Duplicate Values", ckUnique: "Unique Values",
    ckTop: "Top 10 Items", ckBottom: "Bottom 10 Items", ckAboveAverage: "Above Average", ckBelowAverage: "Below Average",
    ckFormula: "Use a formula", ckDataBar: "Data Bar", ckColorScale: "Color Scale"]

proc addRule(v: SheetView, rule: CondRule) =
  let s = v.sheet
  v.structural(proc() = s.condRules.insert(rule, 0))      # the newest rule comes first (Excel)

proc formatRule(rule: var CondRule, fmt: string) =
  for (id, _, fill, color) in CfFormats:
    if id == fmt: rule.fill = fill; rule.color = color
  rule.bold = fmt == "bold"

proc ruleDialog(v: SheetView, kind: CondKind) =
  ## Excel's small "Greater Than…" dialog: the value(s), then the format
  let (r1, c1, r2, c2) = v.selRect()
  var body = "<div style=\"margin-bottom:6px;color:#555\">Format cells " & (case kind
    of ckGreater: "that are GREATER THAN:"
    of ckLess: "that are LESS THAN:"
    of ckBetween: "that are BETWEEN:"
    of ckEqual: "that are EQUAL TO:"
    of ckTextContains: "that contain the text:"
    of ckTop: "that rank in the TOP:"
    of ckBottom: "that rank in the BOTTOM:"
    of ckFormula: "where this formula is true (relative to " & cellName(r1, c1) & "):"
    else: "") & "</div>"
  case kind
  of ckBetween: body.add dlgInput("v1", "", 120) & " and " & dlgInput("v2", "", 120)
  of ckTop, ckBottom: body.add dlgInput("v1", "10", 60) & " " & dlgCheck("pct", "%")
  of ckDuplicate, ckUnique, ckAboveAverage, ckBelowAverage: discard
  else: body.add dlgInput("v1", (if kind == ckFormula: "=" else: ""), 250)
  body.add dlgRow("with", dlgSelect("fmt", CfFormats.mapIt((it[0], it[1])), "red"))
  body.add dlgRow("Applies to", dlgInput("range", rangeText(r1, c1, r2, c2), 160))
  discard v.openDialog("qs-cf-rule", CfKindNames[kind], body, @[("ok", "OK"), ("cancel", "Cancel")], proc(b: string, box: Node): bool =
    if b != "ok": return true
    let (ok, a, bb, c, d) = parseRangeText(box.field("range"))
    if not ok: v.tooltipInfo("Conditional Formatting", "Enter a range such as A1:B10."); return false
    var rule = CondRule(r1: a, c1: bb, r2: c, c2: d, kind: kind, v1: box.field("v1").strip, v2: box.field("v2").strip)
    if kind in {ckTop, ckBottom} and box.field("pct").len > 0: rule.v2 = "%"
    if kind in {ckGreater, ckLess, ckBetween, ckEqual, ckTextContains, ckFormula} and rule.v1.len == 0:
      v.tooltipInfo("Conditional Formatting", "Enter a value."); return false
    rule.formatRule(box.field("fmt"))
    v.addRule(rule)
    true)

proc quickRule(v: SheetView, kind: CondKind, colors: seq[string]) =
  let (r1, c1, r2, c2) = v.selRect()
  v.addRule(CondRule(r1: r1, c1: c1, r2: r2, c2: c2, kind: kind, colors: colors))

proc clearRules(v: SheetView, wholeSheet: bool) =
  let s = v.sheet
  let (r1, c1, r2, c2) = v.selRect()
  v.structural(proc() =
    if wholeSheet: s.condRules.setLen(0)
    else: s.condRules = s.condRules.filterIt(it.r2 < r1 or it.r1 > r2 or it.c2 < c1 or it.c1 > c2))

proc manageRules(v: SheetView) =
  ## Excel's Rules Manager: the sheet's rules, newest first; delete one
  let s = v.sheet
  var body = "<div style=\"max-height:300px;overflow:auto;min-width:420px\">"
  if s.condRules.len == 0: body.add "<p style=\"color:#777\">This sheet has no rules.</p>"
  for i, rule in s.condRules:
    var what = CfKindNames[rule.kind]
    if rule.v1.len > 0: what.add " " & esc(rule.v1)
    if rule.kind == ckBetween: what.add " and " & esc(rule.v2)
    let sample = if rule.colors.len > 0: rule.colors.mapIt("<span style=\"display:inline-block;width:14px;height:14px;background:" & it & "\"></span>").join("")
                 else: "<span style=\"padding:0 6px;background:" & (if rule.fill.len > 0: rule.fill else: "#fff") & ";color:" &
                   (if rule.color.len > 0: rule.color else: "#000") & (if rule.bold: ";font-weight:bold" else: "") & "\">AaBbCc</span>"
    body.add "<div style=\"display:flex;gap:10px;align-items:center;padding:4px 0;border-bottom:1px solid #eee\"><span style=\"flex:1\">" & what &
      "</span>" & sample & "<span style=\"width:90px\">" & rangeText(rule.r1, rule.c1, rule.r2, rule.c2) &
      "</span><button class=\"btn btn-default\" data-btn=\"del" & $i & "\">Delete</button></div>"
  body.add "</div>"
  discard v.openDialog("qs-cf-manage", "Conditional Formatting Rules Manager", body, @[("close", "Close")], proc(b: string, box: Node): bool =
    if b.startsWith("del"):
      let i = parseInt(b[3 .. ^1])
      v.structural(proc() = s.condRules.delete(i))
      v.closeDialog(box)
      v.manageRules()
      return false
    true, 460)

proc openCfMenu(v: SheetView, anchor: Node) =
  v.openRibbonMenu(anchor, @[
    ("<b>Highlight Cells Rules</b>", "", false), ("&nbsp;&nbsp;Greater Than…", "gt", false), ("&nbsp;&nbsp;Less Than…", "lt", false),
    ("&nbsp;&nbsp;Between…", "between", false), ("&nbsp;&nbsp;Equal To…", "eq", false), ("&nbsp;&nbsp;Text that Contains…", "text", false),
    ("&nbsp;&nbsp;Duplicate Values…", "dup", false), ("&nbsp;&nbsp;Unique Values…", "uniq", false),
    ("<b>Top/Bottom Rules</b>", "", false), ("&nbsp;&nbsp;Top 10 Items…", "top", false), ("&nbsp;&nbsp;Bottom 10 Items…", "bottom", false),
    ("&nbsp;&nbsp;Above Average…", "above", false), ("&nbsp;&nbsp;Below Average…", "below", false),
    ("<b>Data Bars</b>", "", false), ("&nbsp;&nbsp;<span style=\"background:linear-gradient(90deg,#638ec6,#fff);padding:0 18px\"></span> Blue", "bar-blue", false),
    ("&nbsp;&nbsp;<span style=\"background:linear-gradient(90deg,#63be7b,#fff);padding:0 18px\"></span> Green", "bar-green", false),
    ("&nbsp;&nbsp;<span style=\"background:linear-gradient(90deg,#ff555a,#fff);padding:0 18px\"></span> Red", "bar-red", false),
    ("<b>Color Scales</b>", "", false), ("&nbsp;&nbsp;Green - Yellow - Red", "scale-gyr", false), ("&nbsp;&nbsp;Red - Yellow - Green", "scale-ryg", false),
    ("&nbsp;&nbsp;White - Green", "scale-wg", false),
    ("New Rule (formula)…", "formula", false), ("Clear Rules from Selected Cells", "clear", false),
    ("Clear Rules from Entire Sheet", "clear-sheet", false), ("Manage Rules…", "manage", false)],
    proc(m: string) =
      case m
      of "gt": v.ruleDialog(ckGreater)
      of "lt": v.ruleDialog(ckLess)
      of "between": v.ruleDialog(ckBetween)
      of "eq": v.ruleDialog(ckEqual)
      of "text": v.ruleDialog(ckTextContains)
      of "dup": v.ruleDialog(ckDuplicate)
      of "uniq": v.ruleDialog(ckUnique)
      of "top": v.ruleDialog(ckTop)
      of "bottom": v.ruleDialog(ckBottom)
      of "above": v.ruleDialog(ckAboveAverage)
      of "below": v.ruleDialog(ckBelowAverage)
      of "formula": v.ruleDialog(ckFormula)
      of "bar-blue": v.quickRule(ckDataBar, @["#638ec6"])
      of "bar-green": v.quickRule(ckDataBar, @["#63be7b"])
      of "bar-red": v.quickRule(ckDataBar, @["#ff555a"])
      of "scale-gyr": v.quickRule(ckColorScale, @["#63be7b", "#ffeb84", "#f8696b"])
      of "scale-ryg": v.quickRule(ckColorScale, @["#f8696b", "#ffeb84", "#63be7b"])
      of "scale-wg": v.quickRule(ckColorScale, @["#fcfcff", "#63be7b"])
      of "clear": v.clearRules(false)
      of "clear-sheet": v.clearRules(true)
      of "manage": v.manageRules()
      else: discard)
