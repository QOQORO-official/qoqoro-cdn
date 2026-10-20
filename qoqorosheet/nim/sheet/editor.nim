## The cell editor's formula support, included into view.nim: Luckysheet's
## look (formula.js functionHTML colours, range highlight boxes, function list,
## argument help) with Excel's behaviour (Enter / Edit / Point modes, F4).
##
## Text positions in the editor are UTF-16 offsets (what DOM ranges count);
## Nim strings are UTF-8, so offsets are converted at the edges.

proc acceptSearch(v: SheetView)
proc updateHelp(v: SheetView)

const RefLetters = {'A'..'Z', 'a'..'z'}

# ------------------------------------------------------------ text offsets --

proc u16Len(s: string): int =
  for r in s.runes: result += (if int32(r) > 0xFFFF: 2 else: 1)

proc u16ToByte(s: string, u: int): int =
  ## The byte index of UTF-16 offset `u` in `s`.
  var n = 0
  var i = 0
  while i < s.len and n < u:
    let r = s.runeAt(i)
    n += (if int32(r) > 0xFFFF: 2 else: 1)
    i += r.size
  i

proc byteToU16(s: string, b: int): int = u16Len(s[0 ..< min(b, s.len)])

proc activeEd(v: SheetView): Node = (if v.editFromFormulaBar: v.fxBar else: v.editor)

proc edText(v: SheetView): string = v.activeEd.getStr("textContent")

proc caretOffset(v: SheetView): int =
  ## The caret as a UTF-16 offset into the editor's text (-1: not in it).
  let ed = v.activeEd
  let sel = window.invoke("getSelection").toNode
  if sel.isNil or sel.getNum("rangeCount") < 1: return -1
  let r = sel.invoke("getRangeAt", 0).toNode
  let node = r.getNode("endContainer")
  if not (ed.same(node) or ed.contains(node)): return -1
  let pre = document.invoke("createRange").toNode
  pre.call("selectNodeContents", ed)
  pre.call("setEnd", node, r.getNum("endOffset"))
  result = int(pre.invoke("toString").toStr.u16Len)
  pre.release()

proc setCaret(v: SheetView, offset: int) =
  let ed = v.activeEd
  let sel = window.invoke("getSelection").toNode
  if sel.isNil: return
  let range = document.invoke("createRange").toNode
  let walker = document.invoke("createTreeWalker", ed, 4).toNode     # NodeFilter.SHOW_TEXT
  var acc = 0
  var placed = false
  while true:
    let node = walker.invoke("nextNode").toNode
    if node.isNil: break
    let len = int(node.getNum("length"))
    if acc + len >= offset:
      range.call("setStart", node, offset - acc)
      placed = true
      break
    acc += len
  if not placed:
    range.call("selectNodeContents", ed)
    range.call("collapse", false)
  else:
    range.call("collapse", true)
  sel.call("removeAllRanges")
  sel.call("addRange", range)
  range.release(); walker.release()

# ------------------------------------------------------- formula colouring --

const LuckyColor = ["#c1232b", "#27727b", "#fcce10", "#e87c25", "#b5c334", "#fe8463", "#9bca63", "#fad860",
  "#f3a43b", "#60c0dd", "#d7504b", "#c6e579", "#f4e001", "#f0805a", "#26c0c0", "#c12e34", "#e6b600", "#0098d9",
  "#2b821d", "#005eaa", "#339ca8", "#cda819", "#32a487", "#3fb1e3", "#6be6c1", "#626c91", "#a0a7e6", "#c4ebad", "#96dee8"]
const FormulaOps = ["==", "!=", "<>", "<=", ">=", "=", "+", "-", ">", "<", "/", "*", "%", "&", "^"]

proc esc(s: string): string = s.multiReplace(("&", "&amp;"), ("<", "&lt;"), (">", "&gt;"))

