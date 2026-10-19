-- Add Row Numbers: writes 1, 2, 3, … into column A for every filled row.
-- Column A is overwritten, so the program asks first when it holds data.
local s = ActiveSheet
local used = false
for r = 1, s:LastRow() do if s:Text(r, 1) ~= "" then used = true; break end end
if used and not Confirm("Column A already holds data and will be overwritten. Continue?") then print("Cancelled."); return end
local n = 0
for r = 1, s:LastRow() do
	local filled = false
	for c = 2, s:LastColumn() do
		if s:Text(r, c) ~= "" then filled = true; break end
	end
	if filled then n += 1; s:SetCell(r, 1, n) end
end
print(`Numbered {n} row(s).`)
