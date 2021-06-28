local config = require("modules/utils/config")
local utils = require("modules/utils/utils")

spawnUI = {
    filter = "",
    selectedGroup = 0,
    paths = {},
    sizeX = 0
}

function spawnUI.loadPaths(spawner)
    spawnUI.paths = config.loadPaths("data/allPaths.txt")
    spawnUI.sort(spawner)
end

function spawnUI.draw(spawner)
    spawnUI.filter = ImGui.InputTextWithHint('##Filter', 'Search for object...', spawnUI.filter, 100)

    if spawnUI.filter ~= '' then
        ImGui.SameLine()
        if ImGui.Button('X') then
            spawnUI.filter = ''
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

    local _, wHeight = GetDisplayResolution()

    ImGui.BeginChild("list", spawnUI.sizeX, wHeight - 150)

    spawnUI.sizeX = 0

    for _, p in pairs(spawnUI.paths) do
        local path = p.path
        if spawner.settings.spawnUIOnlyNames then
            path = p.name
        end
        if (path:lower():match(spawnUI.filter:lower())) ~= nil then
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
end

return spawnUI