proc isCellData(t: string): bool =
  ## iscelldata, through the engine's own reference parser.
  let refs = formulaRefs("=" & t)
  refs.len == 1 and refs[0].start == 1 and refs[0].stop == t.len + 1

proc functionHTML(txt: string, index: var int): string =
  ## formula.js functionHTML: spans for functions, parentheses, operators,
  ## strings and (coloured, numbered) references.
  var s = if txt.len > 0 and txt[0] == '=': txt[1 .. ^1] else: txt
  var i = 0
  var str = ""
  var bracket, squote, dquote, braces = 0
  let chars = toSeq(s.runes).mapIt($it)
  while i < chars.len:
    let c = chars[i]
    if c == "(" and squote == 0 and dquote == 0 and braces == 0:
      inc bracket
      if str.len > 0:
        result.add "<span dir=\"auto\" class=\"luckysheet-formula-text-func\">" & esc(str) & "</span><span dir=\"auto\" class=\"luckysheet-formula-text-lpar\">(</span>"
      else:
        result.add "<span dir=\"auto\" class=\"luckysheet-formula-text-lpar\">(</span>"
      str = ""
    elif c == ")" and squote == 0 and dquote == 0 and braces == 0:
      dec bracket
      result.add functionHTML(str, index) & "<span dir=\"auto\" class=\"luckysheet-formula-text-rpar\">)</span>"
      str = ""
    elif c == "{" and squote == 0 and dquote == 0:
      str.add "{"; inc braces
    elif c == "}" and squote == 0 and dquote == 0:
      str.add "}"; dec braces
    elif c == "\"" and squote == 0:
      if dquote > 0:
        result.add esc(str) & "\"</span>"
        dec dquote
        str = ""
      else:
        inc dquote
        result.add (if str.len > 0: functionHTML(str, index) else: "") & "<span dir=\"auto\" class=\"luckysheet-formula-text-string\">\""
        str = ""
    elif c == "'" and dquote == 0:
      str.add "'"
      squote = if squote == 0: 1 else: 0
    elif c == "," and squote == 0 and dquote == 0 and braces == 0:
      result.add functionHTML(str, index) & "<span dir=\"auto\" class=\"luckysheet-formula-text-comma\">,</span>"
      str = ""
    elif c == "&" and squote == 0 and dquote == 0 and braces == 0:
      result.add (if str.len > 0: functionHTML(str, index) else: "") & "<span dir=\"auto\" class=\"luckysheet-formula-text-calc\">&amp;</span>"
      str = ""
    elif c in FormulaOps and squote == 0 and dquote == 0 and braces == 0:
      let next = if i + 1 < chars.len: chars[i + 1] else: ""
      var p = i - 1
      var pre = ""
      while p >= 0:
        pre = chars[p]; dec p
        if pre != " ": break
      if (c & next) in FormulaOps:
        result.add (if str.len > 0: functionHTML(str, index) else: "") & "<span dir=\"auto\" class=\"luckysheet-formula-text-calc\">" & esc(c & next) & "</span>"
        str = ""
        inc i
      elif c == "-" and next.len > 0 and next[0] in {'0'..'9'} and (pre in ["(", "", ",", " "] or pre in FormulaOps):
        str.add c
      else:
        result.add (if str.len > 0: functionHTML(str, index) else: "") & "<span dir=\"auto\" class=\"luckysheet-formula-text-calc\">" & esc(c) & "</span>"
        str = ""
    else:
      str.add c
    if i == chars.high:
      if isCellData(str.strip):
        result.add "<span class=\"luckysheet-formula-functionrange-cell\" rangeindex=\"" & $index & "\" dir=\"auto\" style=\"color:" &
          LuckyColor[index mod LuckyColor.len] & ";\">" & esc(str) & "</span>"
        inc index
      elif dquote > 0:
        result.add esc(str) & "</span>"
      elif str.len > 0:
        result.add "<span dir=\"auto\" class=\"luckysheet-formula-text-color\">" & esc(str) & "</span>"
    inc i

