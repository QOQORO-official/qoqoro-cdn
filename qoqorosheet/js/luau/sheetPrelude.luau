--!nonstrict
-- QoqoroSheet program prelude. Runs before every program and builds the
-- spreadsheet object model on three host primitives:
--
--   __sheet_op(name, json)       record a command (applied after the program ends)
--   __sheet_data(index) -> text  one sheet's cells, packed (see sheetLuau.js)
--   __sheet_ask(kind, text, def) a dialog answered by the page (InputBox / MsgBox)
--
-- Rows and columns are 1-based, like Excel's Cells(row, column): Cell(1, 1) is A1.
-- Reads see the workbook as it was when the program started, plus the program's
-- own writes. The workbook itself changes only after the program ends, in one go.
-- Luau sandboxes the state (no io, os.execute, require or network), and the
-- prelude returns its model for the host to install as globals.

local op = __sheet_op
local sheetData = __sheet_data
local ask = __sheet_ask
local metaJson = __sheet_meta_json

-- ── JSON ────────────────────────────────────────────────────────────────────
local function decodeJson(text: string): any
	local at = 1
	local value
	local function skip()
		while at <= #text and string.find(string.sub(text, at, at), "^[ \t\r\n]") do
			at += 1
		end
	end
	local escapes = {['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t"}
	local function readString(): string
		at += 1
		local parts = {}
		while at <= #text do
			local char = string.sub(text, at, at)
			if char == '"' then
				at += 1
				return table.concat(parts)
			elseif char == "\\" then
				local code = string.sub(text, at + 1, at + 1)
				if code == "u" then
					local hex = string.sub(text, at + 2, at + 5)
					table.insert(parts, utf8.char(tonumber(hex, 16) or 63))
					at += 6
				else
					table.insert(parts, escapes[code] or code)
					at += 2
				end
			else
				local stop = string.find(text, '["\\]', at) or (#text + 1)
				table.insert(parts, string.sub(text, at, stop - 1))
				at = stop
			end
		end
		error("Unterminated string in JSON")
	end
	function value(): any
		skip()
		local char = string.sub(text, at, at)
		if char == "{" then
			at += 1
			local object = {}
			skip()
			if string.sub(text, at, at) == "}" then
				at += 1
				return object
			end
			while true do
				skip()
				local key = readString()
				skip()
				at += 1 -- ':'
				object[key] = value()
				skip()
				local sep = string.sub(text, at, at)
				at += 1
				if sep == "}" then return object end
			end
		elseif char == "[" then
			at += 1
			local array = {}
			skip()
			if string.sub(text, at, at) == "]" then
				at += 1
				return array
			end
			while true do
				table.insert(array, value())
				skip()
				local sep = string.sub(text, at, at)
				at += 1
				if sep == "]" then return array end
			end
		elseif char == '"' then
			return readString()
		elseif string.sub(text, at, at + 3) == "true" then
			at += 4
			return true
		elseif string.sub(text, at, at + 4) == "false" then
			at += 5
			return false
		elseif string.sub(text, at, at + 3) == "null" then
			at += 4
			return nil
		else
			local stop = string.find(text, "[^-+0-9eE.]", at) or (#text + 1)
			local number = tonumber(string.sub(text, at, stop - 1))
			at = stop
			return number
		end
	end
	return value()
end

local function quote(s: string): string
	s = string.gsub(s, '[%c"\\]', function(c)
		if c == '"' then return '\\"' end
		if c == "\\" then return "\\\\" end
		if c == "\n" then return "\\n" end
		if c == "\r" then return "\\r" end
		if c == "\t" then return "\\t" end
		return string.format("\\u%04x", string.byte(c))
	end)
	return '"' .. s .. '"'
end

-- Tables with keys 1..n are arrays; anything else is an object. An empty table
-- is an array ([]): ECharts options use empty arrays far more than empty objects.
local function encodeJson(v: any, seen: {[any]: boolean}?): string
	local t = type(v)
	if v == nil then return "null" end
	if t == "boolean" then return v and "true" or "false" end
	if t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then return "null" end
		if v == math.floor(v) and math.abs(v) < 2^53 then return string.format("%d", v) end
		return string.format("%.17g", v)
	end
	if t == "string" then return quote(v) end
	if t ~= "table" then error("Cannot convert a " .. t .. " to JSON") end
	seen = seen or {}
	if seen[v] then error("Cannot convert a table that contains itself to JSON") end
	seen[v] = true
	local n, count = #v, 0
	for _ in pairs(v) do count += 1 end
	local parts = {}
	if count == n then
		for i = 1, n do parts[i] = encodeJson(v[i], seen) end
		seen[v] = nil
		return "[" .. table.concat(parts, ",") .. "]"
	end
	local keys = {}
	for k in pairs(v) do table.insert(keys, tostring(k)) end
	table.sort(keys)
	for _, k in ipairs(keys) do
		local item = v[k]
		if item == nil then item = v[tonumber(k)] end
		table.insert(parts, quote(k) .. ":" .. encodeJson(item, seen))
	end
	seen[v] = nil
	return "{" .. table.concat(parts, ",") .. "}"
end

local Json = table.freeze({
	Encode = function(value: any): string return encodeJson(value) end,
	Decode = function(text: string): any return decodeJson(text) end,
})

local function emit(name: string, payload: any)
	op(name, encodeJson(payload))
end

-- ── A1 addresses ────────────────────────────────────────────────────────────
local function columnNumber(letters: string): number
	local n = 0
	for i = 1, #letters do
		n = n * 26 + (string.byte(string.upper(letters), i) - 64)
	end
	return n
end

local function columnLetters(n: number): string
	local s = ""
	while n > 0 do
		local r = (n - 1) % 26
		s = string.char(65 + r) .. s
		n = (n - 1) // 26
	end
	return s
end

local function parseAddress(a1: string): (number, number)
	local letters, digits = string.match(a1, "^%s*%$?(%a+)%$?(%d+)%s*$")
	if not letters then error("Not a cell address: " .. tostring(a1), 3) end
	return tonumber(digits) :: number, columnNumber(letters)
end

-- ── Cells, decoded lazily per sheet ─────────────────────────────────────────
-- Packed format (built by sheetLuau.js): rows joined by \30, cells by \31.
-- A cell is "" (empty) or a tag + payload: n<number> s<text> b1/b0, then
-- optionally \28 + displayed text and \29 + formula.
local function decodeCell(token: string): {[string]: any}?
	if token == "" then return nil end
	local formula, shown
	local f = string.find(token, "\29", 1, true)
	if f then formula = string.sub(token, f + 1); token = string.sub(token, 1, f - 1) end
	local m = string.find(token, "\28", 1, true)
	if m then shown = string.sub(token, m + 1); token = string.sub(token, 1, m - 1) end
	local tag, payload = string.sub(token, 1, 1), string.sub(token, 2)
	local v: any = nil
	if tag == "n" then v = tonumber(payload)
	elseif tag == "s" then v = payload
	elseif tag == "b" then v = payload == "1" end
	return {v = v, m = shown, f = formula}
end

local Worksheet = {}
Worksheet.__index = Worksheet

local sheets: {any} = {}
local byName: {[string]: any} = {}
local active: any = nil

local function load(self)
	if self._rows then return end
	local rows = {}
	local lastRow, lastCol = 0, 0
	local packed = sheetData(self._order)
	if packed and #packed > 0 then
		for r, line in ipairs(string.split(packed, "\30")) do
			if line ~= "" then
				local row = {}
				for c, token in ipairs(string.split(line, "\31")) do
					local cell = decodeCell(token)
					if cell then
						row[c] = cell
						if c > lastCol then lastCol = c end
						lastRow = r
					end
				end
				rows[r] = row
			end
		end
	end
	self._rows, self._lastRow, self._lastCol = rows, lastRow, lastCol
end

local function cellAt(self, r: number, c: number)
	load(self)
	local row = self._rows[r]
	return row and row[c]
end

local function checkRC(r: any, c: any)
	if type(r) ~= "number" or type(c) ~= "number" or r < 1 or c < 1 or r ~= math.floor(r) or c ~= math.floor(c) then
		error("Rows and columns are whole numbers from 1 (Cell(1, 1) is A1)", 3)
	end
end

function Worksheet:Cell(r: number, c: number): any
	checkRC(r, c)
	local cell = cellAt(self, r, c)
	return cell and cell.v
end

function Worksheet:Text(r: number, c: number): string
	checkRC(r, c)
	local cell = cellAt(self, r, c)
	if not cell then return "" end
	if cell.m ~= nil then return cell.m end
	if cell.v == nil then return "" end
	return tostring(cell.v)
end

function Worksheet:Formula(r: number, c: number): string?
	checkRC(r, c)
	local cell = cellAt(self, r, c)
	return cell and cell.f
end

local function put(self, r: number, c: number, cell)
	load(self)
	local row = self._rows[r]
	if not row then row = {}; self._rows[r] = row end
	row[c] = cell
	if cell then
		if r > self._lastRow then self._lastRow = r end
		if c > self._lastCol then self._lastCol = c end
	end
end

-- Formatting keys of a rich cell → Luckysheet's cell fields.
local ALIGN = {center = 0, left = 1, right = 2}
local VALIGN = {middle = 0, top = 1, bottom = 2}
local function styleOf(spec: {[string]: any}): {[string]: any}?
	local style, any = {}, false
	local function set(key, value) style[key] = value; any = true end
	if spec.Background ~= nil then set("bg", spec.Background) end
	if spec.Color ~= nil then set("fc", spec.Color) end
	if spec.Bold ~= nil then set("bl", spec.Bold and 1 or 0) end
	if spec.Italic ~= nil then set("it", spec.Italic and 1 or 0) end
	if spec.Underline ~= nil then set("un", spec.Underline and 1 or 0) end
	if spec.Strike ~= nil then set("cl", spec.Strike and 1 or 0) end
	if spec.FontSize ~= nil then set("fs", spec.FontSize) end
	if spec.Font ~= nil then set("ff", spec.Font) end
	if spec.Align ~= nil then
		local v = ALIGN[spec.Align]
		if v == nil then error('Align is "left", "center" or "right"', 3) end
		set("ht", v)
	end
	if spec.VAlign ~= nil then
		local v = VALIGN[spec.VAlign]
		if v == nil then error('VAlign is "top", "middle" or "bottom"', 3) end
		set("vt", v)
	end
	return any and style or nil
end

local function plainValue(value: any, level: number): any
	local t = type(value)
	if value ~= nil and t ~= "number" and t ~= "string" and t ~= "boolean" then
		error("A cell holds a number, text, true/false or nil, not a " .. t, level)
	end
	if t == "number" and (value ~= value or value == math.huge or value == -math.huge) then return nil end
	return value
end

-- SetCell(r, c, value)  or  SetCell(r, c, { Value = …, Formula = "=…", Text = "shown",
--   Background = "#1e1e2e", Color = "#fff", Bold = true, Italic = true, FontSize = 10.5,
--   Font = "Arial", Align = "left"|"center"|"right", VAlign = "top"|"middle"|"bottom" })
function Worksheet:SetCell(r: number, c: number, value: any)
	checkRC(r, c)
	if type(value) == "table" then
		local v = plainValue(value.Value, 3)
		local f = value.Formula
		if f ~= nil and (type(f) ~= "string" or string.sub(f, 1, 1) ~= "=") then error('A formula starts with "="', 2) end
		local m = value.Text ~= nil and tostring(value.Text) or nil
		put(self, r, c, (v ~= nil or f ~= nil or m ~= nil) and {v = v, m = m, f = f} or nil)
		emit("set", {sheet = self._order, r = r, c = c, v = v, f = f, m = m, style = styleOf(value)})
		return
	end
	local v = plainValue(value, 3)
	put(self, r, c, v ~= nil and {v = v} or nil)
	emit("set", {sheet = self._order, r = r, c = c, v = v})
end

-- Clear(r1, c1, r2, c2): values, formulas and formatting of a block.
function Worksheet:Clear(r1: number, c1: number, r2: number, c2: number)
	checkRC(r1, c1); checkRC(r2, c2)
	if r2 < r1 then r1, r2 = r2, r1 end
	if c2 < c1 then c1, c2 = c2, c1 end
	load(self)
	for r = r1, math.min(r2, self._lastRow) do
		local row = self._rows[r]
		if row then for c = c1, c2 do row[c] = nil end end
	end
	emit("clear", {sheet = self._order, r1 = r1, c1 = c1, r2 = r2, c2 = c2})
end

function Worksheet:SetFormula(r: number, c: number, formula: string)
	checkRC(r, c)
	if type(formula) ~= "string" or string.sub(formula, 1, 1) ~= "=" then error('A formula starts with "=", e.g. "=SUM(A1:A3)"', 2) end
	put(self, r, c, {f = formula})
	emit("set", {sheet = self._order, r = r, c = c, f = formula})
end

function Worksheet:LastRow(): number load(self); return self._lastRow end
function Worksheet:LastColumn(): number load(self); return self._lastCol end

function Worksheet:Row(r: number): {any}
	checkRC(r, 1)
	local out = {}
	for c = 1, self:LastColumn() do out[c] = self:Cell(r, c) end
	return out
end

function Worksheet:Column(c: number, firstRow: number?): {any}
	checkRC(1, c)
	local out = {}
	for r = firstRow or 1, self:LastRow() do table.insert(out, self:Cell(r, c)) end
	return out
end

-- Find(text): the first cell whose text equals `text` (or contains it with
-- partial = true), scanning row by row. Returns row, column or nil.
function Worksheet:Find(text: string, partial: boolean?): (number?, number?)
	load(self)
	for r = 1, self._lastRow do
		local row = self._rows[r]
		if row then
			for c = 1, self._lastCol do
				if row[c] then
					local s = self:Text(r, c)
					if s == text or (partial and string.find(s, text, 1, true)) then return r, c end
				end
			end
		end
	end
	return nil, nil
end

-- DeleteRows(r1, r2): removes rows r1..r2 (r2 defaults to r1); rows below move up.
function Worksheet:DeleteRows(r1: number, r2: number?)
	local last = r2 or r1
	checkRC(r1, 1); checkRC(last, 1)
	if last < r1 then r1, last = last, r1 end
	load(self)
	local count = last - r1 + 1
	local rows = {}
	for r, row in self._rows do
		if r < r1 then rows[r] = row elseif r > last then rows[r - count] = row end
	end
	self._rows = rows
	local lastRow = 0
	for r in rows do if r > lastRow then lastRow = r end end
	self._lastRow = lastRow
	emit("deleteRows", {sheet = self._order, r1 = r1, r2 = last})
end

function Worksheet:Activate()
	active = self
	emit("activate", {sheet = self._order})
end

-- ── Ranges ──────────────────────────────────────────────────────────────────
local Range = {}
Range.__index = Range

function Worksheet:Range(a: any, b: any?, c: any?, d: any?)
	local r1, c1, r2, c2
	if type(a) == "string" then
		local left, right = string.match(a, "^([^:]+):([^:]+)$")
		r1, c1 = parseAddress(left or a)
		r2, c2 = r1, c1
		if right then r2, c2 = parseAddress(right) end
	else
		r1, c1, r2, c2 = a, b, c or a, d or b
		checkRC(r1, c1); checkRC(r2, c2)
	end
	if r2 < r1 then r1, r2 = r2, r1 end
	if c2 < c1 then c1, c2 = c2, c1 end
	return setmetatable({Sheet = self, Row = r1, Column = c1, Rows = r2 - r1 + 1, Columns = c2 - c1 + 1}, Range)
end

function Worksheet:UsedRange()
	load(self)
	return self:Range(1, 1, math.max(self._lastRow, 1), math.max(self._lastCol, 1))
end

function Range:Values(): {{any}}
	local out = {}
	for i = 1, self.Rows do
		local row = {}
		for j = 1, self.Columns do row[j] = self.Sheet:Cell(self.Row + i - 1, self.Column + j - 1) end
		out[i] = row
	end
	return out
end

function Range:SetValues(values: {{any}})
	for i, row in ipairs(values) do
		for j, v in pairs(row) do
			if type(j) == "number" then self.Sheet:SetCell(self.Row + i - 1, self.Column + j - 1, v) end
		end
	end
end

function Range:Cell(i: number, j: number): any
	return self.Sheet:Cell(self.Row + i - 1, self.Column + j - 1)
end

function Range:Address(): string
	local a = columnLetters(self.Column) .. self.Row
	if self.Rows == 1 and self.Columns == 1 then return a end
	return a .. ":" .. columnLetters(self.Column + self.Columns - 1) .. (self.Row + self.Rows - 1)
end

-- ── The workbook ────────────────────────────────────────────────────────────
local meta = decodeJson(metaJson) or {}
for i, info in ipairs(meta.sheets or {}) do
	local ws = setmetatable({Name = info.name, Index = i, _order = info.order}, Worksheet)
	sheets[i] = ws
	byName[info.name] = ws
	if info.active then active = ws end
end
active = active or sheets[1]

local Sheets = setmetatable({}, {
	__index = function(_, key)
		if type(key) == "number" then return sheets[key] end
		return byName[key]
	end,
	__len = function() return #sheets end,
	__iter = function() return ipairs(sheets) end,
	__newindex = function() error("Use AddSheet(name) to add a sheet", 2) end,
})

local function addSheet(name: string)
	if type(name) ~= "string" or name == "" then error("AddSheet needs a sheet name", 2) end
	if byName[name] then error('A sheet named "' .. name .. '" already exists', 2) end
	-- Luckysheet appends a new sheet, so its position (0-based order) is the count so far.
	local ws = setmetatable({Name = name, Index = #sheets + 1, _order = #sheets, _rows = {}, _lastRow = 0, _lastCol = 0}, Worksheet)
	sheets[#sheets + 1] = ws
	byName[name] = ws
	emit("addSheet", {name = name, sheet = ws._order})
	return ws
end

-- ── Charts (ECharts options, as on the page) ────────────────────────────────
local Charts = table.freeze({
	-- Charts.Add{ option = {...}, title = "...", sheet = ws, anchor = {row = 1, col = 8}, size = {w = 640, h = 380} }
	-- or Charts.Add{ type = "line", range = "A1:C40", title = "..." } for a chart over cells.
	Add = function(def: {[string]: any})
		if type(def) ~= "table" then error("Charts.Add needs a table, e.g. Charts.Add{ option = option }", 2) end
		local sheet = def.sheet or active
		local copy = {}
		for k, v in pairs(def) do if k ~= "sheet" then copy[k] = v end end
		copy.sheet = sheet and sheet._order
		if copy.anchor then copy.anchor = {row = (copy.anchor.row or 1) - 1, col = (copy.anchor.col or 1) - 1, offX = copy.anchor.offX or 8, offY = copy.anchor.offY or 8} end
		emit("chart", copy)
	end,
})

-- ── Origin Studio (opened after the program ends) ───────────────────────────
local OriginStudio = table.freeze({
	OpenGraphEditor = function() emit("origin", {action = "openGraphEditor"}) end,
	OpenOpjuExporter = function() emit("origin", {action = "openOpjuExporter"}) end,
	OpenConductanceWorkbench = function() emit("origin", {action = "openConductanceWorkbench"}) end,
})

-- ── Dialogs ─────────────────────────────────────────────────────────────────
local function InputBox(prompt: string, default: any?): string?
	return ask("input", tostring(prompt or ""), default ~= nil and tostring(default) or "")
end

local function MsgBox(text: any)
	ask("alert", tostring(text), "")
end

local function Confirm(text: any): boolean
	return ask("confirm", tostring(text), "") == "yes"
end

return {
	Sheets = Sheets,
	ActiveSheet = active,
	Sheet = function(key) return Sheets[key] end,
	AddSheet = addSheet,
	Charts = Charts,
	OriginStudio = OriginStudio,
	InputBox = InputBox,
	MsgBox = MsgBox,
	Confirm = Confirm,
	Json = Json,
	FileName = meta.fileName or "",
	ColumnLetters = columnLetters,
	ColumnNumber = columnNumber,
}
