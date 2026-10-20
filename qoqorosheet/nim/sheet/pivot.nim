## PivotTable, included into view.nim: Excel's Insert > PivotTable over the
## current region (its first row the field names; pivotTable.js in
## Luckysheet): pick the Rows, Columns and Values fields and how values sum
## up; the table goes on a new sheet with grand totals, and Refresh rebuilds
## it from the source.

proc aggregate(agg: string, xs: seq[float64], count: int): Value =
  case agg
  of "COUNT": numVal(float64(count))
  of "AVERAGE": (if xs.len > 0: numVal(xs.foldl(a + b, 0.0) / float64(xs.len)) else: errVal("#DIV/0!"))
  of "MAX": (if xs.len > 0: numVal(xs.foldl(max(a, b), xs[0])) else: numVal(0))
  of "MIN": (if xs.len > 0: numVal(xs.foldl(min(a, b), xs[0])) else: numVal(0))
  else: numVal(xs.foldl(a + b, 0.0))

proc buildPivot(v: SheetView, def: PivotDef, target: Sheet) =
  ## the pivot of `def` written into `target` (its cells replaced)
  let src = v.wb.sheetNamed(def.source)
  target.cells.clear(); target.merges.setLen(0)
  target.recomputeUsed()
  if src.isNil: return
  proc text(r, c: int): string = (let t = v.wb.displayText(src.cellAt(r, c)); if t.len == 0: "(blank)" else: t)
  var rowKeys, colKeys: seq[(Value, string)]
  var rowSeen, colSeen: HashSet[string]
  var cells = initTable[(string, string), (seq[float64], int)]()
  for r in def.r1 + 1 .. def.r2:
    let rk = if def.rowField >= 0: text(r, def.rowField) else: "Total"
    let ck = if def.colField >= 0: text(r, def.colField) else: ""
    if rk notin rowSeen: rowSeen.incl rk; rowKeys.add (src.cellAt(r, max(def.rowField, 0)).value, rk)
    if ck notin colSeen: colSeen.incl ck; colKeys.add (src.cellAt(r, max(def.colField, 0)).value, ck)
    let cell = src.cellAt(r, def.valueField)
    for kk in [(rk, ck), (rk, "\0total"), ("\0total", ck), ("\0total", "\0total")]:
      var e = cells.getOrDefault(kk)
      if cell.value.kind == vkNum: e[0].add cell.value.num
      if cell.value.kind != vkEmpty: inc e[1]
      cells[kk] = e
  let byValue = proc(a, b: (Value, string)): int = compareValues(a[0], b[0])
  rowKeys.sort(byValue); colKeys.sort(byValue)
  let valueName = v.wb.displayText(src.cellAt(def.r1, def.valueField))
  let aggName = case def.agg
    of "COUNT": "Count"
    of "AVERAGE": "Average"
    of "MAX": "Max"
    of "MIN": "Min"
    else: "Sum"
  var bold = v.wb.styles[0]; bold.bold = true
  var head = bold; head.fill = "#dde7f5"; head.bottom = Border(kind: bkThin, color: "#8ea9db")
  let headId = v.wb.styleId(head)
  let boldId = v.wb.styleId(bold)
  proc put(r, c: int, val: Value, style = 0'i32) = target.putCell(r, c, Cell(value: val, style: style))
  put(0, 0, strVal(aggName & " of " & valueName), headId)
  let withCols = def.colField >= 0
  if withCols:
    put(0, 1, strVal(v.wb.displayText(src.cellAt(def.r1, def.colField)) & " ▾"), headId)
  put(1, 0, strVal(if def.rowField >= 0: v.wb.displayText(src.cellAt(def.r1, def.rowField)) else: ""), headId)
  let cols = if withCols: colKeys.mapIt(it[1]) else: @[""]
  for j, ck in cols: put(1, 1 + j, strVal(if withCols: ck else: aggName & " of " & valueName), headId)
  if withCols: put(1, 1 + cols.len, strVal("Grand Total"), headId)
  for i, (_, rk) in rowKeys:
    put(2 + i, 0, strVal(rk))
    for j, ck in cols:
      if cells.hasKey((rk, ck)):
        let (xs, n) = cells[(rk, ck)]
        put(2 + i, 1 + j, aggregate(def.agg, xs, n))
    if withCols:
      let (xs, n) = cells[(rk, "\0total")]
      put(2 + i, 1 + cols.len, aggregate(def.agg, xs, n), boldId)
  let last = 2 + rowKeys.len
  put(last, 0, strVal("Grand Total"), headId)
  for j, ck in cols:
    let (xs, n) = cells.getOrDefault(("\0total", if withCols: ck else: ""))
    let (allXs, allN) = cells.getOrDefault(("\0total", "\0total"))
    if withCols: put(last, 1 + j, aggregate(def.agg, xs, n), headId)
    else: put(last, 1 + j, aggregate(def.agg, allXs, allN), headId)
  if withCols:
    let (xs, n) = cells.getOrDefault(("\0total", "\0total"))
    put(last, 1 + cols.len, aggregate(def.agg, xs, n), headId)
  target.colWidths[0] = 140
  target.recomputeUsed()

proc pivotDialog*(v: SheetView) =
  let s = v.sheet
  var (r1, c1, r2, c2) = v.selRect()
  if r1 == r2 and c1 == c2: (r1, c1, r2, c2) = s.currentRegion(v.ar, v.ac)
  r2 = min(r2, s.maxRow - 1); c2 = min(c2, s.maxCol - 1)
  if r2 <= r1 or c2 < c1:
    v.tooltipInfo("PivotTable", "Select a range with a row of field names and data under it."); return
  var fields: seq[(string, string)]
  for c in c1 .. c2:
    let n = v.wb.displayText(s.cellAt(r1, c))
    fields.add ($c, if n.len > 0: n else: "Column " & colName(c))
  let none = @[("-1", "(none)")] & fields
  var valueDefault = $c2
  for c in countdown(c2, c1):
    if s.cellAt(r1 + 1, c).value.kind == vkNum: valueDefault = $c; break
  let body = dlgRow("Source", "<b>" & esc(s.name) & "!" & rangeText(r1, c1, r2, c2) & "</b>") &
    dlgRow("Rows", dlgSelect("rows", fields, $c1)) & dlgRow("Columns", dlgSelect("cols", none, "-1")) &
    dlgRow("Values", dlgSelect("values", fields, valueDefault)) &
    dlgRow("Summarize by", dlgSelect("agg", @[("SUM", "Sum"), ("COUNT", "Count"), ("AVERAGE", "Average"), ("MAX", "Max"), ("MIN", "Min")], "SUM"))
  let srcName = s.name
  discard v.openDialog("qs-pivot", "Create PivotTable", body, @[("ok", "OK"), ("cancel", "Cancel")], proc(b: string, box: Node): bool =
    if b != "ok": return true
    let def = PivotDef(source: srcName, r1: r1, c1: c1, r2: r2, c2: c2, rowField: parseInt(box.field("rows")),
      colField: parseInt(box.field("cols")), valueField: parseInt(box.field("values")), agg: box.field("agg"))
    var n = 1
    while v.wb.sheetNamed("PivotTable" & $n) != nil: inc n
    let target = v.wb.addSheet("PivotTable" & $n)
    target.pivot = def
    v.buildPivot(def, target)
    v.undo.setLen(0); v.redo.setLen(0)          # a new sheet, as Excel's Insert PivotTable
    if v.onChange != nil: v.onChange()
    v.activate(v.wb.sheets.high)
    true, 380)

proc refreshPivot*(v: SheetView) =
  let s = v.sheet
  if s.pivot.source.len == 0:
    v.tooltipInfo("PivotTable", "Select a PivotTable sheet to refresh."); return
  let def = s.pivot
  v.structural(proc() = v.buildPivot(def, s), guard = false)
