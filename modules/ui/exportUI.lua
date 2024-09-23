local config = require("modules/utils/config")
local CPS = require("CPStyling")
local object = require("modules/classes/spawn/object")
local gr = require("modules/classes/spawn/group")
local utils = require("modules/utils/utils")
local style = require("modules/ui/style")

local sectorCategory

exportUI = {
    projectName = "new_project",
    groups = {},
    templates = {},
    spawner = nil
}

function exportUI.init()
    for _, file in pairs(dir("data/exportTemplates/")) do
        if file.name:match("^.+(%..+)$") == ".json" then
            local data = config.loadFile("data/exportTemplates/" .. file.name)

            for key, group in pairs(data.groups) do
                if not config.fileExists("data/objects/" .. group.name .. ".json") then
                    data.groups[key] = nil
                end
            end

            exportUI.templates[data.projectName] = data
        end
    end
end

function exportUI.drawGroups()
    if #exportUI.groups > 0 then
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
                ImGui.SetNextItemWidth(150 * style.viewSize)
                group.category = ImGui.Combo("##category", group.category, sectorCategory, #sectorCategory)

                style.mutedText("Sector Level:")
                style.tooltip("Select the level of the sector for the group")
                ImGui.SameLine()
                ImGui.SetNextItemWidth(150 * style.viewSize)
                group.level, changed = ImGui.InputInt("##level", group.level)
                if changed then
                    group.level = math.min(math.max(group.level, 0), 6)
                end

                style.mutedText("Streaming Box Extents:")
                style.tooltip("Change the size of the streaming box for the sector, extends the given amount on each axis in both directions")
                ImGui.SameLine()
                ImGui.PushItemWidth(90 * style.viewSize)
                group.streamingX = ImGui.DragFloat("##x", group.streamingX, 0.25, 0, 9999, "%.1f X Size")
                ImGui.SameLine()
                group.streamingY = ImGui.DragFloat("##y", group.streamingY, 0.25, 0, 9999, "%.1f Y Size")
                ImGui.SameLine()
                group.streamingZ = ImGui.DragFloat("##z", group.streamingZ, 0.25, 0, 9999, "%.1f Z Size")
                ImGui.PopItemWidth()

                if ImGui.Button("Remove from list") then
                    table.remove(exportUI.groups, key)
                end

                ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 0, 0)
                ImGui.PushStyleColor(ImGuiCol.FrameBg, 0)
                ImGui.TreePop()
            end
            ImGui.EndGroup()
        end

        ImGui.EndChildFrame()
        ImGui.PopStyleColor()
        ImGui.PopStyleVar(2)
    else
        ImGui.PushStyleColor(ImGuiCol.Text, style.mutedColor)
        ImGui.TextWrapped("No groups yet added, add them from the \"Saved\" tab!")
        ImGui.PopStyleColor()
    end
end

