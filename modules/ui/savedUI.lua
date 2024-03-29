local config = require("modules/utils/config")
local CPS = require("CPStyling")
local object = require("modules/classes/spawn/object")
local gr = require("modules/classes/spawn/group")
local utils = require("modules/utils/utils")

local debug = false

savedUI = {
    filter = "",
    color = {group = {0, 255, 0}, object = {0, 50, 255}},
    box = {group = {x = 600, y = 116}, object = {x = 600, y = 133}},
    files = {},
    spawner = nil,
    popup = false,
    deleteFile = nil,
    spawned = {}
}

function savedUI.draw(spawner)
    ImGui.PushItemWidth(250)
    savedUI.filter = ImGui.InputTextWithHint('##Filter', 'Search for data...', savedUI.filter, 100)
    ImGui.PopItemWidth()

    if savedUI.filter ~= '' then
        ImGui.SameLine()
        if ImGui.Button('X') then
            savedUI.filter = ''
        end
    end

    local _, wHeight = GetDisplayResolution()
    ImGui.BeginChild("savedUI", 610, math.min(savedUI.getHeight(), wHeight - 150))

    for _, file in pairs(dir("data/objects")) do
        if file.name:match("^.+(%..+)$") == ".json" then
            local exists = false
            for k, _ in pairs(savedUI.files) do
                if k == file.name then
                    exists = true
                end
            end
            if not exists then
                savedUI.files[file.name] = config.loadFile("data/objects/" .. file.name)
            end
        end
    end

    for _, d in pairs(savedUI.files) do
        if (d.name:lower():match(savedUI.filter:lower())) ~= nil then
            if d.type == "group" then
                savedUI.drawGroup(d, spawner)
            else
                savedUI.drawObject(d, spawner)
            end
        end
    end

    ImGui.EndChild()

    savedUI.handlePopUp()
end

function savedUI.drawGroup(group, spawner)
    CPS.colorBegin("Border", savedUI.color.group)
    CPS.colorBegin("Separator", savedUI.color.group)

	local h = 4 * ImGui.GetFrameHeight() + 4 * ImGui.GetStyle().ItemSpacing.y + 2 * ImGui.GetStyle().FramePadding.y + ImGui.GetStyle().ItemSpacing.y * 3 + 3
    ImGui.BeginChild("group_" .. group.name, savedUI.box.group.x, h, true)

    if group.newName == nil then group.newName = group.name end
    ImGui.PushItemWidth(300)
    group.newName = ImGui.InputTextWithHint('##Name', 'Name...', group.newName, 100)
    ImGui.PopItemWidth()
    ImGui.SameLine()

    if utils.hasIndex(savedUI.spawned, group.name) then
        ImGui.PushStyleColor(ImGuiCol.Button, 0xff777777)
        ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0xff777777)
        ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0xff777777)
        ImGui.Button("Apply Name")
        ImGui.PopStyleColor(3)
    else
        if ImGui.Button("Apply Name") then
            savedUI.files[group.name] = nil
            os.rename("data/objects/" .. group.name .. ".json", "data/objects/" .. group.newName .. ".json")
            group.name = group.newName
            group.newName = nil
            config.saveFile("data/objects/" .. group.name .. ".json", group)
            savedUI.files[group.name] = group
            savedUI.reload()
        end
    end

    ImGui.Separator()

    ImGui.Text("Position: X=" .. tostring(group.pos.x) .. ", Y=" .. tostring(group.pos.y) .. ", Z=" .. tostring(group.pos.z))

    ImGui.Separator()

    group.autoLoad, changed = ImGui.Checkbox("Auto Spawn", group.autoLoad)
    if changed then config.saveFile("data/objects/" .. group.name .. ".json", group) end
    ImGui.SameLine()
    ImGui.PushItemWidth(100)
    group.loadRange, changed = ImGui.InputFloat("Auto Spawn Range", group.loadRange, -9999, 9999, "%.1f")
    if changed then config.saveFile("data/objects/" .. group.name .. ".json", group) end
    ImGui.PopItemWidth()

    ImGui.Separator()

    if CPS.CPButton("Spawn") then
        local g = gr:new(spawner.baseUI.spawnedUI)
        g:load(group)
        g:spawn()
        table.insert(spawner.baseUI.spawnedUI.elements, g)
    end
    ImGui.SameLine()
    if CPS.CPButton("Load") then
        local g = gr:new(spawner.baseUI.spawnedUI)
        g:load(group)
        table.insert(spawner.baseUI.spawnedUI.elements, g)
    end
    ImGui.SameLine()
    if CPS.CPButton("TP to pos") then
        Game.GetTeleportationFacility():Teleport(Game.GetPlayer(), utils.getVector(group.pos), GetSingleton('Quaternion'):ToEulerAngles(Game.GetPlayer():GetWorldOrientation()))
    end
    ImGui.SameLine()
    if CPS.CPButton("Delete") then
        savedUI.deleteData(group)
    end

    if debug then
        ImGui.SameLine()
        if CPS.CPButton("TSE") then
            local g = gr:new(spawner.baseUI.spawnedUI)
            g:load(group)

            local data = {objs = {}}
            for _, obj in pairs(g:getObjects()) do
                table.insert(data.objs, {path = obj.path, pos = utils.fromVector(obj.pos), rot = utils.fromEuler(obj.rot)})
            end
            data.pos = utils.fromVector(g:getCenter())
            data.range = g.loadRange

            config.saveFile("export/" .. g.name .. "_TSE.json", data)
        end
    end

    ImGui.EndChild()
    CPS.colorEnd(2)
