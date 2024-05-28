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

function style.spawnableInfo(info)
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.PushTextWrapPos(ImGui.GetFontSize() * 20)

        style.mutedText("Node: ")
        ImGui.Text(info.node)
        ImGui.Spacing()
        style.mutedText("Description: ")
        ImGui.Text(info.description)
        ImGui.Spacing()
        style.mutedText("Preview Note: ")
        ImGui.Text(info.previewNote)

        ImGui.EndTooltip()
    end
end

function style.spacedSeparator()
    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()
end

function style.sectionHeaderStart(text)
    ImGui.PushStyleColor(ImGuiCol.Text, style.mutedColor)
    ImGui.SetWindowFontScale(0.85)
    ImGui.Text(text)
    ImGui.SetWindowFontScale(1)
    ImGui.PopStyleColor()
    ImGui.Separator()
    ImGui.Spacing()

    ImGui.BeginGroup()
    ImGui.AlignTextToFramePadding()
end

function style.sectionHeaderEnd(noSpacing)
    ImGui.EndGroup()

    if not noSpacing then
        ImGui.Spacing()
        ImGui.Spacing()
    end
end

function style.mutedText(text)
    ImGui.PushStyleColor(ImGuiCol.Text, style.mutedColor)
    ImGui.Text(text)
    ImGui.PopStyleColor()
end

return style