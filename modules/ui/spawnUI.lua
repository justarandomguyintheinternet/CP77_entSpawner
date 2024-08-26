local config = require("modules/utils/config")
local utils = require("modules/utils/utils")
local style = require("modules/ui/style")
local settings = require("modules/utils/settings")
local amm = require("modules/utils/ammUtils")
local history = require("modules/utils/history")

local types = {
    ["Entity"] = {
        ["Record"] = require("modules/classes/spawn/entity/entityRecord"),
        ["Template"] = require("modules/classes/spawn/entity/entityTemplate"),
        ["Template (AMM)"] = require("modules/classes/spawn/entity/ammEntity")
    },
    ["Lights"] = {
        ["Light"] = require("modules/classes/spawn/light/light")
    },
    ["Mesh"] = {
        ["Mesh"] = require("modules/classes/spawn/mesh/mesh"),
        ["Rotating Mesh"] = require("modules/classes/spawn/mesh/rotatingMesh"),
        ["Cloth Mesh"] = require("modules/classes/spawn/mesh/clothMesh"),
        ["Dynamic Mesh"] = require("modules/classes/spawn/physics/dynamicMesh")
    },
    ["Collision"] = {
        ["Collision Shape"] = require("modules/classes/spawn/collision/collider")
    },
    ["Deco"] = {
        ["Particles"] = require("modules/classes/spawn/visual/particle"),
        ["Decals"] = require("modules/classes/spawn/visual/decal"),
        ["Effects"] = require("modules/classes/spawn/visual/effect"),
        ["Static Audio Emitter"] = require("modules/classes/spawn/visual/audio")
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
---@field spawner? spawner
---@field filteredList table
spawnUI = {
    filter = "",
    selectedGroup = 0,
    selectedType = 0,
    selectedVariant = 0,
    sizeX = 0,
    spawner = nil,
    filteredList = {}
}

---Loads the spawn data (Either list of e.g. paths, or exported object files) for each data variant
---@param spawner table
function spawnUI.loadSpawnData(spawner)
    typeNames = {}
    variantNames = {}
    spawnData = {}

    AMM = GetMod("AppearanceMenuMod")
    spawnUI.spawner = spawner

    for dataName, dataType in pairs(types) do
        spawnData[dataName] = {}
        for variantName, variant in pairs(dataType) do
            local variantInstance = variant:new()
            local info = { node = variantInstance.node, description = variantInstance.description, previewNote = variantInstance.previewNote }
            if variantInstance.spawnListType == "list" then
                spawnData[dataName][variantName] = { data = config.loadLists(variantInstance.spawnDataPath), class = variant, info = info, isPaths = true }
            else
                spawnData[dataName][variantName] = { data = config.loadFiles(variantInstance.spawnDataPath), class = variant, info = info, isPaths = false }
            end
        end
    end

    for name, _ in pairs(types) do
        table.insert(typeNames, name)
    end

    spawnUI.selectedType = utils.indexValue(typeNames, settings.selectedType) - 1

    for name, _ in pairs(types[typeNames[spawnUI.selectedType + 1]]) do
        table.insert(variantNames, name)
    end

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

---Refresh the sorting and the filtering
function spawnUI.refresh()
    spawnUI.updateFilter()
    spawnUI.sort()
end

function spawnUI.draw()
    -- TODO: Alias / Tag

    spawnUI.filter, changed = ImGui.InputTextWithHint('##Filter', 'Search by name...', spawnUI.filter, 100)
    if changed then
        spawnUI.updateFilter()
    end

    if spawnUI.filter ~= '' then
        ImGui.SameLine()
        if ImGui.Button('X') then
            spawnUI.filter = ''
            spawnUI.updateFilter()
        end
    end

    local groups = { "Root" }
	for _, group in pairs(spawnUI.spawner.baseUI.spawnedUI.containerPaths) do
		table.insert(groups, group.path)
	end

    if spawnUI.selectedGroup >= #groups then
        spawnUI.selectedGroup = 0
    end

	ImGui.PushItemWidth(200)
	spawnUI.selectedGroup = ImGui.Combo("Put new object into group", spawnUI.selectedGroup, groups, #groups)
    tooltip("Automatically place any newly spawned object into the selected group")
	ImGui.PopItemWidth()

    settings.spawnNewSortAlphabetical, changed = ImGui.Checkbox("Sort alphabetically", settings.spawnNewSortAlphabetical)
    if changed then
        settings.save()
    end

    if spawnUI.getActiveSpawnList().isPaths then
        ImGui.SameLine()
        settings.spawnUIOnlyNames, changed = ImGui.Checkbox("Strip paths", settings.spawnUIOnlyNames)
        if changed then
            spawnUI.refresh()
        end
        style.tooltip("Only show the name of the file, without the full path")
    end

    style.spacedSeparator()

    ImGui.PushItemWidth(200)
	spawnUI.selectedType, changed = ImGui.Combo("Object type", spawnUI.selectedType, typeNames, #typeNames)
    if changed then
        settings.selectedType = typeNames[spawnUI.selectedType + 1]
        settings.save()

        variantNames = {}
        for name, _ in pairs(types[typeNames[spawnUI.selectedType + 1]]) do
            table.insert(variantNames, name)
        end

        spawnUI.selectedVariant = utils.indexValue(variantNames, settings.lastVariants[settings.selectedType]) - 1

        spawnUI.refresh()
    end

    ImGui.SameLine()

	spawnUI.selectedVariant, changed = ImGui.Combo("Object variant", spawnUI.selectedVariant, variantNames, #variantNames)
    if changed then
        settings.lastVariants[settings.selectedType] = variantNames[spawnUI.selectedVariant + 1]
        settings.save()

        spawnUI.refresh()
    end
    style.spawnableInfo(spawnUI.getActiveSpawnList().info)

	ImGui.PopItemWidth()

    ImGui.SameLine()

    if variantNames[spawnUI.selectedVariant + 1] == "Template (AMM)" then
        ImGui.SameLine()

        style.pushGreyedOut(not AMM)
        if not amm.importing then
            if ImGui.Button("Generate AMM Props") and AMM then
                amm.generateProps(spawnUI, AMM)
            end
            style.tooltip("[THIS WILL LAG] Generate files for spawning, from current list of AMM props")
        else
            ImGui.ProgressBar(amm.progress / amm.total, 200, 30, string.format("%.2f%%", (amm.progress / amm.total) * 100))
        end

        style.popGreyedOut(not AMM)
    end

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()

    local _, wHeight = GetDisplayResolution()

    ImGui.BeginChild("list")

    spawnUI.sizeX = 800

    local clipper = ImGuiListClipper.new()
    clipper:Begin(#spawnUI.filteredList, -1)

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

            local buttonText = entry.name
            if spawnUI.getActiveSpawnList().isPaths and settings.spawnUIOnlyNames then
                buttonText = utils.getFileName(entry.name)
            end

            if ImGui.Button(buttonText) then
                ImGui.SetClipboardText(entry.name)
                local class = spawnUI.getActiveSpawnList().class
                entry.lastSpawned = spawnUI.spawnNew(entry, class)
            end

            local x, _ = ImGui.GetItemRectSize()
            spawnUI.sizeX = math.max(x + 14, spawnUI.sizeX)

            if entry.lastSpawned ~= nil and entry.lastSpawned.parent == nil then entry.lastSpawned = nil end

            if entry.lastSpawned ~= nil then
                ImGui.SameLine()
                if ImGui.Button("Despawn") then
                    history.addAction(history.getRemove({ entry.lastSpawned }))
                    entry.lastSpawned:remove()
                    entry.lastSpawned = nil
                end

                local deleteX, _ = ImGui.GetItemRectSize()
                spawnUI.sizeX = math.max(x + deleteX + 14, spawnUI.sizeX)
            end

            if isSpawned then ImGui.PopStyleColor(2) end

            ImGui.PopID()
        end
    end

    ImGui.EndChild()
end

function spawnUI.spawnNew(entry, class)
    local parent = spawnUI.spawner.baseUI.spawnedUI.root
    if spawnUI.selectedGroup ~= 0 then
        parent = spawnUI.spawner.baseUI.spawnedUI.containerPaths[spawnUI.selectedGroup].ref
    end

    local new = require("modules/classes/editor/spawnableElement"):new(spawnUI.spawner.baseUI.spawnedUI)
    local rot = GetPlayer():GetWorldOrientation():ToEulerAngles()
    local pos = GetPlayer():GetWorldPosition()

    if settings.spawnPos == 2 then
        local forward = GetPlayer():GetWorldForward()
        pos.x = pos.x + forward.x * settings.spawnDist
        pos.y = pos.y + forward.y * settings.spawnDist
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

    new:setParent(parent)
    new.selected = true
    spawnUI.spawner.baseUI.spawnedUI.unselectAll()
    history.addAction(history.getInsert({ new }))

    return new
end

function spawnUI.sort()
    if settings.spawnNewSortAlphabetical then
        table.sort(spawnUI.getActiveSpawnList().data, function(a, b)
            if spawnUI.getActiveSpawnList().isPaths and settings.spawnUIOnlyNames then
                return utils.getFileName(a.name) < utils.getFileName(b.name)
            else
                return a.name < b.name
            end
        end)
    end
end

return spawnUI