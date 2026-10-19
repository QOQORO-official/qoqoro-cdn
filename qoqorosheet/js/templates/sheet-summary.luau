-- Sheet Summary: rows, columns and numeric cells of the active sheet, with
-- basic statistics over all numeric cells.
local s = ActiveSheet
local rows, cols = s:LastRow(), s:LastColumn()
local filled, n, sum, min, max = 0, 0, 0, math.huge, -math.huge
for r = 1, rows do
	for c = 1, cols do
		local v = s:Cell(r, c)
		if v ~= nil and v ~= "" then filled += 1 end
		if type(v) == "number" then
			n += 1; sum += v
			min = math.min(min, v); max = math.max(max, v)
		end
	end
end
print(`Sheet "{s.Name}": {rows} row(s) × {cols} column(s), {filled} filled cell(s)`)
if n == 0 then print("No numeric cells."); return end
print(`Numeric cells: {n} · sum {sum} · mean {sum / n} · min {min} · max {max}`)
