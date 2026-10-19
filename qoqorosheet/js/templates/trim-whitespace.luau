-- Trim All Text: removes leading and trailing whitespace from every text cell
-- of the active sheet (formula cells are left alone).
local s = ActiveSheet
local changed = 0
for r = 1, s:LastRow() do
	for c = 1, s:LastColumn() do
		local v = s:Cell(r, c)
		if type(v) == "string" and s:Formula(r, c) == nil then
			local t = string.gsub(v, "^%s*(.-)%s*$", "%1")
			if t ~= v then s:SetCell(r, c, t); changed += 1 end
		end
	end
end
print(`Trimmed {changed} cell(s).`)
