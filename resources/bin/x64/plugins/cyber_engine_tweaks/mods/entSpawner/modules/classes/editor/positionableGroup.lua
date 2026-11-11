local utils = require("modules/utils/core/utils")
local settings = require("modules/utils/core/settings")
local style = require("modules/ui/style")
local field = require("modules/utils/ui/field")
local history = require("modules/utils/project/history")
local intersection = require("modules/utils/editor/intersection")
local editor = require("modules/utils/editor/editor")
local projectTagUtil = require("modules/utils/ui/projectTag")
local previewSyncManager = require("modules/utils/preview/previewSyncManager")
local previewTimeline = require("modules/ui/previewTimeline")
local saveState = require("modules/utils/project/saveState")

local element = require("modules/classes/editor/element")
local positionable = require("modules/classes/editor/positionable")

---Class for organizing multiple objects and or groups, with position and rotation
---@class positionableGroup : positionable
---@field origin Vector4
---@field rotation EulerAngles
---@field rotationQuat Quaternion
---@field rotationDragState table?
---@field rotationUIDragStart EulerAngles?
---@field rotationUIDragStartQuat Quaternion?
---@field rotationUIDragValue table
---@field originInitialized boolean
---@field originMode string
---@field supportsSaving boolean
---@field project table?
---@field previewSyncDomain boolean
---@field previewSyncDelay number
---@field previewSyncPropertyWidth number?
local positionableGroup = setmetatable({}, { __index = positionable })

local PROJECT_DEFAULT_ICON = "TagOutline"
local PROJECT_DEFAULT_COLOR = { 0.23, 0.35, 0.55 }
local PROJECT_NEUTRAL_KEY = "__no_project__"
local PROJECT_NEUTRAL_LABEL = "No Project"
local GROUP_ROTATION_COLOR = 0xFF80FFFF

---Same icon + `SameLine()` prefix as every other transform row, so the fields line up.
---@param instance positionableGroup
local function alignGroupRotationInputs(instance)
    instance:drawRotationSectionIcon(GROUP_ROTATION_COLOR)
    ImGui.SameLine()
end

---Group-local project defaults, which differ from the neutral `projectTag` module defaults.
local PROJECT_DEFAULTS = { icon = PROJECT_DEFAULT_ICON, color = PROJECT_DEFAULT_COLOR }

---@param project table?
---@return table?
local function normalizeProjectData(project)
    return projectTagUtil.normalizeProject(project, PROJECT_DEFAULTS)
end

---@param data table?
---@return boolean
local function isSerializedSavedGroup(data)
    return type(data) == "table" and utils.isSerializedGroupStrict(data)
end

---@param instance positionableGroup
---@return table<string, table>, table[]
local function collectSavedProjectCatalog(instance)
    local projectMap = {}
    local projectOptions = {}
    local baseUI = instance and instance.sUI and instance.sUI.spawner and instance.sUI.spawner.baseUI
    local savedFiles = baseUI and baseUI.savedUI and baseUI.savedUI.files or nil
    if type(savedFiles) ~= "table" then
        return projectMap, projectOptions
    end

    for _, data in pairs(savedFiles) do
        if isSerializedSavedGroup(data) then
            local project = projectTagUtil.normalizeProject(data.project)
            if project then
                local key = projectTagUtil.normalizeNameKey(project.name)
                if key ~= "" and not projectMap[key] then
                    projectMap[key] = {
                        key = key,
                        project = project
                    }
                    table.insert(projectOptions, projectMap[key])
                end
            end
        end
    end

    table.sort(projectOptions, function(a, b)
        local nameA = a.project.name:lower()
        local nameB = b.project.name:lower()
        if nameA == nameB then
            return a.key < b.key
        end

        return nameA < nameB
    end)

    return projectMap, projectOptions
end

---@param a table?
---@param b table?
---@return boolean
local function areProjectsEqual(a, b)
    local first = projectTagUtil.normalizeProject(a)
    local second = projectTagUtil.normalizeProject(b)

    if first == nil or second == nil then
        return first == nil and second == nil
    end

    return first.name == second.name
        and first.icon == second.icon
        and first.color[1] == second.color[1]
        and first.color[2] == second.color[2]
        and first.color[3] == second.color[3]
end

---@param instance positionableGroup
---@param project table?
local function setProjectAssignment(instance, project)
    local normalized = projectTagUtil.normalizeProject(project)
    if areProjectsEqual(instance.project, normalized) then
        return
    end

    history.addAction(history.getElementChange(instance))

    if normalized then
        instance.project = {
            name = normalized.name,
            icon = normalized.icon,
            color = { normalized.color[1], normalized.color[2], normalized.color[3] }
        }
    else
        instance.project = nil
    end

    if instance.sUI and instance.sUI.invalidateCache then
        instance.sUI.invalidateCache(false)
    end
end

---@param instance positionableGroup
local function primeProjectCreateState(instance)
    local current = projectTagUtil.normalizeProject(instance.project)
    instance.projectCreateState = {
        name = "",
        icon = current and current.icon or projectTagUtil.DEFAULT_ICON,
        color = projectTagUtil.normalizeColor(current and current.color or nil)
    }
    instance.projectCreateIconSearch = instance.projectCreateIconSearch or ""
end

