local CPS = require("CPStyling")
local config = require("modules/utils/config")
local group = require("modules/classes/favorites/group")
local favorite = require("modules/classes/favorites/favorite")
local utils = require("modules/utils/utils")

favUI = {
    elements = {},
    filter = "",
    newGroupName = "New Group",
    groups = {},
    spawner = nil
}

function favUI.load(spawner)
    for _, file in pairs(dir("data/favorites")) do
        if file.name:match("^.+(%..+)$") == ".json" then
            local data = config.loadFile("data/favorites/" .. file.name)
            if data.type == "group" then
                local g = group:new(favUI)
                g:load(data)
                table.insert(favUI.elements, g)
            else
                local f = favorite:new(favUI)
                f:load(data)
                table.insert(favUI.elements, f)
            end
        end
    end
    favUI.spawner = spawner
end

function favUI.getGroups()
    favUI.groups = {}
    favUI.groups[1] = {name = "-- No group --"}
    for _, f in pairs(favUI.elements) do
        if f.type == "group" then
            if f.parent == nil then
                local ps = f:getPath()
                for _, p in pairs(ps) do
                    table.insert(favUI.groups, p)
                end
            end
        end
    end
end

function favUI.draw(spawner)
    favUI.getGroups()
    ImGui.PushItemWidth(250)
    favUI.filter = ImGui.InputTextWithHint('##Filter', 'Search for favorite...', favUI.filter, 100)
    ImGui.PopItemWidth()

    if favUI.filter ~= '' then
        ImGui.SameLine()
        if ImGui.Button('X') then
            favUI.filter = ''
        end
    end

    ImGui.PushItemWidth(250)
    favUI.newGroupName = ImGui.InputTextWithHint('##newGName', 'New group name...', favUI.newGroupName, 100)
    ImGui.PopItemWidth()
    ImGui.SameLine()
    if ImGui.Button("Add group") then
        local g = group:new(favUI)
        g.name = utils.createFileName(favUI.newGroupName)
        g:save()
        table.insert(favUI.elements, g)
    end
    ImGui.Separator()

    for _, f in pairs(favUI.elements) do
        if favUI.filter == "" then
            f:tryMainDraw()
        else
            if (f.name:lower():match(favUI.filter:lower())) ~= nil then
                if f.type == "favorite" then
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
end

function favUI.createNewFav(object)
    local fav = favorite:new(favUI)
    fav.path = object.path
    fav.name = object.name
    fav.app = object.app
    fav:generateName()
    table.insert(favUI.elements, fav)
    fav:save()
end

return favUI