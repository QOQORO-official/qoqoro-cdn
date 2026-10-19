-- Cleanup CSV/XLSX: tidies an imported sheet in one pass —
--   1. trims whitespace around text,
--   2. turns numbers stored as text into numbers,
--   3. deletes completely empty rows.
local s = ActiveSheet
if not Confirm(`Clean up "{s.Name}"? (trim text, parse numbers, delete empty rows)`) then print("Cancelled."); return end
local trimmed, parsed = 0, 0
for r = 1, s:LastRow() do
	for c = 1, s:LastColumn() do
		local v = s:Cell(r, c)
		if type(v) == "string" and s:Formula(r, c) == nil then
			local t = string.gsub(v, "^%s*(.-)%s*$", "%1")
			local n = t ~= "" and tonumber(t)
			if n and n == n and math.abs(n) ~= math.huge then s:SetCell(r, c, n); parsed += 1
			elseif t ~= v then s:SetCell(r, c, t); trimmed += 1 end
		end
	end
end
local function empty(r: number): boolean
	for c = 1, s:LastColumn() do
		if s:Text(r, c) ~= "" or s:Formula(r, c) then return false end
	end
	return true
end
local deleted, r = 0, s:LastRow()
while r >= 1 do
	if empty(r) then
		local top = r
		while top > 1 and empty(top - 1) do top -= 1 end
		s:DeleteRows(top, r)
		deleted += r - top + 1
		r = top - 1
	else
		r -= 1
	end
end
print(`Trimmed {trimmed} cell(s), parsed {parsed} number(s), deleted {deleted} empty row(s).`)