function exportUI.drawTemplates()
    if utils.tableLength(exportUI.templates) > 0 then
        ImGui.PushStyleVar(ImGuiStyleVar.FrameBorderSize, 0)
        ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 0, 0)
        ImGui.PushStyleColor(ImGuiCol.FrameBg, 0)

        ImGui.BeginChildFrame(2, 0, math.min(5, math.max(utils.tableLength(exportUI.templates), 3)) * ImGui.GetFrameHeightWithSpacing())

        for key, data in pairs(exportUI.templates) do
            ImGui.BeginGroup()

            local nodeFlags = ImGuiTreeNodeFlags.SpanFullWidth
            if ImGui.TreeNodeEx(data.projectName, nodeFlags) then
                ImGui.PopStyleColor()
                ImGui.PopStyleVar()

                style.mutedText("Groups:")
                ImGui.SameLine()
                ImGui.Text(tostring(#data.groups))

                if ImGui.Button("Load") then
                    exportUI.groups = utils.deepcopy(data.groups)
                    exportUI.projectName = data.projectName
                end
                ImGui.SameLine()
                if ImGui.Button("Delete") then
                    os.remove("data/exportTemplates/" .. data.projectName .. ".json")
                    exportUI.templates[key] = nil
                end

                ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 0, 0)
                ImGui.PushStyleColor(ImGuiCol.FrameBg, 0)
                ImGui.TreePop()
            end
            ImGui.EndGroup()
        end

        ImGui.EndChildFrame()
        ImGui.PopStyleColor()
        ImGui.PopStyleVar(2)
    else
        ImGui.PushStyleColor(ImGuiCol.Text, style.mutedColor)
        ImGui.TextWrapped("No templates created yet.")
        ImGui.PopStyleColor()
    end
end

function exportUI.draw(spawner)
    if not sectorCategory then
        sectorCategory = utils.enumTable("worldStreamingSectorCategory")
    end

    exportUI.spawner = spawner

    style.sectionHeaderStart("EXPORT TEMPLATES", "Templates let you save an export setup for later usage, without having to setup what groups/settings to use each time.")

    exportUI.drawTemplates()

    style.sectionHeaderEnd()

    style.sectionHeaderStart("PROPERTIES")

    ImGui.Text("Project Name")
    ImGui.SameLine()
    ImGui.SetNextItemWidth(200 * style.viewSize)
    exportUI.projectName = ImGui.InputTextWithHint('##name', 'Export name...', exportUI.projectName, 100)

    style.sectionHeaderEnd()
    style.sectionHeaderStart("GROUPS")

    exportUI.drawGroups()

    style.sectionHeaderEnd()
    style.sectionHeaderStart("EXPORT AND SAVE")

    style.pushGreyedOut(#exportUI.groups == 0)
    if ImGui.Button("Export") and #exportUI.groups > 0 then
        exportUI.export()
    end
    style.tooltip("Export the currently selected groups to a .json file, ready for import into WKit")

    ImGui.SameLine()
    if ImGui.Button("Save as Template") and #exportUI.groups > 0 then
        local data = {
            projectName = exportUI.projectName,
            groups = utils.deepcopy(exportUI.groups)
        }
        exportUI.templates[exportUI.projectName] = data
        config.saveFile("data/exportTemplates/" .. exportUI.projectName .. ".json", data)
    end
    style.tooltip("Save the current export setup as a template for later (re)usage")

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

function exportUI.flatExport(name)

end

function exportUI.exportGroup(group)
    if not config.fileExists("data/objects/" .. group.name .. ".json") then return end

    local data = config.loadFile("data/objects/" .. group.name .. ".json")

    local g = require("modules/classes/editor/positionableGroup"):new(exportUI.spawner.baseUI.spawnedUI)
    g:load(data, true)

    local center = g:getCenter()
    local min = { x = center.x - group.streamingX, y = center.y - group.streamingY, z = center.z - group.streamingY }
    local max = { x = center.x + group.streamingX, y = center.y + group.streamingY, z = center.z + group.streamingY }

    local exported = {
        name = utils.createFileName(group.name):lower():gsub(" ", "_"),
        min = min,
        max = max,
        category = sectorCategory[group.category + 1],
        level = group.level,
        nodes = {}
    }

    local objects = g:getPathsRecursive(false)

    for key, object in pairs(objects) do
        if utils.isA(object.ref, "spawnableElement") then
            table.insert(exported.nodes, object.ref.spawnable:export(key, #objects))
        end
    end

    return exported
end

function exportUI.export()
    local project = {
        name = utils.createFileName(exportUI.projectName):lower():gsub(" ", "_"),
        sectors = {}
    }

    for _, group in pairs(exportUI.groups) do
        local data = exportUI.exportGroup(group)
        if data then
            table.insert(project.sectors, data)
        end
    end

    config.saveFile("export/" .. project.name .. "_exported.json", project)

    print("[entSpawner] Exported project " .. project.name)
end

return exportUI