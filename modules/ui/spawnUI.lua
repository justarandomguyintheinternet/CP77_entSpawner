local config = require("modules/utils/config")
local utils = require("modules/utils/utils")
local style = require("modules/ui/style")
local settings = require("modules/utils/settings")
local amm = require("modules/utils/ammUtils")
local history = require("modules/utils/history")
local editor = require("modules/utils/editor/editor")
local Cron = require("modules/utils/Cron")

local types = {
    ["Entity"] = {
        variants = {
            ["Template"] = { class = require("modules/classes/spawn/entity/entityTemplate"), index = 1},
            ["Template (AMM)"] = { class = require("modules/classes/spawn/entity/ammEntity"), index = 2},
            ["Record"] = { class = require("modules/classes/spawn/entity/entityRecord"), index = 3},
            ["Device"] = { class = require("modules/classes/spawn/entity/device"), index = 4}
        },
        index = 1
    },
    ["Lighting"] = {
        variants = {
            ["Static Light"] = { class = require("modules/classes/spawn/light/light"), index = 1 },
            ["Reflection Probe"] = { class = require("modules/classes/spawn/meta/reflectionProbe"), index = 2 },
            ["Light Channel Area"] = { class = require("modules/classes/spawn/light/lightChannelArea"), index = 3 },
            ["Fog Volume"] = { class = require("modules/classes/spawn/visual/fog"), index = 4 }
        },
        index = 3
    },
    ["Mesh"] = {
        variants = {
            ["Mesh"] = { class = require("modules/classes/spawn/mesh/mesh"), index = 1 },
            ["Rotating Mesh"] = { class = require("modules/classes/spawn/mesh/rotatingMesh"), index = 2 },
            ["Cloth Mesh"] = { class = require("modules/classes/spawn/mesh/clothMesh"), index = 3 },
            ["Dynamic Mesh"] = { class = require("modules/classes/spawn/physics/dynamicMesh"), index = 4 },
            ["Proxy Mesh"] = { class = require("modules/classes/spawn/mesh/proxyMesh"), index = 5 }
        },
        index = 2
    },
    ["Collision"] = {
        variants = {
            ["Collision Shape"] = { class = require("modules/classes/spawn/collision/collider"), index = 1 }
        },
        index = 5
    },
    ["Deco"] = {
        variants = {
            ["Particles"] = { class = require("modules/classes/spawn/visual/particle"), index = 2 },
            ["Decals"] = { class = require("modules/classes/spawn/visual/decal"), index = 1 },
            ["Effects"] = { class = require("modules/classes/spawn/visual/effect"), index = 3 },
            ["Static Audio Emitter"] = { class = require("modules/classes/spawn/visual/audio"), index = 4 },
            ["Water Patch"] = { class = require("modules/classes/spawn/visual/waterPatch"), index = 5 }
        },
        index = 4
    },
    ["Meta"] = {
        variants = {
            ["Occluder"] = { class = require("modules/classes/spawn/meta/occluder"), index = 1 },
            ["Static Marker"] = { class = require("modules/classes/spawn/meta/staticMarker"), index = 3 },
            ["Spline Point"] = { class = require("modules/classes/spawn/meta/splineMarker"), index = 4 },
            ["Spline"] = { class = require("modules/classes/spawn/meta/spline"), index = 5 }
        },
        index = 6
    },
    ["Area"] = {
        variants = {
            ["Outline Marker"] = { class = require("modules/classes/spawn/area/outlineMarker"), index = 1 },
            ["Kill Area"] = { class = require("modules/classes/spawn/area/killArea"), index = 4 },
            ["Prevention Free"] = { class = require("modules/classes/spawn/area/preventionFree"), index = 5 },
            ["Water Null"] = { class = require("modules/classes/spawn/area/waterNull"), index = 6 },
            ["Trigger Area"] = { class = require("modules/classes/spawn/area/triggerArea"), index = 2 },
            ["Ambient Area"] = { class = require("modules/classes/spawn/area/ambientArea"), index = 3 },
            ["Dummy Area"] = { class = require("modules/classes/spawn/area/dummyArea"), index = 9 },
            ["Conversation Area"] = { class = require("modules/classes/spawn/area/conversationArea"), index = 7 },
            ["Crowd Null Area"] = { class = require("modules/classes/spawn/area/crowdNull"), index = 8 }
        },
        index = 7
    },
    ["AI"] = {
        variants = {
            ["AI Spot"] = { class = require("modules/classes/spawn/ai/aiSpot"), index = 1 },
            ["Community"] = { class = require("modules/classes/spawn/ai/communityArea"), index = 2 }
        },
        index = 8
    }
}

