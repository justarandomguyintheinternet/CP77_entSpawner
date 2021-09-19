local config = require("modules/utils/config")
local utils = require("modules/utils/utils")
local CPS = require("CPStyling")
local object = require("modules/classes/spawn/object")

favorite = {}

function favorite:new(fUI)
	local o = {}

    o.name = ""
    o.path = ""
    o.parent = nil
    o.app = ""

    o.type = "favorite"
    o.newName = ""
    o.selectedGroup = -1
    o.color = {0, 50, 255}
    o.box = {x = 600, y = 118}

    o.fUI = fUI

	self.__index = self
   	return setmetatable(o, self)
end

function favorite:generateName(path) -- Generate valid name from path or if no path given current name
    local text = path or self.name
    if string.find(self.name, "\\") then
        self.name = text:match("\\[^\\]*$") -- Everything after last \
    end
    self.name = self.name:gsub(".ent", ""):gsub("\\", "_") -- Remove .ent, replace \ by _
    self.name = utils.createFileName(self.name)
end

function favorite:rename(name) -- Update file name to new given
    name = utils.createFileName(name)
    os.rename("data/favorites/" .. self.name .. ".json", "data/favorites/" .. name .. ".json")
    self.name = name
    self:save()
end

function favorite:save() -- Either save to file or return self as table to parent
    if self.parent == nil then
        self:generateName()
        local fav = {path = self.path, name = self.name, type = self.type, app = self.app}
        config.tryCreateConfig("data/favorites/" .. fav.name .. ".json", fav)
        config.saveFile("data/favorites/" .. fav.name .. ".json", fav)
    else
        return {path = self.path, name = self.name, type = self.type, app = self.app}
    end
end

function favorite:load(data)
    self.name = data.name
    self.path = data.path
    self.app = data.app or ""
end

function favorite:tryMainDraw()
    if self.parent == nil then
        self:draw()
    end
end

function favorite:draw()
    if self.parent ~= nil then
		ImGui.Indent(35)
	end

    ImGui.PushID(self.path)

    CPS.colorBegin("Border", self.color)
    CPS.colorBegin("Separator", self.color)
    ImGui.BeginChild("fav_" .. self.path, self.box.x, self.box.y, true)

        if self.newName == "" then self.newName = self.name end
        ImGui.PushItemWidth(300)
        self.newName, changed = ImGui.InputTextWithHint('##Name', 'Name...', self.newName, 100)
        ImGui.PopItemWidth()
        if changed then
            self:rename(self.newName)
            if self.parent ~= nil then
                self.parent:saveAfterMove()
            end
        end

        ImGui.Separator()

        --ImGui.Text("Path: " .. tostring(self.path))
        if ImGui.Button("Copy Path to clipboard") then
            ImGui.SetClipboardText(self.path)
        end

        --ImGui.Separator()

        local gs = {} -- Get list of all paths for dropdown
        for _, g in pairs(self.fUI.groups) do
            table.insert(gs, g.name)
        end

        if self.selectedGroup == -1 then -- If first call get the current path and make it selected
			self.selectedGroup = utils.indexValue(gs, self:getOwnPath(true)) - 1
		end

        ImGui.PushItemWidth(200)
        self.selectedGroup = ImGui.Combo("##movetogroup", self.selectedGroup, gs, #gs)
        ImGui.PopItemWidth()

        ImGui.SameLine()
        if ImGui.Button("Move") then
            if self:verifyMove(self.fUI.groups[self.selectedGroup + 1].tab) then -- Dont move inside same group
                if self.selectedGroup ~= 0 then
                    if self.parent == nil then
                        os.remove("data/favorites/" .. self.name .. ".json")
                    end
                    if self.parent ~= nil then
                        utils.removeItem(self.parent.childs, self)
                    end
                    self.parent = self.fUI.groups[self.selectedGroup + 1].tab
                    table.insert(self.fUI.groups[self.selectedGroup + 1].tab.childs, self)
                    self:saveAfterMove()
                else
                    if self.parent ~= nil then
                        utils.removeItem(self.parent.childs, self)
                        self.parent:saveAfterMove()
                    end

                    self.parent = nil
                    self:save()
                end
            end
        end

        ImGui.Separator()

        if CPS.CPButton("Spawn", 50, 25) then
            local new = object:new(self.fUI.spawner.baseUI.spawnedUI)
            new.pos = Game.GetPlayer():GetWorldPosition()

            if self.fUI.spawner.settings.spawnPos == 2 then
                local vec = Game.GetPlayer():GetWorldForward()
                new.pos.x = new.pos.x + vec.x * spawnedUI.spawner.settings.spawnDist
                new.pos.y = new.pos.y + vec.y * spawnedUI.spawner.settings.spawnDist
            end

            new.rot = GetSingleton('Quaternion'):ToEulerAngles(Game.GetPlayer():GetWorldOrientation())
            new.path = self.path
            new.name = self.name
            new.app = self.app
            new.apps = config.loadFile("data/apps.json")[new.path] or {}
            new:spawn()
            table.insert(self.fUI.spawner.baseUI.spawnedUI.elements, new)
        end
        ImGui.SameLine()
        if CPS.CPButton("Delete", 50, 25) then
            if self.parent ~= nil then
                utils.removeItem(self.parent.childs, self)
                self.parent:saveAfterMove()
            end
            utils.removeItem(self.fUI.elements, self)
            os.remove("data/favorites/" .. self.name .. ".json")
        end

    ImGui.EndChild()
    CPS.colorEnd(2)

    ImGui.PopID()

    if self.parent ~= nil then
		ImGui.Unindent(35)
	else
		ImGui.Separator()
	end
end

function favorite:verifyMove(to)
	local allowed = true

	if to == self.parent then
		allowed = false
	end

	return allowed
end

function favorite:saveAfterMove()
	if self.parent == nil then
		self:save()
	else
		self.parent:saveAfterMove()
	end
end

function favorite:getOwnPath(first)
    if self.parent == nil then
        if first then
            return "-- No group --"
        else
            return self.name
        end
    else
        if first then
            return self.parent:getOwnPath()
        else
            return tostring(self.parent:getOwnPath() .. "/" .. self.name)
        end
    end
end

return favorite