proc functionHTMLGenerate(txt: string): string =
  if txt.len == 0 or txt[0] != '=': return esc(txt)
  var index = 0
  "<span dir=\"auto\" class=\"luckysheet-formula-text-color\">=</span>" & functionHTML(txt, index)

# ------------------------------------------------------ reference highlights --

proc clearRangeBoxes(v: SheetView) =
  let sel = byId("luckysheet-formula-functionrange-select")
  if not sel.isNil: sel.style("display", "none")
  let box = byId("luckysheet-formula-functionrange")
  if not box.isNil:
    for n in box.queryAll(".luckysheet-formula-functionrange-highlight"): n.remove()

proc showRangeBoxes(v: SheetView, text: string) =
  ## createRangeHightlight: a coloured box over every reference of this sheet,
  ## numbered in order as the editor colours them.
  v.clearRangeBoxes()
  if text.len == 0 or text[0] != '=': return
  let box = byId("luckysheet-formula-functionrange")
  if box.isNil: return
  let s = v.sheet
  let pointed = if v.pointActive: u16ToByte(text, v.pointStart) else: -1
  for i, rf in formulaRefs(text):
    if rf.sheet.len > 0 and v.wb.sheetNamed(rf.sheet) != s: continue
    if rf.start == pointed:
      # the range being pointed at: Luckysheet's dashed selection box
      let sel = byId("luckysheet-formula-functionrange-select")
      if not sel.isNil:
        let (x, y, w, h) = v.rangeBox(rf.r1, rf.c1, min(rf.r2, s.rowCount - 1), min(rf.c2, s.colCount - 1))
        sel.setAttribute("style", "left: " & px(x) & "; width: " & px(w) & "; top: " & px(y) & "; height: " & px(h) & "; display: block;")
      continue
    let color = LuckyColor[i mod LuckyColor.len]
    let d = el("div", "luckysheet-selection-highlight luckysheet-formula-functionrange-highlight")
    d.setAttribute("id", "luckysheet-formula-functionrange-highlight-" & $i)
    d.setAttribute("rangeindex", $i)
    d.setProp("innerHTML",
      "<div data-type=\"top\" class=\"luckysheet-selection-copy-top luckysheet-copy\"></div><div data-type=\"right\" class=\"luckysheet-selection-copy-right luckysheet-copy\"></div>" &
      "<div data-type=\"bottom\" class=\"luckysheet-selection-copy-bottom luckysheet-copy\"></div><div data-type=\"left\" class=\"luckysheet-selection-copy-left luckysheet-copy\"></div>" &
      "<div class=\"luckysheet-selection-copy-hc\"></div><div data-type=\"lt\" class=\"luckysheet-selection-highlight-topleft luckysheet-highlight\"></div>" &
      "<div data-type=\"rt\" class=\"luckysheet-selection-highlight-topright luckysheet-highlight\"></div><div data-type=\"lb\" class=\"luckysheet-selection-highlight-bottomleft luckysheet-highlight\"></div>" &
      "<div data-type=\"rb\" class=\"luckysheet-selection-highlight-bottomright luckysheet-highlight\"></div>")
    for n in d.queryAll(".luckysheet-copy, .luckysheet-highlight, .luckysheet-selection-copy-hc"): n.style("background", color)
    let (x, y, w, h) = v.rangeBox(rf.r1, rf.c1, min(rf.r2, s.rowCount - 1), min(rf.c2, s.colCount - 1))
    d.setAttribute("style", "left: " & px(x) & "; width: " & px(w) & "; top: " & px(y) & "; height: " & px(h) & "; display: block;")
    discard box.add d

# ------------------------------------------------------- function list/help --