---@param instance positionableGroup
local function drawRootProjectTagSelector(instance)
    local projectMap, projectOptions = collectSavedProjectCatalog(instance)
    local currentProject = projectTagUtil.normalizeProject(instance.project)
    local currentKey = currentProject and projectTagUtil.normalizeNameKey(currentProject.name) or PROJECT_NEUTRAL_KEY
    local previewText = currentProject and currentProject.name or PROJECT_NEUTRAL_LABEL
    local previewIcon = IconGlyphs[(currentProject and currentProject.icon) or projectTagUtil.DEFAULT_ICON] or ""
    local comboSelectionApplied = false

    style.mutedText("Project Tag")
    ImGui.SameLine()
    ImGui.SetNextItemWidth(200 * style.viewSize)

    if ImGui.BeginCombo("##rootGroupProjectAssign" .. instance.id, previewIcon .. " " .. previewText) then
        local neutralSelected = currentKey == PROJECT_NEUTRAL_KEY
        if ImGui.Selectable((IconGlyphs[projectTagUtil.DEFAULT_ICON] or "") .. " " .. PROJECT_NEUTRAL_LABEL, neutralSelected)
            and currentKey ~= PROJECT_NEUTRAL_KEY then
            setProjectAssignment(instance, nil)
            comboSelectionApplied = true
            ImGui.CloseCurrentPopup()
        end

        if not comboSelectionApplied then
            for _, option in ipairs(projectOptions) do
                local selected = currentKey == option.key
                local icon = IconGlyphs[option.project.icon] or IconGlyphs[projectTagUtil.DEFAULT_ICON] or ""
                local label = string.format("%s %s##rootProjectOption%s%s", icon, option.project.name, option.key, instance.id)

                if ImGui.Selectable(label, selected) and currentKey ~= option.key then
                    setProjectAssignment(instance, option.project)
                    comboSelectionApplied = true
                    ImGui.CloseCurrentPopup()
                    break
                end
            end
        end

        if not comboSelectionApplied then
            ImGui.Separator()
            local plusIcon = IconGlyphs.Plus or "+"
            if ImGui.Selectable(string.format("%s Create new project tag...##rootProjectCreate%s", plusIcon, instance.id), false) then
                primeProjectCreateState(instance)
                instance.pendingProjectCreatePopupId = "##rootProjectCreatePopup" .. instance.id
            end
        end

        ImGui.EndCombo()
    end

    ImGui.SameLine()
    style.pushGreyedOut(currentProject == nil)
    style.pushButtonNoBG(true)
    if ImGui.Button(IconGlyphs.Close .. "##rootProjectClear" .. instance.id) and currentProject ~= nil then
        setProjectAssignment(instance, nil)
    end
    style.pushButtonNoBG(false)
    style.popGreyedOut(currentProject == nil)
    style.tooltip("Remove project attribution")

    local popupId = "##rootProjectCreatePopup" .. instance.id
    if instance.pendingProjectCreatePopupId == popupId then
        ImGui.OpenPopup(popupId)
        instance.pendingProjectCreatePopupId = nil
    end

    if not instance.projectCreateState then
        primeProjectCreateState(instance)
    end

    local editorState = instance.projectCreateState
    if ImGui.BeginPopup(popupId) then
        style.mutedText("Create project tag for this group")
        ImGui.Separator()

        ImGui.SetNextItemWidth(220 * style.viewSize)
        editorState.name, _ = style.inputTextWithHint("##rootProjectName" .. instance.id, "Project name...", editorState.name or "", 100)

        editorState.icon, instance.projectCreateIconSearch, _ = field.drawIconSelector("spawnedRootProject:" .. instance.id, editorState.icon, instance.projectCreateIconSearch)
        ImGui.SameLine()
        editorState.color, _ = style.trackedColor(nil, "##rootProjectColor" .. instance.id, editorState.color, 58)

        local normalizedName = projectTagUtil.normalizeNameKey(editorState.name)
        local existingProject = projectMap[normalizedName]
        if existingProject then
            style.mutedText("Existing project name detected. Assignment will reuse the existing shared project data.")
        end

        ImGui.Dummy(0, 8 * style.viewSize)
        local canAssign = projectTagUtil.trimText(editorState.name) ~= ""
        style.pushGreyedOut(not canAssign)
        if ImGui.Button("Assign##rootProjectAssign" .. instance.id) and canAssign then
            local targetProject = existingProject and existingProject.project or {
                name = editorState.name,
                icon = editorState.icon,
                color = editorState.color
            }

            setProjectAssignment(instance, targetProject)
            ImGui.CloseCurrentPopup()
        end
        style.popGreyedOut(not canAssign)

        ImGui.SameLine()
        if ImGui.Button("Cancel##rootProjectCancel" .. instance.id) then
            ImGui.CloseCurrentPopup()
        end

        ImGui.EndPopup()
    end
end

---Save-button glyphs per tracked state. Listed as `iconVariants` so the row reserves the widest of
---them and does not reflow when the state changes.
local SAVE_STATE_ICONS = {
	new = IconGlyphs.ContentSavePlusOutline,
	clean = IconGlyphs.ContentSaveCheckOutline,
	edited = IconGlyphs.ContentSaveAlertOutline,
	saving = IconGlyphs.ContentSaveCogOutline,
	error = IconGlyphs.ContentSaveAlertOutline
}

local SAVE_STATE_COLORS = {
	clean = { 0.45, 0.65, 0.45, 1.0 },
	edited = { 0.90, 0.65, 0.25, 1.0 },
	saving = { 0.45, 0.70, 0.90, 1.0 },
	error = { 0.85, 0.30, 0.30, 1.0 }
}

