local utils = require("modules/utils/core/utils")
local history = require("modules/utils/project/history")
local backup = require("modules/utils/project/backup")
local logger = require("modules/utils/core/logger")
local saveState = require("modules/utils/project/saveState")
local projectFiles = require("modules/utils/project/projectFiles")
local projectLinkPopup = require("modules/utils/ui/projectLinkPopup")
local style = require("modules/ui/style")
local settings = require("modules/utils/core/settings")

-- Depth of `element:load` calls in progress; children attached while loading keep their stored names.
local loadDepth = 0

---Base class for hierchical elements, such as groups and objects
---@class element
---@field name string Free-form display name. Unique among siblings, but not tied to any file.
---@field newName string
---@field projectUID string? For a root group bound to a saved project: its file name in
---`data/objects/`, which is that project's unique id. Mirrored from `saveState`, never serialized.
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
---@field locked boolean
---@field lockedByParent boolean
---@field exportDisabled boolean Excluded from export; descendants inherit this exclusion without changing their own state.
---@field icon string
---@field secondaryIcon string
---@field class string[]
---@field hovered boolean
---@field editName boolean
---@field focusNameEdit number
---@field quickOperations {[string]: {condition : fun(PARAM: element) : boolean, operation : fun(PARAM: element), tooltip : string?, allowWhenLocked : boolean?, disableWhenEmpty : boolean?}}
---@field groupOperationData table
---@field selected boolean
---@field lockedRename boolean
---@field lockedRemove boolean
---@field __jsonCache table? Cached canonical JSON for this node, owned by `saveState`. Never serialized.
element = {}

---Options threaded through `serialize` by the incremental persistence walk.
---@class serializeContext
---@field shallow boolean? Omit `childs`/`elementCount`; the caller emits them itself.
---@field copyVolatile boolean? Deep-copy UI-state tables normally shared by reference.

---Invalidates the cached viewport wireframes owned by the element's spawned UI, when it has one.
---@param instance element? Element whose `sUI` should refresh its wireframe cache.
function element.bumpWireframeEpoch(instance)
	if instance and instance.sUI and instance.sUI.bumpWireframeEpoch then
		instance.sUI.bumpWireframeEpoch()
	end
end

---@param instance element
---@param registryAffected boolean?
local function invalidateSUI(instance, registryAffected)
	if instance and instance.sUI and instance.sUI.invalidateCache then
		instance.sUI.invalidateCache(registryAffected)
	end
end

local function invalidateAutoCenter(instance)
	local current = instance

	while current do
		if current.invalidateAutoCenterCache then
			current:invalidateAutoCenterCache(true)
			return
		end

		current = current.parent
	end
end

function element:new(sUI)
	local o = {}

	o.name = "New Element"
	o.newName = nil
	-- Only ever set by saveState, on root groups that own a project file.
	o.projectUID = nil

	o.parent = nil
    o.childs = {}
	o.visible = true
	o.hiddenByParent = false
	o.locked = false
	o.lockedByParent = false
	o.exportDisabled = false

	o.expandable = true
	o.hideable = true
	o.quickOperations = {}
	o.groupOperationData = {}

	o.icon = ""
	o.secondaryIcon = ""

	o.modulePath = "modules/classes/editor/element"
	o.id = math.random(1, 1000000000)

	o.headerOpen = true
	o.propertyHeaderStates = {}
	o.selected = false
	o.hovered = false
	o.editName = false
	o.focusNameEdit = 0

	o.lockedRemove = false
	o.lockedRename = false

	o.sUI = sUI

	o.class = { "element" }

	self.__index = self
   	return setmetatable(o, self)
end

