## Excel-style formulas: tokenizer, parser, evaluator and recalculation.
##
## Values flow as `Value`; a range evaluates to an array (vkArr), and the
## arithmetic, comparison and concatenation operators work element by element
## with broadcasting, so array formulas such as
##   =MATCH(1, INDEX((B2:B90>=5)*1, 0), 0)
## evaluate the way Excel 365 does. A formula cell keeps its last result in
## Cell.value; `recalc` recomputes every formula of the workbook, each cell
## once per pass, in dependency order (a cycle yields #CYCLE!).

import std/[tables, strutils, math, algorithm, sequtils]
import model

# ------------------------------------------------------------------ tokens --

type
  TokKind = enum tkNum, tkStr, tkBool, tkErr, tkRef, tkFunc, tkOp, tkLParen, tkRParen,
    tkComma, tkSemi, tkLBrace, tkRBrace, tkEnd
  Tok = object
    kind: TokKind
    text: string          ## operator, function name, string contents, error text
    num: float64
    start, stop: int      ## source span (for reference shifting)
    # tkRef: a cell, column range (A:A) or row range (1:1), with its sheet
    sheet: string
    r1, c1, r2, c2: int
    absR1, absC1, absR2, absC2: bool
    refShape: int         ## 0 cell, 1 range, 2 whole columns, 3 whole rows

const ErrorNames = ["#DIV/0!", "#N/A", "#NAME?", "#NULL!", "#NUM!", "#REF!", "#VALUE!", "#CYCLE!", "#SPILL!"]

proc colIndex(letters: string): int =
  result = 0
  for ch in letters: result = result * 26 + (ord(toUpperAscii(ch)) - ord('A') + 1)
  dec result

proc parseCellRef(s: string, i: var int, r, c: var int, absR, absC: var bool): bool =
  ## $?[A-Z]{1,3}$?[0-9]+ at s[i]; advances i on success.
  var j = i
  absC = j < s.len and s[j] == '$'
  if absC: inc j
  let ls = j
  while j < s.len and s[j] in Letters and j - ls < 3: inc j
  if j == ls: return false
  let letters = s[ls ..< j]
  absR = j < s.len and s[j] == '$'
  if absR: inc j
  let ds = j
  while j < s.len and s[j] in Digits: inc j
  if j == ds: return false
  if j < s.len and (s[j] in IdentChars or s[j] == '('): return false
  let row = parseInt(s[ds ..< j]) - 1
  let col = colIndex(letters)
  if row < 0 or row >= MaxRows or col < 0 or col >= MaxCols: return false
  r = row; c = col; i = j
  true

proc tokenize(src: string): seq[Tok] =
  var i = if src.len > 0 and src[0] == '=': 1 else: 0
  while i < src.len:
    let ch = src[i]
    if ch in Whitespace: inc i; continue
    let start = i
    var t = Tok(start: start)
    # Sheet prefix: 'quoted name'! or Name!
    var sheet = ""
    var hasSheet = false
    if ch == '\'':
      var j = i + 1
      var name = ""
      while j < src.len:
        if src[j] == '\'':
          if j + 1 < src.len and src[j + 1] == '\'': name.add '\''; j += 2; continue
          break
        name.add src[j]; inc j
      if j + 1 < src.len and src[j + 1] == '!':
        sheet = name; hasSheet = true; i = j + 2
    elif ch in IdentStartChars:
      var j = i
      while j < src.len and (src[j] in IdentChars or src[j] == '.'): inc j
      if j < src.len and src[j] == '!':
        sheet = src[i ..< j]; hasSheet = true; i = j + 1
    if i < src.len:
      # References: A1, A1:B2, A:A, 1:1
      var r1, c1, r2, c2: int
      var ar1, ac1, ar2, ac2: bool
      var j = i
      if parseCellRef(src, j, r1, c1, ar1, ac1):
        t.kind = tkRef; t.sheet = sheet
        t.r1 = r1; t.c1 = c1; t.r2 = r1; t.c2 = c1
        t.absR1 = ar1; t.absC1 = ac1; t.absR2 = ar1; t.absC2 = ac1
        var k = j
        if k < src.len and src[k] == ':':
          inc k
          if parseCellRef(src, k, r2, c2, ar2, ac2):
            t.r2 = r2; t.c2 = c2; t.absR2 = ar2; t.absC2 = ac2; t.refShape = 1; j = k
        t.stop = j; i = j
        result.add t; continue
      # Whole columns A:A / whole rows 1:1
      block whole:
        var k = i
        let a1 = k < src.len and src[k] == '$'
        if a1: inc k
        let s1 = k
        while k < src.len and src[k] in Letters: inc k
        if k > s1 and k < src.len and src[k] == ':':
          let left = src[s1 ..< k]
          inc k
          let a2 = k < src.len and src[k] == '$'
          if a2: inc k
          let s2 = k
          while k < src.len and src[k] in Letters: inc k
          if k > s2 and (k >= src.len or src[k] notin IdentChars):
            t.kind = tkRef; t.sheet = sheet; t.refShape = 2
            t.c1 = colIndex(left); t.c2 = colIndex(src[s2 ..< k]); t.r1 = 0; t.r2 = MaxRows - 1
            t.absC1 = a1; t.absC2 = a2
            t.stop = k; i = k; result.add t
            break whole
        k = i
        let b1 = k < src.len and src[k] == '$'
        if b1: inc k
        let d1 = k
        while k < src.len and src[k] in Digits: inc k
        if k > d1 and k < src.len and src[k] == ':':
          let top = src[d1 ..< k]
          inc k
          let b2 = k < src.len and src[k] == '$'
          if b2: inc k
          let d2 = k
          while k < src.len and src[k] in Digits: inc k
          if k > d2 and (k >= src.len or src[k] notin IdentChars):
            t.kind = tkRef; t.sheet = sheet; t.refShape = 3
            t.r1 = parseInt(top) - 1; t.r2 = parseInt(src[d2 ..< k]) - 1; t.c1 = 0; t.c2 = MaxCols - 1
            t.absR1 = b1; t.absR2 = b2
            t.stop = k; i = k; result.add t
            break whole
      if t.kind == tkRef: continue
    if hasSheet:
      result.add Tok(kind: tkErr, text: "#REF!", start: start, stop: i); continue
    let c0 = src[i]
    if c0 in Digits or (c0 == '.' and i + 1 < src.len and src[i + 1] in Digits):
      var j = i
      while j < src.len and src[j] in Digits: inc j
      if j < src.len and src[j] == '.':
        inc j
        while j < src.len and src[j] in Digits: inc j
      if j < src.len and src[j] in {'e', 'E'}:
        var k = j + 1
        if k < src.len and src[k] in {'+', '-'}: inc k
        if k < src.len and src[k] in Digits:
          while k < src.len and src[k] in Digits: inc k
          j = k
      result.add Tok(kind: tkNum, num: parseFloat(src[i ..< j]), start: start, stop: j)
      i = j
    elif c0 == '"':
      var j = i + 1
      var s = ""
      while j < src.len:
        if src[j] == '"':
          if j + 1 < src.len and src[j + 1] == '"': s.add '"'; j += 2; continue
          break
        s.add src[j]; inc j
      result.add Tok(kind: tkStr, text: s, start: start, stop: min(j + 1, src.len))
      i = j + 1
    elif c0 == '#':
      var matched = ""
      for e in ErrorNames:
        if src.len >= i + e.len and cmpIgnoreCase(src[i ..< i + e.len], e) == 0: matched = e; break
      if matched.len == 0: matched = "#NAME?"
      result.add Tok(kind: tkErr, text: matched, start: start, stop: i + max(matched.len, 1))
      i += max(matched.len, 1)
    elif c0 in IdentStartChars:
      var j = i
      while j < src.len and (src[j] in IdentChars or src[j] == '.'): inc j
      let word = src[i ..< j]
      var k = j
      while k < src.len and src[k] in Whitespace: inc k
      if k < src.len and src[k] == '(':
        result.add Tok(kind: tkFunc, text: toUpperAscii(word), start: start, stop: j)
      elif cmpIgnoreCase(word, "TRUE") == 0: result.add Tok(kind: tkBool, num: 1, start: start, stop: j)
      elif cmpIgnoreCase(word, "FALSE") == 0: result.add Tok(kind: tkBool, num: 0, start: start, stop: j)
      else: result.add Tok(kind: tkErr, text: "#NAME?", start: start, stop: j)
      i = j
    else:
      let two = if i + 1 < src.len: src[i .. i + 1] else: ""
      if two in ["<=", ">=", "<>"]:
        result.add Tok(kind: tkOp, text: two, start: start, stop: i + 2); i += 2
      else:
        let k = case c0
          of '(': tkLParen
          of ')': tkRParen
          of ',': tkComma
          of ';': tkSemi
          of '{': tkLBrace
          of '}': tkRBrace
          else: tkOp
        result.add Tok(kind: k, text: $c0, start: start, stop: i + 1)
        inc i
  result.add Tok(kind: tkEnd, start: src.len, stop: src.len)

