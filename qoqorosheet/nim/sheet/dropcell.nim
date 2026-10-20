## The fill handle's data rules: Luckysheet's controllers/dropCell.js, ported
## rule for rule, except where Excel differs (the user chose Excel; see
## nim/PARITY.md §9): a lone number copies, 0 is a number, series are linear
## trends, dates continue from the last one, formulas move by their own offset.
##
## Luckysheet keeps a cell's display text in "m"; here it is the cell's
## formatted text (displayText) and dates are numbers with a date format.

import std/[tables, strutils, math, unicode, algorithm]
import model, formula

type
  FillDir* = enum fdDown, fdUp, fdRight, fdLeft
  FillType* = enum                ## applyType "0".."8"
    ftCopy, ftSeries, ftOnlyFormat, ftNoFormat, ftDay, ftWorkDay, ftMonth, ftYear, ftChnNumber
  Run = object                    ## one {data, index} entry of getCopyData
    data: seq[Cell]
    index: seq[int]

proc backward(d: FillDir): bool = d in {fdUp, fdLeft}

# ---------------------------------------------------------------- dates ----
# Excel serials (1900 system): 25569 = 1970-01-01.

proc toCivil(serial: float64): (int, int, int) =
  var z = int(floor(serial)) - 25569 + 719468
  let era = (if z >= 0: z else: z - 146096) div 146097
  let doe = z - era * 146097
  let yoe = (doe - doe div 1460 + doe div 36524 - doe div 146096) div 365
  let doy = doe - (365 * yoe + yoe div 4 - yoe div 100)
  let mp = (5 * doy + 2) div 153
  let d = doy - (153 * mp + 2) div 5 + 1
  let m = if mp < 10: mp + 3 else: mp - 9
  (yoe + era * 400 + (if m <= 2: 1 else: 0), m, d)

proc fromCivil*(y0, m, d: int): float64 =
  let y = if m <= 2: y0 - 1 else: y0
  let era = (if y >= 0: y else: y - 399) div 400
  let yoe = y - era * 400
  let doy = (153 * (if m > 2: m - 3 else: m + 9) + 2) div 5 + d - 1
  let doe = yoe * 365 + yoe div 4 - yoe div 100 + doy
  float64(era * 146097 + doe - 719468 + 25569)

proc daysIn*(y, m: int): int =
  if m == 2: (if (y mod 4 == 0 and y mod 100 != 0) or y mod 400 == 0: 29 else: 28)
  elif m in [4, 6, 9, 11]: 30 else: 31

proc addMonths(serial: float64, n: int): float64 =
  ## dayjs add(n, "months"): the day clamps to the month's end.
  let (y, m, d) = toCivil(serial)
  let t = y * 12 + (m - 1) + n
  let ny = floorDiv(t, 12)
  let nm = floorMod(t, 12) + 1
  fromCivil(ny, nm, min(d, daysIn(ny, nm))) + (serial - floor(serial))

proc weekday(serial: float64): int = floorMod(int(floor(serial)) - 25569 + 4, 7)   ## dayjs .day(): 0 Sunday

proc monthDiffRaw(a, b: float64): float64 =
  ## dayjs's monthDiff(a, b)
  if toCivil(a)[2] < toCivil(b)[2]: return -monthDiffRaw(b, a)
  let (ya, ma, _) = toCivil(a)
  let (yb, mb, _) = toCivil(b)
  let whole = (yb - ya) * 12 + (mb - ma)
  let anchor = addMonths(a, whole)
  let c = b - anchor < 0
  let anchor2 = addMonths(a, whole + (if c: -1 else: 1))
  let r = -(float64(whole) + (b - anchor) / (if c: anchor - anchor2 else: anchor2 - anchor))
  if r != r: 0.0 else: r

proc absFloor(x: float64): int = (if x < 0: int(ceil(x)) else: int(floor(x)))
proc diffDays(x, y: float64): int = absFloor(x - y)                ## x.diff(y, "days")
proc diffMonths(x, y: float64): int = absFloor(-monthDiffRaw(y, x)) ## x.diff(y, "months")
proc diffYears(x, y: float64): int = absFloor(-monthDiffRaw(y, x) / 12)