---Capture which descendants are currently selected, keyed by their path relative to `instance`.
---Used to carry live selection across a `load` that tears down and rebuilds the subtree.
---@param instance element
---@return table<string, boolean>? selection nil when nothing in the subtree is selected
local function captureSubtreeSelection(instance)
	local selection = nil

	local function walk(node, prefix)
		for _, child in pairs(node.childs) do
			local path = prefix .. "/" .. tostring(child.name)

			if child.selected then
				selection = selection or {}
				selection[path] = true
			end

			walk(child, path)
		end
	end

	walk(instance, "")

	return selection
end

---Re-apply a snapshot taken by `captureSubtreeSelection` to a rebuilt subtree. Descendants that no
---longer sit at the same relative path are simply dropped from the selection.
---@param instance element
---@param selection table<string, boolean>?
local function restoreSubtreeSelection(instance, selection)
	if not selection then return end

	local function walk(node, prefix)
		for _, child in pairs(node.childs) do
			local path = prefix .. "/" .. tostring(child.name)

			-- Raw flag rather than `setSelected`: subclasses react to selection by touching their
			-- spawnable, which does not exist yet this far into a load. `spawnableElement` re-applies
			-- the visual state from this flag once its entity is attached.
			if selection[path] and not child:isLocked() then
				child.selected = true
			end

			walk(child, path)
		end
	end

	walk(instance, "")
end

function element:getModulePathByType(data)
	if data.type == "group" then
		return "modules/classes/editor/positionableGroup"
	elseif data.type == "object" then
		return "modules/classes/editor/spawnableElement"
	end
end

---Loads the data from a given table, containing the same data as exported during save()
---@param data {name : string, childs : table, headerOpen : boolean, modulePath : string, visible : boolean, hiddenByParent : boolean, locked : boolean, lockedByParent : boolean, exportDisabled : boolean, propertyHeaderStates: table}
---@param silent boolean? Optional parameter to signal that this load is purely for retrieving data
function element:load(data, silent)
	-- Selection is live editor state, never read from `data`. It still has to survive the rebuild
	-- below, because `load` also re-applies to elements already in the tree (undo/redo, clipboard
	-- paste) and dropping the user's selection there is pure data loss.
	local wasSelected = self.selected
	local subtreeSelection = captureSubtreeSelection(self)

	while self.childs[1] do -- Ensure any children get removed, important for undoing spawnables so that they despawn
		self.childs[1]:remove()
	end

	-- Only the name: what file this came from is the caller's business (a load from `data/objects/`
	-- binds the uID through saveState), and a clipboard paste must not inherit one at all.
	self.name = data.name
	self.newName = self.name
	self.modulePath = data.modulePath
	self.headerOpen = data.headerOpen
	self.visible = data.visible
	self.hiddenByParent = data.hiddenByParent
	self.locked = data.locked
	self.lockedByParent = data.lockedByParent
	self.exportDisabled = data.exportDisabled
	self.propertyHeaderStates = data.propertyHeaderStates
	if self.propertyHeaderStates == nil then self.propertyHeaderStates = {} end
	if self.visible == nil then self.visible = true end
	if self.headerOpen == nil then self.headerOpen = true end
	if self.hiddenByParent == nil then self.hiddenByParent = false end
	if self.locked == nil then self.locked = false end
	if self.lockedByParent == nil then self.lockedByParent = false end
	if self.exportDisabled == nil then self.exportDisabled = false end

	-- Never taken from `data`: old files still contain the field, it is ignored rather than migrated.
	-- A fresh element carries `false` in from `new`, so a load from disk still starts unselected.
	-- The lock check mirrors `setSelected`: data that locks the element also drops the selection.
	self.selected = wasSelected and not self:isLocked()

	self.modulePath = self.modulePath or self:getModulePathByType(data)

	self.childs = {}
	if data.childs then
		loadDepth = loadDepth + 1
		local ok, err = pcall(function ()
			for _, child in pairs(data.childs) do
				local modulePath = child.modulePath or self:getModulePathByType(child)
				local new = require(modulePath):new(self.sUI)
				new:load(child, silent)
				new:setParent(self)
			end
		end)
		loadDepth = loadDepth - 1
		if not ok then error(err, 0) end
	end

	restoreSubtreeSelection(self, subtreeSelection)

	-- Covers undo/redo swaps and clipboard pastes, which replace an element's whole state in place.
	-- A no-op while loading from disk, where suppression is held and the tree matches the file.
	saveState.markDirty(self)
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