# ------------------------------------------------------------------ parser --

type
  Parser = object
    toks: seq[Tok]
    pos: int
  ParseError* = object of ValueError

proc peek(p: Parser): Tok = p.toks[p.pos]
proc next(p: var Parser): Tok =
  result = p.toks[p.pos]
  if p.pos < p.toks.len - 1: inc p.pos
proc fail(msg: string) {.noreturn.} = raise newException(ParseError, msg)

proc prec(op: string): int =
  case op
  of "=", "<>", "<", ">", "<=", ">=": 1
  of "&": 2
  of "+", "-": 3
  of "*", "/": 4
  of "^": 5
  else: -1

proc parseExpr(p: var Parser, minPrec = 0): Expr
proc parsePrimary(p: var Parser): Expr

proc parsePrimary(p: var Parser): Expr =
  let t = p.next()
  case t.kind
  of tkNum: result = Expr(kind: ekNum, num: t.num)
  of tkStr: result = Expr(kind: ekStr, s: t.text)
  of tkBool: result = Expr(kind: ekBool, b: t.num != 0)
  of tkErr: result = Expr(kind: ekErr, s: t.text)
  of tkRef:
    if t.refShape == 0: result = Expr(kind: ekRef, sheet: t.sheet, r1: t.r1, c1: t.c1, r2: t.r1, c2: t.c1)
    else: result = Expr(kind: ekRange, sheet: t.sheet, r1: min(t.r1, t.r2), c1: min(t.c1, t.c2),
                                       r2: max(t.r1, t.r2), c2: max(t.c1, t.c2))
  of tkFunc:
    result = Expr(kind: ekCall, name: t.text)
    if p.next().kind != tkLParen: fail("expected (")
    if p.peek().kind == tkRParen: discard p.next(); return
    while true:
      if p.peek().kind in {tkComma, tkRParen}: result.args.add Expr(kind: ekStr, s: "") # omitted argument
      else: result.args.add p.parseExpr()
      let sep = p.next()
      if sep.kind == tkRParen: break
      if sep.kind notin {tkComma, tkSemi}: fail("expected , or )")
  of tkLParen:
    result = p.parseExpr()
    if p.next().kind != tkRParen: fail("expected )")
  of tkLBrace:
    var rows: seq[seq[Expr]] = @[@[]]
    while true:
      rows[^1].add p.parsePrimary()
      let sep = p.next()
      if sep.kind == tkRBrace: break
      if sep.kind == tkSemi: rows.add @[]
      elif sep.kind != tkComma: fail("expected , ; or }")
    result = Expr(kind: ekArray, arows: rows.len, acols: rows[0].len)
    for r in rows:
      if r.len != result.acols: fail("ragged array")
      for e in r: result.aitems.add e
  of tkOp:
    if t.text in ["-", "+"]:
      # Excel: unary minus binds tighter than ^ (-2^2 = 4).
      result = Expr(kind: ekUnary, op: t.text[0], arg: p.parsePrimary())
    else: fail("unexpected " & t.text)
  else: fail("unexpected token")

proc parseExpr(p: var Parser, minPrec = 0): Expr =
  result = p.parsePrimary()
  while true:
    let t = p.peek()
    if t.kind == tkOp and t.text == "%":
      discard p.next()
      result = Expr(kind: ekPercent, op: '%', arg: result)
      continue
    if t.kind != tkOp: break
    let pr = prec(t.text)
    if pr < 0 or pr < minPrec: break
    discard p.next()
    let rhs = p.parseExpr(pr + 1)        # all binary operators are left-associative in Excel
    result = Expr(kind: ekBinary, bop: t.text, left: result, right: rhs)

proc parseFormula*(src: string): Expr =
  ## Parses "=..." (or the text after '='); raises ParseError.
  var p = Parser(toks: tokenize(src))
  if p.toks.len == 1: fail("empty formula")
  result = p.parseExpr()
  if p.peek().kind != tkEnd: fail("unexpected " & p.peek().text)

# --------------------------------------------------------- reference shift --

