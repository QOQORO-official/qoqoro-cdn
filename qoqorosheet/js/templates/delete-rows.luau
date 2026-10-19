-- Delete Rows: removes every completely empty row inside the used range of
-- the active sheet; the rows below move up.
local s = ActiveSheet
local function empty(r: number): boolean
	for c = 1, s:LastColumn() do
		if s:Text(r, c) ~= "" or s:Formula(r, c) then return false end
	end
	return true
end
local deleted, r = 0, s:LastRow()
-- Bottom-up, one block of consecutive empty rows at a time.
while r >= 1 do
	if empty(r) then
		local top = r
		while top > 1 and empty(top - 1) do top -= 1 end
		s:DeleteRows(top, r)
		deleted += r - top + 1
		r = top - 1
	else
		r -= 1
	end
end
print(`Deleted {deleted} empty row(s).`)