---Cleans up a display name.
---
---Names are free-form, like prefab categories and project tags: spaces, apostrophes and punctuation
---all survive. The one exception is the path separator, because `getPath` joins names with `/` and
---the whole selection/history layer addresses elements by that path -- a name containing one would
---split into segments that match nothing.
---@param name string
---@return string
function element.sanitizeDisplayName(name)
	local cleaned = tostring(name or ""):gsub("[/\\]", "_")
	cleaned = cleaned:match("^%s*(.-)%s*$")

	return element.applyNameStyle(cleaned)
end

---Applies the `underscoreNames` setting to a name.
---@param name string
---@return string
function element.applyNameStyle(name)
	if not settings.underscoreNames then return name end

	return (tostring(name or ""):gsub(" ", "_"))
end

---Whether an element attached now counts as newly added, as opposed to loaded, restored or replayed.
---@return boolean
local function shouldStyleNewNames()
	return settings.underscoreNames
		and loadDepth == 0
		and not saveState.isSuppressed()
		and not history.isReplaying()
end

local function styleChildNames(entry)
	for _, child in ipairs(entry.childs) do
		if not child.lockedRename then
			local styled = element.applyNameStyle(child.name)
			if styled ~= child.name then
				child.name = styled
				generateUniqueName(child, entry.childs)
				child.newName = child.name
			end
		end

		styleChildNames(child)
	end
end

---Applies the `underscoreNames` setting to a newly added element and its whole subtree, keeping
---sibling names unique. Structural elements (`lockedRename`) keep their names.
---@param entry element
function element.styleNewNames(entry)
	if not settings.underscoreNames then return end

	if not entry.lockedRename then
		entry.name = element.applyNameStyle(entry.name)
		if entry.parent then
			generateUniqueName(entry, entry.parent.childs)
		end
		entry.newName = entry.name
	end

	styleChildNames(entry)
end

---The name this element would end up with if renamed to `name`: sanitized, and suffixed until no
---sibling holds it. Answering that without renaming is what a caller applying a name as part of a
---larger change needs, since it writes the name itself instead of going through `rename`.
---@param name string
---@return string cleaned Empty when the name cannot be used at all.
function element:resolveSiblingName(name)
	local cleaned = element.sanitizeDisplayName(name)
	if cleaned == "" or cleaned == self.name then return cleaned end

	-- Deduplicated through a stand-in rather than self, so nothing is written until the caller says
	-- so. It is not among the children either, which is what makes a sibling holding `cleaned` count.
	local candidate = { name = cleaned }
	generateUniqueName(candidate, self.parent and self.parent.childs or {})

	return candidate.name
end

---Whether the display name of this element may be changed.
---@return boolean
function element:canRename()
	return not self.lockedRename and not self:isLocked()
end

---Begin editing the display name, seeding the input from the current displayed row name.
---@param focusFrames number?
---@return boolean
function element:beginNameEdit(focusFrames)
	if not self:canRename() then return false end

	self.newName = self.name
	self.editName = true
	self.focusNameEdit = focusFrames or 1

	return true
end

---Update the display name to the given one. Does not affect which file the element saves to.
---@param name string
function element:rename(name)
	if not self:canRename() then return end

	local cleaned = self:resolveSiblingName(name)
	if cleaned == "" then return end

	local oldPath = self:getPath()
	local oldState = self:serialize()

	self.name = cleaned
	self.newName = self.name

	history.addAction(history.getRename(oldState, oldPath, self:getPath(), self.id))
	saveState.markDirty(self)
	invalidateSUI(self, true)
end