proc formatRef(t: Tok, dr, dc: int, ok: var bool): string =
  proc cellPart(r, c: int, absR, absC: bool, dr, dc: int, ok: var bool): string =
    let rr = if absR: r else: r + dr
    let cc = if absC: c else: c + dc
    if rr < 0 or cc < 0 or rr >= MaxRows or cc >= MaxCols: ok = false; return "#REF!"
    (if absC: "$" else: "") & colName(cc) & (if absR: "$" else: "") & $(rr + 1)
  result = ""
  case t.refShape
  of 0: result = cellPart(t.r1, t.c1, t.absR1, t.absC1, dr, dc, ok)
  of 1: result = cellPart(t.r1, t.c1, t.absR1, t.absC1, dr, dc, ok) & ":" & cellPart(t.r2, t.c2, t.absR2, t.absC2, dr, dc, ok)
  of 2:
    let a = if t.absC1: t.c1 else: t.c1 + dc
    let b = if t.absC2: t.c2 else: t.c2 + dc
    if a < 0 or b < 0 or a >= MaxCols or b >= MaxCols: ok = false; return "#REF!"
    result = (if t.absC1: "$" else: "") & colName(a) & ":" & (if t.absC2: "$" else: "") & colName(b)
  else:
    let a = if t.absR1: t.r1 else: t.r1 + dr
    let b = if t.absR2: t.r2 else: t.r2 + dr
    if a < 0 or b < 0 or a >= MaxRows or b >= MaxRows: ok = false; return "#REF!"
    result = (if t.absR1: "$" else: "") & $(a + 1) & ":" & (if t.absR2: "$" else: "") & $(b + 1)

proc shiftFormula*(src: string, dr, dc: int): string =
  ## The formula as if copied dr rows down and dc columns right: relative
  ## references move, $absolute ones stay; text outside references is kept.
  if dr == 0 and dc == 0: return src
  var toks: seq[Tok]
  try: toks = tokenize(src) except CatchableError: return src
  result = ""
  var last = 0
  for t in toks:
    if t.kind != tkRef: continue
    # keep any sheet prefix: it sits between t.start and the cell text
    var refStart = t.start
    if t.sheet.len > 0:
      let bang = src.find('!', t.start)
      if bang >= 0 and bang < t.stop: refStart = bang + 1
    result.add src[last ..< refStart]
    var ok = true
    result.add formatRef(t, dr, dc, ok)
    last = t.stop
  result.add src[last .. ^1]

# --------------------------------------------------------------- evaluator --

type
  Ctx = object
    wb: Workbook
    sheet: Sheet

proc evalCell*(wb: Workbook, s: Sheet, r, c: int): Value

proc isErr(v: Value): bool {.inline.} = v.kind == vkErr

proc toNum(v: Value, ok: var bool): float64 =
  case v.kind
  of vkNum: v.num
  of vkBool: (if v.b: 1.0 else: 0.0)
  of vkEmpty: 0.0
  of vkStr:
    let t = v.str.strip
    if t.len == 0: ok = false; return 0
    try:
      if t.endsWith("%"): parseFloat(t[0 ..< ^1].strip) / 100
      else: parseFloat(t)
    except ValueError:
      ok = false; 0.0
  of vkArr:
    if v.items.len > 0: toNum(v.items[0], ok) else: 0.0
  of vkErr: ok = false; 0.0

proc toText*(v: Value): string

proc fmtGeneral*(x: float64): string =
  ## Excel's General format: integers in full, otherwise up to ~10
  ## significant digits, scientific for very large or small magnitudes.
  if x.isNaN: return "#NUM!"
  if x.classify in {fcInf, fcNegInf}: return "#NUM!"
  if x == 0: return "0"
  let ax = abs(x)
  if x == trunc(x) and ax < 1e15: return $int64(x)
  if ax >= 1e11 or ax < 1e-9:
    var s = formatFloat(x, ffScientific, 5)            # 1.23457e+11
    let e = s.find('e')
    var mant = s[0 ..< e]
    if '.' in mant: mant = mant.strip(leading = false, chars = {'0'}).strip(leading = false, chars = {'.'})
    var expo = s[e + 1 .. ^1]
    let sign = if expo[0] == '-': "-" else: "+"
    expo = expo.strip(chars = {'+', '-'}).strip(trailing = false, chars = {'0'})
    if expo.len < 2: expo = repeat('0', 2 - expo.len) & expo
    return mant & "E" & sign & expo
  let digits = max(0, 9 - int(floor(log10(ax))))
  result = formatFloat(x, ffDecimal, digits)
  if '.' in result: result = result.strip(leading = false, chars = {'0'}).strip(leading = false, chars = {'.'})
  if result == "-0": result = "0"

proc fmtSignificant*(x: float64, sig: int, scientific: bool): string =
  ## x with at most `sig` significant digits, in decimal or scientific form,
  ## trailing zeros removed — the candidates General tries in a narrow column.
  if x == 0: return "0"
  if scientific:
    var s = formatFloat(x, ffScientific, max(0, sig - 1))
    let e = s.find('e')
    var mant = s[0 ..< e]
    if '.' in mant: mant = mant.strip(leading = false, chars = {'0'}).strip(leading = false, chars = {'.'})
    var expo = s[e + 1 .. ^1]
    let sign = if expo[0] == '-': "-" else: "+"
    expo = expo.strip(chars = {'+', '-'}).strip(trailing = false, chars = {'0'})
    if expo.len < 2: expo = repeat('0', 2 - expo.len) & expo
    return mant & "E" & sign & expo
  let digits = max(0, sig - 1 - int(floor(log10(abs(x)))))
  result = formatFloat(x, ffDecimal, digits)
  if '.' in result: result = result.strip(leading = false, chars = {'0'}).strip(leading = false, chars = {'.'})
  if result == "-0": result = "0"

proc toText*(v: Value): string =
  case v.kind
  of vkEmpty: ""
  of vkNum: fmtGeneral(v.num)
  of vkStr, vkErr: v.str
  of vkBool: (if v.b: "TRUE" else: "FALSE")
  of vkArr: (if v.items.len > 0: toText(v.items[0]) else: "")

proc toBool(v: Value, ok: var bool): bool =
  case v.kind
  of vkBool: v.b
  of vkNum: v.num != 0
  of vkEmpty: false
  of vkStr:
    if cmpIgnoreCase(v.str, "TRUE") == 0: true
    elif cmpIgnoreCase(v.str, "FALSE") == 0: false
    else: ok = false; false
  of vkArr: (if v.items.len > 0: toBool(v.items[0], ok) else: false)
  of vkErr: ok = false; false

proc firstErr(vals: openArray[Value]): Value =
  for v in vals:
    if v.kind == vkErr: return v
    if v.kind == vkArr:
      for x in v.items:
        if x.kind == vkErr: return x
  emptyVal()

proc rangeVal(ctx: Ctx, sheetName: string, r1, c1, r2, c2: int): Value =
  let s = if sheetName.len == 0: ctx.sheet else: ctx.wb.sheetNamed(sheetName)
  if s == nil: return errVal("#REF!")
  # Whole columns/rows stop at the used range.
  let rr2 = min(r2, max(s.maxRow - 1, r1))
  let cc2 = min(c2, max(s.maxCol - 1, c1))
  result = Value(kind: vkArr, rows: rr2 - r1 + 1, cols: cc2 - c1 + 1)
  result.items = newSeq[Value](result.rows * result.cols)
  var i = 0
  for r in r1 .. rr2:
    for c in c1 .. cc2:
      result.items[i] = evalCell(ctx.wb, s, r, c)
      inc i

