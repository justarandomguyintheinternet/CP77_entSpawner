local config = require("modules/utils/config")
local utils = require("modules/utils/utils")

spawnUI = {
    filter = "",
    selectedGroup = 0,
    paths = {}
}

function spawnUI.loadPaths()
    spawnUI.paths = config.loadPaths("data/allPaths.txt")
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
    if changed then config.saveFile("data/config.json", spawner.settings) end

    ImGui.Separator()

    for _, p in pairs(spawnUI.paths) do
        local path = p.path
        if spawner.settings.spawnUIOnlyNames then
            path = p.name
        end
        if (path:lower():match(spawnUI.filter:lower())) ~= nil then
            ImGui.PushID(path)
            if ImGui.Button(path) then
                local parent = nil
                if spawnUI.selectedGroup ~= 0 then
                    parent = spawner.baseUI.spawnedUI.groups[spawnUI.selectedGroup + 1].tab
                end
                local obj = spawner.baseUI.spawnedUI.spawnNewObject(p.path, parent)
                p.obj = obj
            end
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

                if not utils.has_value(spawner.baseUI.spawnedUI.elements, p.obj) then
                    p.obj = nil
                end
            end
            ImGui.PopID()
        end
    end
end

return spawnUI