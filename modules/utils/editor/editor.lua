local utils = require("modules/utils/utils")
local input = require("modules/utils/input")
local intersection = require("modules/utils/editor/intersection")
local settings = require("modules/utils/settings")

---@class editor
---@field active boolean
---@field camera camera?
---@field baseUI baseUI?
---@field spawnedUI spawnedUI?
---@field spawnUI spawnUI?
local editor = {
    active = false,
    camera = nil,
    baseUI = nil,
    spawnedUI = nil,
    spawnUI = nil,
    suspendState = false
}

function editor.init(spawner)
    editor.baseUI = spawner.baseUI
    editor.spawnedUI = spawner.baseUI.spawnedUI
    editor.spawnUI = spawner.baseUI.spawnUI

    editor.camera = require("modules/utils/editor/camera")

    input.registerMouseAction(ImGuiMouseButton.Left, editor.setTarget, function ()
        return editor.active and input.context.viewport.hovered
    end)
    input.registerImGuiHotkey({ ImGuiKey.Tab }, editor.centerCamera, function ()
        return editor.active and (input.context.viewport.focused or input.context.hierarchy.focused)
    end)

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

function editor.setTarget()
    local x, y = ImGui.GetMousePos()
    local width, height = GetDisplayResolution()
    local _, ray = editor.camera.screenToWorld((x / width * 2) - 1, - ((y / height * 2) - 1))

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

function editor.onDraw()
    editor.camera.update()
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