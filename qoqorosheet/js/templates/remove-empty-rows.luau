-- Report Empty Rows: lists the completely empty rows inside the used range
-- (nothing is deleted; the "Delete Rows" template removes them).
local s = ActiveSheet
local empty = {}
for r = 1, s:LastRow() do
	local blank = true
	for c = 1, s:LastColumn() do
		if s:Text(r, c) ~= "" or s:Formula(r, c) then blank = false; break end
	end
	if blank then table.insert(empty, r) end
end
if #empty == 0 then print("No empty rows."); return end
print(`{#empty} empty row(s): {table.concat(empty, ", ")}`)
