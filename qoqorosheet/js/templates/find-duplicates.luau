-- Find Duplicates: values that occur more than once on the active sheet, with
-- the addresses of every occurrence.
local s = ActiveSheet
local seen, order = {}, {}
for r = 1, s:LastRow() do
	for c = 1, s:LastColumn() do
		local text = s:Text(r, c)
		if text ~= "" then
			if not seen[text] then seen[text] = {}; table.insert(order, text) end
			table.insert(seen[text], ColumnLetters(c) .. r)
		end
	end
end
local found = 0
for _, text in order do
	local where = seen[text]
	if #where > 1 then
		found += 1
		print(`"{text}" ×{#where}: {table.concat(where, ", ")}`)
	end
end
print(found == 0 and "No duplicate values." or `{found} duplicated value(s).`)
