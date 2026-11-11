local config = require("modules/utils/core/config")
local utils = require("modules/utils/core/utils")
local style = require("modules/ui/style")
local history = require("modules/utils/project/history")
local settings = require("modules/utils/core/settings")
local field = require("modules/utils/ui/field")
local projectedWireframe = require("modules/utils/editor/projectedWireframe")
local groupExportManager = require("modules/utils/pipeline/groupExportManager")
local pipelineCommon = require("modules/utils/pipeline/common")
local streamingBox = require("modules/utils/pipeline/streamingBox")
local soundSystemData = require("modules/utils/data/soundSystem")

local minScriptVersion = "1.0.5"
local sectorCategory
local ELEVATOR_FLOOR_TERMINAL_CONTROLLER_CLASS = "ElevatorFloorTerminalControllerPS"
local SOUND_SYSTEM_CONTROLLER_CLASS = soundSystemData.SOUND_SYSTEM_CONTROLLER_CLASS
local serializedGroupModulePaths = {
    ["modules/classes/editor/positionableGroup"] = true,
    ["modules/classes/editor/randomizedGroup"] = true
}
local issueOrder = {
    "nodeRefDuplicated",
    "missingElevatorFloorSetup",
    "soundSystemSetup",
    "noOutlineMarkers",
    "noSplineMarker",
    "noConversationWorkspots",
    "splineEmptyRef",
    "spotEmptyRef",
    "spotReferencingEmpty",
    "markingUnresolved",
    "missingInitialPhase",
    "patrolWorkspotInfinite"
}
local streamingPresetLabels = {
    "Interior",
    "Street",
    "District",
    "Lanscape",
    "To the Moon"
}
local streamingPresetExtents = {
    { x = 150, y = 150, z = 100 },
    { x = 500, y = 500, z = 400 },
    { x = 1200, y = 1200, z = 1000 },
    { x = 6000, y = 6000, z = 5000 },
    { x = 3.4028235e+38, y = 3.4028235e+38, z = 3.4028235e+38 }
}

exportUI = {
    projectName = "",
    xlFormat = 0,
    groups = {},
    templates = {},
    spawner = nil,
    exportHovered = false,
    exportIssues = {
        nodeRefDuplicated = {},
        missingElevatorFloorSetup = {},
        soundSystemSetup = {},
        noOutlineMarkers = {},
        noSplineMarker = {},
        noConversationWorkspots = {},
        splineEmptyRef = {},
        spotEmptyRef = {},
        spotReferencingEmpty = {},
        markingUnresolved = {},
        missingInitialPhase = {},
        patrolWorkspotInfinite = {}
    },
    sectorPropertiesWidth = nil,
    mainPropertiesWidth = nil,
    templateDeletePopup = false,
    templateDeleteTarget = nil,
    templateDeleteDontAskAgain = false,
    templateSaveToasts = {},
    -- One state table per divider, so the two bars do not report each other's hover.
    groupsDivider = { hovered = false, dragging = false },
    templatesDivider = { hovered = false, dragging = false }
}

function exportUI.init(spawner)
    for _, file in pairs(dir("data/exportTemplates/")) do
        if file.name:match("^.+(%..+)$") == ".json" then
            local data = config.loadFile("data/exportTemplates/" .. file.name)

            if data.groups then
                for key, group in pairs(data.groups) do
                    -- Templates predate the name/file split, so entries without a uID still fall
                    -- back to the name; see exportUI.resolveGroupFileName.
                    local fileName = group.fileName or (tostring(group.name or "") .. ".json")
                    if not config.fileExists("data/objects/" .. fileName) then
                        data.groups[key] = nil
                    end
                end

                exportUI.templates[data.projectName] = data
            end
        end
    end

    exportUI.xlFormat = settings.defaultExportFormat or 0

    exportUI.spawner = spawner
end


local function drawVariantsTooltip()
    ImGui.SameLine()
    ImGui.Text(IconGlyphs.InformationOutline)
    style.tooltip("All objects placed within the root of the group will be part of the default variant\nLeave variant name empty (or set it to \"default\") to treat it as default/non-variant\nNamed variants use the Default variant state from Settings when first named.")
end

local function getDefaultNamedVariantState()
    return settings.defaultVariantOn == true
end

---Resolves which project file an export entry refers to.
---
---Entries carry the uID (`fileName`) since project files stopped being named after their group.
---Older entries -- saved templates, lists from before the split -- only have the name, which used to
---be the same thing, so that remains the fallback.
---@param group table? Export list entry, or `{ name = ... }`.
---@return string? fileName
function exportUI.resolveGroupFileName(group)
    if type(group) ~= "table" then return nil end

    if type(group.fileName) == "string" and group.fileName ~= "" then
        return group.fileName
    end

    local name = group.name
    if type(name) ~= "string" or name == "" then return nil end

    local savedUI = exportUI.spawner and exportUI.spawner.baseUI and exportUI.spawner.baseUI.savedUI or nil
    local files = savedUI and savedUI.files or nil

    if type(files) == "table" then
        for fileName, data in pairs(files) do
            if type(data) == "table" and data.name == name then
                return fileName
            end
        end
    end

    return name .. ".json"
end

---@param group table|string Export list entry, or a plain file name.
---@return table?
local function loadSavedGroupBlob(group)
    local fileName = type(group) == "string" and group or exportUI.resolveGroupFileName(group)
    if not fileName then return nil end

    local path = "data/objects/" .. fileName
    if not config.fileExists(path) then
        return nil
    end

    return config.loadFile(path)
end

---Computes an export-list entry's streaming box from its saved project, as the export does.
---@param group table Export-list entry.
---@param applyExtents boolean Also replace `streamingX/Y/Z` with the Auto extents.
---@return boolean computed False when the project is missing or has no exported element.
function exportUI.computeStreamingBox(group, applyExtents)
    local blob = loadSavedGroupBlob(group)
    if not blob then return false end

    local root = require("modules/classes/editor/positionableGroup"):new(exportUI.spawner.baseUI.spawnedUI)
    root:load(blob, true)

    local elements = streamingBox.collectExported(root)
    local center = streamingBox.getContentCenter(elements)
    if not center then return false end

    group.streamingCenter = center
    if applyExtents then
        local extents = streamingBox.getAutoExtents(center, elements)
        group.streamingX, group.streamingY, group.streamingZ = extents.x, extents.y, extents.z
    end

    return true
end

---@param entry table?
---@return boolean
local function isSerializedGroupEntry(entry)
    return entry ~= nil and (entry.type == "group" or serializedGroupModulePaths[entry.modulePath] == true)
end

---@param blob table?
---@param existingVariantData table?
---@return table
local function buildVariantDataFromBlob(blob, existingVariantData)
    local variants = {}

    for _, child in pairs(blob and blob.childs or {}) do
        if isSerializedGroupEntry(child) and child.name then
            local existing = existingVariantData and existingVariantData[child.name]
            variants[child.name] = {
                name = existing and existing.name or "",
                ref = existing and existing.ref or "",
                defaultOn = existing == nil or existing.defaultOn ~= false
            }
        end
    end

    return variants
end

---@param variantData table?
---@return string[]
local function getSortedVariantGroupNames(variantData)
    local names = utils.getKeys(variantData or {})

    table.sort(names, function(a, b)
        local aName = tostring(a or ""):lower()
        local bName = tostring(b or ""):lower()

        if aName == bName then
            return tostring(a or "") < tostring(b or "")
        end

        return aName < bName
    end)

    return names
end

---@param blob table?
---@param fallback table?
---@return table
local function resolveGroupCenter(blob, fallback)
    local source = nil
    if blob and blob.pos then
        source = blob.pos
    elseif blob and blob.origin then
        source = blob.origin
    end

    if source then
        return {
            x = source.x or 0,
            y = source.y or 0,
            z = source.z or 0
        }
    end

    if fallback then
        return {
            x = fallback.x or 0,
            y = fallback.y or 0,
            z = fallback.z or 0
        }
    end

    return { x = 0, y = 0, z = 0 }
end

---Center of the group's streaming box: the last one computed from its exported content, else the group position.
---@param group table
---@return Vector4?
local function getGroupCenterVector(group)
    local center = group and (group.streamingCenter or group.center)
    if not center then
        return nil
    end

    return Vector4.new(center.x or 0, center.y or 0, center.z or 0, 0)
end

local function drawGroupStreamingBoxes()
    local player = GetPlayer()
    if not player then return end

    local targets = {}
    for _, group in ipairs(exportUI.groups or {}) do
        if group.visualizeStreamingBox then
            local extentX = tonumber(group.streamingX) or 0
            local extentY = tonumber(group.streamingY) or 0
            local extentZ = tonumber(group.streamingZ) or 0
            local center = getGroupCenterVector(group)

            if center and extentX > 0 and extentY > 0 and extentZ > 0 then
                table.insert(targets, {
                    center = center,
                    extentX = extentX,
                    extentY = extentY,
                    extentZ = extentZ
                })
            end
        end
    end

    if #targets == 0 then return end

    local screen, drawList = projectedWireframe.beginOverlay("##wb-export-streaming-box-overlay-wui")
    if not screen then return end

    local playerPos = player:GetWorldPosition()
    local identityQuat = EulerAngles.new(0, 0, 0):ToQuat()

    for _, target in ipairs(targets) do
        local inside = projectedWireframe.isInsideStreamingExtents(playerPos, target.center, target.extentX, target.extentY, target.extentZ)
        local color, labelColor = projectedWireframe.getStreamingThemeColors(inside)

        projectedWireframe.drawOrientedBox(
            drawList,
            screen,
            target.center,
            identityQuat,
            Vector4.new(-target.extentX, -target.extentY, -target.extentZ, 0),
            Vector4.new(target.extentX, target.extentY, target.extentZ, 0),
            {
                frontColor = color,
                backColor = inside and 0x5500FF00 or 0x550000FF,
                frontThickness = 1.5 * style.viewSize,
                backThickness = 1.2 * style.viewSize,
                fadeNear = 45,
                fadeFar = 175,
                fadeLimit = 0.8,
                originColor = color,
                labelColor = labelColor,
                originDistance = utils.distanceVector(playerPos, target.center)
            }
        )
    end

    projectedWireframe.endOverlay()
