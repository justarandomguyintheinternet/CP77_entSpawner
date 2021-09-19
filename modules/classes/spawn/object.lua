local config = require("modules/utils/config")
local utils = require("modules/utils/utils")
local CPS = require("CPStyling")
local object = require("modules/classes/object")

object = {}

function object:new(sUI)
	local o = {}

    o.name = "" -- Base stuff
    o.path = ""
    o.app = ""
    o.parent = nil
    o.spawned = false

    o.type = "object" -- Visual stuff
    o.newName = ""
    o.selectedGroup = -1
    o.color = {0, 50, 255}
    o.box = {x = 600, y = 218}
    o.id = math.random(1, 1000000000) -- Id for imgui child rng gods bls have mercy
    o.headerOpen = sUI.spawner.settings.headerState

    o.apps = {}
    o.appIndex = -1

    o.entID = nil -- Actual object stuff
    o.pos = Vector4.new(0, 0, 0, 0)
    o.rot = EulerAngles.new(0, 0, 0)

    o.autoLoad = false
	o.loadRange = sUI.spawner.settings.autoSpawnRange
    o.isAutoLoaded = false

    o.sUI = sUI

	self.__index = self
   	return setmetatable(o, self)
end

function object:spawn()
    local transform = Game.GetPlayer():GetWorldTransform()
    transform:SetOrientation(GetSingleton('EulerAngles'):ToQuat(self.rot))
    transform:SetPosition(self.pos)
    self.entID = exEntitySpawner.Spawn(self.path, transform, self.app)
    self.entity = Game.FindEntityByID(self.entID)
    self.spawned = true
end

function object:update()
    if self.spawned then
        local tpSuccess = pcall(function ()
            Game.GetTeleportationFacility():Teleport(Game.FindEntityByID(self.entID), self.pos,  self.rot)
        end)
        if not tpSuccess then
            Game.FindEntityByID(self.entID):GetEntity():Destroy()
            local transform = Game.GetPlayer():GetWorldTransform()
            transform:SetOrientation(GetSingleton('EulerAngles'):ToQuat(self.rot))
            transform:SetPosition(self.pos)
            self.entID = exEntitySpawner.Spawn(self.path, transform, self.app)
        end
    end
end

function object:despawn()
    if Game.FindEntityByID(self.entID) ~= nil then
        Game.FindEntityByID(self.entID):GetEntity():Destroy()
        self.spawned = false
    end
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
    name = utils.createFileName(name)
    os.rename("data/objects/" .. self.name .. ".json", "data/objects/" .. name .. ".json")
    self.name = name
    self.sUI.spawner.baseUI.savedUI.reload()
end

function object:save() -- Either save to file or return self as table to parent
    if self.parent == nil then
        self:generateName()
        local obj = {path = self.path, app = self.app, name = self.name, type = self.type, pos = utils.fromVector(self.pos), rot = utils.fromEuler(self.rot), headerOpen = self.headerOpen, autoLoad = self.autoLoad, loadRange = self.loadRange}
        config.tryCreateConfig("data/objects/" .. obj.name .. ".json", obj)
        config.saveFile("data/objects/" .. obj.name .. ".json", obj)
        self.sUI.spawner.baseUI.savedUI.reload()
    else
        return {path = self.path, app = self.app, name = self.name, type = self.type, pos = utils.fromVector(self.pos), rot = utils.fromEuler(self.rot), headerOpen = self.headerOpen, autoLoad = self.autoLoad, loadRange = self.loadRange}
    end
end

function object:load(data)
    self.name = data.name
    self.path = data.path
    self.pos = utils.getVector(data.pos)
    self.rot = utils.getEuler(data.rot)
    self.headerOpen = data.headerOpen
    self.autoLoad = data.autoLoad
    self.loadRange = data.loadRange

    self.app = data.app or ""
    self.apps = config.loadFile("data/apps.json")[self.path] or {}
end

function object:tryMainDraw()
    if self.parent == nil then
        self:draw()
    end
end

