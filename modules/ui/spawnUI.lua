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
    ["Lights"] = {
        variants = {
            ["Light"] = { class = require("modules/classes/spawn/light/light"), index = 1 }
        },
        index = 3
    },
    ["Mesh"] = {
        variants = {
            ["Mesh"] = { class = require("modules/classes/spawn/mesh/mesh"), index = 1 },
            ["Rotating Mesh"] = { class = require("modules/classes/spawn/mesh/rotatingMesh"), index = 2 },
            ["Cloth Mesh"] = { class = require("modules/classes/spawn/mesh/clothMesh"), index = 3 },
            ["Dynamic Mesh"] = { class = require("modules/classes/spawn/physics/dynamicMesh"), index = 4 }
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
            ["Water Patch"] = { class = require("modules/classes/spawn/visual/waterPatch"), index = 5 },
            ["Fog Volume"] = { class = require("modules/classes/spawn/visual/fog"), index = 6 }
        },
        index = 4
    },
    ["Meta"] = {
        variants = {
            ["Occluder"] = { class = require("modules/classes/spawn/meta/occluder"), index = 1 },
            ["Reflection Probe"] = { class = require("modules/classes/spawn/meta/reflectionProbe"), index = 2 },
            ["Static Marker"] = { class = require("modules/classes/spawn/meta/staticMarker"), index = 3 }
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
            ["Ambient Area"] = { class = require("modules/classes/spawn/area/ambientArea"), index = 3 }
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
---@field spawnNewBBoxCron? number
---@field dragging boolean
---@field dragData table?
---@field lastSpawnedClass table?
---@field lastSpawnedEntry table?
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
    spawnNewBBoxCron = nil,
    dragging = false,
    dragData = nil,
    lastSpawnedClass = nil,
    lastSpawnedEntry = nil
}

---Loads the spawn data (Either list of e.g. paths, or exported object files) for each data variant
---@param spawner spawner
function spawnUI.loadSpawnData(spawner)
    typeNames = {}
    variantNames = {}
    spawnData = {}

    AMM = GetMod("AppearanceMenuMod")
    spawnUI.spawnedUI = spawner.baseUI.spawnedUI
    spawnUI.spawner = spawner

    for dataName, dataType in pairs(types) do
        spawnData[dataName] = {}

        for variantName, variant in pairs(dataType.variants) do
            local variantInstance = variant.class:new()
            local info = { node = variantInstance.node, description = variantInstance.description, previewNote = variantInstance.previewNote }
            if variantInstance.spawnListType == "list" then
                spawnData[dataName][variantName] = { data = config.loadLists(variantInstance.spawnDataPath), class = variant.class, info = info, isPaths = true }
            else
                spawnData[dataName][variantName] = { data = config.loadFiles(variantInstance.spawnDataPath), class = variant.class, info = info, isPaths = false }
            end
        end
    end

    typeNames = utils.getKeys(types)
    table.sort(typeNames, function(a, b) return types[a].index < types[b].index end)

    spawnUI.selectedType = utils.indexValue(typeNames, settings.selectedType) - 1

    variantNames = utils.getKeys(types[typeNames[spawnUI.selectedType + 1]].variants)
    table.sort(variantNames, function(a, b) return types[typeNames[spawnUI.selectedType + 1]].variants[a].index < types[typeNames[spawnUI.selectedType + 1]].variants[b].index end)

    spawnUI.selectedVariant = utils.indexValue(variantNames, settings.lastVariants[settings.selectedType]) - 1

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
            name = utils.getFileName(data.name)
        end
        if (name:lower():match(spawnUI.filter:lower())) ~= nil then
            table.insert(spawnUI.filteredList, data)
        end
    end
end

---Refresh the filtering and sorting
function spawnUI.refresh()
    spawnUI.updateFilter()

    if settings.spawnUIOnlyNames then
        table.sort(spawnUI.filteredList, function(a, b) return utils.getFileName(a.name) < utils.getFileName(b.name) end)
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

    spawnUI.selectedVariant = utils.indexValue(variantNames, settings.lastVariants[settings.selectedType]) - 1

    spawnUI.refresh()
end

function spawnUI.updateVariant()
    settings.lastVariants[settings.selectedType] = variantNames[spawnUI.selectedVariant + 1]
    settings.save()

    spawnUI.refresh()
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

function spawnUI.draw()
    spawnUI.drawDragWindow()

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

    local groups = { "Root" }
	for _, group in pairs(spawnUI.spawnedUI.containerPaths) do
		table.insert(groups, group.path)
	end

    if spawnUI.selectedGroup >= #groups then
        spawnUI.selectedGroup = 0
    end

	ImGui.PushItemWidth(150 * style.viewSize)
	spawnUI.selectedGroup = ImGui.Combo("Put new object into group", spawnUI.selectedGroup, groups, #groups)
    tooltip("Automatically place any newly spawned object into the selected group")
	ImGui.PopItemWidth()

    if spawnUI.getActiveSpawnList().isPaths then
        ImGui.Text("Strip paths")
        ImGui.SameLine()
        settings.spawnUIOnlyNames, changed = ImGui.Checkbox("##strip", settings.spawnUIOnlyNames)
        if changed then
            spawnUI.refresh()
        end
        style.tooltip("Only show the name of the file, without the full path")
    end

    spawnUI.drawSpawnPosition()

    ImGui.SameLine()

    style.mutedText(IconGlyphs.InformationOutline)
    style.tooltip("To spawn an object under the cursor, either:\n - Use the Shift-A menu while in editor mode\n - Drag and drop an object from the list to the desired position on the screen.")

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

            if ImGui.Button(utils.shortenPath(buttonText, xSpace - ImGui.GetCursorPosX(), true)) and not ImGui.IsMouseDragging(0, 0.6) then
                local class = spawnUI.getActiveSpawnList().class
                entry.lastSpawned = spawnUI.spawnNew(entry, class)
            elseif ImGui.IsMouseDragging(0, 0.6) and not spawnUI.dragging and ImGui.IsItemHovered() then
                spawnUI.dragging = true
                spawnUI.dragData = entry
            elseif not ImGui.IsMouseDragging(0, 0.6) and spawnUI.dragging then
                if not ImGui.IsItemHovered() then
                    local ray = editor.getScreenToWorldRay()
                    spawnUI.popupSpawnHit = editor.getRaySceneIntersection(ray, GetPlayer():GetFPPCameraComponent():GetLocalToWorld():GetTranslation(), true)

                    local class = spawnUI.getActiveSpawnList().class
                    spawnUI.lastSpawned = spawnUI.spawnNew(spawnUI.dragData, class)
                end

                spawnUI.dragging = false
                spawnUI.dragData = nil
                spawnUI.popupSpawnHit = nil
            end
            if settings.spawnUIOnlyNames then
                style.tooltip(entry.name)
            end

            if isSpawned then ImGui.PopStyleColor(2) end

            ImGui.PopID()
        end
    end

    ImGui.EndChild()
end

function spawnUI.spawnNew(entry, class)
    spawnUI.lastSpawnedClass = class
    spawnUI.lastSpawnedEntry = entry

    local parent = spawnUI.spawnedUI.root
    if spawnUI.selectedGroup ~= 0 and spawnUI.spawnedUI.containerPaths[spawnUI.selectedGroup] then
        parent = spawnUI.spawnedUI.containerPaths[spawnUI.selectedGroup].ref
    end

    local new = require("modules/classes/editor/spawnableElement"):new(spawnUI.spawnedUI)
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
        if #spawnUI.spawnedUI.selectedPaths == 1 and utils.isA(spawnUI.spawnedUI.selectedPaths[1].ref, "positionable") then
            pos = spawnUI.spawnedUI.selectedPaths[1].ref:getPosition()
            rot = spawnUI.spawnedUI.selectedPaths[1].ref:getRotation()
        elseif #spawnUI.spawnedUI.selectedPaths > 1 then
            pos = spawnUI.spawnedUI.multiSelectGroup:getPosition()
            rot = spawnUI.spawnedUI.multiSelectGroup:getDirection("forward"):ToRotation()
        end
    end

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
    data.modulePath = class:new().modulePath
    data.position = { x = pos.x, y = pos.y, z = pos.z, w = 0 }
    data.rotation = { roll = rot.roll, pitch = rot.pitch, yaw = rot.yaw }

    new:load({
        name = utils.getFileName(entry.name),
        modulePath = new.modulePath,
        spawnable = data
    })

    if new.spawnable.bBoxLoaded == nil and snap then -- Bbox is immediately available
        local adjustedPos = utils.addVector(spawnUI.popupSpawnHit.result.position, utils.multVector(spawnUI.popupSpawnHit.result.normal, math.abs(new.spawnable:getBBox().min.z)))
        Cron.After(0.1, function ()
            new:setPosition(adjustedPos)
        end)
    end

    new:setParent(parent)
    new.selected = true
    spawnUI.spawnedUI.unselectAll()

    if snap and new.spawnable.bBoxLoaded ~= nil then
        local position = spawnUI.popupSpawnHit.result.position
        local normal = spawnUI.popupSpawnHit.result.normal

        spawnUI.spawnNewBBoxCron = Cron.Every(0.05, function ()
            if new.spawnable.bBoxLoaded and new.spawnable:getEntity() then
                Cron.After(0.1, function ()
                    local adjustedPos = utils.addVector(position, utils.multVector(normal, math.abs(new.spawnable:getBBox().min.z)))
                    new:setPosition(adjustedPos)
                    history.addAction(history.getInsert({ new }))
                end)

                Cron.Halt(spawnUI.spawnNewBBoxCron)
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

    spawnUI.lastSpawned = spawnUI.spawnNew(spawnUI.lastSpawnedEntry, spawnUI.lastSpawnedClass)
    spawnUI.spawnedUI.cachePaths()
    spawnUI.popupSpawnHit = nil
end

function spawnUI.loadPopupData(typeName, variantName)
    local data = {}

    for _, entry in pairs(spawnData[typeName][variantName].data) do
        if (entry.name:lower():match(spawnUI.popupFilter:lower())) ~= nil then
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
                        spawnUI.lastSpawned = spawnUI.spawnNew(spawnUI.popupData[i], class)
                        ImGui.CloseCurrentPopup()
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

    if ImGui.BeginPopupContextItem("##spawnNew") then
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
end

return spawnUI