proc eval(ctx: Ctx, e: Expr): Value

proc flatten(v: Value, into: var seq[Value]) =
  if v.kind == vkArr:
    for x in v.items: into.add x
  else: into.add v

proc pick(v: Value, vr, vc, r, c: int): Value =
  ## Element (r, c) of v broadcast to a larger array.
  if v.kind != vkArr: return v
  let rr = if vr == 1: 0 else: r
  let cc = if vc == 1: 0 else: c
  if rr >= vr or cc >= vc: return errVal("#N/A")
  v.items[rr * vc + cc]

proc elementwise(a, b: Value, f: proc(x, y: Value): Value): Value =
  if a.kind != vkArr and b.kind != vkArr: return f(a, b)
  let ar = if a.kind == vkArr: a.rows else: 1
  let ac = if a.kind == vkArr: a.cols else: 1
  let br = if b.kind == vkArr: b.rows else: 1
  let bc = if b.kind == vkArr: b.cols else: 1
  let rows = max(ar, br)
  let cols = max(ac, bc)
  result = Value(kind: vkArr, rows: rows, cols: cols, items: newSeq[Value](rows * cols))
  for r in 0 ..< rows:
    for c in 0 ..< cols:
      result.items[r * cols + c] = f(pick(a, ar, ac, r, c), pick(b, br, bc, r, c))

proc compareVals(x, y: Value): int =
  ## Excel ordering: numbers < text < booleans; text case-insensitive.
  proc rank(v: Value): int =
    case v.kind
    of vkNum, vkEmpty: 0
    of vkStr: 1
    of vkBool: 2
    else: 3
  var a = x
  var b = y
  if a.kind == vkEmpty: a = (if b.kind == vkStr: strVal("") elif b.kind == vkBool: boolVal(false) else: numVal(0))
  if b.kind == vkEmpty: b = (if a.kind == vkStr: strVal("") elif a.kind == vkBool: boolVal(false) else: numVal(0))
  if rank(a) != rank(b): return cmp(rank(a), rank(b))
  case a.kind
  of vkNum: cmp(a.num, b.num)
  of vkStr: cmp(toLowerAscii(a.str), toLowerAscii(b.str))
  of vkBool: cmp(ord(a.b), ord(b.b))
  else: 0

proc binop(op: string, x, y: Value): Value =
  if x.kind == vkErr: return x
  if y.kind == vkErr: return y
  case op
  of "&": return strVal(toText(x) & toText(y))
  of "=": return boolVal(compareVals(x, y) == 0)
  of "<>": return boolVal(compareVals(x, y) != 0)
  of "<": return boolVal(compareVals(x, y) < 0)
  of ">": return boolVal(compareVals(x, y) > 0)
  of "<=": return boolVal(compareVals(x, y) <= 0)
  of ">=": return boolVal(compareVals(x, y) >= 0)
  else: discard
  var ok = true
  let a = toNum(x, ok)
  let b = toNum(y, ok)
  if not ok: return errVal("#VALUE!")
  case op
  of "+": numVal(a + b)
  of "-": numVal(a - b)
  of "*": numVal(a * b)
  of "/": (if b == 0: errVal("#DIV/0!") else: numVal(a / b))
  of "^":
    let r = pow(a, b)
    if r.isNaN or r.classify in {fcInf, fcNegInf}: errVal("#NUM!") else: numVal(r)
  else: errVal("#VALUE!")

# ----------------------------------------------------------------- functions

proc numbersOf(vals: seq[Value], fromRange: seq[bool], strict: var Value): seq[float64] =
  ## Numbers for SUM/AVERAGE/...: from ranges only real numbers count; direct
  ## arguments are coerced (text that is not a number -> #VALUE!).
  for i, v in vals:
    if v.kind == vkArr or fromRange[i]:
      var items: seq[Value]
      flatten(v, items)
      for x in items:
        if x.kind == vkNum: result.add x.num
        elif x.kind == vkErr and strict.kind == vkEmpty: strict = x
    else:
      case v.kind
      of vkNum: result.add v.num
      of vkBool: result.add(if v.b: 1.0 else: 0.0)
      of vkEmpty: discard
      of vkErr: (if strict.kind == vkEmpty: strict = v)
      of vkStr:
        var ok = true
        let n = toNum(v, ok)
        if ok: result.add n elif strict.kind == vkEmpty: strict = errVal("#VALUE!")
      of vkArr: discard

proc criteriaMatch(v: Value, crit: Value): bool =
  ## COUNTIF/SUMIF criteria: ">=5", "<>x", "=a", "abc*", or a plain value.
  if crit.kind != vkStr: return compareVals(v, crit) == 0
  var c = crit.str
  var op = "="
  for o in [">=", "<=", "<>", ">", "<", "="]:
    if c.startsWith(o): op = o; c = c[o.len .. ^1]; break
  var target: Value
  var ok = true
  let n = toNum(strVal(c), ok)
  target = if ok and c.strip.len > 0: numVal(n) else: strVal(c)
  if target.kind == vkStr and op in ["=", "<>"] and ('*' in c or '?' in c):
    # wildcard match, case-insensitive
    proc wild(p, s: string): bool =
      if p.len == 0: return s.len == 0
      if p[0] == '*': return wild(p[1 .. ^1], s) or (s.len > 0 and wild(p, s[1 .. ^1]))
      if s.len > 0 and (p[0] == '?' or toLowerAscii(p[0]) == toLowerAscii(s[0])): return wild(p[1 .. ^1], s[1 .. ^1])
      false
    let m = v.kind == vkStr and wild(c, v.str)
    return if op == "=": m else: not m
  if target.kind == vkNum and v.kind notin {vkNum}:
    return op == "<>"
  let r = compareVals(v, target)
  case op
  of "=": r == 0
  of "<>": r != 0
  of ">": r > 0
  of "<": r < 0
  of ">=": r >= 0
  else: r <= 0

proc callFn(ctx: Ctx, name: string, args: seq[Expr]): Value
proc formatNumber*(x: float64, fmt: string): string
proc runeLenCompat(s: string): int

