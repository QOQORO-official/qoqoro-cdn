-- Find & Replace Text: replaces every occurrence of a text in the text cells
-- of the active sheet (plain text, case-sensitive; formulas are left alone).
local s = ActiveSheet
local find = InputBox("Find what?", "")
if find == nil or find == "" then print("Cancelled."); return end
local replace = InputBox(`Replace "{find}" with:`, "")
if replace == nil then print("Cancelled."); return end
local pattern = string.gsub(find, "[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
local safe = string.gsub(replace, "%%", "%%%%")
local cells, total = 0, 0
for r = 1, s:LastRow() do
	for c = 1, s:LastColumn() do
		local v = s:Cell(r, c)
		if type(v) == "string" and s:Formula(r, c) == nil then
			local new, n = string.gsub(v, pattern, safe)
			if n > 0 then s:SetCell(r, c, new); cells += 1; total += n end
		end
	end
end
print(`Replaced {total} occurrence(s) in {cells} cell(s).`)