local spawnData = {}
local typeNames = {}
local variantNames = {}
local modulePathToSpawnList = {}
local AMM = nil

local function tooltip(text)
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip(text)
    end
end

---@class spawnUI
---@field filter string
---@field selectedGroup number
---@field selectedType number
---@field selectedVariant number
---@field sizeX number
---@field spawnedUI? spawnedUI
---@field spawner? spawner
---@field filteredList table
---@field openPopup boolean
---@field popupFilter string
---@field currentPopupVariant string
---@field popupSpawnHit table?
---@field popupData table
---@field dragging boolean
---@field dragData table?
---@field lastSpawnedClass table?
---@field lastSpawnedEntry table?
---@field lastSpawnedIsFavorite boolean
---@field previewInstance spawnable?
---@field previewTimer number?
---@field hoveredEntry table?
---@field favoritesUI favoritesUI
spawnUI = {
    filter = "",
    popupFilter = "",
    selectedGroup = 0,
    selectedType = 0,
    selectedVariant = 0,
    sizeX = 0,
    spawnedUI = nil,
    spawner = nil,
    filteredList = {},
    openPopup = false,
    currentPopupVariant = "",
    popupData = {},
    popupSpawnHit = nil,
    dragging = false,
    dragData = nil,
    lastSpawnedClass = nil,
    lastSpawnedEntry = nil,
    lastSpawnedIsFavorite = false,
    previewInstance = nil,
    previewTimer = nil,
    hoveredEntry = nil,
    favoritesUI = require("modules/ui/favoritesUI")
}

---Loads the spawn data (Either list of e.g. paths, or exported object files) for each data variant
---@param spawner spawner
function spawnUI.loadSpawnData(spawner)
    typeNames = {}
    variantNames = {}
    spawnData = {}
    modulePathToSpawnList = {}

    AMM = GetMod("AppearanceMenuMod")
    spawnUI.spawnedUI = spawner.baseUI.spawnedUI
    spawnUI.spawner = spawner

    for dataName, dataType in pairs(types) do
        spawnData[dataName] = {}

        for variantName, variant in pairs(dataType.variants) do
            local variantInstance = variant.class:new()
            local info = { node = variantInstance.node, description = variantInstance.description, previewNote = variantInstance.previewNote }
            if variantInstance.spawnListType == "list" then
                spawnData[dataName][variantName] = { data = config.loadLists(variantInstance.spawnDataPath), class = variant.class, modulePath = variantInstance.modulePath, info = info, isPaths = true, assetPreviewDelay = variantInstance.assetPreviewDelay, assetPreviewType = variantInstance.assetPreviewType }
            else
                spawnData[dataName][variantName] = { data = config.loadFiles(variantInstance.spawnDataPath), class = variant.class, modulePath = variantInstance.modulePath, info = info, isPaths = false, assetPreviewDelay = variantInstance.assetPreviewDelay, assetPreviewType = variantInstance.assetPreviewType }
            end
            modulePathToSpawnList[variantInstance.modulePath] = spawnData[dataName][variantName]

            if settings.assetPreviewEnabled[variantInstance.modulePath] == nil then
                settings.assetPreviewEnabled[variantInstance.modulePath] = true
                settings.save()
            end
        end
    end

    typeNames = utils.getKeys(types)
    table.sort(typeNames, function(a, b) return types[a].index < types[b].index end)

    spawnUI.selectedType = math.max(utils.indexValue(typeNames, settings.selectedType) - 1, 0)

    variantNames = utils.getKeys(types[typeNames[spawnUI.selectedType + 1]].variants)
    table.sort(variantNames, function(a, b) return types[typeNames[spawnUI.selectedType + 1]].variants[a].index < types[typeNames[spawnUI.selectedType + 1]].variants[b].index end)

    spawnUI.selectedVariant = math.max(utils.indexValue(variantNames, settings.lastVariants[settings.selectedType]) - 1, 0)

    spawnUI.refresh()
end

---Returns a table containing the currently active spawnables list, each entry being structured as {data: String|table, name: String, lastSpawned: table}
---@return table
function spawnUI.getActiveSpawnList()
    return spawnData[typeNames[spawnUI.selectedType + 1]][variantNames[spawnUI.selectedVariant + 1]]
end

---Regenerate the filteredList based on the active filter and the currently selected active spawn list
function spawnUI.updateFilter()
    settings.spawnUIFilter = spawnUI.filter
    settings.save()

    if spawnUI.filter == "" then
        spawnUI.filteredList = spawnUI.getActiveSpawnList().data
        return
    end

    spawnUI.filteredList = {}
    for _, data in pairs(spawnUI.getActiveSpawnList().data) do
        local name = data.name
        if spawnUI.getActiveSpawnList().isPaths and settings.spawnUIOnlyNames then
            name = data.fileName
        end
        if utils.matchSearch(name, spawnUI.filter) then
            table.insert(spawnUI.filteredList, data)
        end
    end
