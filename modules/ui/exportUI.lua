local config = require("modules/utils/config")
local utils = require("modules/utils/utils")
local style = require("modules/ui/style")

local sectorCategory

exportUI = {
    projectName = "",
    groups = {},
    templates = {},
    spawner = nil,
    exportHovered = false,
    foundDuplicates = nil
}

function exportUI.init(spawner)
    for _, file in pairs(dir("data/exportTemplates/")) do
        if file.name:match("^.+(%..+)$") == ".json" then
            local data = config.loadFile("data/exportTemplates/" .. file.name)

            if data.groups then
                for key, group in pairs(data.groups) do
                    if not config.fileExists("data/objects/" .. group.name .. ".json") then
                        data.groups[key] = nil
                    end
                end

                exportUI.templates[data.projectName] = data
            end
        end
    end

    exportUI.spawner = spawner
end

local function calculateExtents(center, objects)
    local maxExtent = {x = 0, y = 0, z = 0}

    for _, point in ipairs(objects) do
        if utils.isA(point.ref, "spawnableElement") and Vector4.Distance(point.ref:getPosition(), Vector4.new(0, 0, 0, 0)) > 25 then
            local pos = point.ref:getPosition()
            local range = point.ref.spawnable.primaryRange

            local dx = math.abs(pos.x - center.x) + range
            local dy = math.abs(pos.y - center.y) + range
            local dz = math.abs(pos.z - center.z) + range

            maxExtent.x = math.max(maxExtent.x, dx)
            maxExtent.y = math.max(maxExtent.y, dy)
            maxExtent.z = math.max(maxExtent.z, dz)
        end
    end

    return maxExtent
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
                if ImGui.Button("Auto") then
                    local blob = config.loadFile("data/objects/" .. group.name .. ".json")
                    local g = require("modules/classes/editor/positionableGroup"):new(exportUI.spawner.baseUI.spawnedUI)
                    g:load(blob, true)

                    local extents = calculateExtents(group.center, g:getPathsRecursive(false))
                    group.streamingX = extents.x * 1.2
                    group.streamingY = extents.y * 1.2
                    group.streamingZ = extents.z * 1.2
                end
                ImGui.SameLine()
                ImGui.PushItemWidth(90 * style.viewSize)
                group.streamingX = ImGui.DragFloat("##x", group.streamingX, 0.25, 0, 9999, "%.1f X Size")
                ImGui.SameLine()
                group.streamingY = ImGui.DragFloat("##y", group.streamingY, 0.25, 0, 9999, "%.1f Y Size")
                ImGui.SameLine()
                group.streamingZ = ImGui.DragFloat("##z", group.streamingZ, 0.25, 0, 9999, "%.1f Z Size")
                ImGui.PopItemWidth()
                ImGui.SameLine()

                local outOfBox = false

                local playerPos = GetPlayer():GetWorldPosition()
                if group.center.x + group.streamingX < playerPos.x or group.center.x - group.streamingX > playerPos.x then
                    outOfBox = true
                end
                if group.center.y + group.streamingY < playerPos.y or group.center.y - group.streamingY > playerPos.y then
                    outOfBox = true
                end
                if group.center.z + group.streamingZ < playerPos.z or group.center.z - group.streamingZ > playerPos.z then
                    outOfBox = true
                end

                local distance = utils.distanceVector(group.center, playerPos)
                style.styledText(IconGlyphs.AxisArrowInfo, outOfBox and 0xFF0000FF or 0xFF00FF00)
                style.tooltip("Distance to player: " .. string.format("%.2f", distance))

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

