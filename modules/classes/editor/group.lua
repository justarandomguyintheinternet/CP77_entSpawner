local object = require("modules/classes/spawn/object")
local utils = require("modules/utils/utils")
local CPS = require("CPStyling")
local style = require("modules/ui/style")
local settings = require("modules/utils/settings")

local element = require("modules/classes/editor/element")

---Class for organizing multiple objects and or groups
---@class group : element
local group = setmetatable({}, { __index = element })

function group:new(sUI)
	local o = element.new(self, sUI)

	o.name = "New Group"
	o.modulePath = "modules/classes/editor/group"

	o.pos = Vector4.new(0, 0, 0, 0)
    o.rot = EulerAngles.new(0, 0, 0)
	o.isUsingSpawnables = true

	setmetatable(o, { __index = self })
   	return o
end

---@override
function group:load(data)
	element.load(self, data)

	self.pos = utils.getVector(data.pos)
	self.rot = utils.getEuler(data.rot)
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

	if self.beingDragged then ImGui.PushStyleColor(ImGuiCol.Header, 1, 0, 0, 0.5) end
	if self.beingTargeted then ImGui.PushStyleColor(ImGuiCol.Header, 0, 1, 0, 0.5) end
    self.headerOpen = ImGui.CollapsingHeader(n)
	if self.beingDragged or self.beingTargeted then ImGui.PopStyleColor() end

	self:handleDrag()

	local addY = 0
	if settings.groupRot then addY = ImGui.GetFrameHeight() + ImGui.GetStyle().ItemSpacing.y end

	if self.headerOpen then
		CPS.colorBegin("Border", self.color)

		local h = 6 * ImGui.GetFrameHeight() + 2 * ImGui.GetStyle().FramePadding.y + 7 * ImGui.GetStyle().ItemSpacing.y
    	ImGui.BeginChild("group" .. tostring(self.name .. self.id), self.box.x, h + addY, true)

		if not self.isAutoLoaded then
			if self.newName == nil then self.newName = self.name end

			ImGui.SetNextItemWidth(300)
			self.newName, changed = ImGui.InputTextWithHint('##newname', 'New Name...', self.newName, 100)
			if ImGui.IsItemDeactivatedAfterEdit() then
				self:rename(self.newName)
				self:saveAfterMove()
			end
		else
			ImGui.Text(tostring(self.name .. " | AUTOSPAWNED"))
		end

		self:drawMoveGroup()

		---TODO: Unify draggability into class, hierarchical things into class
		---TODO: Draw arrow
		---TODO: Add group spawnable controls
		---TODO: More modular for future NCA feature

		CPS.colorBegin("Separator", self.color)
		style.spacedSeparator()

		self.pos = self:getCenter()
		self:drawPos()

		if settings.groupRot then
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
			g.name = utils.generateCopyName(self.name)

			if settings.moveCloneToParent == 1 then
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
	end

	ImGui.PopID()
end

---@protected
function group:drawPos()
	ImGui.PushItemWidth(150)
	local x = self.pos.x
    x, changed = ImGui.DragFloat("##x", x, settings.posSteps, -9999, 9999, "%.3f X")
    if changed then
		x = x - self.pos.x
        self:update(Vector4.new(x, 0, 0, 0))
		self:getCenter()
    end
    ImGui.SameLine()
	local y = self.pos.y
    y, changed = ImGui.DragFloat("##y", y, settings.posSteps, -9999, 9999, "%.3f Y")
    if changed then
        y = y - self.pos.y
        self:update(Vector4.new(0, y, 0, 0))
		self:getCenter()
    end
    ImGui.SameLine()
	local z = self.pos.z
    z, changed = ImGui.DragFloat("##z", z, settings.posSteps, -9999, 9999, "%.3f Z")
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
    local x, changed = ImGui.DragFloat("##r_x", 0, settings.posSteps, -9999, 9999, "%.3f Relative X")
    if changed then
        local v = self:getAvgVector("right")
        self:update(Vector4.new((v.x * x), (v.y * x), (v.z * x), 0))
		self:getCenter()
		x = 0
    end
    ImGui.SameLine()
    local y, changed = ImGui.DragFloat("##r_y", 0, settings.posSteps, -9999, 9999, "%.3f Relative Y")
    if changed then
        local v = self:getAvgVector("forward")
        self:update(Vector4.new((v.x * y), (v.y * y), (v.z * y), 0))
		self:getCenter()
		y = 0
    end
    ImGui.SameLine()
    local z, changed = ImGui.DragFloat("##r_z", 0, settings.posSteps, -9999, 9999, "%.3f Relative Z")
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
    local roll, changed = ImGui.DragFloat("##roll", self.rot.roll, settings.rotSteps, -9999, 9999, "%.3f Roll")
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
    local pitch, changed = ImGui.DragFloat("##pitch", self.rot.pitch, settings.rotSteps, -9999, 9999, "%.3f Pitch")
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
    local yaw, changed = ImGui.DragFloat("##yaw", self.rot.yaw, settings.rotSteps, -9999, 9999, "%.3f Yaw")
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

return group