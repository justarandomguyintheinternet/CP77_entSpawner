local input = {
    hotkeys = {},
    mouse = {},
    context = {
        main = { hovered = false, focused = false },
        hierarchy = { hovered = false, focused = false },
        viewport = { hovered = false, focused = false }
    }
}

function input.registerImGuiHotkey(keys, callback, runCondition)
    table.insert(input.hotkeys, {keys = keys, active = false, callback = callback, runCondition = runCondition})
end

function input.registerMouseAction(mouseKey, callback, runCondition)
    table.insert(input.mouse, {mouseKey = mouseKey, active = false, callback = callback, runCondition = runCondition})
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
            if (hotkey.runCondition and hotkey.runCondition()) or hotkey.runCondition == nil then
                hotkey.callback()
            end
            hotkey.active = true
        end
    end

    for _, mouse in ipairs(input.mouse) do
        if ImGui.IsMouseDown(mouse.mouseKey) then
            if not mouse.active then
                if (mouse.runCondition and mouse.runCondition()) or mouse.runCondition == nil then
                    mouse.callback()
                end
                mouse.active = true
            end
        else
            mouse.active = false
        end
    end
end

function input.resetContext()
    for key, _ in pairs(input.context) do
        input.context[key] = { hovered = false, focused = false }
    end
end

function input.updateContext(key)
    input.context[key].hovered = ImGui.IsWindowHovered(ImGuiHoveredFlags.ChildWindows) or input.context[key].hovered
    input.context[key].focused = ImGui.IsWindowFocused(ImGuiHoveredFlags.ChildWindows) or input.context[key].focused
end

return input