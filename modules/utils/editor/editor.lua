local utils = require("modules/utils/utils")
local input = require("modules/utils/input")
local intersection = require("modules/utils/editor/intersection")
local settings = require("modules/utils/settings")
local visualizer = require("modules/utils/visualizer")
local history = require("modules/utils/history")

---@class editor
---@field active boolean
---@field camera camera?
---@field baseUI baseUI?
---@field spawnedUI spawnedUI?
---@field spawnUI spawnUI?
---@field suspendState boolean
---@field hoveredArrow string
---@field currentAxis string
---@field dragOriginalDiff number?
---@field grab boolean
---@field rotate boolean
---@field originalPos Vector4?
---@field originalRotation EulerAngles?
local editor = {
    active = false,
    camera = nil,
    baseUI = nil,
    spawnedUI = nil,
    spawnUI = nil,
    suspendState = false,
    hoveredArrow = "none",
    currentAxis = "none",
    dragOriginalDiff = nil,
    grab = false,
    rotate = false,
    originalPos = nil,
    originalRotation = nil
}

function onViewport()
    return editor.active and input.context.viewport.focused
end

function editor.getSelected()
    if #editor.spawnedUI.selectedPaths == 0 then return end

    if #editor.spawnedUI.selectedPaths == 1 then
        return editor.spawnedUI.selectedPaths[1].ref
    else
        return editor.spawnedUI.multiSelectGroup
    end
end

function editor.updateArrowColor()
    local selected = editor.getSelected()

    if not selected or not utils.isA(selected, "spawnableElement") then return end

    visualizer.highlightArrow(selected.spawnable:getEntity(), editor.currentAxis)
end

function editor.updateGrabbedAxis()
    if not editor.grab then return end

    if editor.currentAxis ~= "none" then
        local element = editor.getSelected()
        if not element then return end

        element:setPosition(editor.originalPos)
        editor.dragOriginalDiff = nil
    end
end

function editor.init(spawner)
    editor.baseUI = spawner.baseUI
    editor.spawnedUI = spawner.baseUI.spawnedUI
    editor.spawnUI = spawner.baseUI.spawnUI

    editor.camera = require("modules/utils/editor/camera")

    input.registerMouseAction(ImGuiMouseButton.Right, function()
        editor.grab = false

        local element = editor.getSelected()
        if not element or editor.currentAxis == "none" then return end

        editor.currentAxis = "none"
        element:setPosition(editor.originalPos)
    end, onViewport)

    input.registerMouseAction(ImGuiMouseButton.Left, function ()
        if not editor.grab and editor.hoveredArrow == "none" then
            editor.setTarget()
        end
        editor.grab = false
    end,
    function ()
        return editor.active and input.context.viewport.hovered
    end)

    input.registerImGuiHotkey({ ImGuiKey.Tab }, editor.centerCamera, function ()
        return editor.active and (input.context.viewport.focused or input.context.hierarchy.focused)
    end)

    input.registerImGuiHotkey({ ImGuiKey.G }, function ()
        if editor.currentAxis ~= "none" then return end

        local selected = editor.getSelected()

        if selected and utils.isA(selected, "positionable") then
            editor.grab = true
            editor.originalPos = Vector4.new(selected:getPosition())
        end
    end, onViewport)

    input.registerImGuiHotkey({ ImGuiKey.R }, function ()
        if editor.currentAxis ~= "none" then return end

        local selected = editor.getSelected()

        if selected and utils.isA(selected, "positionable") then
            editor.rotate = true
            editor.originalRotation = EulerAngles.new(selected:getRotation())
        end
    end, onViewport)

    input.registerImGuiHotkey({ ImGuiKey.X }, function ()
        if not (editor.grab or editor.rotate) then return end

        if ImGui.IsKeyDown(ImGuiKey.LeftShift) and not editor.rotate then
            editor.currentAxis = "yz"
        else
            editor.currentAxis = "x"
        end
        editor.updateArrowColor()
        editor.updateGrabbedAxis()
    end, onViewport)

    input.registerImGuiHotkey({ ImGuiKey.Y }, function ()
        if not (editor.grab or editor.rotate) then return end

        if ImGui.IsKeyDown(ImGuiKey.LeftShift) and not editor.rotate then
            editor.currentAxis = "xz"
        else
            editor.currentAxis = "y"
        end
        editor.updateArrowColor()
        editor.updateGrabbedAxis()
    end, onViewport)

    input.registerImGuiHotkey({ ImGuiKey.Z }, function ()
        if not (editor.grab or editor.rotate) then return end

        if ImGui.IsKeyDown(ImGuiKey.LeftShift) and not editor.rotate then
            editor.currentAxis = "xy"
        else
            editor.currentAxis = "z"
        end
        editor.updateArrowColor()
        editor.updateGrabbedAxis()
    end, onViewport)

    --TODO: depth menu
end

function editor.centerCamera()
    if not editor.spawnedUI.selectedPaths[1] and editor.active then return end

    local singleTarget = editor.spawnedUI.selectedPaths[1].ref.spawnable
    local pos = Vector4.new(singleTarget:getCenter())

    if utils.distanceVector(pos, singleTarget.position) > 25 then
        pos = Vector4.new(singleTarget.position)
    end

    local size = singleTarget:getSize()
    local distance = math.min(5, math.max(size.x, size.y, size.z, 1) * 1.35)
    if #editor.spawnedUI.selectedPaths > 1 then
        pos = Vector4.new(spawnedUI.multiSelectGroup:getPosition())
        distance = editor.camera.distance
    end

    pos.z = pos.z - 1.5
    editor.camera.transition(editor.camera.cameraTransform.position, pos, distance, 0.5)
end

