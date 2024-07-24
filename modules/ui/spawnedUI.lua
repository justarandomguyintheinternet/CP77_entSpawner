local utils = require("modules/utils/utils")
local object = require("modules/classes/spawn/object")
local group = require("modules/classes/spawn/group")
local settings = require("modules/utils/settings")

---@class spawnedUI
---@field elements table {element}
---@field filter string
---@field newGroupName string
---@field groups table {string}
---@field spawner spawner?
spawnedUI = {
    elements = {},
    filter = "",
    newGroupName = "New Group",
    groups = {},
    spawner = nil
}

function spawnedUI.spawnNewObject(entry, class, parent)
    local new = object:new(spawnedUI)
    local rot = GetPlayer():GetWorldOrientation():ToEulerAngles()
    local pos = GetPlayer():GetWorldPosition()

    if settings.spawnPos == 2 then
        local forward = GetPlayer():GetWorldForward()
        pos.x = pos.x + forward.x * settings.spawnDist
        pos.y = pos.y + forward.y * settings.spawnDist
    end

    new.spawnable = class:new(new)
    new.spawnable.object = new
    new.spawnable:loadSpawnData(entry.data, pos, rot)
    new.name = new.spawnable:generateName(entry.name)
    new.parent = parent

    if parent ~= nil then
        table.insert(new.parent.childs, new)
    end

    new:spawn()
    table.insert(spawnedUI.elements, new)
    return new
end

function spawnedUI.getGroups()
    spawnedUI.groups = {}
    spawnedUI.groups[1] = {name = "-- No group --"}
    for _, f in pairs(spawnedUI.elements) do
        if f.type == "group" then
            if f.parent == nil then
                local ps = f:getPath()
                for _, p in pairs(ps) do
                    table.insert(spawnedUI.groups, p)
                end
            end
        end
    end
end

function spawnedUI.draw()
    spawnedUI.getGroups()

    ImGui.PushItemWidth(250)
    spawnedUI.filter = ImGui.InputTextWithHint('##Filter', 'Search for object...', spawnedUI.filter, 100)
    ImGui.PopItemWidth()

    if spawnedUI.filter ~= '' then
        ImGui.SameLine()
        if ImGui.Button('X') then
            spawnedUI.filter = ''
        end
    end

    ImGui.PushItemWidth(250)
    spawnedUI.newGroupName = ImGui.InputTextWithHint('##newG', 'New group name...', spawnedUI.newGroupName, 100)
    ImGui.PopItemWidth()

    ImGui.SameLine()
    if ImGui.Button("Add group") then
        local g = group:new(spawnedUI)
        g.name = utils.createFileName(spawnedUI.newGroupName)
        table.insert(spawnedUI.elements, g)
    end

    if ImGui.Button("Collapse all") then
        for _, e in pairs(spawnedUI.elements) do
            e.headerOpen = false
        end
    end
    ImGui.SameLine()
    if ImGui.Button("Expand all") then
        for _, e in pairs(spawnedUI.elements) do
            e.headerOpen = true
        end
    end
    ImGui.SameLine()
    if ImGui.Button("Spawn all") then
        for _, e in pairs(spawnedUI.elements) do
            e:spawn()
        end
    end
    ImGui.SameLine()
    if ImGui.Button("Despawn all") then
        for _, e in pairs(spawnedUI.elements) do
            e:despawn()
        end
    end

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()

    local _, wHeight = GetDisplayResolution()
    ImGui.BeginChild("spawnedUI", spawnedUI.getWidth(), wHeight - wHeight * 0.175)

    for _, f in pairs(spawnedUI.elements) do
        if spawnedUI.filter == "" then
            f:tryMainDraw()
        else
            if (f.name:lower():match(spawnedUI.filter:lower())) ~= nil then
                if f.type == "object" then
                    if f.parent ~= nil then
                        ImGui.Unindent(35)
                    end
                    f:draw()
                    if f.parent ~= nil then
                        ImGui.Indent(35)
                    end
                end
            end
        end
    end

    ImGui.EndChild()
end

function spawnedUI.getAllObjects()
    local allObjects = {}
    for _, e in pairs(spawnedUI.elements) do
        if e.type == "object" then
            table.insert(allObjects, e)
        else
            for _, obj in pairs(e:getObjects()) do
                table.insert(allObjects, obj)
            end
        end
    end
    return allObjects
end

function spawnedUI.getHeight()
    local y = 0
    for _, e in pairs(spawnedUI.elements) do
        if e.parent == nil then
            y = e:getHeight(y)
        end
    end

    local _, wHeight = GetDisplayResolution()
    if spawnedUI.filter ~= "" then y = wHeight - 150 end
    return y
end

function spawnedUI.getWidth()
    local x = 0
    for _, e in pairs(spawnedUI.elements) do
        if e.parent == nil then
            if e.type == "object" then
                x = math.max(x, e.box.x)
            else
                x = math.max(x, e.box.x)
                x = math.max(x, e:getWidth(x))
            end
        end
    end
    return x
end

function spawnedUI.despawnAll()
    for _, e in pairs(spawnedUI.elements) do
        e:despawn()
    end
end

return spawnedUI