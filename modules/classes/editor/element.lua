local utils = require("modules/utils/utils")
local settings = require("modules/utils/settings")
local history = require("modules/utils/history")

---Base class for hierchical elements, such as groups and objects
---@class element
---@field name string
---@field newName string
---@field parent element
---@field childs table {element}
---@field modulePath string
---@field id number
---@field headerOpen boolean
---@field sUI spawnedUI
---@field expandable boolean
---@field hideable boolean
---@field selected boolean
element = {}

function element:new(sUI)
	local o = {}

	o.name = "New Element"
	o.newName = nil

	o.parent = nil
    o.childs = {}
	o.visible = true
	o.hiddenByParent = false

	o.expandable = true
	o.hideable = true

	o.icon = ""

	o.modulePath = "modules/classes/editor/element"
	o.id = math.random(1, 1000000000)

	o.headerOpen = settings.headerState
	o.selected = false
	o.hovered = false
	o.editName = false
	o.focusNameEdit = 0

	o.sUI = sUI

	self.__index = self
   	return setmetatable(o, self)
end

function element:getModulePathByType(data)
	if data.type == "group" then
		return "modules/classes/editor/group"
	elseif data.type == "object" then
		return "modules/classes/editor/object"
	end
end

---Loads the data from a given table, containing the same data as exported during save()
---@param data table {name, childs, headerOpen, modulePath, visible}
function element:load(data)
	self.name = data.name
	self.headerOpen = data.headerOpen
	self.modulePath = data.modulePath
	self.visible = data.visible == nil and true or data.visible
	self.selected = data.selected == nil and false or data.selected
	self.hiddenByParent = data.hiddenByParent == nil and false or data.hiddenByParent

	self.modulePath = self.modulePath or self:getModulePathByType(data)

	self.childs = {}
	if data.childs then
		for _, child in pairs(data.childs) do
			child.modulePath = child.modulePath or child:getModulePathByType(data)

			local new = require(child.modulePath):new(self.sUI)
			new:load(child)
			new:setParent(self)
		end
	end
end

---Checks if there is another child which is not entry, with the same name
---@param entry element
---@param childs table {element}
---@return boolean
local function hasChildWithSameName(entry, childs)
	for _, child in pairs(childs) do
		if child.name == entry.name and not (child == entry) then
			return true
		end
	end

	return false
end

local function generateUniqueName(entry, childs)
	while hasChildWithSameName(entry, childs) do
		entry.name = utils.generateCopyName(entry.name)
	end
end

---Update file name to new given
---@param name string
function element:rename(name)
	local oldPath = self:getPath()
	local oldState = self:serialize()

	self.name = utils.createFileName(name)
	generateUniqueName(self, self.parent.childs)
	self.newName = self.name

	history.addAction(history.getRename(oldState, oldPath, self:getPath()))
end

---@param new element
---@param index number?
function element:addChild(new, index)
	index = index or #self.childs + 1

	generateUniqueName(new, self.childs)
	table.insert(self.childs, index, new)
end

function element:removeChild(child)
	utils.removeItem(self.childs, child)
end

---Sets the parent, removes it from previous parent and adds self to new one
---@param parent element
---@param index number?
function element:setParent(parent, index)
	if self.parent then
		self.parent:removeChild(self)
	end

	self.parent = parent
	parent:addChild(self, index)
end

---Removes self from parent
function element:remove()
	if self.parent ~= nil then
		self.parent:removeChild(self)
	end
end

---Checks if the element is a visual root, or true root of hierarchy
---@param realRoot boolean
---@return boolean
function element:isRoot(realRoot)
	if realRoot then
		return self.parent == nil
	end
	return self.parent:isRoot(true)
end

---Base condition ensuring the target is not contained in a source
---@param paths table {path = string, ref = element}
---@return boolean
function element:isValidDropTarget(paths)
	if self.expandable then
		local ownPath = self:getPath()

		for _, path in pairs(paths) do
			if ownPath:match("^" .. path.path .. "/") then
				return false
			end
		end
		return true
	end
	return false
end

---Check if self or any parent is selected. If parent of an element returns false for this, the element is the first selected element
---@return boolean
function element:isParentOrSelfSelected()
	if self.selected then return true end

	if self.parent and not self.parent:isRoot(true) then
		return self.parent:isParentOrSelfSelected()
	end

	return false
end

function element:drawProperties()
	ImGui.Text(tostring(self.hiddenByParent))
end

function element:drawName()
	if not self.newName then self.newName = self.name end

	self.newName, changed = ImGui.InputTextWithHint('##newname', 'New Name...', self.newName, 100)
	if ImGui.IsItemDeactivated() then
		self.editName = false
		if self.newName == "" then self.newName = self.name return end
		self:rename(self.newName)
	end
end

---Recursive function to get all elements, including root
---@param isRoot boolean? If true, self does not get added to the list
---@return table {path = string, ref = element}
function element:getPathsRecursive(isRoot)
	local paths = {}

	if not isRoot then
		table.insert(paths, {path = self:getPath(), ref = self})
	end

	for _, child in pairs(self.childs) do
		for _, path in pairs(child:getPathsRecursive()) do
			table.insert(paths, path)
		end
	end

	return paths
end

function element:setHeaderStateRecursive(state)
	self.headerOpen = state

	for _, child in pairs(self.childs) do
		child:setHeaderStateRecursive(state)
	end
end

---Sets visibility of self and all children
---@param state boolean
---@param fromRecursive boolean? Indicates that this is not the first call, and should not be added to history
function element:setVisibleRecursive(state, fromRecursive)
	self:setVisible(state, fromRecursive)

	for _, child in pairs(self.childs) do
		child:setVisibleRecursive(state, true)
	end
end

function element:setVisible(state, fromRecursive)
	if not fromRecursive then
		history.addAction(history.getElementChange(self))
	end
	self.visible = state

	if self.hiddenByParent then return end

	for _, child in pairs(self.childs) do
		child:setHiddenByParent(not state)
	end
end

function element:setHiddenByParent(state)
	if self.hiddenByParent or not self.visible then return end

	self.hiddenByParent = state

	for _, child in pairs(self.childs) do
		child:setHiddenByParent(state)
	end
end

function element:expandAllParents()
	if self.parent ~= nil then
		self.parent.headerOpen = true
		self.parent:expandAllParents()
	end
end

function element:getPath()
	if not self.parent then return "" end
	if self.parent.parent == nil then return "/" .. self.name end

	return self.parent:getPath() .. "/" .. self.name
end

function element:save()

end

function element:serialize()
	local data = {
		name = self.name,
		modulePath = self.modulePath,
		headerOpen = self.headerOpen,
		visible = self.visible,
		hiddenByParent = self.hiddenByParent,
		expandable = self.expandable,
		selected = self.selected,
		childs = {}
	}

	for _, child in pairs(self.childs) do
		table.insert(data.childs, child:serialize())
	end

	return data
end

return element