end

---Refresh the filtering and sorting
function spawnUI.refresh()
    spawnUI.updateFilter()

    if settings.spawnUIOnlyNames and spawnUI.getActiveSpawnList().isPaths then
        table.sort(spawnUI.filteredList, function(a, b) return a.fileName < b.fileName end)
    else
        table.sort(spawnUI.filteredList, function(a, b) return a.name < b.name end)
    end
end

function spawnUI.getCategoryIndex(category)
    return types[category].index
end

function spawnUI.getVariantIndex(category, sub)
    return types[category].variants[sub].index
end

function spawnUI.updateCategory()
    settings.selectedType = typeNames[spawnUI.selectedType + 1]
    settings.save()

    variantNames = utils.getKeys(types[typeNames[spawnUI.selectedType + 1]].variants)
    table.sort(variantNames, function(a, b) return types[typeNames[spawnUI.selectedType + 1]].variants[a].index < types[typeNames[spawnUI.selectedType + 1]].variants[b].index end)

    spawnUI.selectedVariant = math.max(utils.indexValue(variantNames, settings.lastVariants[settings.selectedType]) - 1, 0)

    spawnUI.refresh()
end

function spawnUI.updateVariant()
    settings.lastVariants[settings.selectedType] = variantNames[spawnUI.selectedVariant + 1]
    settings.save()

    spawnUI.refresh()
end

---@param entry table|favorite
---@param isFavorite boolean
function spawnUI.handleAssetPreviewHovered(entry, isFavorite)
    if spawnUI.hoveredEntry ~= entry then
        if spawnUI.previewInstance then
            spawnUI.previewInstance:assetPreview(false)
        end

        spawnUI.hoveredEntry = entry

        if spawnUI.previewTimer then
            Cron.Halt(spawnUI.previewTimer)
        end

        local assetPreviewType = spawnUI.getActiveSpawnList().assetPreviewType
        local assetPreviewDelay = spawnUI.getActiveSpawnList().assetPreviewDelay
        if isFavorite then
            -- If its favorite, then entry is just the favorite instance
            if entry.data.modulePath ~= "modules/classes/editor/spawnableElement" then
                assetPreviewType = "none"
            else
                assetPreviewDelay = modulePathToSpawnList[entry.data.spawnable.modulePath].assetPreviewDelay
                assetPreviewType = modulePathToSpawnList[entry.data.spawnable.modulePath].assetPreviewType
            end
        end

        if assetPreviewType == "none" then return end

        spawnUI.previewTimer = Cron.After(assetPreviewDelay, function ()
            spawnUI.previewTimer = nil
            if not spawnUI.hoveredEntry then return end

            local data = utils.deepcopy(entry.data)
            if isFavorite then
                spawnUI.previewInstance = require("modules/classes/spawn/" .. data.spawnable.modulePath):new()
                data = data.spawnable
            else
                spawnUI.previewInstance = spawnUI.getActiveSpawnList().class:new()
                data.modulePath = spawnUI.previewInstance.modulePath
            end

            local pos, _ = spawnUI.getSpawnNewPosition()
            rot = GetPlayer():GetFPPCameraComponent():GetLocalToWorld():GetRotation()
            rot.yaw = rot.yaw - 180
            rot.pitch = -rot.pitch
            spawnUI.previewInstance:loadSpawnData(data, pos, rot)

            spawnUI.previewInstance:assetPreview(true)
        end)
    end
end

function spawnUI.updateAssetPreview()
    if spawnUI.previewInstance and spawnUI.previewInstance:isSpawned() then
        spawnUI.previewInstance:assetPreviewSetPosition()
    end
end

function spawnUI.drawSpawnPosition()
    ImGui.Text("Spawn position")
    ImGui.SameLine()
    local x = ImGui.GetCursorPosX()
    ImGui.PushItemWidth(100 * style.viewSize)
    local pos, changed = ImGui.Combo("##spawnPos", settings.spawnPos - 1, { "At selected", "Screen center" }, 2)
    settings.spawnPos = pos + 1
    if changed then settings.save() end
    if settings.spawnPos == 1 then
        style.tooltip("Spawn the new object at the position of the selected object(s), if none are selected, it will spawn in front of the player")
    else
        style.tooltip("Spawn position is relative to the camera position and orientation.")
    end

    ImGui.SameLine()

    style.mutedText(IconGlyphs.InformationOutline)
    style.tooltip("To spawn an object under the cursor, either:\n - Use the Shift-A menu while in editor mode\n - Drag and drop an object from the list to the desired position on the screen.")

    return x
