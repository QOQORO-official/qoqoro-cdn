-- Column Statistics: min, max, mean and standard deviation (sample) of every
-- column that holds numbers. Row 1 is taken as the header when it is text.
local s = ActiveSheet
for c = 1, s:LastColumn() do
	local values = {}
	for r = 1, s:LastRow() do
		local v = s:Cell(r, c)
		if type(v) == "number" then table.insert(values, v) end
	end
	if #values > 0 then
		local sum, min, max = 0, math.huge, -math.huge
		for _, v in values do sum += v; min = math.min(min, v); max = math.max(max, v) end
		local mean, sq = sum / #values, 0
		for _, v in values do sq += (v - mean) ^ 2 end
		local sd = #values > 1 and math.sqrt(sq / (#values - 1)) or 0
		local head = s:Text(1, c)
		local name = (head ~= "" and type(s:Cell(1, c)) ~= "number") and `{ColumnLetters(c)} ({head})` or ColumnLetters(c)
		print(string.format("%s: n=%d  min=%.6g  max=%.6g  mean=%.6g  sd=%.6g", name, #values, min, max, mean, sd))
	end
end