function editor.removeHighlight(onlySelected)
    local paths = onlySelected and editor.spawnedUI.selectedPaths or editor.spawnedUI.paths

    for _, selected in pairs(paths) do
        if utils.isA(selected.ref, "spawnableElement") and selected.ref.spawnable:isSpawned() then
            utils.sendOutlineEvent(selected.ref.spawnable:getEntity(), 0)
        end
    end
end

function editor.addHighlightToSelected()
    for _, selected in pairs(editor.spawnedUI.selectedPaths) do
        if utils.isA(selected.ref, "spawnableElement") and selected.ref.spawnable:isSpawned() then
            utils.sendOutlineEvent(selected.ref.spawnable:getEntity(), settings.outlineColor + 1)
        end
    end
end

function editor.getScreenToWorldRay()
    local x, y = ImGui.GetMousePos()
    local width, height = GetDisplayResolution()
    local _, ray = editor.camera.screenToWorld((x / width * 2) - 1, - ((y / height * 2) - 1))

    return ray:Normalize()
end

function editor.setTarget()
    local ray = editor.getScreenToWorldRay()
    local hit = editor.getRaySceneIntersection(ray, GetPlayer():GetFPPCameraComponent():GetLocalToWorld():GetTranslation())
    if not hit then return end

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

function editor.getRaySceneIntersection(ray, origin)
    local hits = {}

    for _, element in pairs(editor.spawnedUI.paths) do
        if element.ref.visible and utils.isA(element.ref, "spawnableElement") then
            local hit = element.ref.spawnable:calculateIntersection(origin, ray)

            if hit.hit then
                hit.element = element.ref
                -- TODO: Modify distance and hit position based on type (keep for physical and shape, make a bit worse for bbox)
                table.insert(hits, hit)
            end
        end
    end

    if #hits == 0 then
        return
    end

    table.sort(hits, function (a, b)
        return a.distance < b.distance
    end)

    for _, hit in pairs(hits) do
        print("Hit: ", hit.position, hit.collisionType, hit.distance, hit.element.spawnable.name)
    end

    -- If there is a hit inside the primary hit, use that one instead (To prefer things inside the bbox of the primary hit, can often be the case)
    -- TODO: Maybe scale bbox of next best hit a bit down
    local bestHitIdx = 1
    while bestHitIdx + 1 <= #hits and intersection.BBoxInsideBBox(hits[bestHitIdx].objectOrigin, hits[bestHitIdx].objectRotation, hits[bestHitIdx].bBox, hits[bestHitIdx + 1].objectOrigin, hits[bestHitIdx + 1].objectRotation, hits[bestHitIdx + 1].bBox) do
        bestHitIdx = bestHitIdx + 1
    end
    bestHitIdx = math.min(bestHitIdx, #hits)

    print("Best hit: ", hits[bestHitIdx].position, hits[bestHitIdx].collisionType, hits[bestHitIdx].distance, hits[bestHitIdx].size)

    return hits[bestHitIdx]
end

function editor.checkArrow()
    editor.hoveredArrow = "none"

    if #editor.spawnedUI.selectedPaths ~= 1 or editor.currentAxis ~= "none" then return end

    local selected = editor.spawnedUI.selectedPaths[1].ref.spawnable
    if not selected:isSpawned() then return end

    local ray = editor.getScreenToWorldRay()
    local arrowWidth = 0.05

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
        visualizer.highlightArrow(selected:getEntity(), "none")
    end

    if editor.hoveredArrow ~= "none" then
        visualizer.highlightArrow(selected:getEntity(), editor.hoveredArrow)
    end
end

-- TODO:
    -- Rotation
    -- Scale
    -- Fix spawned new not selected
    -- Fix hotkeys working when on other main tab / not hierarchy

function editor.updateDrag()
    if ImGui.IsMouseDragging(0, 0) then
        if editor.hoveredArrow ~= "none" then
            editor.currentAxis = editor.hoveredArrow
        end
    elseif not editor.grab then
        if editor.currentAxis ~= "none" then
            local element = editor.getSelected()
            local new = Vector4.new(element:getPosition())
            element:setPosition(editor.originalPos)
            history.addAction(history.getElementChange(element))
            element:setPosition(new)
        end

        editor.currentAxis = "none"
        editor.dragOriginalDiff = nil
    end

    if editor.currentAxis == "none" then return end

    ---@type positionable
    local selected = editor.spawnedUI.selectedPaths[1].ref
    local rotation = selected:getRotation()
    local position = selected:getPosition()

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

    local offset = Vector4.new(0, 0, 0, 0)
    for key, data in pairs(axis) do
        if data.mult ~= 0 then
            local t, _ = intersection.getTClosestToRay(position, data.dir, GetPlayer():GetFPPCameraComponent():GetLocalToWorld():GetTranslation(), editor.getScreenToWorldRay())
            offset[key] = t
        end
    end

    local diff = rotation:ToQuat():Transform(offset)

    if not editor.dragOriginalDiff then
        editor.dragOriginalDiff = diff
        editor.originalPos = Vector4.new(position)
    end

    selected:setPositionDelta(Vector4.new(diff.x - editor.dragOriginalDiff.x, diff.y - editor.dragOriginalDiff.y, diff.z - editor.dragOriginalDiff.z))
end

function editor.onDraw()
    editor.camera.update()

    if editor.active and input.context.viewport.hovered then
        editor.checkArrow()
        editor.updateDrag()
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
    editor.active = state
    editor.camera.toggle(state)

    if not state then
        editor.baseUI.loadTabSize = true
        editor.baseUI.restoreWindowPosition = true
        editor.removeHighlight(false)
        editor.currentAxis = "none"
        editor.hoveredArrow = "none"
        editor.grab = false
    else
        editor.addHighlightToSelected()
    end
end

return editor