end

function spawnUI.drawDragWindow()
    if not spawnUI.dragging then return end

    ImGui.SetMouseCursor(ImGuiMouseCursor.Hand)

    local x, y = ImGui.GetMousePos()
    ImGui.SetNextWindowPos(x + 10 * style.viewSize, y + 10 * style.viewSize, ImGuiCond.Always)
    if ImGui.Begin("##drag", ImGuiWindowFlags.NoResize + ImGuiWindowFlags.NoMove + ImGuiWindowFlags.NoTitleBar + ImGuiWindowFlags.NoBackground + ImGuiWindowFlags.AlwaysAutoResize) then
        ImGui.Text(spawnUI.dragData.name)
        ImGui.End()
    end
end

function spawnUI.drawNoMatch()
    if #spawnUI.filteredList ~= 0 or not spawnUI.getActiveSpawnList().isPaths then return end

    style.mutedText("No match found...")
    style.mutedText(("Spawn \"%s\" anyways?"):format(spawnUI.filter))

    if ImGui.Button("Spawn") then
        local class = spawnUI.getActiveSpawnList().class
        spawnUI.spawnNew({
            data = { spawnData = spawnUI.filter }, lastSpawned = nil, name = spawnUI.filter, fileName = spawnUI.filter
        }, class, false)
    end
end

function spawnUI.drawOptions()
    local activeList = spawnUI.getActiveSpawnList()
    if activeList.isPaths then
        ImGui.Text("Strip paths")
        ImGui.SameLine()
        settings.spawnUIOnlyNames, changed = ImGui.Checkbox("##strip", settings.spawnUIOnlyNames)
        if changed then
            spawnUI.refresh()
        end
        style.tooltip("Only show the name of the file, without the full path")
    end

    if activeList.assetPreviewType ~= "none" then
        ImGui.Text("Asset Preview")
        ImGui.SameLine()
        settings.assetPreviewEnabled[activeList.modulePath], changed = ImGui.Checkbox("##assetPreview", settings.assetPreviewEnabled[activeList.modulePath])
        if changed then
            settings.save()
        end
        style.tooltip("Preview the asset when hovered. Is Experimental.")
        if activeList.assetPreviewType == "backdrop" then
            ImGui.SameLine()
            style.mutedText(IconGlyphs.Checkerboard)
            style.tooltip("Asset gets previewed with a backdrop")
        else
            ImGui.SameLine()
            style.mutedText(IconGlyphs.AxisArrowInfo)
            style.tooltip("Asset gets previewed at the same position it would spawn in")
        end
    end

    spawnUI.drawSpawnPosition()
end

