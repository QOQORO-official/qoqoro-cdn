-- Value Frequency Table: how often each distinct value appears on the active
-- sheet, most frequent first (the top 50 are printed).
local s = ActiveSheet
local counts, keys = {}, {}
for r = 1, s:LastRow() do
	for c = 1, s:LastColumn() do
		local text = s:Text(r, c)
		if text ~= "" then
			if not counts[text] then counts[text] = 0; table.insert(keys, text) end
			counts[text] += 1
		end
	end
end
table.sort(keys, function(a, b) return counts[a] > counts[b] or (counts[a] == counts[b] and a < b) end)
print(`{#keys} distinct value(s):`)
for i = 1, math.min(50, #keys) do print(`{counts[keys[i]]}\t{keys[i]}`) end
