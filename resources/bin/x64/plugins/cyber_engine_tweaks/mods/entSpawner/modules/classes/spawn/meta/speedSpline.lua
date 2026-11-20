local spline = require("modules/classes/spawn/meta/spline")
local style = require("modules/ui/style")
local utils = require("modules/utils/core/utils")
local history = require("modules/utils/project/history")
local field = require("modules/utils/ui/field")
local projectedWireframe = require("modules/utils/editor/projectedWireframe")
local settings = require("modules/utils/core/settings")
local speedSplineTimeline = require("modules/ui/speedSplineTimeline")
local visualizer = require("modules/utils/preview/visualizer")

-- worldSpeedSplineOrientationMarkerType, ordered by enum value.
-- The `value` is the exact RED enum name used on export, the rest drives the UI.
-- `axes` lists which orientation components (pitch/yaw/roll) this mode actually overrides;
-- only those are shown as inputs and applied to the gizmo.
local orientationModes = {
    { value = "UseSplineOrientation",        label = "Use spline orientation",        tooltip = "Keep the orientation defined by the spline itself. Target orientation is ignored.",  axes = {} },
    { value = "WorldSpace",                  label = "World space (absolute)",         tooltip = "Force an absolute world-space orientation, ignoring the spline direction.",           axes = { pitch = true, yaw = true, roll = true } },
    { value = "LocalSpace",                  label = "Local space (spline relative)",  tooltip = "Apply the target orientation relative to the spline's local frame.",                  axes = { pitch = true, yaw = true, roll = true } },
    { value = "KeepYawRoll_WorldSpacePitch", label = "Override pitch only",            tooltip = "Keep yaw & roll from the spline, override pitch in world space.",                     axes = { pitch = true } },
    { value = "KeepPitchYaw_WorldSpaceRoll", label = "Override roll only",             tooltip = "Keep pitch & yaw from the spline, override roll in world space.",                     axes = { roll = true } },
    { value = "KeepPitchRoll_WorldSpaceYaw", label = "Override yaw only",              tooltip = "Keep pitch & roll from the spline, override yaw in world space.",                     axes = { yaw = true } },
    { value = "KeepYaw_WorldSpacePitchRoll", label = "Override pitch & roll",          tooltip = "Keep yaw from the spline, override pitch & roll in world space.",                     axes = { pitch = true, roll = true } },
    { value = "KeepRoll_WorldSpacePitchYaw", label = "Override pitch & yaw",           tooltip = "Keep roll from the spline, override pitch & yaw in world space.",                     axes = { pitch = true, yaw = true } },
    { value = "KeepPitch_WorldSpaceYawRoll", label = "Override yaw & roll",            tooltip = "Keep pitch from the spline, override yaw & roll in world space.",                     axes = { yaw = true, roll = true } }
}

local orientationModeLabels = {}
local orientationModeIndexByValue = {}
for index, mode in ipairs(orientationModes) do
    orientationModeLabels[index] = mode.label
    orientationModeIndexByValue[mode.value] = index
end

---Resolves a mode entry (falls back to the first entry) from its enum value.
---@param modeValue string
---@return table
local function getOrientationMode(modeValue)
    return orientationModes[orientationModeIndexByValue[modeValue] or 1]
end

local maxSectionPosition = 100000

-- In-world gizmo used to preview rotation points. The prism model points along +Y after
-- the alignment offset below (same offset the light preview uses for this mesh).
local rotationGizmoMesh = "base\\spawner\\triangular_prism.mesh"
local rotationGizmoAppearance = "yellow"
local rotationGizmoScale = 0.5

---Packs an RGBA color into the IM_COL32 (0xAABBGGRR) integer used by ImGui draw lists.
---@param r number
---@param g number
---@param b number
---@param a number?
---@return integer
local function rgba(r, g, b, a)
    return (a or 255) * 0x1000000 + b * 0x10000 + g * 0x100 + r
end

-- On-screen point marker colors per type, in two variants selected by the global
-- "Wireframe color style" setting: 1 = darker markers + white text, 2 = lighter markers + black text.
local pointLabelColors = {
    [1] = {
        speed = rgba(45, 140, 60),       -- dark green
        rotation = rgba(180, 100, 20),   -- dark orange
        groundSnap = rgba(30, 105, 170)  -- dark blue
    },
    [2] = {
        speed = rgba(95, 220, 95),       -- light green
        rotation = rgba(245, 165, 45),   -- light orange
        groundSnap = rgba(70, 190, 235)  -- light blue
    }
}
local pointLabelTextColors = {
    [1] = rgba(220, 216, 209), -- near-white
    [2] = rgba(0, 0, 0)        -- black
}

---Resolves the current point-label palette from the "Wireframe color style" setting.
---@return table colors Marker colors keyed by point type.
---@return integer textColor Badge text color.
local function getPointLabelPalette()
    local styleIndex = tonumber(settings.wireframeColorStyle) == 2 and 2 or 1
    return pointLabelColors[styleIndex], pointLabelTextColors[styleIndex]
