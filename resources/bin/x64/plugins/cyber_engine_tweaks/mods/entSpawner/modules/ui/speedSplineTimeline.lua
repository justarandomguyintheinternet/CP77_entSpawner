local style = require("modules/ui/style")
local settings = require("modules/utils/core/settings")
local history = require("modules/utils/project/history")
local input = require("modules/utils/core/input")

local wu

---A spatial timeline for a single Speed Spline node. The horizontal axis is distance along the
---spline (meters), not time. It exposes three tracks (speed ranges, rotation points, ground-snap
---points) that can be dragged, resized and reordered, plus a scrubber that mirrors the cursor
---position onto the spline in the world (showing the interpolated speed there).
---@class speedSplineTimelineDrag
---@field active boolean
---@field track string?
---@field index number
---@field mode string
---@field startMouseX number
---@field baseStart number
---@field baseEnd number
---@field leftBound number
---@field rightBound number
---@field historyAdded boolean
---@field changed boolean

---@class speedSplineTimeline
---@field open boolean
---@field spline table?
---@field spawnedUI table?
---@field zoom number
---@field snapEnabled boolean
---@field snapMeters number
---@field dockWasBottom boolean
---@field selected table
---@field drag speedSplineTimelineDrag
local speedSplineTimeline = {
    open = false,
    spline = nil,
    spawnedUI = nil,
    zoom = 12, -- pixels per meter
    snapEnabled = true,
    snapMeters = 0.5,
    dockWasBottom = false,
    selected = { track = nil, index = 0 },
    contextTrack = nil,   -- track key captured when the lane "add event" menu opens
    contextDistance = 0,  -- distance (m) captured for the lane "add event" menu
    drag = {
        active = false,
        track = nil,
        index = 0,
        mode = "move",
        startMouseX = 0,
        baseStart = 0,
        baseEnd = 0,
        leftBound = 0,
        rightBound = 0,
        historyAdded = false,
        changed = false
    }
}

-- Layout metrics (unscaled; multiplied by style.viewSize at draw time).
local layout = {
    trackHeight = 30,
    trackGap = 10,
    headerHeight = 24,
    labelWidth = 132,
    editorHeight = 40 -- one inline properties row
}

local timelineDockButtonHovered = false
local timelineCloseButtonHovered = false

---@param r number
---@param g number
---@param b number
---@param a number?
---@return integer
local function rgba(r, g, b, a)
    return (a or 255) * 0x1000000 + b * 0x10000 + g * 0x100 + r
end

-- Track definitions, matching the on-screen marker semantics of the spline overlay.
local trackDefs = {
    { key = "speed",      label = "Speed Control", color = rgba(95, 210, 95),  kind = "range" },
    { key = "rotation",   label = "Rotation",      color = rgba(245, 165, 45), kind = "point" },
    { key = "groundSnap", label = "Ground Snap",   color = rgba(70, 190, 235), kind = "point" }
}

local overlapColor = rgba(220, 80, 80)
local scrubColor = rgba(0, 214, 255)
local selectedBorderColor = 0xFF00D6FF

---@param value number
---@param minValue number
---@param maxValue number
---@return number
local function clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(value, maxValue))
end

---@param color integer
---@param alpha number
---@return integer
local function withAlpha(color, alpha)
    local rgb = (tonumber(color) or 0) % 0x1000000
    return clamp(math.floor(alpha), 0, 255) * 0x1000000 + rgb
end

---@param value number
---@return number
local function snapValue(value)
    if not speedSplineTimeline.snapEnabled then
        return value
    end
    local snap = math.max(0.01, tonumber(speedSplineTimeline.snapMeters) or 0.5)
    return math.floor((value / snap) + 0.5) * snap
end

---@param meters number
---@return string
local function formatMeters(meters)
    return string.format("%.1f m", meters)
end

