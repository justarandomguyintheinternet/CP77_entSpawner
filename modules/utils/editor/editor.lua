local utils = require("modules/utils/utils")
local input = require("modules/utils/input")
local intersection = require("modules/utils/editor/intersection")
local settings = require("modules/utils/settings")
local visualizer = require("modules/utils/visualizer")
local history = require("modules/utils/history")
local style = require("modules/ui/style")

---@class editor
---@field active boolean
---@field camera camera?
---@field baseUI baseUI?
---@field spawnedUI spawnedUI?
---@field spawnUI spawnUI?
---@field suspendState boolean
---@field hoveredArrow string
---@field currentAxis string
---@field originalDiff table?
---@field grab boolean
---@field rotate boolean
---@field scale boolean
---@field dragging boolean
---@field originalPosition Vector4?
---@field originalRotation EulerAngles?
---@field originalScale Vector4?
---@field interface gamestateMachineGameScriptInterface?
---@field depthSelectElements table
---@field depthSelectOpen boolean
---@field depthElementsMaxWidth number
---@field boxSelectActive boolean
---@field boxSelectStart table
---@field freeflyWasActive boolean
local editor = {
    active = false,
    camera = nil,
    baseUI = nil,
    spawnedUI = nil,
    spawnUI = nil,
    suspendState = false,
    hoveredArrow = "none",
    currentAxis = "none",
    originalDiff = {pos = nil, rot = nil, scale = nil},
    dragging = false,
    grab = false,
    rotate = false,
    scale = false,
    originalPosition = nil,
    originalRotation = nil,
    originalScale = nil,
    interface = nil,
    depthSelectElements = {},
    depthSelectOpen = false,
    depthElementsMaxWidth = 0,
    boxSelectActive = false,
    boxSelectStart = { x = 0, y = 0 },

    freeflyWasActive = false
}

function viewportFocused()
    return editor.active and input.context.viewport.focused
end

function viewportHovered()
    return editor.active and input.context.viewport.hovered
end

function editor.cancleEditingTransform()
    editor.grab = false
    editor.rotate = false
    editor.scale = false

    local element = editor.getSelected()
    if not element or editor.currentAxis == "none" then return end
    editor.currentAxis = "none"
    element:setPosition(editor.originalPosition)
    element:setRotation(editor.originalRotation)
    element:setScale(editor.originalScale, true)

    editor.originalDiff.pos = nil
    editor.originalDiff.rot = nil
    editor.originalDiff.scale = nil
    input.trackNumeric(false)
end

function editor.confirmEditingTransform()
    if not editor.grab and not editor.rotate and not editor.scale and editor.hoveredArrow == "none" and not editor.spawnUI.popupSpawnHit then
        editor.setTarget()
    end

    if editor.grab or editor.rotate or editor.scale then
        editor.recordChange()
    end

    editor.grab = false
    editor.rotate = false
    editor.scale = false
    editor.currentAxis = "none"
    input.trackNumeric(false)
end