proc loadFunctions(v: SheetView) =
  fetchBytes("functions.json", proc(ok: bool, data: string) =
    if not ok: return
    try:
      for f in parseJson(data):
        var info = FuncInfo(name: f["n"].getStr, abstract: f["a"].getStr, detail: f["d"].getStr)
        for p in f["p"]:
          info.params.add FuncParam(name: p["name"].getStr, detail: p["detail"].getStr, example: p["example"].getStr,
            optional: p["require"].getStr == "o", repeat: p["repeat"].getStr == "y")
        v.funcs.add info
    except CatchableError: discard)

proc hideSearch(v: SheetView) =
  if not v.searchBox.isNil: v.searchBox.style("display", "none")
  v.searchItems.setLen(0)

proc hideHelp(v: SheetView) =
  if not v.helpBox.isNil: v.helpBox.style("display", "none")

proc placeBelowEditor(v: SheetView, menu: Node) =
  ## searchFunctionPosition: under the input box, or above it without room.
  let r = v.inputBox.rect
  menu.style("display", "block")
  let mw = menu.getNum("offsetWidth")
  let mh = menu.getNum("offsetHeight")
  let left = if r.left + mw > window.getNum("innerWidth"): r.left - mw + r.width else: r.left
  let top = if r.top + r.height + mh > window.getNum("innerHeight"): r.top - mh else: r.top + r.height
  menu.style("left", px(left)); menu.style("top", px(top))

proc tokenBeforeCaret(text: string, caretByte: int): (int, string) =
  ## The function-name prefix just before the caret (letters, digits, _ . )
  ## starting with a letter, outside strings; (-1, "") if none.
  var quotes = 0
  for i in 0 ..< caretByte:
    if text[i] == '"': inc quotes
  if quotes mod 2 == 1: return (-1, "")
  var j = caretByte
  while j > 0 and text[j - 1] in {'A'..'Z', 'a'..'z', '0'..'9', '_', '.'}: dec j
  if j == caretByte or text[j] notin {'A'..'Z', 'a'..'z'}: return (-1, "")
  if j > 0 and text[j - 1] in {'$', '!', '\'', ':'}: return (-1, "")
  (j, text[j ..< caretByte])

proc renderSearch(v: SheetView) =
  if v.searchBox.isNil:
    v.searchBox = el("div", "luckysheet-formula-search-c")
    v.searchBox.setAttribute("id", "luckysheet-formula-search-c")
    discard document.query("body").add v.searchBox
  var html = ""
  for i, n in v.searchItems:
    var abstract = ""
    for f in v.funcs:
      if f.name == n: abstract = f.abstract
    html.add "<div data-func=\"" & n & "\" class=\"luckysheet-formula-search-item" & (if i == v.searchActive: " luckysheet-formula-search-item-active" else: "") &
      "\"><div class=\"luckysheet-formula-search-func\">" & n & "</div><div class=\"luckysheet-formula-search-detail\">" & esc(abstract) & "</div></div>"
  v.searchBox.setProp("innerHTML", html)
  for i_1, item_1 in v.searchBox.queryAll(".luckysheet-formula-search-item"):
    let i_0 = i_1
    let item_0 = item_1
    closureScope:
      let i = i_0
      let item = item_0
      let k = i
      item.on("mousedown", proc(e: Event) =
        e.preventDefault()          # keep the editor's focus and caret
        v.searchActive = k
        v.acceptSearch())
  v.placeBelowEditor(v.searchBox)

proc updateSearch(v: SheetView) =
  ## Excel's formula AutoComplete: functions starting with the name being typed.
  let text = v.edText
  let caret = v.caretOffset
  if text.len == 0 or text[0] != '=' or caret < 0 or v.funcs.len == 0: v.hideSearch(); return
  let cb = u16ToByte(text, caret)
  let (start, tok) = tokenBeforeCaret(text, cb)
  if start < 0 or (cb < text.len and text[cb] == '('): v.hideSearch(); return
  let up = tok.toUpperAscii
  v.searchItems.setLen(0)
  for f in v.funcs:
    if f.name.startsWith(up): v.searchItems.add f.name
  if v.searchItems.len == 0: v.hideSearch(); return
  v.searchItems.setLen(min(v.searchItems.len, 12))
  v.searchActive = 0
  v.searchToken = (byteToU16(text, start), caret)
  v.renderSearch()

