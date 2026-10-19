-- Detect Exposure Segments: finds gas-exposure segments on the active sheet
-- with one global threshold on the deviation from the baseline:
--   R₀        = median R1 of the first BASELINE_POINTS points
--   deviation = |R1 − R₀| / R₀
--   threshold = max(MIN_THRESHOLD, NOISE_FACTOR × the baseline's median deviation)
-- Runs above the threshold become segments; gaps shorter than MERGE_GAP_S are
-- joined and segments shorter than MIN_LENGTH_S are dropped.
local BASELINE_POINTS = 30
local MIN_THRESHOLD = 0.005 -- 0.5 %
local NOISE_FACTOR = 5
local MERGE_GAP_S = 10
local MIN_LENGTH_S = 10

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
if #pts <= BASELINE_POINTS then error("Not enough numeric points.") end

local base = {}
for i = 1, BASELINE_POINTS do base[i] = pts[i].v end
local R0 = median(base)
if R0 == 0 then error("Baseline R₀ is 0.") end
local noise = {}
for i = 1, BASELINE_POINTS do noise[i] = math.abs(pts[i].v - R0) / R0 end
local threshold = math.max(MIN_THRESHOLD, NOISE_FACTOR * median(noise))

local segments, open = {}, nil
for i, p in pts do
	if math.abs(p.v - R0) / R0 > threshold then
		if not open then open = {from = i, to = i} else open.to = i end
	elseif open then
		table.insert(segments, open); open = nil
	end
end
if open then table.insert(segments, open) end

local merged = {}
for _, seg in segments do
	local last = merged[#merged]
	if last and pts[seg.from].t - pts[last.to].t < MERGE_GAP_S then last.to = seg.to else table.insert(merged, seg) end
end

print(string.format('"%s": R₀ = %.6g Ω · threshold %.3f %%', s.Name, R0, threshold * 100))
local n = 0
for _, seg in merged do
	local t1, t2 = pts[seg.from].t, pts[seg.to].t
	if t2 - t1 >= MIN_LENGTH_S then
		local peak = R0
		for i = seg.from, seg.to do if math.abs(pts[i].v - R0) > math.abs(peak - R0) then peak = pts[i].v end end
		n += 1
		print(string.format("  Segment %d: %.6g – %.6g s (%.4g s) · peak %.6g Ω · ΔR/R₀ %.3f %%", n, t1, t2, t2 - t1, peak, (peak - R0) / R0 * 100))
	end
end
if n == 0 then print("  No exposure segments above the threshold.") end
