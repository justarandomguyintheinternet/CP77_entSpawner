local utils = require("modules/utils/utils")
local settings = require("modules/utils/settings")
local history = require("modules/utils/history")

---Base class for hierchical elements, such as groups and objects
---@class element
---@field name string
---@field newName string
---@field fileName string
---@field parent element
---@field childs element[]
---@field modulePath string
---@field id number
---@field headerOpen boolean
---@field propertyHeaderStates table
---@field sUI spawnedUI
---@field expandable boolean
---@field hideable boolean
---@field visible boolean
---@field hiddenByParent boolean
---@field icon string
---@field class string[]
---@field hovered boolean
---@field editName boolean
---@field focusNameEdit number
---@field quickOperations {[string]: {condition : fun(PARAM: element) : boolean, operation : fun(PARAM: element)}}
---@field groupOperationData table
---@field selected boolean
element = {}

function element:new(sUI)
	local o = {}

	o.name = "New Element"
	o.newName = nil
	o.fileName = ""

	o.parent = nil
    o.childs = {}
	o.visible = true
	o.hiddenByParent = false

	o.expandable = true
	o.hideable = true
	o.quickOperations = {}
	o.groupOperationData = {}

	o.icon = ""

	o.modulePath = "modules/classes/editor/element"
	o.id = math.random(1, 1000000000)

	o.headerOpen = settings.headerState
	o.propertyHeaderStates = {}
	o.selected = false
	o.hovered = false
	o.editName = false
	o.focusNameEdit = 0

	o.sUI = sUI

	o.class = { "element" }

	self.__index = self
   	return setmetatable(o, self)
end

function element:getModulePathByType(data)
	if data.type == "group" then
		return "modules/classes/editor/positionableGroup"
	elseif data.type == "object" then
		return "modules/classes/editor/spawnableElement"
	end
end

---Loads the data from a given table, containing the same data as exported during save()
---@param data {name : string, childs : table, headerOpen : boolean, modulePath : string, visible : boolean, selected : boolean, hiddenByParent : boolean, propertyHeaderStates: table}
---@param silent boolean? Optional parameter to signal that this load is purely for retrieving data
function element:load(data, silent)
	while self.childs[1] do -- Ensure any children get removed, important for undoing spawnables so that they despawn
		self.childs[1]:remove()
	end

	self.fileName = data.name
	self.name = data.name
	self.modulePath = data.modulePath
	self.headerOpen = data.headerOpen
	self.visible = data.visible
	self.selected = data.selected
	self.hiddenByParent = data.hiddenByParent
	self.propertyHeaderStates = data.propertyHeaderStates
	if self.propertyHeaderStates == nil then self.propertyHeaderStates = {} end
	if self.visible == nil then self.visible = true end
	if self.headerOpen == nil then self.headerOpen = settings.headerState end
	if self.selected == nil then self.selected = false end
	if self.hiddenByParent == nil then self.hiddenByParent = false end

	self.modulePath = self.modulePath or self:getModulePathByType(data)

	self.childs = {}
	if data.childs then
		for _, child in pairs(data.childs) do
			child.modulePath = child.modulePath or self:getModulePathByType(child)
			local new = require(child.modulePath):new(self.sUI)
			new:load(child, silent)
			new:setParent(self)
		end
	end
end

---Checks if there is another child which is not entry, with the same name
---@param entry element
---@param childs element[]
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
	new:setHiddenByParent(not self.visible or self.hiddenByParent)
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

	while self.childs[1] do
		self.childs[1]:remove()
	end

	self.parent = nil
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

---Returns the visual root parent of the element
---@return element
function element:getRootParent()
	if self:isRoot(true) then
		return self
	end
	if self.parent.parent == nil then
		return self
	end
	return self.parent:getRootParent()
end

