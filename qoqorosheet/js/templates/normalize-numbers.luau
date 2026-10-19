-- Parse Text Numbers: cells that hold a number stored as text ("  12.5",
-- "1e-6", "1,234") become real numbers.
local s = ActiveSheet
local changed = 0
for r = 1, s:LastRow() do
	for c = 1, s:LastColumn() do
		local v = s:Cell(r, c)
		if type(v) == "string" and s:Formula(r, c) == nil then
			local text = string.gsub(string.gsub(v, "^%s*(.-)%s*$", "%1"), ",", "")
			local n = tonumber(text)
			if n and text ~= "" and n == n and math.abs(n) ~= math.huge then s:SetCell(r, c, n); changed += 1 end
		end
	end
end
print(`Converted {changed} cell(s) to numbers.`)