---@param new element
---@param index number?
function element:addChild(new, index)
	index = index or #self.childs + 1

	generateUniqueName(new, self.childs)
	table.insert(self.childs, index, new)
	new:setHiddenByParent(not self.visible or self.hiddenByParent)
	new:setLockedByParent(self.locked or self.lockedByParent)
	saveState.markDirty(self)
	invalidateSUI(self, true)
	invalidateAutoCenter(self)
end

function element:removeChild(child)
	utils.removeItem(self.childs, child)
	saveState.markDirty(self)
	invalidateSUI(self, true)
	invalidateAutoCenter(self)
end

---Sets the parent, removes it from previous parent and adds self to new one
---@param parent element
---@param index number?
function element:setParent(parent, index)
	if self.lockedRemove then return end
	local isNew = self.parent == nil
	if self.parent then
		self.parent:removeChild(self)
	end

	self.parent = parent
	if isNew and shouldStyleNewNames() then
		element.styleNewNames(self)
	end
	parent:addChild(self, index)
	invalidateSUI(self, true)
end

---Removes self from parent
function element:remove()
	if self.lockedRemove then return end
	if self.parent ~= nil then
		self.parent:removeChild(self)
	end

	while self.childs[1] do
		self.childs[1]:remove()
	end

	self.parent = nil
	invalidateSUI(self, true)
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

---Checks if the element sits directly under the real root, i.e. is one of the top-level entries of
---the Spawned tab. Unlike `isRoot(false)` this is safe to call on the real root itself.
---@return boolean
function element:isRootChild()
	return self.parent ~= nil and self.parent:isRoot(true)
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

---Whether the element would still be a root child after being moved under `newParent`.
---
---A project's identity is its file, and only a direct child of the real root is a project. Letting a
---linked group become someone's child would leave a file that nothing owns and a subtree that
---auto-save writes as part of a different project, so it is refused rather than silently unlinked.
---@param newParent element? Prospective parent.
---@return boolean
function element:wouldUnlinkFromProject(newParent)
	if self.projectUID == nil then return false end
	if newParent == nil then return false end

	return not newParent:isRoot(true)
end

---Base condition ensuring the target is not contained in a source
---@param paths {path : string, ref : element}[]
---@param hasToBeExpandable boolean Whether the element has to be expandable or not, i.e. whether the
---sources would be dropped *into* this element rather than reordered next to it.
---@return boolean
function element:isValidDropTarget(paths, hasToBeExpandable)
	if not hasToBeExpandable or self.expandable then
		local ownPath = self:getPath()
		-- Dropping onto an element nests into it; reordering puts the sources beside it instead.
		local prospectiveParent = hasToBeExpandable and self or self.parent

		for _, path in pairs(paths) do
			-- Escaped: names are free-form, so a group called "Zone (2)" or "50% cover" would
			-- otherwise be read as a pattern and match the wrong subtree, or nothing at all.
			if ownPath:match("^" .. utils.escapePattern(path.path) .. "/") then
				return false
			end

			if path.ref and path.ref:wouldUnlinkFromProject(prospectiveParent) then
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

	if self.parent and not self:isRootChild() then
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
		if prop.drawHeader then
			prop.drawHeader()
		end

		if self.propertyHeaderStates[prop.id] then
			prop.draw()
			ImGui.TreePop()
		end
	end

	-- Collect and reduce any potential grouped properties, store data for group operations
	local epoch = self.sUI and self.sUI.cacheEpoch or 0
	local groupedProperties = nil
	if self.groupedPropertiesCache and self.groupedPropertiesCache.epoch == epoch then
		groupedProperties = self.groupedPropertiesCache.data
	else
		groupedProperties = {}

		for key, property in pairs(self:getExtraGroupedProperties()) do
			if not groupedProperties[key] then
				groupedProperties[key] = {
					name = property.name,
					draw = { [property.id] = property.draw },
					entries = property.entries or {}
				}
			elseif not groupedProperties[key].draw[property.id] then
				groupedProperties[key].draw[property.id] = property.draw
			end

			if not self.groupOperationData[key] then
				self.groupOperationData[key] = property.data
			end
		end

		for _, child in ipairs(self:getPathsRecursive(true)) do
			if not child.ref:isLocked() then
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
		end

		self.groupedPropertiesCache = {
			epoch = epoch,
			data = groupedProperties
		}
	end

	if utils.tableLength(groupedProperties) > 0 then
		if self.propertyHeaderStates["groupedProperties"] == nil then
			self.propertyHeaderStates["groupedProperties"] = false
		end

		ImGui.SetNextItemOpen(self.propertyHeaderStates["groupedProperties"])
		self.propertyHeaderStates["groupedProperties"] = ImGui.TreeNodeEx("Group Properties", ImGuiTreeNodeFlags.SpanFullWidth)

		if self.propertyHeaderStates["groupedProperties"] then
			local function drawGroupedProperty(key, property)
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

			for key, property in pairs(groupedProperties) do
				drawGroupedProperty(key, property)
			end

			ImGui.TreePop()
		end
	end
