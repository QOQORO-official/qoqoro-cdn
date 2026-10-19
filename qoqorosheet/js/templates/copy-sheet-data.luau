-- Log All Sheet Names: every sheet with its used size.
for i, sheet in Sheets do
	local mark = sheet == ActiveSheet and "  (active)" or ""
	print(`{i}. {sheet.Name}: {sheet:LastRow()} row(s) × {sheet:LastColumn()} column(s){mark}`)
end