# ------------------------------------------------------- text categories ----

proc extendNumber(txt: string): (bool, float64, string, string) =
  ## isExtendNumber: the last /0|([1-9]+[0-9]*)/ match, with the text around it.
  var last = (-1, 0)
  var i = 0
  while i < txt.len:
    if txt[i] == '0': last = (i, 1); inc i
    elif txt[i] in {'1'..'9'}:
      var j = i
      while j < txt.len and txt[j] in {'0'..'9'}: inc j
      last = (i, j - i); i = j
    else: inc i
  if last[0] < 0: return (false, 0.0, "", "")
  let m = txt[last[0] ..< last[0] + last[1]]
  let at = txt.rfind(m)
  (true, parseFloat(m), txt[0 ..< at], txt[at + m.len .. ^1])

const ChnDigits = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
const ChnUnits = [("十", 10, false), ("百", 100, false), ("千", 1000, false), ("万", 10000, true), ("亿", 100000000, true)]

proc chnDigit(s: string): int =
  for i, d in ChnDigits:
    if d == s: return i
  -1

proc chineseToNumber(s: string): int =
  var rtn, section, number = 0
  let chars = s.toRunes
  for i, r in chars:
    let ch = $r
    let n = chnDigit(ch)
    if n >= 0:
      number = n
      if i == chars.high: section += number
    else:
      for (u, value, secUnit) in ChnUnits:
        if u == ch:
          if secUnit:
            section = (section + number) * value
            rtn += section
            section = 0
          else: section += number * value
      number = 0
  rtn + section

proc sectionToChinese(section0: int): string =
  const UnitChar = ["", "十", "百", "千"]
  var section = section0
  var unitPos = 0
  var zero = true
  while section > 0:
    let v = section mod 10
    if v == 0:
      if not zero:
        zero = true
        result = ChnDigits[v] & result
    else:
      zero = false
      result = ChnDigits[v] & UnitChar[unitPos] & result
    inc unitPos
    section = section div 10

proc numberToChinese(num0: int): string =
  const UnitSection = ["", "万", "亿", "万亿", "亿亿"]
  if num0 == 0: return ChnDigits[0]
  var num = num0
  var unitPos = 0
  var needZero = false
  while num > 0:
    let section = num mod 10000
    if needZero: result = ChnDigits[0] & result
    result = sectionToChinese(section) & (if section != 0: UnitSection[unitPos] else: UnitSection[0]) & result
    needZero = section < 1000 and section > 0
    num = num div 10000
    inc unitPos

proc isChnNumber(txt: string): bool =
  if txt.len == 0: return true
  let chars = txt.toRunes
  if chars.len == 1: return txt == "日" or chnDigit(txt) >= 0
  for r in chars:
    let ch = $r
    if chnDigit(ch) < 0 and ch notin ["十", "百", "千", "万", "亿"]: return false
  true

const Week2 = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
const Week3 = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"]
const Week1 = ["日", "一", "二", "三", "四", "五", "六"]

proc lastRune(s: string): string = (let r = s.toRunes; if r.len > 0: $r[^1] else: "")

# ---------------------------------------------------------------- cells ----

proc isDate(wb: Workbook, c: Cell): bool =
  c.value.kind == vkNum and isDateFormat(wb.styles[c.style].numFmt)

proc mText(wb: Workbook, c: Cell): string =
  case c.value.kind
  of vkStr: c.value.str
  of vkNum:
    let f = wb.styles[c.style].numFmt
    if f.len > 0: formatNumber(c.value.num, f) else: fmtGeneral(c.value.num)
  else: toText(c.value)

proc truthy(c: Cell): bool =
  case c.value.kind
  of vkEmpty: false
  of vkNum: c.value.num != 0
  of vkStr: c.value.str.len > 0
  of vkBool: c.value.b
  else: true