---Base condition ensuring the target is not contained in a source
---@param paths {path : string, ref : element}[]
---@param hasToBeExpandable boolean Whether the element has to be expandable or not
---@return boolean
function element:isValidDropTarget(paths, hasToBeExpandable)
	if not hasToBeExpandable or self.expandable then
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
	-- Draw properties of actual element
	for _, prop in pairs(self:getProperties()) do
		if self.propertyHeaderStates[prop.id] == nil then
			self.propertyHeaderStates[prop.id] = prop.defaultHeader
		end

		ImGui.SetNextItemOpen(self.propertyHeaderStates[prop.id])
		self.propertyHeaderStates[prop.id] = ImGui.TreeNodeEx(prop.name, ImGuiTreeNodeFlags.SpanFullWidth)

		if self.propertyHeaderStates[prop.id] then
			prop.draw()
			ImGui.TreePop()
		end
	end

	-- Collect and reduce any potential grouped properties, store data for group operations
	local groupedProperties = {}

	for _, child in pairs(self:getPathsRecursive(true)) do
		for key, property in pairs(child.ref:getGroupedProperties()) do
			if not groupedProperties[key] then
				groupedProperties[key] = { name = property.name, draw = { [property.id] = property.draw }, entries = {} }
			elseif not groupedProperties[key].draw[property.id] then
				groupedProperties[key].draw[property.id] = property.draw
			end
			table.insert(groupedProperties[key].entries, child.ref)

			if not self.groupOperationData[key] then
				self.groupOperationData[key] = property.data
			end
		end
	end

	-- Draw grouped properties
	if utils.tableLength(groupedProperties) > 0 then
		if self.propertyHeaderStates["groupedProperties"] == nil then
			self.propertyHeaderStates["groupedProperties"] = false
		end

		ImGui.SetNextItemOpen(self.propertyHeaderStates["groupedProperties"])
		self.propertyHeaderStates["groupedProperties"] = ImGui.TreeNodeEx("Group Properties", ImGuiTreeNodeFlags.SpanFullWidth)

		if self.propertyHeaderStates["groupedProperties"] then
			for key, property in pairs(groupedProperties) do
				if self.propertyHeaderStates[key] == nil then
					self.propertyHeaderStates[key] = false
				end

				ImGui.SetNextItemOpen(self.propertyHeaderStates[key])
				self.propertyHeaderStates[key] = ImGui.TreeNodeEx(property.name, ImGuiTreeNodeFlags.SpanFullWidth)

				if self.propertyHeaderStates[key] then
					for _, draw in pairs(property.draw) do
						draw(self, property.entries)
					end
					ImGui.TreePop()
				end
			end
		end
	end
end

function element:getProperties()
	return {}
end

function element:getGroupedProperties()
	return {}
end

function element:drawName()
	if not self.newName then self.newName = self.name end

	ImGui.SetNextItemAllowOverlap()
	self.newName, changed = ImGui.InputTextWithHint('##newname', 'New Name...', self.newName, 100)
	if ImGui.IsItemDeactivated() then
		self.editName = false
		if self.newName == "" then self.newName = self.name return end
		if self.newName == self.name then return end
		self:rename(self.newName)
	end
end

---Recursive function to get all elements, including root
---@param isRoot boolean? If true, self does not get added to the list
---@return {path : string, ref : element}[]
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
	self.hiddenByParent = state

	if not self.visible then return end

	for _, child in pairs(self.childs) do
		child:setHiddenByParent(state)
	end
end

function element:setSilent(state)
	self.silent = state

	for _, child in pairs(self.childs) do
		child:setSilent(state)
	end
end

function element:expandAllParents()
	if self.parent ~= nil then
		self.parent.headerOpen = true
		self.parent:expandAllParents()
	end
end

function element:setHovered(state)
	self.hovered = state
end

function element:setSelected(state)
	self.selected = state
end

function element:getPath()
	if not self.parent then return "" end
	if self.parent.parent == nil then return "/" .. self.name end

	return self.parent:getPath() .. "/" .. self.name
end

function element:serialize()
	local data = {
		name = self.name,
		modulePath = self.modulePath,
		headerOpen = self.headerOpen,
		propertyHeaderStates = self.propertyHeaderStates,
		visible = self.visible,
		hiddenByParent = self.hiddenByParent,
		expandable = self.expandable,
		selected = self.selected,
		isUsingSpawnables = true,
		childs = {}
	}

	for _, child in pairs(self.childs) do
		table.insert(data.childs, child:serialize())
	end

	return data
end

function element:save()
	local data = self:serialize()

	if self.fileName ~= self.name then
		self.fileName = self.name
	end

	config.saveFile("data/objects/" .. self.fileName .. ".json", data)
	self.sUI.spawner.baseUI.savedUI.reload()
end

return element