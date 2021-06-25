local config = require("modules/utils/config")
local favorite = require("modules/classes/favorites/favorite")
local utils = require("modules/utils/utils")
local CPS = require("CPStyling")

group = {}

function group:new(fUI)
	local o = {}

	o.name = "New Group"
	o.childs = {}
	o.parent = nil

	o.selectedGroup = -1
	o.type = "group"
	o.color = {0, 255, 0}
	o.box = {x = 600, y = 92}

	o.fUI = fUI

	self.__index = self
   	return setmetatable(o, self)
end

function group:load(data)
	self.name = data.name

	local cData = data.childs
	for _, c in pairs(cData) do
		if c.type == "group" then
			local g = group:new(self.fUI)
			g.parent = self
			g:load(c)
			table.insert(self.childs, g)
			table.insert(self.fUI.elements, g)
		else
			local f = favorite:new(self.fUI)
			f.name = c.name
			f.path = c.path
			f.parent = self
			table.insert(self.childs, f)
			table.insert(self.fUI.elements, f)
		end
	end
end

function group:tryMainDraw() -- Try to draw as "main group"
	if self.parent == nil then
		self:draw()
	end
end

function group:rename(name) -- Update file name to new given
	name = utils.createFileName(name)
    os.rename("data/favorites/" .. self.name .. ".json", "data/favorites/" .. name .. ".json")
    self.name = name
    self:save()
end

function group:draw() -- Draw func if this is just a sub group
	ImGui.PushID(self.name)

	if self.parent ~= nil then
		ImGui.Indent(35)
	end
	if ImGui.TreeNodeEx(self.name, ImGuiTreeNodeFlags.CollapsingHeader) then
		CPS.colorBegin("Border", self.color)
    	ImGui.BeginChild("group" .. self.name, self.box.x, self.box.y, true)

		if self.newName == nil then self.newName = "" end
        ImGui.PushItemWidth(300)
        self.newName, changed = ImGui.InputTextWithHint('##newname', 'New Name...', self.newName, 100)
        ImGui.PopItemWidth()
		ImGui.SameLine()
        if ImGui.Button("Apply new group name") then
			self:rename(self.newName)
            self:saveAfterMove()
        end

		local gs = {}
		for _, g in pairs(self.fUI.groups) do
			table.insert(gs, g.name)
		end

		if self.selectedGroup == -1 then
			self.selectedGroup = utils.indexValue(gs, self:getOwnPath(true)) - 1
		end

		ImGui.PushItemWidth(200)
		self.selectedGroup = ImGui.Combo("##moveto", self.selectedGroup, gs, #gs)
		ImGui.PopItemWidth()
		ImGui.SameLine()
		if ImGui.Button("Move to group") then
			if self:verifyMove(self.fUI.groups[self.selectedGroup + 1].tab) then
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

		CPS.colorBegin("Separator", self.color)
		ImGui.Separator()
		CPS.colorEnd()

		if CPS.CPButton("Delete", 50, 25) then
            if self.parent ~= nil then
                utils.removeItem(self.parent.childs, self)
				self.parent:saveAfterMove()
            end
            utils.removeItem(self.fUI.elements, self)
            os.remove("data/favorites/" .. self.name .. ".json")
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
		local data = {name = self.name, childs = {}, type = self.type}
		for _, c in pairs(self.childs) do
			table.insert(data.childs, c:save())
		end
		config.saveFile("data/favorites/" .. self.name .. ".json", data)
	else
		local data = {name = self.name, childs = {}, type = self.type}
		for _, c in pairs(self.childs) do
			table.insert(data.childs, c:save())
		end
		return data
	end
end

function group:saveAfterMove()
	if self.parent == nil then
		self:save()
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

return group