local input = {
    hotkeys = {},
    mouse = {},
    windowHovered = false
}

function input.registerImGuiHotkey(keys, callback)
    table.insert(input.hotkeys, {keys = keys, active = false, callback = callback})
end

function input.registerMouseAction(mouseKey, callback)
    table.insert(input.mouse, {mouseKey = mouseKey, active = false, callback = callback})
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
            if input.windowHovered then
                hotkey.callback()
            end
            hotkey.active = true
        end
    end

    for _, mouse in ipairs(input.mouse) do
        if ImGui.IsMouseDown(mouse.mouseKey) then
            if not mouse.active then
                mouse.callback()
                mouse.active = true
            end
        else
            mouse.active = false
        end
    end

    input.windowHovered = false
end

function input.updateWindowState()
    input.windowHovered = ImGui.IsWindowHovered(ImGuiHoveredFlags.ChildWindows) or ImGui.IsWindowFocused(ImGuiHoveredFlags.ChildWindows) or input.windowHovered
end

return input