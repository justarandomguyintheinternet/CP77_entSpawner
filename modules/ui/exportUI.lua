local config = require("modules/utils/config")
local CPS = require("CPStyling")
local object = require("modules/classes/spawn/object")
local gr = require("modules/classes/spawn/group")
local utils = require("modules/utils/utils")
local style = require("modules/ui/style")

local sectorCategory = {
    "Exterior",
    "Interior",
    "Quest",
    "Navigation",
    "AlwaysLoaded",
}

exportUI = {
    projectName = "new_project",
    groups = {}
}

function exportUI.drawGroups()
    if #exportUI.groups > 0 then
        ImGui.PushStyleVar(ImGuiStyleVar.IndentSpacing, 0)
        ImGui.PushStyleVar(ImGuiStyleVar.FrameBorderSize, 0)
        ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 0, 0)
        ImGui.PushStyleColor(ImGuiCol.FrameBg, 0)

        ImGui.BeginChildFrame(1, 0, math.min(15, math.max(#exportUI.groups, 10)) * ImGui.GetFrameHeightWithSpacing())

        for key, group in ipairs(exportUI.groups) do
            ImGui.BeginGroup()

            local nodeFlags = ImGuiTreeNodeFlags.SpanFullWidth
            if ImGui.TreeNodeEx(group.name, nodeFlags) then
                ImGui.PopStyleColor()
                ImGui.PopStyleVar()

                style.mutedText("Group file name:")
                ImGui.SameLine()
                ImGui.Text(group.name)

                style.mutedText("Sector Category:")
                style.tooltip("Select the type of the sector for the group, if in doubt use Interior or Exterior")
                ImGui.SameLine()
                ImGui.SetNextItemWidth(150)
                group.category = ImGui.Combo("##category", group.category, sectorCategory, #sectorCategory)

                style.mutedText("Sector Level:")
                style.tooltip("Select the level of the sector for the group")
                ImGui.SameLine()
                ImGui.SetNextItemWidth(150)
                group.level, changed = ImGui.InputInt("##level", group.level)
                if changed then
                    group.level = math.min(math.max(group.level, 0), 6)
                end

                style.mutedText("Streaming Box Extents:")
                style.tooltip("Change the size of the streaming box for the sector, extends the given amount on each axis in both directions")
                ImGui.SameLine()
                ImGui.PushItemWidth(110)
                group.streamingX = ImGui.DragFloat("##x", group.streamingX, 0.25, 0, 9999, "%.1f X Size")
                ImGui.SameLine()
                group.streamingY = ImGui.DragFloat("##y", group.streamingY, 0.25, 0, 9999, "%.1f Y Size")
                ImGui.SameLine()
                group.streamingZ = ImGui.DragFloat("##z", group.streamingZ, 0.25, 0, 9999, "%.1f Z Size")
                ImGui.PopItemWidth()

                if ImGui.Button("Remove from list") then
                   exportUI.groups[key] = nil
                end

                ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 0, 0)
                ImGui.PushStyleColor(ImGuiCol.FrameBg, 0)
                ImGui.TreePop()
            end
            ImGui.EndGroup()
        end

        ImGui.EndChildFrame()
        ImGui.PopStyleColor()
        ImGui.PopStyleVar(3)
    else
        ImGui.PushStyleColor(ImGuiCol.Text, style.mutedColor)
        ImGui.TextWrapped("No groups yet added, add them from the \"Saved\" tab!")
        ImGui.PopStyleColor()
    end
end

function exportUI.draw()
    style.sectionHeaderStart("PROPERTIES")

    ImGui.Text("Project Name")
    ImGui.SameLine()
    ImGui.SetNextItemWidth(250)
    exportUI.projectName = ImGui.InputTextWithHint('##name', 'Export name...', exportUI.projectName, 100)

    style.sectionHeaderEnd()
    style.sectionHeaderStart("GROUPS")

    exportUI.drawGroups()

    style.sectionHeaderEnd()
    style.sectionHeaderStart("EXPORT")

    style.pushGreyedOut(#exportUI.groups == 0)
    if ImGui.Button("Export") and #exportUI.groups > 0 then
        exportUI.export()
    end
    style.popGreyedOut(#exportUI.groups == 0)

    style.sectionHeaderEnd(true)
end

function exportUI.addGroup(name)
    for _, data in pairs(exportUI.groups) do
        if data.name == name then return end
    end

    local data = {
        name = name,
        category = 0,
        level = 1,
        streamingX = 150,
        streamingY = 150,
        streamingZ = 100
    }
    table.insert(exportUI.groups, data)
end

function exportUI.export()

end

return exportUI