## Conditional formatting and data validation — what a cell's rules make of
## it — included into view.nim before the drawing. Excel's rules: every rule
## that matches a cell applies, the first in the list winning a property both
## set (Luckysheet's conditionformat.js checksCF does the same with its
## luckysheet_conditionformat_save order).

type
  CfStats = object               ## what a rule needs to know of its whole range
    lo, hi, mid, avg, threshold: float64
    counts: Table[string, int]
  CfOut = object                 ## what the rules make of one cell
    fill, color: string
    bold: bool
    bar: float64                 ## a data bar's length (0 .. 1); NaN none
    barColor: string

proc ruleValues(s: Sheet, rule: CondRule): seq[(int, int, Cell)] =
  let r2 = min(rule.r2, s.maxRow - 1)
  let c2 = min(rule.c2, s.maxCol - 1)
  if (r2 - rule.r1 + 1) * (c2 - rule.c1 + 1) < s.cells.len:
    for r in rule.r1 .. r2:
      for c in rule.c1 .. c2:
        let k = key(r, c)
        if s.cells.hasKey(k): result.add (r, c, s.cells[k])
  else:
    for k, cell in s.cells:
      let (r, c) = (rowOf(k), colOf(k))
      if r >= rule.r1 and r <= r2 and c >= rule.c1 and c <= c2: result.add (r, c, cell)

proc cfKey(v: SheetView, cell: Cell): string = v.wb.displayText(cell).toLowerAscii

proc ruleStats(v: SheetView, s: Sheet, rule: CondRule): CfStats =
  var nums: seq[float64]
  for (_, _, cell) in s.ruleValues(rule):
    if cell.value.kind == vkNum: nums.add cell.value.num
    if rule.kind in {ckDuplicate, ckUnique} and cell.value.kind != vkEmpty:
      let k = v.cfKey(cell)
      result.counts[k] = result.counts.getOrDefault(k) + 1
  if nums.len == 0: return
  nums.sort()
  result.lo = nums[0]; result.hi = nums[^1]
  result.mid = nums[nums.len div 2]
  result.avg = nums.foldl(a + b, 0.0) / float64(nums.len)
  if rule.kind in {ckTop, ckBottom}:
    var n = try: parseInt(rule.v1.strip) except ValueError: 10
    if rule.v2 == "%": n = max(1, int(float64(nums.len) * float64(n) / 100))
    n = clamp(n, 1, nums.len)
    result.threshold = if rule.kind == ckTop: nums[nums.len - n] else: nums[n - 1]

proc ruleNumber(v: SheetView, s: Sheet, text: string): (bool, float64) =
  ## a rule's value: a number, or a formula giving one
  let t = text.strip
  if t.startsWith("="):
    let x = evalFormulaAt(v.wb, s, t)
    if x.kind == vkNum: return (true, x.num)
    return (false, 0.0)
  try: (true, parseFloat(t)) except ValueError: (false, 0.0)

proc truthy(x: Value): bool =
  case x.kind
  of vkBool: x.b
  of vkNum: x.num != 0
  of vkStr: cmpIgnoreCase(x.str, "TRUE") == 0
  of vkArr: x.items.len > 0 and truthy(x.items[0])
  else: false

proc hexRgb(c: string): (int, int, int) =
  if c.len == 7 and c[0] == '#':
    try: return (parseHexInt(c[1..2]), parseHexInt(c[3..4]), parseHexInt(c[5..6])) except ValueError: discard
  (255, 255, 255)

proc mixColor(a, b: string, t: float64): string =
  let (r1, g1, b1) = hexRgb(a)
  let (r2, g2, b2) = hexRgb(b)
  proc ch(x, y: int): string = toHex(int(round(float64(x) + (float64(y) - float64(x)) * clamp(t, 0.0, 1.0))), 2).toLowerAscii
  "#" & ch(r1, r2) & ch(g1, g2) & ch(b1, b2)

proc cfPrepare(v: SheetView): seq[CfStats] =
  ## the stats of the active sheet's rules, once per frame
  let s = v.sheet
  for rule in s.condRules: result.add v.ruleStats(s, rule)