---Renders the per-group save button from tracked state instead of a fixed glyph.
---@param instance element
---@return string icon
---@return number[]? color
---@return string tooltip
local function getSaveButtonDisplay(instance)
	local record = saveState.getRecordFor(instance)
	local state = record and record.state or "new"
	local icon = SAVE_STATE_ICONS[state] or IconGlyphs.ContentSaveOutline

	local tooltip
	if state == "clean" then
		tooltip = string.format("Saved to \"%s\"\nNo unsaved changes", tostring(record.projectFile))
	elseif state == "edited" then
		tooltip = string.format("Unsaved changes\nSaves to \"%s\"", tostring(record.projectFile))
	elseif state == "saving" then
		tooltip = "Saving..."
	elseif state == "error" then
		tooltip = "Save problem: " .. tostring(record and record.lastError or "unknown")
	elseif record and record.duplicateOf then
		tooltip = string.format(
			"Second copy of \"%s\"\nAuto-save leaves this one alone so it cannot overwrite the original.\nSaving it manually takes over that file.",
			record.duplicateOf)
	else
		tooltip = "Not linked to a project file\nSaving creates one, named after this group"
	end

	return icon, SAVE_STATE_COLORS[state], tooltip
end

---Row save button. Goes through the frame-budgeted pipeline rather than blocking, and falls back to
---a synchronous save if the pipeline will not take it.
---@param instance element
local function queueSave(instance)
	local sUI = instance.sUI
	if sUI and sUI.saveRootGroup then
		sUI.saveRootGroup(instance)
		return
	end

	instance:save(true)
end

function positionableGroup:new(sUI)
	local o = positionable.new(self, sUI)

	o.name = "New Group"
	o.modulePath = "modules/classes/editor/positionableGroup"

	o.origin = nil
	o.rotation = nil
	o.rotationQuat = nil
	o.rotationDragState = nil
	o.rotationUIDragStart = nil
	o.rotationUIDragStartQuat = nil
	o.rotationUIDragValue = { roll = nil, pitch = nil }
	o.originInitialized = false
	o.originMode = "autoCenter"
	o.autoCenterCacheValid = false
	o.autoCenterCacheMin = nil
	o.autoCenterCacheMax = nil
	o.autoCenterCacheCenter = nil
	o.autoCenterCacheLeafCount = nil
	o.autoCenterCacheBounded = nil
	o.autoCenterCacheLockedOnly = false
	o.class = utils.combine(o.class, { "positionableGroup" })
	o.quickOperations = {
		[IconGlyphs.ContentSaveOutline] = {
			operation = queueSave,
			-- Called as `condition(element)`, which is exactly the method's own signature.
			condition = element.isRootChild,
			tooltip = "Save root group",
			allowWhenLocked = true,
			disableWhenEmpty = true,
			getDisplay = getSaveButtonDisplay,
			iconVariants = SAVE_STATE_ICONS
		}
	}
	o.supportsSaving = true
	o.applyRotationWhenDropped = false
	-- Assign the configured default project tag (if any) to newly created groups.
	o.project = normalizeProjectData(settings.defaultGroupProject)
    o.previewSyncDomain = false
    o.previewSyncDelay = 0
    o.previewSyncPropertyWidth = nil

	setmetatable(o, { __index = self })
   	return o
end

function positionableGroup:load(data, silent)
	positionable.load(self, data, silent)

	-- Backward compatibility: legacy data may only have `pos` (often 0,0,0 for nested groups).
	-- Prefer an explicit origin, else legacy pos when meaningful, else auto-center.
	local legacyPos = data.pos
	local hasLegacyPos = legacyPos ~= nil
	local legacyPosIsZero = true
	if hasLegacyPos then
		local x = legacyPos.x or 0
		local y = legacyPos.y or 0
		local z = legacyPos.z or 0
		legacyPosIsZero = x == 0 and y == 0 and z == 0
	end

	if data.origin == nil then
		if hasLegacyPos and not legacyPosIsZero then
			data.origin = legacyPos
			data.originMode = data.originMode or "manual"
			if data.originInitialized == nil then
				data.originInitialized = true
			end
		else
			data.originMode = data.originMode or "autoCenter"
			data.origin = { x = 0, y = 0, z = 0 }
			if data.originInitialized == nil then
				data.originInitialized = false
			end
		end
	else
		data.originMode = data.originMode or "manual"
		if data.originInitialized == nil then
			data.originInitialized = true
		end
	end

	data.rotation = data.rotation or { roll = 0, pitch = 0, yaw = 0 }

	self.origin = Vector4.new(data.origin.x, data.origin.y, data.origin.z, 0)
	self.originMode = data.originMode
	self.originInitialized = data.originMode ~= "autoCenter" or data.originInitialized == true

	self.rotation = EulerAngles.new(data.rotation.roll, data.rotation.pitch, data.rotation.yaw)
	self.rotationQuat = self.rotation:ToQuat()
	self.project = normalizeProjectData(data.project)
    self.previewSyncDomain = data.previewSyncDomain == true
    self.previewSyncDelay = math.max(0, tonumber(data.previewSyncDelay) or 0)
	self:invalidateAutoCenterCache(false)
	element.bumpWireframeEpoch(self)
end

