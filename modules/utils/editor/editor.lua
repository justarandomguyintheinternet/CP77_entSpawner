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

function editor.BBoxInsideBBox(outerOrigin, outerRotation, outerBox, innerOrigin, innerRotation, innerBox)
    local min = utils.addVector(innerOrigin, innerRotation:ToQuat():Transform(ToVector4(innerBox.min)))
    local max = utils.addVector(innerOrigin, innerRotation:ToQuat():Transform(ToVector4(innerBox.max)))

    return intersection.pointInsideBox(min, outerOrigin, outerRotation, outerBox) and intersection.pointInsideBox(max, outerOrigin, outerRotation, outerBox)
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
    local bestHitIdx = 1
    while bestHitIdx + 1 <= #hits and intersection.pointInsideBox(hits[bestHitIdx + 1].position, hits[bestHitIdx].objectOrigin, hits[bestHitIdx].objectRotation, hits[bestHitIdx].bBox) do
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