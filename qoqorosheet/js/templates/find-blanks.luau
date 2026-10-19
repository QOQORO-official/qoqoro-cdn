-- Find Blank Cells: every empty cell inside the used range of the active sheet.
local s = ActiveSheet
local blanks = {}
for r = 1, s:LastRow() do
	for c = 1, s:LastColumn() do
		if s:Text(r, c) == "" and s:Formula(r, c) == nil then table.insert(blanks, ColumnLetters(c) .. r) end
	end
end
if #blanks == 0 then print("No blank cells in " .. s:UsedRange():Address()); return end
print(`{#blanks} blank cell(s) in {s:UsedRange():Address()}:`)
for i = 1, #blanks, 20 do print(table.concat(blanks, ", ", i, math.min(i + 19, #blanks))) end