end

function savedUI.drawObject(obj, spawner)
    CPS.colorBegin("Border", savedUI.color.object)
    CPS.colorBegin("Separator", savedUI.color.object)

	local h = 5 * ImGui.GetFrameHeight() + 4 * ImGui.GetStyle().ItemSpacing.y + 2 * ImGui.GetStyle().FramePadding.y + ImGui.GetStyle().ItemSpacing.y * 3 + 3
    ImGui.BeginChild("group_" .. obj.name, savedUI.box.object.x, h, true)

    if obj.newName == nil then obj.newName = obj.name end
    ImGui.PushItemWidth(300)
    obj.newName = ImGui.InputTextWithHint('##Name', 'Name...', obj.newName, 100)
    ImGui.PopItemWidth()
    ImGui.SameLine()

    if utils.hasIndex(savedUI.spawned, obj.name) then
        ImGui.PushStyleColor(ImGuiCol.Button, 0xff777777)
        ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0xff777777)
        ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0xff777777)
        ImGui.Button("Apply Name")
        ImGui.PopStyleColor(3)
    else
        if ImGui.Button("Apply Name") then
            savedUI.files[obj.name] = nil
            os.rename("data/objects/" .. obj.name .. ".json", "data/objects/" .. obj.newName .. ".json")
            obj.name = obj.newName
            obj.newName = nil
            config.saveFile("data/objects/" .. obj.name .. ".json", obj)
            savedUI.files[obj.name] = obj
            savedUI.reload()
        end
    end

    ImGui.Separator()

    ImGui.Text("Position: X=" .. tostring(obj.pos.x) .. ", Y=" .. tostring(obj.pos.y) .. ", Z=" .. tostring(obj.pos.z))
    ImGui.Text("Path: " .. obj.path)

    ImGui.Separator()

    obj.autoLoad, changed = ImGui.Checkbox("Auto Spawn", obj.autoLoad)
    if changed then config.saveFile("data/objects/" .. obj.name .. ".json", obj) end
    ImGui.SameLine()
    ImGui.PushItemWidth(100)
    obj.loadRange, changed = ImGui.InputFloat("Auto Spawn Range", obj.loadRange, -9999, 9999, "%.1f")
    if changed then config.saveFile("data/objects/" .. obj.name .. ".json", obj) end
    ImGui.PopItemWidth()

    ImGui.Separator()

    if CPS.CPButton("Spawn") then
        local o = object:new(spawner.baseUI.spawnedUI)
        o:load(obj)
        o:spawn()
        table.insert(spawner.baseUI.spawnedUI.elements, o)
    end
    ImGui.SameLine()
    if CPS.CPButton("Load") then
        local o = object:new(spawner.baseUI.spawnedUI)
        o:load(obj)
        table.insert(spawner.baseUI.spawnedUI.elements, o)
    end
    ImGui.SameLine()
    if CPS.CPButton("TP to pos") then
        Game.GetTeleportationFacility():Teleport(Game.GetPlayer(),  utils.getVector(obj.pos), GetSingleton('Quaternion'):ToEulerAngles(Game.GetPlayer():GetWorldOrientation()))
    end
    ImGui.SameLine()
    if CPS.CPButton("Delete") then
        savedUI.deleteData(obj)
    end

    ImGui.EndChild()
    CPS.colorEnd(2)