proc category(wb: Workbook, c: Cell): string =
  ## getCopyData's classes: "!!v" with no formula, by ct type, then by text.
  if c.formula.len > 0: return "other"
  if c.value.kind == vkNum: return (if wb.isDate(c): "date" else: "number")   # Excel: 0 is a number too
  if not c.truthy: return "other"
  if c.value.kind == vkNum: return (if wb.isDate(c): "date" else: "number")
  let m = wb.mText(c)
  if extendNumber(m)[0]: "extendNumber"
  elif isChnNumber(m): "chnNumber"
  elif m in Week2: "chnWeek2"
  elif m in Week3: "chnWeek3"
  else: "other"

proc fillKinds*(wb: Workbook, s: Sheet, r1, c1, r2, c2: int): array[7, bool] =
  ## typeItemHide: [number, extendNumber, date, chn, chnWeek1, chnWeek2, chnWeek3]
  for r in r1 .. r2:
    for c in c1 .. c2:
      if not s.hasCell(r, c): continue
      let cell = s.cellAt(r, c)
      if cell.value.kind == vkEmpty or cell.formula.len > 0: continue
      let m = wb.mText(cell)
      if cell.value.kind == vkNum and not wb.isDate(cell): result[0] = true
      elif wb.isDate(cell): result[2] = true
      elif extendNumber(m)[0]: result[1] = true
      elif isChnNumber(m) and m != "日": result[3] = true
      elif m == "日": result[4] = true
      elif m in Week2: result[5] = true
      elif m in Week3: result[6] = true

# --------------------------------------------------------------- fills -----

proc fillCopy(data: seq[Cell], len: int): seq[Cell] =
  for i in 1 .. len: result.add data[(i - 1) mod data.len]

proc isEqualDiff(arr: seq[float64]): bool =
  let step = arr[1] - arr[0]
  for i in 1 ..< arr.len:
    if arr[i] - arr[i - 1] != step: return false
  true

proc isEqualRatio(arr: seq[float64]): bool =
  let step = arr[1] / arr[0]
  for i in 1 ..< arr.len:
    if arr[i] / arr[i - 1] != step: return false
  true

proc forecast(x: float64, yArr: seq[float64]): float64 =
  ## the least-squares line through (1, y1) … (n, yn), at x; rounded to 5 places
  var ax, ay = 0.0
  for i, y in yArr: ax += float64(i + 1); ay += y
  ax /= float64(yArr.len); ay /= float64(yArr.len)
  var sd, sn = 0.0
  for i, y in yArr:
    let x = float64(i + 1)
    sd += (x - ax) * (y - ay)
    sn += (x - ax) * (x - ax)
  let b = if sn == 0: 1.0 else: sd / sn
  round((ay - b * ax + b * x) * 100000) / 100000

proc fillSeries(data: seq[Cell], len: int, dir: FillDir, auto: bool): seq[Cell] =
  ## Excel: a drag continues the linear trend of 2+ numbers and copies a lone
  ## number; choosing "Sequence" counts a lone number up by 1.
  if auto and data.len == 1: return fillCopy(data, len)
  var nums: seq[float64]
  for c in data: nums.add c.value.num
  for i in 1 .. len:
    var d = data[(i - 1) mod data.len]
    d.value = numVal(if dir.backward: forecast(float64(1 - i), nums) else: forecast(float64(data.len + i), nums))
    result.add d

proc fillExtendNumber(wb: Workbook, data: seq[Cell], len: int, step: float64): seq[Cell] =
  let last = wb.mText(data[^1])
  let (_, n, before, after) = extendNumber(last)
  for i in 1 .. len:
    var d = data[(i - 1) mod data.len]
    let num = abs(n + step * float64(i))
    d.value = strVal(before & (if num == floor(num) and abs(num) < 1e15: $int64(num) else: $num) & after)
    result.add d

proc fillOnlyFormat(data: seq[Cell], len: int): seq[Cell] =
  for i in 1 .. len: result.add Cell(style: data[(i - 1) mod data.len].style)

proc fillWithoutFormat(arr: seq[Cell]): seq[Cell] =
  for d in arr:
    var c = Cell(value: d.value)
    if d.formula.len > 0: c.setFormula(d.formula)
    result.add c

proc fillDays(data: seq[Cell], len: int, step: int): seq[Cell] =
  for i in 1 .. len:
    var d = data[(i - 1) mod data.len]
    d.value = numVal(floor(data[^1].value.num) + float64(step * i))   # Excel: from the last date
    result.add d