proc eval(ctx: Ctx, e: Expr): Value =
  if e == nil: return errVal("#VALUE!")
  case e.kind
  of ekNum: numVal(e.num)
  of ekStr: strVal(e.s)
  of ekBool: boolVal(e.b)
  of ekErr: errVal(e.s)
  of ekRef:
    let s = if e.sheet.len == 0: ctx.sheet else: ctx.wb.sheetNamed(e.sheet)
    if s == nil: errVal("#REF!") else: evalCell(ctx.wb, s, e.r1, e.c1)
  of ekRange: rangeVal(ctx, e.sheet, e.r1, e.c1, e.r2, e.c2)
  of ekArray:
    var v = Value(kind: vkArr, rows: e.arows, cols: e.acols)
    for x in e.aitems: v.items.add eval(ctx, x)
    v
  of ekUnary:
    let a = eval(ctx, e.arg)
    elementwise(a, numVal(0), proc(x, y: Value): Value =
      if x.kind == vkErr: return x
      var ok = true
      let n = toNum(x, ok)
      if not ok: return errVal("#VALUE!")
      numVal(if e.op == '-': -n else: n))
  of ekPercent:
    elementwise(eval(ctx, e.arg), numVal(100), proc(x, y: Value): Value = binop("/", x, y))
  of ekBinary:
    let op = e.bop
    elementwise(eval(ctx, e.left), eval(ctx, e.right), proc(x, y: Value): Value = binop(op, x, y))
  of ekCall: callFn(ctx, e.name, e.args)

proc scalar(v: Value): Value =
  if v.kind == vkArr: (if v.items.len > 0: v.items[0] else: emptyVal()) else: v