end

local GROUPS_DEFAULT_HEIGHT = 260
local GROUPS_MIN_HEIGHT = 120
local GROUPS_MAX_HEIGHT = 800

---Clamp bounds for the groups list, in scaled pixels. Shared by the list and the divider that
---resizes it, which are drawn from different places.
---@return number minSize
---@return number maxSize
local function getGroupsHeightBounds()
    return GROUPS_MIN_HEIGHT * style.viewSize, GROUPS_MAX_HEIGHT * style.viewSize
end

function exportUI.drawGroups()
    local minSize, maxSize = getGroupsHeightBounds()
    settings.exportGroupsHeight = math.max(minSize, math.min(maxSize, settings.exportGroupsHeight or GROUPS_DEFAULT_HEIGHT))

    ImGui.PushStyleVar(ImGuiStyleVar.FrameBorderSize, 0)
    ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 0, 0)
    ImGui.PushStyleColor(ImGuiCol.FrameBg, 0)

    ImGui.BeginChildFrame(1, 0, settings.exportGroupsHeight)

    if #exportUI.groups > 0 then
        for key, group in ipairs(exportUI.groups) do
            ImGui.BeginGroup()

            local nodeFlags = ImGuiTreeNodeFlags.SpanFullWidth
            local groupOpen = ImGui.TreeNodeEx(group.name .. "##exportGroup" .. key, nodeFlags)

            -- Which project an entry points at is no longer implied by its name, and two entries may
            -- legitimately share one, so the row says which file it came from.
            ImGui.SameLine()
            style.mutedText(tostring(exportUI.resolveGroupFileName(group) or "?"))

            if groupOpen then
                ImGui.PopStyleColor()
                ImGui.PopStyleVar()

                if not exportUI.sectorPropertiesWidth then
                    exportUI.sectorPropertiesWidth = utils.getTextMaxWidth({ "Sector Category", "Sector Level" }) + ImGui.GetStyle().ItemSpacing.x + ImGui.GetCursorPosX()
                end

                if ImGui.TreeNodeEx("Variants", ImGuiTreeNodeFlags.SpanFullWidth) then
                    drawVariantsTooltip()

                    local baseCursorX = ImGui.GetCursorPosX()
                    style.mutedText("Variant Node Ref")
                    ImGui.SameLine()
                    group.variantRef = style.inputTextWithHint('##variantRef', '$/#foobar', group.variantRef, 100)

                    style.mutedText("Variant name")
                    local variantNameColumnWidth = 150 * style.viewSize
                    local defaultStateColumnWidth = 85 * style.viewSize
                    local defaultStateColumnX = baseCursorX + variantNameColumnWidth + ImGui.GetStyle().ItemSpacing.x
                    local groupNameColumnX = defaultStateColumnX + defaultStateColumnWidth
                    ImGui.SameLine()
                    ImGui.SetCursorPosX(defaultStateColumnX)
                    style.mutedText("Default state")
                    ImGui.SameLine()
                    ImGui.SetCursorPosX(groupNameColumnX)
                    style.mutedText("Group name")
                    ImGui.Separator()


                    for _, name in ipairs(getSortedVariantGroupNames(group.variantData)) do
                        local variantData = group.variantData[name]

                        if variantData ~= nil then
                            ImGui.PushID(name)
                            ImGui.SetNextItemWidth(variantNameColumnWidth)
                            local previousName = variantData.name or ""
                            local _, previousIsDefaultName = pipelineCommon.normalizeVariantName(previousName)
                            variantData.name = style.inputTextWithHint('##variantName', 'default', variantData.name, 100)
                            local variantNameTooltip = variantData.name or ""
                            style.tooltip(variantNameTooltip ~= "" and variantNameTooltip or "default")
                            ImGui.SameLine()
                            local normalizedName, isDefaultName = pipelineCommon.normalizeVariantName(variantData.name)
                            local changed = false
                            ImGui.BeginDisabled(isDefaultName)
                            variantData.defaultOn, changed = style.toggleButton(IconGlyphs.EyeOutline, variantData.defaultOn)
                            ImGui.SameLine()
                            ImGui.Text(variantData.defaultOn and "Visible" or "Hidden")
                            ImGui.EndDisabled()
                            if isDefaultName then
                                variantData.defaultOn = true
                            elseif previousName ~= variantData.name and previousIsDefaultName then
                                -- If the name was changed from default/non-variant, apply the configured default state.
                                variantData.defaultOn = getDefaultNamedVariantState()
                                changed = true
                            end
                            if changed and not isDefaultName then
                                for variant, _ in pairs(group.variantData) do
                                    local siblingName = group.variantData[variant] and group.variantData[variant].name
                                    local siblingNormalizedName, siblingIsDefaultName = pipelineCommon.normalizeVariantName(siblingName)
                                    if not siblingIsDefaultName and siblingNormalizedName == normalizedName then
                                        group.variantData[variant].defaultOn = variantData.defaultOn
                                    end
                                end
                            end
                            ImGui.SameLine()
                            ImGui.SetCursorPosX(groupNameColumnX)
                            style.mutedText(name)
                            style.tooltip(name)

                            ImGui.PopID()
                        end
                    end

                    ImGui.Dummy(0, 4 * style.viewSize)
                    ImGui.TreePop()
                else
                    drawVariantsTooltip()
                end

                style.mutedText("Sector Category")
                style.tooltip("Select the type of the sector for the group, if in doubt use Interior or Exterior")
                ImGui.SameLine()
                ImGui.SetCursorPosX(exportUI.sectorPropertiesWidth)
                ImGui.SetNextItemWidth(150 * style.viewSize)
                group.category = ImGui.Combo("##category", group.category, sectorCategory, #sectorCategory)

                if group.category == 3 then
                    style.mutedText("Prefab Ref")
                    style.tooltip("Prefab NodeRef of the sector")
                    ImGui.SameLine()
                    ImGui.SetCursorPosX(exportUI.sectorPropertiesWidth)
                    ImGui.SetNextItemWidth(150 * style.viewSize)

                    group.prefabRef, _ = style.inputTextWithHint('##prefabRef', '$/#foobar', group.prefabRef, 100)
                end

                style.mutedText("Sector Level")
                style.tooltip("Select the level of the sector for the group")
                ImGui.SameLine()
                ImGui.SetCursorPosX(exportUI.sectorPropertiesWidth)
                ImGui.SetNextItemWidth(150 * style.viewSize)
                group.level, changed = ImGui.InputInt("##level", group.level)
                if changed then
                    group.level = math.min(math.max(group.level, 0), 6)
                end

                if ImGui.TreeNodeEx("Streaming Box", ImGuiTreeNodeFlags.SpanFullWidth) then
                    local streamingPropertiesWidth = utils.getTextMaxWidth({ "Visualize", "Distance Preset", "Auto on Export", "Box Extents" }) + ImGui.GetStyle().ItemSpacing.x + ImGui.GetCursorPosX()

                    style.mutedText("Visualize")
                    style.tooltip("Draw a projected wireframe of this group's streaming box in the world view.")
                    ImGui.SameLine()
                    ImGui.SetCursorPosX(streamingPropertiesWidth)
                    group.visualizeStreamingBox, _ = ImGui.Checkbox("##visualizeStreamingBox", group.visualizeStreamingBox == true)

                    style.mutedText("Distance Preset")
                    ImGui.SameLine()
                    ImGui.SetCursorPosX(streamingPropertiesWidth)
                    ImGui.SetNextItemWidth(140 * style.viewSize)
                    group.streamingPresetIndex = ImGui.Combo("##groupStreamingDistancePreset", group.streamingPresetIndex or 0, streamingPresetLabels, #streamingPresetLabels)
                    style.tooltip("Quickly set Streaming Box Extents to a common value.\n- Interior: Small rooms and indoor props loaded only when close.\n- Street: Regular city assets visible from nearby streets.\n- District: Medium-large city chunks visible across a wider district area.\n- Landscape: Large outdoor landmarks visible from far away.\n- To the Moon: Keep visible from anywhere; use only for very important assets.")
                    ImGui.SameLine()
                    if ImGui.Button("Apply##groupStreamingDistancePreset") then
                        local preset = streamingPresetExtents[(group.streamingPresetIndex or 0) + 1]
                        if preset then
                            group.streamingX = preset.x
                            group.streamingY = preset.y
                            group.streamingZ = preset.z
                            group.streamingAuto = false
                        end
                    end
                    style.tooltip("Apply the selected preset to Streaming Box Extents.\nTurns off Auto on Export.")

                    style.mutedText("Auto on Export")
                    style.tooltip("Recompute Box Extents from the group's content on every export.\nThe X/Y/Z fields then show the last computed values.")
                    ImGui.SameLine()
                    ImGui.SetCursorPosX(streamingPropertiesWidth)
                    group.streamingAuto, _ = ImGui.Checkbox("##streamingAuto", group.streamingAuto == true)

                    style.mutedText("Box Extents")
                    style.tooltip("Size of the sector's streaming box, extending the given amount on each axis in both directions.\nThe box is centered on the group's exported content.")
                    ImGui.SameLine()
                    ImGui.SetCursorPosX(streamingPropertiesWidth)
                    if ImGui.Button("Auto") then
                        exportUI.computeStreamingBox(group, true)
                    end
                    style.tooltip(string.format("Compute box extents from the group's saved content.\nCovers each exported element's position plus its streaming range (capped at %d), with a %d%% margin.\nReplaces the current X/Y/Z values.", streamingBox.rangeCap, math.floor((streamingBox.margin - 1) * 100 + 0.5)))
                    ImGui.SameLine()
                    ImGui.BeginDisabled(group.streamingAuto == true)
                    group.streamingX, _, _ = field.advancedTrackedFloat(nil, "##x", group.streamingX, {
                        step = 0.25,
                        min = 0,
                        max = 3.4028235e+38,
                        format = "%.1f",
                        width = 84,
                        suffix = " X Size"
                    })
                    ImGui.SameLine()
                    group.streamingY, _, _ = field.advancedTrackedFloat(nil, "##y", group.streamingY, {
                        step = 0.25,
                        min = 0,
                        max = 3.4028235e+38,
                        format = "%.1f",
                        width = 84,
                        suffix = " Y Size"
                    })
                    ImGui.SameLine()
                    group.streamingZ, _, _ = field.advancedTrackedFloat(nil, "##z", group.streamingZ, {
                        step = 0.25,
                        min = 0,
                        max = 3.4028235e+38,
                        format = "%.1f",
                        width = 84,
                        suffix = " Z Size"
                    })
                    ImGui.EndDisabled()
                    ImGui.SameLine()

                    local player = GetPlayer()
                    local center = getGroupCenterVector(group)
                    local playerPos = player and player:GetWorldPosition() or Vector4.new(0, 0, 0, 0)
                    local inside = false

                    if center and player then
                        inside = projectedWireframe.isInsideStreamingExtents(playerPos, center, group.streamingX, group.streamingY, group.streamingZ)
                    end

                    local distance = center and utils.distanceVector(center, playerPos) or 0
                    style.styledText(IconGlyphs.AxisArrowInfo, inside and 0xFF00FF00 or 0xFF0000FF)
                    style.tooltip("Distance to player: " .. string.format("%.2f", distance))

                    ImGui.TreePop()
                end

                if ImGui.Button("Remove from list") then
                    table.remove(exportUI.groups, key)
                end

                ImGui.Dummy(0, 4 * style.viewSize)
                ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 0, 0)
                ImGui.PushStyleColor(ImGuiCol.FrameBg, 0)
                ImGui.TreePop()
            end
            ImGui.EndGroup()
        end
    else
        ImGui.PushStyleColor(ImGuiCol.Text, style.mutedColor)
        ImGui.TextWrapped("No groups yet added, add them from the \"Saved\" tab!")
        ImGui.PopStyleColor()
    end

    ImGui.EndChildFrame()
    ImGui.PopStyleColor()
    ImGui.PopStyleVar(2)
    drawGroupStreamingBoxes()
end

---The bar that resizes the groups list. Drawn under the card holding Properties and Groups rather
---than inside it, so it reads as the edge the card is resized by and spans the full tab width.
function exportUI.drawGroupsDivider()
    local minSize, maxSize = getGroupsHeightBounds()

    local wasDragging = exportUI.groupsDivider.dragging
    local delta, reset = style.drawHorizontalDivider("##groupsDivider", exportUI.groupsDivider)

    if reset then
        settings.exportGroupsHeight = GROUPS_DEFAULT_HEIGHT
        settings.save()
    elseif delta ~= 0 then
        settings.exportGroupsHeight = math.max(minSize, math.min(maxSize, settings.exportGroupsHeight + delta))
    elseif wasDragging and not exportUI.groupsDivider.dragging then
        -- Written once the drag lets go, rather than on every frame of it.
        settings.save()
    end
end

function exportUI.loadTemplate(data)
    -- Keyed by uID rather than name: a template listing two projects that happen to share a name has
    -- to bring in both, and re-loading a template must not duplicate what is already listed.
    local existingFiles = {}
    for _, existing in ipairs(exportUI.groups) do
        local fileName = exportUI.resolveGroupFileName(existing)
        if fileName then
            existingFiles[fileName] = true
        end
    end

    for _, group in pairs(data.groups or {}) do
        local blob = loadSavedGroupBlob(group)
        if blob then
            local mapped = {
                name = group.name,
                fileName = exportUI.resolveGroupFileName(group),
                category = group.category or 1,
                level = group.level or 1,
                visualizeStreamingBox = group.visualizeStreamingBox == true,
                streamingPresetIndex = group.streamingPresetIndex or 0,
                streamingX = group.streamingX or 150,
                streamingY = group.streamingY or 150,
                streamingZ = group.streamingZ or 100,
                streamingAuto = group.streamingAuto == true,
                center = resolveGroupCenter(blob, group.center),
                prefabRef = group.prefabRef or "",
                variantRef = group.variantRef or "",
                variantData = buildVariantDataFromBlob(blob, group.variantData)
            }

            if mapped.fileName and not existingFiles[mapped.fileName] then
                table.insert(exportUI.groups, mapped)
                existingFiles[mapped.fileName] = true
            end
        end
    end

    exportUI.xlFormat = data.xlFormat or 0
    exportUI.projectName = data.projectName
end

---@param key string
---@param data table
local function deleteTemplateEntry(key, data)
    local templateName = data and data.projectName or key
    if not templateName then return end

    os.remove("data/exportTemplates/" .. templateName .. ".json")
    exportUI.templates[key] = nil
end

---@param key string
---@param data table
function exportUI.deleteTemplate(key, data)
    if settings.skipTemplateDeleteConfirm then
        deleteTemplateEntry(key, data)
        return
    end

    exportUI.templateDeletePopup = true
    exportUI.templateDeleteTarget = { key = key, data = data }
    exportUI.templateDeleteDontAskAgain = settings.skipTemplateDeleteConfirm
end

function exportUI.handleTemplateDeletePopup()
    if exportUI.templateDeletePopup then
        ImGui.OpenPopup("Delete Template?##wb-wui")
        if ImGui.BeginPopupModal("Delete Template?##wb-wui", true, ImGuiWindowFlags.AlwaysAutoResize) then
            local targetName = exportUI.templateDeleteTarget and exportUI.templateDeleteTarget.data and exportUI.templateDeleteTarget.data.projectName or "Unknown"
            ImGui.Text("Delete \"" .. targetName .. "\"?")
            style.mutedText("This action cannot be undone.")
            ImGui.Dummy(0, 8 * style.viewSize)
            exportUI.templateDeleteDontAskAgain = ImGui.Checkbox("Don't ask again", exportUI.templateDeleteDontAskAgain)
            ImGui.Dummy(0, 8 * style.viewSize)

            if ImGui.Button("Cancel") then
                ImGui.CloseCurrentPopup()
                exportUI.templateDeletePopup = false
                exportUI.templateDeleteTarget = nil
            end

            ImGui.SameLine()

            if ImGui.Button("Confirm") then
                ImGui.CloseCurrentPopup()
                settings.skipTemplateDeleteConfirm = exportUI.templateDeleteDontAskAgain
                settings.save()

                local target = exportUI.templateDeleteTarget
                if target and target.key and target.data then
                    deleteTemplateEntry(target.key, target.data)
                end

                exportUI.templateDeletePopup = false
                exportUI.templateDeleteTarget = nil
            end

            ImGui.EndPopup()
        end
    end
end

function exportUI.drawTemplates()
    local defaultSize = 160
    local minSize = 80 * style.viewSize
    local maxSize = 500 * style.viewSize
    local defaultFramePaddingX = ImGui.GetStyle().FramePadding.x
    local defaultFramePaddingY = ImGui.GetStyle().FramePadding.y
    settings.exportTemplatesHeight = math.max(minSize, math.min(maxSize, settings.exportTemplatesHeight or 160))

    if utils.tableLength(exportUI.templates) > 0 then
        ImGui.PushStyleVar(ImGuiStyleVar.FrameBorderSize, 0)
        ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 0, 0)
        ImGui.PushStyleColor(ImGuiCol.FrameBg, 0)

        ImGui.BeginChildFrame(2, 0, settings.exportTemplatesHeight)

        local sortedTemplates = {}
        for key, data in pairs(exportUI.templates) do
            table.insert(sortedTemplates, { key = key, data = data })
        end

        table.sort(sortedTemplates, function(a, b)
            local aName = tostring(a.data.projectName or a.key or ""):lower()
            local bName = tostring(b.data.projectName or b.key or ""):lower()

            if aName == bName then
                return tostring(a.key) < tostring(b.key)
            end

            return aName < bName
        end)

        if ImGui.BeginTable("##exportTemplatesTable", 3, ImGuiTableFlags.SizingStretchProp or ImGuiTableFlags.NoHostExtendX) then
            ImGui.TableSetupColumn("##templateName", ImGuiTableColumnFlags.WidthStretch, 0.55)
            ImGui.TableSetupColumn("##templateGroups", ImGuiTableColumnFlags.WidthStretch, 0.20)
            ImGui.TableSetupColumn("##templateActions", ImGuiTableColumnFlags.WidthStretch, 0.25)

            for _, entry in ipairs(sortedTemplates) do
                local key = entry.key
                local data = entry.data
                local templateName = tostring(data.projectName or key)
                local groupLabel = tostring(#data.groups)
                local rowHeight = ImGui.GetFrameHeight() + defaultFramePaddingY * 2
                local loadWidth = ImGui.CalcTextSize("Load") + defaultFramePaddingX * 2
                local deleteWidth = ImGui.CalcTextSize(IconGlyphs.DeleteOutline) + defaultFramePaddingX * 2
                local actionsWidth = loadWidth + ImGui.GetStyle().ItemSpacing.x + deleteWidth
                local rowActivated = false
                local rowHovered = false

                ImGui.TableNextRow(ImGuiTableRowFlags.None, rowHeight)
                ImGui.PushID(key)

                ImGui.TableSetColumnIndex(0)
                local rowContentY = ImGui.GetCursorPosY()
                ImGui.PushStyleColor(ImGuiCol.Header, 0, 0, 0, 0)
                ImGui.PushStyleColor(ImGuiCol.HeaderHovered, 0, 0, 0, 0)
                ImGui.PushStyleColor(ImGuiCol.HeaderActive, 0, 0, 0, 0)
                ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, defaultFramePaddingX, defaultFramePaddingY)
                rowActivated = ImGui.Selectable("##templateRow", false, ImGuiSelectableFlags.SpanAllColumns + ImGuiSelectableFlags.AllowOverlap + ImGuiSelectableFlags.AllowDoubleClick)
                rowHovered = ImGui.IsItemHovered()
                ImGui.PopStyleVar()
                ImGui.PopStyleColor(3)
                ImGui.SetItemAllowOverlap()
                ImGui.TableSetColumnIndex(0)
                ImGui.SetCursorPosY(rowContentY)
                ImGui.AlignTextToFramePadding()
                ImGui.Text(templateName)

                ImGui.TableSetColumnIndex(1)
                ImGui.SetCursorPosY(rowContentY)
                local groupStartX = ImGui.GetCursorPosX()
                local groupAvailWidth = ImGui.GetContentRegionAvail()
                local groupWidth = ImGui.CalcTextSize(groupLabel)
                ImGui.SetCursorPosX(groupStartX + math.max(0, (groupAvailWidth - groupWidth) / 2))
                ImGui.AlignTextToFramePadding()
                style.mutedText(groupLabel)

                ImGui.TableSetColumnIndex(2)
                ImGui.SetCursorPosY(rowContentY)
                local actionsStartX = ImGui.GetCursorPosX()
                local actionsAvailWidth = ImGui.GetContentRegionAvail()
                local loadButtonHovered = false
                local deleteButtonHovered = false
                ImGui.SetCursorPosX(actionsStartX + math.max(0, actionsAvailWidth - actionsWidth))
                ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, defaultFramePaddingX, defaultFramePaddingY)
                if ImGui.Button("Load") then
                    exportUI.loadTemplate(data)
                end
                loadButtonHovered = ImGui.IsItemHovered()
                ImGui.SameLine()
                if style.dangerButton(IconGlyphs.DeleteOutline) then
                    exportUI.deleteTemplate(key, data)
                end
                deleteButtonHovered = ImGui.IsItemHovered()
                ImGui.PopStyleVar()

                if rowHovered then
                    ImGui.TableSetBgColor(ImGuiTableBgTarget.RowBg0, 0.30, 0.30, 0.30, 0.20)
                end
                if rowActivated and not loadButtonHovered and not deleteButtonHovered and ImGui.IsMouseDoubleClicked(ImGuiMouseButton.Left) then
                    exportUI.loadTemplate(data)
                end

                ImGui.PopID()
            end

            ImGui.EndTable()
        end

        ImGui.EndChildFrame()
        ImGui.PopStyleColor()
        ImGui.PopStyleVar(2)
    else
        ImGui.PushStyleVar(ImGuiStyleVar.FrameBorderSize, 0)
        ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 0, 0)
        ImGui.PushStyleColor(ImGuiCol.FrameBg, 0)
        ImGui.BeginChildFrame(2, 0, settings.exportTemplatesHeight)
        ImGui.PushStyleColor(ImGuiCol.Text, style.mutedColor)
        ImGui.TextWrapped("No templates created yet.")
        ImGui.PopStyleColor()
        ImGui.EndChildFrame()
        ImGui.PopStyleColor()
        ImGui.PopStyleVar(2)
    end

    local wasDragging = exportUI.templatesDivider.dragging
    local delta, reset = style.drawHorizontalDivider("##templatesDivider", exportUI.templatesDivider)

    if reset then
        settings.exportTemplatesHeight = defaultSize
        settings.save()
    elseif delta ~= 0 then
        settings.exportTemplatesHeight = math.max(minSize, math.min(maxSize, settings.exportTemplatesHeight + delta))
    elseif wasDragging and not exportUI.templatesDivider.dragging then
        settings.save()
    end
