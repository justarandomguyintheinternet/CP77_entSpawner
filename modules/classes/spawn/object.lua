local config = require("modules/utils/config")
local utils = require("modules/utils/utils")
local CPS = require("CPStyling")
local object = require("modules/classes/object")

object = {}

function object:new(sUI)
	local o = {}

    o.name = "" -- Base stuff
    o.parent = nil

    o.type = "object" -- Visual stuff
    o.newName = ""
    o.selectedGroup = -1
    o.color = {0, 50, 255}
    o.box = {x = 650, y = 282}
    o.id = math.random(1, 1000000000) -- Id for imgui child rng gods bls have mercy
    o.headerOpen = sUI.spawner.settings.headerState
    o.dynSize = nil

    o.autoLoad = false
	o.loadRange = sUI.spawner.settings.autoSpawnRange
    o.isAutoLoaded = false

    o.spawnable = nil

    o.sUI = sUI

	self.__index = self
   	return setmetatable(o, self)
end

function object:spawn()
    self.spawnable:spawn()
end

function object:update()
    self.spawnable:update()
end

function object:despawn()
    self.spawnable:despawn()
end

function object:getPosition()
    return self.spawnable.position
end

function object:setPosition(position)
    self.spawnable.position = position
    self:update()
end

function object:getRotation()
    return self.spawnable.rotation
end

-- Group system functions

function object:generateName(path) -- Generate valid name from path or if no path given current name
    local text = path or self.name
    if string.find(self.name, "\\") then
        self.name = text:match("\\[^\\]*$") -- Everything after last \
    end
    self.name = self.name:gsub(".ent", ""):gsub("\\", "_") -- Remove .ent, replace \ by _
    self.name = utils.createFileName(self.name)
end

function object:rename(name) -- Update file name to new given
    name = self.spawnable:generateName(name)
    os.rename("data/objects/" .. self.name .. ".json", "data/objects/" .. name .. ".json")
    self.name = name
    self.sUI.spawner.baseUI.savedUI.reload()
end

function object:getState()
    self.name = self.spawnable:generateName(self.name)

    return {
        name = self.name,
        type = self.type,
        headerOpen = self.headerOpen,
        autoLoad = self.autoLoad,
        loadRange = self.loadRange,
        spawnable = self.spawnable:save()
    }
end

function object:save() -- Either save to file or return self as table to parent
    if self.parent == nil then
        local state = self:getState()

        config.tryCreateConfig("data/objects/" .. state.name .. ".json", state)
        config.saveFile("data/objects/" .. state.name .. ".json", state)
        self.sUI.spawner.baseUI.savedUI.reload()
    else
        return self:getState()
    end
end

function object:load(data)
    self.name = data.name
    self.headerOpen = data.headerOpen
    self.autoLoad = data.autoLoad
    self.loadRange = data.loadRange

    self.spawnable = require("modules/classes/spawn/" .. data.spawnable.modulePath):new()
    self.spawnable:loadSpawnData(data.spawnable, ToVector4(data.spawnable.position), ToEulerAngles(data.spawnable.rotation), self.sUI.spawner)

    -- self.app = data.app or ""
    -- self.apps = config.loadFile("data/apps.json")[self.path] or {}
end

function object:tryMainDraw()
    if self.parent == nil then
        self:draw()
    end
end

function object:draw()
    if self.parent ~= nil then
		ImGui.Indent(35)
	end

    ImGui.PushID(tostring(self.name .. self.id))
    ImGui.SetNextItemOpen(self.headerOpen)

    self.headerOpen = ImGui.CollapsingHeader(self.name)
    if self.headerOpen then
        CPS.colorBegin("Border", self.color)
        CPS.colorBegin("Separator", self.color)

        local h = 6 * ImGui.GetFrameHeight() + 2 * ImGui.GetStyle().WindowPadding.y + 5 * ImGui.GetStyle().ItemSpacing.y + 6 * ImGui.GetStyle().ItemSpacing.y
        h = h + self.spawnable:getExtraHeight()
        ImGui.BeginChild("obj_" .. tostring(self.name .. self.id), self.box.x, h, true)

        if not self.isAutoLoaded then
            ImGui.SetNextItemWidth(250)
            self.newName = ImGui.InputTextWithHint('##Name', 'New Name...', self.newName, 100)
            ImGui.SameLine()

            if ImGui.Button("Apply", 150, 0) then
                self:rename(self.newName)
                self:saveAfterMove()
                self.newName = ""
            end
        else
			ImGui.Text(tostring(self.name .. " | AUTOSPAWNED"))
		end

        -- ImGui.Text(tostring("Spawned: " .. tostring(self.spawnable:isSpawned()):upper()))

        -- if ImGui.Button("Copy Path to clipboard") then
        --     ImGui.SetClipboardText(self.path)
        -- end

        self:drawGroup()

        ImGui.Spacing()
        ImGui.Separator()
        ImGui.Spacing()

        self.spawnable:draw()

        ImGui.Spacing()
        ImGui.Separator()
        ImGui.Spacing()

        if CPS.CPButton("Spawn") then
            self:despawn()
            self:spawn()
        end
        ImGui.SameLine()
        if CPS.CPButton("Despawn") then
            self:despawn()
        end
        ImGui.SameLine()
        if CPS.CPButton("Clone") then
            local clone = object:new(self.sUI)
            local rot = EulerAngles.new(self.spawnable.rotation.roll, self.spawnable.rotation.pitch, self.spawnable.rotation.yaw)
            local pos = Vector4.new(self.spawnable.position.x, self.spawnable.position.y, self.spawnable.position.z, 0)

            clone.spawnable = require("modules/classes/spawn/" .. self.spawnable.modulePath):new()
            clone.spawnable:loadSpawnData(self.spawnable:save(), pos, rot, self.sUI.spawner)

            clone.name = self.name .. " Clone"

            clone:spawn()
            table.insert(self.sUI.elements, clone)
            if self.parent ~= nil then
                clone.parent = self.parent
                table.insert(self.parent.childs, clone)
            end
        end
        ImGui.SameLine()
        if CPS.CPButton("Remove") then
            self:despawn()
            if self.parent ~= nil then
                utils.removeItem(self.parent.childs, self)
                self.parent:saveAfterMove()
            end
            utils.removeItem(self.sUI.elements, self)
        end
        ImGui.SameLine()
        if CPS.CPButton("Make Favorite") then
            self.sUI.spawner.baseUI.favUI.createNewFav(self)
        end
        ImGui.SameLine()
        if self.parent == nil then
            if CPS.CPButton("Save to file") then
                self:save()
                self.sUI.spawner.baseUI.savedUI.files[self.name] = nil
            end
        end

        ImGui.EndChild()
        CPS.colorEnd(2)
    end

    ImGui.PopID()

    if self.parent ~= nil then
		ImGui.Unindent(35)
	else
		ImGui.Separator()
	end