proc callFn(ctx: Ctx, name: string, args: seq[Expr]): Value =
  template arg(i: int): Value = eval(ctx, args[i])
  template need(n: int) =
    if args.len < n: return errVal("#N/A")
  proc evalAll(): (seq[Value], seq[bool]) =
    for a in args:
      result[0].add eval(ctx, a)
      result[1].add(a.kind == ekRange)
  proc num1(v: Value, res: var Value): float64 =
    let s = scalar(v)
    if s.kind == vkErr: res = s; return 0
    var ok = true
    result = toNum(s, ok)
    if not ok: res = errVal("#VALUE!")
  template numArg(i: int): float64 =
    var bad = emptyVal()
    let x = num1(arg(i), bad)
    if bad.kind != vkEmpty: return bad
    x
  case name
  of "SUM", "AVERAGE", "MIN", "MAX", "COUNT", "MEDIAN", "PRODUCT", "STDEV", "STDEV.S", "STDEVP", "STDEV.P",
     "VAR", "VAR.S", "VARP", "VAR.P", "SUMSQ":
    let (vals, rng) = evalAll()
    if name == "COUNT":
      var n = 0
      for i, v in vals:
        var items: seq[Value]
        flatten(v, items)
        for x in items:
          if x.kind == vkNum: inc n
          elif not rng[i] and v.kind != vkArr and x.kind == vkStr:
            var ok = true
            discard toNum(x, ok)
            if ok: inc n
      return numVal(float64(n))
    var bad = emptyVal()
    let xs = numbersOf(vals, rng, bad)
    if bad.kind != vkEmpty: return bad
    case name
    of "SUM": return numVal(sum(xs))
    of "SUMSQ":
      var t = 0.0
      for x in xs: t += x * x
      return numVal(t)
    of "PRODUCT":
      var p = 1.0
      for x in xs: p *= x
      return numVal(if xs.len == 0: 0.0 else: p)
    of "AVERAGE": return (if xs.len == 0: errVal("#DIV/0!") else: numVal(sum(xs) / float64(xs.len)))
    of "MIN": return numVal(if xs.len == 0: 0.0 else: min(xs))
    of "MAX": return numVal(if xs.len == 0: 0.0 else: max(xs))
    of "MEDIAN":
      if xs.len == 0: return errVal("#NUM!")
      var s = xs
      s.sort()
      let h = s.len div 2
      return numVal(if s.len mod 2 == 1: s[h] else: (s[h - 1] + s[h]) / 2)
    else:
      let sample = name in ["STDEV", "STDEV.S", "VAR", "VAR.S"]
      let n = xs.len
      if n == 0 or (sample and n < 2): return errVal("#DIV/0!")
      let mean = sum(xs) / float64(n)
      var ss = 0.0
      for x in xs: ss += (x - mean) * (x - mean)
      let variance = ss / float64(if sample: n - 1 else: n)
      return numVal(if name.startsWith("VAR"): variance else: sqrt(variance))
  of "COUNTA", "COUNTBLANK":
    var filled, blank = 0
    for a in args:
      var items: seq[Value]
      flatten(eval(ctx, a), items)
      for x in items:
        if x.kind == vkEmpty or (x.kind == vkStr and x.str.len == 0): inc blank else: inc filled
    return numVal(float64(if name == "COUNTA": filled else: blank))
  of "IF":
    need(1)
    let c = arg(0)
    if c.kind == vkArr:
      let t = if args.len > 1: arg(1) else: boolVal(true)
      let f = if args.len > 2: arg(2) else: boolVal(false)
      var res = Value(kind: vkArr, rows: c.rows, cols: c.cols)
      for i, x in c.items:
        if x.kind == vkErr: res.items.add x; continue
        var ok = true
        let b = toBool(x, ok)
        let src = if b: t else: f
        res.items.add(if not ok: errVal("#VALUE!")
                      elif src.kind != vkArr: src
                      elif i < src.items.len: src.items[i]
                      else: errVal("#N/A"))
      return res
    if c.kind == vkErr: return c
    var ok = true
    let b = toBool(c, ok)
    if not ok: return errVal("#VALUE!")
    if b: return (if args.len > 1: arg(1) else: boolVal(true))
    return (if args.len > 2: arg(2) else: boolVal(false))
  of "IFERROR":
    need(2)
    let v = arg(0)
    if scalar(v).kind == vkErr: return arg(1)
    return v
  of "IFNA":
    need(2)
    let v = arg(0)
    if scalar(v).kind == vkErr and scalar(v).str == "#N/A": return arg(1)
    return v
  of "AND", "OR", "XOR":
    var res = name == "AND"
    var seen = false
    var cnt = 0
    for a in args:
      var items: seq[Value]
      flatten(eval(ctx, a), items)
      for x in items:
        if x.kind == vkErr: return x
        if x.kind in {vkEmpty, vkStr}: continue
        var ok = true
        let b = toBool(x, ok)
        seen = true
        if b: inc cnt
        if name == "AND": res = res and b
        elif name == "OR": res = res or b
    if not seen: return errVal("#VALUE!")
    return boolVal(if name == "XOR": cnt mod 2 == 1 else: res)
  of "NOT":
    need(1)
    var ok = true
    let v = scalar(arg(0))
    if v.kind == vkErr: return v
    let b = toBool(v, ok)
    return (if ok: boolVal(not b) else: errVal("#VALUE!"))
  of "TRUE": return boolVal(true)
  of "FALSE": return boolVal(false)
  of "ABS", "SQRT", "EXP", "LN", "LOG10", "INT", "SIGN", "SIN", "COS", "TAN", "ASIN", "ACOS", "ATAN", "EVEN", "ODD", "FACT", "DEGREES", "RADIANS":
    need(1)
    let x = numArg(0)
    let r = case name
      of "ABS": abs(x)
      of "SQRT": (if x < 0: NaN else: sqrt(x))
      of "EXP": exp(x)
      of "LN": (if x <= 0: NaN else: ln(x))
      of "LOG10": (if x <= 0: NaN else: log10(x))
      of "INT": floor(x)
      of "SIGN": float64(sgn(x))
      of "SIN": sin(x)
      of "COS": cos(x)
      of "TAN": tan(x)
      of "ASIN": arcsin(x)
      of "ACOS": arccos(x)
      of "ATAN": arctan(x)
      of "DEGREES": radToDeg(x)
      of "RADIANS": degToRad(x)
      of "FACT":
        if x < 0: NaN
        else:
          var f = 1.0
          for i in 2 .. int(x): f *= float64(i)
          f
      of "EVEN":
        let a = ceil(abs(x) / 2) * 2
        if x < 0: -a else: a
      else:
        var a = ceil(abs(x))
        if int(a) mod 2 == 0: a += 1
        if x < 0: -a else: a
    return (if r.isNaN or r.classify in {fcInf, fcNegInf}: errVal("#NUM!") else: numVal(r))
  of "LOG":
    need(1)
    let x = numArg(0)
    let b = if args.len > 1: numArg(1) else: 10.0
    if x <= 0 or b <= 0 or b == 1: return errVal("#NUM!")
    return numVal(ln(x) / ln(b))
  of "POWER":
    need(2)
    return binop("^", numVal(numArg(0)), numVal(numArg(1)))
  of "MOD":
    need(2)
    let a = numArg(0)
    let b = numArg(1)
    if b == 0: return errVal("#DIV/0!")
    return numVal(a - b * floor(a / b))
  of "ROUND", "ROUNDUP", "ROUNDDOWN", "TRUNC":
    need(1)
    let x = numArg(0)
    let d = if args.len > 1: int(numArg(1)) else: 0
    let f = pow(10.0, float64(d))
    let y = x * f
    let r = case name
      of "ROUND": (if y >= 0: floor(y + 0.5 + 1e-9) else: -floor(-y + 0.5 + 1e-9))
      of "ROUNDUP": (if y >= 0: ceil(y - 1e-9) else: -ceil(-y - 1e-9))
      else: (if y >= 0: floor(y + 1e-9) else: -floor(-y + 1e-9))
    return numVal(r / f)
  of "CEILING", "FLOOR", "MROUND":
    need(1)
    let x = numArg(0)
    let s = if args.len > 1: numArg(1) else: 1.0
    if s == 0: return numVal(0)
    return numVal(case name
      of "CEILING": ceil(x / s) * s
      of "FLOOR": floor(x / s) * s
      else: round(x / s) * s)
  of "PI": return numVal(PI)
  of "RAND": return numVal(0.5)
  of "SUMPRODUCT":
    need(1)
    var acc: Value = arg(0)
    for i in 1 ..< args.len:
      acc = elementwise(acc, arg(i), proc(x, y: Value): Value =
        var ok = true
        let a = (if x.kind == vkNum: x.num elif x.kind == vkBool: (if x.b: 1.0 else: 0.0) else: 0.0)
        let b = (if y.kind == vkNum: y.num elif y.kind == vkBool: (if y.b: 1.0 else: 0.0) else: 0.0)
        discard ok
        numVal(a * b))
    var items: seq[Value]
    flatten(acc, items)
    var t = 0.0
    for x in items:
      if x.kind == vkErr: return x
      if x.kind == vkNum: t += x.num
    return numVal(t)
  of "SUMIF", "AVERAGEIF", "COUNTIF":
    need(2)
    let rng = arg(0)
    let crit = scalar(arg(1))
    let sumRng = if args.len > 2: arg(2) else: rng
    var items, sums: seq[Value]
    flatten(rng, items)
    flatten(sumRng, sums)
    var t = 0.0
    var n = 0
    for i, x in items:
      if criteriaMatch(x, crit):
        inc n
        if i < sums.len and sums[i].kind == vkNum: t += sums[i].num
    case name
    of "COUNTIF": return numVal(float64(n))
    of "SUMIF": return numVal(t)
    else: return (if n == 0: errVal("#DIV/0!") else: numVal(t / float64(n)))
  of "INDEX":
    need(2)
    let a = arg(0)
    if a.kind == vkErr: return a
    let arr = if a.kind == vkArr: a else: Value(kind: vkArr, rows: 1, cols: 1, items: @[a])
    let r = int(numArg(1))
    let c = if args.len > 2: int(numArg(2)) else: (if arr.rows == 1 and r != 0: -1 else: 1)
    if r == 0 and (args.len <= 2 or c == 0):
      return arr                                  # INDEX(array, 0): the whole array
    if r == 0:
      if c < 1 or c > arr.cols: return errVal("#REF!")
      var col = Value(kind: vkArr, rows: arr.rows, cols: 1)
      for i in 0 ..< arr.rows: col.items.add arr.items[i * arr.cols + c - 1]
      return col
    if c == -1:                                    # one row: INDEX(row, n)
      if r < 1 or r > arr.cols: return errVal("#REF!")
      return arr.items[r - 1]
    if c == 0:
      if r < 1 or r > arr.rows: return errVal("#REF!")
      var row = Value(kind: vkArr, rows: 1, cols: arr.cols)
      for j in 0 ..< arr.cols: row.items.add arr.items[(r - 1) * arr.cols + j]
      return row
    if r < 1 or r > arr.rows or c < 1 or c > arr.cols: return errVal("#REF!")
    return arr.items[(r - 1) * arr.cols + c - 1]
  of "MATCH":
    need(2)
    let look = scalar(arg(0))
    if look.kind == vkErr: return look
    var items: seq[Value]
    flatten(arg(1), items)
    let mode = if args.len > 2: int(numArg(2)) else: 1
    if mode == 0:
      for i, x in items:
        if x.kind == vkErr: continue
        if look.kind == vkStr and x.kind == vkStr and ('*' in look.str or '?' in look.str):
          if criteriaMatch(x, strVal("=" & look.str)): return numVal(float64(i + 1))
        elif x.kind != vkEmpty and compareVals(x, look) == 0: return numVal(float64(i + 1))
      return errVal("#N/A")
    var best = -1
    for i, x in items:
      if x.kind in {vkEmpty, vkErr}: continue
      let c = compareVals(x, look)
      if mode > 0:
        if c <= 0: best = i else: break
      else:
        if c >= 0: best = i else: break
    return (if best < 0: errVal("#N/A") else: numVal(float64(best + 1)))
  of "VLOOKUP", "HLOOKUP":
    need(3)
    let look = scalar(arg(0))
    let t = arg(1)
    if t.kind != vkArr: return errVal("#N/A")
    let idx = int(numArg(2))
    var okApprox = true
    let approx = if args.len > 3: toBool(scalar(arg(3)), okApprox) else: true
    let vertical = name == "VLOOKUP"
    let n = if vertical: t.rows else: t.cols
    if idx < 1 or idx > (if vertical: t.cols else: t.rows): return errVal("#REF!")
    proc at(i, j: int): Value = (if vertical: t.items[i * t.cols + j] else: t.items[j * t.cols + i])
    var hit = -1
    for i in 0 ..< n:
      let c = compareVals(at(i, 0), look)
      if not approx:
        if at(i, 0).kind != vkEmpty and c == 0: hit = i; break
      else:
        if c <= 0: hit = i else: break
    return (if hit < 0: errVal("#N/A") else: at(hit, idx - 1))
  of "ROW", "COLUMN", "ROWS", "COLUMNS":
    if args.len == 0: return errVal("#VALUE!")
    let a = args[0]
    if a.kind notin {ekRef, ekRange}:
      if name in ["ROWS", "COLUMNS"]:
        let v = eval(ctx, a)
        if v.kind == vkArr: return numVal(float64(if name == "ROWS": v.rows else: v.cols))
        return numVal(1)
      return errVal("#VALUE!")
    case name
    of "ROW": return numVal(float64(a.r1 + 1))
    of "COLUMN": return numVal(float64(a.c1 + 1))
    of "ROWS": return numVal(float64(a.r2 - a.r1 + 1))
    else: return numVal(float64(a.c2 - a.c1 + 1))
  of "CONCATENATE", "CONCAT", "TEXTJOIN":
    var s = ""
    var start = 0
    var sep = ""
    var skipEmpty = false
    if name == "TEXTJOIN":
      need(2)
      sep = toText(scalar(arg(0)))
      var ok = true
      skipEmpty = toBool(scalar(arg(1)), ok)
      start = 2
    var first = true
    for i in start ..< args.len:
      var items: seq[Value]
      flatten(eval(ctx, args[i]), items)
      for x in items:
        if x.kind == vkErr: return x
        let t = toText(x)
        if skipEmpty and t.len == 0: continue
        if not first: s.add sep
        s.add t
        first = false
    return strVal(s)
  of "LEN":
    need(1)
    return numVal(float64(toText(scalar(arg(0))).runeLenCompat))
  of "LEFT", "RIGHT":
    need(1)
    let t = toText(scalar(arg(0)))
    let n = if args.len > 1: int(numArg(1)) else: 1
    if n < 0: return errVal("#VALUE!")
    return strVal(if name == "LEFT": t[0 ..< min(n, t.len)] else: t[max(0, t.len - n) .. ^1])
  of "MID":
    need(3)
    let t = toText(scalar(arg(0)))
    let s = int(numArg(1))
    let n = int(numArg(2))
    if s < 1 or n < 0: return errVal("#VALUE!")
    if s > t.len: return strVal("")
    return strVal(t[s - 1 ..< min(t.len, s - 1 + n)])
  of "UPPER": need(1); return strVal(toUpperAscii(toText(scalar(arg(0)))))
  of "LOWER": need(1); return strVal(toLowerAscii(toText(scalar(arg(0)))))
  of "TRIM":
    need(1)
    var joined = ""
    for w in toText(scalar(arg(0))).splitWhitespace:
      if joined.len > 0: joined.add ' '
      joined.add w
    return strVal(joined)
  of "VALUE":
    need(1)
    var ok = true
    let n = toNum(scalar(arg(0)), ok)
    return (if ok: numVal(n) else: errVal("#VALUE!"))
  of "TEXT":
    need(2)
    let v = scalar(arg(0))
    var ok = true
    let n = toNum(v, ok)
    if not ok: return strVal(toText(v))
    return strVal(formatNumber(n, toText(scalar(arg(1)))))
  of "FIND", "SEARCH":
    need(2)
    let what = toText(scalar(arg(0)))
    let within = toText(scalar(arg(1)))
    let start = if args.len > 2: int(numArg(2)) - 1 else: 0
    let i = if name == "FIND": within.find(what, start) else: toLowerAscii(within).find(toLowerAscii(what), start)
    return (if i < 0: errVal("#VALUE!") else: numVal(float64(i + 1)))
  of "SUBSTITUTE":
    need(3)
    return strVal(toText(scalar(arg(0))).replace(toText(scalar(arg(1))), toText(scalar(arg(2)))))
  of "REPT":
    need(2)
    return strVal(repeat(toText(scalar(arg(0))), max(0, int(numArg(1)))))
  of "EXACT":
    need(2)
    return boolVal(toText(scalar(arg(0))) == toText(scalar(arg(1))))
  of "ISBLANK": need(1); return boolVal(scalar(arg(0)).kind == vkEmpty)
  of "ISNUMBER": need(1); return boolVal(scalar(arg(0)).kind == vkNum)
  of "ISTEXT": need(1); return boolVal(scalar(arg(0)).kind == vkStr)
  of "ISLOGICAL": need(1); return boolVal(scalar(arg(0)).kind == vkBool)
  of "ISERROR", "ISERR": need(1); return boolVal(scalar(arg(0)).kind == vkErr)
  of "ISNA":
    need(1)
    let v = scalar(arg(0))
    return boolVal(v.kind == vkErr and v.str == "#N/A")
  of "NA": return errVal("#N/A")
  of "CHOOSE":
    need(2)
    let i = int(numArg(0))
    if i < 1 or i >= args.len: return errVal("#VALUE!")
    return arg(i)
  of "TRANSPOSE":
    need(1)
    let a = arg(0)
    if a.kind != vkArr: return a
    var t = Value(kind: vkArr, rows: a.cols, cols: a.rows, items: newSeq[Value](a.items.len))
    for r in 0 ..< a.rows:
      for c in 0 ..< a.cols: t.items[c * a.rows + r] = a.items[r * a.cols + c]
    return t
  else:
    return errVal("#NAME?")