end

function exportUI.getCurrentIssue()
    for _, key in ipairs(issueOrder) do
        local value = exportUI.exportIssues[key]
        if #value ~= 0 then
            return key
        end
    end
end

function exportUI.resetIssues()
    for _, key in ipairs(issueOrder) do
        exportUI.exportIssues[key] = {}
    end
end

function exportUI.hasBlockingIssues()
    return exportUI.getCurrentIssue() ~= nil
end

function exportUI.drawToasts()
    groupExportManager.drawToasts()
    pipelineCommon.drawQueuedToasts(exportUI.templateSaveToasts)
end

function exportUI.cancelExport(reason, suppressToast)
    return groupExportManager.cancel(reason, suppressToast)
end

function exportUI.drawExportProgress()
    return groupExportManager.drawProgress(style)
end

---Strips the "[Type] " prefix `spawnable:export` puts in front of every exported node name.
---@param name string?
---@param fallback string
---@return string
local function cleanExportedNodeName(name, fallback)
    return (tostring(name or fallback):gsub("^%[[^%]]*%]%s*", ""))
end

---Flags patrol point workspots left on "Is Infinite".
---
---A patrol spline drives its NPC from one workspot to the next, but an infinite workspot never
---releases the actor, so the NPC stops at the first one it reaches and the rest of the route is
---dead. The editor's AI Spot defaults `Is Infinite` to on, which is right for a standalone
---workspot and wrong for every patrol point, hence the check.
---
---Runs over the whole project rather than one sector: patrol points reach their workspots by
---NodeRef, so the two nodes are regularly authored in different groups.
---@param sectors table[] Exported sectors of the current run.
local function collectInfinitePatrolWorkspots(sectors)
    local spotsByRef = {}

    for _, sector in ipairs(sectors or {}) do
        for _, node in ipairs(sector.nodes or {}) do
            local ref = node.nodeRef or ""
            if node.type == "worldAISpotNode" and ref ~= "" then
                spotsByRef[ref] = node
                -- A hand-typed ref can be stored as its hash; index both forms so it still matches.
                spotsByRef[utils.nodeRefStringToHashString(ref)] = node
            end
        end
    end

    for _, sector in ipairs(sectors or {}) do
        for _, node in ipairs(sector.nodes or {}) do
            if node.type == "worldPatrolSplineNode" then
                for index, pointDef in ipairs(node.data and node.data.patrolPointDefs or {}) do
                    local def = pointDef.Data

                    if def and def.pointType == "Workspot" then
                        local ref = def.node and def.node["$value"] or ""
                        local spot = spotsByRef[ref]

                        if spot and spot.data and spot.data.isWorkspotInfinite == 1 then
                            table.insert(exportUI.exportIssues.patrolWorkspotInfinite, {
                                spline = cleanExportedNodeName(node.name, "Unnamed Patrol Spline"),
                                point = index,
                                spot = cleanExportedNodeName(spot.name, "Unnamed AISpot"),
                                ref = ref,
                                node = spot
                            })
                        end
                    end
                end
            end
        end
    end