end

function object:drawGroup()
    local gs = {} -- Get list of all paths for dropdown
    for _, g in pairs(self.sUI.groups) do
        table.insert(gs, g.name)
    end

    if self.selectedGroup == -1 then -- If first call get the current path and make it selected
        self.selectedGroup = utils.indexValue(gs, self:getOwnPath(true)) - 1
    end

    ImGui.SetNextItemWidth(250)
    self.selectedGroup = ImGui.Combo("##movetogroup", self.selectedGroup, gs, #gs)

    ImGui.SameLine()

    if ImGui.Button("Move to group", 150, 0) then
        if self:verifyMove(self.sUI.groups[self.selectedGroup + 1].tab) then -- Dont move inside same group
            if self.selectedGroup ~= 0 then
                if self.parent == nil then
                    os.remove("data/objects/" .. self.name .. ".json")
                    self.sUI.spawner.baseUI.savedUI.reload()
                end
                if self.parent ~= nil then
                    utils.removeItem(self.parent.childs, self)
                end
                self.parent = self.sUI.groups[self.selectedGroup + 1].tab
                table.insert(self.sUI.groups[self.selectedGroup + 1].tab.childs, self)
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
end

function object:drawApp()
    ImGui.PushItemWidth(100)
    self.app, changed = ImGui.InputTextWithHint('##App', 'Appearance...', self.app, 100)
    if changed then self:getEntitiy():ScheduleAppearanceChange(self.app) end
    ImGui.PopItemWidth()

    if #self.apps ~= 0 then
        ImGui.SameLine()

        local as = {}
        table.insert(as, "-- Default Appearance --")
        for _, app in pairs(self.apps) do
            table.insert(as, app)
        end
        if self.appIndex == -1 then
            self.appIndex = utils.indexValue(self.apps, self.app)
        end
        if self.apps[1] == "default" then self.appIndex = 1 end
        if self.appIndex == -1 then
            self.appIndex = 0
        end
        ImGui.PushItemWidth(200)

        local numItems = #as
        if self.apps[1] == "default" then numItems = numItems - 1 end

        self.appIndex, changed = ImGui.Combo("##app", self.appIndex, as, numItems)
        if changed and self.appIndex ~= 0 then
            self.app = self.apps[self.appIndex]
            self:despawn()
            self:getEntitiy():ScheduleAppearanceChange(self.app)
            self:spawn()
        elseif changed and self.appIndex == 0 then
            self.app = ""
            self:despawn()
            self:getEntitiy():ScheduleAppearanceChange(self.apps[1])
            self:spawn()
        end
        ImGui.PopItemWidth()
    end

    ImGui.SameLine()
    if ImGui.Button("Fetch Apps") then
        self.sUI.spawner.fetcher.queueFetching(self)
    end
end

function object:getEntitiy()
    return Game.FindEntityByID(self.entID)
end

function object:verifyMove(to)
	local allowed = true

	if to == self.parent then
		allowed = false
	end

	return allowed
end

function object:saveAfterMove()
	if self.parent == nil then
		for _, file in pairs(dir("data/objects")) do
			if file.name:match("^.+(%..+)$") == ".json" then
				if file.name == self.name .. ".json" then
					self:save()
				end
			end
		end
	else
		self.parent:saveAfterMove()
	end
end

function object:getOwnPath(first)
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

function object:getHeight(y)
	if self.headerOpen then
		return y + self.box.y + 32
	else
	    return y + 28
    end
end

function object:getWidth(x)
    if self.headerOpen then
        return math.max(x, x + 35)
    else
        return x
    end
end

return object