function editor.init(spawner)
    editor.baseUI = spawner.baseUI
    editor.spawnedUI = spawner.baseUI.spawnedUI
    editor.spawnUI = spawner.baseUI.spawnUI

    editor.camera = require("modules/utils/editor/camera")

    input.registerMouseAction(ImGuiMouseButton.Right, function()
        editor.cancleEditingTransform()
    end, viewportHovered)
    input.registerMouseAction(ImGuiMouseButton.Left, function ()
        editor.confirmEditingTransform()
    end,
    function ()
        return editor.active and input.context.viewport.hovered
    end)

    input.registerImGuiHotkey({ ImGuiKey.Escape }, function()
        editor.cancleEditingTransform()
    end, viewportHovered)
    input.registerImGuiHotkey({ ImGuiKey.Enter }, function ()
        editor.confirmEditingTransform()
    end,
    function ()
        return editor.active and input.context.viewport.hovered
    end)

    input.registerImGuiHotkey({ ImGuiKey.Tab }, editor.centerCamera, function ()
        return editor.active and (input.context.viewport.focused or input.context.hierarchy.focused)
    end)

    input.registerImGuiHotkey({ ImGuiKey.G }, function ()
        editor.toggleTransform("translate") -- TODO: CTRL-G somehow can enable this for groups
    end, viewportHovered)

    input.registerImGuiHotkey({ ImGuiKey.R }, function ()
        if ImGui.IsKeyDown(ImGuiKey.LeftCtrl) then
            return
        end
        editor.toggleTransform("rotate")
    end, viewportHovered)

    input.registerImGuiHotkey({ ImGuiKey.S }, function ()
        editor.toggleTransform("scale")
    end, viewportHovered)

    input.registerImGuiHotkey({ ImGuiKey.X }, function ()
        if not (editor.grab or editor.rotate or editor.scale) then return end

        if ImGui.IsKeyDown(ImGuiKey.LeftShift) and not editor.rotate then
            editor.currentAxis = "yz"
        else
            editor.currentAxis = "x"
        end
        editor.updateArrowColor()
        editor.updateCurrentAxis()
    end, viewportHovered)

    input.registerImGuiHotkey({ ImGuiKey.Y }, function ()
        if not (editor.grab or editor.rotate or editor.scale) then return end

        if ImGui.IsKeyDown(ImGuiKey.LeftShift) and not editor.rotate then
            editor.currentAxis = "xz"
        else
            editor.currentAxis = "y"
        end
        editor.updateArrowColor()
        editor.updateCurrentAxis()
    end, viewportHovered)

    input.registerImGuiHotkey({ ImGuiKey.Z }, function ()
        if not (editor.grab or editor.rotate or editor.scale) then return end

        if ImGui.IsKeyDown(ImGuiKey.LeftShift) and not editor.rotate then
            editor.currentAxis = "xy"
        else
            editor.currentAxis = "z"
        end
        editor.updateArrowColor()
        editor.updateCurrentAxis()
    end, viewportHovered)

    input.registerImGuiHotkey({ ImGuiKey.LeftShift, ImGuiKey.D }, function ()
        local ray = editor.getScreenToWorldRay()
        local hit = editor.getRaySceneIntersection(ray, GetPlayer():GetFPPCameraComponent():GetLocalToWorld():GetTranslation(), false)

        if #hit.allHits == 0 then
            editor.depthSelectOpen = false
            return
        end

        editor.depthSelectOpen = true
        editor.depthSelectElements = hit.allHits
        table.sort(editor.depthSelectElements, function (a, b)
            return a.distance < b.distance
        end)

        local max = 0
        for _, hit in pairs(editor.depthSelectElements) do
            local x, _ = ImGui.CalcTextSize(string.format("[%.2f m]", hit.distance))
            max = math.max(max, x)
        end

        editor.depthElementsMaxWidth = max
    end, viewportHovered)

    input.registerImGuiHotkey({ ImGuiKey.A, ImGuiKey.LeftShift }, function ()
        editor.baseUI.spawnUI.openPopup = true
    end, viewportHovered)

    input.registerImGuiHotkey({ ImGuiKey.LeftCtrl, ImGuiKey.R }, function ()
        editor.baseUI.spawnUI.repeatLastSpawn()
    end, viewportHovered)

    Observe("LocomotionEventsTransition", "OnUpdate", function(_, _, _, interface)
        editor.interface = interface
    end)
end

function editor.getSelected()
    editor.spawnedUI.cachePaths()

    if #editor.spawnedUI.selectedPaths == 0 then return end

    if #editor.spawnedUI.selectedPaths == 1 then
        if utils.isA(editor.spawnedUI.selectedPaths[1].ref, "positionable") then
            return editor.spawnedUI.selectedPaths[1].ref
        end
    else
        return editor.spawnedUI.multiSelectGroup
    end
end

function editor.centerCamera()
    if not editor.spawnedUI.selectedPaths[1] and editor.active then return end

    local singleTarget = editor.spawnedUI.selectedPaths[1].ref

    local pos = Vector4.new(singleTarget:getPosition())
    if utils.isA(singleTarget, "spawnableElement") then
        pos = Vector4.new(singleTarget.spawnable:getCenter())
    end

    if utils.distanceVector(pos, singleTarget:getPosition()) > 25 then
        pos = Vector4.new(singleTarget:getPosition())
    end

    local distance
    if #editor.spawnedUI.selectedPaths > 1 then
        pos = Vector4.new(spawnedUI.multiSelectGroup:getPosition())
        distance = editor.camera.distance
    elseif utils.isA(singleTarget, "spawnableElement") then -- Single spawnableElement
        local size = singleTarget.spawnable:getSize()
        distance = math.min(10, math.max(size.x, size.y, size.z, 1) * 2)
    else -- Single positionableGroup
        distance = editor.camera.distance
    end

    pos.z = pos.z - 1.5
    editor.camera.transition(editor.camera.cameraTransform.position, pos, editor.camera.cameraTransform.rotation, editor.camera.cameraTransform.rotation, distance, 0.5)