end

---Clears `Is Infinite` on every AISpot the check flagged, in both places it has to be cleared:
---the node already written into this export run, and the AISpot spawnable it came from, so the
---fix sticks for the next export and shows up in the inspector. The spawnable edits go in as one
---composite history action, undoable in a single step.
local function fixInfinitePatrolWorkspots()
    local issues = exportUI.exportIssues.patrolWorkspotInfinite
    if #issues == 0 then return end

    local spawnedUI = exportUI.spawner and exportUI.spawner.baseUI and exportUI.spawner.baseUI.spawnedUI or nil
    local elementsByRef = {}

    if spawnedUI then
        spawnedUI.ensureCache()

        for _, entry in pairs(spawnedUI.paths) do
            local element = entry.ref
            local spawnable = utils.isA(element, "spawnableElement") and element.spawnable or nil

            if spawnable and spawnable.node == "worldAISpotNode" and (spawnable.nodeRef or "") ~= "" then
                elementsByRef[spawnable.nodeRef] = element
                elementsByRef[utils.nodeRefStringToHashString(spawnable.nodeRef)] = element
            end
        end
    end

    local pending = {}
    local seen = {}

    for _, issue in ipairs(issues) do
        if issue.node and issue.node.data then
            issue.node.data.isWorkspotInfinite = 0
        end

        local element = elementsByRef[issue.ref]
        -- Several patrol points may share one workspot, so only track each element once.
        if element and not seen[element] and element.spawnable.isWorkspotInfinite then
            seen[element] = true
            table.insert(pending, element)
        end
    end

    if #pending > 0 then
        -- Snapshots the pre-edit state, so it has to be built before the flags are cleared.
        history.addAction(history.getMultiSelectChange(pending))

        for _, element in ipairs(pending) do
            element.spawnable.isWorkspotInfinite = false
        end
    end
end

local function resolveIssue(issueKey, forceExport)
    if not issueKey then
        return
    end

    exportUI.exportIssues[issueKey] = {}
    ImGui.CloseCurrentPopup()

    if groupExportManager.isPaused() then
        if forceExport then
            if not exportUI.hasBlockingIssues() then
                groupExportManager.resume()
            end
        else
            exportUI.resetIssues()
            exportUI.cancelExport("validation issue")
        end
    end
end

---@class issueFixButton
---@field label string Button label.
---@field tooltip string? Hover text.
---@field action fun() Applies the fix. Runs before the issue list is cleared, so it can read it.

---@param issueKey string
---@param fix issueFixButton? Optional "repair it for me" button, shown only while the export waits.
local function drawIssueButtons(issueKey, fix)
    if ImGui.Button("OK") then
        resolveIssue(issueKey, false)
    end

    if groupExportManager.isPaused() then
        if fix then
            ImGui.SameLine()
            if ImGui.Button(fix.label) then
                fix.action()
                resolveIssue(issueKey, true)
            end
            if fix.tooltip then
                style.tooltip(fix.tooltip)
            end
        end

        ImGui.SameLine()
        if style.warnButton("Force export") then
            resolveIssue(issueKey, true)
        end
    end
end