end

function element:getProperties()
	return {}
end

function element:getGroupedProperties()
	return {}
end

function element:getExtraGroupedProperties()
	return {}
end

function element:drawName()
	if self:isLocked() then
		self.editName = false
		return
	end

	if not self.newName then self.newName = self.name end

	ImGui.SetNextItemAllowOverlap()
	self.newName, changed = style.inputTextWithHint('##newname', 'New Name...', self.newName, 100)
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

	for _, child in ipairs(self.childs) do
		for _, path in ipairs(child:getPathsRecursive()) do
			table.insert(paths, path)
		end
	end

	return paths
end

---Returns all descendants of self (excluding self).
---@return element[]
function element:getDescendants()
	local descendants = {}

	for _, child in pairs(self.childs) do
		table.insert(descendants, child)
		for _, descendant in pairs(child:getDescendants()) do
			table.insert(descendants, descendant)
		end
	end

	return descendants
end

---Sets the locked state of all descendants of self (excluding self).
---@param state boolean
---@param fromRecursive boolean? Indicates this call is part of a batched/multi operation.
function element:setDescendantsLocked(state, fromRecursive)
	for _, descendant in pairs(self:getDescendants()) do
		descendant:setLocked(state, fromRecursive)
	end
end

---Sets the visibility of all descendants of self (excluding self).
---@param state boolean
---@param fromRecursive boolean? Indicates this call is part of a batched/multi operation.
function element:setDescendantsVisible(state, fromRecursive)
	for _, descendant in pairs(self:getDescendants()) do
		descendant:setVisible(state, fromRecursive)
	end
end

function element:setHeaderStateRecursive(state, fromRecursive)
	self.headerOpen = state

	for _, child in pairs(self.childs) do
		child:setHeaderStateRecursive(state, true)
	end

	if not fromRecursive then
		invalidateSUI(self, false)
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
	-- Not gated on fromRecursive: setVisibleRecursive changes `visible` on every descendant, and each
	-- of those is real content. The ancestor walk early-exits, so marking a whole subtree stays cheap.
	saveState.markDirty(self)
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

---Sets lock state of self and all children
---@param state boolean
---@param fromRecursive boolean? Indicates that this is not the first call, and should not be added to history
function element:setLockedRecursive(state, fromRecursive)
	self:setLocked(state, fromRecursive)

	for _, child in pairs(self.childs) do
		child:setLockedRecursive(state, true)
	end
end

function element:setLocked(state, fromRecursive)
	if not fromRecursive then
		history.addAction(history.getElementChange(self))
	end
	-- See setVisible: setLockedRecursive changes `locked` on every descendant.
	saveState.markDirty(self)
	self.locked = state
	if state then
		self:setSelected(false)
		self.editName = false
	end

	if self.lockedByParent then return end

	for _, child in pairs(self.childs) do
		child:setLockedByParent(state)
	end

	invalidateSUI(self, false)
	invalidateAutoCenter(self)
