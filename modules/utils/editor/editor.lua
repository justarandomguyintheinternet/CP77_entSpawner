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
end

function editor.toggle(state)
    editor.active = state
    editor.camera.toggle(state)
end

return editor