# Small helpers used above (kept after the evaluator to keep it readable).
proc runeLenCompat(s: string): int =
  for ch in s:
    if (ord(ch) and 0xC0) != 0x80: inc result

proc isDateFormat*(fmt: string): bool =
  ## y, d, h or s outside quotes and [colour] brackets: a date/time format.
  var inQuote, inBracket = false
  for ch in fmt:
    if ch == '"': inQuote = not inQuote
    elif not inQuote and ch == '[': inBracket = true
    elif ch == ']': inBracket = false
    elif not inQuote and not inBracket and ch in {'y', 'Y', 'd', 'D', 'h', 'H', 's', 'S'}: return true
  false

proc formatDate*(serial: float64, fmt: string): string =
  ## Excel serial date (1900 system) with yyyy yy mmmm mmm mm m dddd ddd dd d
  ## hh h mm ss AM/PM; m after h or before s is minutes.
  const Months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
  const Days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
  var days = int(floor(serial))
  var secs = int(round((serial - floor(serial)) * 86400))
  if secs >= 86400: inc days; secs -= 86400
  # days since 1899-12-30 (Excel's leap-year bug: serial 60 is 1900-02-29)
  var z = days - 25569 + 719468            # to days since 0000-03-01 (civil algorithm), via 1970-01-01
  if days < 61 and days > 0: z += 1        # before the fictitious 1900-02-29
  let era = (if z >= 0: z else: z - 146096) div 146097
  let doe = z - era * 146097
  let yoe = (doe - doe div 1460 + doe div 36524 - doe div 146096) div 365
  var y = yoe + era * 400
  let doy = doe - (365 * yoe + yoe div 4 - yoe div 100)
  let mp = (5 * doy + 2) div 153
  let d = doy - (153 * mp + 2) div 5 + 1
  let m = if mp < 10: mp + 3 else: mp - 9
  if m <= 2: inc y
  let weekday = ((days mod 7) + 6) mod 7     # serial 1 (1900-01-01) was a Sunday in Excel's calendar
  var h = secs div 3600
  let mi = (secs div 60) mod 60
  let se = secs mod 60
  let ampm = "AM/PM" in fmt.toUpperAscii or "A/P" in fmt.toUpperAscii
  var hour = h
  if ampm:
    hour = h mod 12
    if hour == 0: hour = 12
  let f = fmt.split(';')[0]
  var i = 0
  var lastWasHour = false
  while i < f.len:
    let ch = f[i]
    var j = i
    while j < f.len and toLowerAscii(f[j]) == toLowerAscii(ch): inc j
    let n = j - i
    case toLowerAscii(ch)
    of 'y': result.add (if n <= 2: align($(y mod 100), 2, '0') else: $y)
    of 'd':
      result.add (case n
        of 1: $d
        of 2: align($d, 2, '0')
        of 3: Days[weekday][0 .. 2]
        else: Days[weekday])
    of 'm':
      var k = j
      while k < f.len and f[k] in {' ', ':', '.'}: inc k
      let minutes = lastWasHour or (k < f.len and toLowerAscii(f[k]) == 's')
      if minutes: result.add (if n == 1: $mi else: align($mi, 2, '0'))
      else:
        result.add (case n
          of 1: $m
          of 2: align($m, 2, '0')
          of 3: Months[m - 1][0 .. 2]
          else: Months[m - 1])
    of 'h': result.add (if n == 1: $hour else: align($hour, 2, '0'))
    of 's': result.add (if n == 1: $se else: align($se, 2, '0'))
    of 'a':
      if f.substr(i, i + 4).toUpperAscii == "AM/PM": result.add (if h < 12: "AM" else: "PM"); j = i + 5
      elif f.substr(i, i + 2).toUpperAscii == "A/P": result.add (if h < 12: "A" else: "P"); j = i + 3
      else: result.add f[i ..< j]
    of '"':
      let close = f.find('"', i + 1)
      result.add f[i + 1 ..< (if close < 0: f.len else: close)]
      j = if close < 0: f.len else: close + 1
    of '[':
      let close = f.find(']', i)
      let inner = f[i + 1 ..< (if close < 0: f.len else: close)]
      if inner.len > 0 and toLowerAscii(inner[0]) == 'h': result.add $(days * 24 + h)   # [h] elapsed hours
      j = if close < 0: f.len else: close + 1
    of '\\':
      if i + 1 < f.len: result.add f[i + 1]
      j = i + 2
    else: result.add f[i ..< j]
    if toLowerAscii(ch) == 'h': lastWasHour = true
    elif toLowerAscii(ch) notin {' ', ':', '.'}: lastWasHour = false
    i = j