end

function element:setLockedByParent(state)
	self.lockedByParent = state
	if state then
		self:setSelected(false)
		self.editName = false
	end

	if self.locked then return end

	for _, child in pairs(self.childs) do
		child:setLockedByParent(state)
	end

	invalidateSUI(self, false)
end

---Sets whether this element is excluded from export. Parent exclusion is resolved by the exporter,
---so a group never overwrites its descendants' own state.
---@param state boolean
function element:setExportDisabled(state)
	if self.exportDisabled == state then return end

	history.addAction(history.getElementChange(self))
	saveState.markDirty(self)
	self.exportDisabled = state
	invalidateSUI(self, false)
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
		invalidateSUI(self, false)
	end
end

function element:setHovered(state)
	self.hovered = state
end

function element:setSelected(state)
	if state and self:isLocked() then return end
	if self.selected == state then return end
	self.selected = state
	invalidateSUI(self, false)
end

---@return boolean
function element:isLocked()
	return self.locked or self.lockedByParent
end

function element:getPath()
	if not self.parent then return "" end
	if self.parent.parent == nil then return "/" .. self.name end

	return self.parent:getPath() .. "/" .. self.name
end

---Serializes this element and, unless told otherwise, its whole subtree.
---@param ctx serializeContext? Optional context used by the incremental persistence walk.
---When omitted (all pre-existing callers) behaviour is unchanged.
function element:serialize(ctx)
	local propertyHeaderStates = self.propertyHeaderStates
	if ctx and ctx.copyVolatile then
		-- Normally handed out by reference, and drawProperties writes into it every frame the
		-- inspector is open. The persistence walk needs a stable snapshot, so it asks for a copy.
		propertyHeaderStates = utils.deepcopy(propertyHeaderStates)
	end

	local data = {
		name = self.name,
		modulePath = self.modulePath,
		headerOpen = self.headerOpen,
		propertyHeaderStates = propertyHeaderStates,
		visible = self.visible,
		hiddenByParent = self.hiddenByParent,
		locked = self.locked,
		lockedByParent = self.lockedByParent,
		exportDisabled = self.exportDisabled,
		expandable = self.expandable,
		isUsingSpawnables = true,
		childs = {}
	}

	if ctx and ctx.shallow then
		-- The persistence walk emits childs/elementCount itself, so it can splice in cached output
		-- for subtrees that have not changed.
		data.childs = nil
		return data
	end

	local elementCount = 0

	for _, child in pairs(self.childs) do
		local childData = child:serialize(ctx)
		table.insert(data.childs, childData)

		if utils.isSerializedSpawnableStrict(childData) then
			elementCount = elementCount + 1
		elseif utils.isSerializedGroupStrict(childData) then
			elementCount = elementCount + (childData.elementCount or 0)
		end
	end

	if utils.isSerializedGroupStrict(data) then
		data.elementCount = elementCount
	end

	return data
end

---Reports a failed save to the user.
---
---`ImGui.ToastType.Error` is not present in every CET build, so it is probed rather than assumed --
---and the probe has to come before the table is indexed, or the fallback itself throws.
---@param message string
local function showSaveErrorToast(message)
	local toastType = 0
	if ImGui.ToastType then
		toastType = ImGui.ToastType.Error or ImGui.ToastType.Success or 0
	end

	ImGui.ShowToast(ImGui.Toast.new(toastType, 5000, message))
end

