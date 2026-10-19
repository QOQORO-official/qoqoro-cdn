-- ── PPM Gas Sensor — Normalized Response Chart (ECharts) ──────────────────
-- For each selected sheet it plots the normalized sensor response
--
--        ΔR/R₀ (%) = (R1 − R₀) / R₀ × 100
--
-- where R₀ is that sheet's own baseline (mean of pre-exposure points), with
-- noise/time cropping and shaded PPM exposure zones (an ECharts markArea).

local SERIES_COLORS = {
	"#E63946", "#457B9D", "#2A9D8F", "#E9C46A", "#F4A261",
	"#6A4C93", "#06D6A0", "#118AB2", "#FF6B6B", "#8338EC",
}
local BASELINE_FALLBACK_N = 30

-- ── PPM exposure zones (raw seconds) ──────────────────────────────────────
local function defaultPpmZones(startZone: number)
	local zones = {}
	local ppmSteps = {100, 300, 500, 1000, 1500, 5000}
	local s, e, i = startZone, startZone + 200, 1
	while s <= 3000 and i <= #ppmSteps do
		table.insert(zones, {xMin = s, xMax = math.min(e, 3000), label = ppmSteps[i] .. " PPM"})
		s += 400; e += 400; i += 1
	end
	return zones
end

-- The row holding both "Time" and "DataName"; its header names → columns.
local function analyzeHeader(sheet)
	for r = 1, sheet:LastRow() do
		local hasTime, hasName = false, false
		for c = 1, sheet:LastColumn() do
			local s = string.gsub(sheet:Text(r, c), "^%s*(.-)%s*$", "%1")
			if s == "Time" then hasTime = true elseif s == "DataName" then hasName = true end
		end
		if hasTime and hasName then
			local colMap = {}
			for c = 1, sheet:LastColumn() do
				local s = string.gsub(sheet:Text(r, c), "^%s*(.-)%s*$", "%1")
				if s ~= "" then colMap[s] = c end
			end
			return r, colMap
		end
	end
	return nil, nil
end

local function trim(s: string): string
	return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

-- ── Sheet selection ───────────────────────────────────────────────────────
if #Sheets == 0 then error("No sheets found.") end
local list = {}
for i, sheet in Sheets do table.insert(list, i .. ". " .. sheet.Name) end
local userInput = InputBox("Available sheets:\n" .. table.concat(list, "\n") ..
	"\n\nEnter sheet numbers to compare (comma-separated), e.g. 1,3,5\nLeave blank to include ALL sheets:", "")
if userInput == nil then print("Cancelled."); return end

local selected = {}
if trim(userInput) == "" then
	for _, sheet in Sheets do table.insert(selected, sheet) end
else
	local seen, bad = {}, {}
	for part in string.gmatch(userInput, "[^,]+") do
		local n = tonumber(trim(part))
		if not n or n ~= math.floor(n) or n < 1 or n > #Sheets then
			table.insert(bad, trim(part))
		elseif not seen[n] then
			seen[n] = true
			table.insert(selected, Sheets[n])
		end
	end
	if #bad > 0 then error("Invalid sheet number(s): " .. table.concat(bad, ", ")) end
end
if #selected == 0 then error("No sheets selected.") end

-- ── Phase / cropping prompts ──────────────────────────────────────────────
local phaseInput = InputBox("Total initial phase before 100 PPM gas starts (seconds).\n" ..
	"e.g. enter 100 → 50 s baseline kept after noise cutoff.", "100")
if phaseInput == nil then print("Cancelled."); return end
local startZone = tonumber(trim(phaseInput)) or 100
if startZone == 0 then startZone = 100 end
local timeCutoffLow = math.max(0, startZone - 50)
local BASELINE_TIME_MAX = startZone

local maxTimeInput = InputBox("Maximum time to include (raw seconds, before X shift).\n" ..
	"Data beyond this is cropped. Blank/0 = keep all.", "")
if maxTimeInput == nil then print("Cancelled."); return end
local maxRaw = tonumber(trim(maxTimeInput))
local timeCutoffHigh = (maxRaw and maxRaw > 0) and maxRaw or math.huge

print(string.format("✔ Phase %ss · noise cutoff %ss · %s", tostring(startZone), tostring(timeCutoffLow),
	timeCutoffHigh == math.huge and "no max cutoff" or ("max " .. tostring(timeCutoffHigh) .. "s")))

-- ── Extract + normalize each sheet ────────────────────────────────────────
local seriesList = {} -- { name, points = {{t, normPct}, ...} }
local firstTimeVal: number? = nil