end

---Returns the world position and spline travel direction at a given distance (m) along a polyline.
---@param points table[] Ordered {x,y,z} points forming the polyline.
---@param distance number Distance in meters measured from the first point.
---@return table|nil position {x,y,z} world position, or nil when the polyline is empty.
---@return Vector4|nil forward Spline travel direction at that position.
local function positionAlongPolyline(points, distance)
    if #points == 0 then return nil end

    local function forwardAt(i)
        local a = points[i]
        local b = points[i + 1]
        return Vector4.new(b.x - a.x, b.y - a.y, b.z - a.z, 0)
    end

    if #points == 1 then
        return points[1], Vector4.new(0, 1, 0, 0)
    end

    if distance <= 0 then
        return points[1], forwardAt(1)
    end

    local traveled = 0
    for i = 1, #points - 1 do
        local a = points[i]
        local b = points[i + 1]
        local segmentLength = utils.distanceVector(a, b)
        if segmentLength > 0 and traveled + segmentLength >= distance then
            local t = (distance - traveled) / segmentLength
            return {
                x = a.x + (b.x - a.x) * t,
                y = a.y + (b.y - a.y) * t,
                z = a.z + (b.z - a.z) * t
            }, forwardAt(i)
        end
        traveled = traveled + segmentLength
    end

    return points[#points], forwardAt(#points - 1)
end

---Class for worldSpeedSplineNode. Reuses the whole basic spline pipeline (path,
---markers, curve/NPC preview) and layers the speed-spline specific runtime data on top:
---speed control, per-position rotation overrides and ground snapping.
---@class speedSpline : spline
---@field speedChangeSections table
---@field orientationChangeSections table
---@field roadAdjustmentFactorChangeSections table
---@field ignoreTerrain boolean
---@field protected speedPropertyWidth number
---@field protected _timelineHoverDistance number? Distance (m) of the timeline scrubber, or nil when not hovering.
---@field protected _maxPositionCache number? Cached spline length used to cap event positions.
local speedSpline = setmetatable({}, { __index = spline })

function speedSpline:new()
    local o = spline.new(self)

    o.spawnListType = "files"
    o.dataType = "Speed Spline"
    o.spawnDataPath = "data/spawnables/meta/speedSpline/"
    o.modulePath = "meta/speedSpline"
    o.node = "worldSpeedSplineNode"
    o.description = "Spline that drives movement along it, with speed, rotation and ground-snap control at arbitrary positions. Reuses the basic spline for its path and can be referenced using its NodeRef."
    o.icon = IconGlyphs.Speedometer

    o.previewColor = "cyan"

    -- [Speed control]
    o.speedChangeSections = {}
    -- [Rotation]
    o.orientationChangeSections = {}
    -- [Ground Snap]
    o.roadAdjustmentFactorChangeSections = {}
    o.ignoreTerrain = false

    o.speedPropertyWidth = nil
    o._rotationGizmoCount = 0

    setmetatable(o, { __index = self })
    return o
end

function speedSpline:loadSpawnData(data, position, rotation)
    spline.loadSpawnData(self, data, position, rotation)

    self.speedChangeSections = self:normalizeSpeedSections(self.speedChangeSections)
    self.orientationChangeSections = self:normalizeOrientationSections(self.orientationChangeSections)
    self.roadAdjustmentFactorChangeSections = self:normalizeRoadSections(self.roadAdjustmentFactorChangeSections)
    self.ignoreTerrain = self.ignoreTerrain == true
end

---@param sections table?
---@return table
function speedSpline:normalizeSpeedSections(sections)
    local normalized = {}
    for _, section in ipairs(sections or {}) do
        table.insert(normalized, {
            start = utils.toNumber(section.start, 0),
            endPos = utils.toNumber(section.endPos, 0),
            speed = utils.toNumber(section.speed, 0)
        })
    end
    return normalized
end

---@param sections table?
---@return table
function speedSpline:normalizeOrientationSections(sections)
    local normalized = {}
    for _, section in ipairs(sections or {}) do
        local mode = section.mode
        if not orientationModeIndexByValue[mode] then
            mode = orientationModes[1].value
        end
        table.insert(normalized, {
            pos = utils.toNumber(section.pos, 0),
            mode = mode,
            pitch = utils.toNumber(section.pitch, 0),
            yaw = utils.toNumber(section.yaw, 0),
            roll = utils.toNumber(section.roll, 0)
        })
    end
    return normalized
end

---@param sections table?
---@return table
function speedSpline:normalizeRoadSections(sections)
    local normalized = {}
    for _, section in ipairs(sections or {}) do
        table.insert(normalized, {
            pos = utils.toNumber(section.pos, 0),
            factor = utils.toNumber(section.factor, 1)
        })
    end
    return normalized
end

---Snapshots the element for undo before a structural (add/remove) list change.
function speedSpline:recordStructuralChange()
    if self.object then
        history.addAction(history.getElementChange(self.object))
    end
end

---Recomputes and caches the max in-bounds position. `getTotalLength` does bezier arc-length
---integration, so this is called once per draw pass (see `draw` / the timeline) rather than per
---field, and `getMaxPosition` reads the cache.
---@return number
function speedSpline:refreshMaxPosition()
    local length = self:getTotalLength()
    self._maxPositionCache = (length and length > 0.01) and length or maxSectionPosition
    return self._maxPositionCache
end

---Maximum in-bounds position (m) for any event: the spline length, so positions can't run past
---the end of the spline. Falls back to a large value only for a degenerate spline (< 2 points).
---@return number
function speedSpline:getMaxPosition()
    if self._maxPositionCache == nil then
        return self:refreshMaxPosition()
    end
    return self._maxPositionCache
end

---Adds a speed range and returns its new index. Shared by the section list and the timeline.
---@param startPos number
---@param endPos number
---@param speed number
---@return integer index
function speedSpline:addSpeedSection(startPos, endPos, speed)
    self:recordStructuralChange()
    table.insert(self.speedChangeSections, { start = startPos, endPos = endPos, speed = speed })
    return #self.speedChangeSections
end

---Adds a rotation point and returns its new index. Respawns the node so the fresh entity assembly
---creates the new prism gizmo component: adding a component to an already-assembled entity does
---not render until it is reassembled (same reason hiding then unhiding the node works).
---@param pos number
---@return integer index
function speedSpline:addOrientationPoint(pos)
    self:recordStructuralChange()
    table.insert(self.orientationChangeSections, {
        pos = pos,
        mode = orientationModes[1].value,
        pitch = 0,
        yaw = 0,
        roll = 0
    })
    if self:isSpawned() then
        self:respawn()
    end
    return #self.orientationChangeSections
end

---Adds a ground-snap point and returns its new index.
---@param pos number
---@param factor number
---@return integer index
function speedSpline:addRoadPoint(pos, factor)
    self:recordStructuralChange()
    table.insert(self.roadAdjustmentFactorChangeSections, { pos = pos, factor = factor })
    return #self.roadAdjustmentFactorChangeSections
end

---Removes a timeline event from the given track. Rotation removals refresh the gizmos (the freed
---one is hidden by updateRotationGizmos); no respawn is needed on removal.
---@param track string "speed" | "rotation" | "groundSnap"
---@param index number
---@return boolean removed
function speedSpline:removeTimelineEvent(track, index)
    local sections = (track == "speed" and self.speedChangeSections)
        or (track == "rotation" and self.orientationChangeSections)
        or (track == "groundSnap" and self.roadAdjustmentFactorChangeSections)
    if not sections or not sections[index] then return false end

    self:recordStructuralChange()
    table.remove(sections, index)
    if track == "rotation" then
        self:updateCurvePreview()
    end
    return true
end

---Ordered curve polyline (first marker -> last marker), independent of the reverse
---preview flag, so a point's "position along the spline" is always measured from the
---first spline point.
---@return table[] points Ordered {x,y,z} world points.
function speedSpline:getMarkerOrderedPathPoints()
    local points = self:getFollowerPathPoints()
    if self.reverse and #points > 1 then
        local ordered = {}
        for i = #points, 1, -1 do
            table.insert(ordered, points[i])
        end
        return ordered
    end
    return points
end

---Target speed (m/s) that the performer holds at a given distance along the spline, derived
---from the speed change sections. Each section ramps linearly from the previously held speed to
---its target across [start, end]; between sections the speed holds at the last target. The
---performer enters at rest, so the speed before the first section's start is 0 and the first
---section ramps up from 0.
---@param distance number Distance in meters from the spline start.
---@return number|nil speed Speed in m/s, or nil when there are no speed sections.
function speedSpline:getSpeedAtDistance(distance)
    if #self.speedChangeSections == 0 then return nil end

    local sorted = {}
    for _, section in ipairs(self.speedChangeSections) do
        table.insert(sorted, section)
    end
    table.sort(sorted, function(a, b)
        return math.min(a.start, a.endPos) < math.min(b.start, b.endPos)
    end)

    local held = 0 -- initial speed before the first section (performer starts at rest)
    for _, section in ipairs(sorted) do
        local rampStart = math.min(section.start, section.endPos)
        local rampEnd = math.max(section.start, section.endPos)
        if distance < rampStart then
            return held
        elseif distance <= rampEnd then
            if rampEnd - rampStart < 1e-6 then
                return section.speed
            end
            local t = (distance - rampStart) / (rampEnd - rampStart)
            return held + (section.speed - held) * t
        end
        held = section.speed
    end

    return held
end

---Creates (or fetches) the mesh component used as the in-world gizmo for rotation point `index`.
---@param index number
---@return entMeshComponent|nil
function speedSpline:getRotationGizmoComponent(index)
    local entity = self:getEntity()
    if not entity then return end

    local name = "rotationGizmo" .. tostring(index)
    local component = entity:FindComponentByName(name)
    if component then
        return component
    end

    if not self:canAddPreviewComponent(entity) then
        return nil
    end

    component = entMeshComponent.new()
    component.name = name
    component.mesh = ResRef.FromString(rotationGizmoMesh)
    component.meshAppearance = rotationGizmoAppearance
    component.visualScale = Vector3.new(rotationGizmoScale, rotationGizmoScale, rotationGizmoScale)
    component.isEnabled = self.previewed
    visualizer.bindToPlacedParent(entity, component)
    entity:AddComponent(component)

    return component
end

---Combines the spline travel direction at a point with the point's target orientation and
---applies the prism alignment offset. `WorldSpace` uses the absolute target orientation only.
---@param forward Vector4? Spline travel direction at the point.
---@param section table Orientation change section.
---@return Quaternion
function speedSpline:getRotationGizmoOrientation(forward, section)
    -- Only the axes the mode actually overrides contribute; the rest follow the spline.
    -- This also makes "Use spline orientation" ignore any stale target values.
    local axes = getOrientationMode(section.mode).axes
    local pointRotation = EulerAngles.new(
        axes.roll and section.roll or 0,
        axes.pitch and section.pitch or 0,
        axes.yaw and section.yaw or 0
    )

    local combined
    if section.mode == "WorldSpace" or not (forward and forward:Length() > 0.0001) then
        combined = pointRotation
    else
        -- Overridden components applied relative to the spline heading (its local frame).
        combined = utils.addEulerRelative(forward:ToRotation(), pointRotation)
    end

    -- Align the prism model with the combined forward, mirroring the light preview's
    -- `entityRotation * meshLocalOffset` composition.
    local offset = EulerAngles.new(-90, 0, 90):ToQuat()
    return utils.multQuat(combined:ToQuat(), offset)
end

---Positions and orients a triangular-prism gizmo at each rotation point, hiding unused ones.
---The gizmo shows the point's orientation combined with the spline direction for an accurate preview.
function speedSpline:updateRotationGizmos()
    local entity = self:getEntity()
    if not entity then return end

    local points = self:getMarkerOrderedPathPoints()
    local used = 0

    if #points >= 2 then
        for _, section in ipairs(self.orientationChangeSections) do
            local worldPos, forward = positionAlongPolyline(points, section.pos)
            if worldPos then
                used = used + 1
                local component = self:getRotationGizmoComponent(used)
                if component then
                    local localPos = utils.subVector(Vector4.new(worldPos.x, worldPos.y, worldPos.z, 0), self.position)
                    component:SetLocalPosition(Vector4.new(localPos.x, localPos.y, localPos.z, 0))
                    component:SetLocalOrientation(self:getRotationGizmoOrientation(forward, section))
                    component:Toggle(self.previewed)
                    component:RefreshAppearance()
                end
            end
        end
    end

    for i = used + 1, self._rotationGizmoCount or 0 do
        local component = entity:FindComponentByName("rotationGizmo" .. tostring(i))
        if component then
            component:Toggle(false)
        end
    end

    self._rotationGizmoCount = math.max(self._rotationGizmoCount or 0, used)
end

function speedSpline:updateCurvePreview()
    spline.updateCurvePreview(self)
    self:updateRotationGizmos()
end

---Whether point labels should currently be drawn: only while the spline is selected
---or its preview is enabled. Used by the editor to skip opening an empty overlay.
---@return boolean
function speedSpline:wantsViewportOverlay()
    if self._timelineHoverDistance ~= nil then return true end
    return self.object ~= nil and (self.object.selected == true or self.previewed == true)
end

---Draws on-screen, color-coded labels for each point at its position along the spline.
---Shown while the spline is selected or its preview is enabled. Invoked once per frame
---by the editor viewport overlay pass.
---@param screen projectedScreenContext Projection context from `projectedWireframe.beginOverlay`.
---@param drawList table ImGui draw list from `projectedWireframe.beginOverlay`.
function speedSpline:drawViewportOverlay(screen, drawList)
    if not self:wantsViewportOverlay() then return end

    local points = self:getMarkerOrderedPathPoints()
    if #points < 2 then return end

    local colors, textColor = getPointLabelPalette()

    ---@param position number Distance along the spline (m).
    ---@param color integer Marker color.
    ---@param text string Badge text.
    ---@param below boolean? When true, the badge is placed under the point instead of above.
    local function drawLabel(position, color, text, below)
        local world = positionAlongPolyline(points, position)
        if not world then return end

        projectedWireframe.drawWorldMarker(drawList, screen, Vector4.new(world.x, world.y, world.z, 0), {
            color = color,
            labelColor = textColor,
            text = text,
            radius = 5 * style.viewSize,
            innerRadius = 2.5 * style.viewSize,
            badgeOffsetY = (below and 9 or -14) * style.viewSize,
            fontRatio = 0.85,
            clampToScreen = false
        })
    end

    for index, section in ipairs(self.speedChangeSections) do
        drawLabel(section.start, colors.speed, string.format("S%d start", index))
        drawLabel(section.endPos, colors.speed, string.format("S%d  %s", index, settings.formatSpeed(section.speed)))
    end

    -- Rotation points are previewed with in-world prism gizmos (see updateRotationGizmos), not labels.

    for index, section in ipairs(self.roadAdjustmentFactorChangeSections) do
        drawLabel(section.pos, colors.groundSnap, string.format("G%d  %.2f", index, section.factor), true)
    end

    -- Timeline scrubber: a movable indicator synced to the cursor in the Speed Spline Timeline,
    -- reading out the speed interpolated at that exact distance.
    if self._timelineHoverDistance ~= nil then
        local world = positionAlongPolyline(points, self._timelineHoverDistance)
        if world then
            local speed = self:getSpeedAtDistance(self._timelineHoverDistance)
            local text = speed and settings.formatSpeed(speed) or "no speed"
            projectedWireframe.drawWorldMarker(drawList, screen, Vector4.new(world.x, world.y, world.z, 0), {
                color = rgba(0, 214, 255),
                labelColor = textColor,
                text = text,
                radius = 7 * style.viewSize,
                innerRadius = 3 * style.viewSize,
                badgeOffsetY = -15 * style.viewSize,
                fontRatio = 0.9,
                clampToScreen = false
            })
        end
    end
end

-- Width (unscaled) reserved for the leading index cell of each table row.
local rowIndexColumnWidth = 20

---Draws the leading index cell of a table-style row and aligns the cursor to the field columns.
---@param prefix string Unique ImGui id prefix for the row.
---@param index number Row number shown in the index cell.
---@param fieldStartX number Absolute cursor X where the field columns start.
local function beginTableRow(prefix, index, fieldStartX)
    ImGui.PushID(prefix .. index)
    ImGui.AlignTextToFramePadding()
    ImGui.SetCursorPosX(8 * style.viewSize)
    style.mutedText(string.format("%d", index))
    ImGui.SameLine()
    ImGui.SetCursorPosX(fieldStartX)
end

---Draws a red delete button at the end of a table-style row. Returns true when clicked.
---@return boolean
local function drawRowDeleteButton()
    ImGui.SameLine()
    local clicked = style.dangerButton(IconGlyphs.DeleteOutline)
    style.tooltip("Remove this entry")
    return clicked
end

---Absolute X where a table row's value columns start (after the index cell).
---@return number
local function getRowFieldStartX()
    return rowIndexColumnWidth * (style.viewSize or 1)
end

---Editable "position along the spline" cell. Capped at the spline length so a position can't be
---edited out of bounds (existing out-of-range values are only pulled in when the field is touched).
---@param self speedSpline
---@param id string
---@param value number
---@param suffix string
---@return number newValue
local function positionCell(self, id, value, suffix)
    local newValue = field.advancedTrackedFloat(self.object, id, value, {
        min = 0,
        max = self:getMaxPosition(),
        step = 0.1,
        format = "%.2f",
        suffix = suffix,
        width = 68
    })
    return newValue
end

function speedSpline:draw()
    -- Reuse the entire basic spline UI (path, length, reverse, looped, previewing options).
    spline.draw(self)

    -- Refresh the cached max position once per frame; the section position fields read the cache.
    self:refreshMaxPosition()

    if not self.speedPropertyWidth then
        self.speedPropertyWidth = utils.getTextMaxWidth({ "Ignore Terrain" }) + 2 * ImGui.GetStyle().ItemSpacing.x + ImGui.GetCursorPosX()
    end

    ImGui.Spacing()

    -- The timeline always tracks the selected speed spline, so an open window is showing this one.
    local timelineOpen = speedSplineTimeline.isOpen()
    local toggleText = timelineOpen and "Close Timeline Editor" or "Open Timeline Editor"
    local toggleLabel, toggleHiddenText = style.resolveActionLabel(IconGlyphs.ChartTimeline, toggleText, "speedSplineTimelineToggle", nil, true)
    if ImGui.Button(toggleLabel) then
        if timelineOpen then
            speedSplineTimeline.close()
        else
            speedSplineTimeline.openForSpline(self)
        end
    end
    if toggleHiddenText then
        style.tooltipActionLabel(toggleHiddenText, toggleHiddenText .. "\nDrag, resize and reorder every speed / rotation / ground-snap point on a spatial timeline.")
    else
        style.tooltip("Drag, resize and reorder every speed / rotation / ground-snap point on a spatial timeline.")
    end

    ImGui.Spacing()
    self:drawSpeedControlSection()
    self:drawRotationSection()
    self:drawGroundSnapSection()
end

function speedSpline:drawSpeedControlSection()
    if not ImGui.TreeNodeEx("Speed Control (" .. #self.speedChangeSections .. ")###speedControl", ImGuiTreeNodeFlags.SpanFullWidth) then
        return
    end

    style.mutedText("Sets the target speed along ranges of the spline.\nPositions are distances in meters from the spline start.")
    ImGui.Spacing()

    local fieldStartX = getRowFieldStartX()
    local removeIndex = nil

    for index, section in ipairs(self.speedChangeSections) do
        beginTableRow("speedSection", index, fieldStartX)

        section.start = positionCell(self, "##start", section.start, " start")
        style.tooltip("Distance where the speed change begins (m along the spline).")

        ImGui.SameLine()
        section.endPos = positionCell(self, "##end", section.endPos, " end")
        style.tooltip("Distance where the target speed is fully reached. A shorter range means a quicker change.")

        ImGui.SameLine()
        section.speed = field.advancedTrackedFloat(self.object, "##speed", section.speed, { min = 0, max = 1000, step = 0.1, format = "%.2f", suffix = " m/s", width = 80 })
        style.tooltip("Desired speed inside this range, in meters per second.")

        ImGui.SameLine()
        style.mutedText(string.format("(%s)", settings.formatSpeed(section.speed)))

        if drawRowDeleteButton() then
            removeIndex = index
        end

        ImGui.PopID()
    end

    if removeIndex then
        self:recordStructuralChange()
        table.remove(self.speedChangeSections, removeIndex)
    end

    if ImGui.Button(IconGlyphs.Plus .. " Add speed range") then
        local length = self:getTotalLength()
        self:addSpeedSection(0, length > 0.01 and length or 10, 10)
    end

    ImGui.TreePop()
end

function speedSpline:drawRotationSection()
    if not ImGui.TreeNodeEx("Rotation (" .. #self.orientationChangeSections .. ")###rotation", ImGuiTreeNodeFlags.SpanFullWidth) then
        return
    end

    style.mutedText("Overrides orientation at specific positions along the spline.")
    ImGui.Spacing()

    local fieldStartX = getRowFieldStartX()
    local removeIndex = nil
    local dirty = false

    for index, section in ipairs(self.orientationChangeSections) do
        beginTableRow("orientationSection", index, fieldStartX)

        local previousPos = section.pos
        section.pos = positionCell(self, "##pos", section.pos, " m")
        style.tooltip("Position where this orientation is applied (m along the spline).")
        if section.pos ~= previousPos then dirty = true end

        ImGui.SameLine()
        local modeIndex = orientationModeIndexByValue[section.mode] or 1
        -- Pass the description through the combo's own tooltip (value + helper) instead of a
        -- second style.tooltip call, which would render an overlapping/clipped tooltip window.
        local newModeIndex, modeChanged = style.trackedCombo(self.object, "##mode", modeIndex - 1, orientationModeLabels, 168, {
            tooltip = getOrientationMode(section.mode).tooltip
        })
        if modeChanged then
            section.mode = orientationModes[newModeIndex + 1].value
            dirty = true
        end

        local axes = getOrientationMode(section.mode).axes
        local changedP, changedY, changedR
        if axes.pitch then
            ImGui.SameLine()
            section.pitch, changedP = field.advancedTrackedFloat(self.object, "##pitch", section.pitch, { min = -360, max = 360, step = 0.5, format = "%.1f", suffix = " P", width = 52 })
            style.tooltip("Overridden pitch, in degrees.")
        end
        if axes.yaw then
            ImGui.SameLine()
            section.yaw, changedY = field.advancedTrackedFloat(self.object, "##yaw", section.yaw, { min = -360, max = 360, step = 0.5, format = "%.1f", suffix = " Y", width = 52 })
            style.tooltip("Overridden yaw, in degrees.")
        end
        if axes.roll then
            ImGui.SameLine()
            section.roll, changedR = field.advancedTrackedFloat(self.object, "##roll", section.roll, { min = -360, max = 360, step = 0.5, format = "%.1f", suffix = " R", width = 52 })
            style.tooltip("Overridden roll, in degrees.")
        end
        if changedP or changedY or changedR then dirty = true end

        if drawRowDeleteButton() then
            removeIndex = index
        end

        ImGui.PopID()
    end

    if removeIndex then
        self:recordStructuralChange()
        table.remove(self.orientationChangeSections, removeIndex)
        dirty = true
    end

    if ImGui.Button(IconGlyphs.Plus .. " Add rotation point") then
        self:addOrientationPoint(0)
    end

    if dirty then
        self:updateCurvePreview()
    end

    ImGui.TreePop()
end

function speedSpline:drawGroundSnapSection()
    if not ImGui.TreeNodeEx("Ground Snap (" .. #self.roadAdjustmentFactorChangeSections .. ")###groundSnap", ImGuiTreeNodeFlags.SpanFullWidth) then
        return
    end

    style.mutedText("Ignore Terrain")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.speedPropertyWidth + ImGui.GetTreeNodeToLabelSpacing())
    self.ignoreTerrain = style.trackedCheckbox(self.object, "##ignoreTerrain", self.ignoreTerrain)
    style.tooltip("When enabled, the spline no longer snaps its height to the terrain / road below it.")

    ImGui.Spacing()
    style.mutedText("Adjusts how strongly the spline snaps to the ground at specific positions.\n1 = fully snapped, 0 = keep the spline height.")
    ImGui.Spacing()

    local fieldStartX = getRowFieldStartX()
    local removeIndex = nil

    for index, section in ipairs(self.roadAdjustmentFactorChangeSections) do
        beginTableRow("roadSection", index .. ".", fieldStartX)

        section.pos = positionCell(self, "##pos", section.pos, " m")
        style.tooltip("Position where this ground-snap strength is applied (m along the spline).")

        ImGui.SameLine()
        section.factor = field.advancedTrackedFloat(self.object, "##factor", section.factor, { min = 0, max = 1, step = 0.01, format = "%.2f", suffix = " snap", width = 80 })
        style.tooltip("Ground snap blend factor. 1 = fully snapped to the ground, 0 = keep the spline's own height.")

        if drawRowDeleteButton() then
            removeIndex = index
        end

        ImGui.PopID()
    end

    if removeIndex then
        self:recordStructuralChange()
        table.remove(self.roadAdjustmentFactorChangeSections, removeIndex)
    end

    if ImGui.Button(IconGlyphs.Plus .. " Add ground-snap point") then
        self:addRoadPoint(0, 1)
    end

    ImGui.TreePop()
end

---Whether the speed range at `index` overlaps any other speed range (ranges must be disjoint).
---@param index number
---@return boolean
function speedSpline:speedRangeOverlaps(index)
    local section = self.speedChangeSections[index]
    if not section then return false end

    local aStart = math.min(section.start, section.endPos)
    local aEnd = math.max(section.start, section.endPos)
    for otherIndex, other in ipairs(self.speedChangeSections) do
        if otherIndex ~= index then
            local bStart = math.min(other.start, other.endPos)
            local bEnd = math.max(other.start, other.endPos)
            if aStart < bEnd and bStart < aEnd then
                return true
            end
        end
    end
    return false
end

---Draws the editable inputs for the timeline-selected event of a given track on a single inline
---row (to save vertical space). Reuses the same tracked fields as the sections, so edits share
---undo history. Deletion is handled by the timeline's right-click context menu, not here.
---@param track string "speed" | "rotation" | "groundSnap"
---@param index number Index within that track's section array.
---@return boolean stillSelected False when the event no longer exists (out of range).
function speedSpline:drawTimelineEventEditor(track, index)
    if track == "speed" then
        local section = self.speedChangeSections[index]
        if not section then return false end

        ImGui.AlignTextToFramePadding()
        style.mutedText(string.format("S%d", index))

        ImGui.SameLine()
        local maxPos = self:getMaxPosition()
        section.start = field.advancedTrackedFloat(self.object, "##evSpeedStart", section.start, { min = 0, max = maxPos, step = 0.1, format = "%.2f", suffix = " start", width = 86 })
        style.tooltip("Distance where the speed change begins (m along the spline).")

        ImGui.SameLine()
        section.endPos = field.advancedTrackedFloat(self.object, "##evSpeedEnd", section.endPos, { min = 0, max = maxPos, step = 0.1, format = "%.2f", suffix = " end", width = 86 })
        style.tooltip("Distance where the target speed is fully reached. A shorter range means a quicker change.")

        ImGui.SameLine()
        section.speed = field.advancedTrackedFloat(self.object, "##evSpeedValue", section.speed, { min = 0, max = 1000, step = 0.1, format = "%.2f", suffix = " m/s", width = 90 })
        style.tooltip("Target speed reached at the end of this range, in meters per second.")

        ImGui.SameLine()
        style.mutedText(string.format("(%s)", settings.formatSpeed(section.speed)))

        if self:speedRangeOverlaps(index) then
            ImGui.SameLine()
            style.pushStyleColor(true, ImGuiCol.Text, style.warnColor)
            ImGui.Text(IconGlyphs.Alert .. " overlaps")
            style.popStyleColor(true)
            style.tooltip("This range overlaps another one. Speed ranges must not overlap.")
        end

    elseif track == "rotation" then
        local section = self.orientationChangeSections[index]
        if not section then return false end
        local dirty = false

        ImGui.AlignTextToFramePadding()
        style.mutedText(string.format("R%d", index))

        ImGui.SameLine()
        local previousPos = section.pos
        section.pos = positionCell(self, "##evRotPos", section.pos, " m")
        style.tooltip("Position where this orientation is applied (m along the spline).")
        if section.pos ~= previousPos then dirty = true end

        ImGui.SameLine()
        local modeIndex = orientationModeIndexByValue[section.mode] or 1
        local newModeIndex, modeChanged = style.trackedCombo(self.object, "##evRotMode", modeIndex - 1, orientationModeLabels, 168, {
            tooltip = getOrientationMode(section.mode).tooltip
        })
        if modeChanged then
            section.mode = orientationModes[newModeIndex + 1].value
            dirty = true
        end

        local axes = getOrientationMode(section.mode).axes
        local changedP, changedY, changedR
        if axes.pitch then
            ImGui.SameLine()
            section.pitch, changedP = field.advancedTrackedFloat(self.object, "##evRotPitch", section.pitch, { min = -360, max = 360, step = 0.5, format = "%.1f", suffix = " P", width = 60 })
            style.tooltip("Overridden pitch, in degrees.")
        end
        if axes.yaw then
            ImGui.SameLine()
            section.yaw, changedY = field.advancedTrackedFloat(self.object, "##evRotYaw", section.yaw, { min = -360, max = 360, step = 0.5, format = "%.1f", suffix = " Y", width = 60 })
            style.tooltip("Overridden yaw, in degrees.")
        end
        if axes.roll then
            ImGui.SameLine()
            section.roll, changedR = field.advancedTrackedFloat(self.object, "##evRotRoll", section.roll, { min = -360, max = 360, step = 0.5, format = "%.1f", suffix = " R", width = 60 })
            style.tooltip("Overridden roll, in degrees.")
        end
        if changedP or changedY or changedR then dirty = true end

        if dirty then
            self:updateCurvePreview()
        end

    elseif track == "groundSnap" then
        local section = self.roadAdjustmentFactorChangeSections[index]
        if not section then return false end

        ImGui.AlignTextToFramePadding()
        style.mutedText(string.format("G%d", index))

        ImGui.SameLine()
        section.pos = positionCell(self, "##evGroundPos", section.pos, " m")
        style.tooltip("Position where this ground-snap strength is applied (m along the spline).")

        ImGui.SameLine()
        section.factor = field.advancedTrackedFloat(self.object, "##evGroundFactor", section.factor, { min = 0, max = 1, step = 0.01, format = "%.2f", suffix = " snap", width = 90 })
        style.tooltip("Ground snap blend factor. 1 = fully snapped to the ground, 0 = keep the spline's own height.")
    else
        return false
    end

    -- Inline delete button (a second path alongside the timeline's right-click delete). Safe to
    -- mutate here: the editor panel is drawn after the canvas, so no section list is being iterated.
    ImGui.SameLine()
    if style.dangerButton(IconGlyphs.DeleteOutline) then
        self:removeTimelineEvent(track, index)
        return false
    end
    style.tooltip("Delete this point")

    return true
end

function speedSpline:save()
    local data = spline.save(self)

    data.speedChangeSections = utils.deepcopy(self.speedChangeSections)
    data.orientationChangeSections = utils.deepcopy(self.orientationChangeSections)
    data.roadAdjustmentFactorChangeSections = utils.deepcopy(self.roadAdjustmentFactorChangeSections)
    data.ignoreTerrain = self.ignoreTerrain

    return data
end

function speedSpline:export()
    local data = spline.export(self)
    data.type = "worldSpeedSplineNode"

    local speedChangeSections = {}
    for _, section in ipairs(self.speedChangeSections) do
        table.insert(speedChangeSections, {
            ["$type"] = "worldSpeedSplineNodeSpeedChangeSection",
            ["start"] = section.start,
            ["end"] = section.endPos,
            ["targetSpeed_M_P_S"] = section.speed
        })
    end

    local orientationChangeSections = {}
    for _, section in ipairs(self.orientationChangeSections) do
        table.insert(orientationChangeSections, {
            ["$type"] = "worldSpeedSplineNodeOrientationChangeSection",
            ["pos"] = section.pos,
            ["type"] = section.mode,
            ["targetOrientation"] = {
                ["$type"] = "EulerAngles",
                ["Pitch"] = section.pitch,
                ["Yaw"] = section.yaw,
                ["Roll"] = section.roll
            }
        })
    end

    local roadAdjustmentFactorChangeSections = {}
    for _, section in ipairs(self.roadAdjustmentFactorChangeSections) do
        table.insert(roadAdjustmentFactorChangeSections, {
            ["$type"] = "worldSpeedSplineNodeRoadAdjustmentFactorChangeSection",
            ["pos"] = section.pos,
            ["targetFactor"] = section.factor
        })
    end

    data.data.speedChangeSections = speedChangeSections
    data.data.orientationChangeSections = orientationChangeSections
    data.data.roadAdjustmentFactorChangeSections = roadAdjustmentFactorChangeSections
    data.data.ignoreTerrain = self.ignoreTerrain and 1 or 0

    return data
end

return speedSpline