---@param showToast boolean?
---@param opts {autoResolveName : boolean?}? `autoResolveName` makes a first save that collides with
---an existing project file pick the next free name instead of asking. For batch callers (the AMM
---import) that have no user in front of them.
function element:save(showToast, opts)
	showToast = showToast ~= false
	local updatedInExport = 0

	local data
	local serializeOk, serializeErr = pcall(function ()
		data = self:serialize()
	end)
	if not serializeOk or type(data) ~= "table" then
		local errMsg = string.format("Failed to serialize \"%s\": %s", tostring(self.name), tostring(serializeErr))
		logger:error("[Element] " .. errMsg)

		if showToast then
			showSaveErrorToast(errMsg)
		end

		return nil
	end

	data.lastEditedAt = os.date("%Y-%m-%d %H:%M:%S")

	-- The name on screen only ever decides the *first* file name; after that the uID is the target,
	-- so renaming a group cannot orphan its project or overwrite someone else's.
	local fileName, suggestion, takenBy = projectFiles.resolveSaveTarget(self.projectUID, self.name)
	if not fileName then
		if not (opts and opts.autoResolveName) then
			-- The popup only takes root groups. Anything else that lands here has nowhere to go, so
			-- say so rather than failing silently.
			if not projectLinkPopup.requestConflict(self, suggestion, takenBy) and showToast then
				showSaveErrorToast(string.format("\"%s\" already exists, and \"%s\" cannot be linked to a project file",
					tostring(takenBy), tostring(self.name)))
			end

			return nil
		end

		fileName = suggestion
		logger:info(string.format("[Element] \"%s\" was saved as \"%s\"; \"%s\" was already taken",
			tostring(self.name), tostring(fileName), tostring(takenBy)))
	end

	local targetPath = projectFiles.getPath(fileName)
	local hadBackup = backup.backupObjectBeforeSave(fileName)
	-- data.lastEditedAt is refreshed above on every save, so the canonical-content comparison in
	-- config.saveFile can never match. Skipping it avoids a pointless read + decode + re-encode of
	-- the existing file (multi-second on large groups) before a write that always happens anyway.
	local saved, saveErr = config.saveFile(targetPath, data, { skipExistingComparison = true })
	if not saved then
		if hadBackup then
			backup.restoreObjectBackup("on_save", fileName)
		end

		local errMsg = string.format("Failed to save \"%s\": %s", tostring(fileName), tostring(saveErr))
		logger:error("[Element] " .. errMsg)

		if showToast then
			showSaveErrorToast(errMsg)
		end

		return nil
	end

	local baseUI = self.sUI and self.sUI.spawner and self.sUI.spawner.baseUI
	if baseUI and baseUI.savedUI then
		if baseUI.savedUI.refreshEntry then
			baseUI.savedUI.refreshEntry(fileName, data)
		elseif baseUI.savedUI.reload then
			baseUI.savedUI.reload()
		end
	end

	if saveState.isSavableRootGroup(self) then
		-- This group now is its file. Binds it so auto-save knows what it may overwrite, and clears
		-- the modified state; the baseline hash is adopted by the next persistence pass rather than
		-- being computed here, where it would add a full-tree walk to every save.
		saveState.markManuallySaved(self, fileName)

		if baseUI and baseUI.exportUI then
			-- Addressed by uID, not name: the export list follows the file, so a renamed group keeps
			-- its export entry and two same-named projects stay apart.
			-- Pass the data we just wrote: syncGroup would re-read and decode the file from disk.
			if baseUI.exportUI.syncGroupFromData then
				updatedInExport = baseUI.exportUI.syncGroupFromData(fileName, data) or 0
			elseif baseUI.exportUI.syncGroup then
				updatedInExport = baseUI.exportUI.syncGroup(fileName) or 0
			end
		end

		if showToast then
			local msg = string.format("Saved group \"%s\"", self.name)
			if updatedInExport > 0 then
				if updatedInExport == 1 then
					msg = msg .. " and updated it in export list"
				else
					msg = msg .. string.format(" and updated %s entries in export list", updatedInExport)
				end
			end

			ImGui.ShowToast(ImGui.Toast.new(ImGui.ToastType.Success, 2500, msg))
		end
	end

	return updatedInExport
end

return element
