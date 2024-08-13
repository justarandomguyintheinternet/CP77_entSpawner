local config = require("modules/utils/config")
local object = require("modules/classes/spawn/object")
local utils = require("modules/utils/utils")
local CPS = require("CPStyling")
local style = require("modules/ui/style")
local settings = require("modules/utils/settings")
local drag = require("modules/utils/dragHelper")

---Base class for hierchical elements, such as groups and objects
---@class element
---@field name string
---@field parent element
---@field childs table {element}
---@field selectedGroup number
---@field type string
---@field color table {number, number, number}
---@field box table {x = number, y = number}
---@field id number
---@field headerOpen boolean
---@field sUI spawnedUI
---@field beingTargeted boolean
---@field targetable boolean
---@field beingDragged boolean
---@field hovered boolean
element = {}

function element:new(sUI)
	local o = {}

	o.name = "New Element"

	o.parent = nil
    o.childs = {}
	o.expandable = false
	o.selectedGroup = -1

	o.icon = ""

	o.type = "element"
	o.color = {0, 255, 0}
	o.box = {x = 650, y = 142}
	o.id = math.random(1, 1000000000)
	o.headerOpen = settings.headerState

	o.sUI = sUI

	o.beingTargeted = false
    o.targetable = true
	o.beingDragged = false
	o.hovered = false

	self.__index = self
   	return setmetatable(o, self)
end

---Loads the data from a given table, containing the same data as exported during save()
---@param data table {name, type, headerOpen}
---@param silent boolean Set to true to not register the element with the UI
function element:load(data, silent)
	self.name = data.name
	self.headerOpen = data.headerOpen
    self.type = data.type
end

---Update file name to new given
---@param name string
function element:rename(name)
	name = utils.createFileName(name)
    os.rename("data/objects/" .. self.name .. ".json", "data/objects/" .. name .. ".json")
    self.name = name
	self.newName = name
	self.sUI.spawner.baseUI.savedUI.reload()
end

function element:handleDrag()
	local hovered = ImGui.IsItemHovered(ImGuiHoveredFlags.AllowWhenBlockedByActiveItem)

	if hovered and not self.hovered then
		drag.draggableHoveredIn(self)
	elseif not hovered and self.hovered then
		drag.draggableHoveredOut(self)
	end

	self.hovered = hovered
end

---Callback for when this element gets dropped into another one
---@param target element
function element:dropIn(target)
    print("[Element] dropIn behavior not defined for class " .. self.type)
end

---Try to draw as root element
function element:tryMainDraw()
	if self.parent == nil then
		self:draw()
	end
end

---Amount of extra height to be added to 
---@see element.draw
---@return number
function element:getExtraHeight()
	return 0
end

local function getBaseHeight()
	return 6 * ImGui.GetFrameHeight() + 2 * ImGui.GetStyle().FramePadding.y + 7 * ImGui.GetStyle().ItemSpacing.y
end

function element:drawName()
	ImGui.SetNextItemWidth(300)
	self.newName, changed = ImGui.InputTextWithHint('##newname', 'New Name...', self.newName, 100)
	if ImGui.IsItemDeactivatedAfterEdit() then
		self:rename(self.newName)
		self:saveAfterMove()
	end
end

---Main drawing
---@protected
function element:draw()
	ImGui.PushID(tostring(self.name .. self.id))

	if self.parent ~= nil then
		ImGui.Indent(style.elementIndent)
	end

	ImGui.SetNextItemOpen(self.headerOpen)

	if self.beingDragged then ImGui.PushStyleColor(ImGuiCol.Header, style.draggedColor) end
	if self.beingTargeted then ImGui.PushStyleColor(ImGuiCol.Header, style.targetedColor) end

    self.headerOpen = ImGui.CollapsingHeader(n)
	if self.beingDragged or self.beingTargeted then ImGui.PopStyleColor() end
	self:handleDrag()

	if self.headerOpen then
		CPS.colorBegin("Border", self.color)
    	ImGui.BeginChild("group" .. tostring(self.name .. self.id), self.box.x, getBaseHeight() + self:getExtraHeight(), true)

		if self.newName == nil then self.newName = self.name end

		self:drawName()
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
function element:drawMoveGroup()
	local gs = {}
	for _, g in pairs(self.sUI.groups) do
		table.insert(gs, g.name)
	end

	if self.selectedGroup == -1 then
		self.selectedGroup = utils.indexValue(gs, self:getOwnPath(true)) - 1
	end

	ImGui.SetNextItemWidth(300)
	self.selectedGroup = ImGui.Combo("##moveto", self.selectedGroup, gs, #gs)
	ImGui.SameLine()
	if ImGui.Button("Move to group", 150, 0) then
		self:moveToSelectedGroup()
	end
end

function element:setSelectedGroupByPath(path)
    self.sUI.getGroups()

    local i = 0
    for _, group in pairs(self.sUI.groups) do
        if group.name == path then
            self.selectedGroup = i
            break
        end
        i = i + 1
    end
end

function element:moveToSelectedGroup()
	if not self:verifyMove(self.sUI.groups[self.selectedGroup + 1].tab) then
		return
	end

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

function element:remove()
	if self.parent ~= nil then
		utils.removeItem(self.parent.childs, self)
		self.parent:saveAfterMove()
	end
	utils.removeItem(self.sUI.elements, self)
end

function element:verifyMove(to) -- Make sure group doesnt get moved into child
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