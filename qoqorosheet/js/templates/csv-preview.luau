-- Preview as CSV: the first 10 rows of the active sheet as comma-separated text.
local s = ActiveSheet
local function field(text: string): string
	if string.find(text, '[,"\n]') then return '"' .. string.gsub(text, '"', '""') .. '"' end
	return text
end
for r = 1, math.min(10, s:LastRow()) do
	local cells = {}
	for c = 1, s:LastColumn() do cells[c] = field(s:Text(r, c)) end
	print(table.concat(cells, ","))
end
