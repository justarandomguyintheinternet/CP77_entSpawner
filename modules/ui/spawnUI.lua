local config = require("modules/utils/config")
local utils = require("modules/utils/utils")

local types = {
    entity = {
        template = require("modules/classes/spawn/entity/entityTemplate"),
        record = require("modules/classes/spawn/entity/entityRecord")
    }
}

local spawnData = {}

spawnUI = {
    filter = "",
    selectedGroup = 0,
    sizeX = 0
}

function spawnUI.loadSpawnData()
    for dataName, dataType in pairs(types) do
        for subName, sub in pairs(dataType) do
            if sub.spawnListType == "list" then
                spawnData[dataName][dataType] = config.loadLists(sub.spawnListPath)
            else
                spawnData[dataName][dataType] = config.loadFiles(sub.spawnListPath)
            end
        end
    end
end

function spawnUI.loadPaths(spawner)
    spawnUI.paths = config.loadPaths("data/allPaths.txt")
    spawnUI.sort(spawner)
end

function spawnUI.updateFPaths()
    spawnUI.fPaths = {}
    for _, value in pairs(spawnUI.paths) do
        local path = value.path
        if spawner.settings.spawnUIOnlyNames then
            path = value.name
        end
        if (path:lower():match(spawnUI.filter:lower())) ~= nil then
            table.insert(spawnUI.fPaths, value)
        end
    end
end

function spawnUI.draw(spawner)
    spawnUI.filter, changed = ImGui.InputTextWithHint('##Filter', 'Search for object...', spawnUI.filter, 100)
    if changed then
        spawnUI.updateFPaths()
    end

    if spawnUI.filter ~= '' then
        ImGui.SameLine()
        if ImGui.Button('X') then
            spawnUI.filter = ''
            spawnUI.updateFPaths()
        end
    end

    local gs = {}
	for _, g in pairs(spawner.baseUI.spawnedUI.groups) do
		table.insert(gs, g.name)
	end

    if spawnUI.selectedGroup >= #gs then
        spawnUI.selectedGroup = 0
    end

	ImGui.PushItemWidth(200)
	spawnUI.selectedGroup = ImGui.Combo("Put new objects into group", spawnUI.selectedGroup, gs, #gs)
	ImGui.PopItemWidth()

    spawner.settings.spawnUIOnlyNames, changed = ImGui.Checkbox("Hide paths, show only names", spawner.settings.spawnUIOnlyNames)
    if changed then
        spawnUI.sort(spawner)
        config.saveFile("data/config.json", spawner.settings)
    end

    ImGui.SameLine()

    spawner.settings.spawnNewSortAlphabetical, changed = ImGui.Checkbox("Sort alphabetically", spawner.settings.spawnNewSortAlphabetical)
    if changed then
        spawnUI.sort(spawner)
        config.saveFile("data/config.json", spawner.settings)
    end

    ImGui.Separator()
    ImGui.Spacing()

    local types = {
        "Entity",
        "Mesh",
        "Light",
        "Occluder",
        "Collision"
    }

    ImGui.PushItemWidth(200)
	ImGui.Combo("Object type", 1, types, #types)
	ImGui.PopItemWidth()

    ImGui.Spacing()
    ImGui.Separator()

    local _, wHeight = GetDisplayResolution()

    ImGui.BeginChild("list", spawnUI.sizeX, wHeight - wHeight * 0.175)

    spawnUI.sizeX = 0

    local clipper = ImGuiListClipper.new()
    clipper:Begin(#spawnUI.fPaths, -1)
    while (clipper:Step()) do
        for i = clipper.DisplayStart + 1, clipper.DisplayEnd, 1 do
            p = spawnUI.fPaths[i]

            local path = p.path
            if spawner.settings.spawnUIOnlyNames then
                path = p.name
            end

            ImGui.PushID(path)

            local hasColor = false
            if p.obj ~= nil then
                ImGui.PushStyleColor(ImGuiCol.Button, 0xff009933)
                ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0xff009900)
                hasColor = true
            end

            if ImGui.Button(path) then
                local parent = nil
                if spawnUI.selectedGroup ~= 0 then
                    parent = spawner.baseUI.spawnedUI.groups[spawnUI.selectedGroup + 1].tab
                end
                local obj = spawner.baseUI.spawnedUI.spawnNewObject(p.path, parent)
                p.obj = obj
            end

            local x, _ = ImGui.GetItemRectSize()
            spawnUI.sizeX = math.max(x + 14, spawnUI.sizeX)

            if p.obj ~= nil then
                ImGui.SameLine()
                if ImGui.Button("Despawn") then
                    p.obj:despawn()
                    if p.obj.parent ~= nil then
                        utils.removeItem(p.obj.parent.childs, p.obj)
                        p.obj.parent:saveAfterMove()
                    end
                    utils.removeItem(spawner.baseUI.spawnedUI.elements, p.obj)
                    p.obj = nil
                end

                local deleteX, _ = ImGui.GetItemRectSize()
                spawnUI.sizeX = math.max(x + deleteX + 14, spawnUI.sizeX)

                if not utils.has_value(spawner.baseUI.spawnedUI.elements, p.obj) then
                    p.obj = nil
                end
            end

            if hasColor then ImGui.PopStyleColor(2) end

            ImGui.PopID()
        end
    end

    ImGui.EndChild()
end

function spawnUI.sort(spawner)
    if spawner.settings.spawnNewSortAlphabetical then
        table.sort(spawnUI.paths, function(a, b) return a.name:lower() < b.name:lower() end)
    end
    spawnUI.updateFPaths()
end

return spawnUI