function spawnUI.drawTargetGroupSelector()
    local groups = { "Root" }
	for _, group in pairs(spawnUI.spawnedUI.containerPaths) do
		table.insert(groups, group.path)
	end

    if spawnUI.selectedGroup >= #groups then
        spawnUI.selectedGroup = 0
    end

	ImGui.PushItemWidth(150 * style.viewSize)
    ImGui.Text("Target group")
    ImGui.SameLine()
	spawnUI.selectedGroup = ImGui.Combo("##newSpawnGroup", spawnUI.selectedGroup, groups, #groups)
    tooltip("Automatically place any newly spawned object into the selected group.\nPress CTRL-N in \"Spawned UI\" to set this selector to the currently selected group.")
	ImGui.PopItemWidth()
end

function spawnUI.drawAll()
    ImGui.SetNextItemWidth(300 * style.viewSize)
    spawnUI.filter, changed = ImGui.InputTextWithHint('##Filter', 'Search by name... (Supports pattern matching)', spawnUI.filter, 100)
    if changed then
        spawnUI.updateFilter()
    end

    if spawnUI.filter ~= '' then
        ImGui.SameLine()

        style.pushButtonNoBG(true)
        if ImGui.Button(IconGlyphs.Close) then
            spawnUI.filter = ''
            spawnUI.updateFilter()
        end
        style.pushButtonNoBG(false)
    end

    ImGui.SameLine()
    ImGui.SetCursorPosX(ImGui.GetWindowWidth() - 20 * style.viewSize)
    style.mutedText(IconGlyphs.InformationOutline)
    style.tooltip("Supports custom search query syntax:\n- | (OR), includes any terms including the word after the |\n- ! (NOT), excludes any terms including the word after the !\n- & (AND), terms must include the word after the &\n- E.g. table|chair!poor&low to match any terms that include 'table' or 'chair', but not 'poor', and must include 'low'")

    spawnUI.drawTargetGroupSelector()

    if ImGui.TreeNodeEx("Options", ImGuiTreeNodeFlags.SpanFullWidth) then
        spawnUI.drawOptions()
        ImGui.TreePop()
    end

    style.spacedSeparator()

    ImGui.PushItemWidth(120 * style.viewSize)
	spawnUI.selectedType, changed = ImGui.Combo("Object type", spawnUI.selectedType, typeNames, #typeNames)
    if changed then
        spawnUI.updateCategory()
    end

    ImGui.SameLine()

	spawnUI.selectedVariant, changed = ImGui.Combo("Object variant", spawnUI.selectedVariant, variantNames, #variantNames)
    if changed then
        spawnUI.updateVariant()
    end
    style.spawnableInfo(spawnUI.getActiveSpawnList().info)

	ImGui.PopItemWidth()

    ImGui.SameLine()

    if variantNames[spawnUI.selectedVariant + 1] == "Template (AMM)" then
        ImGui.SameLine()

        style.pushGreyedOut(not AMM)
        if not amm.importing then
            if ImGui.Button("Generate AMM Props") and AMM then
                amm.generateProps(spawnUI, AMM, spawnUI.spawner)
            end
            style.tooltip("Generate files for spawning, from current list of AMM props")
        else
            ImGui.ProgressBar(amm.progress / amm.total, 200, 30, string.format("%.2f%%", (amm.progress / amm.total) * 100))
        end

        style.popGreyedOut(not AMM)
    end

    style.spacedSeparator()

    ImGui.BeginChild("list")

    spawnUI.sizeX = 800

    local clipper = ImGuiListClipper.new()
    clipper:Begin(#spawnUI.filteredList, -1)

    local xSpace, _ = ImGui.GetItemRectSize() - 2 * ImGui.GetStyle().WindowPadding.x - (ImGui.GetScrollMaxY() > 0 and ImGui.GetStyle().ScrollbarSize or 0)

    spawnUI.drawNoMatch()

    while (clipper:Step()) do
        for i = clipper.DisplayStart + 1, clipper.DisplayEnd, 1 do
            local entry = spawnUI.filteredList[i]
            local isSpawned = false

            ImGui.PushID(entry.name)

            if entry.lastSpawned ~= nil then
                ImGui.PushStyleColor(ImGuiCol.Button, 0xff009933)
                ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0xff009900)
                isSpawned = true
            end

            local x, _ = ImGui.GetItemRectSize()
            spawnUI.sizeX = math.max(x + 14, spawnUI.sizeX)

            if entry.lastSpawned ~= nil and entry.lastSpawned.parent == nil then entry.lastSpawned = nil end

            if entry.lastSpawned ~= nil then
                if ImGui.Button("Despawn") then
                    history.addAction(history.getRemove({ entry.lastSpawned }))
                    entry.lastSpawned:remove()
                    entry.lastSpawned = nil
                end
                ImGui.SameLine()

                local deleteX, _ = ImGui.GetItemRectSize()
                spawnUI.sizeX = math.max(x + deleteX + 14, spawnUI.sizeX)
            end

            local buttonText = entry.name
            if spawnUI.getActiveSpawnList().isPaths and settings.spawnUIOnlyNames then
                buttonText = utils.getFileName(entry.name)
            end

            if ImGui.Button(utils.shortenPath(buttonText, xSpace - ImGui.GetCursorPosX(), true)) and not ImGui.IsMouseDragging(0, style.draggingThreshold) then
                local class = spawnUI.getActiveSpawnList().class
                entry.lastSpawned = spawnUI.spawnNew(entry, class, false)
            elseif ImGui.IsMouseDragging(0, style.draggingThreshold) and not spawnUI.dragging and ImGui.IsItemHovered() then
                spawnUI.dragging = true
                spawnUI.dragData = entry
            elseif not ImGui.IsMouseDragging(0, style.draggingThreshold) and spawnUI.dragging then
                if not ImGui.IsItemHovered() then
                    local ray = editor.getScreenToWorldRay()
                    spawnUI.popupSpawnHit = editor.getRaySceneIntersection(ray, GetPlayer():GetFPPCameraComponent():GetLocalToWorld():GetTranslation(), true)

                    local class = spawnUI.getActiveSpawnList().class
                    spawnUI.dragData.lastSpawned = spawnUI.spawnNew(spawnUI.dragData, class, false)
                end

                spawnUI.dragging = false
                spawnUI.dragData = nil
                spawnUI.popupSpawnHit = nil
            end
            if ImGui.IsItemClicked(ImGuiMouseButton.Middle) then
                ImGui.SetClipboardText(entry.name)
            end
            if ImGui.IsItemHovered() and settings.assetPreviewEnabled[spawnUI.getActiveSpawnList().modulePath] then
                spawnUI.handleAssetPreviewHovered(entry, false)
            elseif spawnUI.hoveredEntry == entry and spawnUI.previewInstance then
                spawnUI.hoveredEntry = nil
                if spawnUI.previewTimer then
                    Cron.Halt(spawnUI.previewTimer)
                else
                    spawnUI.previewInstance:assetPreview(false)
                end
            end
            if settings.spawnUIOnlyNames then
                style.tooltip(entry.name)
            end

            if ImGui.BeginPopupContextItem("##spawnNewContext", ImGuiPopupFlags.MouseButtonRight) then
                if ImGui.MenuItem("Make Favorite") then
                    local new = require("modules/classes/editor/spawnableElement"):new(spawnUI.spawnedUI)
                    local data = utils.deepcopy(entry.data)
                    data.modulePath = spawnUI.getActiveSpawnList().class:new().modulePath
                    data.position = { x = 0, y = 0, z = 0, w = 0 }
                    data.rotation = { roll = 0, pitch = 0, yaw = 0 }

                    new:load({
                        name = utils.getFileName(entry.name),
                        modulePath = new.modulePath,
                        spawnable = data
                    })

                    spawnUI.favoritesUI.addNewItem(new:serialize(), new.name, new.icon)
                end

                ImGui.EndPopup()
            end

            if isSpawned then ImGui.PopStyleColor(2) end

            ImGui.PopID()
        end
    end

    if #spawnUI.filteredList == 0 then
        if spawnUI.previewTimer then
            Cron.Halt(spawnUI.previewTimer)
        elseif spawnUI.previewInstance then
            spawnUI.previewInstance:assetPreview(false)
        end
    end

    ImGui.EndChild()
end

function spawnUI.draw()
    spawnUI.drawDragWindow()
    spawnUI.updateAssetPreview()

    if ImGui.BeginTabBar("##spawnUITabbar", ImGuiTabItemFlags.NoTooltip) then
        if ImGui.BeginTabItem("All") then
            spawnUI.drawAll()
            ImGui.EndTabItem()
        end
        if ImGui.BeginTabItem("Favorites") then
            spawnUI.favoritesUI.draw()
            ImGui.EndTabItem()
        end
        ImGui.EndTabBar()
    end
end

function spawnUI.hidden()
    if not spawnUI.previewInstance then return end

    spawnUI.hoveredEntry = nil
    if spawnUI.previewTimer then
        Cron.Halt(spawnUI.previewTimer)
    else
        spawnUI.previewInstance:assetPreview(false)
    end
end

function spawnUI.getSpawnNewPosition()
    if not GetPlayer() then
        return Vector4.new(0, 0, 0, 0), EulerAngles.new(0, 0, 0)
    end

    local rot = EulerAngles.new(0, 0, GetPlayer():GetFPPCameraComponent():GetLocalToWorld():GetRotation().yaw + 180)
    local pos = GetPlayer():GetWorldPosition()
    local forward = GetPlayer():GetFPPCameraComponent():GetLocalToWorld():GetAxisY()

    if editor.active then
        pos = GetPlayer():GetFPPCameraComponent():GetLocalToWorld():GetTranslation()
        pos.z = pos.z + forward.z * settings.spawnDist
    end
    pos.x = pos.x + forward.x * settings.spawnDist
    pos.y = pos.y + forward.y * settings.spawnDist

    if settings.spawnPos == 1 then
        if #spawnUI.spawnedUI.selectedPaths == 1 and utils.isA(spawnUI.spawnedUI.selectedPaths[1].ref, "spawnableElement") then
            pos = spawnUI.spawnedUI.selectedPaths[1].ref:getPosition()
            rot = spawnUI.spawnedUI.selectedPaths[1].ref:getRotation()
        elseif #spawnUI.spawnedUI.selectedPaths > 1 then
            pos = spawnUI.spawnedUI.multiSelectGroup:getPosition()
            rot = spawnUI.spawnedUI.multiSelectGroup:getDirection("forward"):ToRotation()
        end
    end

    return pos, rot
end

function spawnUI.spawnNew(entry, class, isFavorite)
    spawnUI.lastSpawnedClass = class
    spawnUI.lastSpawnedEntry = entry
    spawnUI.lastSpawnedIsFavorite = isFavorite

    -- Cleanup preview
    if spawnUI.previewTimer then
        Cron.Halt(spawnUI.previewTimer)
    end
    if spawnUI.previewInstance then
        spawnUI.previewInstance:assetPreview(false)
    end

    local parent = spawnUI.spawnedUI.root
    if spawnUI.selectedGroup ~= 0 and spawnUI.spawnedUI.containerPaths[spawnUI.selectedGroup] then
        parent = spawnUI.spawnedUI.containerPaths[spawnUI.selectedGroup].ref
    end

    local new = require("modules/classes/editor/spawnableElement"):new(spawnUI.spawnedUI)
    local pos, rot = spawnUI.getSpawnNewPosition()

    local snap = spawnUI.popupSpawnHit and spawnUI.popupSpawnHit.hit
    if snap then
        pos = spawnUI.popupSpawnHit.result.position
        local target = spawnUI.popupSpawnHit.result.normal
        local current = Vector4.new(0, 0, 1, 0)
        local axis = current:Cross(target)
        local angle = Vector4.GetAngleBetween(current, target)

        if math.abs(angle) < 0.1 then
            rot = EulerAngles.new(0, 0, GetPlayer():GetFPPCameraComponent():GetLocalToWorld():GetRotation().yaw + 180)
        else
            rot = Quaternion.SetAxisAngle(axis:Normalize(), math.rad(angle)):ToEulerAngles()
        end
    end

    local data = utils.deepcopy(entry.data)
    if not isFavorite then
        data.modulePath = class:new().modulePath
        data.position = { x = pos.x, y = pos.y, z = pos.z, w = 0 }
        data.rotation = { roll = rot.roll, pitch = rot.pitch, yaw = rot.yaw }
    end

    if isFavorite then
        ---@type positionable
        new = require(entry.data.modulePath):new(spawnUI.spawnedUI)
        data.visible = false

        new:load(data, true) -- Load without spawning
        new:setPosition(pos)
        new:setRotation(rot)
        new:setSilent(false)
        new:setVisible(true, true) -- Now spawn, but dont record in history

        if new.modulePath == "modules/classes/editor/positionableGroup" or new.modulePath == "modules/classes/editor/randomizedGroup" then
            new.yaw = 0
        end
    else
        new:load({
            name = utils.getFileName(entry.name),
            modulePath = new.modulePath,
            spawnable = data
        })
    end

    if utils.isA(new, "spawnableElement") and new.spawnable.bBoxLoaded == nil and snap then -- Bbox is immediately available
        local adjustedPos = utils.addVector(spawnUI.popupSpawnHit.result.position, utils.multVector(spawnUI.popupSpawnHit.result.normal, math.abs(new.spawnable:getBBox().min.z)))
        Cron.After(0.1, function ()
            new:setPosition(adjustedPos)
        end)
    end

    new:setParent(parent)
    new.selected = true
    spawnUI.spawnedUI.unselectAll()

    if utils.isA(new, "spawnableElement") and snap and new.spawnable.bBoxLoaded ~= nil then
        local position = spawnUI.popupSpawnHit.result.position
        local normal = spawnUI.popupSpawnHit.result.normal

        Cron.Every(0.05, function (timer)
            if new.spawnable.bBoxLoaded and new.spawnable:getEntity() then
                Cron.After(0.1, function ()
                    local adjustedPos = utils.addVector(position, utils.multVector(normal, math.abs(new.spawnable:getBBox().min.z)))
                    new:setPosition(adjustedPos)
                    history.addAction(history.getInsert({ new }))
                end)

                timer:Halt()
            end
        end)
    else
        history.addAction(history.getInsert({ new }))
    end

    return new
end

function spawnUI.repeatLastSpawn()
    if not spawnUI.lastSpawnedClass or not spawnUI.lastSpawnedEntry then return end

    local ray = editor.getScreenToWorldRay()
    spawnUI.popupSpawnHit = editor.getRaySceneIntersection(ray, GetPlayer():GetFPPCameraComponent():GetLocalToWorld():GetTranslation(), true)

    spawnUI.spawnNew(spawnUI.lastSpawnedEntry, spawnUI.lastSpawnedClass, spawnUI.lastSpawnedIsFavorite)
    spawnUI.spawnedUI.cachePaths()
    spawnUI.popupSpawnHit = nil
end

function spawnUI.loadPopupData(typeName, variantName)
    local data = {}

    for _, entry in pairs(spawnData[typeName][variantName].data) do
        if utils.matchSearch(entry.name, spawnUI.popupFilter) then
            table.insert(data, entry)
        end
    end

    spawnUI.popupData = data
end

function spawnUI.drawPopupVariant(typeName, variantName)
    local _, screenHeight = GetDisplayResolution()

    if spawnUI.currentPopupVariant ~= variantName then
        ImGui.SetKeyboardFocusHere()
        spawnUI.loadPopupData(typeName, variantName)
        spawnUI.currentPopupVariant = variantName
    end
    spawnUI.popupFilter, changed = ImGui.InputTextWithHint('##Filter', 'Search...', spawnUI.popupFilter, 75)
    local xSpace, _ = ImGui.GetItemRectSize()
    if changed then
        spawnUI.loadPopupData(typeName, variantName)
    end

    if spawnUI.popupFilter ~= '' then
        ImGui.SameLine()

        style.pushButtonNoBG(true)
        if ImGui.Button(IconGlyphs.Close) then
            spawnUI.popupFilter = ''
            spawnUI.updateFilter()
        end
        style.pushButtonNoBG(false)
        local x, _ = ImGui.GetItemRectSize()
        xSpace = xSpace + x + ImGui.GetStyle().ItemSpacing.x
    end

    if spawnUI.popupFilter ~= "" or #spawnData[typeName][variantName].data < 100 then
        local y = #spawnUI.popupData * ImGui.GetFrameHeightWithSpacing()

        if ImGui.BeginChild("##list", xSpace, math.max(math.min(y, screenHeight / 2), 1)) then
            local clipper = ImGuiListClipper.new()
            clipper:Begin(#spawnUI.popupData, -1)

            while (clipper:Step()) do
                for i = clipper.DisplayStart + 1, clipper.DisplayEnd, 1 do
                    ImGui.PushID(spawnUI.popupData[i].name)

                    if ImGui.Button(utils.shortenPath(spawnUI.popupData[i].name, xSpace - ImGui.GetStyle().ItemSpacing.x * 3, true)) then
                        if not settings.spawnAtCursor then spawnUI.popupSpawnHit = nil end
                        local class = spawnData[typeName][variantName].class
                        spawnUI.popupData[i].lastSpawned = spawnUI.spawnNew(spawnUI.popupData[i], class, false)
                        ImGui.CloseCurrentPopup()
                    end
                    if ImGui.IsItemClicked(ImGuiMouseButton.Middle) then
                        ImGui.SetClipboardText(spawnUI.popupData[i].name)
                    end

                    ImGui.PopID()
                end
            end
            ImGui.EndChild()
        end
    end
end

function spawnUI.drawPopup()
    local x, y = ImGui.GetMousePos()
    ImGui.SetNextWindowPos(x + 10 * style.viewSize, y - 4 * ImGui.GetFrameHeight(), ImGuiCond.Appearing)

    if ImGui.BeginPopup("##spawnNew") then
        local x, _ = ImGui.CalcTextSize("Reset search") + ImGui.GetStyle().ItemSpacing.x

        if not settings.spawnAtCursor then
           x = spawnUI.drawSpawnPosition()
        end
        ImGui.Text("At cursor")
        ImGui.SameLine()
        ImGui.SetCursorPosX(x)
        settings.spawnAtCursor, changed = ImGui.Checkbox("##cursor", settings.spawnAtCursor)
        if changed then settings.save() end
        style.tooltip("Spawn the object under the cursor.")

        ImGui.Text("Strip paths")
        ImGui.SameLine()
        ImGui.SetCursorPosX(x)
        settings.spawnUIOnlyNames, changed = ImGui.Checkbox("##strip", settings.spawnUIOnlyNames)
        if changed then settings.save() end
        style.tooltip("Only show the name of the file, without the full path")

        ImGui.Text("Reset search")
        ImGui.SameLine()
        ImGui.SetCursorPosX(x)
        settings.resetSpawnPopupSearch, changed = ImGui.Checkbox("##reset", settings.resetSpawnPopupSearch)
        if changed then settings.save() end
        style.tooltip("Resets the search when spawning something or closing the popup")

        ImGui.Separator()

        for _, typeName in pairs(typeNames) do
            if ImGui.BeginMenu(typeName) then
                local variantKeys = utils.getKeys(types[typeName].variants)
                table.sort(variantKeys, function(a, b) return types[typeName].variants[a].index < types[typeName].variants[b].index end)

                for _, variantName in pairs(variantKeys) do
                    if ImGui.BeginMenu(variantName) then
                        spawnUI.drawPopupVariant(typeName, variantName)
                        ImGui.EndMenu()
                    end
                end
                ImGui.EndMenu()
            end
        end

        ImGui.EndPopup()
    else
        spawnUI.popupSpawnHit = nil
    end

    if spawnUI.openPopup then
        spawnUI.openPopup = false
        spawnUI.currentPopupVariant = ""
        if settings.resetSpawnPopupSearch then
            spawnUI.popupFilter = ""
        end

        local ray = editor.getScreenToWorldRay()
        spawnUI.popupSpawnHit = editor.getRaySceneIntersection(ray, GetPlayer():GetFPPCameraComponent():GetLocalToWorld():GetTranslation(), true)

        ImGui.OpenPopup("##spawnNew")
    end

    spawnUI.favoritesUI.drawEditFavoritePopup()
end

return spawnUI