---@param ctx serializeContext?
function positionableGroup:serialize(ctx)
	local data = positionable.serialize(self, ctx)

	self.origin = self.origin or self:getPosition()
	self.rotation = self.rotation or EulerAngles.new(0, 0, 0)
	self.rotationQuat = self.rotationQuat or self.rotation:ToQuat()
	self.originInitialized = self.originInitialized or (#self.childs > 0)
	self.originMode = self.originMode or "autoCenter"

	data.origin = { x = self.origin.x, y = self.origin.y, z = self.origin.z }
	data.originInitialized = self.originInitialized
	data.originMode = self.originMode
	data.rotation = { roll = self.rotation.roll, pitch = self.rotation.pitch, yaw = self.rotation.yaw }
	data.project = normalizeProjectData(self.project)
    data.previewSyncDomain = self.previewSyncDomain == true
    data.previewSyncDelay = math.max(0, tonumber(self.previewSyncDelay) or 0)

	return data
end

---Assigns the project tag, as the selector in this group's UI does.
---
---Public so the Projects tab can reach a group that is open in the Spawned tab: the tag it writes
---into the file would otherwise be overwritten by the next save of the live group, which re-emits
---the whole document from memory. Same rules either way -- an undo entry, change tracking, and a
---hierarchy cache invalidation -- and a no-op when the tag is already what it should be.
---@param project table?
function positionableGroup:setProject(project)
	setProjectAssignment(self, project)
end

function positionableGroup:addChild(child, index)
	positionable.addChild(self, child, index)
end

---@param propagate boolean?
function positionableGroup:invalidateAutoCenterCache(propagate)
	self.autoCenterCacheValid = false
	self.autoCenterCacheMin = nil
	self.autoCenterCacheMax = nil
	self.autoCenterCacheCenter = nil
	self.autoCenterCacheLeafCount = nil
	self.autoCenterCacheBounded = nil

	if propagate and self.parent and utils.isA(self.parent, "positionableGroup") then
		self.parent:invalidateAutoCenterCache(true)
	end
end

---@param entry element
---@param min Vector4
---@param max Vector4
---@param state {leafs: integer, bounded: boolean} Accumulator: how many unlocked leafs were seen, and
---whether any of them actually contributed bounds.
---@param includeLocked boolean? Also count locked entries; bypasses group caches, which exclude them.
local function accumulateWorldMinMax(entry, min, max, state, includeLocked)
	if not includeLocked and entry:isLocked() then
		return
	end

	if utils.isA(entry, "spawnableElement") then
		state.leafs = state.leafs + 1

		local entrySize = entry:getSize()
		local entryPos = entry:getCenter()

		if entrySize and entryPos then
			local halfSize = utils.multVector(entrySize, 0.5)
			local entryMin = utils.subVector(entryPos, halfSize)
			local entryMax = utils.addVector(entryPos, halfSize)

			min.x = math.min(min.x, entryMin.x)
			min.y = math.min(min.y, entryMin.y)
			min.z = math.min(min.z, entryMin.z)
			max.x = math.max(max.x, entryMax.x)
			max.y = math.max(max.y, entryMax.y)
			max.z = math.max(max.z, entryMax.z)

			state.bounded = true
		end

		return
	end

	if utils.isA(entry, "positionableGroup") then
		-- A group that already knows its own bounds is folded in wholesale instead of re-walking it,
		-- which keeps a full-tree serialize from costing O(n * depth).
		if not includeLocked and entry.autoCenterCacheValid and entry.autoCenterCacheLeafCount ~= nil then
			-- Bounds measured from locked content only stay private to that group.
			if entry.autoCenterCacheLockedOnly then
				return
			end

			state.leafs = state.leafs + entry.autoCenterCacheLeafCount

			if entry.autoCenterCacheBounded and entry.autoCenterCacheMin and entry.autoCenterCacheMax then
				local entryMin = entry.autoCenterCacheMin
				local entryMax = entry.autoCenterCacheMax

				min.x = math.min(min.x, entryMin.x)
				min.y = math.min(min.y, entryMin.y)
				min.z = math.min(min.z, entryMin.z)
				max.x = math.max(max.x, entryMax.x)
				max.y = math.max(max.y, entryMax.y)
				max.z = math.max(max.z, entryMax.z)

				state.bounded = true
			end

			return
		end

		for _, child in pairs(entry.childs) do
			accumulateWorldMinMax(child, min, max, state, includeLocked)
		end
	end
end

function positionableGroup:getDirection(direction)
    local groupQuat = self:getRotation():ToQuat()

    if direction == "forward" then
        return groupQuat:GetForward()
    elseif direction == "right" then
        return groupQuat:GetRight()
    elseif direction == "up" then
        return groupQuat:GetUp()
    else
		return groupQuat:GetForward()
    end
end

---Gets all the positionable leaf objects, i.e. positionable's without childs
---@return positionable[]
function positionableGroup:getPositionableLeafs()
	local objects = {}

	local function collectLeafs(entry)
		if entry:isLocked() then
			-- Locked entries are excluded from group-level transforms and batch operations.
		elseif utils.isA(entry, "spawnableElement") then
			table.insert(objects, entry)
		elseif utils.isA(entry, "positionableGroup") then
			for _, child in pairs(entry.childs) do
				collectLeafs(child)
			end
		end
	end

	for _, entry in pairs(self.childs) do
		collectLeafs(entry)
	end

	return objects
end

function positionableGroup:drawGeneralProperties()
	positionable.drawGeneralProperties(self)
	style.mutedText("Show Group Wireframe")
	ImGui.SameLine()
	settings.groupWireframeEnabled, _ = style.trackedCheckbox(self, "##showGroupWireframe", settings.groupWireframeEnabled)
	style.tooltip("Show boundaries and origin.")

    if ImGui.TreeNodeEx("Preview Sync", ImGuiTreeNodeFlags.SpanFullWidth) then
        if not self.previewSyncPropertyWidth then
            self.previewSyncPropertyWidth = utils.getTextMaxWidth({ "Sync Domain Root", "Group Delay" }) + 2 * ImGui.GetStyle().ItemSpacing.x + ImGui.GetCursorPosX()
        end

        style.mutedText("Sync Domain Root")
        ImGui.SameLine()
        ImGui.SetCursorPosX(self.previewSyncPropertyWidth)
        local changed
        self.previewSyncDomain, changed = style.trackedCheckbox(self, "##previewSyncDomain", self.previewSyncDomain)
        if changed then
            previewSyncManager.onGroupSettingsChanged(self)
        end
        style.tooltip("When enabled, this group starts a new preview synchronization domain for descendants.")

        style.mutedText("Group Delay")
        ImGui.SameLine()
        ImGui.SetCursorPosX(self.previewSyncPropertyWidth)
        self.previewSyncDelay, changed = style.trackedDragFloat(self, "##previewSyncDelay", self.previewSyncDelay, 0.05, 0, 120, "%.2f sec", 90)
        if changed then
            self.previewSyncDelay = math.max(0, self.previewSyncDelay)
            previewSyncManager.onGroupSettingsChanged(self)
        end
        style.tooltip("Delay added to all synchronized preview loops under this group. Nested group delays stack.")

        if ImGui.Button("Sync Now##previewSyncDomainNow") then
            previewSyncManager.syncGroupDomain(self)
        end
        style.tooltip("Restart synchronized effect/particle preview timing for this group's effective domain.")

        ImGui.SameLine()
        local openTimelineLabel, openTimelineHiddenText = style.resolveActionLabel(IconGlyphs.ChartTimeline, "Open Preview Timeline", "previewSyncOpenTimeline", nil, true)
        if ImGui.Button(openTimelineLabel) then
            previewTimeline.openForGroup(self)
        end
        if openTimelineHiddenText then
            style.tooltipActionLabel(openTimelineHiddenText, openTimelineHiddenText .. "\nOpen Preview Timeline focused on this group's synchronization domain.")
        else
            style.tooltip("Open Preview Timeline focused on this group's synchronization domain.")
        end

        ImGui.TreePop()
    end
end

function positionableGroup:getExtraGroupedProperties()
    if not self:isRootChild() then
        return {}
    end

    return {
        rootProjectTag = {
            id = "rootProjectTag",
            name = "Project Tag",
            draw = function ()
                drawRootProjectTagSelector(self)
            end
        }
    }
end

function positionableGroup:getWorldMinMax()
	if self.autoCenterCacheValid and self.autoCenterCacheMin and self.autoCenterCacheMax then
		return self.autoCenterCacheMin, self.autoCenterCacheMax
	end

	local function getFallbackOrigin()
		if self.origin then
			return Vector4.new(self.origin.x, self.origin.y, self.origin.z, self.origin.w or 0)
		end

		return Vector4.new(0, 0, 0, 1)
	end

	local min = Vector4.new(math.huge, math.huge, math.huge, 0)
	local max = Vector4.new(-math.huge, -math.huge, -math.huge, 0)

	-- One walk. This used to call getPositionableLeafs() purely to test for emptiness, which walked
	-- the whole subtree and allocated a table of every leaf, and then walked it a second time to
	-- accumulate. The leaf count now falls out of the accumulation itself.
	local state = { leafs = 0, bounded = false }

	for _, entry in pairs(self.childs) do
		accumulateWorldMinMax(entry, min, max, state)
	end

	-- Everything locked (e.g. a locked group): use the locked content rather than the stale origin.
	local lockedOnly = false
	if state.leafs == 0 then
		for _, entry in pairs(self.childs) do
			accumulateWorldMinMax(entry, min, max, state, true)
		end
		lockedOnly = state.leafs > 0
	end
	self.autoCenterCacheLockedOnly = lockedOnly

	if state.leafs == 0 then
		local fallback = getFallbackOrigin()
		self.autoCenterCacheMin = fallback
		self.autoCenterCacheMax = fallback
		self.autoCenterCacheCenter = fallback
		self.autoCenterCacheLeafCount = 0
		self.autoCenterCacheBounded = false
		self.autoCenterCacheValid = true
		return self.autoCenterCacheMin, self.autoCenterCacheMax
	end

	if not state.bounded then
		min = Vector4.new(0, 0, 0, 0)
		max = Vector4.new(0, 0, 0, 0)
	end

	self.autoCenterCacheMin = min
	self.autoCenterCacheMax = max
	self.autoCenterCacheCenter = utils.addVector(utils.multVector(utils.subVector(max, min), 0.5), min)
	self.autoCenterCacheLeafCount = state.leafs
	self.autoCenterCacheBounded = state.bounded
	self.autoCenterCacheValid = true

	return min, max
end

function positionableGroup:getCenter()
	if self.autoCenterCacheValid and self.autoCenterCacheCenter then
		return self.autoCenterCacheCenter
	end

	local min, max = self:getWorldMinMax()
	return self.autoCenterCacheCenter or utils.addVector(utils.multVector(utils.subVector(max, min), 0.5), min)
end

function positionableGroup:setOriginToCenter()
	self.originMode = "autoCenter"
	self:invalidateAutoCenterCache(false)
	if #self.childs == 0 then
		self.origin = Vector4.new(0, 0, 0, 1)
	else
		self.origin = self:getCenter()
	end
	self.originInitialized = true
	-- Only this node's own fields change, so the subtree keeps its caches.
	saveState.markDirty(self)
	element.bumpWireframeEpoch(self)
end

function positionableGroup:setOrigin(v)
	self.origin = v
	self.originMode = "manual"
	self.originInitialized = true
	saveState.markDirty(self)
	element.bumpWireframeEpoch(self)
end

function positionableGroup:getPosition()
	self.originMode = self.originMode or "autoCenter"

	if self.originMode == "autoCenter" then
		if #self.childs == 0 then
			return Vector4.new(0, 0, 0, 1)
		end
		return self:getCenter()
	end

	if self.origin == nil then
		if #self.childs == 0 then
			self.origin = Vector4.new(0, 0, 0, 1)
		else
			self.origin = self:getCenter()
		end
		self.originInitialized = true
	end
	return self.origin
end

function positionableGroup:setPosition(position)
	local delta = utils.subVector(position, self:getPosition())
	self:setPositionDelta(delta)
end

function positionableGroup:setPositionDelta(delta)
	if self.originMode ~= "autoCenter" then
		self.origin = utils.addVector(self:getPosition(), delta)
	end
	local leafs = self:getPositionableLeafs()

	for _, entry in pairs(leafs) do
		entry:setPositionDelta(delta)
	end

	-- Covers this node's own `origin`, and the descendants a locked entry kept `leafs` from reaching.
	saveState.markSubtreeDirty(self)
end

function positionableGroup:drawRotation(rotation)
	local locked = self.rotationLocked
	local shiftActive = (ImGui.IsKeyDown(ImGuiKey.LeftShift) or ImGui.IsKeyDown(ImGuiKey.RightShift)) and not ImGui.IsMouseDragging(0, 0)
	local finished = false
	local unstableZoneThreshold = 3.6
	local function drawLiveAngleFromStart(value, name, axis)
		local steps = settings.rotSteps

		local displayValue = self.rotationUIDragValue[axis] or value
		local inUnstableZone = math.abs(displayValue) <= unstableZoneThreshold
		if inUnstableZone then
			ImGui.PushStyleColor(ImGuiCol.FrameBg, 1.0, 0.55, 0.0, 0.35)
			ImGui.PushStyleColor(ImGuiCol.FrameBgHovered, 1.0, 0.55, 0.0, 0.45)
			ImGui.PushStyleColor(ImGuiCol.FrameBgActive, 1.0, 0.55, 0.0, 0.55)
		end
		local newValue, changed, finishedAxis = field.advancedTrackedFloat(nil, "##" .. name, displayValue, {
			step = steps,
			min = -99999,
			max = 99999,
			format = "%.2f",
			shiftFormat = "%.3f",
			manualEditFormat = "%.3f",
			suffix = " " .. name,
			width = 80,
			flags = ImGuiSliderFlags.NoRoundToFormat
		})
		if inUnstableZone then
			ImGui.PopStyleColor(3)
		end
		self.controlsHovered = (ImGui.IsItemHovered() or ImGui.IsItemActive()) or self.controlsHovered

		if (ImGui.IsItemHovered() or ImGui.IsItemActive()) and axis ~= self.visualizerDirection then
			self:setVisualizerDirection(axis)
		end

		if changed and not history.propBeingEdited then
			history.addAction(history.getElementChange(self))
			history.propBeingEdited = true
			history.lastEditedElement = self
		end

		if changed then
			if not self.rotationUIDragStart then
				self.rotationUIDragStart = EulerAngles.new(rotation.roll, rotation.pitch, rotation.yaw)
				self.rotationUIDragStartQuat = self.rotationQuat or self:getRotation():ToQuat()
				self.rotationUIDragValue.roll = rotation.roll
				self.rotationUIDragValue.pitch = rotation.pitch
				self:beginRotationDrag()
			end

			local start = self.rotationUIDragStart
			local startQuat = self.rotationUIDragStartQuat or start:ToQuat()
			local angleDelta = (axis == "roll" and (newValue - start.roll) or (newValue - start.pitch))
			local localAxis = axis == "roll" and Vector4.new(0, 1, 0, 0) or Vector4.new(1, 0, 0, 0)
			local worldAxis = startQuat:Transform(localAxis):Normalize()
			local stepQuat = Quaternion.SetAxisAngle(worldAxis, Deg2Rad(angleDelta))
			local targetQuat = utils.multQuat(stepQuat, startQuat)

			self.rotationUIDragValue[axis] = newValue
			self:applyRotationDrag(stepQuat, targetQuat, targetQuat:ToEulerAngles())
		end

		if finishedAxis then
			self.rotationUIDragStart = nil
			self.rotationUIDragStartQuat = nil
			self.rotationUIDragValue.roll = nil
			self.rotationUIDragValue.pitch = nil
			self:endRotationDrag()
			history.propBeingEdited = false
			self:onEdited()
		end

		return finishedAxis
	end

    alignGroupRotationInputs(self)
	ImGui.PushItemWidth(80 * style.viewSize)
	ImGui.BeginDisabled(locked)
	style.pushGreyedOut(locked)
    finished = drawLiveAngleFromStart(rotation.roll, "Roll", "roll")
	self:handleRightAngleChange("roll", shiftActive and not finished)
    ImGui.SameLine()
    finished = drawLiveAngleFromStart(rotation.pitch, "Pitch", "pitch") or finished
	self:handleRightAngleChange("pitch", shiftActive and not finished)
    ImGui.SameLine()
	finished = self:drawProp(rotation.yaw, "Yaw", "yaw")
	self:handleRightAngleChange("yaw", shiftActive and not finished)
	ImGui.SameLine()
	style.pushButtonNoBG(true)
	if ImGui.Button(IconGlyphs.Numeric0BoxMultipleOutline) then
		history.addAction(history.getElementChange(self))
		self:setRotationIdentity()
	end
	style.pushButtonNoBG(false)
	style.tooltip("Set current group rotation as identity\nKeeps current rotation, but treats it as the new zero.")
	style.popGreyedOut(locked)
	ImGui.EndDisabled()
	ImGui.SameLine()
	style.mutedText(IconGlyphs.AlertOutline)
	style.tooltip("Experimental Roll/Pitch\nUnreliable between -3.60° and 3.60°\nUse with caution")
end

function positionableGroup:setRotationIdentity()
	self:setIdentity(EulerAngles.new(0, 0, 0))
end

---@param rotation EulerAngles|table
function positionableGroup:setIdentity(rotation)
	local roll = rotation and rotation.roll or 0
	local pitch = rotation and rotation.pitch or 0
	local yaw = rotation and rotation.yaw or 0

	self.rotationDragState = nil
	self.rotationUIDragStart = nil
	self.rotationUIDragStartQuat = nil
	self.rotationUIDragValue.roll = nil
	self.rotationUIDragValue.pitch = nil
	self.rotation = EulerAngles.new(roll, pitch, yaw)
	self.rotationQuat = self.rotation:ToQuat()
	-- Re-labels this group's frame without touching a single child transform.
	saveState.markDirty(self)
	element.bumpWireframeEpoch(self)
end

function positionableGroup:beginRotationDrag()
	local pos = self:getPosition()
	local leafs = self:getPositionableLeafs()
	local entries = {}

	for _, entry in pairs(leafs) do
		table.insert(entries, {
			entry = entry,
			startRelativePosition = utils.subVector(entry:getPosition(), pos),
			startRotationQuat = entry:getRotation():ToQuat()
		})
	end

	self.rotationDragState = {
		position = pos,
		entries = entries
	}
end

---@param stepQuat Quaternion
---@param targetQuat Quaternion
---@param targetEuler EulerAngles?
function positionableGroup:applyRotationDrag(stepQuat, targetQuat, targetEuler)
	if self.rotationLocked then return end
	if not self.rotationDragState then
		self:beginRotationDrag()
	end

	local state = self.rotationDragState
	self.rotationQuat = targetQuat
	self.rotation = targetEuler or targetQuat:ToEulerAngles()

	for _, data in pairs(state.entries) do
		local newRotation = utils.multQuat(stepQuat, data.startRotationQuat):ToEulerAngles()
		data.entry:setRotation(newRotation)

		local newPosition = utils.addVector(state.position, stepQuat:Transform(data.startRelativePosition))
		data.entry:setPosition(newPosition)
	end

	saveState.markSubtreeDirty(self)
end

function positionableGroup:endRotationDrag()
	self.rotationDragState = nil
end

function positionableGroup:setRotation(rotation)
	if self.rotationLocked then return end

	self.rotationDragState = nil
	local pos = self:getPosition()
	local leafs = self:getPositionableLeafs()
	local currentQuat = self.rotationQuat or self:getRotation():ToQuat()
	local targetQuat = rotation:ToQuat()
	local deltaQuat = Quaternion.MulInverse(targetQuat, currentQuat)

	self.rotationQuat = targetQuat
	self.rotation = EulerAngles.new(rotation.roll, rotation.pitch, rotation.yaw)

	for _, entry in pairs(leafs) do
		local relativePosition = utils.subVector(entry:getPosition(), pos)
		local entryQuat = entry:getRotation():ToQuat()

		local newRotation = utils.multQuat(deltaQuat, entryQuat):ToEulerAngles()
		entry:setRotation(newRotation)

		local newPosition = utils.addVector(pos, deltaQuat:Transform(relativePosition))
		entry:setPosition(newPosition)
	end

	saveState.markSubtreeDirty(self)
end

function positionableGroup:getRotation()
	if self.rotation == nil then
		self.rotation = EulerAngles.new(0, 0, 0)
	end
	if self.rotationQuat == nil then
		self.rotationQuat = self.rotation:ToQuat()
	end
	return self.rotation
end

function positionableGroup:setRotationDelta(delta)
	if self.rotationLocked then return end

	local pos = self:getPosition()
	local leafs = self:getPositionableLeafs()
	local workingQuat = self.rotationQuat or self:getRotation():ToQuat()
	local deltaQuat = EulerAngles.new(0, 0, 0):ToQuat()

	local function applyLocalAxisDelta(localAxis, angleDeg)
		if angleDeg == 0 then return end

		local worldAxis = workingQuat:Transform(localAxis):Normalize()
		local stepQuat = Quaternion.SetAxisAngle(worldAxis, Deg2Rad(angleDeg))

		deltaQuat = utils.multQuat(stepQuat, deltaQuat)
		workingQuat = utils.multQuat(stepQuat, workingQuat)
	end

	-- Keep mapping aligned with existing element behavior:
	-- roll -> local Y, pitch -> local X, yaw -> local Z.
	applyLocalAxisDelta(Vector4.new(0, 1, 0, 0), delta.roll)
	applyLocalAxisDelta(Vector4.new(1, 0, 0, 0), delta.pitch)
	applyLocalAxisDelta(Vector4.new(0, 0, 1, 0), delta.yaw)

	self.rotationQuat = workingQuat
	self.rotation = workingQuat:ToEulerAngles()

	for _, entry in pairs(leafs) do
		local relativePosition = utils.subVector(entry:getPosition(), pos)
		local entryQuat = entry:getRotation():ToQuat()

		local newRotation = utils.multQuat(deltaQuat, entryQuat):ToEulerAngles()
		entry:setRotation(newRotation)

		local newPosition = utils.addVector(pos, deltaQuat:Transform(relativePosition))
		entry:setPosition(newPosition)
	end

	saveState.markSubtreeDirty(self)
end

function positionableGroup:onEdited()
	local leafs = self:getPositionableLeafs()

	for _, entry in pairs(leafs) do
		entry:onEdited()
	end
end

function positionableGroup:getSize()
	local min, max = self:getWorldMinMax()
	return utils.subVector(max, min)
end

---Whether a drop anchors on the low point of the bounding box instead of the asset's own origin.
---Read at land time rather than passed down: the setting is global to every drop and the group drop
---queue is asynchronous, so reading it here keeps an in-flight queue consistent with the UI.
---@return boolean
local function dropAnchorsToBoundingBox()
	return settings.dropToFloorMode == 1
end

---@param isMulti boolean? True to drop every child individually instead of the group as one box.
---@param direction Vector4 Drop direction.
---@param excludeDict table<number, boolean>? Spawnable element ids the drop raycast must ignore.
---@param onComplete fun()? Invoked once the drop has settled, on every exit path.
---@param skipHistory boolean? True when a caller already recorded a history action.
function positionableGroup:dropToSurface(isMulti, direction, excludeDict, onComplete, skipHistory)
	local function finish()
		if onComplete then onComplete() end
	end

	-- Exclusions were already resolved by whoever asked for the multi drop, so they are forwarded
	-- rather than rebuilt here; rebuilding would drop the caller's set on every nesting level.
	if isMulti then self:dropChildrenToSurface(skipHistory, direction, false, excludeDict, onComplete); return end

	excludeDict = excludeDict or {}
	local leafs = self:getPositionableLeafs()
	for _, entry in pairs(leafs) do
		excludeDict[entry.id] = true
	end

	local size = self:getSize()
	local bBox = {
		min = Vector4.new(-size.x / 2, -size.y / 2, -size.z / 2, 0),
		max = Vector4.new(size.x / 2, size.y / 2, size.z / 2, 0)
	}

	local toOrigin = utils.multVector(direction, -999)
	local origin = intersection.getBoxIntersection(utils.subVector(self:getCenter(), toOrigin), utils.multVector(direction, -1), self:getCenter(), self:getRotation(), bBox --[[ -9 +9 ]])

	if not origin.hit then return finish() end

	origin.position = utils.addVector(origin.position, utils.multVector(direction, 0.025))
	local hit = editor.getRaySceneIntersection(direction, origin.position, excludeDict, true)

	if not hit.hit then return finish() end

	local target = utils.multVector(hit.result.normal, -1)
	local current = origin.normal

	local diff = utils.getAlignmentQuat(current, target, self:getRotation())

	if not isMulti and not skipHistory then
		history.addAction(history.getElementChange(self))
	end

	local newRotation = utils.multQuat(self:getRotation():ToQuat(), diff)
	if self.applyRotationWhenDropped then
		self:setRotation(newRotation:ToEulerAngles())
	end

	local surfacePoint = hit.result.unscaledHit or hit.result.position -- phyiscal hits dont have unscaledHit
	local newPosition = surfacePoint

	if dropAnchorsToBoundingBox() then
		-- Push back out along the half-extents so the low point of the bounding box rests on the
		-- surface. Evaluated after `setRotation` above, since the rotation moves the center too.
		local offset = utils.multVecXVec(newRotation:Transform(origin.normal), Vector4.new(size.x / 2, size.y / 2, size.z / 2, 0))
		local newCenter = utils.addVector(surfacePoint, utils.multVector(hit.result.normal, offset:Length()))
		newPosition = utils.addVector(newCenter, utils.subVector(self:getPosition(), self:getCenter()))
	end

	if hit.hit then
		self:setPosition(newPosition)
		self:onEdited()
	end

	finish()
end

---Drops every child of this group individually, one per `taskDelay`, lowest child first.
---
---Runs asynchronously: children after the first land over the following frames. Callers that need
---to act on the finished result (the brush applies its rotation/scale variation) must use
---`onComplete` rather than assuming the drop is done when this returns.
---@param skipHistory boolean? True when a caller already recorded a history action.
---@param direction Vector4 Drop direction.
---@param excludeSelf boolean? True to hide this group's own geometry from the drop raycasts.
---@param excludeDict table<number, boolean>? Spawnable element ids the drop raycast must ignore.
---@param onComplete fun()? Invoked once every child has settled.
function positionableGroup:dropChildrenToSurface(skipHistory, direction, excludeSelf, excludeDict, onComplete)
	-- Copy before sorting: `self.childs` is the hierarchy order shown in the UI and written to the
	-- project file, and dropping must not reorder it.
	local children = {}
	for _, child in ipairs(self.childs) do
		if utils.isA(child, "positionable") then
			children[#children + 1] = child
		end
	end
	table.sort(children, function (a, b)
		return a:getPosition().z < b:getPosition().z
	end)

	excludeDict = excludeDict or {}
	if excludeSelf then
		-- The raycast only ever matches spawnable element ids, so excluding direct children is not
		-- enough: a group id matches nothing, and its meshes would stay hittable.
		for _, leaf in pairs(self:getPositionableLeafs()) do
			excludeDict[leaf.id] = true
		end
	end

	local task = require("modules/utils/pipeline/tasks"):new()
	task.taskDelay = 0.03
	task:onFinalize(function ()
		if onComplete then onComplete() end
	end)

	for _, entry in ipairs(children) do
		task:addTask(function ()
			-- The queue spans several frames, so a child can be erased or undone out from under it.
			if entry.parent == nil then
				task:taskCompleted()
				return
			end

			-- A child group drops asynchronously in turn, so completion is reported by callback
			-- instead of assumed on return.
			entry:dropToSurface(true, direction, excludeDict, function ()
				task:taskCompleted()
			end, true)
		end)
	end

	if not skipHistory then
		history.addAction(history.getElementChange(self))
	end

	task:run(true)
end

return positionableGroup