proc formatNumber*(x: float64, fmt: string): string =
  ## A practical subset of Excel number formats: 0, 0.00, #,##0.00, 0%,
  ## 0.00%, 0.00E+00, dates and times, @ and General.
  if isDateFormat(fmt): return formatDate(x, fmt)
  var f = fmt.strip
  if f.len == 0 or cmpIgnoreCase(f, "General") == 0: return fmtGeneral(x)
  if f == "@": return fmtGeneral(x)
  var v = x
  var suffix = ""
  if f.endsWith("%"): v *= 100; suffix = "%"; f = f[0 ..< ^1]
  let sci = f.toUpperAscii.find("E+")
  let dot = f.find('.')
  let body = if sci >= 0: f[0 ..< sci] else: f
  let decimals = if dot >= 0 and (sci < 0 or dot < sci): (block:
      var n = 0
      for ch in body[dot + 1 .. ^1]:
        if ch in {'0', '#'}: inc n
      n) else: 0
  if sci >= 0:
    var s = formatFloat(v, ffScientific, decimals)
    let e = s.find('e')
    var expo = s[e + 1 .. ^1]
    let sign = if expo[0] == '-': "-" else: "+"
    expo = expo.strip(chars = {'+', '-'}).strip(trailing = false, chars = {'0'})
    if expo.len < 2: expo = repeat('0', 2 - expo.len) & expo
    return s[0 ..< e] & "E" & sign & expo & suffix
  var s = formatFloat(abs(v), ffDecimal, decimals)
  if ',' in body:
    let dp = s.find('.')
    var intPart = if dp >= 0: s[0 ..< dp] else: s
    let frac = if dp >= 0: s[dp .. ^1] else: ""
    var grouped = ""
    for i, ch in intPart:
      if i > 0 and (intPart.len - i) mod 3 == 0: grouped.add ','
      grouped.add ch
    s = grouped & frac
  (if v < 0 and s.anyIt(it in {'1'..'9'}): "-" else: "") & s & suffix

# ------------------------------------------------------------ recalculation --

proc evalCell*(wb: Workbook, s: Sheet, r, c: int): Value =
  ## The current value of a cell, computing its formula once per pass.
  let k = key(r, c)
  if not s.cells.hasKey(k): return emptyVal()
  let cell = s.cells[k]
  if cell.formula.len == 0 or cell.stamp == wb.pass: return cell.value
  if cell.stamp == -wb.pass: return errVal("#CYCLE!")
  s.cells[k].stamp = -wb.pass
  var v: Value
  if cell.ast == nil: v = errVal("#NAME?")
  else:
    try: v = eval(Ctx(wb: wb, sheet: s), cell.ast)
    except CatchableError: v = errVal("#VALUE!")
  if v.kind == vkArr: v = (if v.items.len > 0: v.items[0] else: emptyVal())
  if v.kind == vkEmpty: v = numVal(0)
  s.cells[k].value = v
  s.cells[k].stamp = wb.pass
  v

proc recalc*(wb: Workbook) =
  ## Recomputes every formula of the workbook.
  inc wb.pass
  if wb.pass > 1_000_000_000: wb.pass = 1
  for s in wb.sheets:
    var ks: seq[int64]
    for k, cell in s.cells:
      if cell.formula.len > 0: ks.add k
    for k in ks: discard evalCell(wb, s, rowOf(k), colOf(k))

proc setFormula*(cell: var Cell, text: string) =
  cell.formula = text
  cell.stamp = 0
  try: cell.ast = parseFormula(text)
  except CatchableError: cell.ast = nil
