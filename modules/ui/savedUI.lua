local config = require("modules/utils/config")
local CPS = require("CPStyling")
local object = require("modules/classes/spawn/object")
local gr = require("modules/classes/spawn/group")
local utils = require("modules/utils/utils")
local style = require("modules/ui/style")
local settings = require("modules/utils/settings")
local amm = require("modules/utils/ammUtils")

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

function savedUI.convertObject(object, getState)
    local spawnable = require("modules/classes/spawn/entity/entityTemplate"):new()
    spawnable:loadSpawnData({
        spawnData = object.path,
        app = object.app
    }, ToVector4(object.pos), ToEulerAngles(object.rot))

    local newObject = require("modules/classes/spawn/object"):new(savedUI)
    newObject.name = object.name
    newObject.headerOpen = object.headerOpen
    newObject.loadRange = object.loadRange
    newObject.autoLoad = object.autoLoad
    newObject.spawnable = spawnable

    if getState then
        return newObject:getState()
    else
        return newObject
    end
end

function savedUI.convertGroup(group)
    local data = {}

    for _, child in pairs(group.childs) do
        if child.type == "object" then
            table.insert(data, savedUI.convertObject(child, true))
        else
            table.insert(data, savedUI.convertGroup(child))
        end
    end

    group.childs = data
    return group
end

function savedUI.backwardComp()
    for _, file in pairs(dir("data/objects")) do
        if file.name:match("^.+(%..+)$") == ".json" then
            local data = config.loadFile("data/objects/" .. file.name)

            if data.type == "object" and data.path then
                config.saveFile("data/oldFormat/" .. file.name, data)

                local new = savedUI.convertObject(data, true)
                config.saveFile("data/objects/" .. file.name, new)
                print("[ObjectSpawner] Converted \"" .. file.name .. "\" to the new file format.")
            elseif data.type == "group" and not data.isUsingSpawnables then
                config.saveFile("data/oldFormat/" .. file.name, data)

                data = savedUI.convertGroup(data)
                data.isUsingSpawnables = true
                config.saveFile("data/objects/" .. file.name, data)
                print("[ObjectSpawner] Converted \"" .. file.name .. "\" to the new file format.")
            end
        end
    end
end

function savedUI.importAMMPresets()
    amm.importPresets(savedUI)
end

function savedUI.draw(spawner)
    ImGui.PushItemWidth(250)
    savedUI.filter, changed = ImGui.InputTextWithHint('##Filter', 'Search for data...', savedUI.filter, 100)
    if changed then
        settings.savedUIFilter = savedUI.filter
        settings.save()
    end
    ImGui.PopItemWidth()

    if savedUI.filter ~= '' then
        ImGui.SameLine()
        if ImGui.Button('X') then
            savedUI.filter = ''
            settings.savedUIFilter = savedUI.filter
            settings.save()
        end
    end

    style.spacedSeparator()

    if ImGui.Button("Import AMM Presets") then
        savedUI.importAMMPresets()
    end
    style.tooltip("Imports all presets from the AMMImport folder.\nImport might take a bit, depending on size.\nThe initial spawn might crash for now.")

    style.spacedSeparator()

    local _, wHeight = GetDisplayResolution()
    ImGui.BeginChild("savedUI", 0, math.min(savedUI.getHeight(), wHeight - 150))

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

local function getGroupHeight()
    return 3 * ImGui.GetFrameHeight() + 2 * ImGui.GetStyle().WindowPadding.y + ImGui.GetStyle().ItemSpacing.y * 7
end

local function getObjectHeight()
    return 4 * ImGui.GetFrameHeight() + 7 * ImGui.GetStyle().ItemSpacing.y + 2 * ImGui.GetStyle().WindowPadding.y
end

