local input = {
    hotkeys = {}
}

function input.registerImGuiHotkey(keys, callback)
    table.insert(input.hotkeys, {keys = keys, active = false, callback = callback})
end

function input.update()
    for _, hotkey in ipairs(input.hotkeys) do
        local pressed = true

        for _, key in ipairs(hotkey.keys) do
            if not ImGui.IsKeyDown(key) then
                pressed = false
                hotkey.active = false
                break
            end
        end

        if pressed and not hotkey.active then
            hotkey.callback()
            hotkey.active = true
        end
    end
end

return input