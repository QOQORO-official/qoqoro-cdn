-- Cell Type Audit: how many cells in the used range are numbers, text,
-- formulas, true/false and empty.
local s = ActiveSheet
local counts = {number = 0, text = 0, formula = 0, boolean = 0, empty = 0}
for r = 1, s:LastRow() do
	for c = 1, s:LastColumn() do
		local v = s:Cell(r, c)
		if s:Formula(r, c) then counts.formula += 1
		elseif type(v) == "number" then counts.number += 1
		elseif type(v) == "boolean" then counts.boolean += 1
		elseif v == nil or v == "" then counts.empty += 1
		else counts.text += 1 end
	end
end
print(`{s:UsedRange():Address()}: {counts.number} number · {counts.text} text · {counts.formula} formula · {counts.boolean} true/false · {counts.empty} empty`)
