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
---@field draggingAxis string
---@field dragOriginalDiff number?
---@field grab boolean
---@field originalPos Vector4
local editor = {
    active = false,
    camera = nil,
    baseUI = nil,
    spawnedUI = nil,
    spawnUI = nil,
    suspendState = false,
    hoveredArrow = "none",
    draggingAxis = "none",
    dragOriginalDiff = nil,
    grab = false,
    originalPos = Vector4.new(0, 0, 0, 0)
}

function onViewport()
    return editor.active and input.context.viewport.focused
end

function editor.init(spawner)
    editor.baseUI = spawner.baseUI
    editor.spawnedUI = spawner.baseUI.spawnedUI
    editor.spawnUI = spawner.baseUI.spawnUI

    editor.camera = require("modules/utils/editor/camera")

    input.registerMouseAction(ImGuiMouseButton.Right, function()
        editor.grab = false
        editor.draggingAxis = "none"
        local element = editor.spawnedUI.selectedPaths[1]
        if not element then return end

        element.ref.spawnable.position = editor.originalPos
        element.ref.spawnable:update()
    end, onViewport) -- Cancle
    input.registerMouseAction(ImGuiMouseButton.Left, function ()
        editor.setTarget()
        editor.grab = false
    end,
    function ()
        return editor.active and input.context.viewport.hovered
    end)
    input.registerImGuiHotkey({ ImGuiKey.Tab }, editor.centerCamera, function ()
        return editor.active and (input.context.viewport.focused or input.context.hierarchy.focused)
    end)

    input.registerImGuiHotkey({ ImGuiKey.G }, function ()
        if editor.draggingAxis ~= "none" then return end

        editor.grab = true

        if #editor.spawnedUI.selectedPaths == 1 then
            local selected = editor.spawnedUI.selectedPaths[1].ref.spawnable
            if selected:isSpawned() then
                editor.originalPos = Vector4.new(selected.position)
            end
        end
    end, onViewport)
    input.registerImGuiHotkey({ ImGuiKey.X }, function ()
        if not editor.grab then return end

        if ImGui.IsKeyDown(ImGuiKey.LeftShift) then
            editor.draggingAxis = "yz"
        else
            editor.draggingAxis = "x"
        end
    end, onViewport)
    input.registerImGuiHotkey({ ImGuiKey.Y }, function ()
        if not editor.grab then return end

        if ImGui.IsKeyDown(ImGuiKey.LeftShift) then
            editor.draggingAxis = "xz"
        else
            editor.draggingAxis = "y"
        end
    end, onViewport)
    input.registerImGuiHotkey({ ImGuiKey.Z }, function ()
        if not editor.grab then return end

        if ImGui.IsKeyDown(ImGuiKey.LeftShift) then
            editor.draggingAxis = "xy"
        else
            editor.draggingAxis = "z"
        end
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

    if #editor.spawnedUI.selectedPaths ~= 1 or editor.draggingAxis ~= "none" then return end

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
        visualizer.highlightArrow(selected:getEntity(), "blue")
        editor.hoveredArrow = "z"
    elseif xHit.hit then
        visualizer.highlightArrow(selected:getEntity(), "red")
        editor.hoveredArrow = "x"
    elseif yHit.hit then
        visualizer.highlightArrow(selected:getEntity(), "green")
        editor.hoveredArrow = "y"
    else
        visualizer.highlightArrow(selected:getEntity(), "none")
    end
end

function editor.updateDrag()
    print(editor.draggingAxis, editor.hoveredArrow, editor.grab)

    if ImGui.IsMouseDragging(0, 0) then
        if editor.hoveredArrow ~= "none" then
            editor.draggingAxis = editor.hoveredArrow
        end
    elseif not editor.grab then
        if editor.draggingAxis ~= "none" then
            local element = editor.spawnedUI.selectedPaths[1].ref
            local new = Vector4.new(element.spawnable.position)
            element.spawnable.position = editor.originalPos
            history.addAction(history.getElementChange(element))
            element.spawnable.position = new
        end

        editor.draggingAxis = "none"
        editor.dragOriginalDiff = nil
    end

    if editor.draggingAxis == "none" then return end

    local selected = editor.spawnedUI.selectedPaths[1].ref.spawnable

    local axis
    local axisMult = { x = 0, y = 0, z = 0 }
    if editor.draggingAxis == "x" then
        axis = selected.rotation:GetRight()
        axisMult.x = 1
    elseif editor.draggingAxis == "y" then
        axis = selected.rotation:GetForward()
        axisMult.y = 1
    elseif editor.draggingAxis == "z" then
        axis = selected.rotation:GetUp()
        axisMult.z = 1
    end

    local t, _ = intersection.getTClosestToRay(selected.position, axis, GetPlayer():GetFPPCameraComponent():GetLocalToWorld():GetTranslation(), editor.getScreenToWorldRay())
    local diff = selected.rotation:ToQuat():Transform(Vector4.new(t * axisMult.x, t * axisMult.y, t * axisMult.z, 0))

    if not editor.dragOriginalDiff then
        editor.dragOriginalDiff = diff
        editor.originalPos = Vector4.new(selected.position)
    end

    editor.spawnedUI.selectedPaths[1].ref:setPositionDelta(Vector4.new(diff.x - editor.dragOriginalDiff.x, diff.y - editor.dragOriginalDiff.y, diff.z - editor.dragOriginalDiff.z))
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
    else
        editor.addHighlightToSelected()
    end
end

return editor