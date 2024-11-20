local utils = require("modules/utils/utils")
local input = require("modules/utils/input")
local intersection = require("modules/utils/editor/intersection")

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
    spawnUI = nil
}

function editor.init(spawner)
    editor.baseUI = spawner.baseUI
    editor.spawnedUI = spawner.baseUI.spawnedUI
    editor.spawnUI = spawner.baseUI.spawnUI

    editor.camera = require("modules/utils/editor/camera")

    input.registerMouseAction(ImGuiMouseButton.Right, editor.calculateTarget)
    input.registerImGuiHotkey({ ImGuiKey.Tab }, editor.centerCamera, function ()
        return editor.spawnedUI.selectedPaths[1] and editor.active
    end)
    --TODO CONTEXT; depth menu
end

function editor.centerCamera()
    if #editor.spawnedUI.selectedPaths == 0 then
        return
    end

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
            selected.ref.spawnable:getEntity():QueueEvent(entRenderHighlightEvent.new({
                seeThroughWalls = true,
                outlineIndex = 0,
                opacity = 1
            }))
        end
    end
end

function editor.calculateTarget()
    local x, y = ImGui.GetMousePos()
    local width, height = GetDisplayResolution()
    local _, ray = editor.camera.screenToWorld((x / width * 2) - 1, - ((y / height * 2) - 1))
    local hits = {}

    for _, element in pairs(editor.spawnedUI.paths) do
        if element.ref.visible and utils.isA(element.ref, "spawnableElement") then
            local hit = element.ref.spawnable:calculateIntersection(GetPlayer():GetFPPCameraComponent():GetLocalToWorld():GetTranslation(), ray)

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
        print("Hit: ", hit.position, hit.collisionType, hit.distance)
    end

    -- If there is a hit inside the primary hit, use that one instead (To prefer things inside the bbox of the primary hit, can often be the case)
    -- TODO: Maybe scale bbox of next best hit a bit down
    local bestHitIdx = 1
    while bestHitIdx + 1 <= #hits and intersection.BBoxInsideBBox(hits[bestHitIdx].objectOrigin, hits[bestHitIdx].objectRotation, hits[bestHitIdx].bBox, hits[bestHitIdx + 1].objectOrigin, hits[bestHitIdx + 1].objectRotation, hits[bestHitIdx + 1].bBox) do
        bestHitIdx = bestHitIdx + 1
    end
    bestHitIdx = math.min(bestHitIdx, #hits)

    print("Best hit: ", hits[bestHitIdx].position, hits[bestHitIdx].collisionType, hits[bestHitIdx].distance, hits[bestHitIdx].size)

    editor.removeHighlight(true)
    editor.spawnedUI.unselectAll()
    editor.spawnedUI.scrollToSelected = true
    hits[bestHitIdx].element:expandAllParents()
    hits[bestHitIdx].element:setSelected(true)
    hits[bestHitIdx].element.spawnable:getEntity():QueueEvent(entRenderHighlightEvent.new({
        seeThroughWalls = true,
        outlineIndex = 1,
        opacity = 1.0
    }))
end

function editor.onDraw()
    editor.camera.update()
end

function editor.toggle(state)
    editor.active = state
    editor.camera.toggle(state)

    if not state then
        editor.baseUI.loadTabSize = true
        editor.baseUI.restoreWindowPosition = true
    end
end

return editor