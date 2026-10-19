-- Uppercase First Row: converts the text in row 1 (the headers) to uppercase.
local s = ActiveSheet
local changed = 0
for c = 1, s:LastColumn() do
	local v = s:Cell(1, c)
	if type(v) == "string" and string.upper(v) ~= v then s:SetCell(1, c, string.upper(v)); changed += 1 end
end
print(`Uppercased {changed} header(s).`)