proc acceptSearch(v: SheetView) =
  ## Tab / click in the list: the name and an opening parenthesis.
  if v.searchItems.len == 0: return
  let name = v.searchItems[v.searchActive]
  let text = v.edText
  let a = u16ToByte(text, v.searchToken[0])
  let b = u16ToByte(text, v.searchToken[1])
  let t = text[0 ..< a] & name & "(" & text[b .. ^1]
  v.hideSearch()
  v.renderEditor(t, v.searchToken[0] + u16Len(name) + 1)
  v.updateHelp()

proc callAtCaret(text: string, caretByte: int): (string, int) =
  ## The innermost function call around the caret and the argument it is in.
  var stack: seq[(string, int)]
  var i = 1
  var inStr = false
  while i < caretByte:
    let ch = text[i]
    if ch == '"': inStr = not inStr
    elif not inStr:
      if ch == '(':
        var j = i
        while j > 0 and text[j - 1] in {'A'..'Z', 'a'..'z', '0'..'9', '_', '.'}: dec j
        stack.add (text[j ..< i].toUpperAscii, 0)
      elif ch == ')' and stack.len > 0: discard stack.pop()
      elif ch == ',' and stack.len > 0: inc stack[^1][1]
    inc i
  if stack.len == 0: ("", 0) else: stack[^1]