function savedUI.drawGroup(group, spawner)
    CPS.colorBegin("Border", savedUI.color.group)
    CPS.colorBegin("Separator", savedUI.color.group)

    ImGui.BeginChild("group_" .. group.name, savedUI.box.group.x - ImGui.GetStyle().ScrollbarSize, getGroupHeight(), true)

    if group.newName == nil then group.newName = group.name end

    style.pushGreyedOut(utils.hasIndex(savedUI.spawned, group.name))

    ImGui.PushItemWidth(300)
    group.newName = ImGui.InputTextWithHint('##Name', 'Name...', group.newName, 100)
    ImGui.PopItemWidth()

    if ImGui.IsItemDeactivatedAfterEdit() then
        savedUI.files[group.name] = nil
        os.rename("data/objects/" .. group.name .. ".json", "data/objects/" .. group.newName .. ".json")
        group.name = group.newName
        group.newName = nil
        config.saveFile("data/objects/" .. group.name .. ".json", group)
        savedUI.files[group.name] = group
        savedUI.reload()
    end

    style.popGreyedOut(utils.hasIndex(savedUI.spawned, group.name))

    style.spacedSeparator()

    local pPos = Vector4.new(0, 0, 0, 0)
    if GetPlayer() then
        pPos = GetPlayer():GetWorldPosition()
    end
    ImGui.Text(("Position: X=%.1f Y=%.1f Z=%.1f, Distance: %.1f"):format(group.pos.x, group.pos.y, group.pos.z, ToVector4(group.pos):Distance(pPos)))

    style.spacedSeparator()

    -- group.autoLoad, changed = ImGui.Checkbox("Auto Spawn", group.autoLoad)
    -- if changed then config.saveFile("data/objects/" .. group.name .. ".json", group) end
    -- ImGui.SameLine()
    -- ImGui.PushItemWidth(100)
    -- group.loadRange, changed = ImGui.InputFloat("Auto Spawn Range", group.loadRange, -9999, 9999, "%.1f")
    -- if changed then config.saveFile("data/objects/" .. group.name .. ".json", group) end
    -- ImGui.PopItemWidth()

    -- ImGui.Separator()

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
    if CPS.CPButton("Add to Export") then
        spawner.baseUI.exportUI.addGroup(group.name)
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

    ImGui.BeginChild("group_" .. obj.name, savedUI.box.object.x - ImGui.GetStyle().ScrollbarSize, getObjectHeight(), true)

    if obj.newName == nil then obj.newName = obj.name end

    style.pushGreyedOut(utils.hasIndex(savedUI.spawned, obj.name))

    ImGui.PushItemWidth(300)
    obj.newName = ImGui.InputTextWithHint('##Name', 'Name...', obj.newName, 100)
    ImGui.PopItemWidth()

    if ImGui.IsItemDeactivatedAfterEdit() then
        savedUI.files[obj.name] = nil
        os.rename("data/objects/" .. obj.name .. ".json", "data/objects/" .. obj.newName .. ".json")
        obj.name = obj.newName
        obj.newName = nil
        config.saveFile("data/objects/" .. obj.name .. ".json", obj)
        savedUI.files[obj.name] = obj
        savedUI.reload()
    end

    style.popGreyedOut(utils.hasIndex(savedUI.spawned, obj.name))

    style.spacedSeparator()

    local pPos = Vector4.new(0, 0, 0, 0)
    if GetPlayer() then
        pPos = GetPlayer():GetWorldPosition()
    end
    ImGui.Text(("Position: X=%.1f Y=%.1f Z=%.1f, Distance: %.1f"):format(obj.spawnable.position.x, obj.spawnable.position.y, obj.spawnable.position.z, ToVector4(obj.spawnable.position):Distance(pPos)))
    ImGui.Text("Type: " .. obj.spawnable.dataType)

    style.spacedSeparator()

    -- obj.autoLoad, changed = ImGui.Checkbox("Auto Spawn", obj.autoLoad)
    -- if changed then config.saveFile("data/objects/" .. obj.name .. ".json", obj) end
    -- ImGui.SameLine()
    -- ImGui.PushItemWidth(100)
    -- obj.loadRange, changed = ImGui.InputFloat("Auto Spawn Range", obj.loadRange, -9999, 9999, "%.1f")
    -- if changed then config.saveFile("data/objects/" .. obj.name .. ".json", obj) end
    -- ImGui.PopItemWidth()

    -- ImGui.Separator()

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
    if settings.deleteConfirm then
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
            local again, changed = ImGui.Checkbox("Dont ask again", not settings.deleteConfirm)
            if changed then
                settings.deleteConfirm = not again
                settings.save()
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
            if y ~= 0 then
                y = y + ImGui.GetStyle().ItemSpacing.y
            end
            if d.type == "group" then
                y = y + getGroupHeight()
            else
                y = y + getObjectHeight()
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
    -- for _, data in pairs(savedUI.files) do
    --     if (utils.distanceVector(Game.GetPlayer():GetWorldPosition(), data.pos) < data.loadRange) and data.autoLoad then
    --         if not utils.hasIndex(savedUI.spawned, data.name) then
    --             if data.type == "object" then
    --                 local o = object:new(spawner.baseUI.spawnedUI)
    --                 o:load(data)
    --                 o.isAutoLoaded = true
    --                 o.headerOpen = false
    --                 o:spawn()
    --                 table.insert(spawner.baseUI.spawnedUI.elements, o)
    --                 savedUI.spawned[data.name] = o
    --             else
    --                 local g = gr:new(spawner.baseUI.spawnedUI)
    --                 g:load(data)
    --                 g.isAutoLoaded = true
    --                 g.headerOpen = false
    --                 g:spawn()
    --                 table.insert(spawner.baseUI.spawnedUI.elements, g)
    --                 savedUI.spawned[data.name] = g
    --             end
    --         end
    --     end
    -- end

    -- for _, obj in pairs(savedUI.spawned) do
    --     if (utils.distanceVector(Game.GetPlayer():GetWorldPosition(), obj.pos) > obj.loadRange + 1) then
    --         if obj.type == "group" then
    --             obj:despawn()
    --             savedUI.spawned[obj.name] = nil
    --             utils.removeItem(spawner.baseUI.spawnedUI.elements, obj)

    --             for _, c in pairs(obj:getObjects()) do
    --                 utils.removeItem(spawner.baseUI.spawnedUI.elements, c)
    --             end
    --         else
    --             obj:despawn()
    --             savedUI.spawned[obj.name] = nil
    --             utils.removeItem(spawner.baseUI.spawnedUI.elements, obj)
    --         end
    --     end
    -- end
end

return savedUI