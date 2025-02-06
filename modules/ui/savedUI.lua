local config = require("modules/utils/config")
local utils = require("modules/utils/utils")
local style = require("modules/ui/style")
local settings = require("modules/utils/settings")
local amm = require("modules/utils/ammUtils")
local history = require("modules/utils/history")

savedUI = {
    filter = "",
    color = {group = {0, 255, 0}, object = {0, 50, 255}},
    box = {group = {x = 600, y = 116}, object = {x = 600, y = 133}},
    files = {},
    spawner = nil,
    popup = false,
    deleteFile = nil,
    spawned = {},
    maxTextWidth = nil
}

function savedUI.convertObject(object, getState)
    local spawnable = require("modules/classes/spawn/entity/entityTemplate"):new()
    spawnable:loadSpawnData({
        spawnData = object.path,
        app = object.app
    }, ToVector4(object.pos), ToEulerAngles(object.rot))

    local newObject = require("modules/classes/editor/spawnableElement"):new(savedUI)
    newObject.name = object.name
    newObject.headerOpen = object.headerOpen
    newObject.loadRange = object.loadRange
    newObject.autoLoad = object.autoLoad
    newObject.spawnable = spawnable

    if getState then
        return newObject:serialize()
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
    if amm.importing then return end
    amm.importPresets(savedUI)
end

function savedUI.draw(spawner)
    if not savedUI.maxTextWidth then
        savedUI.maxTextWidth = utils.getTextMaxWidth({"File name:", "Position:"}) + 4 * ImGui.GetStyle().ItemSpacing.x
    end

    ImGui.PushItemWidth(250 * style.viewSize)
    savedUI.filter, changed = ImGui.InputTextWithHint('##Filter', 'Search for data...', savedUI.filter, 100)
    if changed then
        settings.savedUIFilter = savedUI.filter
        settings.save()
    end
    ImGui.PopItemWidth()

    if savedUI.filter ~= '' then
        ImGui.SameLine()

        style.pushButtonNoBG(true)
        if ImGui.Button(IconGlyphs.Close) then
            savedUI.filter = ''
            settings.savedUIFilter = savedUI.filter
            settings.save()
        end
        style.pushButtonNoBG(false)
    end

    style.spacedSeparator()

    if not amm.importing then
        if ImGui.Button("Import AMM Presets") then
            savedUI.importAMMPresets()
        end
        style.tooltip("Imports all presets from the AMMImport folder.\nImport might take a bit, depending on size.\nThe initial spawn might crash for now.\nMight leave behind unwanted objects, so reloading a save is advised.")
    else
        ImGui.ProgressBar(amm.progress / amm.total, 200, 30, string.format("%.2f%%", (amm.progress / amm.total) * 100))
    end

    style.spacedSeparator()

    ImGui.BeginChild("savedUI")

    for _, file in pairs(dir("data/objects")) do
        if file.name:match("^.+(%..+)$") == ".json" then
            if not savedUI.files[file.name] then
                savedUI.files[file.name] = config.loadFile("data/objects/" .. file.name)
            end
        end
    end

    for _, d in pairs(savedUI.files) do
        if (d.name:lower():match(savedUI.filter:lower())) ~= nil then
            if d.type == "group" or d.modulePath == "modules/classes/editor/positionableGroup" then
                savedUI.drawGroup(d, spawner)
            elseif d.type == "element" or d.modulePath == "modules/classes/editor/spawnableElement" then
                savedUI.drawObject(d, spawner)
            end
        end
    end

    ImGui.EndChild()

    savedUI.handlePopUp()
end

