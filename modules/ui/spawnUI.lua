local config = require("modules/utils/config")
local utils = require("modules/utils/utils")
local style = require("modules/ui/style")
local object = require("modules/classes/spawn/object")

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
        ["Rotating Mesh"] = require("modules/classes/spawn/mesh/rotatingMesh")
    }
    ,
    ["Collision"] = {
        ["Collision Shape"] = require("modules/classes/spawn/collision/collider")
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
            if variantInstance.spawnListType == "list" then
                spawnData[dataName][variantName] = { data = config.loadLists(variantInstance.spawnDataPath), class = variant }
            else
                spawnData[dataName][variantName] = { data = config.loadFiles(variantInstance.spawnDataPath), class = variant }
            end
        end
    end

    for name, _ in pairs(types) do
        table.insert(typeNames, name)
    end

    for name, _ in pairs(types[typeNames[spawnUI.selectedType + 1]]) do
        table.insert(variantNames, name)
    end

    spawnUI.refresh()
end

---Returns a table containing the currently active spawnables list, each entry being structured as {data: String|table, name: String, lastSpawned: table}
---@return table
function spawnUI.getActiveSpawnList()
    return spawnData[typeNames[spawnUI.selectedType + 1]][variantNames[spawnUI.selectedVariant + 1]]
end

---Regenerate the filteredList based on the active filter and the currently selected active spawn list
function spawnUI.updateFilter()
    if spawnUI.filter == "" then
        spawnUI.filteredList = spawnUI.getActiveSpawnList().data
        return
    end

    spawnUI.filteredList = {}
    for _, data in pairs(spawnUI.getActiveSpawnList().data) do
        if (data.name:lower():match(spawnUI.filter:lower())) ~= nil then
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

    local groups = {}
	for _, group in pairs(spawnUI.spawner.baseUI.spawnedUI.groups) do
		table.insert(groups, group.name)
	end

    if spawnUI.selectedGroup >= #groups then
        spawnUI.selectedGroup = 0
    end

	ImGui.PushItemWidth(200)
	spawnUI.selectedGroup = ImGui.Combo("Put new object into group", spawnUI.selectedGroup, groups, #groups)
    tooltip("Automatically place any newly spawned object into the selected group")
	ImGui.PopItemWidth()

    spawnUI.spawner.settings.spawnNewSortAlphabetical, changed = ImGui.Checkbox("Sort alphabetically", spawnUI.spawner.settings.spawnNewSortAlphabetical)
    if changed then
        config.saveFile("data/config.json", spawnUI.spawner.settings)
    end

    style.spacedSeparator()

    ImGui.PushItemWidth(200)
	spawnUI.selectedType, changed = ImGui.Combo("Object type", spawnUI.selectedType, typeNames, #typeNames)
    if changed then
        spawnUI.selectedVariant = 0

        variantNames = {}
        for name, _ in pairs(types[typeNames[spawnUI.selectedType + 1]]) do
            table.insert(variantNames, name)
        end

        spawnUI.refresh()
    end

    ImGui.SameLine()

	spawnUI.selectedVariant, changed = ImGui.Combo("Object variant", spawnUI.selectedVariant, variantNames, #variantNames)
    if changed then
        spawnUI.refresh()
    end
	ImGui.PopItemWidth()

    if variantNames[spawnUI.selectedVariant + 1] == "Template (AMM)" then
        ImGui.SameLine()

        style.pushGreyedOut(not AMM)
        if ImGui.Button("Generate AMM Props") and AMM then
            local props = AMM.API.GetAMMProps()
            for _, prop in pairs(props) do
                local new = object:new(spawnUI)
                new.spawnable = require("modules/classes/spawn/entity/ammEntity"):new()
                new.spawnable:loadSpawnData({ spawnData = prop.path }, Vector4.new(0, 0, 0, 0), EulerAngles.new(0, 0, 0), spawnedUI.spawner)
                new.name = new.spawnable:generateName(prop.name)

                config.saveFile("data/spawnables/entity/amm/" .. prop.name .. ".json", new:getState())
            end

            spawnUI.loadSpawnData(spawnUI.spawner)
        end
        style.tooltip("[THIS WILL LAG] Generate files for spawning, from current list of AMM props")

        style.popGreyedOut(not AMM)
    end

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()

    local _, wHeight = GetDisplayResolution()

    ImGui.BeginChild("list", spawnUI.sizeX, wHeight - wHeight * 0.2)

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

            if ImGui.Button(entry.name) then
                local parent = nil
                if spawnUI.selectedGroup ~= 0 then
                    parent = spawnUI.spawner.baseUI.spawnedUI.groups[spawnUI.selectedGroup + 1].tab
                end

                ImGui.SetClipboardText(entry.name)
                local class = spawnUI.getActiveSpawnList().class
                entry.lastSpawned = spawnUI.spawner.baseUI.spawnedUI.spawnNewObject(entry, class, parent)
            end

            local x, _ = ImGui.GetItemRectSize()
            spawnUI.sizeX = math.max(x + 14, spawnUI.sizeX)

            if entry.lastSpawned ~= nil then
                ImGui.SameLine()
                if ImGui.Button("Despawn") then
                    entry.lastSpawned:despawn()
                    if entry.lastSpawned.parent ~= nil then
                        utils.removeItem(entry.lastSpawned.parent.childs, entry.lastSpawned)
                        entry.lastSpawned.parent:saveAfterMove()
                    end
                    utils.removeItem(spawnUI.spawner.baseUI.spawnedUI.elements, entry.lastSpawned)
                    entry.lastSpawned = nil
                end

                local deleteX, _ = ImGui.GetItemRectSize()
                spawnUI.sizeX = math.max(x + deleteX + 14, spawnUI.sizeX)

                if not utils.has_value(spawnUI.spawner.baseUI.spawnedUI.elements, entry.lastSpawned) and entry.lastSpawned ~= nil then
                    entry.lastSpawned = nil
                end
            end

            if isSpawned then ImGui.PopStyleColor(2) end

            ImGui.PopID()
        end
    end

    ImGui.EndChild()
end

function spawnUI.sort()
    if spawnUI.spawner.settings.spawnNewSortAlphabetical then
        table.sort(spawnUI.getActiveSpawnList().data, function(a, b) return a.name:lower() < b.name:lower() end)
    end
end

return spawnUI