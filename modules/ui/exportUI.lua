local config = require("modules/utils/config")
local utils = require("modules/utils/utils")
local style = require("modules/ui/style")

local minScriptVersion = "1.0.3"
local sectorCategory

exportUI = {
    projectName = "",
    groups = {},
    templates = {},
    spawner = nil,
    exportHovered = false,
    exportIssues = {},
    sectorPropertiesWidth = nil
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
            local range = math.min(point.ref.spawnable.primaryRange, 250)

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

local function drawVariantsTooltip()
    ImGui.SameLine()
    ImGui.Text(IconGlyphs.InformationOutline)
    style.tooltip("All objects placed within the root of the group will be part of the default variant\nYou can assign to each group what variant they should belong to")
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

                if not exportUI.sectorPropertiesWidth then
                    exportUI.sectorPropertiesWidth = utils.getTextMaxWidth({"Group file name:", "Sector Category:", "Sector Level:", "Streaming Box Extents:"}) + ImGui.GetStyle().ItemSpacing.x + ImGui.GetCursorPosX()
                end

                if ImGui.TreeNodeEx("Variants", ImGuiTreeNodeFlags.SpanFullWidth) then
                    drawVariantsTooltip()

                    style.mutedText("Variant Node Ref")
                    ImGui.SameLine()
                    group.variantRef = ImGui.InputTextWithHint('##variantRef', '$/#foobar', group.variantRef, 100)

                    for name, _ in pairs(group.variantData) do
                        ImGui.PushID(name)
                        ImGui.SetNextItemWidth(100 * style.viewSize)
                        group.variantData[name].name = ImGui.InputTextWithHint('##variantName', 'default', group.variantData[name].name, 100)
                        ImGui.SameLine()
                        ImGui.SetNextItemWidth(185 * style.viewSize)
                        local default = group.variantData[name].name == "default"
                        style.pushGreyedOut(default)
                        group.variantData[name].defaultOn, changed = ImGui.Checkbox("Default On", group.variantData[name].defaultOn)
                        style.popGreyedOut(default)
                        if default then
                            group.variantData[name].defaultOn = true
                        end
                        if changed and not default then
                            for variant, _ in pairs(group.variantData) do
                                if group.variantData[variant].name == group.variantData[name].name then
                                    group.variantData[variant].defaultOn = group.variantData[name].defaultOn
                                end
                            end
                        end
                        ImGui.SameLine()
                        style.mutedText(name)

                        ImGui.PopID()
                    end

                    ImGui.TreePop()
                else
                    drawVariantsTooltip()
                end

                style.mutedText("Group file name:")
                ImGui.SameLine()
                ImGui.SetCursorPosX(exportUI.sectorPropertiesWidth)
                ImGui.Text(group.name)

                style.mutedText("Sector Category:")
                style.tooltip("Select the type of the sector for the group, if in doubt use Interior or Exterior")
                ImGui.SameLine()
                ImGui.SetCursorPosX(exportUI.sectorPropertiesWidth)
                ImGui.SetNextItemWidth(150 * style.viewSize)
                group.category = ImGui.Combo("##category", group.category, sectorCategory, #sectorCategory)

                if group.category == 3 then
                    style.mutedText("Prefab Ref:")
                    style.tooltip("Prefab NodeRef of the sector")
                    ImGui.SameLine()
                    ImGui.SetCursorPosX(exportUI.sectorPropertiesWidth)
                    ImGui.SetNextItemWidth(150 * style.viewSize)

                    group.prefabRef, _ = ImGui.InputTextWithHint('##prefabRef', '$/#foobar', group.prefabRef, 100)
                end

                style.mutedText("Sector Level:")
                style.tooltip("Select the level of the sector for the group")
                ImGui.SameLine()
                ImGui.SetCursorPosX(exportUI.sectorPropertiesWidth)
                ImGui.SetNextItemWidth(150 * style.viewSize)
                group.level, changed = ImGui.InputInt("##level", group.level)
                if changed then
                    group.level = math.min(math.max(group.level, 0), 6)
                end

                style.mutedText("Streaming Box Extents:")
                style.tooltip("Change the size of the streaming box for the sector, extends the given amount on each axis in both directions")
                ImGui.SameLine()
                ImGui.SetCursorPosX(exportUI.sectorPropertiesWidth)
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

function exportUI.loadTemplate(data)
    for _, group in pairs(utils.deepcopy(data.groups)) do
        if config.fileExists("data/objects/" .. group.name .. ".json") then
            if not group.variantData then
                group.variantData = {}
            end
            if not group.prefabRef then
                group.prefabRef = ""
            end
            if not group.variantRef then
                group.variantRef = ""
            end

            local g = require("modules/classes/editor/positionableGroup"):new(exportUI.spawner.baseUI.spawnedUI)
            g:load(config.loadFile("data/objects/" .. group.name .. ".json"), true)

            local variants = {}

            for _, child in pairs(g.childs) do
                if child.expandable then
                    if not group.variantData[child.name] then
                        variants[child.name] = { name = "default", ref = "", defaultOn = true }
                    else
                        variants[child.name] = group.variantData[child.name]
                    end
                end
            end

            group.variantData = variants
            table.insert(exportUI.groups, group)
        end
    end

    exportUI.projectName = data.projectName
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
                    exportUI.loadTemplate(data)
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

function exportUI.drawIssues()
    if exportUI.exportIssues.nodeRefDuplicated then
        ImGui.OpenPopup("Duplicated NodeRefs")
        if ImGui.BeginPopupModal("Duplicated NodeRefs", true, ImGuiWindowFlags.AlwaysAutoResize) then
            ImGui.Text("Duplicated nodeRefs found, please fix them before exporting!")

            ImGui.Separator()

            style.mutedText("NodeRef:")
            ImGui.SameLine()
            ImGui.Text(exportUI.exportIssues.nodeRefDuplicated.nodeRef)

            style.mutedText("Node 1: ")
            ImGui.SameLine()
            ImGui.Text(exportUI.exportIssues.nodeRefDuplicated.name1)

            style.mutedText("Node 2: ")
            ImGui.SameLine()
            ImGui.Text(exportUI.exportIssues.nodeRefDuplicated.name2)

            ImGui.Separator()

            if ImGui.Button("OK") then
                ImGui.CloseCurrentPopup()
                exportUI.exportIssues.nodeRefDuplicated = nil
            end
            ImGui.EndPopup()
        end
    end
    if exportUI.exportIssues.noOutlineMarkers and not exportUI.exportIssues.nodeRefDuplicated then
        ImGui.OpenPopup("Missing Outline Markers")
        if ImGui.BeginPopupModal("Missing Outline Markers", true, ImGuiWindowFlags.AlwaysAutoResize) then
            ImGui.Text("The following area nodes have no outline, possibly due to a broken outline group link!")

            ImGui.Separator()

            for _, area in pairs(exportUI.exportIssues.noOutlineMarkers) do
                style.mutedText("Area Name:")
                ImGui.SameLine()
                ImGui.Text(area)

                ImGui.Separator()
            end

            if ImGui.Button("OK") then
                ImGui.CloseCurrentPopup()
                exportUI.exportIssues.noOutlineMarkers = nil
            end
            ImGui.EndPopup()
        end
    end
    if exportUI.exportIssues.spotEmptyRef and not exportUI.exportIssues.nodeRefDuplicated and not exportUI.exportIssues.noOutlineMarkers then
        ImGui.OpenPopup("Empty AISpot NodeRef")
        if ImGui.BeginPopupModal("Empty AISpot NodeRef", true, ImGuiWindowFlags.AlwaysAutoResize) then
            ImGui.Text("The following AISpot's do not have a NodeRef assigned to them, making them unusable!")

            ImGui.Separator()

            for _, name in pairs(exportUI.exportIssues.spotEmptyRef) do
                style.mutedText("Node Name:")
                ImGui.SameLine()
                ImGui.Text(name)
            end

            ImGui.Separator()

            if ImGui.Button("OK") then
                ImGui.CloseCurrentPopup()
                exportUI.exportIssues.spotEmptyRef = nil
            end
            ImGui.EndPopup()
        end
    end
    if exportUI.exportIssues.spotReferencingEmpty and not exportUI.exportIssues.nodeRefDuplicated and not exportUI.exportIssues.noOutlineMarkers and not exportUI.exportIssues.spotEmptyRef then
        ImGui.OpenPopup("Community Referencing Missing NodeRef")
        if ImGui.BeginPopupModal("Community Referencing Missing NodeRef", true, ImGuiWindowFlags.AlwaysAutoResize) then
            ImGui.Text("The following Community Entries reference a NodeRef that is not part of this export. (Might still work, if the NodeRef is part of another export)")

            ImGui.Separator()

            for _, entry in pairs(exportUI.exportIssues.spotReferencingEmpty) do
                style.mutedText("Node Name:")
                ImGui.SameLine()
                ImGui.Text(entry.name)

                style.mutedText("Community Entry:")
                ImGui.SameLine()
                ImGui.Text(entry.entry)

                style.mutedText("Entry Phase:")
                ImGui.SameLine()
                ImGui.Text(entry.phase)

                style.mutedText("Phase Period:")
                ImGui.SameLine()
                ImGui.Text(entry.period)

                style.mutedText("Missing spotNodeRef:")
                ImGui.SameLine()
                ImGui.Text(entry.ref)

                ImGui.Separator()
            end

            if ImGui.Button("OK") then
                ImGui.CloseCurrentPopup()
                exportUI.exportIssues.spotReferencingEmpty = nil
            end
            ImGui.EndPopup()
        end
    end
    if exportUI.exportIssues.markingUnresolved and not exportUI.exportIssues.nodeRefDuplicated and not exportUI.exportIssues.noOutlineMarkers and not exportUI.exportIssues.spotEmptyRef and not exportUI.exportIssues.spotReferencingEmpty then
        ImGui.OpenPopup("Unresolved Marking")
        if ImGui.BeginPopupModal("Unresolved Marking", true, ImGuiWindowFlags.AlwaysAutoResize) then
            ImGui.Text("The following markings have no AISpots associated with them.")

            ImGui.Separator()

            for _, entry in pairs(exportUI.exportIssues.markingUnresolved) do
                style.mutedText("Node Name:")
                ImGui.SameLine()
                ImGui.Text(entry.name)

                style.mutedText("Community Entry:")
                ImGui.SameLine()
                ImGui.Text(entry.entry)

                style.mutedText("Entry Phase:")
                ImGui.SameLine()
                ImGui.Text(entry.phase)

                style.mutedText("Phase Period:")
                ImGui.SameLine()
                ImGui.Text(entry.period)

                style.mutedText("Marking:")
                ImGui.SameLine()
                ImGui.Text(entry.marking)

                ImGui.Separator()
            end

            if ImGui.Button("OK") then
                ImGui.CloseCurrentPopup()
                exportUI.exportIssues.markingUnresolved = nil
            end
            ImGui.EndPopup()
        end
    end
end

function exportUI.draw()
    exportUI.drawIssues()

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
        center = nil,
        prefabRef = "",
        variantRef = "",
        variantData = {}
    }

    table.insert(exportUI.groups, data)

    if not config.fileExists("data/objects/" .. name .. ".json") then return end

    local blob = config.loadFile("data/objects/" .. name .. ".json")
    local group = require("modules/classes/editor/positionableGroup"):new(exportUI.spawner.baseUI.spawnedUI)
    group:load(blob, true)

    for _, child in pairs(group.childs) do
        if child.expandable then
            data.variantData[child.name] = { name = "default", ref = "", defaultOn = true }
        end
    end

    local center = group:getPosition()
    data.center = utils.fromVector(center)
end

function exportUI.getSpawnableByNodeRef(nodes, nodeRef)
    for _, node in pairs(nodes) do
        if node.ref.spawnable.nodeRef == nodeRef then
            return node
        end
    end
end

function exportUI.handleDevice(object, devices, psEntries, childs, nodes)
    local hash = utils.nodeRefStringToHashString(object.ref.spawnable.nodeRef)

    local childHashes = {}
    for _, child in pairs(object.ref.spawnable.deviceConnections) do
        table.insert(childHashes, utils.nodeRefStringToHashString(child.nodeRef))

        -- Remember what childs exist, so that we can also add those to the devices file which are entityNodes, not deviceNodes

        local childRef = exportUI.getSpawnableByNodeRef(nodes, child.nodeRef)
        if childRef and childRef.ref.spawnable.deviceConnections == nil then
            table.insert(childs, {
                className = child.deviceClassName,
                nodePosition = utils.fromVector(childRef ~= nil and childRef.ref:getPosition() or object.ref:getPosition()),
                ref = child.nodeRef,
                parent = hash
            })
        end
    end

    devices[hash] = {
        hash = hash,
        className = object.ref.spawnable.deviceClassName,
        nodePosition = utils.fromVector(object.ref:getPosition()),
        parents = {},
        children = childHashes
    }

    if object.ref.spawnable.persistent and object.ref.spawnable.nodeRef ~= "" then
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

function exportUI.getNodeRefsFromMarking(marking, spotNodes)
    local nodeRefs = {}

    for _, node in pairs(spotNodes) do
        if utils.has_value(node.markings, marking) then
            table.insert(nodeRefs, {
                ["$type"] = "NodeRef",
                ["$storage"] = "string",
                ["$value"] = node.ref
            })
        end
    end

    return nodeRefs
end

function exportUI.handleCommunities(projectName, communities, spotNodes, nodeRefs)
    local wsPersistentData = {}
    local registryEntries = {}
    local periodEnums = utils.enumTable("communityECommunitySpawnTime")

    -- Collect all spots for workspotsPersistentData
    for _, node in pairs(spotNodes) do
        table.insert(wsPersistentData, {
            ["$type"] = "AISpotPersistentData",
            ["globalNodeId"] = {
                ["$type"] = "worldGlobalNodeID",
                ["hash"] = utils.nodeRefStringToHashString(node.ref)
            },
            ["isEnabled"] = 1,
            ["worldPosition"] = {
                ["$type"] = "WorldPosition",
                ["x"] = {
                    ["$type"] = "FixedPoint",
                    ["Bits"] = math.floor(node.position.x * 131072)
                },
                ["y"] = {
                    ["$type"] = "FixedPoint",
                    ["Bits"] = math.floor(node.position.y * 131072)
                },
                ["z"] = {
                    ["$type"] = "FixedPoint",
                    ["Bits"] = math.floor(node.position.z * 131072)
                }
            },
            ["yaw"] = node.yaw
        })

        if node.ref == "" then
            if not exportUI.exportIssues.spotEmptyRef then
                exportUI.exportIssues.spotEmptyRef = {}
            end
            table.insert(exportUI.exportIssues.spotEmptyRef, node.name)
        end
    end

    -- Generate registry entry, and resolve markings to nodeRefs
    for _, community in pairs(communities) do
        local initialStates = {}
        local entries = {}

        for entryKey, entry in pairs(community.data) do
            table.insert(initialStates, {
                ["$type"] = "worldCommunityEntryInitialState",
                ["entryActiveOnStart"] = entry.entryActiveOnStart and 1 or 0,
                ["entryName"] = {
                    ["$type"] = "CName",
                    ["$storage"] = "string",
                    ["$value"] = entry.entryName
                },
                ["initialPhaseName"] = {
                    ["$type"] = "CName",
                    ["$storage"] = "string",
                    ["$value"] = entry.initialPhaseName
                }
            })

            local phases = {}

            for phaseKey, phase in pairs(entry.phases) do
                local appearances = {}
                for _, appearance in pairs(phase.appearances) do
                    table.insert(appearances, {
                        ["$type"] = "CName",
                        ["$storage"] = "string",
                        ["$value"] = appearance
                    })
                end

                local periods = {}

                for periodKey, period in pairs(phase.timePeriods) do
                    local markings = {}
                    local spotRefs = {}
                    if #period.markings > 0 then
                        for _, marking in pairs(period.markings) do
                            table.insert(markings, {
                                ["$type"] = "CName",
                                ["$storage"] = "string",
                                ["$value"] = marking
                            })

                            -- Update spotRefs on communityAreaNode, resolved from markings
                            local refs = exportUI.getNodeRefsFromMarking(marking, spotNodes)
                            for _, ref in pairs(refs) do
                                table.insert(community.node.data.area.Data.entriesData[entryKey].phasesData[phaseKey].timePeriodsData[periodKey].spotNodeIds, {
                                    ["$type"] = "worldGlobalNodeID",
                                    ["hash"] = utils.nodeRefStringToHashString(ref["$value"])
                                })
                            end

                            utils.combine(spotRefs, refs)

                            if #spotRefs == 0 then
                                if not exportUI.exportIssues.markingUnresolved then
                                    exportUI.exportIssues.markingUnresolved = {}
                                end
                                table.insert(exportUI.exportIssues.markingUnresolved, {
                                    name = community.node.name,
                                    entry = entry.entryName,
                                    phase = phase.phaseName,
                                    period = periodEnums[period.hour + 1],
                                    marking = marking
                                })
                            end
                        end
                    else
                        for _, ref in pairs(period.spotNodeRefs) do
                            table.insert(spotRefs, {
                                ["$type"] = "NodeRef",
                                ["$storage"] = "string",
                                ["$value"] = ref
                            })
                            if not nodeRefs[ref] then
                                if not exportUI.exportIssues.spotReferencingEmpty then
                                    exportUI.exportIssues.spotReferencingEmpty = {}
                                end
                                table.insert(exportUI.exportIssues.spotReferencingEmpty, {
                                    name = community.node.name,
                                    entry = entry.entryName,
                                    phase = phase.phaseName,
                                    period = periodEnums[period.hour + 1],
                                    ref = ref
                                })
                            end
                        end
                    end

                    table.insert(periods, {
                        ["$type"] = "communityPhaseTimePeriod",
                        ["hour"] = periodEnums[period.hour + 1],
                        ["isSequence"] = period.isSequence and 1 or 0,
                        ["markings"] = markings,
                        ["quantity"] = period.quantity,
                        ["spotNodeRefs"] = spotRefs
                    })
                end

                table.insert(phases, {
                    ["Data"] = {
                        ["$type"] = "communitySpawnPhase",
                        ["appearances"] = appearances,
                        ["phaseName"] = {
                            ["$type"] = "CName",
                            ["$storage"] = "string",
                            ["$value"] = phase.phaseName
                        },
                        ["timePeriods"] = periods
                    }
                  })
            end

            table.insert(entries, {
                ["Data"] = {
                    ["$type"] = "communitySpawnEntry",
                    ["characterRecordId"] = {
                        ["$type"] = "TweakDBID",
                        ["$storage"] = "string",
                        ["$value"] = entry.characterRecordId
                    },
                    ["entryName"] = {
                        ["$type"] = "CName",
                        ["$storage"] = "string",
                        ["$value"] = entry.entryName
                    },
                    ["phases"] = phases,
                }
            })
        end

        table.insert(registryEntries, {
            ["$type"] = "worldCommunityRegistryItem",
            ["communityAreaType"] = "Regular",
            ["communityId"] = {
                ["$type"] = "gameCommunityID",
                ["entityId"] = {
                    ["$type"] = "entEntityID",
                    ["hash"] = utils.nodeRefStringToHashString(community.node.nodeRef)
                }
            },
            ["entriesInitialState"] = initialStates,
            ["template"] = {
                ["Data"] = {
                    ["$type"] = "communityCommunityTemplateData",
                    ["entries"] = entries
                }
            }
        })
    end

    if #wsPersistentData == 0 and #registryEntries == 0 then return end

    return {
        name = projectName .. "_always_loaded",
        min = { x = -99999, y = -99999, z = -99999 },
        max = { x = 99999, y = 99999, z = 99999 },
        category = "AlwaysLoaded",
        level = 1,
        nodes = {
            {
                ["scale"] = {
                    ["x"] = 1,
                    ["y"] = 1,
                    ["z"] = 1
                },
                ["data"] = {
                    ["workspotsPersistentData"] = wsPersistentData,
                    ["communitiesData"] = registryEntries
                },
                ["name"] = "registry",
                ["position"] = {
                    ["x"] = 0,
                    ["y"] = 0,
                    ["w"] = 0,
                    ["z"] = 0
                },
                ["rotation"] = {
                    ["j"] = 0,
                    ["k"] = 0,
                    ["i"] = 0,
                    ["r"] = 0
                },
                ["primaryRange"] = 99999999,
                ["secondaryRange"] = 17.320507,
                ["uk11"] = 512,
                ["type"] = "worldCommunityRegistryNode",
                ["nodeRef"] = "",
                ["uk10"] = 32
            }
        }
    }
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
        nodes = {},
        prefabRef = group.prefabRef,
        variantIndices = { 0 },
        variants = {}
    }

    local devices = {}
    local psEntries = {}
    local childs = {}
    local communities = {}
    local spotNodes = {}

    local objects = g:getPathsRecursive(false)
    local variantNodes = {
        default = {}
    }
    local variantInfo = {}
    local nodes = {}

    -- Group and bring the nodes in order, based on their variant, starting with default
    for groupName, variant in pairs(group.variantData) do
        if not variantNodes[variant.name] then
            variantNodes[variant.name] = {}
            variantInfo[variant.name] = {
                defaultOn = variant.defaultOn
            }
        end

        for _, node in pairs(g.childs) do
            if node.name == groupName then
                for _, entry in pairs(node:getPathsRecursive(false)) do
                    if utils.isA(entry.ref, "spawnableElement") and not entry.ref.spawnable.noExport then
                        table.insert(variantNodes[variant.name], entry)
                    end
                end
            end
        end
    end

    for _, node in pairs(g.childs) do
        if utils.isA(node, "spawnableElement") and not node.spawnable.noExport then
            table.insert(variantNodes["default"], { ref = node })
        end
    end

    nodes = variantNodes["default"]

    local index = 1
    for key, variant in pairs(variantNodes) do
        if key ~= "default" then
            table.insert(exported.variantIndices, #nodes)
            utils.combine(nodes, variant)

            table.insert(exported.variants, {
                name = key,
                index = index,
                defaultOn = variantInfo[key].defaultOn and 1 or 0,
                ref = group.variantRef
            })

            index = index + 1
        end
    end

    for key, object in pairs(nodes) do
        if utils.isA(object.ref, "spawnableElement") and not object.ref.spawnable.noExport then
            table.insert(exported.nodes, object.ref.spawnable:export(key, #objects))

            -- Handle device nodes
            if object.ref.spawnable.node == "worldDeviceNode" then
                exportUI.handleDevice(object, devices, psEntries, childs, nodes)
            elseif object.ref.spawnable.node == "worldCompiledCommunityAreaNode_Streamable" then
                table.insert(communities, { data = object.ref.spawnable.entries, node = exported.nodes[#exported.nodes] })
            elseif object.ref.spawnable.node == "worldAISpotNode" then
                table.insert(spotNodes, {
                    ref = object.ref.spawnable.nodeRef,
                    position = utils.fromVector(object.ref:getPosition()),
                    yaw = object.ref.spawnable.rotation.yaw,
                    markings = object.ref.spawnable.markings,
                    name = object.ref.name
                })
            end
        end
    end

    return exported, devices, psEntries, childs, communities, spotNodes
end

function exportUI.export()
    local project = {
        name = utils.createFileName(exportUI.projectName):lower():gsub(" ", "_"),
        sectors = {},
        devices = {},
        psEntries = {},
        version = minScriptVersion
    }

    local nodeRefs = {}
    local spotNodes = {}
    local communities = {}
    local childs = {}

    for _, group in pairs(exportUI.groups) do
        local data, devices, psEntries, subChilds, comms, spots = exportUI.exportGroup(group)
        if data then
            table.insert(project.sectors, data)

            for hash, device in pairs(devices) do
                project.devices[hash] = device
            end

            for PSID, entry in pairs(psEntries) do
                project.psEntries[PSID] = entry
            end

            utils.combine(communities, comms)
            utils.combine(spotNodes, spots)
            utils.combine(childs, subChilds)

            for _, node in pairs(data.nodes) do
                if not nodeRefs[node.nodeRef] then
                    nodeRefs[node.nodeRef] = node.name
                elseif node.nodeRef ~= "" then
                    exportUI.exportIssues.nodeRefDuplicated = {
                        nodeRef = node.nodeRef,
                        name1 = nodeRefs[node.nodeRef],
                        name2 = node.name
                    }
                    break
                end
            end
        end
    end

    for hash, device in pairs(project.devices) do
        for _, childHash in pairs(device.children) do
            if project.devices[childHash] then
                table.insert(project.devices[childHash].parents, hash)
            end
        end
    end

    -- TODO: Aggregate all parents of double entries, so a device that isnt a device can be linked to multiple parents
    local additionalEntries = {}
    for _, child in pairs(childs) do
        local hash = utils.nodeRefStringToHashString(child.ref)
        if not additionalEntries[hash] then
            additionalEntries[hash] = {
                hash = hash,
                className = child.className,
                nodePosition = child.nodePosition,
                parents = { child.parent },
                children = {}
            }
        else
            table.insert(additionalEntries[hash].parents, child.parent)
        end
    end

    for _, child in pairs(additionalEntries) do
        project.devices[child.hash] = child
    end

    local always_loaded = exportUI.handleCommunities(project.name, communities, spotNodes, nodeRefs)
    if always_loaded then
        table.insert(project.sectors, always_loaded)
    end

    config.saveFile("export/" .. project.name .. "_exported.json", project)

    print("[entSpawner] Exported project " .. project.name)
end

return exportUI