function savedUI.drawGroup(group, spawner)
    if ImGui.TreeNodeEx(group.name) then
        local pPos = Vector4.new(0, 0, 0, 0)
        if spawner.player then
            pPos = spawner.player:GetWorldPosition()
        end
        local posString = ("X=%.1f Y=%.1f Z=%.1f, Distance: %.1f"):format(group.pos.x, group.pos.y, group.pos.z, ToVector4(group.pos):Distance(pPos))

        if group.newName == nil then group.newName = group.name end

        style.pushGreyedOut(utils.hasIndex(savedUI.spawned, group.name))

        style.mutedText("File name:")
        ImGui.SameLine()
        ImGui.SetCursorPosX(savedUI.maxTextWidth)
        ImGui.PushItemWidth(180 * style.viewSize)
        group.newName = ImGui.InputTextWithHint('##Name', 'Name...', group.newName, 100)
        ImGui.PopItemWidth()

        if ImGui.IsItemDeactivatedAfterEdit() then
            savedUI.files[group.name .. ".json"] = nil
            os.rename("data/objects/" .. group.name .. ".json", "data/objects/" .. group.newName .. ".json")
            group.name = group.newName
            config.saveFile("data/objects/" .. group.name .. ".json", group)
            savedUI.files[group.name .. ".json"] = group
        end

        style.popGreyedOut(utils.hasIndex(savedUI.spawned, group.name))

        style.mutedText("Position:")
        ImGui.SameLine()
        ImGui.SetCursorPosX(savedUI.maxTextWidth)
        ImGui.Text(posString)

        if ImGui.Button("Load") then
            local g = require("modules/classes/editor/positionableGroup"):new(spawner.baseUI.spawnedUI)
            g:load(utils.deepcopy(group))
            spawner.baseUI.spawnedUI.addRootElement(g)
            history.addAction(history.getInsert({ g }))
        end
        ImGui.SameLine()
        if ImGui.Button("TP to pos") then
            Game.GetTeleportationFacility():Teleport(Game.GetPlayer(), utils.getVector(group.pos), GetSingleton('Quaternion'):ToEulerAngles(Game.GetPlayer():GetWorldOrientation()))
        end
        ImGui.SameLine()
        if ImGui.Button("Add to Export") then
            spawner.baseUI.exportUI.addGroup(group.name)
        end
        ImGui.SameLine()
        if ImGui.Button("Delete") then
            savedUI.deleteData(group)
        end

        ImGui.TreePop()
        ImGui.Spacing()
    end
end

function savedUI.drawObject(obj, spawner)
    if ImGui.TreeNodeEx(group.name) then
        local pPos = Vector4.new(0, 0, 0, 0)
        if spawner.player then
            pPos = spawner.player:GetWorldPosition()
        end
        local posString = ("X=%.1f Y=%.1f Z=%.1f, Distance: %.1f"):format(obj.spawnable.position.x, obj.spawnable.position.y, obj.spawnable.position.z, ToVector4(obj.spawnable.position):Distance(pPos))

        if obj.newName == nil then obj.newName = obj.name end

        style.pushGreyedOut(utils.hasIndex(savedUI.spawned, obj.name))

        ImGui.SetNextItemWidth(180 * style.viewSize)
        obj.newName = ImGui.InputTextWithHint('##Name', 'Name...', obj.newName, 100)
        ImGui.PopItemWidth()

        if ImGui.IsItemDeactivatedAfterEdit() then
            savedUI.files[obj.name .. ".json"] = nil
            os.rename("data/objects/" .. obj.name .. ".json", "data/objects/" .. obj.newName .. ".json")
            obj.name = obj.newName
            config.saveFile("data/objects/" .. obj.name .. ".json", obj)
            savedUI.files[obj.name .. ".json"] = obj
        end

        style.popGreyedOut(utils.hasIndex(savedUI.spawned, obj.name))

        style.mutedText("Position:")
        ImGui.SameLine()
        ImGui.Text(posString)

        style.mutedText("Type:")
        ImGui.SameLine()
        ImGui.Text(obj.spawnable.dataType)

        if ImGui.Button("Load") then
            local o = require("modules/classes/editor/spawnableElement"):new(spawner.baseUI.spawnedUI)
            o:load(obj)
            spawner.baseUI.spawnedUI.addRootElement(o)
            history.addAction(history.getInsert({ o }))
        end
        ImGui.SameLine()
        if ImGui.Button("TP to pos") then
            Game.GetTeleportationFacility():Teleport(Game.GetPlayer(),  utils.getVector(obj.pos), GetSingleton('Quaternion'):ToEulerAngles(Game.GetPlayer():GetWorldOrientation()))
        end
        ImGui.SameLine()
        if ImGui.Button("Delete") then
            savedUI.deleteData(obj)
        end

        ImGui.TreePop()
        ImGui.Spacing()
    end
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

function savedUI.reload()
    savedUI.files = {}

    for _, file in pairs(dir("data/objects")) do
        if file.name:match("^.+(%..+)$") == ".json" then
            savedUI.files[file.name] = config.loadFile("data/objects/" .. file.name)
        end
    end
end

return savedUI