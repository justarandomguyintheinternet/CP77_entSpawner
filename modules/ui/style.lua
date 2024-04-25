-- Most of the colors and style has been taken from https://github.com/psiberx/cp2077-red-hot-tools

local style = {
    mutedColor = 0xFFA5A19B
}

function style.pushGreyedOut(state)
    if not state then return end

    ImGui.PushStyleColor(ImGuiCol.Button, 0xff777777)
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0xff777777)
    ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0xff777777)

    ImGui.PushStyleColor(ImGuiCol.FrameBg, 0xff777777)
    ImGui.PushStyleColor(ImGuiCol.FrameBgHovered, 0xff777777)
    ImGui.PushStyleColor(ImGuiCol.FrameBgActive, 0xff777777)
end
function style.popGreyedOut(state)
    if not state then return end

    ImGui.PopStyleColor(6)
end

function style.tooltip(text)
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip(text)
    end
end

return style