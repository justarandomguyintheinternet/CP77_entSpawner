local config = require("modules/utils/config")
local object = require("modules/classes/spawn/object")
local utils = require("modules/utils/utils")
local CPS = require("CPStyling")
local style = require("modules/ui/style")

---Class for organizing multiple objects and or groups
---@class group
---@field public name string
---@field public childs object[]
---@field public parent group?
---@field public selectedGroup integer
---@field public type string
---@field public color table
---@field public box table {x: number, y: number}
---@field public id integer
---@field public headerOpen boolean
---@field public pos Vector4
---@field public rot EulerAngles
---@field public autoLoad boolean
---@field public loadRange number
---@field public isAutoLoaded boolean
---@field public sUI table
---@field public isUsingSpawnables boolean Signalizes that the groups has been converted from the old format
group = {}

function group:new(sUI)
	local o = {}

	o.name = "New Group"
	o.childs = {}
	o.parent = nil

	o.selectedGroup = -1
	o.type = "group"
	o.color = {0, 255, 0}
	o.box = {x = 600, y = 142}
	o.id = math.random(1, 1000000000) -- Id for imgui child rng gods bls have mercy
	o.headerOpen = sUI.spawner.settings.headerState

	o.pos = Vector4.new(0, 0, 0, 0)
    o.rot = EulerAngles.new(0, 0, 0)

	o.autoLoad = false
	o.loadRange = sUI.spawner.settings.autoSpawnRange
	o.isAutoLoaded = false

	o.sUI = sUI
	o.isUsingSpawnables = true

	self.__index = self
   	return setmetatable(o, self)
end

---Loads the data from a given table, recursively building up the tree of child elements
---@param data table {name, childs, type, pos, rot, headerOpen, autoLoad, loadRange}
---@param silent boolean
function group:load(data, silent)
	self.name = data.name
	self.pos = utils.getVector(data.pos)
	self.rot = utils.getEuler(data.rot)
	self.headerOpen = data.headerOpen
	self.autoLoad = data.autoLoad
	self.loadRange = data.loadRange

	for _, c in pairs(data.childs) do
		if c.type == "group" then
			local g = require("modules/classes/spawn/group"):new(self.sUI)
			g.parent = self
			g:load(c)
			table.insert(self.childs, g)
			if not silent then
				table.insert(self.sUI.elements, g)
			end
		else
			local o = object:new(self.sUI)
			o:load(c)
			o.parent = self
			table.insert(self.childs, o)
			if not silent then
				table.insert(self.sUI.elements, o)
			end
		end
	end
end

---Try to draw as "main group"
function group:tryMainDraw()
	if self.parent == nil then
		self:draw()
	end
end

---Update file name to new given
---@param name string
function group:rename(name)
	name = utils.createFileName(name)
    os.rename("data/objects/" .. self.name .. ".json", "data/objects/" .. name .. ".json")
    self.name = name
	self.sUI.spawner.baseUI.savedUI.reload()
end