function object:checkSpawned()
    if Game.FindEntityByID(self.entID) == nil then
        self.spawned = false
    else
        self.spawned = true
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
        ImGui.BeginChild("obj_" .. tostring(self.name .. self.id), self.box.x, self.box.y, true)

        if not self.isAutoLoaded then
            if self.newName == "" then self.newName = self.name end
            ImGui.PushItemWidth(300)
            self.newName = ImGui.InputTextWithHint('##Name', 'Name...', self.newName, 100)
            ImGui.PopItemWidth()
            ImGui.SameLine()
            if ImGui.Button("Apply new object name") then
                self:rename(self.newName)
                self:saveAfterMove()
            end
        else
			ImGui.Text(tostring(self.name .. " | AUTOSPAWNED"))
		end

            ImGui.Separator()

            self:checkSpawned()
            ImGui.Text(tostring("Spawned: " .. tostring(self.spawned):upper()))

            ImGui.SameLine()

            if ImGui.Button("Copy Path to clipboard") then
                ImGui.SetClipboardText(self.path)
            end

            self:drawGroup()

            ImGui.Separator()

            self:drawApp()

            ImGui.Separator()

            self:drawPos()
            self:drawRot()

            ImGui.Separator()

            if CPS.CPButton("Spawn", 50, 25) then
                self:despawn()
                self:spawn()
            end
            ImGui.SameLine()
            if CPS.CPButton("Despawn", 60, 25) then
                self:despawn()
            end
            ImGui.SameLine()
            if CPS.CPButton("Clone", 50, 25) then
                local obj = object:new(self.sUI)
                obj.pos = Vector4.new(self.pos.x, self.pos.y, self.pos.z, self.pos.w)
                obj.rot = EulerAngles.new(self.rot.roll, self.rot.pitch, self.rot.yaw)
                obj.path = self.path
                obj.name = self.name .. " Clone"
                obj.apps = self.apps
                obj:spawn()
                table.insert(self.sUI.elements, obj)
                if self.parent ~= nil then
                    obj.parent = self.parent
                    table.insert(self.parent.childs, obj)
                end
            end
            ImGui.SameLine()
            if CPS.CPButton("Remove", 50, 25) then
                self:despawn()
                if self.parent ~= nil then
                    utils.removeItem(self.parent.childs, self)
                    self.parent:saveAfterMove()
                end
                utils.removeItem(self.sUI.elements, self)
            end
            ImGui.SameLine()
            if CPS.CPButton("Make Favorite", 100, 25) then
                self.sUI.spawner.baseUI.favUI.createNewFav(self)
            end
            ImGui.SameLine()
            if self.parent == nil then
                if CPS.CPButton("Save to file", 100, 25) then
                    self:save()
                    self.sUI.spawner.baseUI.savedUI.files[self.name] = nil
                end
                if self.sUI.spawner.settings.groupExport then
                    ImGui.SameLine()
                    if CPS.CPButton("Export", 60, 25) then
                        self:export()
                    end
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

    ImGui.PushItemWidth(200)
    self.selectedGroup = ImGui.Combo("##movetogroup", self.selectedGroup, gs, #gs)
    ImGui.PopItemWidth()

    ImGui.SameLine()
    if ImGui.Button("Move to group") then
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

function object:drawPos()
    ImGui.PushItemWidth(100)
    self.pos.x, changed = ImGui.DragFloat("##x", self.pos.x, self.sUI.spawner.settings.posSteps, -9999, 9999, "%.3f X")
    if changed then
        self:update()
    end
    ImGui.SameLine()
    self.pos.y, changed = ImGui.DragFloat("##y", self.pos.y, self.sUI.spawner.settings.posSteps, -9999, 9999, "%.3f Y")
    if changed then
        self:update()
    end
    ImGui.SameLine()
    self.pos.z, changed = ImGui.DragFloat("##z", self.pos.z, self.sUI.spawner.settings.posSteps, -9999, 9999, "%.3f Z")
    if changed then
        self:update()
    end
    ImGui.PopItemWidth()
    ImGui.SameLine()
    if ImGui.Button("To player") then
        self.pos = Game.GetPlayer():GetWorldPosition()
        self:update()
    end

    ImGui.PushItemWidth(150)
    local x, changed = ImGui.DragFloat("##r_x", 0, self.sUI.spawner.settings.posSteps, -9999, 9999, "%.3f Relativ X")
    if changed then
        local v = self:getEntitiy():GetWorldRight()
        self.pos.x = self.pos.x + (v.x * x)
        self.pos.y = self.pos.y + (v.y * x)
        self.pos.z = self.pos.z + (v.z * x)
        self:update()
        x = 0
    end
    ImGui.SameLine()
    local y, changed = ImGui.DragFloat("##r_y", 0, self.sUI.spawner.settings.posSteps, -9999, 9999, "%.3f Relativ Y")
    if changed then
        local v = self:getEntitiy():GetWorldForward()
        self.pos.x = self.pos.x + (v.x * y)
        self.pos.y = self.pos.y + (v.y * y)
        self.pos.z = self.pos.z + (v.z * y)
        self:update()
        y = 0
    end
    ImGui.SameLine()
    local z, changed = ImGui.DragFloat("##r_z", 0, self.sUI.spawner.settings.posSteps, -9999, 9999, "%.3f Relativ Z")
    if changed then
        local v = self:getEntitiy():GetWorldUp()
        self.pos.x = self.pos.x + (v.x * z)
        self.pos.y = self.pos.y + (v.y * z)
        self.pos.z = self.pos.z + (v.z * z)
        self:update()
        z = 0
    end
    ImGui.PopItemWidth()
end

function object:drawRot()
    ImGui.PushItemWidth(100)
    self.rot.roll, changed = ImGui.DragFloat("##roll", self.rot.roll, self.sUI.spawner.settings.rotSteps, -9999, 9999, "%.3f Roll")
    if changed then
        self:update()
    end
    ImGui.SameLine()
    self.rot.pitch, changed = ImGui.DragFloat("##pitch", self.rot.pitch, self.sUI.spawner.settings.rotSteps, -9999, 9999, "%.3f Pitch")
    if changed then
        self:update()
    end
    ImGui.SameLine()
    self.rot.yaw, changed = ImGui.DragFloat("##yaw", self.rot.yaw, self.sUI.spawner.settings.rotSteps, -9999, 9999, "%.3f Yaw")
    if changed then
        self:update()
    end
    ImGui.SameLine()
    ImGui.PopItemWidth()
    if ImGui.Button("Player rot") then
        self.rot = GetSingleton('Quaternion'):ToEulerAngles(Game.GetPlayer():GetWorldOrientation())
        self:update()
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

function object:export()
	local data = {{path = self.path, pos = utils.fromVector(self.pos), rot = utils.fromEuler(self.rot), app = self.app}}
	config.saveFile("export/" .. self.name .. "_export.json", data)
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