function exportUI.draw()
    if exportUI.foundDuplicates then
        ImGui.OpenPopup("Duplicated NodeRefs")
        if ImGui.BeginPopupModal("Duplicated NodeRefs", true, ImGuiWindowFlags.AlwaysAutoResize) then
            ImGui.Text("Duplicated nodeRefs found, please fix them before exporting! (Export aborted)")

            ImGui.Separator()

            style.mutedText("NodeRef:")
            ImGui.SameLine()
            ImGui.Text(exportUI.foundDuplicates.nodeRef)

            style.mutedText("Node 1: ")
            ImGui.SameLine()
            ImGui.Text(exportUI.foundDuplicates.name1)

            style.mutedText("Node 2: ")
            ImGui.SameLine()
            ImGui.Text(exportUI.foundDuplicates.name2)

            ImGui.Separator()

            if ImGui.Button("OK") then
                ImGui.CloseCurrentPopup()
                exportUI.foundDuplicates = nil
            end
            ImGui.EndPopup()
        end
    end

    if not sectorCategory then
        sectorCategory = utils.enumTable("worldStreamingSectorCategory")
    end

    style.sectionHeaderStart("EXPORT TEMPLATES", "Templates let you save an export setup for later usage, without having to setup what groups/settings to use each time.")

    exportUI.drawTemplates()

    style.sectionHeaderEnd()

    style.sectionHeaderStart("PROPERTIES")

    style.pushStyleColor(exportUI.projectName == "" and exportUI.exportHovered, ImGuiCol.Text, 0xFF0000FF)
    ImGui.Text("Project Name")
    style.popStyleColor(exportUI.projectName == "" and exportUI.exportHovered)
    ImGui.SameLine()
    ImGui.SetNextItemWidth(200 * style.viewSize)
    exportUI.projectName = ImGui.InputTextWithHint('##name', 'Export name...', exportUI.projectName, 100)

    style.sectionHeaderEnd()
    style.sectionHeaderStart("GROUPS")

    exportUI.drawGroups()

    style.sectionHeaderEnd()
    style.sectionHeaderStart("EXPORT AND SAVE")

    style.pushGreyedOut(#exportUI.groups == 0 or exportUI.projectName == "")
    if ImGui.Button("Export") and #exportUI.groups > 0  and exportUI.projectName ~= "" then
        exportUI.export()
    end
    style.tooltip("Export the currently selected groups to a .json file, ready for import into WKit")
    exportUI.exportHovered = ImGui.IsItemHovered()

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

    style.popGreyedOut(#exportUI.groups == 0 or exportUI.projectName == "")

    style.sectionHeaderEnd(true)
end

function exportUI.addGroup(name)
    for _, data in pairs(exportUI.groups) do
        if data.name == name then return end
    end

    local data = {
        name = name,
        category = 1,
        level = 1,
        streamingX = 150,
        streamingY = 150,
        streamingZ = 100,
        center = nil
    }

    table.insert(exportUI.groups, data)

    if not config.fileExists("data/objects/" .. name .. ".json") then return end

    local blob = config.loadFile("data/objects/" .. name .. ".json")
    local g = require("modules/classes/editor/positionableGroup"):new(exportUI.spawner.baseUI.spawnedUI)
    g:load(blob, true)

    local center = g:getPosition()
    data.center = utils.fromVector(center)
end

function exportUI.exportGroup(group)
    if not config.fileExists("data/objects/" .. group.name .. ".json") then return end

    local data = config.loadFile("data/objects/" .. group.name .. ".json")

    local g = require("modules/classes/editor/positionableGroup"):new(exportUI.spawner.baseUI.spawnedUI)
    g:load(data, true)

    local center = g:getPosition()
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

    local devices = {}
    local psEntries = {}
    local objects = g:getPathsRecursive(false)

    for key, object in pairs(objects) do
        if utils.isA(object.ref, "spawnableElement") then
            table.insert(exported.nodes, object.ref.spawnable:export(key, #objects))

            -- Handle device nodes
            if object.ref.spawnable.node == "worldDeviceNode" then
                local hash = utils.nodeRefStringToHashString(object.ref.spawnable.nodeRef)

                local childHashes = {}
                for _, child in pairs(object.ref.spawnable.deviceConnections) do
                    table.insert(childHashes, utils.nodeRefStringToHashString(child.nodeRef))
                end

                devices[hash] = {
                    hash = hash,
                    className = object.ref.spawnable.deviceClassName,
                    nodePosition = utils.fromVector(object.ref:getPosition()),
                    parents = {},
                    children = childHashes
                }

                if object.ref.spawnable.persistent then
                    local PSID = PersistentID.ForComponent(entEntityID.new({ hash = loadstring("return " .. hash .. "ULL", "")() }), object.ref.spawnable.controllerComponent):ToHash()
                    PSID = tostring(PSID):gsub("ULL", "")

                    local psData = object.ref.spawnable:getPSData()

                    if psData then
                        psEntries[PSID] = {
                            PSID = PSID,
                            instanceData = psData
                        }
                    end
                end
            end
        end
    end

    return exported, devices, psEntries
end

function exportUI.export()
    local project = {
        name = utils.createFileName(exportUI.projectName):lower():gsub(" ", "_"),
        sectors = {},
        devices = {},
        psEntries = {}
    }

    local nodeRefs = {}

    for _, group in pairs(exportUI.groups) do
        local data, devices, psEntries = exportUI.exportGroup(group)
        if data then
            table.insert(project.sectors, data)

            for hash, device in pairs(devices) do
                project.devices[hash] = device
            end

            for PSID, entry in pairs(psEntries) do
                project.psEntries[PSID] = entry
            end

            for _, node in pairs(data.nodes) do
                if not nodeRefs[node.nodeRef] then
                    nodeRefs[node.nodeRef] = node.name
                else
                    exportUI.foundDuplicates = {
                        nodeRef = node.nodeRef,
                        name1 = nodeRefs[node.nodeRef],
                        name2 = node.name
                    }
                    break
                end
            end
        end

        if exportUI.foundDuplicates then break end
    end

    if exportUI.foundDuplicates then return end

    for hash, device in pairs(project.devices) do
        for _, childHash in pairs(device.children) do
            if project.devices[childHash] then
                table.insert(project.devices[childHash].parents, hash)
            end
        end
    end

    config.saveFile("export/" .. project.name .. "_exported.json", project)

    print("[entSpawner] Exported project " .. project.name)
end

return exportUI