function exportUI.drawIssues()
    if exportUI.getCurrentIssue() == "nodeRefDuplicated" then
        ImGui.OpenPopup("Duplicated NodeRefs##wb-wui")
        if ImGui.BeginPopupModal("Duplicated NodeRefs##wb-wui", true, ImGuiWindowFlags.AlwaysAutoResize) then
            ImGui.Text("Duplicated nodeRefs found, please fix them before exporting!")

            ImGui.Separator()

            for _, duplicate in pairs(exportUI.exportIssues.nodeRefDuplicated) do
                style.mutedText("NodeRef:")
                ImGui.SameLine()
                ImGui.Text(duplicate.nodeRef)

                style.mutedText("Node 1: ")
                ImGui.SameLine()
                ImGui.Text(duplicate.name1)

                style.mutedText("Node 2: ")
                ImGui.SameLine()
                ImGui.Text(duplicate.name2)
            end

            ImGui.Separator()

            drawIssueButtons("nodeRefDuplicated")
            ImGui.EndPopup()
        end
    end
    if exportUI.getCurrentIssue() == "missingElevatorFloorSetup" then
        ImGui.OpenPopup("Missing Elevator Floor Setup##wb-wui")
        if ImGui.BeginPopupModal("Missing Elevator Floor Setup##wb-wui", true, ImGuiWindowFlags.AlwaysAutoResize) then
            ImGui.Text("Persistent elevator floor terminal data is missing and export cannot safely create .psrep entries.")

            ImGui.Separator()

            for _, entry in pairs(exportUI.exportIssues.missingElevatorFloorSetup) do
                style.mutedText("Node Name:")
                ImGui.SameLine()
                ImGui.Text(entry.name)

                style.mutedText("Group:")
                ImGui.SameLine()
                ImGui.Text(entry.group)

                style.mutedText("NodeRef:")
                ImGui.SameLine()
                ImGui.Text(entry.nodeRef ~= "" and entry.nodeRef or "(empty)")

                style.mutedText("Issue:")
                ImGui.SameLine()
                ImGui.Text(entry.reason)

                ImGui.Separator()
            end

            drawIssueButtons("missingElevatorFloorSetup")
            ImGui.EndPopup()
        end
    end
    if exportUI.getCurrentIssue() == "soundSystemSetup" then
        ImGui.OpenPopup("Sound System Setup##wb-wui")
        if ImGui.BeginPopupModal("Sound System Setup##wb-wui", true, ImGuiWindowFlags.AlwaysAutoResize) then
            ImGui.Text("These sound systems export without error but will not play as set up.")

            ImGui.Separator()

            for _, entry in pairs(exportUI.exportIssues.soundSystemSetup) do
                style.mutedText("Node Name:")
                ImGui.SameLine()
                ImGui.Text(entry.name)

                style.mutedText("Group:")
                ImGui.SameLine()
                ImGui.Text(entry.group)

                style.mutedText("NodeRef:")
                ImGui.SameLine()
                ImGui.Text(entry.nodeRef ~= "" and entry.nodeRef or "(empty)")

                style.mutedText("Issue:")
                ImGui.SameLine()
                ImGui.Text(entry.reason)

                ImGui.Separator()
            end

            drawIssueButtons("soundSystemSetup")
            ImGui.EndPopup()
        end
    end
    if exportUI.getCurrentIssue() == "noOutlineMarkers" then
        ImGui.OpenPopup("Missing Outline Markers##wb-wui")
        if ImGui.BeginPopupModal("Missing Outline Markers##wb-wui", true, ImGuiWindowFlags.AlwaysAutoResize) then
            ImGui.Text("The following area nodes have no outline, possibly due to a broken outline group link!")

            ImGui.Separator()

            for _, area in pairs(exportUI.exportIssues.noOutlineMarkers) do
                style.mutedText("Area Name:")
                ImGui.SameLine()
                ImGui.Text(area)

                ImGui.Separator()
            end

            drawIssueButtons("noOutlineMarkers")
            ImGui.EndPopup()
        end
    end
    if exportUI.getCurrentIssue() == "noSplineMarker" then
        ImGui.OpenPopup("Missing Spline Points##wb-wui")
        if ImGui.BeginPopupModal("Missing Spline Points##wb-wui", true, ImGuiWindowFlags.AlwaysAutoResize) then
            ImGui.Text("The following spline nodes have no points, possibly due to a broken spline group link!")

            ImGui.Separator()

            for _, spline in pairs(exportUI.exportIssues.noSplineMarker) do
                style.mutedText("Spline Name:")
                ImGui.SameLine()
                ImGui.Text(spline)

                ImGui.Separator()
            end

            drawIssueButtons("noSplineMarker")
            ImGui.EndPopup()
        end
    end
    if exportUI.getCurrentIssue() == "noConversationWorkspots" then
        ImGui.OpenPopup("Missing Conversation Workspots##wb-wui")
        if ImGui.BeginPopupModal("Missing Conversation Workspots##wb-wui", true, ImGuiWindowFlags.AlwaysAutoResize) then
            ImGui.Text("The following conversation areas have no workspots assigned, so they have no actors to play their scenes on!")

            ImGui.Separator()

            for _, name in pairs(exportUI.exportIssues.noConversationWorkspots) do
                style.mutedText("Area Name:")
                ImGui.SameLine()
                ImGui.Text(name)

                ImGui.Separator()
            end

            drawIssueButtons("noConversationWorkspots")
            ImGui.EndPopup()
        end
    end
    if exportUI.getCurrentIssue() == "splineEmptyRef" then
        ImGui.OpenPopup("Empty Spline NodeRef##wb-wui")
        if ImGui.BeginPopupModal("Empty Spline NodeRef##wb-wui", true, ImGuiWindowFlags.AlwaysAutoResize) then
            ImGui.Text("The following Spline nodes do not have a NodeRef assigned to them, making them unusable!")

            ImGui.Separator()

            for _, name in pairs(exportUI.exportIssues.splineEmptyRef) do
                style.mutedText("Node Name:")
                ImGui.SameLine()
                ImGui.Text(name)
            end

            ImGui.Separator()

            drawIssueButtons("splineEmptyRef")
            ImGui.EndPopup()
        end
    end
    if exportUI.getCurrentIssue() == "spotEmptyRef" then
        ImGui.OpenPopup("Empty AISpot NodeRef##wb-wui")
        if ImGui.BeginPopupModal("Empty AISpot NodeRef##wb-wui", true, ImGuiWindowFlags.AlwaysAutoResize) then
            ImGui.Text("The following AISpot's do not have a NodeRef assigned to them, making them unusable!")

            ImGui.Separator()

            for _, name in pairs(exportUI.exportIssues.spotEmptyRef) do
                style.mutedText("Node Name:")
                ImGui.SameLine()
                ImGui.Text(name)
            end

            ImGui.Separator()

            drawIssueButtons("spotEmptyRef")
            ImGui.EndPopup()
        end
    end
    if exportUI.getCurrentIssue() == "spotReferencingEmpty" then
        ImGui.OpenPopup("Community Referencing Missing NodeRef##wb-wui")
        if ImGui.BeginPopupModal("Community Referencing Missing NodeRef##wb-wui", true, ImGuiWindowFlags.AlwaysAutoResize) then
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

            drawIssueButtons("spotReferencingEmpty")
            ImGui.EndPopup()
        end
    end
    if exportUI.getCurrentIssue() == "markingUnresolved" then
        ImGui.OpenPopup("Unresolved Marking##wb-wui")
        if ImGui.BeginPopupModal("Unresolved Marking##wb-wui", true, ImGuiWindowFlags.AlwaysAutoResize) then
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

            drawIssueButtons("markingUnresolved")
            ImGui.EndPopup()
        end
    end
    if exportUI.getCurrentIssue() == "missingInitialPhase" then
        ImGui.OpenPopup("Missing Initial Phase##wb-wui")
        if ImGui.BeginPopupModal("Missing Initial Phase##wb-wui", true, ImGuiWindowFlags.AlwaysAutoResize) then
            ImGui.Text("The following Community Entries reference non-existing phases as their initial phase.")

            ImGui.Separator()

            for _, entry in pairs(exportUI.exportIssues.missingInitialPhase) do
                style.mutedText("Node Name:")
                ImGui.SameLine()
                ImGui.Text(entry.name)

                style.mutedText("Community Entry:")
                ImGui.SameLine()
                ImGui.Text(entry.entry)

                style.mutedText("Missing Phase:")
                ImGui.SameLine()
                ImGui.Text(entry.phase)

                ImGui.Separator()
            end

            drawIssueButtons("missingInitialPhase")
            ImGui.EndPopup()
        end
    end
    if exportUI.getCurrentIssue() == "patrolWorkspotInfinite" then
        ImGui.OpenPopup("Infinite Patrol Workspot##wb-wui")
        if ImGui.BeginPopupModal("Infinite Patrol Workspot##wb-wui", true, ImGuiWindowFlags.AlwaysAutoResize) then
            ImGui.Text("The following AISpots are used as patrol points, but have \"Is Infinite\" enabled.")
            style.mutedText("An infinite workspot never releases the NPC, so it stops at that point\nand never walks the rest of the route.")

            ImGui.Separator()

            for _, entry in pairs(exportUI.exportIssues.patrolWorkspotInfinite) do
                style.mutedText("Patrol Spline:")
                ImGui.SameLine()
                ImGui.Text(entry.spline)

                style.mutedText("Patrol Point:")
                ImGui.SameLine()
                ImGui.Text(string.format("%d (Workspot)", entry.point))

                style.mutedText("AISpot:")
                ImGui.SameLine()
                ImGui.Text(entry.spot)

                style.mutedText("NodeRef:")
                ImGui.SameLine()
                ImGui.Text(entry.ref)

                ImGui.Separator()
            end

            drawIssueButtons("patrolWorkspotInfinite", {
                label = "Fix & continue",
                tooltip = "Disable \"Is Infinite\" on the AISpots listed above and continue the export.\nUndoable in one step.",
                action = fixInfinitePatrolWorkspots
            })
            ImGui.EndPopup()
        end
    end
end

