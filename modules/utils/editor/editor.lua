local utils = require("modules/utils/utils")

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
end

function editor.onDraw()
    editor.camera.update()

    if ImGui.IsMouseDown(ImGuiMouseButton.Right) then
        local x, y = ImGui.GetMousePos()
        local width, height = GetDisplayResolution()

        local _, ray = editor.camera.screenToWorld((x / width * 2) - 1, - ((y / height * 2) - 1))
        local closest = nil

        for _, element in pairs(editor.spawnedUI.paths) do
            if utils.isA(element.ref, "spawnableElement") then
                local hit = element.ref.spawnable:calculateIntersection(GetPlayer():GetFPPCameraComponent():GetLocalToWorld():GetTranslation(), ray)

                print(hit.hit, hit.position, hit.collisionType, hit.distance, hit.size)
                if hit.hit then
                    if not closest or hit.distance < closest.distance then
                        hit.element = element
                        closest = hit
                    end
                end
            end
        end

        if closest then
            editor.spawnedUI.unselectAll()
            editor.spawnedUI.scrollToSelected = true
            closest.element.ref:setSelected(true)
        end
    end
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