proc fillMonths(data: seq[Cell], len: int, step: int): seq[Cell] =
  for i in 1 .. len:
    var d = data[(i - 1) mod data.len]
    d.value = numVal(floor(addMonths(data[^1].value.num, step * i)))   # Excel: from the last date
    result.add d

proc fillYears(data: seq[Cell], len: int, step: int): seq[Cell] =
  for i in 1 .. len:
    var d = data[(i - 1) mod data.len]
    d.value = numVal(floor(addMonths(data[^1].value.num, 12 * step * i)))   # Excel: from the last date
    result.add d

proc fillWeek(wb: Workbook, data: seq[Cell], len: int, step: int, names: openArray[string], sunday: string): seq[Cell] =
  ## FillChnWeek / FillChnWeek2 / FillChnWeek3
  let last = wb.mText(data[^1])
  for i in 1 .. len:
    var d = data[(i - 1) mod data.len]
    var num = if last == sunday: 7 + step * i
              else: chineseToNumber(if names.len > 0 and names[0].toRunes.len > 1: last.lastRune else: last) + step * i
    if num < 0: num = int(ceil(abs(num) / 7)) * 7 + num
    d.value = strVal(names[num mod 7])
    result.add d

proc fillChnNumber(wb: Workbook, data: seq[Cell], len: int, step: int): seq[Cell] =
  let last = chineseToNumber(wb.mText(data[^1]))
  for i in 1 .. len:
    var d = data[(i - 1) mod data.len]
    let num = last + step * i
    d.value = strVal(if num <= 0: "零" else: numberToChinese(num))
    result.add d

proc judgeDate(data: seq[Cell]): array[5, bool] =
  ## [same day, same month, equal day diffs, equal month diffs, equal year diffs]
  result = [true, true, true, true, true]
  let v = proc(i: int): float64 = data[i].value.num
  let sameDay = toCivil(v(0))[2]
  let sameMonth = toCivil(v(0))[1]
  let dd = diffDays(v(1), v(0))
  let dm = diffMonths(v(1), v(0))
  let dy = diffYears(v(1), v(0))
  for i in 1 ..< data.len:
    if toCivil(v(i))[2] != sameDay: result[0] = false
    if toCivil(v(i))[1] != sameMonth: result[1] = false
    if diffDays(v(i), v(i - 1)) != dd: result[2] = false
    if diffMonths(v(i), v(i - 1)) != dm: result[3] = false
    if diffYears(v(i), v(i - 1)) != dy: result[4] = false
  if dd == 0: result[2] = false
  if dm == 0: result[3] = false
  if dy == 0: result[4] = false

proc unit(dir: FillDir): int = (if dir.backward: -1 else: 1)

proc stepFill(data: seq[Cell], len: int, dir: FillDir, months, years: int, workday: bool): seq[Cell] =
  ## The "compare with the first of the array" loops of types 5-7: each cycle
  ## moves the first cell by n months / years (or 7n days) and the others by
  ## the same number of days; on workdays a Sunday steps back 2, a Saturday 1.
  var step = 0
  for i in 1 .. len:
    let index = (i - 1) mod data.len
    var d = data[index]
    let num = int(ceil(i / data.len))
    let base = floor(d.value.num)
    if index == 0:
      step = if months != 0: diffDays(addMonths(base, months * num), base)
             elif years != 0: diffDays(addMonths(base, 12 * years * num), base)
             else: 7 * num * dir.unit
    var date = base + float64(step)
    if workday:
      let wd = weekday(date)
      if wd == 0: date -= 2
      elif wd == 6: date -= 1
    d.value = numVal(date)
    result.add d