for _, sheet in selected do
	if sheet:LastRow() == 0 then
		warn(`"{sheet.Name}": empty — skip.`)
		continue
	end
	local headerRow, colMap = analyzeHeader(sheet)
	if not headerRow then
		warn(`"{sheet.Name}": no Time/DataName header — skip.`)
		continue
	end
	local timeCol, r1Col = colMap["Time"], colMap["R1"]
	if not timeCol or not r1Col then
		warn(`"{sheet.Name}": missing Time/R1 — skip.`)
		continue
	end

	-- Rows kept after cropping, sorted by time.
	local rows = {}
	for r = headerRow + 1, sheet:LastRow() do
		local t, v = tonumber(sheet:Cell(r, timeCol)), sheet:Cell(r, r1Col)
		if t and v ~= nil and t > timeCutoffLow and t <= timeCutoffHigh then
			table.insert(rows, {t = t, v = tonumber(v)})
		end
	end
	table.sort(rows, function(a, b) return a.t < b.t end)
	if #rows == 0 then
		warn(`"{sheet.Name}": no data after cropping — skip.`)
		continue
	end

	-- Baseline R₀ = mean of pre-exposure points (or the first N as a fallback).
	local base = {}
	for _, row in rows do if row.t < BASELINE_TIME_MAX then table.insert(base, row) end end
	if #base == 0 then for i = 1, math.min(BASELINE_FALLBACK_N, #rows) do base[i] = rows[i] end end
	local sum, n = 0, 0
	for _, row in base do if row.v then sum += row.v; n += 1 end end
	local R0 = n > 0 and sum / n or 0 / 0
	if not (R0 > 0) then
		warn(`"{sheet.Name}": invalid baseline R₀ — skip.`)
		continue
	end

	if firstTimeVal == nil then firstTimeVal = rows[1].t end
	local points = {}
	for _, row in rows do
		if row.v then table.insert(points, {math.round(row.t - firstTimeVal), (row.v - R0) / R0 * 100}) end
	end
	table.insert(seriesList, {name = sheet.Name, points = points})
	print(string.format('  ✔ "%s": %d pts, R₀ = %.1f Ω (%d baseline pt).', sheet.Name, #points, R0, n))
end

if #seriesList == 0 then error("No valid R1 data in the selected sheets.") end
local first = firstTimeVal :: number

-- ── PPM zones → ECharts markArea (shifted to start at 0) ──────────────────
local shiftedMax = timeCutoffHigh == math.huge and math.huge or math.round(timeCutoffHigh - first)
local markAreaData = {}
for _, z in defaultPpmZones(startZone) do
	local xMin, xMax = math.round(z.xMin - first), math.round(z.xMax - first)
	if xMax > 0 and xMin < shiftedMax then
		table.insert(markAreaData, {
			{xAxis = xMin, itemStyle = {color = "rgba(120,120,120,0.12)"},
				label = {show = true, formatter = z.label, position = "insideTop", fontSize = 10, color = "#666"}},
			{xAxis = xMax},
		})
	end
end

-- ── ECharts option ────────────────────────────────────────────────────────
local CHART_TITLE = "H₂ Gas Sensor — Normalized Response (ΔR/R₀)"
local colors, names, series = {}, {}, {}
for i, s in seriesList do
	if i <= #SERIES_COLORS then colors[i] = SERIES_COLORS[i] end -- ECharts cycles them itself
	names[i] = s.name
	local item = {
		name = s.name, type = "line",
		showSymbol = false,  -- dense traces render fast without symbols
		sampling = "lttb",   -- downsample large point counts
		lineStyle = {width = 1.5},
		data = s.points,
	}
	if i == 1 and #markAreaData > 0 then item.markArea = {silent = true, data = markAreaData} end
	series[i] = item
end

Charts.Add{
	title = CHART_TITLE,
	size = {w = 900, h = 500},
	option = {
		color = colors,
		title = {text = CHART_TITLE, left = "center", textStyle = {fontSize = 14, fontWeight = "bold"}},
		tooltip = {trigger = "axis"},
		legend = {type = "scroll", data = names},
		xAxis = {type = "value", name = "Time (s)", nameLocation = "middle", nameGap = 26},
		yAxis = {type = "value", name = "ΔR/R₀ (%)", axisLabel = {formatter = "{value} %"}},
		animation = false,
		series = series,
	},
}

print(`✔ Chart added: {#seriesList} normalized series. Use the ✎ Format pane to set legend position, axis titles and Y range.`)
