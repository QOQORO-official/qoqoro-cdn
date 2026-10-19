-- Gas Sensor Summary: finds the Time and R1 columns of the active sheet and
-- reports data quality, the time range, and R1 normalised to its baseline R₀
-- (the median of the points before BASELINE_UNTIL_S, or of the first 30 points).
local BASELINE_UNTIL_S = 100

local function trim(s: string): string
	return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

-- The first row with both a "Time" and an "R1" header; returns row, time column, R1 column.
local function findColumns(sheet)
	for r = 1, sheet:LastRow() do
		local timeCol, r1Col
		for c = 1, sheet:LastColumn() do
			local t = trim(sheet:Text(r, c))
			if t == "Time" then timeCol = c elseif t == "R1" then r1Col = c end
		end
		if timeCol and r1Col then return r, timeCol, r1Col end
	end
	return nil
end

-- Numeric (time, R1) points below the header, sorted by time.
local function readSeries(sheet, headerRow: number, timeCol: number, r1Col: number)
	local pts = {}
	for r = headerRow + 1, sheet:LastRow() do
		local t, v = sheet:Cell(r, timeCol), sheet:Cell(r, r1Col)
		if type(t) == "string" then t = tonumber(trim(t)) end
		if type(v) == "string" then v = tonumber(trim(v)) end
		if type(t) == "number" and type(v) == "number" then table.insert(pts, {t = t, v = v}) end
	end
	table.sort(pts, function(a, b) return a.t < b.t end)
	return pts
end

local function median(values: {number}): number
	local s = table.clone(values)
	table.sort(s)
	local n = #s
	if n == 0 then return 0 / 0 end
	return n % 2 == 1 and s[(n + 1) // 2] or (s[n // 2] + s[n // 2 + 1]) / 2
end

local s = ActiveSheet
local headerRow, timeCol, r1Col = findColumns(s)
if not headerRow then error(`"{s.Name}": no row with both a Time and an R1 header.`) end
local pts = readSeries(s, headerRow, timeCol, r1Col)
local total = s:LastRow() - headerRow
print(`"{s.Name}": header row {headerRow} · Time = {ColumnLetters(timeCol)} · R1 = {ColumnLetters(r1Col)}`)
print(`Data rows: {total} · numeric points: {#pts} · skipped: {total - #pts}`)
if #pts < 2 then error("Not enough numeric points.") end

local span = pts[#pts].t - pts[1].t
print(string.format("Time: %.6g – %.6g s (%.6g s, mean step %.4g s)", pts[1].t, pts[#pts].t, span, span / (#pts - 1)))

local base = {}
for _, p in pts do if p.t < BASELINE_UNTIL_S then table.insert(base, p.v) end end
if #base == 0 then for i = 1, math.min(30, #pts) do base[i] = pts[i].v end end
local R0 = median(base)
local min, max = math.huge, -math.huge
for _, p in pts do min = math.min(min, p.v); max = math.max(max, p.v) end
print(string.format("R1: min %.6g Ω · max %.6g Ω · baseline R₀ %.6g Ω (%d pt)", min, max, R0, #base))
if R0 ~= 0 then
	print(string.format("ΔR/R₀: %.3f %% … %.3f %% · Rmax/R₀ = %.4g", (min - R0) / R0 * 100, (max - R0) / R0 * 100, max / R0))
end