function exportUI.draw()
    local runtime = groupExportManager.getState()
    local exporting = groupExportManager.isActive()

    exportUI.drawToasts()

    if not exporting or groupExportManager.isPaused() then
        exportUI.drawIssues()
    end

    if not sectorCategory then
        sectorCategory = utils.enumTable("worldStreamingSectorCategory")
    end

    do
        local headerX = ImGui.GetCursorPosX()
        local headerWidth = ImGui.GetContentRegionAvail()
        local qtyLabel = "Qty groups"
        local qtyLabelWidth = ImGui.CalcTextSize(qtyLabel)
        local qtyLabelX = headerX + headerWidth * 0.55 + math.max(0, (headerWidth * 0.20 - qtyLabelWidth) / 2)

        ImGui.PushStyleColor(ImGuiCol.Text, style.mutedColor)
        ImGui.Text("Export templates")
        style.tooltip("Templates let you save an export setup for later usage, without having to setup what groups/settings to use each time.")
        ImGui.SameLine()
        ImGui.SetCursorPosX(math.max(ImGui.GetCursorPosX(), qtyLabelX))
        ImGui.Text(qtyLabel)
        ImGui.PopStyleColor()
        ImGui.Separator()
        ImGui.Spacing()

        ImGui.BeginGroup()
        ImGui.AlignTextToFramePadding()
    end

    exportUI.drawTemplates()
    exportUI.handleTemplateDeletePopup()

    style.sectionHeaderEnd()

    -- Properties and Groups are the one thing being set up, so they sit together on a card rather
    -- than reading as two unrelated sections of the tab. Auto-height: the Groups list inside is
    -- resizable, so the card has to follow whatever the divider leaves it.
    style.beginCard("##exportSetupCard", { height = "auto" })

    style.sectionHeaderStart("Properties")

    if not exportUI.mainPropertiesWidth then
        exportUI.mainPropertiesWidth = utils.getTextMaxWidth({ "Project Name", "XL Format" }) + ImGui.GetStyle().ItemSpacing.x + ImGui.GetCursorPosX()
    end

    style.pushStyleColor(exportUI.projectName == "" and exportUI.exportHovered, ImGuiCol.Text, 0xFF0000FF)
    ImGui.Text("Project Name")
    style.popStyleColor(exportUI.projectName == "" and exportUI.exportHovered)
    ImGui.SameLine()
    ImGui.SetNextItemWidth(200 * style.viewSize)
    ImGui.SetCursorPosX(exportUI.mainPropertiesWidth)
    exportUI.projectName = style.inputTextWithHint('##name', 'Export name...', exportUI.projectName, 100)
    if exportUI.projectName ~= "" then
        ImGui.SameLine()
        style.pushButtonNoBG(true)
        if ImGui.Button(IconGlyphs.Close .. "##clearExportProjectName") then
            exportUI.projectName = ""
        end
        style.pushButtonNoBG(false)
    end

    ImGui.Text("XL Format")
    ImGui.SameLine()
    ImGui.SetNextItemWidth(150 * style.viewSize)
    ImGui.SetCursorPosX(exportUI.mainPropertiesWidth)
    exportUI.xlFormat, _ = ImGui.Combo("##xlFormat", exportUI.xlFormat, { "JSON", "YAML" }, 2)
    style.tooltip("Select the format in which the contents of the generated .xl file should be.")

    style.pushGreyedOut(#exportUI.groups == 0 or exporting)
    if ImGui.Button("Clear group list") and not exporting then
        exportUI.groups = {}
    end
    style.popGreyedOut(#exportUI.groups == 0 or exporting)
    style.tooltip("Remove all groups from the current export list")

    style.sectionHeaderEnd()
    style.sectionHeaderStart(string.format("Groups (%d)", #exportUI.groups))

    exportUI.drawGroups()

    style.sectionHeaderEnd(true)
    style.endCard()

    exportUI.drawGroupsDivider()

    ImGui.Spacing()
    ImGui.Spacing()

    style.sectionHeaderStart("Export and Save")

    local groupNameCounts = {}
    local duplicateGroupNames = {}
    for _, group in ipairs(exportUI.groups) do
        local name = group.name or ""
        groupNameCounts[name] = (groupNameCounts[name] or 0) + 1
    end
    for name, count in pairs(groupNameCounts) do
        if name ~= "" and count > 1 then
            table.insert(duplicateGroupNames, name)
        end
    end

    if #duplicateGroupNames > 0 then
        table.sort(duplicateGroupNames)
        local duplicateGroupWarningLabel = style.resolveActionLabelNoIconOnly(IconGlyphs.AlertOutline, "Duplicate group names detected", nil)
        style.styledText(duplicateGroupWarningLabel, 0xFF0088FF)
        style.tooltip("Duplicated group names:\n- " .. table.concat(duplicateGroupNames, "\n- "))
        ImGui.Spacing()
    end

    style.pushGreyedOut(#exportUI.groups == 0 or exportUI.projectName == "" or exporting)
    local fullExportLabel = "Full export"
    local updateChangedLabel = "Update existing export"
    if exporting then
        local modeLabel = runtime and runtime.mode == "incremental" and "Updating..." or "Exporting..."
        fullExportLabel = string.format("%s (%d/%d)", modeLabel, runtime.completedGroups or 0, runtime.totalGroups or 0)
        updateChangedLabel = fullExportLabel
    end

    if ImGui.Button(updateChangedLabel) and #exportUI.groups > 0 and exportUI.projectName ~= "" and not exporting then
        exportUI.export("incremental")
    end
    style.tooltip("Update the existing export file by rebuilding only changed groups.")
    exportUI.exportHovered = ImGui.IsItemHovered()

    ImGui.SameLine()
    if ImGui.Button(fullExportLabel) and #exportUI.groups > 0 and exportUI.projectName ~= "" and not exporting then
        exportUI.export("full")
    end
    style.tooltip("Export all selected groups from scratch, overriding the existing export file.")
    exportUI.exportHovered = exportUI.exportHovered or ImGui.IsItemHovered()

    ImGui.SameLine()
    if ImGui.Button("Save as Template") and #exportUI.groups > 0 and exportUI.projectName ~= "" and not exporting then
        local data = {
            projectName = exportUI.projectName,
            xlFormat = exportUI.xlFormat,
            groups = utils.deepcopy(exportUI.groups)
        }
        local saved, saveErr = config.saveFile("data/exportTemplates/" .. exportUI.projectName .. ".json", data)
        if saved then
            exportUI.templates[exportUI.projectName] = data
            pipelineCommon.queueToast(exportUI.templateSaveToasts, "success", 2500, string.format("Saved export template \"%s\"", exportUI.projectName))
        else
            pipelineCommon.queueToast(exportUI.templateSaveToasts, "error", 5000, string.format("Failed to save export template \"%s\": %s", exportUI.projectName, tostring(saveErr or "unknown_error")))
        end
    end
    style.tooltip("Save the current export setup as a template for later (re)usage")

    style.popGreyedOut(#exportUI.groups == 0 or exportUI.projectName == "" or exporting)

    exportUI.drawExportProgress()

    style.sectionHeaderEnd(true)
end

---Adds a saved project to the export list.
---@param name string Group name, used as the label and in the exported sector names.
---@param fileName string? The project's uID. Resolved from the name when omitted, for callers that
---only know the label (older templates, the settings UI).
function exportUI.addGroup(name, fileName)
    fileName = fileName or exportUI.resolveGroupFileName({ name = name })

    for _, data in pairs(exportUI.groups) do
        -- Matched on the uID: two projects may now be called the same thing, and adding one must not
        -- be mistaken for the other already being in the list.
        if exportUI.resolveGroupFileName(data) == fileName then return end
    end

    local data = {
        name = name,
        fileName = fileName,
        category = 1,
        level = 1,
        visualizeStreamingBox = false,
        streamingPresetIndex = 0,
        streamingX = 150,
        streamingY = 150,
        streamingZ = 100,
        streamingAuto = false,
        streamingCenter = nil,
        center = nil,
        prefabRef = "",
        variantRef = "",
        variantData = {}
    }

    -- First group added to an unnamed export: the group name is the best guess at what the export
    -- should be called, and saves having to type it again.
    if #exportUI.groups == 0 and exportUI.projectName == "" then
        exportUI.projectName = name
    end

    table.insert(exportUI.groups, data)
    local blob = loadSavedGroupBlob(data)
    if not blob then return end

    data.variantData = buildVariantDataFromBlob(blob, nil)
    data.center = resolveGroupCenter(blob, nil)
end

---Removes export list entries pointing at one project file.
---@param fileName string Project uID, i.e. its file name including extension.
---@return integer
function exportUI.removeGroupByFile(fileName)
    local removed = 0

    for i = #exportUI.groups, 1, -1 do
        if exportUI.resolveGroupFileName(exportUI.groups[i]) == fileName then
            table.remove(exportUI.groups, i)
            removed = removed + 1
        end
    end

    return removed
end

---Remove groups from export list by group name
---@param name string
---@return integer
function exportUI.removeGroupByName(name)
    local removed = 0

    for i = #exportUI.groups, 1, -1 do
        if exportUI.groups[i].name == name then
            table.remove(exportUI.groups, i)
            removed = removed + 1
        end
    end

    return removed
end

---Points export list entries at a renamed project file, so the list survives a rename in the
---Projects tab.
---@param oldFileName string
---@param newFileName string
---@return integer
function exportUI.retargetGroupFile(oldFileName, newFileName)
    local updated = 0

    for _, group in ipairs(exportUI.groups) do
        if exportUI.resolveGroupFileName(group) == oldFileName then
            group.fileName = newFileName
            updated = updated + 1
        end
    end

    return updated
end

---Relabels export list entries after the group inside a project was renamed.
---@param fileName string Project uID.
---@param newName string
---@return integer
function exportUI.renameGroupByFile(fileName, newName)
    local updated = 0

    for _, group in ipairs(exportUI.groups) do
        if exportUI.resolveGroupFileName(group) == fileName and group.name ~= newName then
            group.name = newName
            updated = updated + 1
        end
    end

    return updated
end

---Sync group data in export list from an already in-memory group blob
---Keeps export-specific settings (streaming/category/level/refs) while refreshing center + variants
---Only `pos`/`origin` and the top level of `childs` are read, so a shallow summary is enough
---@param fileName string Project uID. A plain group name still works for legacy entries.
---@param blob table? Serialized group data, or a summary carrying `pos`/`origin` and top-level `childs`
---@return integer
function exportUI.syncGroupFromData(fileName, blob)
    if not blob then return 0 end

    local updated = 0

    for _, group in ipairs(exportUI.groups) do
        if exportUI.resolveGroupFileName(group) == fileName or group.name == fileName then
            group.variantData = buildVariantDataFromBlob(blob, group.variantData)
            group.center = resolveGroupCenter(blob, group.center)
            if blob.streamingCenter then
                group.streamingCenter = blob.streamingCenter
            end
            updated = updated + 1
        end
    end

    return updated
end

---Sync group data in export list from saved group file
---Prefer `exportUI.syncGroupFromData` when the data is already in memory: this variant re-reads and
---decodes the file from disk, which is expensive for large groups.
---@param fileName string Project uID.
---@return integer
function exportUI.syncGroup(fileName)
    return exportUI.syncGroupFromData(fileName, loadSavedGroupBlob(fileName))
end

function exportUI.getSpawnableByNodeRef(nodeRefMap, nodeRef)
    if not nodeRef or nodeRef == "" then
        return nil
    end

    return nodeRefMap[nodeRef]
end

---Interaction records referenced by this export that the game does not have. Collected while
---walking the devices, written out as a TweakXL `.yaml` once the export finishes.
---@type { id: string, caption: string?, name: string? }[]
local pendingInteractionRecords = {}
local pendingInteractionSeen = {}

local function resetPendingInteractionRecords()
    pendingInteractionRecords = {}
    pendingInteractionSeen = {}
end

---@param interactionID string
---@param entry table Normalized sound system entry, used to borrow a caption
local function collectMissingInteractionRecord(interactionID, entry)
    if pendingInteractionSeen[interactionID] then
        return
    end

    pendingInteractionSeen[interactionID] = true
    table.insert(pendingInteractionRecords, {
        id = interactionID,
        caption = soundSystemData.getGeneratedCaptionFor(entry)
    })
end

---Writes the companion `.tweak` next to the exported sector, when anything needs one.
---@param projectName string
---@return string? path
function exportUI.writeInteractionTweak(projectName)
    local contents = soundSystemData.buildInteractionTweak(pendingInteractionRecords, projectName)
    if not contents then
        return nil
    end

    local path = "export/" .. tostring(projectName) .. "_interactions.yaml"
    local ok = pcall(function ()
        config.saveRaw(path, contents)
    end)

    if not ok then
        return nil
    end

    return path
end

---@param object table
---@param reason string
local function addSoundSystemIssue(object, reason)
    local ref = object and object.ref
    local spawnable = ref and ref.spawnable
    if not spawnable then
        return
    end

    local root = ref and ref.getRootParent and ref:getRootParent() or nil
    table.insert(exportUI.exportIssues.soundSystemSetup, {
        name = tostring(ref and ref.name or "Unknown"),
        group = tostring(root and root.name or "Unknown"),
        nodeRef = utils.sanitizeText(spawnable.nodeRef),
        reason = tostring(reason or "Sound system is not set up")
    })
end

---Checks a sound system for the ways it can ship silent. Every one of these exports without error
---and simply does nothing in game, which is why they are worth catching here.
---@param object table
---@param nodeRefMap table
local function validateSoundSystem(object, nodeRefMap)
    local spawnable = object and object.ref and object.ref.spawnable
    if not spawnable or spawnable.getSoundSystemEntries == nil then
        return
    end

    -- Speaker connections are plain project data, readable whether or not the node is spawned.
    local speakers = spawnable:getSpeakerEntries()

    if #speakers == 0 then
        addSoundSystemIssue(object, "No speakers connected, so nothing carries the sound")
    end

    for _, speakerEntry in ipairs(speakers) do
        if not exportUI.getSpawnableByNodeRef(nodeRefMap, speakerEntry.nodeRef) then
            addSoundSystemIssue(object, string.format(
                "Speaker connection '%s' matches no node being exported",
                speakerEntry.nodeRef ~= "" and speakerEntry.nodeRef or "(empty)"
            ))
        end
    end

    -- The entry list lives in persistent state, which is only readable once the component has been
    -- resolved. Without it there is nothing to judge, and guessing would report a working system as
    -- empty.
    local componentID = spawnable:getSoundSystemComponentID()
    if not componentID then
        return
    end

    local entries = spawnable:getSoundSystemEntries()

    if #entries == 0 then
        addSoundSystemIssue(object, "No entries: the device has no buttons and plays nothing")
    else
        local defaultAction = math.floor(tonumber(
            spawnable:getComponentPathValue(spawnable, componentID, soundSystemData.DEFAULT_ACTION_PATH)
        ) or 0)

        if defaultAction < 0 or defaultAction > #entries - 1 then
            addSoundSystemIssue(object, string.format(
                "Starting entry is %d but there are only %d entries (0-%d)",
                defaultAction, #entries, #entries - 1
            ))
        end

        for index, entry in ipairs(entries) do
            local interactionID = utils.sanitizeText(entry.interactionName["$value"])

            if interactionID == "" then
                addSoundSystemIssue(object, string.format("Entry %d has no interaction record, so its button has no caption", index))
            elseif not soundSystemData.interactionExists(interactionID) then
                collectMissingInteractionRecord(interactionID, entry)
                addSoundSystemIssue(object, string.format(
                    "Entry %d uses %s, which is not in TweakDB. World Builder will write it into %s_interactions.yaml",
                    index, interactionID, tostring(exportUI.projectName)
                ))
            end

            if soundSystemData.getEntrySource(entry) == "PlaySoundEvent" then
                local eventName = tostring(entry.musicSettings.Data.soundEvent and entry.musicSettings.Data.soundEvent["$value"] or "")
                if utils.sanitizeText(eventName) == "" or eventName == "None" then
                    addSoundSystemIssue(object, string.format("Entry %d plays a sound event but none is set", index))
                elseif soundSystemData.isMusicBusEvent(eventName) then
                    addSoundSystemIssue(object, string.format(
                        "Entry %d plays %s on the music bus, so it is heard everywhere rather than from the speakers",
                        index, eventName
                    ))
                end
            end
        end

        -- Entries only reach the game through the .psrep file, which is keyed on the NodeRef.
        if not spawnable.persistent then
            addSoundSystemIssue(object, "Persistent is off, so the entries above are not written and the system keeps its shipped behaviour")
        end
    end
end

---@param object table
---@param reason string
local function addMissingElevatorFloorSetupIssue(object, reason)
    local ref = object and object.ref
    local spawnable = ref and ref.spawnable
    if not spawnable then
        return
    end

    local root = ref and ref.getRootParent and ref:getRootParent() or nil
    table.insert(exportUI.exportIssues.missingElevatorFloorSetup, {
        name = tostring(ref and ref.name or "Unknown"),
        group = tostring(root and root.name or "Unknown"),
        nodeRef = utils.sanitizeText(spawnable.nodeRef),
        reason = tostring(reason or "Missing elevator floor setup")
    })
end

function exportUI.handleDevice(object, devices, psEntries, childs, nodeRefMap)
    local hash = utils.nodeRefStringToHashString(object.ref.spawnable.nodeRef)

    local childHashes = {}
    for _, child in pairs(object.ref.spawnable.deviceConnections) do
        table.insert(childHashes, utils.nodeRefStringToHashString(child.nodeRef))

        -- Remember what childs exist, so that we can also add those to the devices file which are entityNodes, not deviceNodes

        local childRef = exportUI.getSpawnableByNodeRef(nodeRefMap, child.nodeRef)
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

    -- Outside the persistent gate below on purpose: a sound system with Persistent off is exactly
    -- one of the cases worth reporting, and that gate would skip it.
    if utils.sanitizeText(object.ref.spawnable.deviceClassName) == SOUND_SYSTEM_CONTROLLER_CLASS then
        validateSoundSystem(object, nodeRefMap)
    end

    if object.ref.spawnable.persistent and object.ref.spawnable.nodeRef ~= "" then
        local psData = object.ref.spawnable:getPSData()
        local className = utils.sanitizeText(object.ref.spawnable.deviceClassName)
        local isElevatorFloorTerminal = className == ELEVATOR_FLOOR_TERMINAL_CONTROLLER_CLASS

        if isElevatorFloorTerminal then
            if type(psData) ~= "table" then
                addMissingElevatorFloorSetupIssue(object, "Persistent data is missing")
            elseif type(psData.elevatorFloorSetup) ~= "table" then
                addMissingElevatorFloorSetupIssue(object, "persistentState.Data.elevatorFloorSetup is missing")
            end
        end

        if psData then
            local PSID = PersistentID.ForComponent(entEntityID.new({ hash = loadstring("return " .. hash .. "ULL", "")() }), object.ref.spawnable.controllerComponent):ToHash()
            PSID = tostring(PSID):gsub("ULL", "")

            psEntries[PSID] = {
                PSID = PSID,
                instanceData = psData
            }
        end
    end
end

local function buildMarkingRefMap(spotNodes)
    local markingRefMap = {}

    for _, node in pairs(spotNodes) do
        for _, marking in pairs(node.markings or {}) do
            if not markingRefMap[marking] then
                markingRefMap[marking] = {}
            end
            table.insert(markingRefMap[marking], node.ref)
        end
    end

    return markingRefMap
end

---Build the `communitySpawnEntry.initializers` array.
---@param initializers table?
---@return table
local function exportEntryInitializers(initializers)
    local exported = {}
    local movementTypes = utils.enumTable("moveMovementType")
    local continuationPolicies = utils.enumTable("AIPatrolContinuationPolicy")
    local squadTypes = utils.enumTable("communityESquadType")

    for _, initializer in pairs(initializers or {}) do
        if initializer.type == "patrol" then
            table.insert(exported, {
                ["Data"] = {
                    ["$type"] = "communityPatrolInitializer",
                    ["patrolRole"] = {
                        ["Data"] = {
                            ["$type"] = "AIPatrolRole",
                            ["pathParams"] = {
                                ["Data"] = {
                                    ["$type"] = "AIPatrolPathParameters",
                                    ["path"] = {
                                        ["$type"] = "NodeRef",
                                        ["$storage"] = "string",
                                        ["$value"] = initializer.path or ""
                                    },
                                    ["movementType"] = movementTypes[(initializer.movementType or 0) + 1] or "Walk",
                                    ["continuationPolicy"] = continuationPolicies[(initializer.continuationPolicy or 0) + 1] or "FromNextControlPoint",
                                    ["startFromClosestPoint"] = initializer.startFromClosestPoint and 1 or 0,
                                    ["patrolWithWeapon"] = initializer.patrolWithWeapon and 1 or 0,
                                    ["isBackAndForth"] = initializer.isBackAndForth and 1 or 0,
                                    ["isInfinite"] = initializer.isInfinite and 1 or 0,
                                    ["numberOfLoops"] = math.max(1, math.floor(tonumber(initializer.numberOfLoops) or 1)),
                                    ["sortPatrolPoints"] = initializer.sortPatrolPoints and 1 or 0,
                                    ["patrolAction"] = {
                                        ["$type"] = "TweakDBID",
                                        ["$storage"] = "string",
                                        ["$value"] = initializer.patrolAction or "PatrolActions.DefaultPatrolAction"
                                    }
                                }
                            }
                        }
                    }
                }
            })
        elseif initializer.type == "squad" then
            -- `entries` is an array, but both shipped squad initializers hold exactly one entry
            -- and only one is authorable here.
            table.insert(exported, {
                ["Data"] = {
                    ["$type"] = "communitySquadInitializer",
                    ["entries"] = {
                        {
                            ["$type"] = "communitySquadInitializerEntry",
                            ["type"] = squadTypes[(initializer.squadType or 1) + 1] or "Community",
                            ["value"] = {
                                ["$type"] = "CName",
                                ["$storage"] = "string",
                                ["$value"] = initializer.squadName or ""
                            }
                        }
                    }
                }
            })
        else
            table.insert(exported, {
                ["Data"] = {
                    ["$type"] = "communityVoiceTagInitializer",
                    ["voiceTagName"] = {
                        ["$type"] = "CName",
                        ["$storage"] = "string",
                        ["$value"] = initializer.voiceTagName or ""
                    }
                }
            })
        end
    end

    return exported
end

local function hasEntryPhase(entry, phase)
    for _, entryPhase in pairs(entry.phases) do
        if entryPhase.phaseName == phase then
            return true
        end
    end

    return false
end

function exportUI.handleCommunities(projectName, communities, spotNodes, nodeRefs)
    local wsPersistentData = {}
    local registryEntries = {}
    local periodEnums = utils.enumTable("communityECommunitySpawnTime")
    local markingRefMap = buildMarkingRefMap(spotNodes)

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

            if not hasEntryPhase(entry, entry.initialPhaseName) then
                table.insert(exportUI.exportIssues.missingInitialPhase, {
                    name = community.node.name,
                    entry = entry.entryName,
                    phase = entry.initialPhaseName
                })
            end

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
                        local exportedPeriod = community.node.data.area.Data.entriesData[entryKey].phasesData[phaseKey].timePeriodsData[periodKey]
                        exportedPeriod.spotNodeIds = {}

                        for _, marking in pairs(period.markings) do
                            table.insert(markings, {
                                ["$type"] = "CName",
                                ["$storage"] = "string",
                                ["$value"] = marking
                            })

                            -- Update spotRefs on communityAreaNode, resolved from cached marking lookup.
                            local refs = markingRefMap[marking] or {}
                            for _, refValue in pairs(refs) do
                                table.insert(spotRefs, {
                                    ["$type"] = "NodeRef",
                                    ["$storage"] = "string",
                                    ["$value"] = refValue
                                })
                                table.insert(exportedPeriod.spotNodeIds, {
                                    ["$type"] = "worldGlobalNodeID",
                                    ["hash"] = utils.nodeRefStringToHashString(refValue)
                                })
                            end

                            if #refs == 0 then
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
                        ["alwaysSpawned"] = phase.alwaysSpawned and "true_" or "default__false_",
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
                    ["spawnInView"] = entry.spawnInView == false and "false_" or "default__true_",
                    ["initializers"] = exportEntryInitializers(entry.initializers),
                    ["phases"] = phases,
                }
            })
        end

        table.insert(registryEntries, {
            ["$type"] = "worldCommunityRegistryItem",
            -- Must agree with the area node class the spawnable exported, see community:getNodeType.
            ["communityAreaType"] = community.areaType or "Streamable",
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
                ["type"] = "worldCommunityRegistryNode",
                ["nodeRef"] = ""
            }
        }
    }
end

local isExportDisabled = streamingBox.isExportDisabled
local shouldExportNode = streamingBox.shouldExportNode

function exportUI.exportGroup(group)
    local data = loadSavedGroupBlob(group)
    if not data then return end

    local g = require("modules/classes/editor/positionableGroup"):new(exportUI.spawner.baseUI.spawnedUI)
    g:load(data, true)

    local center, extents = streamingBox.resolve(group, streamingBox.collectExported(g), g:getPosition())
    local min = { x = center.x - extents.x, y = center.y - extents.y, z = center.z - extents.z }
    local max = { x = center.x + extents.x, y = center.y + extents.y, z = center.z + extents.z }

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

    local variantNodes = {
        default = {}
    }
    local variantInfo = {}
    local nodes = {}
    local rootChildByName = {}

    for _, node in pairs(g.childs) do
        rootChildByName[node.name] = node
    end

    -- Group and bring the nodes in order, based on their variant, starting with default
    for groupName, variant in pairs(group.variantData) do
        local variantName = pipelineCommon.normalizeVariantName(variant.name)

        if not variantNodes[variantName] then
            variantNodes[variantName] = {}
            variantInfo[variantName] = {
                defaultOn = variant.defaultOn
            }
        end

        local node = rootChildByName[groupName]
        if node then
            for _, entry in pairs(node:getPathsRecursive(false)) do
                if utils.isA(entry.ref, "spawnableElement") and not entry.ref.spawnable.noExport and shouldExportNode(entry.ref) then
                    table.insert(variantNodes[variantName], entry)
                end
            end
        end
    end

    for _, node in pairs(g.childs) do
        if utils.isA(node, "spawnableElement") and not node.spawnable.noExport and shouldExportNode(node) then
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

    local nodeRefMap = {}
    for _, object in ipairs(nodes) do
        if utils.isA(object.ref, "spawnableElement") and object.ref.spawnable and object.ref.spawnable.nodeRef and object.ref.spawnable.nodeRef ~= "" then
            nodeRefMap[object.ref.spawnable.nodeRef] = object
        end
    end

    local nodeCount = #nodes
    for key, object in ipairs(nodes) do
        if utils.isA(object.ref, "spawnableElement") and not object.ref.spawnable.noExport and shouldExportNode(object.ref) then
            table.insert(exported.nodes, object.ref.spawnable:export(key, nodeCount))

            -- Handle device nodes
            if object.ref.spawnable.node == "worldDeviceNode" then
                exportUI.handleDevice(object, devices, psEntries, childs, nodeRefMap)
            elseif object.ref.spawnable.node == "worldCompiledCommunityAreaNode"
                or object.ref.spawnable.node == "worldCompiledCommunityAreaNode_Streamable" then
                table.insert(communities, {
                    data = object.ref.spawnable.entries,
                    node = exported.nodes[#exported.nodes],
                    areaType = object.ref.spawnable:getAreaType(),
                    hostedInAlwaysLoaded = object.ref.spawnable:isAlwaysLoadedHosted()
                })
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

local function collectMissingSplineNodeRefs(nodes)
    for _, node in ipairs(nodes or {}) do
        local nodeRef = node.nodeRef or ""

        if (node.type == "worldSplineNode" or node.type == "worldSpeedSplineNode" or node.type == "worldPatrolSplineNode") and nodeRef == "" then
            local name = tostring(node.name or "Unnamed Spline"):gsub("^%[[^%]]*%]%s*", "")
            table.insert(exportUI.exportIssues.splineEmptyRef, name)
        end
    end
end

local function collectDuplicateNodeRefs(nodeRefs, nodes)
    for _, node in ipairs(nodes or {}) do
        local nodeRef = node.nodeRef or ""
        if not nodeRefs[nodeRef] then
            nodeRefs[nodeRef] = node.name
        elseif nodeRef ~= "" then
            table.insert(exportUI.exportIssues.nodeRefDuplicated, {
                nodeRef = nodeRef,
                name1 = nodeRefs[nodeRef],
                name2 = node.name
            })
            break
        end
    end
end

---@param mode string?
function exportUI.export(mode)
    if groupExportManager.isActive() then
        return
    end

    local exportMode = mode == "incremental" and "incremental" or "full"
    exportUI.resetIssues()

    if not sectorCategory then
        sectorCategory = utils.enumTable("worldStreamingSectorCategory")
    end

    resetPendingInteractionRecords()

    groupExportManager.start({
        spawner = exportUI.spawner,
        projectName = exportUI.projectName,
        xlFormat = exportUI.xlFormat,
        version = minScriptVersion,
        groups = exportUI.groups,
        sectorCategory = sectorCategory,
        shouldExportNode = shouldExportNode,
        isExportDisabled = isExportDisabled,
        handleDevice = exportUI.handleDevice,
        handleCommunities = exportUI.handleCommunities,
        collectMissingSplineNodeRefs = collectMissingSplineNodeRefs,
        collectDuplicateNodeRefs = collectDuplicateNodeRefs,
        collectInfinitePatrolWorkspots = collectInfinitePatrolWorkspots,
        writeInteractionTweak = exportUI.writeInteractionTweak,
        hasBlockingIssues = exportUI.hasBlockingIssues,
        mode = exportMode
    })
end

return exportUI