proc byType(wb: Workbook, data0: seq[Cell], len: int, dir: FillDir, typ: FillType, kind: string, auto: bool): seq[Cell] =
  ## getDataByType
  var data = data0
  template rev() =
    if dir.backward: data.reverse()
  case typ
  of ftCopy:
    rev(); fillCopy(data, len)
  of ftSeries:
    case kind
    of "number": fillSeries(data, len, dir, auto)
    of "extendNumber":
      if data.len == 1: fillExtendNumber(wb, data, len, float64(dir.unit))
      else:
        var nums: seq[float64]
        for c in data: nums.add extendNumber(wb.mText(c))[1]
        if dir.backward: data.reverse(); nums.reverse()
        if isEqualDiff(nums): fillExtendNumber(wb, data, len, nums[1] - nums[0]) else: fillCopy(data, len)
    of "date":
      if data.len == 1: fillDays(data, len, dir.unit)
      else:
        rev()
        let j = judgeDate(data)
        if j[0] and j[3]: fillMonths(data, len, diffMonths(data[1].value.num, data[0].value.num))
        elif not j[0] and j[2]: fillDays(data, len, diffDays(data[1].value.num, data[0].value.num))
        else: fillCopy(data, len)
    of "chnNumber":
      let m0 = wb.mText(data[0])
      if data.len == 1:
        if m0 == "日" or chineseToNumber(m0) < 7: fillWeek(wb, data, len, dir.unit, Week1, "日")
        else: fillChnNumber(wb, data, len, dir.unit)
      else:
        var hasweek = false
        for c in data:
          if wb.mText(c) == "日": hasweek = true
        var nums: seq[float64]
        var weekIndex = 0
        for i, c in data:
          let m = wb.mText(c)
          if m == "日":
            if i == 0: nums.add 0
            else: inc weekIndex; nums.add float64(weekIndex * 7)
          elif hasweek and chineseToNumber(m) > 0 and chineseToNumber(m) < 7: nums.add float64(chineseToNumber(m) + weekIndex * 7)
          else: nums.add float64(chineseToNumber(m))
        if dir.backward: data.reverse(); nums.reverse()
        if isEqualDiff(nums):
          let step = int(nums[1] - nums[0])
          if hasweek or (nums[^1] < 6 and nums[0] > 0) or (nums[0] < 6 and nums[^1] > 0): fillWeek(wb, data, len, step, Week1, "日")
          else: fillChnNumber(wb, data, len, step)
        else: fillCopy(data, len)
    of "chnWeek2", "chnWeek3":
      let names = if kind == "chnWeek2": @Week2 else: @Week3
      if data.len == 1: fillWeek(wb, data, len, dir.unit, names, names[0])
      else:
        var nums: seq[float64]
        var weekIndex = 0
        for i, c in data:
          let m = wb.mText(c)
          if m == names[0]:
            if i == 0: nums.add 0
            else: inc weekIndex; nums.add float64(weekIndex * 7)
          else: nums.add float64(chineseToNumber(m.lastRune) + weekIndex * 7)
        if dir.backward: data.reverse(); nums.reverse()
        if isEqualDiff(nums): fillWeek(wb, data, len, int(nums[1] - nums[0]), names, names[0]) else: fillCopy(data, len)
    else:
      rev(); fillCopy(data, len)
  of ftOnlyFormat:
    rev(); fillOnlyFormat(data, len)
  of ftNoFormat:
    fillWithoutFormat(byType(wb, data, len, dir, ftSeries, kind, auto))
  of ftDay:
    if data.len == 1: fillDays(data, len, dir.unit)
    elif data.len == 2:
      rev(); fillDays(data, len, diffDays(data[1].value.num, data[0].value.num))
    else:
      rev()
      let j = judgeDate(data)
      if j[0] and j[3]: fillMonths(data, len, diffMonths(data[1].value.num, data[0].value.num))
      elif not j[0] and j[2]: fillDays(data, len, diffDays(data[1].value.num, data[0].value.num))
      else: fillCopy(data, len)
  of ftWorkDay:
    if data.len == 1:
      # the weekday is tested a step forward even when filling backward (as dropCell.js does)
      var res: seq[Cell]
      let newLen = int(round(float64(len) * 1.5))
      for i in 1 .. newLen:
        var d = data[0]
        let wd = weekday(floor(d.value.num) + float64(i))
        if wd == 0 or wd == 6: continue
        d.value = numVal(floor(d.value.num) + float64(dir.unit * i))
        res.add d
        if res.len == len: break
      res
    elif data.len == 2:
      let a = data[0].value.num
      let b = data[1].value.num
      if toCivil(b)[2] == toCivil(a)[2] and diffMonths(b, a) != 0:
        # monthly, moved back to Friday off a weekend (what dropCell.js meant;
        # it read the cell object and produced "Invalid Date")
        rev()
        let step = diffMonths(data[1].value.num, data[0].value.num)
        var res: seq[Cell]
        for i in 1 .. len:
          var d = data[(i - 1) mod data.len]
          var date = floor(addMonths(data[^1].value.num, step * i))
          let wd = weekday(date)
          if wd == 0: date -= 2
          elif wd == 6: date -= 1
          d.value = numVal(date)
          res.add d
        res
      else:
        rev(); stepFill(data, len, dir, dir.unit, 0, true)    # dates differ by more than 7 ms: always the month branch
    else:
      let j = judgeDate(data)
      if j[0] and j[3]:
        rev()
        let step = diffMonths(data[1].value.num, data[0].value.num)
        var res: seq[Cell]
        for i in 1 .. len:
          var d = data[(i - 1) mod data.len]
          var date = floor(addMonths(data[^1].value.num, step * i))
          let wd = weekday(date)
          if wd == 0: date -= 2
          elif wd == 6: date -= 1
          d.value = numVal(date)
          res.add d
        res
      elif not j[0] and j[2]:
        rev(); stepFill(data, len, dir, dir.unit, 0, true)
      else:
        rev(); fillCopy(data, len)
  of ftMonth:
    if data.len == 1: fillMonths(data, len, dir.unit)
    elif data.len == 2:
      let a = data[0].value.num
      let b = data[1].value.num
      if toCivil(b)[2] == toCivil(a)[2] and diffMonths(b, a) != 0:
        rev(); fillMonths(data, len, diffMonths(data[1].value.num, data[0].value.num))
      else:
        rev(); stepFill(data, len, dir, dir.unit, 0, false)
    else:
      let j = judgeDate(data)
      if j[0] and j[3]:
        rev(); fillMonths(data, len, diffMonths(data[1].value.num, data[0].value.num))
      elif not j[0] and j[2]:
        rev(); stepFill(data, len, dir, dir.unit, 0, false)
      else:
        rev(); fillCopy(data, len)
  of ftYear:
    if data.len == 1: fillYears(data, len, dir.unit)
    elif data.len == 2:
      let a = data[0].value.num
      let b = data[1].value.num
      if toCivil(b)[2] == toCivil(a)[2] and toCivil(b)[1] == toCivil(a)[1] and diffYears(b, a) != 0:
        rev(); fillYears(data, len, diffYears(data[1].value.num, data[0].value.num))
      else:
        rev(); stepFill(data, len, dir, 0, dir.unit, false)
    else:
      let j = judgeDate(data)
      if j[0] and j[1] and j[4]:
        rev(); fillYears(data, len, diffYears(data[1].value.num, data[0].value.num))
      elif (j[0] and j[3]) or j[2]:
        rev(); stepFill(data, len, dir, 0, dir.unit, false)
      else:
        rev(); fillCopy(data, len)
  of ftChnNumber:
    if data.len == 1: fillChnNumber(wb, data, len, dir.unit)
    else:
      var nums: seq[float64]
      for c in data: nums.add float64(chineseToNumber(wb.mText(c)))
      if dir.backward: data.reverse(); nums.reverse()
      if isEqualDiff(nums): fillChnNumber(wb, data, len, int(nums[1] - nums[0])) else: fillCopy(data, len)