---@param text string
---@param maxWidth number
---@param fontScale number
---@return string
local function fitText(text, maxWidth, fontScale)
    maxWidth = math.max(1, maxWidth)
    if ImGui.CalcTextSize(text) * fontScale <= maxWidth then
        return text
    end
    local ellipsis = "..."
    local trimmed = text
    while #trimmed > 0 and ImGui.CalcTextSize(trimmed .. ellipsis) * fontScale > maxWidth do
        trimmed = trimmed:sub(1, #trimmed - 1)
    end
    if #trimmed == 0 then
        return ""
    end
    return trimmed .. ellipsis
end

---@param zoom number
---@return number
local function getTickStep(zoom)
    local desired = 90 / math.max(zoom, 0.0001) -- meters per ~90 px
    local steps = { 0.5, 1, 2, 5, 10, 20, 50, 100, 200, 500, 1000 }
    for _, step in ipairs(steps) do
        if step >= desired then
            return step
        end
    end
    return steps[#steps]
end

---Returns the bound timeline spline when it is still valid.
---@return table?
local function getSpline()
    local sp = speedSplineTimeline.spline
    if sp and sp.object and sp.node == "worldSpeedSplineNode" then
        return sp
    end
    return nil
end

---Furthest meaningful distance the canvas needs to cover.
---@param spline table
---@return number
local function getContentLength(spline)
    local maxPos = spline:getTotalLength() or 0
    for _, section in ipairs(spline.speedChangeSections) do
        maxPos = math.max(maxPos, section.start, section.endPos)
    end
    for _, section in ipairs(spline.orientationChangeSections) do
        maxPos = math.max(maxPos, section.pos)
    end
    for _, section in ipairs(spline.roadAdjustmentFactorChangeSections) do
        maxPos = math.max(maxPos, section.pos)
    end
    return math.max(1, maxPos)
end

---@param track string
---@param index number
local function selectEvent(track, index)
    speedSplineTimeline.selected.track = track
    speedSplineTimeline.selected.index = index
end

---@param track string
---@param index number
---@return boolean
local function isSelected(track, index)
    return speedSplineTimeline.selected.track == track and speedSplineTimeline.selected.index == index
end

local function saveSettings()
    settings.speedTimelineZoom = speedSplineTimeline.zoom
    settings.speedTimelineSnapEnabled = speedSplineTimeline.snapEnabled
    settings.speedTimelineSnapMeters = speedSplineTimeline.snapMeters
    settings.save()
end

local function loadSettings()
    speedSplineTimeline.zoom = clamp(tonumber(settings.speedTimelineZoom) or speedSplineTimeline.zoom, 2, 200)
    speedSplineTimeline.snapEnabled = settings.speedTimelineSnapEnabled ~= false
    speedSplineTimeline.snapMeters = clamp(tonumber(settings.speedTimelineSnapMeters) or speedSplineTimeline.snapMeters, 0.01, 100)
end

local function endDrag()
    local drag = speedSplineTimeline.drag
    drag.active = false
    drag.track = nil
    drag.index = 0
    drag.mode = "move"
    drag.historyAdded = false
    drag.changed = false
end

---Left/right meter bounds a speed range may occupy without overlapping its neighbours.
---Other ranges are treated as fixed for the duration of the drag.
---@param spline table
---@param index number
---@return number left
---@return number right
local function computeSpeedBounds(spline, index)
    local section = spline.speedChangeSections[index]
    local lo = math.min(section.start, section.endPos)
    local hi = math.max(section.start, section.endPos)
    local left = 0
    local right = spline:getMaxPosition()

    for i, other in ipairs(spline.speedChangeSections) do
        if i ~= index then
            local otherLo = math.min(other.start, other.endPos)
            local otherHi = math.max(other.start, other.endPos)
            if otherHi <= lo then
                left = math.max(left, otherHi)
            elseif otherLo >= hi then
                right = math.min(right, otherLo)
            end
        end
    end

    return left, right
end

---Left-edge position closest to `desiredLo` where a width-`width` range fits without overlapping
---any OTHER range, so a moved range can slot into any big-enough gap (reordering past others).
---Returns nil when no gap is wide enough (the range should then stay put).
---@param spline table
---@param index number
---@param desiredLo number
---@param width number
---@return number?
local function computeSpeedSlot(spline, index, desiredLo, width)
    local maxPos = spline:getMaxPosition()

    -- Occupied intervals from the other ranges, clamped to [0, maxPos] and sorted.
    local occupied = {}
    for i, other in ipairs(spline.speedChangeSections) do
        if i ~= index then
            local lo = clamp(math.min(other.start, other.endPos), 0, maxPos)
            local hi = clamp(math.max(other.start, other.endPos), 0, maxPos)
            if hi > lo then
                table.insert(occupied, { lo = lo, hi = hi })
            end
        end
    end
    table.sort(occupied, function(a, b) return a.lo < b.lo end)

    -- Merge overlapping/adjacent occupied intervals (tolerates pre-existing overlaps in the data).
    local merged = {}
    for _, iv in ipairs(occupied) do
        local last = merged[#merged]
        if last and iv.lo <= last.hi + 1e-6 then
            last.hi = math.max(last.hi, iv.hi)
        else
            table.insert(merged, { lo = iv.lo, hi = iv.hi })
        end
    end

    -- Walk the free gaps between occupied intervals; pick the valid x closest to desiredLo.
    local bestX, bestDist = nil, math.huge
    local function consider(gapLo, gapHi)
        if gapHi - gapLo >= width - 1e-6 then
            local x = clamp(desiredLo, gapLo, gapHi - width)
            local dist = math.abs(x - desiredLo)
            if dist < bestDist then
                bestDist = dist
                bestX = x
            end
        end
    end

    local cursor = 0
    for _, iv in ipairs(merged) do
        consider(cursor, iv.lo)
        cursor = math.max(cursor, iv.hi)
    end
    consider(cursor, maxPos)

    return bestX
end

---@param track string
---@param index number
---@param mode string
---@param mouseX number
local function beginDrag(track, index, mode, mouseX)
    local spline = getSpline()
    if not spline then return end

    local drag = speedSplineTimeline.drag
    drag.active = true
    drag.track = track
    drag.index = index
    drag.mode = mode
    drag.startMouseX = mouseX
    drag.historyAdded = false
    drag.changed = false

    if track == "speed" then
        local section = spline.speedChangeSections[index]
        drag.baseStart = math.min(section.start, section.endPos)
        drag.baseEnd = math.max(section.start, section.endPos)
        drag.leftBound, drag.rightBound = computeSpeedBounds(spline, index)
    elseif track == "rotation" then
        drag.baseStart = spline.orientationChangeSections[index].pos
    elseif track == "groundSnap" then
        drag.baseStart = spline.roadAdjustmentFactorChangeSections[index].pos
    end
end

---@param spline table
---@param applyFn function
local function applyChange(spline, applyFn)
    local drag = speedSplineTimeline.drag
    if not drag.historyAdded then
        history.addAction(history.getElementChange(spline.object))
        drag.historyAdded = true
    end
    applyFn()
    drag.changed = true
end

local function updateDrag()
    local drag = speedSplineTimeline.drag
    if not drag.active then return end

    local spline = getSpline()
    if not spline then endDrag(); return end

    if not ImGui.IsMouseDown(ImGuiMouseButton.Left) then
        if drag.changed and drag.track == "rotation" then
            spline:updateCurvePreview()
        end
        endDrag()
        return
    end

    local mouseX = select(1, ImGui.GetMousePos())
    local deltaMeters = (mouseX - drag.startMouseX) / math.max(speedSplineTimeline.zoom, 0.0001)

    if drag.track == "speed" then
        local section = spline.speedChangeSections[drag.index]
        if not section then endDrag(); return end

        local width = drag.baseEnd - drag.baseStart
        local newLo, newHi
        if drag.mode == "resizeLeft" then
            newLo = clamp(snapValue(drag.baseStart + deltaMeters), drag.leftBound, drag.baseEnd)
            newHi = drag.baseEnd
        elseif drag.mode == "resizeRight" then
            newLo = drag.baseStart
            newHi = clamp(snapValue(drag.baseEnd + deltaMeters), drag.baseStart, drag.rightBound)
        else
            -- Move: slot into whichever free gap is closest, allowing the range to reorder past
            -- others. Keeps its current spot if nothing else fits.
            local desiredLo = snapValue(drag.baseStart + deltaMeters)
            newLo = computeSpeedSlot(spline, drag.index, desiredLo, width) or math.min(section.start, section.endPos)
            newHi = newLo + width
        end

        if math.abs(section.start - newLo) > 1e-6 or math.abs(section.endPos - newHi) > 1e-6 then
            applyChange(spline, function()
                section.start = newLo
                section.endPos = newHi
            end)
        end
    elseif drag.track == "rotation" or drag.track == "groundSnap" then
        local sections = drag.track == "rotation" and spline.orientationChangeSections or spline.roadAdjustmentFactorChangeSections
        local section = sections[drag.index]
        if not section then endDrag(); return end

        local newPos = clamp(snapValue(drag.baseStart + deltaMeters), 0, spline:getMaxPosition())
        if math.abs(section.pos - newPos) > 1e-6 then
            applyChange(spline, function()
                section.pos = newPos
            end)
            if drag.track == "rotation" then
                spline:updateCurvePreview()
            end
        end
    end
end

---Adds a new event of the given track at a distance (m), records history, and selects it.
---@param spline table
---@param track string
---@param distance number
local function addEventAt(spline, track, distance)
    local maxPos = spline:getMaxPosition()
    distance = clamp(distance, 0, maxPos)
    local newIndex
    if track == "speed" then
        newIndex = spline:addSpeedSection(distance, math.min(distance + 5, maxPos), 10)
    elseif track == "rotation" then
        newIndex = spline:addOrientationPoint(distance)
    elseif track == "groundSnap" then
        newIndex = spline:addRoadPoint(distance, 1)
    end
    if newIndex then
        selectEvent(track, newIndex)
    end
end

---Deletes a timeline event and keeps the current selection consistent with the shifted indices.
---@param spline table
---@param track string
---@param index number
local function deleteTimelineEvent(spline, track, index)
    if not spline:removeTimelineEvent(track, index) then return end
    local selected = speedSplineTimeline.selected
    if selected.track == track then
        if selected.index == index then
            selected.track = nil
            selected.index = 0
        elseif selected.index > index then
            selected.index = selected.index - 1
        end
    end
end

---Readout shown in a tooltip while an event is being moved or resized. For a speed range it shows
---the moving edge (resize) or both ends (move); for a point it shows its position.
---@param spline table
---@param drag speedSplineTimelineDrag
---@return string?
local function dragReadout(spline, drag)
    if drag.track == "speed" then
        local section = spline.speedChangeSections[drag.index]
        if not section then return nil end
        local lo = math.min(section.start, section.endPos)
        local hi = math.max(section.start, section.endPos)
        if drag.mode == "resizeLeft" then
            return string.format("Start: %s", formatMeters(lo))
        elseif drag.mode == "resizeRight" then
            return string.format("End: %s", formatMeters(hi))
        end
        return string.format("Start: %s   End: %s", formatMeters(lo), formatMeters(hi))
    elseif drag.track == "rotation" or drag.track == "groundSnap" then
        local sections = drag.track == "rotation" and spline.orientationChangeSections or spline.roadAdjustmentFactorChangeSections
        local section = sections[drag.index]
        if not section then return nil end
        return string.format("Position: %s", formatMeters(section.pos))
    end
    return nil
end

---Draws a filled diamond marker centred on (cx, cy).
---@param drawList table
---@param cx number
---@param cy number
---@param radius number
---@param fill integer
---@param border integer
local function drawDiamond(drawList, cx, cy, radius, fill, border)
    ImGui.ImDrawListAddQuadFilled(drawList, cx, cy - radius, cx + radius, cy, cx, cy + radius, cx - radius, cy, fill)
    ImGui.ImDrawListAddLine(drawList, cx, cy - radius, cx + radius, cy, border, 1)
    ImGui.ImDrawListAddLine(drawList, cx + radius, cy, cx, cy + radius, border, 1)
    ImGui.ImDrawListAddLine(drawList, cx, cy + radius, cx - radius, cy, border, 1)
    ImGui.ImDrawListAddLine(drawList, cx - radius, cy, cx, cy - radius, border, 1)
end

---Draws the scrolling canvas: ruler, tracks and events. Sets the spline scrubber when the
---cursor hovers the speed lane.
---@param spline table
local function drawCanvas(spline)
    -- Refresh the cached max position once per frame; drag/add/editor position clamps read the cache.
    spline:refreshMaxPosition()

    local vs = style.viewSize
    local zoom = speedSplineTimeline.zoom
    local contentLength = getContentLength(spline)
    local displayLength = contentLength + math.max(2, speedSplineTimeline.snapMeters * 4)

    -- Header controls -------------------------------------------------------
    style.mutedText(string.format("Spline: %s", spline.object and spline.object.name or "?"))
    ImGui.SameLine()
    style.mutedText(string.format("| Length: %s", formatMeters(spline:getTotalLength() or 0)))

    ImGui.SameLine()
    ImGui.Dummy(8 * style.viewSize, 0)
    ImGui.SameLine()
    local snapEnabled, snapChanged = ImGui.Checkbox("Snap##speedTimelineSnap", speedSplineTimeline.snapEnabled)
    if snapChanged then
        speedSplineTimeline.snapEnabled = snapEnabled
        saveSettings()
    end

    ImGui.SameLine()
    ImGui.BeginDisabled(not speedSplineTimeline.snapEnabled)
    ImGui.SetNextItemWidth(80 * vs)
    local newSnap, snapValueChanged = ImGui.InputFloat("##speedTimelineSnapMeters", speedSplineTimeline.snapMeters, 0, 0, "%.2f m")
    if snapValueChanged then
        speedSplineTimeline.snapMeters = clamp(tonumber(newSnap) or speedSplineTimeline.snapMeters, 0.01, 100)
        saveSettings()
    end
    ImGui.EndDisabled()

    ImGui.SameLine()
    ImGui.Dummy(8 * style.viewSize, 0)
    ImGui.SameLine()
    ImGui.SetNextItemWidth(100 * vs)
    local newZoom, zoomChanged = ImGui.DragFloat("Zoom##speedTimelineZoom", speedSplineTimeline.zoom, 0.2, 2, 200, "%.1f px/m")
    if zoomChanged then
        speedSplineTimeline.zoom = clamp(tonumber(newZoom) or speedSplineTimeline.zoom, 2, 200)
        saveSettings()
    end

    ImGui.SameLine()
    if ImGui.Button("Fit") then
        -- Base "fit" on the window width; the canvas child spans it minus the window padding, the
        -- label gutter, the canvas right padding and the vertical scrollbar (reserved so the fitted
        -- content never overflows into a horizontal scrollbar when a vertical one is present).
        local winWidth = ImGui.GetWindowSize()
        local pad = ImGui.GetStyle().WindowPadding.x
        local scrollbar = ImGui.GetStyle().ScrollbarSize
        local usable = winWidth - (2 * pad) - scrollbar - (layout.labelWidth * vs) - (60 * vs)
        if usable > 20 and displayLength > 0 then
            speedSplineTimeline.zoom = clamp(usable / displayLength, 2, 200)
            zoom = speedSplineTimeline.zoom
            saveSettings()
        end
    end
    style.tooltip("Zoom so the whole spline fits the current width.")

    ImGui.Separator()

    -- Canvas ----------------------------------------------------------------
    local _, ySpace = ImGui.GetContentRegionAvail()
    local editorReserve = speedSplineTimeline.selected.track and ((layout.editorHeight + 8) * vs) or 0
    local canvasHeightChild = math.max(120 * vs, ySpace - editorReserve)

    if ImGui.BeginChild("##speedTimelineCanvas", 0, canvasHeightChild, false, ImGuiWindowFlags.HorizontalScrollbar) then
        local drawList = ImGui.GetWindowDrawList()
        local startX = ImGui.GetCursorPosX()
        local startY = ImGui.GetCursorPosY()

        local labelWidth = layout.labelWidth * vs
        local headerHeight = layout.headerHeight * vs
        local trackHeight = layout.trackHeight * vs
        local trackGap = layout.trackGap * vs
        local timelineX = startX + labelWidth

        local tracksHeight = #trackDefs * (trackHeight + trackGap) + trackGap
        local canvasHeight = headerHeight + tracksHeight + 6 * vs
        local canvasWidth = labelWidth + (displayLength * zoom) + (60 * vs)

        -- Size the scroll region.
        ImGui.SetCursorPos(startX + canvasWidth, startY + canvasHeight)
        ImGui.Dummy(1, 1)
        ImGui.SetCursorPos(startX, startY)

        local windowX, windowY = ImGui.GetWindowPos()
        local scrollX = (ImGui.GetScrollX and ImGui.GetScrollX()) or 0
        local scrollY = (ImGui.GetScrollY and ImGui.GetScrollY()) or 0

        local mouseX, mouseY = ImGui.GetMousePos()
        local childW = ImGui.GetWindowSize()
        local timelineLeftScreen = windowX + labelWidth
        local timelineRightScreen = windowX + childW
        local canvasTopScreen = windowY + startY - scrollY
        local canvasBottomScreen = windowY + startY + canvasHeight - scrollY

        local function toTimeline(localX, localY)
            return windowX + localX - scrollX, windowY + localY - scrollY
        end
        local function toLabel(localX, localY)
            return windowX + localX, windowY + localY - scrollY
        end
        ---@param meters number
        ---@return number
        local function meterToLocalX(meters)
            return timelineX + meters * zoom
        end

        -- Backgrounds.
        local bgX1, bgY1 = toTimeline(startX, startY)
        local bgX2, bgY2 = toTimeline(startX + canvasWidth, startY + canvasHeight)
        ImGui.ImDrawListAddRectFilled(drawList, bgX1, bgY1, bgX2, bgY2, 0x1A1E1E1E, 0)

        local rulerX1, rulerY1 = toTimeline(timelineX, startY)
        local rulerX2, rulerY2 = toTimeline(startX + canvasWidth, startY + headerHeight)
        ImGui.ImDrawListAddRectFilled(drawList, rulerX1, rulerY1, rulerX2, rulerY2, 0xFF252525, 0)

        local labelBgX1, labelBgY1 = toLabel(startX, startY)
        local labelBgX2, labelBgY2 = toLabel(timelineX, startY + headerHeight)
        ImGui.ImDrawListAddRectFilled(drawList, labelBgX1, labelBgY1, labelBgX2, labelBgY2, 0xFF1F1F1F, 0)

        -- Ruler ticks.
        local tickStep = getTickStep(zoom)
        local minorStep = math.max(0.01, tickStep / 5)

        local t = 0
        while t <= displayLength + 0.0001 do
            local lineX1, lineY1 = toTimeline(meterToLocalX(t), startY + headerHeight)
            local lineX2, lineY2 = toTimeline(meterToLocalX(t), startY + canvasHeight)
            ImGui.ImDrawListAddLine(drawList, lineX1, lineY1, lineX2, lineY2, 0x1D4B4B4B, 1)
            t = t + minorStep
        end

        t = 0
        while t <= displayLength + 0.0001 do
            local lineX1, lineY1 = toTimeline(meterToLocalX(t), startY)
            local lineX2, lineY2 = toTimeline(meterToLocalX(t), startY + canvasHeight)
            ImGui.ImDrawListAddLine(drawList, lineX1, lineY1, lineX2, lineY2, 0x3D5F5F5F, 1)

            local labelX, labelY = toTimeline(meterToLocalX(t) + 3, startY + 4 * vs)
            ImGui.ImDrawListAddText(drawList, ImGui.GetFontSize() * 0.8, labelX, labelY, 0xFFA5A19B, string.format("%gm", t))
            t = t + tickStep
        end

        -- Divider between label gutter and lanes.
        local divX1, divY1 = toLabel(timelineX, startY)
        local divX2, divY2 = toLabel(timelineX, startY + canvasHeight)
        ImGui.ImDrawListAddLine(drawList, divX1, divY1, divX2, divY2, 0x44383838, 1)

        -- Tracks and events. `rightClickOnEvent` suppresses the lane "add" menu when an event was
        -- the right-click target (that event opens its own delete menu instead). Deletions are
        -- deferred to `pendingDelete` and applied after the loops, never mutating a list mid-ipairs.
        local rightClickOnEvent = false
        local pendingDelete = nil
        for trackIdx, track in ipairs(trackDefs) do
            local trackTop = startY + headerHeight + (trackIdx - 1) * (trackHeight + trackGap) + trackGap
            local trackBottom = trackTop + trackHeight

            -- Lane backgrounds.
            local laneX1, laneY1 = toTimeline(timelineX, trackTop)
            local laneX2, laneY2 = toTimeline(startX + canvasWidth, trackBottom)
            ImGui.ImDrawListAddRectFilled(drawList, laneX1, laneY1, laneX2, laneY2, (trackIdx % 2 == 0) and 0x14262626 or 0x1E202020, 0)

            local labelLX1, labelLY1 = toLabel(startX, trackTop)
            local labelLX2, labelLY2 = toLabel(timelineX, trackBottom)
            ImGui.ImDrawListAddRectFilled(drawList, labelLX1, labelLY1, labelLX2, labelLY2, 0xFF202020, 0)

            local swatchX1, swatchY1 = toLabel(startX + 8 * vs, trackTop + trackHeight * 0.5 - 5 * vs)
            local swatchX2, swatchY2 = toLabel(startX + 13 * vs, trackTop + trackHeight * 0.5 + 5 * vs)
            ImGui.ImDrawListAddRectFilled(drawList, swatchX1, swatchY1, swatchX2, swatchY2, track.color, 2)

            local nameX, nameY = toLabel(startX + 20 * vs, trackTop + trackHeight * 0.5 - ImGui.GetFontSize() * 0.45)
            local count = 0
            if track.key == "speed" then count = #spline.speedChangeSections
            elseif track.key == "rotation" then count = #spline.orientationChangeSections
            else count = #spline.roadAdjustmentFactorChangeSections end
            ImGui.ImDrawListAddText(drawList, ImGui.GetFontSize() * 0.9, nameX, nameY, 0xFFD0D0D0, string.format("%s (%d)", track.label, count))

            if track.kind == "range" then
                for index, section in ipairs(spline.speedChangeSections) do
                    local lo = math.min(section.start, section.endPos)
                    local hi = math.max(section.start, section.endPos)
                    local barX = meterToLocalX(lo)
                    local barW = math.max(12 * vs, (hi - lo) * zoom)
                    local barY = trackTop + 3 * vs
                    local barH = trackHeight - 6 * vs

                    local sx1, sy1 = toTimeline(barX, barY)
                    local sx2, sy2 = toTimeline(barX + barW, barY + barH)

                    local selected = isSelected("speed", index)
                    local overlaps = spline:speedRangeOverlaps(index)
                    local fill = withAlpha(overlaps and overlapColor or track.color, 205)
                    local border = selected and selectedBorderColor or 0x99000000

                    ImGui.ImDrawListAddRectFilled(drawList, sx1, sy1, sx2, sy2, fill, 4)
                    ImGui.ImDrawListAddRect(drawList, sx1, sy1, sx2, sy2, border, 4, 0, selected and 2 or 1)

                    local labelText = string.format("S%d  %s", index, settings.formatSpeed(section.speed))
                    local titleX, titleY = toTimeline(barX + 5 * vs, barY + barH * 0.5 - ImGui.GetFontSize() * 0.4)
                    ImGui.ImDrawListAddText(drawList, ImGui.GetFontSize() * 0.8, titleX, titleY, 0xFFF5F5F5, fitText(labelText, barW - 8 * vs, 0.8))

                    ImGui.SetCursorPos(barX, barY)
                    ImGui.InvisibleButton("##speedEvt" .. index, barW, barH)
                    local hovered = ImGui.IsItemHovered()
                    local edgeZone = math.min(8 * vs, barW * 0.3)
                    local localX = select(1, ImGui.GetMousePos()) - sx1

                    if ImGui.IsItemActivated() then
                        local mode = "move"
                        if localX <= edgeZone then
                            mode = "resizeLeft"
                        elseif (barW - localX) <= edgeZone then
                            mode = "resizeRight"
                        end
                        selectEvent("speed", index)
                        beginDrag("speed", index, mode, select(1, ImGui.GetMousePos()))
                    end

                    local dragging = speedSplineTimeline.drag.active and speedSplineTimeline.drag.track == "speed" and speedSplineTimeline.drag.index == index
                    if dragging or hovered then
                        -- Emphasise the grabbable edges.
                        ImGui.ImDrawListAddLine(drawList, sx1 + 2, sy1 + 3, sx1 + 2, sy2 - 3, 0xCCFFFFFF, 2)
                        ImGui.ImDrawListAddLine(drawList, sx2 - 2, sy1 + 3, sx2 - 2, sy2 - 3, 0xCCFFFFFF, 2)
                    end

                    if ImGui.IsItemHovered() and ImGui.IsMouseReleased(ImGuiMouseButton.Right) then
                        rightClickOnEvent = true
                    end
                    if ImGui.BeginPopupContextItem("##speedEvtCtx" .. index, ImGuiPopupFlags.MouseButtonRight) then
                        style.mutedText(string.format("Speed range S%d", index))
                        ImGui.Separator()
                        if ImGui.MenuItem("Delete") then
                            pendingDelete = { track = "speed", index = index }
                        end
                        ImGui.EndPopup()
                    end
                end
            else
                local sections = track.key == "rotation" and spline.orientationChangeSections or spline.roadAdjustmentFactorChangeSections
                for index, section in ipairs(sections) do
                    local cx = meterToLocalX(section.pos)
                    local topLocal = trackTop + 2 * vs
                    local botLocal = trackBottom - 2 * vs
                    local midLocal = (topLocal + botLocal) * 0.5

                    local selected = isSelected(track.key, index)
                    local stemX1, stemY1 = toTimeline(cx, topLocal)
                    local stemX2, stemY2 = toTimeline(cx, botLocal)
                    ImGui.ImDrawListAddLine(drawList, stemX1, stemY1, stemX2, stemY2, withAlpha(track.color, 200), 2)

                    local diaCx, diaCy = toTimeline(cx, midLocal)
                    drawDiamond(drawList, diaCx, diaCy, 6 * vs, track.color, selected and selectedBorderColor or 0xCC000000)

                    local labelText = track.key == "rotation" and string.format("R%d", index) or string.format("G%d  %.2f", index, section.factor)
                    local labelX, labelY = toTimeline(cx + 9 * vs, topLocal)
                    ImGui.ImDrawListAddText(drawList, ImGui.GetFontSize() * 0.78, labelX, labelY, 0xFFECECEC, labelText)

                    local btnW = 16 * vs
                    ImGui.SetCursorPos(cx - btnW * 0.5, topLocal)
                    ImGui.InvisibleButton("##" .. track.key .. "Evt" .. index, btnW, botLocal - topLocal)
                    if ImGui.IsItemActivated() then
                        selectEvent(track.key, index)
                        beginDrag(track.key, index, "move", select(1, ImGui.GetMousePos()))
                    end

                    if ImGui.IsItemHovered() and ImGui.IsMouseReleased(ImGuiMouseButton.Right) then
                        rightClickOnEvent = true
                    end
                    if ImGui.BeginPopupContextItem("##" .. track.key .. "EvtCtx" .. index, ImGuiPopupFlags.MouseButtonRight) then
                        style.mutedText(track.key == "rotation" and string.format("Rotation point R%d", index) or string.format("Ground snap G%d", index))
                        ImGui.Separator()
                        if ImGui.MenuItem("Delete") then
                            pendingDelete = { track = track.key, index = index }
                        end
                        ImGui.EndPopup()
                    end
                end
            end
        end

        -- Apply a deferred deletion now that no list is being iterated.
        if pendingDelete then
            deleteTimelineEvent(spline, pendingDelete.track, pendingDelete.index)
        end

        -- Right-click an empty lane to add an event of that lane's type at the cursor distance.
        if not rightClickOnEvent and ImGui.IsWindowHovered() and ImGui.IsMouseReleased(ImGuiMouseButton.Right)
            and mouseX >= timelineLeftScreen and mouseX <= timelineRightScreen then
            for ti, tr in ipairs(trackDefs) do
                local laneTopScreen = windowY + (startY + headerHeight + (ti - 1) * (trackHeight + trackGap) + trackGap) - scrollY
                local laneBottomScreen = laneTopScreen + trackHeight
                if mouseY >= laneTopScreen and mouseY <= laneBottomScreen then
                    speedSplineTimeline.contextTrack = tr.key
                    speedSplineTimeline.contextDistance = clamp((mouseX - windowX + scrollX - timelineX) / math.max(zoom, 0.0001), 0, displayLength)
                    ImGui.OpenPopup("##speedTimelineAddCtx")
                    break
                end
            end
        end
        if ImGui.BeginPopup("##speedTimelineAddCtx") then
            local key = speedSplineTimeline.contextTrack
            local trackLabel = (key == "speed" and "speed range") or (key == "rotation" and "rotation point") or "ground-snap point"
            style.mutedText(string.format("At %s", formatMeters(speedSplineTimeline.contextDistance or 0)))
            ImGui.Separator()
            if key and ImGui.MenuItem("Add " .. trackLabel .. " here") then
                addEventAt(spline, key, snapValue(speedSplineTimeline.contextDistance or 0))
            end
            ImGui.EndPopup()
        end

        -- Scrubber -> world indicator. Active anywhere over the timeline (any lane or the ruler).
        local scrubActive = false
        if not speedSplineTimeline.drag.active
            and ImGui.IsWindowHovered()
            and mouseX >= timelineLeftScreen and mouseX <= timelineRightScreen
            and mouseY >= canvasTopScreen and mouseY <= canvasBottomScreen then
            local distance = clamp((mouseX - windowX + scrollX - timelineX) / math.max(zoom, 0.0001), 0, displayLength)
            spline._timelineHoverDistance = distance
            scrubActive = true

            -- Vertical guide across all lanes.
            ImGui.ImDrawListAddLine(drawList, mouseX, canvasTopScreen, mouseX, canvasBottomScreen, scrubColor, 1)

            -- Readout badge near the cursor (a tooltip can't be used here: there is no owning item).
            local speed = spline:getSpeedAtDistance(distance)
            local readout = string.format("%s   %s", formatMeters(distance), speed and settings.formatSpeed(speed) or "no speed set")
            local textW, textH = ImGui.CalcTextSize(readout)
            local pad = 4 * vs
            local badgeX = math.min(mouseX + 14 * vs, timelineRightScreen - textW - 2 * pad)
            local badgeY = mouseY - textH - 3 * pad
            if badgeY < canvasTopScreen then
                badgeY = mouseY + 16 * vs
            end
            ImGui.ImDrawListAddRectFilled(drawList, badgeX - pad, badgeY - pad, badgeX + textW + pad, badgeY + textH + pad, 0xE6202020, 3)
            ImGui.ImDrawListAddText(drawList, ImGui.GetFontSize(), badgeX, badgeY, 0xFFFFFFFF, readout)
        end

        updateDrag()

        -- While moving/resizing, show the event's live position value(s) in a cursor tooltip.
        if speedSplineTimeline.drag.active then
            local readout = dragReadout(spline, speedSplineTimeline.drag)
            if readout then
                ImGui.BeginTooltip()
                ImGui.PushStyleColor(ImGuiCol.Text, style.regularColor)
                ImGui.Text(readout)
                ImGui.PopStyleColor()
                ImGui.EndTooltip()
            end
        end

        if not scrubActive and not speedSplineTimeline.drag.active then
            spline._timelineHoverDistance = nil
        end
    end
    ImGui.EndChild()

    -- Selected-event editor.
    if speedSplineTimeline.selected.track then
        ImGui.Separator()
        if ImGui.BeginChild("##speedTimelineEditor", 0, layout.editorHeight * vs, false) then
            local stillSelected = spline:drawTimelineEventEditor(speedSplineTimeline.selected.track, speedSplineTimeline.selected.index)
            if not stillSelected then
                speedSplineTimeline.selected.track = nil
                speedSplineTimeline.selected.index = 0
            end
        end
        ImGui.EndChild()
    end
end

---@param spawnedUI table
function speedSplineTimeline.bindSpawnedUI(spawnedUI)
    speedSplineTimeline.spawnedUI = spawnedUI
end

---@param spline table
function speedSplineTimeline.openForSpline(spline)
    speedSplineTimeline.open = true
    speedSplineTimeline.spline = spline
    speedSplineTimeline.selected.track = nil
    speedSplineTimeline.selected.index = 0
end

function speedSplineTimeline.close()
    speedSplineTimeline.open = false
    endDrag()
end

---True while the timeline window is open (it always tracks the selected speed spline).
---@return boolean
function speedSplineTimeline.isOpen()
    return speedSplineTimeline.open == true
end

---Follows the single-selected speed spline in the Spawned hierarchy, and closes the window when
---the bound spline is removed from the hierarchy (`element:remove` nils the element's parent).
local function syncToSelection()
    local spawnedUI = speedSplineTimeline.spawnedUI
    if spawnedUI then
        spawnedUI.ensureCache()
        if #spawnedUI.selectedPaths == 1 then
            local ref = spawnedUI.selectedPaths[1].ref
            if ref and ref.spawnable and ref.spawnable.node == "worldSpeedSplineNode"
                and speedSplineTimeline.spline ~= ref.spawnable then
                speedSplineTimeline.spline = ref.spawnable
                speedSplineTimeline.selected.track = nil
                speedSplineTimeline.selected.index = 0
            end
        end
    end

    local sp = speedSplineTimeline.spline
    if speedSplineTimeline.open and sp and (sp.object == nil or sp.object.parent == nil) then
        speedSplineTimeline.close()
        speedSplineTimeline.spline = nil
    end
end

function speedSplineTimeline.drawWindow()
    wu = wu or GetMod("WindowUtils") or ImGui

    syncToSelection()

    -- Always clear the scrubber first; it is re-set below only while hovering the speed lane.
    local spline = getSpline()
    if spline then
        spline._timelineHoverDistance = nil
    end

    if not speedSplineTimeline.open then
        endDrag()
        return
    end

    loadSettings()

    -- Keep an in-progress drag responsive (and self-terminating on mouse-up) even on frames
    -- where the canvas child is skipped; the in-canvas call below handles the normal case.
    if speedSplineTimeline.drag.active then
        updateDrag()
    end

    local screenWidth, screenHeight = GetDisplayResolution()
    local timelineFlags = ImGuiWindowFlags.NoCollapse
    local dockStyleApplied = false

    if settings.speedTimelineDockBottom then
        local minHeight = 180 * style.viewSize
        local maxHeight = math.max(minHeight, screenHeight * 0.85)
        local targetHeight = clamp(settings.speedTimelineDockHeight or math.floor(screenHeight * 0.3), minHeight, maxHeight)

        ImGui.SetNextWindowPos(0, screenHeight, ImGuiCond.Always, 0, 1)
        ImGui.SetNextWindowSizeConstraints(screenWidth, minHeight, screenWidth, maxHeight)
        if not speedSplineTimeline.dockWasBottom then
            ImGui.SetNextWindowSize(screenWidth, targetHeight, ImGuiCond.Always)
        end

        timelineFlags = timelineFlags + ImGuiWindowFlags.NoMove + ImGuiWindowFlags.NoTitleBar
        style.pushStyleColor(true, ImGuiCol.WindowBg, 0, 0, 0, 1)
        style.pushStyleVar(true, ImGuiStyleVar.WindowRounding, 0)
        dockStyleApplied = true
    end

    speedSplineTimeline.open = wu.Begin("Speed Spline Timeline", true, timelineFlags, { skip = settings.speedTimelineDockBottom })
    if not speedSplineTimeline.open then
        -- CET only pairs End() with a truthy Begin(); collapsed/closed window must not call End().
        endDrag()
        speedSplineTimeline.dockWasBottom = settings.speedTimelineDockBottom
        style.popStyleVar(dockStyleApplied)
        style.popStyleColor(dockStyleApplied)
        return
    end

    -- Register as "main" input context while hovered so the 3D-editor's viewport/hierarchy
    -- right-click context menu doesn't fire over this window (viewport.hovered = not main.hovered).
    input.updateContext("main")

    -- Dock / close controls (top-right).
    local originalCursorX = ImGui.GetCursorPosX()
    local originalCursorY = ImGui.GetCursorPosY()
    local dockInIcon = (IconGlyphs.DockBottom and IconGlyphs.DockBottom ~= "") and IconGlyphs.DockBottom or "v"
    local dockOutIcon = (IconGlyphs.DockWindow and IconGlyphs.DockWindow ~= "") and IconGlyphs.DockWindow or "^"
    local dockIcon = settings.speedTimelineDockBottom and dockOutIcon or dockInIcon
    local showDockedClose = settings.speedTimelineDockBottom == true
    local closeIcon = (IconGlyphs.Close and IconGlyphs.Close ~= "") and IconGlyphs.Close or "x"
    local dockButtonWidth = ImGui.CalcTextSize(dockIcon)
    local closeButtonWidth = ImGui.CalcTextSize(closeIcon)
    local controlsSpacing = ImGui.GetStyle().ItemSpacing.x
    local totalControlWidth = dockButtonWidth + (showDockedClose and (controlsSpacing + closeButtonWidth) or 0)
    local dockButtonX = originalCursorX + ImGui.GetContentRegionAvail() - totalControlWidth
    local dockButtonY = math.max(0, originalCursorY - 4)
    local closeRequested = false

    ImGui.SetCursorPos(dockButtonX, dockButtonY)
    style.pushStyleColor(timelineDockButtonHovered, ImGuiCol.Text, style.mutedColor)
    ImGui.SetItemAllowOverlap()
    ImGui.Text(dockIcon)
    style.popStyleColor(timelineDockButtonHovered)
    timelineDockButtonHovered = ImGui.IsItemHovered()
    if ImGui.IsItemClicked(ImGuiMouseButton.Left) then
        settings.speedTimelineDockBottom = not settings.speedTimelineDockBottom
        settings.save()
    end
    style.tooltip(settings.speedTimelineDockBottom and "Dock panel as floating window" or "Dock panel to the bottom")

    if showDockedClose then
        ImGui.SetCursorPos(dockButtonX + dockButtonWidth + controlsSpacing, dockButtonY)
        style.pushStyleColor(timelineCloseButtonHovered, ImGuiCol.Text, style.mutedColor)
        ImGui.SetItemAllowOverlap()
        ImGui.Text(closeIcon)
        style.popStyleColor(timelineCloseButtonHovered)
        timelineCloseButtonHovered = ImGui.IsItemHovered()
        if ImGui.IsItemClicked(ImGuiMouseButton.Left) then
            closeRequested = true
        end
        style.tooltip("Close Speed Spline Timeline")
    end

    ImGui.SetCursorPosX(originalCursorX)
    ImGui.SetCursorPosY(originalCursorY)

    local function finish()
        speedSplineTimeline.dockWasBottom = settings.speedTimelineDockBottom
        if settings.speedTimelineDockBottom then
            local _, currentHeight = ImGui.GetWindowSize()
            local minHeight = 180 * style.viewSize
            local maxHeight = math.max(minHeight, screenHeight * 0.85)
            local clampedHeight = clamp(currentHeight, minHeight, maxHeight)
            if math.abs((settings.speedTimelineDockHeight or clampedHeight) - clampedHeight) > 0.5 then
                settings.speedTimelineDockHeight = clampedHeight
                settings.save()
            end
        end
        wu.End()
        style.popStyleVar(dockStyleApplied)
        style.popStyleColor(dockStyleApplied)
    end

    if closeRequested then
        speedSplineTimeline.open = false
        endDrag()
        finish()
        return
    end

    if not spline then
        style.mutedText("No Speed Spline is bound to the timeline.")
        style.mutedText("Open it from a Speed Spline's inspector with \"Open Timeline Editor\".")
        finish()
        return
    end

    local points = spline:getMarkerOrderedPathPoints()
    if #points < 2 then
        style.mutedText("This Speed Spline needs at least two points before it can be edited on the timeline.")
        finish()
        return
    end

    drawCanvas(spline)
    finish()
end

return speedSplineTimeline