---Draw func if this is just a sub group
---@protected
function group:draw()
	ImGui.PushID(tostring(self.name .. self.id))

	if self.parent ~= nil then
		ImGui.Indent(35)
	end

	ImGui.SetNextItemOpen(self.headerOpen)

	local n = self.name
	if self.isAutoLoaded then n = tostring(self.name .. " | AUTOSPAWNED") end

    self.headerOpen = ImGui.CollapsingHeader(n)

	local addY = 0
	if spawner.settings.groupRot then addY = ImGui.GetFrameHeight() + ImGui.GetStyle().ItemSpacing.y end

	if self.headerOpen then
		CPS.colorBegin("Border", self.color)

		local h = 6 * ImGui.GetFrameHeight() + 2 * ImGui.GetStyle().FramePadding.y + 7 * ImGui.GetStyle().ItemSpacing.y
    	ImGui.BeginChild("group" .. tostring(self.name .. self.id), self.box.x, h + addY, true)

		if not self.isAutoLoaded then
			if self.newName == nil then self.newName = "" end
			ImGui.SetNextItemWidth(250)
			self.newName, changed = ImGui.InputTextWithHint('##newname', 'New Name...', self.newName, 100)
			ImGui.SameLine()
			if ImGui.Button("Apply", 150, 0) then
				self:rename(self.newName)
				self:saveAfterMove()
			end
		else
			ImGui.Text(tostring(self.name .. " | AUTOSPAWNED"))
		end

		self:drawMoveGroup()

		CPS.colorBegin("Separator", self.color)
		style.spacedSeparator()

		self.pos = self:getCenter()
		self:drawPos()

		if spawner.settings.groupRot then
			self:drawRot()
		end

		ImGui.Spacing()
		style.spacedSeparator()

		CPS.colorEnd()

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
			local g = require("modules/classes/spawn/group"):new(self.sUI)

			g:load(self:toTable())
			g.name = self.name .. " Clone"

			if self.sUI.spawner.settings.moveCloneToParent == 1 then
				g.parent = self
				table.insert(self.childs, g)
			else
				if self.parent ~= nil then
					g.parent = self.parent
					table.insert(self.parent.childs, g)
				else
					g.parent = nil
				end
			end

			table.insert(self.sUI.elements, g)
			g:spawn()
		end
		ImGui.SameLine()
		if CPS.CPButton("Remove") then
			self:remove()
		end
		ImGui.SameLine()
		if self.parent == nil then
			if CPS.CPButton("Save to file") then
				self:save()
				self.sUI.spawner.baseUI.savedUI.files[self.name] = nil
			end
			--- TODO: Do we still need this?
			-- if self.sUI.spawner.settings.groupExport then
			-- 	ImGui.SameLine()
			-- 	if CPS.CPButton("Export") then
			-- 		self:export()
			-- 	end
			-- end
		end

		ImGui.EndChild()
    	CPS.colorEnd(1)

        for _, c in pairs(self.childs) do
			c:draw()
		end
		--ImGui.TreePop()
	end
	if self.parent ~= nil then
		ImGui.Unindent(35)
	else
		ImGui.Separator()
	end

	ImGui.PopID()
end