proc kindType(typ: FillType, kind: string): FillType =
  ## getApplyData: which type each class is filled with.
  case kind
  of "number", "extendNumber", "chnWeek2", "chnWeek3":
    if typ in {ftSeries, ftNoFormat, ftOnlyFormat}: typ else: ftCopy
  of "date":
    if typ == ftChnNumber: ftCopy else: typ
  of "chnNumber":
    if typ in {ftSeries, ftNoFormat, ftOnlyFormat, ftChnNumber}: typ else: ftCopy
  else:
    if typ in {ftOnlyFormat, ftNoFormat}: typ else: ftCopy

proc fillLine(wb: Workbook, cells: seq[Cell], asLen: int, dir: FillDir, typ: FillType, auto: bool): seq[Cell] =
  ## getCopyData for one column (row) + getApplyData: runs of one class are
  ## filled together, then laid back at their positions, cycling.
  let csLen = cells.len
  var runs: OrderedTable[string, seq[Run]]
  var text = ""
  var cur: Run
  var before, after = ""
  var haveExt = false
  var sameStr = true
  for b, cell in cells:
    let str = wb.category(cell)
    if str == "extendNumber":
      let (_, _, bs, as1) = extendNumber(wb.mText(cell))
      if not haveExt:
        sameStr = true; before = bs; after = as1; haveExt = true
      elif bs != before or as1 != after:
        sameStr = false; before = bs; after = as1
      else: sameStr = true
    else:
      haveExt = false
    let joins = text == str and (str != "extendNumber" or sameStr)
    if b == 0:
      text = str; cur = Run(data: @[cell], index: @[1])
    elif joins:
      cur.data.add cell; cur.index.add b + 1
    else:
      runs.mgetOrPut(text, @[]).add cur
      text = str; cur = Run(data: @[cell], index: @[b + 1])
  runs.mgetOrPut(text, @[]).add cur
  let num = asLen div csLen
  let rsd = asLen mod csLen
  result = newSeq[Cell](asLen)
  for kind, list in runs:
    for run in list:
      var s = 0
      for ix in run.index:
        if ix <= rsd: inc s else: break
      let filled = byType(wb, run.data, run.index.len * num + s, dir, kindType(typ, kind), kind, auto)
      # getDataIndex: position -> the filled entry
      var sum = 0
      for i in 1 .. num:
        for ix in run.index:
          result[ix + (i - 1) * csLen - 1] = filled[sum]; inc sum
      for ix in run.index:
        if ix <= rsd:
          result[ix + csLen * num - 1] = filled[sum]; inc sum
        else: break