end

function editor.removeHighlight(onlySelected)
    local paths = onlySelected and editor.spawnedUI.selectedPaths or editor.spawnedUI.paths

    for _, selected in pairs(paths) do
        if utils.isA(selected.ref, "spawnableElement") then
            selected.ref.spawnable:setOutline(0)
        end
    end
end

function editor.addHighlightToSelected()
    for _, selected in pairs(editor.spawnedUI.selectedPaths) do
        if utils.isA(selected.ref, "spawnableElement") then
            selected.ref.spawnable:setOutline(settings.outlineColor + 1)
        end
    end
end

---Gets a ray pointing from the screen into the scene, using mouse position as default
---@param x number?
---@param y number?
---@return Vector4
function editor.getScreenToWorldRay(x, y)
    if not x or not y then
        x, y = ImGui.GetMousePos()
    end
    local width, height = GetDisplayResolution()
    local _, ray = editor.camera.screenToWorld((x / width * 2) - 1, - ((y / height * 2) - 1))

    return ray:Normalize()
end

function editor.getRaySceneIntersection(ray, origin, excludeSpawnable, usePhysical)
    local hits = {}

    for _, element in pairs(editor.spawnedUI.paths) do
        if element.ref.visible and utils.isA(element.ref, "spawnableElement") then
            local hit = element.ref.spawnable:calculateIntersection(origin, ray)

            if hit.hit and (not excludeSpawnable or (excludeSpawnable and element.ref.spawnable ~= excludeSpawnable)) then
                hit.element = element.ref
                table.insert(hits, hit)
            end
        end
    end

    local raycast = editor.interface:RaycastWithASingleGroup(origin, utils.addVector(origin, utils.multVector(ray, 9999)), "PlayerBlocker")

    if #hits == 0 then
        if raycast:IsValid() then
            return {
                result = {
                    position = Vector4.Vector3To4(raycast.position),
                    normal = Vector4.Vector3To4(raycast.normal)
                },
                isNode = false,
                hit = true,
                allHits = hits
            }
        end

        return { hit = false, isNode = false, allHits = hits }
    end

    table.sort(hits, function (a, b)
        return a.distance < b.distance
    end)

    -- If there is a hit inside the primary hit, use that one instead (To prefer things inside the bbox of the primary hit, can often be the case)
    local bestHitIdx = 1
    while bestHitIdx + 1 <= #hits and intersection.BBoxInsideBBox(hits[bestHitIdx].objectOrigin, hits[bestHitIdx].objectRotation, hits[bestHitIdx].bBox, hits[bestHitIdx + 1].objectOrigin, hits[bestHitIdx + 1].objectRotation, intersection.scaleBBox(hits[bestHitIdx + 1].bBox, Vector4.new(0.85, 0.85, 0.85))) do
        bestHitIdx = bestHitIdx + 1
    end
    bestHitIdx = math.min(bestHitIdx, #hits)

    if raycast:IsValid() and usePhysical then
        local distance = Vector4.Vector3To4(raycast.position):Distance(origin)

        if distance + 0.1 < hits[bestHitIdx].distance or distance < 0.1 then
            return {
                result = {
                    position = Vector4.Vector3To4(raycast.position),
                    normal = Vector4.Vector3To4(raycast.normal)
                },
                isNode = false,
                hit = true,
                allHits = hits
            }
        end
    end

    return {
        result = hits[bestHitIdx],
        isNode = true,
        hit = true,
        allHits = hits
    }
end

function editor.setTarget()
    local ray = editor.getScreenToWorldRay()
    local hit = editor.getRaySceneIntersection(ray, GetPlayer():GetFPPCameraComponent():GetLocalToWorld():GetTranslation(), false)
    if not hit.hit or (not hit.isNode and #hit.allHits == 0) then return end -- or not hit.isNode | for now allow selecing through physical objects

    hit = hit.result

    if not editor.spawnedUI.multiSelectActive() then
        editor.spawnedUI.unselectAll()
    end

    if hit.element.selected then
        hit.element:setSelected(false)
    else
        hit.element:expandAllParents()
        editor.spawnedUI.scrollToSelected = true
        hit.element:setSelected(true)
        editor.spawnedUI.cachePaths()
        editor.addHighlightToSelected()
    end
end

function editor.updateArrowColor()
    local selected = editor.getSelected()

    if not selected or not utils.isA(selected, "spawnableElement") then return end

    visualizer.highlightArrow(selected.spawnable:getEntity(), editor.currentAxis)
end

function editor.updateCurrentAxis()
    if not editor.grab and not editor.rotate and not editor.scale then return end

    if editor.currentAxis ~= "none" then
        local element = editor.getSelected()
        if not element then return end

        element:setPosition(editor.originalPosition)
        element:setRotation(editor.originalRotation)
        if editor.scale then
            element:setScale(editor.originalScale, false) -- Avoid updating unless necessary, to fix flickering with e.g. colliders
        end

        -- Might remove this, makes things snap to cursor instantly (might be good, might be bad)
        editor.originalDiff.pos = nil
        editor.originalDiff.rot = nil
        editor.originalDiff.scale = nil
    end
end

function editor.toggleTransform(transformationType)
    if editor.currentAxis ~= "none" then return end

    local selected = editor.getSelected()

    if selected and utils.isA(selected, "positionable") then
        editor.grab = transformationType == "translate" and true or false
        editor.rotate = transformationType == "rotate" and true or false

        if transformationType == "scale" and not selected.hasScale then
            return
        elseif transformationType == "scale" then
            editor.scale = true
        end

        editor.originalPosition = Vector4.new(selected:getPosition())
        editor.originalRotation = EulerAngles.new(selected:getRotation())
        editor.originalScale = Vector4.new(selected:getScale())
        editor.currentAxis = "all"
        editor.updateArrowColor()
        input.trackNumeric(true)
    end
end

function editor.recordChange()
    local element = editor.getSelected()
    local newPosition = Vector4.new(element:getPosition())
    local newRotation = EulerAngles.new(element:getRotation())
    local newScale = Vector4.new(element:getScale())

    element:setPosition(editor.originalPosition)
    element:setRotation(editor.originalRotation)
    element:setScale(editor.originalScale, false)
    if utils.isA(element, "spawnableElement") then
        history.addAction(history.getElementChange(element))
    else
        history.addAction(history.getMultiSelectChange(element.childs))
    end
    element:setPosition(newPosition)
    element:setRotation(newRotation)
    element:setScale(newScale, true)
    element:onEdited()

    editor.originalDiff.pos = nil
    editor.originalDiff.rot = nil
    editor.originalDiff.scale = nil
end

function editor.checkArrow()
    if #editor.spawnedUI.selectedPaths ~= 1 or editor.currentAxis ~= "none" then
        editor.hoveredArrow = "none"
        return
    end

    if ImGui.IsMouseDragging(0, 0.5) then
        return
    end

    local selected = editor.spawnedUI.selectedPaths[1].ref.spawnable
    if not selected or not selected:isSpawned() then return end

    local ray = editor.getScreenToWorldRay()
    local arrowWidth = 0.04 * math.max(selected:getArrowSize().x, selected:getArrowSize().y, selected:getArrowSize().z)

    local xHit = intersection.getBoxIntersection(GetPlayer():GetFPPCameraComponent():GetLocalToWorld():GetTranslation(), ray, selected.position, selected.rotation, {
        min = { x = 0, y = -arrowWidth, z = -arrowWidth },
        max = { x = selected:getArrowSize().x * 2, y = arrowWidth, z = arrowWidth }
    })

    local yHit = intersection.getBoxIntersection(GetPlayer():GetFPPCameraComponent():GetLocalToWorld():GetTranslation(), ray, selected.position, selected.rotation, {
        min = { x = -arrowWidth, y = 0, z = -arrowWidth },
        max = { x = arrowWidth, y = selected:getArrowSize().y * 2, z = arrowWidth }
    })

    local zHit = intersection.getBoxIntersection(GetPlayer():GetFPPCameraComponent():GetLocalToWorld():GetTranslation(), ray, selected.position, selected.rotation, {
        min = { x = -arrowWidth, y = -arrowWidth, z = 0 },
        max = { x = arrowWidth, y = arrowWidth, z = selected:getArrowSize().z * 2 }
    })

    if zHit.hit then
        editor.hoveredArrow = "z"
    elseif xHit.hit then
        editor.hoveredArrow = "x"
    elseif yHit.hit then
        editor.hoveredArrow = "y"
    else
        editor.hoveredArrow = "none"
    end

    visualizer.highlightArrow(selected:getEntity(), editor.hoveredArrow)
end

function editor.getScreenRelativeToPoint(position)
    local cam = GetPlayer():GetFPPCameraComponent():GetLocalToWorld():GetTranslation()
    local normal = GetPlayer():GetFPPCameraComponent():GetLocalToWorld():GetRotation():GetForward()
    normal.x = -normal.x
    normal.y = -normal.y
    normal.z = -normal.z

    local hit = intersection.getPlaneIntersection(cam, editor.getScreenToWorldRay(), position, normal)
    local dir = utils.subVector(hit.position, position)

    local diff = Quaternion.MulInverse(EulerAngles.new(0, 0, 0):ToQuat(), GetPlayer():GetFPPCameraComponent():GetLocalToWorld():GetRotation():ToQuat())

    return diff:Transform(dir)
end

function editor.updateDrag()
    local dragging = ImGui.IsMouseDragging(0, 0.5) and not (editor.grab or editor.rotate or editor.scale)
    if dragging then
        if editor.hoveredArrow ~= "none" then
            editor.currentAxis = editor.hoveredArrow
        end
    elseif not editor.grab and not editor.rotate and not editor.scale then
        if editor.currentAxis ~= "none" then
            editor.recordChange()
        end

        editor.currentAxis = "none"
    end

    if editor.currentAxis == "none" then return end

    ---@type positionable
    local selected = editor.getSelected()

    if not selected then
        editor.currentAxis = "none"
        return
    end

    local rotation = selected:getRotation()
    local position = selected:getPosition()
    local scale = selected:getScale()

    local axis = {
        x = { mult = 0, dir = rotation:GetRight() },
        y = { mult = 0, dir = rotation:GetForward() },
        z = { mult = 0, dir = rotation:GetUp() },
    }

    if editor.currentAxis:find("x") then
        axis.x.mult = 1
    end
    if editor.currentAxis:find("y") then
        axis.y.mult = 1
    end
    if editor.currentAxis:find("z") then
        axis.z.mult = 1
    end

    if editor.currentAxis == "all" and editor.scale then
        axis.x.mult = 1
        axis.y.mult = 1
        axis.z.mult = 1
    end

    local offset = Vector4.new(0, 0, 0, 0)
    for key, data in pairs(axis) do
        if data.mult ~= 0 then
            local t, _ = intersection.getTClosestToRay(position, data.dir, GetPlayer():GetFPPCameraComponent():GetLocalToWorld():GetTranslation(), editor.getScreenToWorldRay())
            offset[key] = t
        end
    end

    local diff = rotation:ToQuat():Transform(offset)

    if not editor.originalDiff.pos then
        editor.originalDiff.pos = diff

        editor.originalPosition = Vector4.new(position)
        editor.originalRotation = EulerAngles.new(rotation)
        editor.originalScale = Vector4.new(scale)
    end

    if editor.grab or dragging then
        selected:setPositionDelta(Vector4.new(diff.x - editor.originalDiff.pos.x, diff.y - editor.originalDiff.pos.y, diff.z - editor.originalDiff.pos.z))
    elseif editor.rotate then
        local dir = editor.getScreenRelativeToPoint(position):Normalize()
        local angle = math.atan2(dir.z, dir.x) * 180 / math.pi

        if not editor.originalDiff.rot then
            editor.originalDiff.rot = angle
        end

        local original = EulerAngles.new(editor.originalRotation)
        original.pitch = original.pitch + (angle - editor.originalDiff.rot + input.getNumeric(0)) * axis.x.mult
        original.roll = original.roll + (angle - editor.originalDiff.rot + input.getNumeric(0)) * axis.y.mult
        original.yaw = original.yaw + (angle - editor.originalDiff.rot + input.getNumeric(0)) * axis.z.mult

        selected:setRotation(original)
    elseif editor.scale then
        local distance = Vector4.Length(editor.getScreenRelativeToPoint(position))

        if not editor.originalDiff.scale then
            editor.originalDiff.scale = distance
        end

        local original = Vector4.new(editor.originalScale)
        original.x = (original.x * (axis.x.mult == 1 and input.getNumeric(1) or 1)) + (distance - editor.originalDiff.scale) * axis.x.mult
        original.y = (original.y * (axis.y.mult == 1 and input.getNumeric(1) or 1)) + (distance - editor.originalDiff.scale) * axis.y.mult
        original.z = (original.z * (axis.z.mult == 1 and input.getNumeric(1) or 1)) + (distance - editor.originalDiff.scale) * axis.z.mult

        selected:setScale(original, false)
    end
end

function editor.getForward(distance)
    local forward = GetPlayer():GetFPPCameraComponent():GetLocalToWorld():GetRotation():GetForward()
    local relativeForward = Vector4.new(0, 1, 0, 0)

    if editor.active then
        local screenWidth, _ = GetDisplayResolution()
        local x = (screenWidth - settings.editorWidth) / 2

        relativeForward, adjusted = editor.camera.screenToWorld((x / screenWidth * 2) - 1, 0)
        adjusted = adjusted:Normalize()
        distance = distance / math.cos(math.rad(Vector4.GetAngleBetween(forward, adjusted)))
        forward = adjusted
    end

    local position = GetPlayer():GetFPPCameraComponent():GetLocalToWorld():GetTranslation()

    return utils.addVector(position, utils.multVector(forward, distance)), relativeForward
end

function editor.drawDepthSelect()
    if not editor.active or not editor.depthSelectOpen then return end

    local x, y = ImGui.GetMousePos()
    ImGui.SetNextWindowPos(x + 10 * style.viewSize, y + 10 * style.viewSize, ImGuiCond.Appearing)

    ImGui.PushStyleColor(ImGuiCol.TitleBgActive, 0, 0, 0, 1)
    editor.depthSelectOpen = ImGui.Begin("Depth Selection", true, ImGuiWindowFlags.NoResize + ImGuiWindowFlags.AlwaysAutoResize + ImGuiWindowFlags.NoCollapse)
    editor.depthSelectOpen = editor.depthSelectOpen and ImGui.IsWindowFocused(ImGuiHoveredFlags.ChildWindows)
    ImGui.PopStyleColor()

    if editor.depthSelectOpen then
        for _, hit in pairs(editor.depthSelectElements) do
            style.mutedText(string.format("[%.2f m]", hit.distance))

            ImGui.SameLine(editor.depthElementsMaxWidth + 10 * style.viewSize)

            if ImGui.Selectable(hit.element.name, false) then
                editor.spawnedUI.unselectAll()
                hit.element:setSelected(true)
                editor.depthSelectOpen = false
            end
        end

        ImGui.End()
    end
end

---@param entry spawnable
local function calculateSpawnableCorners(entry)
    local bBox = entry:getBBox()

    local corners = {
        Vector4.new(bBox.min.x, bBox.min.y, bBox.min.z, 1),
        Vector4.new(bBox.min.x, bBox.min.y, bBox.max.z, 1),
        Vector4.new(bBox.min.x, bBox.max.y, bBox.min.z, 1),
        Vector4.new(bBox.min.x, bBox.max.y, bBox.max.z, 1),
        Vector4.new(bBox.max.x, bBox.min.y, bBox.min.z, 1),
        Vector4.new(bBox.max.x, bBox.min.y, bBox.max.z, 1),
        Vector4.new(bBox.max.x, bBox.max.y, bBox.min.z, 1),
        Vector4.new(bBox.max.x, bBox.max.y, bBox.max.z, 1)
    }

    for key, corner in pairs(corners) do
        corners[key] = utils.addVector(entry.position, entry.rotation:ToQuat():Transform(corner))
    end

    return corners
end

function editor.handleBoxSelect()
    if not editor.active then return end

    local x, y = ImGui.GetMousePos()
    if ImGui.IsKeyDown(ImGuiKey.LeftCtrl) and ImGui.IsMouseDragging(0, 0.6) and not editor.boxSelectActive and input.context.viewport.hovered then
        editor.boxSelectActive = true
        editor.boxSelectStart = { x = x, y = y }
        editor.spawnedUI.unselectAll()
    elseif not ImGui.IsMouseDragging(0, 0.6) and editor.boxSelectActive then
        editor.boxSelectActive = false

        local width, height = GetDisplayResolution()
        local min = { x = math.min(editor.boxSelectStart.x, x), y = math.min(editor.boxSelectStart.y, y) }
        local max = { x = math.max(editor.boxSelectStart.x, x), y = math.max(editor.boxSelectStart.y, y) }

        for _, element in pairs(editor.spawnedUI.paths) do
            if element.ref.visible and utils.isA(element.ref, "spawnableElement") then
                local inside = true
                for _, corner in pairs(calculateSpawnableCorners(element.ref.spawnable)) do
                    local xCorner, yCorner = editor.camera.worldToScreen(corner)
                    xCorner, yCorner = (xCorner + 1) * width / 2, (- yCorner + 1) * height / 2

                    if xCorner < min.x or xCorner > max.x or yCorner < min.y or yCorner > max.y then
                        inside = false
                        break
                    end
                end

                if inside then
                    element.ref:setSelected(true)
                end
            end
        end
    end

    if editor.boxSelectActive then
        ImGui.SetNextWindowPos(math.min(editor.boxSelectStart.x, x), math.min(editor.boxSelectStart.y, y), ImGuiCond.Always)
        ImGui.SetNextWindowSize(math.abs(x - editor.boxSelectStart.x), math.abs(y - editor.boxSelectStart.y))

        ImGui.PushStyleVar(ImGuiStyleVar.WindowMinSize, 0, 0)
        ImGui.PushStyleColor(ImGuiCol.WindowBg, 0, 0, 0, 0.1)
        editor.boxSelectActive = ImGui.Begin("##boxSelect", ImGuiWindowFlags.NoResize + ImGuiWindowFlags.NoMove + ImGuiWindowFlags.NoTitleBar + ImGuiWindowFlags.NoCollapse)
        ImGui.PopStyleColor()
        ImGui.PopStyleVar()
    end
end

function editor.onDraw()
    editor.camera.update()

    if editor.active and input.context.viewport.hovered then
        editor.checkArrow()
        editor.updateDrag()
        editor.drawDepthSelect()
        editor.handleBoxSelect()
    end
end

function editor.suspend(state)
    if editor.active and not state and not editor.suspendState then
        editor.suspendState = true
        editor.toggle(false)
    elseif not editor.active and state and editor.suspendState then
        editor.suspendState = false
        editor.toggle(true)
    end
end

function editor.toggle(state)
    local freefly = GetMod("freefly")

    if freefly then
        if state and freefly.runtimeData.active then
            freefly.runtimeData.active = false
            freefly.logic.toggleFlight(freefly, freefly.runtimeData.active)
            editor.freeflyWasActive = true
        elseif not state and editor.freeflyWasActive then
            freefly.runtimeData.active = true
            freefly.logic.toggleFlight(freefly, freefly.runtimeData.active)
            editor.freeflyWasActive = false
        end
    end

    editor.active = state
    editor.camera.toggle(state)
    editor.baseUI.loadTabSize = true

    if not state then
        editor.baseUI.restoreWindowPosition = true
        editor.removeHighlight(false)
        editor.currentAxis = "none"
        editor.hoveredArrow = "none"
        editor.grab = false
        Game.GetStatsSystem():RemoveModifier(GetPlayer():GetEntityID(), RPGManager.CreateStatModifier(gamedataStatType.KnockdownImmunity, gameStatModifierType.Additive, 1))
    else
        Game.GetStatsSystem():AddModifier(GetPlayer():GetEntityID(), RPGManager.CreateStatModifier(gamedataStatType.KnockdownImmunity, gameStatModifierType.Additive, 1))
        editor.addHighlightToSelected()
    end
end

return editor