proc cfFor(v: SheetView, stats: seq[CfStats], r, c: int, cell: Cell): CfOut =
  result.bar = NaN
  let s = v.sheet
  for i, rule in s.condRules:
    if r < rule.r1 or r > rule.r2 or c < rule.c1 or c > rule.c2: continue
    let st = stats[i]
    let isNum = cell.value.kind == vkNum
    let x = if isNum: cell.value.num else: 0.0
    var hit = false
    case rule.kind
    of ckGreater, ckLess, ckBetween:
      let (ok1, a) = v.ruleNumber(s, rule.v1)
      if isNum and ok1:
        case rule.kind
        of ckGreater: hit = x > a
        of ckLess: hit = x < a
        else:
          let (ok2, b) = v.ruleNumber(s, rule.v2)
          hit = ok2 and x >= min(a, b) and x <= max(a, b)
    of ckEqual:
      let (ok1, a) = v.ruleNumber(s, rule.v1)
      hit = if isNum and ok1: x == a else: cell.value.kind != vkEmpty and cmpIgnoreCase(v.wb.displayText(cell), rule.v1.strip(chars = {'"', ' '})) == 0
    of ckTextContains:
      hit = rule.v1.len > 0 and cell.value.kind != vkEmpty and rule.v1.toLowerAscii in v.cfKey(cell)
    of ckDuplicate: hit = cell.value.kind != vkEmpty and st.counts.getOrDefault(v.cfKey(cell)) > 1
    of ckUnique: hit = cell.value.kind != vkEmpty and st.counts.getOrDefault(v.cfKey(cell)) == 1
    of ckTop: hit = isNum and x >= st.threshold
    of ckBottom: hit = isNum and x <= st.threshold
    of ckAboveAverage: hit = isNum and x > st.avg
    of ckBelowAverage: hit = isNum and x < st.avg
    of ckFormula: hit = truthy(evalFormulaAt(v.wb, s, rule.v1, r - rule.r1, c - rule.c1))
    of ckDataBar:
      if isNum and result.bar != result.bar:
        let lo = min(0.0, st.lo)
        result.bar = if st.hi > lo: (x - lo) / (st.hi - lo) else: 1.0
        result.barColor = if rule.colors.len > 0: rule.colors[0] else: "#638ec6"
    of ckColorScale:
      if isNum and result.fill.len == 0 and rule.colors.len >= 2:
        if rule.colors.len >= 3:
          result.fill = if x <= st.mid: mixColor(rule.colors[0], rule.colors[1], (if st.mid > st.lo: (x - st.lo) / (st.mid - st.lo) else: 0.0))
                        else: mixColor(rule.colors[1], rule.colors[2], (if st.hi > st.mid: (x - st.mid) / (st.hi - st.mid) else: 1.0))
        else:
          result.fill = mixColor(rule.colors[0], rule.colors[1], (if st.hi > st.lo: (x - st.lo) / (st.hi - st.lo) else: 0.0))
    if hit:
      if result.fill.len == 0: result.fill = rule.fill
      if result.color.len == 0: result.color = rule.color
      result.bold = result.bold or rule.bold

# -------------------------------------------------------------- validation --

proc validationAt*(s: Sheet, r, c: int): int =
  ## the validation covering a cell (the last one set wins, as Excel replaces), or -1
  result = -1
  for i, dv in s.validations:
    if r >= dv.r1 and r <= dv.r2 and c >= dv.c1 and c <= dv.c2: result = i

proc listItems(v: SheetView, dv: Validation): seq[string] =
  ## a list validation's choices: its own items, or a range's values
  let src = dv.list.strip
  if src.startsWith("="):
    let x = evalFormulaAt(v.wb, v.sheet, src)
    if x.kind == vkArr:
      for it in x.items:
        let t = toText(it)
        if it.kind != vkEmpty and t.len > 0 and t notin result: result.add t
    elif x.kind != vkEmpty and x.kind != vkErr: result.add toText(x)
  else:
    for part in src.split(','):
      let t = part.strip
      if t.len > 0: result.add t

proc compareOp(op: string, x, a, b: float64): bool =
  case op
  of "notBetween": x < min(a, b) or x > max(a, b)
  of "equal": x == a
  of "notEqual": x != a
  of "greaterThan": x > a
  of "lessThan": x < a
  of "greaterThanOrEqual": x >= a
  of "lessThanOrEqual": x <= a
  else: x >= min(a, b) and x <= max(a, b)

proc dvNumber(v: SheetView, text: string, date: bool): (bool, float64) =
  let t = text.strip
  if date:
    let parsed = parseInput(v.wb, t, Cell())
    if parsed.value.kind == vkNum: return (true, parsed.value.num)
  v.ruleNumber(v.sheet, t)

proc isValid(v: SheetView, dv: Validation, cell: Cell): bool =
  ## Excel's check of an entry against a cell's validation.
  if cell.value.kind == vkEmpty: return dv.allowBlank or true   # Excel lets a cell be cleared
  case dv.kind
  of dvAny: true
  of dvList:
    let t = v.wb.displayText(cell)
    for it in v.listItems(dv):
      if cmpIgnoreCase(it, t) == 0: return true
    false
  of dvWhole, dvDecimal, dvDate:
    if cell.value.kind != vkNum: return false
    let x = cell.value.num
    if dv.kind == dvWhole and x != floor(x): return false
    let (ok1, a) = v.dvNumber(dv.v1, dv.kind == dvDate)
    let (ok2, b) = v.dvNumber(dv.v2, dv.kind == dvDate)
    if not ok1: return true
    compareOp(dv.op, x, a, if ok2: b else: a)
  of dvTextLength:
    let n = float64(v.wb.displayText(cell).toRunes.len)
    let (ok1, a) = v.ruleNumber(v.sheet, dv.v1)
    let (ok2, b) = v.ruleNumber(v.sheet, dv.v2)
    if not ok1: return true
    compareOp(dv.op, n, a, if ok2: b else: a)