proc defaultFillType*(kinds: array[7, bool]): FillType =
  ## A drag fills a series when the source has anything a series applies to.
  for k in kinds:
    if k: return ftSeries
  ftCopy

proc dropFill*(wb: Workbook, s: Sheet, copy, apply: (int, int, int, int), dir: FillDir,
               typ: FillType, auto = false): seq[(int, int, Cell)] =
  ## update(): the cells of `apply` (r1, c1, r2, c2), from `copy`. `auto`: the
  ## type came from the drag, not the menu. Formulas move as in Excel: by the
  ## distance from the copy cell they repeat (the copy range tiles the fill).
  let (cr1, cc1, cr2, cc2) = copy
  let (ar1, ac1, ar2, ac2) = apply
  if dir in {fdDown, fdUp}:
    let asLen = ar2 - ar1 + 1
    let n = cr2 - cr1 + 1
    for c in ac1 .. ac2:
      var line: seq[Cell]
      for r in cr1 .. cr2: line.add s.cellAt(r, c)
      let data = fillLine(wb, line, asLen, dir, typ, auto)
      for k in 0 ..< asLen:
        let r = if dir == fdDown: ar1 + k else: ar2 - k
        var cell = data[k]
        if cell.formula.len > 0:
          let src = cr1 + floorMod(r - cr1, n)
          let f = s.cellAt(src, c).formula
          cell.setFormula(shiftFormula(if f.len > 0: f else: cell.formula, r - src, 0))
        result.add (r, c, cell)
  else:
    let asLen = ac2 - ac1 + 1
    let n = cc2 - cc1 + 1
    for r in ar1 .. ar2:
      var line: seq[Cell]
      for c in cc1 .. cc2: line.add s.cellAt(r, c)
      let data = fillLine(wb, line, asLen, dir, typ, auto)
      for k in 0 ..< asLen:
        let c = if dir == fdRight: ac1 + k else: ac2 - k
        var cell = data[k]
        if cell.formula.len > 0:
          let src = cc1 + floorMod(c - cc1, n)
          let f = s.cellAt(r, src).formula
          cell.setFormula(shiftFormula(if f.len > 0: f else: cell.formula, 0, c - src))
        result.add (r, c, cell)