---@protected
function group:drawMoveGroup()
	local gs = {}
	for _, g in pairs(self.sUI.groups) do
		table.insert(gs, g.name)
	end

	if self.selectedGroup == -1 then
		self.selectedGroup = utils.indexValue(gs, self:getOwnPath(true)) - 1
	end

	ImGui.SetNextItemWidth(250)
	self.selectedGroup = ImGui.Combo("##moveto", self.selectedGroup, gs, #gs)
	ImGui.SameLine()
	if ImGui.Button("Move to group", 150, 0) then
		if self:verifyMove(self.sUI.groups[self.selectedGroup + 1].tab) then
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

---@protected
function group:drawPos()
	ImGui.PushItemWidth(150)
	local x = self.pos.x
    x, changed = ImGui.DragFloat("##x", x, self.sUI.spawner.settings.posSteps, -9999, 9999, "%.3f X")
    if changed then
		x = x - self.pos.x
        self:update(Vector4.new(x, 0, 0, 0))
		self:getCenter()
    end
    ImGui.SameLine()
	local y = self.pos.y
    y, changed = ImGui.DragFloat("##y", y, self.sUI.spawner.settings.posSteps, -9999, 9999, "%.3f Y")
    if changed then
        y = y - self.pos.y
        self:update(Vector4.new(0, y, 0, 0))
		self:getCenter()
    end
    ImGui.SameLine()
	local z = self.pos.z
    z, changed = ImGui.DragFloat("##z", z, self.sUI.spawner.settings.posSteps, -9999, 9999, "%.3f Z")
    if changed then
        z = z - self.pos.z
        self:update(Vector4.new(0, 0, z, 0))
		self:getCenter()
    end
    ImGui.PopItemWidth()
    ImGui.SameLine()
    if ImGui.Button("To player") then
        self:update(utils.subVector(Game.GetPlayer():GetWorldPosition(), self.pos))
		self.pos = Game.GetPlayer():GetWorldPosition()
    end

    ImGui.PushItemWidth(150)
    local x, changed = ImGui.DragFloat("##r_x", 0, self.sUI.spawner.settings.posSteps, -9999, 9999, "%.3f Relative X")
    if changed then
        local v = self:getAvgVector("right")
        self:update(Vector4.new((v.x * x), (v.y * x), (v.z * x), 0))
		self:getCenter()
		x = 0
    end
    ImGui.SameLine()
    local y, changed = ImGui.DragFloat("##r_y", 0, self.sUI.spawner.settings.posSteps, -9999, 9999, "%.3f Relative Y")
    if changed then
        local v = self:getAvgVector("forward")
        self:update(Vector4.new((v.x * y), (v.y * y), (v.z * y), 0))
		self:getCenter()
		y = 0
    end
    ImGui.SameLine()
    local z, changed = ImGui.DragFloat("##r_z", 0, self.sUI.spawner.settings.posSteps, -9999, 9999, "%.3f Relative Z")
    if changed then
        local v = self:getAvgVector("up")
        self:update(Vector4.new((v.x * z), (v.y * z), (v.z * z), 0))
		self:getCenter()
		z = 0
    end
    ImGui.PopItemWidth()
end

---@protected
function group:drawRot()
    ImGui.PushItemWidth(150)
    local roll, changed = ImGui.DragFloat("##roll", self.rot.roll, self.sUI.spawner.settings.rotSteps, -9999, 9999, "%.3f Roll")
    if changed then
		roll = roll - self.rot.roll
		local objs = self:getObjects()
		for _, o in pairs(objs) do
			o:setPosition(utils.addVector(Vector4.RotateAxis(utils.subVector(o:getPosition(), self.pos), self:getAvgVector("forward"), math.rad(roll)), self.pos))
			o.spawnable.rotation.roll = o.spawnable.rotation.roll + roll
		end

		self.rot.roll = self.rot.roll + roll
		self:update(Vector4.new(0, 0, 0, 0))
    end
    ImGui.SameLine()
    local pitch, changed = ImGui.DragFloat("##pitch", self.rot.pitch, self.sUI.spawner.settings.rotSteps, -9999, 9999, "%.3f Pitch")
    if changed then
		pitch = pitch - self.rot.pitch
		local objs = self:getObjects()
		for _, o in pairs(objs) do
			o:setPosition(utils.addVector(Vector4.RotateAxis(utils.subVector(o:getPosition(), self.pos), self:getAvgVector("right"), math.rad(pitch)), self.pos))
			o.spawnable.rotation.pitch = o.spawnable.rotation.pitch + pitch
		end

		self.rot.pitch = self.rot.pitch + pitch
		self:update(Vector4.new(0, 0, 0, 0))
    end
    ImGui.SameLine()
    local yaw, changed = ImGui.DragFloat("##yaw", self.rot.yaw, self.sUI.spawner.settings.rotSteps, -9999, 9999, "%.3f Yaw")
    if changed then
        yaw = yaw - self.rot.yaw
		local objs = self:getObjects()
		for _, o in pairs(objs) do
			o:setPosition(utils.addVector(Vector4.RotateAxis(utils.subVector(o:getPosition(), self.pos), self:getAvgVector("up"), math.rad(yaw)), self.pos))
			o.spawnable.rotation.yaw = o.spawnable.rotation.yaw + yaw
		end

		self.rot.yaw = self.rot.yaw + yaw
		self:update(Vector4.new(0, 0, 0, 0))
    end
    ImGui.SameLine()
    ImGui.PopItemWidth()
end

function group:spawn()
	for _, obj in pairs(self:getObjects()) do
		obj:spawn()
	end
end

function group:despawn()
	for _, obj in pairs(self:getObjects()) do
		obj:despawn()
	end
end

function group:remove()
	self:despawn()
	if self.parent ~= nil then
		utils.removeItem(self.parent.childs, self)
		self.parent:saveAfterMove()
	end
	for _, c in pairs(self:getObjects()) do
		utils.removeItem(self.sUI.elements, c)
	end
	utils.removeItem(self.sUI.elements, self)
end

function group:update(vec)
	for _, obj in pairs(self:getObjects()) do
		obj:setPosition(utils.addVector(obj:getPosition(), vec))
	end
end

function group:getAvgVector(dir)
	local objs = self:getObjects()
	local vectors = {}
	local vec = Vector4.new(0,0,0,0)

	local maxDegDiff = 3

	if #objs > 0 then
		for _, o in pairs(objs) do
			local dirVec = Vector4.new(0, 0, 0, 0)
			local entity = o.spawnable:getEntity()

			if entity then
				if dir == "forward" then
					dirVec =  entity:GetWorldForward()
				elseif dir == "right" then
					dirVec =  entity:GetWorldRight()
				elseif dir == "up" then
					dirVec =  entity:GetWorldUp()
				end
			end
			if #vectors == 0 then
				table.insert(vectors, {vec = dirVec, count = 1})
			else
				local hasSimilar = false
				for _, v in pairs(vectors) do
					if Vector4.GetAngleBetween(v.vec, dirVec) < maxDegDiff then
						v.count = v.count + 1
						hasSimilar = true
					end
				end
				if not hasSimilar then
					table.insert(vectors, {vec = dirVec, count = 1})
				end
			end
		end
	end

	local biggest = {vec = vec, count = 0}
	for _, v in pairs(vectors) do
		if v.count > biggest.count then
			biggest = v
		end
	end

	return biggest.vec
end

function group:getCenter()
	local center = Vector4.new(0,0,0,0)
	local objs = self:getObjects()
	if #objs > 0 then
		local totalX = 0
		local totalY = 0
		local totalZ = 0
		for _, o in pairs(objs) do
			totalX = totalX + o:getPosition().x
			totalY = totalY + o:getPosition().y
			totalZ = totalZ + o:getPosition().z
		end
		center = Vector4.new(totalX / #objs, totalY / #objs, totalZ / #objs, 0)
	end
	return center
end

function group:getObjects()
	local objects = {}
	for _, c in pairs(self.childs) do
		if c.type == "group" then
			local objs = c:getObjects()
			for _, o in pairs(objs) do
				table.insert(objects, o)
			end
		else
			table.insert(objects, c)
		end
	end
	return objects
end

function group:verifyMove(to) -- Make sure group doesnt get moved into child
	local allowed = true
	local childs = self:getPath()
	for _, c in pairs(childs) do
		if c.tab == to then
			allowed = false
		end
	end

	if to == self.parent then
		allowed = false
	end

	return allowed
end

function group:getPath() -- Recursive function called from favUI to get all paths to all objects
	local paths = {}
	table.insert(paths, {name = self.name, tab = self})

	if #self.childs ~= 0 then
		for _, c in pairs(self.childs) do
			if c.type == "group" then
				local ps = c:getPath()
				for _, p in pairs(ps) do
					table.insert(paths, {name = self.name .. "/" .. p.name, tab = p.tab})
				end
			end
		end
	end

	return paths
end

function group:save()
	if self.parent == nil then
		local data = { isUsingSpawnables = true, name = self.name, childs = {}, type = self.type, pos = utils.fromVector(self.pos), rot = utils.fromEuler(self.rot), headerOpen = self.headerOpen, autoLoad = self.autoLoad, loadRange = self.loadRange}
		for _, c in pairs(self.childs) do
			table.insert(data.childs, c:save())
		end
		config.saveFile("data/objects/" .. self.name .. ".json", data)
		self.sUI.spawner.baseUI.savedUI.reload()
	else
		local data = { isUsingSpawnables = true, name = self.name, childs = {}, type = self.type, pos = utils.fromVector(self.pos), rot = utils.fromEuler(self.rot), headerOpen = self.headerOpen, autoLoad = self.autoLoad, loadRange = self.loadRange}
		for _, c in pairs(self.childs) do
			table.insert(data.childs, c:save())
		end
		return data
	end
end

function group:toTable()
	local data = { isUsingSpawnables = true, name = self.name, childs = {}, type = self.type, pos = utils.fromVector(self.pos), rot = utils.fromEuler(self.rot), headerOpen = self.headerOpen, autoLoad = self.autoLoad, loadRange = self.loadRange}
	for _, c in pairs(self.childs) do
		table.insert(data.childs, c:save())
	end
	return data
end

function group:saveAfterMove()
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

function group:getOwnPath(first)
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

function group:export()
	local data = {}
	for _, obj in pairs(self:getObjects()) do
		table.insert(data, {path = obj.path, pos = utils.fromVector(obj.pos), rot = utils.fromEuler(obj.rot), app = obj.app})
	end
	config.saveFile("export/" .. self.name .. "_export.json", data)
end

function group:getHeight(yy)
	local y = yy
	if self.headerOpen then
		y = y + self.box.y + 30
		for _, c in pairs(self.childs) do
			y = c:getHeight(y)
		end
		return y
	else
		return y + 28
	end
end

function group:getWidth(x)
	if self.headerOpen then
		if self.parent ~= nil then
			x = math.max(x, x + 35)
		else
			if x ~= self.box.x + 35 then
				x = math.max(x, x + 35)
			end
		end
		local once = false
		for _, c in pairs(self.childs) do
			if c.type == "object" then
				if not once then
					x = math.max(x, x + 35)
				end
				once = true
			else
				x = math.max(x, c:getWidth(x))
			end
		end
	end
	return x
end

return group