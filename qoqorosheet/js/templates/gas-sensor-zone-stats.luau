-- PPM Zone Statistics: reads PPM zones from a sheet named "ranges" (as written
-- by the Python XLSX export: a header row with start and end columns, and
-- optionally a label/PPM column) and computes, per zone, on the active sheet:
--   R₀    = median R1 in the BASELINE_WINDOW_S seconds before the zone starts
--   peak  = the R1 furthest from R₀ inside the zone
--   ratio = peak / R₀
--   T90   = seconds from the zone start until R1 first covers 90 % of the change
local BASELINE_WINDOW_S = 20

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

local ranges = Sheets["ranges"] or Sheets["Ranges"]
if not ranges then error('No sheet named "ranges" with the PPM zones.') end
local data = ActiveSheet
if data == ranges then
	local list = {}
	for i, sh in Sheets do table.insert(list, i .. ". " .. sh.Name) end
	local answer = InputBox("Which sheet holds the sensor data?\n" .. table.concat(list, "\n"), "1")
	if answer == nil then print("Cancelled."); return end
	data = Sheets[tonumber(answer) or 0]
	if not data or data == ranges then error("Pick a data sheet other than \"ranges\".") end
end

-- The zone table: the first row naming a start and an end column.
local START = {start = true, xmin = true, from = true, ["start (s)"] = true}
local FINISH = {["end"] = true, xmax = true, to = true, stop = true, ["end (s)"] = true}
local LABEL = {label = true, ppm = true, zone = true, name = true, concentration = true}
local zoneRow, startCol, endCol, labelCol
for r = 1, ranges:LastRow() do
	local sc, ec, lc
	for c = 1, ranges:LastColumn() do
		local h = string.lower(trim(ranges:Text(r, c)))
		if START[h] then sc = c elseif FINISH[h] then ec = c elseif LABEL[h] then lc = c end
	end
	if sc and ec then zoneRow, startCol, endCol, labelCol = r, sc, ec, lc; break end
end
if not zoneRow then error('"ranges" has no header row with start and end columns.') end

local headerRow, timeCol, r1Col = findColumns(data)
if not headerRow then error(`"{data.Name}": no row with both a Time and an R1 header.`) end
local pts = readSeries(data, headerRow, timeCol, r1Col)
print(`Zones from "ranges", data from "{data.Name}" ({#pts} points):`)

local count = 0
for r = zoneRow + 1, ranges:LastRow() do
	local t1, t2 = tonumber(ranges:Cell(r, startCol)), tonumber(ranges:Cell(r, endCol))
	if t1 and t2 then
		count += 1
		local label = labelCol and ranges:Text(r, labelCol) or `Zone {count}`
		local base, peak = {}, nil
		for _, p in pts do
			if p.t >= t1 - BASELINE_WINDOW_S and p.t < t1 then table.insert(base, p.v) end
		end
		local R0 = median(base)
		for _, p in pts do
			if p.t >= t1 and p.t <= t2 and (peak == nil or math.abs(p.v - R0) > math.abs(peak - R0)) then peak = p.v end
		end
		if #base == 0 or peak == nil then
			print(`  {label}: no data in the baseline window or the zone — skipped.`)
		else
			local target, t90 = R0 + 0.9 * (peak - R0), nil
			for _, p in pts do
				if p.t >= t1 and p.t <= t2 and ((peak >= R0 and p.v >= target) or (peak < R0 and p.v <= target)) then t90 = p.t - t1; break end
			end
			print(string.format("  %s: %.6g – %.6g s · R₀ %.6g Ω · peak %.6g Ω · ratio %.4g · T90 %s",
				label, t1, t2, R0, peak, peak / R0, t90 and string.format("%.4g s", t90) or "n/a"))
		end
	end
end
if count == 0 then print("  No zones found below the header row.") end