end

function savedUI.deleteData(data)
    if savedUI.spawner.settings.deleteConfirm then
        savedUI.popup = true
        savedUI.deleteFile = data
    else
        os.remove("data/objects/" .. data.name .. ".json")
        savedUI.files[data.name .. ".json"] = nil
    end
end

function savedUI.handlePopUp()
    if savedUI.popup then
        ImGui.OpenPopup("Delete Data?")
        if ImGui.BeginPopupModal("Delete Data?", true, ImGuiWindowFlags.AlwaysAutoResize) then
            local again, changed = ImGui.Checkbox("Dont ask again", not savedUI.spawner.settings.deleteConfirm)
            if changed then
                savedUI.spawner.settings.deleteConfirm = not again
                config.saveFile("data/config.json", savedUI.spawner.settings)
            end

            if ImGui.Button("Cancel") then
                ImGui.CloseCurrentPopup()
                savedUI.popup = false
            end

            ImGui.SameLine()

            if ImGui.Button("Confirm") then
                ImGui.CloseCurrentPopup()
                os.remove("data/objects/" .. savedUI.deleteFile.name .. ".json")
                savedUI.files[savedUI.deleteFile.name .. ".json"] = nil
                savedUI.popup = false
            end
            ImGui.EndPopup()
        end
    end
end

function savedUI.getHeight()
    local y = 0
    for _, d in pairs(savedUI.files) do
        if (d.name:lower():match(savedUI.filter:lower())) ~= nil then
            if d.type == "group" then
                y = y + savedUI.box.group.y + 4
            else
                y = y + savedUI.box.object.y + 4
            end
        end
    end
    return y
end

function savedUI.reload()
    savedUI.files = {}

    for _, file in pairs(dir("data/objects")) do
        if file.name:match("^.+(%..+)$") == ".json" then
            savedUI.files[file.name] = config.loadFile("data/objects/" .. file.name)
        end
    end
end

function savedUI.run(spawner)
    for _, data in pairs(savedUI.files) do
        if (utils.distanceVector(Game.GetPlayer():GetWorldPosition(), data.pos) < data.loadRange) and data.autoLoad then
            if not utils.hasIndex(savedUI.spawned, data.name) then
                if data.type == "object" then
                    local o = object:new(spawner.baseUI.spawnedUI)
                    o:load(data)
                    o.isAutoLoaded = true
                    o.headerOpen = false
                    o:spawn()
                    table.insert(spawner.baseUI.spawnedUI.elements, o)
                    savedUI.spawned[data.name] = o
                else
                    local g = gr:new(spawner.baseUI.spawnedUI)
                    g:load(data)
                    g.isAutoLoaded = true
                    g.headerOpen = false
                    g:spawn()
                    table.insert(spawner.baseUI.spawnedUI.elements, g)
                    savedUI.spawned[data.name] = g
                end
            end
        end
    end

    for _, obj in pairs(savedUI.spawned) do
        if (utils.distanceVector(Game.GetPlayer():GetWorldPosition(), obj.pos) > obj.loadRange + 1) then
            if obj.type == "group" then
                obj:despawn()
                savedUI.spawned[obj.name] = nil
                utils.removeItem(spawner.baseUI.spawnedUI.elements, obj)

                for _, c in pairs(obj:getObjects()) do
                    utils.removeItem(spawner.baseUI.spawnedUI.elements, c)
                end
            else
                obj:despawn()
                savedUI.spawned[obj.name] = nil
                utils.removeItem(spawner.baseUI.spawnedUI.elements, obj)
            end
        end
    end
end

return savedUI