proc updateHelp(v: SheetView) =
  ## helpFunction: the function's signature, current argument highlighted, its
  ## description and the arguments' (Luckysheet's help box, en locale).
  let text = v.edText
  let caret = v.caretOffset
  if text.len == 0 or text[0] != '=' or caret < 0 or (not v.searchBox.isNil and v.searchItems.len > 0): v.hideHelp(); return
  let (name, arg) = callAtCaret(text, u16ToByte(text, caret))
  var info: FuncInfo
  var found = false
  for f in v.funcs:
    if f.name == name: info = f; found = true
  if not found or info.params.len == 0: v.hideHelp(); return
  if v.helpBox.isNil:
    v.helpBox = el("div", "luckysheet-formula-help-c")
    v.helpBox.setAttribute("id", "luckysheet-formula-help-c")
    discard document.query("body").add v.helpBox
  let active = min(arg, info.params.high)
  var sig, ex, params = ""
  for i, p in info.params:
    var nm = p.name
    var li = p.name
    if p.repeat:
      nm.add ", ..."
      li.add "<span class=\"luckysheet-arguments-help-argument-info\">...-Repeat</span>"
    if p.optional:
      nm = "[" & nm & "]"
      li.add "<span class=\"luckysheet-arguments-help-argument-info\">-[Option]</span>"
    let cls = "luckysheet-arguments-help-parameter" & (if i == active: " luckysheet-arguments-help-parameter-active" else: "")
    sig.add (if i > 0: ", " else: "") & "<span class=\"" & cls & "\" dir=\"auto\">" & esc(nm) & "</span>"
    ex.add (if i > 0: ", " else: "") & "<span class=\"luckysheet-arguments-help-parameter\" dir=\"auto\">" & esc(p.example) & "</span>"
    params.add "<div class=\"luckysheet-arguments-help-section\"><div class=\"luckysheet-arguments-help-section-title\">" & li &
      "</div><span class=\"luckysheet-arguments-help-parameter-content\">" & esc(p.detail) & "</span></div>"
  let fn = "<span class=\"luckysheet-arguments-help-function-name\">" & info.name & "</span> <span class=\"luckysheet-arguments-paren\">(</span> " &
    "<span class=\"luckysheet-arguments-parameter-holder\">"
  v.helpBox.setProp("innerHTML",
    " <div class=\"luckysheet-formula-help-close\" title=\"Close\"><i class=\"fa fa-times\" aria-hidden=\"true\"></i></div>" &
    " <div class=\"luckysheet-formula-help-collapse\" title=\"Collapse\"><i class=\"fa fa-angle-up\" aria-hidden=\"true\"></i></div>" &
    " <div class=\"luckysheet-formula-help-title\"><div class=\"luckysheet-formula-help-title-formula\"> " & fn & sig &
    "</span> <span class=\"luckysheet-arguments-paren\">)</span> </div></div>" &
    " <div class=\"luckysheet-formula-help-content\"> <div class=\"luckysheet-formula-help-content-example\"> <div class=\"luckysheet-arguments-help-section-title\">Example</div>" &
    " <div class=\"luckysheet-arguments-help-formula\"> " & fn & ex & "</span> <span class=\"luckysheet-arguments-paren\">)</span> </div> </div>" &
    " <div class=\"luckysheet-formula-help-content-detail\"> <div class=\"luckysheet-arguments-help-section\"> <div class=\"luckysheet-arguments-help-section-title luckysheet-arguments-help-parameter-name\">Abstract</div>" &
    " <span class=\"luckysheet-arguments-help-parameter-content\">" & esc(info.detail) & "</span> </div> </div>" &
    " <div class=\"luckysheet-formula-help-content-param\"> " & params & " </div> </div> <div class=\"luckysheet-formula-help-foot\"></div>")
  v.helpBox.query(".luckysheet-formula-help-title-formula .luckysheet-arguments-help-function-name").style("font-weight", "normal")
  # Excel's ScreenTip: the signature line; the arrow opens Luckysheet's details
  v.helpBox.query(".luckysheet-formula-help-content").style("display", if v.helpExpanded: "block" else: "none")
  let collapse = v.helpBox.query(".luckysheet-formula-help-collapse")
  if not collapse.isNil:
    collapse.setProp("innerHTML", if v.helpExpanded: "<i class=\"fa fa-angle-up\" aria-hidden=\"true\"></i>" else: "<i class=\"fa fa-angle-down\" aria-hidden=\"true\"></i>")
    collapse.on("mousedown", proc(e: Event) =
      e.preventDefault()
      v.helpExpanded = not v.helpExpanded
      v.updateHelp())
  let close = v.helpBox.query(".luckysheet-formula-help-close")
  if not close.isNil:
    close.on("mousedown", proc(e: Event) =
      e.preventDefault(); v.hideHelp())
  v.placeBelowEditor(v.helpBox)

# ------------------------------------------------------------- rendering ----

proc renderEditor(v: SheetView, text: string, caret: int) =
  ## The editor's coloured HTML (formulaBar <-> cell editor kept equal), the
  ## range boxes, the caret put back.
  let html = functionHTMLGenerate(text)
  v.editor.setProp("innerHTML", html)
  v.fxBar.setProp("innerHTML", html)
  v.setCaret(caret)
  v.showRangeBoxes(text)
  if not v.editFromFormulaBar: v.centerEditor()

proc clearFormulaUI(v: SheetView) =
  v.clearRangeBoxes()
  v.hideSearch()
  v.hideHelp()
  v.pointActive = false

# ------------------------------------------------------------- point mode ---

proc canPoint(v: SheetView): bool =
  ## Excel's Point mode: in a formula, right after "=", "(", ",", an operator
  ## or the reference being pointed at.
  let text = v.edText
  if text.len == 0 or text[0] != '=': return false
  let caret = v.caretOffset
  if caret < 0: return false
  if v.pointActive and caret == v.pointEnd: return true
  let cb = u16ToByte(text, caret)
  var quotes = 0
  for i in 0 ..< cb:
    if text[i] == '"': inc quotes
  if quotes mod 2 == 1: return false
  var j = cb - 1
  while j >= 0 and text[j] == ' ': dec j
  j >= 0 and text[j] in {'=', '(', ',', '+', '-', '*', '/', '^', '&', '<', '>', ':', ';', '%'}

