local config = require("modules/utils/config")
local utils = require("modules/utils/utils")
local style = require("modules/ui/style")
local settings = require("modules/utils/settings")
local amm = require("modules/utils/ammUtils")
local history = require("modules/utils/history")
local editor = require("modules/utils/editor/editor")

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
        ["Static Audio Emitter"] = require("modules/classes/spawn/visual/audio"),
        ["Water Patch"] = require("modules/classes/spawn/visual/waterPatch")
    },
    ["Meta"] = {
        ["Occluder"] = require("modules/classes/spawn/meta/occluder"),
        ["Reflection Probe"] = require("modules/classes/spawn/meta/reflectionProbe")
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
    openPopup = false
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

---Refresh the filtering and sorting
function spawnUI.refresh()
    spawnUI.updateFilter()

    if settings.spawnUIOnlyNames then
        table.sort(spawnUI.filteredList, function(a, b) return utils.getFileName(a.name) < utils.getFileName(b.name) end)
    else
        table.sort(spawnUI.filteredList, function(a, b) return a.name < b.name end)
    end
end

function spawnUI.drawSpawnPosition()
    ImGui.Text("Spawn position")
    ImGui.SameLine()
    ImGui.PushItemWidth(100 * style.viewSize)
    local pos, changed = ImGui.Combo("##spawnPos", settings.spawnPos - 1, { "At selected", "Screen center" }, 2)
    settings.spawnPos = pos + 1
    if changed then settings.save() end
    if settings.spawnPos == 1 then
        style.tooltip("Spawn the new object at the position of the selected object(s), if none are selected, it will spawn in front of the player")
    else
        style.tooltip("Spawn position is relative to the camera position and orientation.")
    end
end

function spawnUI.draw()
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

    ImGui.Text("Strip paths")
    ImGui.SameLine()
    if spawnUI.getActiveSpawnList().isPaths then
        settings.spawnUIOnlyNames, changed = ImGui.Checkbox("##strip", settings.spawnUIOnlyNames)
        if changed then
            spawnUI.refresh()
        end
        style.tooltip("Only show the name of the file, without the full path")
    end

    ImGui.SameLine()

    spawnUI.drawSpawnPosition()

    style.spacedSeparator()

    ImGui.PushItemWidth(120 * style.viewSize)
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

            if ImGui.Button(buttonText) then
                ImGui.SetClipboardText(entry.name)
                local class = spawnUI.getActiveSpawnList().class
                entry.lastSpawned = spawnUI.spawnNew(entry, class)
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
    local parent = spawnUI.spawnedUI.root
    if spawnUI.selectedGroup ~= 0 then
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
    spawnUI.spawnedUI.unselectAll()
    history.addAction(history.getInsert({ new }))

    return new
end

function spawnUI.drawPopup()
    local x, y = ImGui.GetMousePos()
    ImGui.SetNextWindowPos(x + 10 * style.viewSize, y + 10 * style.viewSize, ImGuiCond.Appearing)
    local screenWidth, screenHeight = GetDisplayResolution()

    -- TODO: Independent search, search reset option
    -- Window auto y, max y
    -- Window auto x, max x
    -- Spawn under cursor

    if ImGui.BeginPopupContextItem("##spawnNew") then
        spawnUI.drawSpawnPosition()
        ImGui.Separator()

        if ImGui.BeginMenu('Search all') then
            ImGui.EndMenu()
        end

        for typeName, typeData in pairs(types) do
            if ImGui.BeginMenu(typeName) then
                for variantName, _ in pairs(typeData) do
                    if ImGui.BeginMenu(variantName) then
                        spawnUI.popupFilter, _ = ImGui.InputTextWithHint('##Filter', 'Search...', spawnUI.popupFilter, 75)
                        local xSpace, _ = ImGui.GetItemRectSize()
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

                        if spawnUI.popupFilter ~= "" or #spawnData[typeName][variantName].data < 25 then
                            local x = 0
                            local data = {}
                            for _, entry in pairs(spawnData[typeName][variantName].data) do
                                if (entry.name:lower():match(spawnUI.popupFilter:lower())) ~= nil then
                                    table.insert(data, entry)
                                    x = math.max(x, ImGui.CalcTextSize(entry.name) + ImGui.GetStyle().WindowPadding.x)
                                end
                            end

                            local y = #data * ImGui.GetFrameHeightWithSpacing()

                            if ImGui.BeginChild("##list", math.max(math.min(x, xSpace), 1), math.max(math.min(y, screenHeight / 2), 1)) then
                                for _, entry in pairs(data) do
                                    ImGui.PushID(entry.name)

                                    if ImGui.Button(entry.name) then
                                        ImGui.SetClipboardText(entry.name)
                                        local class = spawnData[typeName][variantName].class
                                        spawnUI.spawnNew(entry, class)
                                        ImGui.CloseCurrentPopup()
                                    end

                                    ImGui.PopID()
                                end
                                ImGui.EndChild()
                            end
                        end

                        ImGui.EndMenu()
                    end
                end
                ImGui.EndMenu()
            end
        end

        ImGui.EndPopup()
    end

    if spawnUI.openPopup then
        spawnUI.openPopup = false
        spawnUI.popupFilter = ""

        ImGui.OpenPopup("##spawnNew")
    end
end

return spawnUI