local config = require("modules/utils/config")
local utils = require("modules/utils/utils")
local CPS = require("CPStyling")
local style = require("modules/ui/style")
local settings = require("modules/utils/settings")
local drag = require("modules/utils/dragHelper")

---Base class for hierchical elements, such as groups and objects
---@class element
---@field name string
---@field parent element
---@field childs element[]
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
---@field newName string?
---@field width number
---@field isNode boolean Determines if this element can contain other elements
local element = {}

function element:new(sUI)
	local o = {}

	o.name = "New Element"
	o.newName = nil

	o.parent = nil
	o.isNode = true
    o.childs = {}
	o.selectedGroup = -1

	o.type = "element"
	o.color = {0, 255, 0}
	o.width = 650
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

	for _, child in pairs(data.childs) do
		if child.type == "group" then
			local group = require("modules/classes/spawn/group"):new(self.sUI)
			group.parent = self
			group:load(c)
			self:addElement(group)

			if not silent then
				table.insert(self.sUI.elements, g)
			end
		else
			local object = require("modules/classes/spawn/object"):new(self.sUI)
			object:load(c)
			object.parent = self
			self:addElement(object)

			if not silent then
				table.insert(self.sUI.elements, o)
			end
		end
	end
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

function element:drawContents()

end

---Main drawing
---@protected
---@param root boolean Identifies if this is supposed to be drawn as root element or child element
function element:draw(root)
	if root and self.parent ~= nil then return end

	ImGui.PushID(tostring(self.name .. self.id))
	ImGui.SetNextItemOpen(self.headerOpen)

	if self.beingDragged then ImGui.PushStyleColor(ImGuiCol.Header, style.draggedColor) end
	if self.beingTargeted then ImGui.PushStyleColor(ImGuiCol.Header, style.targetedColor) end

    self.headerOpen = ImGui.CollapsingHeader(n)
	if self.beingDragged or self.beingTargeted then ImGui.PopStyleColor() end
	self:handleDrag()

	if self.headerOpen then
		CPS.colorBegin("Border", self.color)
		CPS.colorBegin("Separator", self.color)
    	ImGui.BeginChild("group" .. tostring(self.name .. self.id), self.box.x, getBaseHeight() + self:getExtraHeight(), true)

		if self.newName == nil then self.newName = self.name end

		self:drawName()
		self:drawMoveGroup()
		self:drawContents()

		ImGui.EndChild()
    	CPS.colorEnd(2)

		ImGui.Indent(style.elementIndent)
        for _, c in pairs(self.childs) do
			c:draw(false)
		end
		ImGui.Unindent(style.elementIndent)
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

---Adds the given element to the child list, ensuring unique names
---@param e element
function element:addElement(e)
	for _, child in pairs(self.childs) do
		if child.name == e.name then
			e.name = utils.generateCopyName(e.name)
		end
	end

	table.insert(self.childs, e)
end

function element:remove()
	if self.parent ~= nil then
		utils.removeItem(self.parent.childs, self)
		self.parent:saveAfterMove()
	end
	utils.removeItem(self.sUI.elements, self)
end

-- what do we need
	-- All node paths
	-- All node paths above each node

function element:verifyMove(to) -- Make sure group doesnt get moved into child
	local allowed = true

	local childs = self:getChildNodes()
	for _, c in pairs(childs) do
		if c.tab == to then
			allowed = false
		end
	end

	local isParent = to == self.parent

	return { isNotChild = allowed and not isParent, isParent = isParent }
end

---Recursively gets all the child elements that are nodes, with their path
---@return table {path = string, tab = element}
function element:getChildNodes()
	local paths = {}
	table.insert(paths, {path = self.name, tab = self})

	for _, child in pairs(self.childs) do
		if child.isNode then
			local cPaths = child:getPaths()
			for _, path in pairs(cPaths) do
				table.insert(paths, {path = self.name .. "/" .. path.name, tab = path.tab})
			end
		end
	end

	return paths
end

function element:save()
	if self.parent == nil then
		config.saveFile("data/objects/" .. self.name .. ".json", self:toTable())
		self.sUI.spawner.baseUI.savedUI.reload()
	else
		return self:toTable()
	end
end

function element:toTable()
	local data = {
		isUsingSpawnables = true,
		name = self.name,
		childs = {},
		type = self.type,
		headerOpen = self.headerOpen
	}

	for _, child in pairs(self.childs) do
		table.insert(data.childs, child:save())
	end

	return data
end

function element:saveAfterMove()
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

function element:getOwnPath(calledRecursively)
    if self.parent == nil then
		if #self.childs == 0 and not calledRecursively then
			return "-- No group --"
		else
			return self.name
		end
	end

	if not self.isNode then
		return self.parent:getOwnPath(true)
	else
		return self.parent:getOwnPath(true) .. "/" .. self.name
	end
end

function element:getWidth()
	if self.headerOpen then
		local width = (self.parent == nil) and self.width or style.elementIndent

		for _, child in pairs(self.childs) do
			width = math.max(width, child:getWidth() + width)
		end

		return width
	end
	return 0
end

return element