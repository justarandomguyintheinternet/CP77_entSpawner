local CPS = require("CPStyling")
local utils = require("modules/utils/utils")
local object = require("modules/classes/spawn/object")
local group = require("modules/classes/spawn/group")

spawnedUI = {
    elements = {},
    filter = "",
    newGroupName = "New Group",
    groups = {},
    spawner = nil
}

function spawnedUI.init(spawner)
    spawnedUI.spawner = spawner
end

function spawnedUI.spawnNewObject(path, parent)
    local new = object:new(spawnedUI)
    new.path = path
    new.name = path
    new.rot = GetSingleton('Quaternion'):ToEulerAngles(Game.GetPlayer():GetWorldOrientation())
    new.pos = Game.GetPlayer():GetWorldPosition()
    new.parent = parent

    if parent ~= nil then
        table.insert(new.parent.childs, new)
    end

    if spawnedUI.spawner.settings.spawnPos == 2 then
        local vec = Game.GetPlayer():GetWorldForward()
        new.pos.x = new.pos.x + vec.x * spawnedUI.spawner.settings.spawnDist
        new.pos.y = new.pos.y + vec.y * spawnedUI.spawner.settings.spawnDist
    end

    new:generateName()
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

function spawnedUI.draw(spawner)
    if spawnedUI.spawner == nil then spawnedUI.init(spawner) end

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
        g.name =utils.createFileName(spawnedUI.newGroupName)
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
    if ImGui.Button("Fetch all Apps (LAG)") then
        for _, object in pairs(spawnedUI.getAllObjects()) do
            spawnedUI.spawner.fetcher.queueFetching(object)
        end
    end

    ImGui.Separator()

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

function spawnedUI.hotkey()
    local allObjects = {}
    for _, data in pairs(spawnedUI.elements) do
        if data.type == "group" then
            for _, obj in pairs(data:getObjects()) do
                table.insert(allObjects, obj)
            end
        else
            table.insert(allObjects, data)
        end
    end

    local closest = 999
    local closestObj = nil

    for _, obj in pairs(allObjects) do

        targetDir = utils.subVector(obj.pos, Game.GetPlayer():GetWorldPosition())
        targetDir = Vector4.Normalize(targetDir)

        dot = Vector4.Dot(targetDir, Game.GetPlayer():GetWorldForward())

        angle =  math.deg(math.acos(dot))
        print(180-angle, obj.name)
        if (180 - angle) < closest then
            closest = 180 - angle
            closestObj = obj
        end
    end

    spawnedUI.filter = closestObj.name
end

return spawnedUI