proc refName(v: SheetView, r1, c1, r2, c2: int): string =
  ## A1 or A1:B2; a merged range alone is its top-left cell.
  let s = v.sheet
  let (a, b, e, f) = (min(r1, r2), min(c1, c2), max(r1, r2), max(c1, c2))
  let mi = s.mergeAt(a, b)
  if (a == e and b == f) or (mi >= 0 and (let m = s.merges[mi]; m.r1 == a and m.c1 == b and m.r2 == e and m.c2 == f)):
    cellName(a, b)
  else: cellName(a, b) & ":" & cellName(e, f)

proc pointAt(v: SheetView, anchorR, anchorC, r, c: int) =
  ## Put (or move) the pointed reference into the formula at the caret.
  let text = v.edText
  if not v.pointActive:
    let caret = max(0, v.caretOffset)
    v.pointStart = caret; v.pointEnd = caret
    v.pointActive = true
  v.pointAnchor = (anchorR, anchorC)
  v.pointFocus = (r, c)
  let name = v.refName(anchorR, anchorC, r, c)
  let a = u16ToByte(text, v.pointStart)
  let b = u16ToByte(text, v.pointEnd)
  let t = text[0 ..< a] & name & text[b .. ^1]
  v.pointEnd = v.pointStart + u16Len(name)
  v.renderEditor(t, v.pointEnd)
  v.hideSearch()
  v.updateHelp()
  v.scrollIntoView(r, c)

proc pointMove(v: SheetView, dr, dc: int, extend: bool) =
  ## An arrow in Point mode: the first one points at the cell next to the one
  ## being edited; later ones move (Shift: stretch) the reference.
  let s = v.sheet
  var (r, c) = if v.pointActive: v.pointFocus else: (v.ar, v.ac)
  (r, c) = s.stepFrom(r, c, dr, dc)
  r = clamp(r, 0, s.rowCount - 1); c = clamp(c, 0, s.colCount - 1)
  let (ar, ac) = if extend and v.pointActive: v.pointAnchor else: (r, c)
  v.pointAt(ar, ac, r, c)

proc toggleAbsolute(v: SheetView) =
  ## F4: the reference at the caret cycles A1 -> $A$1 -> A$1 -> $A1 -> A1.
  let text = v.edText
  let caret = v.caretOffset
  if text.len == 0 or text[0] != '=' or caret < 0: return
  let cb = u16ToByte(text, caret)
  for rf in formulaRefs(text):
    if cb < rf.start or cb > rf.stop: continue
    var body = text[rf.start ..< rf.stop]
    var prefix = ""
    let bang = body.rfind('!')
    if bang >= 0: prefix = body[0 .. bang]; body = body[bang + 1 .. ^1]
    proc cycle(part: string): string =
      var i = 0
      let absC = part.len > 0 and part[0] == '$'
      if absC: inc i
      var letters = ""
      while i < part.len and part[i] in RefLetters: letters.add part[i]; inc i
      let absR = i < part.len and part[i] == '$'
      if absR: inc i
      let digits = part[i .. ^1]
      let (nc, nr) = if not absC and not absR: (true, true)
                     elif absC and absR: (false, true)
                     elif absR: (true, false)
                     else: (false, false)
      (if nc and letters.len > 0: "$" else: "") & letters & (if nr and digits.len > 0: "$" else: "") & digits
    let parts = body.split(':')
    let nb = prefix & parts.mapIt(cycle(it)).join(":")
    let t = text[0 ..< rf.start] & nb & text[rf.stop .. ^1]
    v.renderEditor(t, byteToU16(t, rf.start + nb.len))
    return
