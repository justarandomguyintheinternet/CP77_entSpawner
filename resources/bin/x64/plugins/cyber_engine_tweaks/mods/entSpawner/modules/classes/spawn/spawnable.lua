local utils = require("modules/utils/core/utils")
local gameUtils = require("modules/utils/game/gameUtils")
local builder = require("modules/utils/game/entityBuilder")
local visualizer = require("modules/utils/preview/visualizer")
local style = require("modules/ui/style")
local field = require("modules/utils/ui/field")
local history = require("modules/utils/project/history")
local intersection = require("modules/utils/editor/intersection")
local registry = require("modules/utils/game/nodeRefRegistry")
local editor = require("modules/utils/editor/editor")
local GameSettings = require("modules/utils/vendor/GameSettings")
local preview = require("modules/utils/preview/previewUtils")
local logger = require("modules/utils/core/logger")
local settings = require("modules/utils/core/settings")
local assetValidation = require("modules/utils/game/assetValidation")
local Cron = require("modules/utils/vendor/Cron")

---Base class for any object / node that can be spawned
---@class spawnable
---@field public dataType string
---@field public spawnListType string
---@field public spawnListPath string
---@field public modulePath string
---@field public spawnData string
---@field public app string
---@field public position Vector4
---@field public rotation EulerAngles
---@field protected entityID entEntityID
---@field protected entity entEntity?
---@field protected spawned boolean
---@field protected spawning boolean
---@field protected despawning boolean
---@field protected queueRespawn boolean
---@field public primaryRange number
---@field protected streamingMultiplier number
---@field public isHovered boolean
---@field protected arrowDirection string all|red|green|blue
---@field public object element? The element that is using this spawnable
---@field public node string
---@field public description string
---@field public previewNote string
---@field public icon string
---@field public secondaryIcon string
---@field private rotationRelative boolean
---@field protected outline integer
---@field private spawnedAndCachedCallback function[]
---@field protected spawnGeneration integer
---@field protected currentSpawnToken {generation: integer, entityHash: integer}?
---@field protected nodeRef string
---@field public noExport boolean
---@field private worldNodePropertyWidth number
---@field private streamingPropertyWidth number
---@field private streamingPresetIndex integer
---@field public assetPreviewType string none|backdrop|current_position
---@field public assetPreviewDelay number
---@field public isAssetPreview boolean
---@field public assetPreviewBaseRotation EulerAngles? Rotation the asset preview turntable was at when the keyboard controls took over
---@field private assetPreviewLensDistortion boolean
---@field public streamingRefPointOverride boolean
---@field public streamingRefPoint Vector4
---@field public visualizeStreamingRange boolean
---@field protected assetCheck assetCheckResult? Type check of `spawnData`, see `refreshAssetCheck`
---@field private assetBlockReported boolean
---@field private assetPathEdit string Live value of the asset path editor's path field, see `drawAssetPathEditPopup`
---@field private assetNameEdit string Live value of the asset path editor's name field
local spawnable = {}

-- The asset path editor is drawn by whichever node is selected, and only one ever is, so a single
-- ID is enough. Text before `##` is the popup's title bar.
local ASSET_PATH_EDIT_POPUP_ID = "Edit Asset Path##wb-assetPathEdit-wui"
local ASSET_PATH_EDIT_POPUP_WIDTH = 520
local streamingPresetLabels = {
    "Interior",
    "Street",
    "District",
    "Landscape",
    "To the Moon"
}
local streamingPresetValues = {
    100,
    400,
    1000,
    5000,
    3.4028235e+38 -- Effectively infinite
}
local streamingPresetVersion = 2

function spawnable:new()
	local o = {}

    o.dataType = "Spawnable"
    o.spawnListType = "list"
    o.spawnListPath = "data/spawnables/entity/templates/"
    o.modulePath = "spawnable"
    o.node = "worldEntityNode"
    o.description = ""
    o.previewNote = "---"
    o.icon = ""
    o.secondaryIcon = ""

    o.spawnData = "base\\spawner\\empty_entity.ent"
    o.app = "default"

    o.position = Vector4.new(0, 0, 0, 0)
    o.rotation = EulerAngles.new(0, 0, 0)
    o.entityID = entEntityID.new({hash = 0})
    o.entity = nil
    o.spawned = false
    o.spawning = false
    o.despawning = false
    o.queueRespawn = false
    o.spawnedAndCachedCallback = {}
    o.spawnGeneration = 0
    o.currentSpawnToken = nil
    o.worldNodePropertyWidth = nil
    o.streamingPropertyWidth = nil

    -- Default streaming distance is driven by the "Default Streaming distance"
    -- setting so both the preset selector and the numeric input start in sync.
    local defaultPreset = math.max(0, math.min(#streamingPresetLabels - 1, settings.defaultStreamingPreset or 0))
    o.streamingPresetIndex = defaultPreset

    o.noExport = false
    o.primaryRange = streamingPresetValues[defaultPreset + 1] or 120
    o.streamingMultiplier = 1
    o.nodeRef = ""
    o.streamingRefPointOverride = false
    o.streamingRefPoint = Vector4.new(0, 0, 0, 0)
    o.visualizeStreamingRange = false

    o.assetCheck = nil
    o.assetBlockReported = false
    o.assetPathEdit = ""
    o.assetNameEdit = ""

    o.isHovered = false
    o.arrowDirection = "none"
    o.rotationRelative = false
    o.outline = 0

    o.assetPreviewType = "none"
    o.assetPreviewDelay = 0.1
    o.isAssetPreview = false
    o.assetPreviewLensDistortion = false

    o.collapseSpawnList = false
    o.collapsedSpawnListLabel = nil
    o.entryFilter = nil
    o.entryNote = nil
    o.previewSuppressedComponents = nil

    o.object = object

    self.__index = self
   	return setmetatable(o, self)
end

function spawnable:onAssemble(entity)
    visualizer.attachArrows(entity, self:getScaledArrowSize(), self.isHovered, self.arrowDirection)
end

function spawnable:onAttached(entity)
    self.spawned = true
    self.spawning = false

    -- Before the callbacks, so they observe the corrected transform rather than the spawned one.
    self:reconcileSpawnTransform()

    for _, callback in ipairs(self.spawnedAndCachedCallback) do
        callback(entity)
    end

    if self.despawning then
        self.despawning = false
        self:despawn()
    end

    if self.queueRespawn then
        self.queueRespawn = false
        self:respawn()
    end
end

function spawnable:registerSpawnedAndAttachedCallback(callback)
    table.insert(self.spawnedAndCachedCallback, callback)
end

---Returns a snapshot token that identifies the current spawn lifetime.
---@return {generation: integer, entityHash: integer}?
function spawnable:getSpawnLifetimeToken()
    if type(self.currentSpawnToken) ~= "table" then
        return nil
    end

    return {
        generation = self.currentSpawnToken.generation,
        entityHash = self.currentSpawnToken.entityHash
    }
end

---Checks whether the provided token still matches the currently active spawn lifetime.
---@param token {generation: integer, entityHash: integer}?
---@param entity entEntity?
---@return boolean
function spawnable:isSpawnLifetimeTokenCurrent(token, entity)
    if type(token) ~= "table" or type(self.currentSpawnToken) ~= "table" then
        return false
    end

    if token.generation ~= self.currentSpawnToken.generation then
        return false
    end

    if token.entityHash ~= self.currentSpawnToken.entityHash then
        return false
    end

    if entity ~= nil then
        local okEntityId, entityId = pcall(function ()
            return entity:GetEntityID()
        end)

        if okEntityId and entityId and entityId.hash and entityId.hash ~= token.entityHash then
            return false
        end
    end

    return true
end

---Re-runs the asset type check against the current `spawnData`.
---Called from `loadSpawnData`, which is the only place `spawnData` is set for good; anything that
---swaps it around a spawn call (the placeholder entity wrappers) must not invalidate the result,
---which is why `spawn` reads the cached one rather than checking the live path.
---@protected
function spawnable:refreshAssetCheck()
    self.assetCheck = assetValidation.check(self.modulePath, self.spawnData)
    self.assetBlockReported = false
end

---The reason this spawnable's asset must not be handed to the game, or nil when it may be.
---@return string? reason
function spawnable:getAssetSpawnBlock()
    if settings.validateAssetTypes == false then return nil end
    if not self.assetCheck or self.assetCheck.severity ~= "error" then return nil end

    return assetValidation.getSummary(self.assetCheck, self.dataType or self.modulePath)
end

---Whether `spawnData` is a depot asset path that may be pointed at another asset.
---@return boolean
function spawnable:hasEditableAssetPath()
    return assetValidation.hasAssetPath(self.modulePath)
end

---Points this node at another asset, optionally renaming the element in the same move.
---
---Writing `spawnData` and respawning would keep everything the class read off the *old* asset:
---appearance lists, bounding box, occluder support, whatever a subtype loads for itself. So the
---element is serialized and loaded back with the new path instead, which is the one path every
---class already implements for an asset it has never seen.
---
---The name rides along in that same payload rather than going through `element:rename`, which would
---record a second history action: both were one decision in the editor, so one undo takes both back.
---That is also how history itself renames -- `getRename` swaps a serialized element in, name and all.
---@param path string New depot path. Trimmed, and ignored when empty or unchanged.
---@param name string? New display name. Ignored when empty, unchanged, or the element is locked.
---@return boolean changed
function spawnable:setAssetPath(path, name)
    local object = self.object
    if not object then return false end

    path = utils.sanitizeText(path)
    local newPath = (path ~= "" and path ~= self.spawnData) and path or nil

    local newName = nil
    if name ~= nil and object:canRename() then
        local resolved = object:resolveSiblingName(utils.sanitizeText(name))
        if resolved ~= "" and resolved ~= object.name then
            newName = resolved
        end
    end

    if not newPath and not newName then return false end

    local data = object:serialize()
    if not data or not data.spawnable then return false end

    local previousPath = self.spawnData
    local previousName = object.name
    data.spawnable.spawnData = newPath or previousPath
    data.name = newName or previousName

    history.addAction(history.getElementChange(object))
    object:load(data, object.silent)

    if newPath then
        logger:info(string.format("Asset path of \"%s\" changed from \"%s\" to \"%s\"", tostring(previousName), tostring(previousPath), newPath))
	end

	if newName then
		-- A renamed element sits at a different path, and both the Spawned tab's path cache and the
		-- NodeRef registry are keyed by it. `load` marks the element dirty but knows nothing of them.
		local sUI = object.sUI
        if sUI and sUI.invalidateCache then
            sUI.invalidateCache(true)
        end

        logger:info(string.format("Renamed \"%s\" to \"%s\"", tostring(previousName), newName))
    end

    return true
end

---Spawns the spawnable if not spawned already, must register a callback for entityAssemble which calls onAssemble
---@param ignoreSpawning boolean? If true, spawn call will be issued even if already spawning
function spawnable:spawn(ignoreSpawning)
    if self:isSpawned() or (self.spawning and not ignoreSpawning) then
        return false
    end

    -- Last line of defense: the UI refuses these long before they get here, but a project saved
    -- before the check existed, or written by hand, can still carry one. Handing the game a
    -- resource of the wrong type crashes it, so the node stays unspawned instead.
    local assetBlock = self:getAssetSpawnBlock()
    if assetBlock then
        if not self.assetBlockReported then
            self.assetBlockReported = true
            -- The checked path, not `spawnData`: the placeholder wrappers have already swapped
            -- theirs out by the time this runs.
            logger:warn(string.format("Refused to spawn \"%s\": %s", tostring(self.assetCheck.path), assetBlock))
            ImGui.ShowToast(ImGui.Toast.new(ImGui.ToastType.Error, 6000, string.format("Not spawned - %s", assetBlock)))
        end

        return false
    end

    local templatePath = type(self.spawnData) == "string" and self.spawnData or ""
    if utils.trimString(templatePath) == "" then
        logger:warn(string.format("Refused to spawn \"%s\": empty template path", tostring(self.dataType or "unknown")))
        return false
    end

    local spec = StaticEntitySpec.new()
    spec.templatePath = templatePath
    spec.position = self.position
    spec.orientation = self.rotation:ToQuat()
    spec.attached = true
    spec.appearanceName = self.app
    local spawnedId = Game.GetStaticEntitySystem():SpawnEntity(spec)
    if not spawnedId or not spawnedId.hash or spawnedId.hash == 0 then
        self.spawning = false
        self.spawned = false
        logger:warn(string.format("Failed to spawn template path \"%s\" (%s)", templatePath, tostring(self.dataType or "unknown")))
        return false
    end

    self.entityID = spawnedId
    self.spawnGeneration = self.spawnGeneration + 1
    local token = {
        generation = self.spawnGeneration,
        entityHash = self.entityID.hash
    }
    self.currentSpawnToken = token
    self.spawning = true
    -- The spec above froze the transform at request time, but the entity does not exist until the
    -- attach callback lands. `update()` needs a live entity, so anything that moves the spawnable in
    -- between (the brush randomizing rotation, a drop to the surface) is silently discarded and the
    -- entity stays at the transform it was spawned with, even though the spawnable holds the right
    -- one. Remember what the game was actually given, so `onAttached` can tell whether it went stale.
    self.spawnTransform = {
        position = Vector4.new(self.position.x, self.position.y, self.position.z, self.position.w or 0),
        rotation = EulerAngles.new(self.rotation.roll, self.rotation.pitch, self.rotation.yaw)
    }

    builder.registerAssembleCallback(self.entityID, function (entity)
        if not self:isSpawnLifetimeTokenCurrent(token, entity) then return end
        self.entity = entity
        self:onAssemble(entity)
    end)

    builder.registerAttachCallback(self.entityID, function (entity)
        if not self:isSpawnLifetimeTokenCurrent(token, entity) then return end
        self:onAttached(entity)
    end)

    return true
end

---Template used by node types whose `spawnData` is a resource path rather than an entity template.
spawnable.PLACEHOLDER_ENTITY_TEMPLATE = "base\\spawner\\empty_entity.ent"

---Spawns through the placeholder wrapper entity, restoring `spawnData` afterwards.
---Node types that carry a non-entity resource path in `spawnData` (probes, fog volumes, ...)
---use this so the base spawn call still receives a valid `.ent` template.
---@param placeholderPath string? Defaults to `spawnable.PLACEHOLDER_ENTITY_TEMPLATE`.
function spawnable:spawnAsPlaceholderEntity(placeholderPath)
    local original = self.spawnData
    self.spawnData = placeholderPath or spawnable.PLACEHOLDER_ENTITY_TEMPLATE

    spawnable.spawn(self)
    self.spawnData = original
end

---@return boolean
function spawnable:isSpawned()
    return self.spawned
end

function spawnable:despawn()
    local entity = self:getEntity()
    if entity then
        Game.GetStaticEntitySystem():DespawnEntity(self.entityID)
    end
    self.spawnTransform = nil
    self.spawned = false
    self.entity = nil

    if self.spawning then
        self.despawning = true
    end
end

function spawnable:respawn()
    -- A spawn still in flight has no live ID to despawn and spawn() no-ops while spawning, so
    -- despawn()+spawn() here would tear the entity down with nothing to bring it back. Queue
    -- instead, and onAttached runs it once the current spawn finishes.
    if self.spawning then
        self.queueRespawn = true
        return
    end

    self:despawn()
    self:spawn()
end

---@param target string
---@return boolean converted
function spawnable:convertSpawnableTo(target)
    if not self.object then return false end

    local data = self.object:serialize()
    if not data or not data.spawnable then return false end

    data.spawnable.modulePath = target
    self.object:load(data, self.object.silent)

    return true
end

---Update the position and rotation of the spawnable
local TRANSFORM_RECONCILE_EPSILON = 0.0001

---Pushes the current transform onto a freshly attached entity, but only when it drifted from the one
---the entity was spawned with. Subclass `update()` overrides can be expensive (splines rebuild their
---curve preview, bended meshes their preview hosts), so an unchanged transform stays untouched.
---@protected
function spawnable:reconcileSpawnTransform()
    local spawnTransform = self.spawnTransform
    self.spawnTransform = nil

    if not spawnTransform then return end

    local function differs(a, b)
        return math.abs(a - b) > TRANSFORM_RECONCILE_EPSILON
    end

    local drifted = differs(spawnTransform.position.x, self.position.x)
        or differs(spawnTransform.position.y, self.position.y)
        or differs(spawnTransform.position.z, self.position.z)
        or differs(spawnTransform.rotation.roll, self.rotation.roll)
        or differs(spawnTransform.rotation.pitch, self.rotation.pitch)
        or differs(spawnTransform.rotation.yaw, self.rotation.yaw)

    if not drifted then return end

    self:update()

    -- Some node types finish their internal component setup after the attach callback and overwrite
    -- what was just written, so the transform is applied once more a tick later. The lifetime token
    -- makes this a no-op if the spawnable was despawned or respawned in the meantime.
    local token = self:getSpawnLifetimeToken()
    Cron.After(0.05, function ()
        if not self:isSpawnLifetimeTokenCurrent(token, self:getEntity()) then return end

        self:update()
    end)
end

function spawnable:update()
    if not self:isSpawned() then return end

    local entity = self:getEntity()

    if not entity then return end

    local transform = entity:GetWorldTransform()
    transform:SetPosition(self.position)
    transform:SetOrientationEuler(self.rotation)
    entity:SetWorldTransform(transform)
end

---@param finished boolean
---@param delta Vector4
function spawnable:updateScale(finished, delta) end

function spawnable:onParentChanged(newParent) end

function spawnable:onObjectRemoved() end

function spawnable:setOutline(color)
    if not self:isSpawned() then return end

    self.outline = color
    utils.sendOutlineEvent(self:getEntity(), color)
end

---Called when one of the control UI widgets is released
function spawnable:onEdited(edited) end

---@return entEntity?
function spawnable:getEntity()
    local liveEntity = Game.GetStaticEntitySystem():GetEntity(self.entityID)
    if liveEntity then
        return liveEntity
    end

    if self.entity then
        local okEntityId, entityId = pcall(function ()
            return self.entity:GetEntityID()
        end)

        if okEntityId and entityId and entityId.hash and self.entityID and entityId.hash == self.entityID.hash then
            return self.entity
        end
    end

    return nil
end

---Display name of an asset path, used for Spawn New entries and spawned elements.
---@param path string
---@return string
function spawnable.getAssetName(path)
    return utils.getFileName(path)
end

--- Generate valid name from given name / path
---@param name string
---@return string newName The generated/sanitized name
function spawnable:generateName(name)
    if string.find(name, "\\") then
        name = name:match("\\[^\\]*$") -- Everything after last \
    end
    name = name:gsub(".ent", ""):gsub("\\", "_") -- Remove .ent, replace \ by _
    return utils.createFileName(name)
end

---Return the spawnable data for internal object format saving
---@return table {modulePath, position, rotation, spawnData, dataType, app}
function spawnable:save()
    return {
        modulePath = self.modulePath,
        position = { x = self.position.x, y = self.position.y, z = self.position.z, w = 0 },
        rotation = { roll = self.rotation.roll, pitch = self.rotation.pitch, yaw = self.rotation.yaw },
        spawnData = self.spawnData,
        dataType = self.dataType,
        app = self.app,
        rotationRelative = self.rotationRelative,
        primaryRange = self.primaryRange,
        nodeRef = self.nodeRef,
        streamingRefPointOverride = self.streamingRefPointOverride,
        streamingRefPoint = utils.fromVector(self.streamingRefPoint),
        visualizeStreamingRange = self.visualizeStreamingRange,
        streamingPresetIndex = self.streamingPresetIndex,
        streamingPresetVersion = streamingPresetVersion
    }
end

function spawnable:draw() end

---Optional per-class transform UI visibility contract consumed by positionable UI.
---Return nil to use defaults.
---@return table?
function spawnable:getTransformUIConfig()
    return nil
end

---Appends this node's own collapsible property section to a base-class property list.
---Subclasses whose inspector is just "base properties + my own `draw()`" use this
---so the section descriptor stays defined in one place.
---@param properties table[] Property list returned by the base class.
---@return table[] properties The same list, with this node's section appended.
function spawnable:addNodeProperty(properties)
    table.insert(properties, {
        id = self.node,
        name = self.dataType,
        defaultHeader = true,
        draw = function()
            self:draw()
        end
    })

    return properties
end

---Draws the asset type warning of the World Node section, when there is one to draw.
---Red for an asset that is refused, orange for one that spawns but looks wrong.
---@protected
function spawnable:drawAssetCheckWarning()
    local check = self.assetCheck
    if not check or check.ok then return end

    local label = self.dataType or self.modulePath
    local blocking = check.severity == "error" and settings.validateAssetTypes ~= false

    ImGui.SameLine()
    style.styledText(IconGlyphs.AlertOutline, blocking and 0xFF0000FF or style.warnColor)
    style.tooltip(assetValidation.getSummary(check, label) .. "\n\n" .. assetValidation.getDetail(check, label))
end

---The Spawn New UI, when this node's element can reach it.
---Only ever used for wording: it owns the "Type > Variant" labels the asset check names in its
---hints, and a node whose element is not attached to the UI simply goes without them.
---@param instance spawnable
---@return table?
local function getSpawnUI(instance)
    local sUI = instance.object and instance.object.sUI
    local baseUI = sUI and sUI.spawner and sUI.spawner.baseUI

    return baseUI and baseUI.spawnUI or nil
end

---Reason the Apply button of the asset path editor is disabled, or nil when it is not.
---@param blocked boolean Whether the asset check refuses the typed path.
---@param pathChanged boolean
---@param nameChanged boolean
---@param emptyPath boolean
---@return string? reason
local function getAssetPathEditBlockReason(blocked, pathChanged, nameChanged, emptyPath)
    if blocked then return nil end -- Explained by the check's own detail text instead.
    if pathChanged or nameChanged then return nil end

    if emptyPath then
        return "Enter an asset path, or a new name"
    end

    return "Neither the asset path nor the name was changed"
end

---Draws the popup that points this node at another asset, and renames the element with it.
---
---The asset is checked exactly the way Spawn New checks a path typed into its search field, and for
---the same reason: nothing vouches for a hand written path, and handing the game a resource of the
---wrong type crashes it. A path that fails that check cannot be applied; the softer warnings (asset
---not in any loaded archive, mesh not authored for this node type) are shown and left to the user.
---
---The name is offered here because the two go together: an element is named after the asset it was
---spawned from, so pointing it somewhere else usually leaves the name describing the old one.
---@protected
function spawnable:drawAssetPathEditPopup()
    if not ImGui.BeginPopupModal(ASSET_PATH_EDIT_POPUP_ID, true, ImGuiWindowFlags.AlwaysAutoResize) then
        return
    end

    local width = ASSET_PATH_EDIT_POPUP_WIDTH * style.viewSize
    local label = self.dataType or self.modulePath
    local canRename = self.object ~= nil and self.object:canRename()
    -- Every wrapped line ends where the fields do, so the auto-resized popup keeps one width whatever
    -- it ends up saying. Taken before the first `SameLine` moves the cursor.
    local wrapX = ImGui.GetCursorPosX() + width

    -- `styledText`, not `styledTextWrapped`: `TextWrapped` overrides the wrap position with the
    -- content region width, which in an auto-resizing popup is whatever the widest item made it.
    ImGui.PushTextWrapPos(wrapX)
    style.styledText(IconGlyphs.AlertOutline .. " Changing this path replaces the asset the node spawns.", style.warnColor)
    style.styledText("Appearance, size and anything else read off the asset are loaded again from the new path. Everything else is kept as it is, which for an unrelated asset can mean settings that no longer match it, or a node that spawns wrong. Undo restores the node as it was.", style.mutedColor)
    ImGui.PopTextWrapPos()

    style.spacedSeparator()

    local valueX = utils.getTextMaxWidth({ "Current", "New Path", "Name" }) + ImGui.GetStyle().ItemSpacing.x + ImGui.GetCursorPosX()
    local fieldWidth = math.max(wrapX - valueX, 140 * style.viewSize)

    style.mutedText("Current")
    ImGui.SameLine()
    ImGui.SetCursorPosX(valueX)
    ImGui.Text(utils.shortenPath(self.spawnData or "", fieldWidth, true))
    style.tooltip(self.spawnData or "")

    style.mutedText("New Path")
    ImGui.SameLine()
    ImGui.SetCursorPosX(valueX)
    ImGui.SetNextItemWidth(fieldWidth)
    self.assetPathEdit, _ = style.inputTextWithHint("##assetPathEditField", "base\\path\\to\\asset...", self.assetPathEdit, 500)

    -- Sanitized here as well as in `setAssetPath`, so what gets checked is what gets applied.
    local newPath = utils.sanitizeText(self.assetPathEdit)
    local check = assetValidation.check(self.modulePath, newPath)
    local blocked = check.severity == "error" and settings.validateAssetTypes ~= false
    local pathChanged = newPath ~= "" and newPath ~= self.spawnData

    if not check.ok then
        local spawnUI = getSpawnUI(self)
        local suggestion = spawnUI and spawnUI.getVariantSuggestion(check) or ""
        local detail = assetValidation.getDetail(check, label)

        style.styledText(IconGlyphs.AlertOutline, blocked and 0xFF0000FF or style.warnColor)
        ImGui.SameLine()
        ImGui.PushTextWrapPos(wrapX)
        style.styledText(assetValidation.getSummary(check, label), blocked and 0xFF0000FF or style.warnColor)
        ImGui.PopTextWrapPos()
        style.tooltip(suggestion ~= "" and (detail .. "\n\n" .. suggestion) or detail)
    end

    -- A locked element keeps its name whatever is typed, so the field is left out rather than offered
    -- and then ignored.
    local resolvedName = ""
    if canRename then
        style.mutedText("Name")
        ImGui.SameLine()
        ImGui.SetCursorPosX(valueX)
        ImGui.SetNextItemWidth(fieldWidth)
        self.assetNameEdit, _ = style.inputTextWithHint("##assetNameEditField", "Element name...", self.assetNameEdit, 100)

        local typedName = utils.sanitizeText(self.assetNameEdit)
        resolvedName = self.object:resolveSiblingName(typedName)

        -- Sibling names are unique, so a taken one comes back suffixed. Said up front rather than
        -- letting the element quietly land under a name nobody typed.
        if resolvedName ~= "" and resolvedName ~= typedName then
            ImGui.PushTextWrapPos(wrapX)
            style.styledText(string.format("Another element here is already called \"%s\", this one becomes \"%s\".", typedName, resolvedName), style.mutedColor)
            ImGui.PopTextWrapPos()
        end
    end

    local nameChanged = canRename and resolvedName ~= "" and resolvedName ~= self.object.name

    ImGui.Dummy(0, 8 * style.viewSize)

    -- Applying replaces `self` with a freshly loaded spawnable, so the popup is closed at the very
    -- end of the frame rather than from inside the button, which keeps this draw on the live object.
    local closeAfterDraw = false
    local blockReason = getAssetPathEditBlockReason(blocked, pathChanged, nameChanged, newPath == "")
    local disabled = blocked or blockReason ~= nil

    style.pushGreyedOut(disabled)
    if ImGui.Button("Apply##assetPathEditApply") and not disabled then
        if self:setAssetPath(newPath, canRename and self.assetNameEdit or nil) then
            local applied = pathChanged and (nameChanged and "Asset path and name changed" or "Asset path changed") or "Name changed"
            ImGui.ShowToast(ImGui.Toast.new(ImGui.ToastType.Success, 2500, applied))
        end
        closeAfterDraw = true
    end
    style.popGreyedOut(disabled)

    if blocked then
        style.tooltip(assetValidation.getDetail(check, label))
    elseif blockReason then
        style.tooltip(blockReason)
    end

    ImGui.SameLine()
    if ImGui.Button("Cancel##assetPathEditCancel") then
        closeAfterDraw = true
    end

    if closeAfterDraw then
        ImGui.CloseCurrentPopup()
    end

    ImGui.EndPopup()
end

function spawnable:getProperties()
    local properties =  {}

    table.insert(properties, {
        id = "worldNode",
        name = "World Node",
        defaultHeader = false,
        draw = function()
            if not self.worldNodePropertyWidth then
                self.worldNodePropertyWidth = utils.getTextMaxWidth({ "Asset Path", "Node Ref" }) + ImGui.GetStyle().ItemSpacing.x + ImGui.GetCursorPosX()
            end

            local entry = self.nodeRef ~= "" and registry.refs[self.object:getRootParent().name] and registry.refs[self.object:getRootParent().name][self.nodeRef]
            local refDuplicate = entry and (entry.path ~= self.object:getPath() or entry.duplicate)
            local assetPath = self.spawnData or ""

            style.mutedText("Asset Path")
            ImGui.SameLine()
            ImGui.SetCursorPosX(self.worldNodePropertyWidth)
            style.pushButtonNoBG(true)
            if ImGui.Button(IconGlyphs.ContentCopy .. "##copyAssetPath") then
                ImGui.SetClipboardText(assetPath)
                ImGui.ShowToast(ImGui.Toast.new(ImGui.ToastType.Success, 2500, "Copied asset path to clipboard"))
            end
            style.pushButtonNoBG(false)
            style.tooltip("Copy asset path to clipboard")

            local editableAssetPath = self:hasEditableAssetPath()
            if editableAssetPath then
                ImGui.SameLine()
                style.pushButtonNoBG(true)
                if ImGui.Button(IconGlyphs.PencilOutline .. "##editAssetPath") then
                    self.assetPathEdit = assetPath
                    self.assetNameEdit = self.object and self.object.name or ""
                    ImGui.OpenPopup(ASSET_PATH_EDIT_POPUP_ID)
                end
                style.pushButtonNoBG(false)
                style.tooltip("Point this node at another asset, and rename it")
            end

            ImGui.SameLine()
            ImGui.Text(utils.shortenPath(assetPath, style.getMaxWidth(250), true))
            style.tooltip(assetPath)

            self:drawAssetCheckWarning()

            if editableAssetPath then
                self:drawAssetPathEditPopup()
            end

            style.mutedText("Node Ref")
            ImGui.SameLine()
            ImGui.SetCursorPosX(self.worldNodePropertyWidth)
            local nodeRefValue, nodeRefChanged, _ = style.trackedTextField(self.object, "##noderef", self.nodeRef, "$/#foobar", style.getMaxWidth(250) - 30 - (refDuplicate and 25 or 0))
            self.nodeRef = nodeRefValue
            if nodeRefChanged then
                registry.invalidate()
            end
            style.pushButtonNoBG(true)
            ImGui.SameLine()
            if ImGui.Button(IconGlyphs.ReloadAlert) then
                local generated = registry.generate(self.object)

                if generated ~= self.nodeRef then
                    history.addAction(history.getElementChange(self.object))
                    self.nodeRef = generated
                    registry.invalidate()
                end
            end
            style.pushButtonNoBG(false)
            style.tooltip("Generate a unique NodeRef for this object")

            if refDuplicate then
                ImGui.SameLine()
                style.styledText(IconGlyphs.AlertOutline, 0xFF0000FF)
                style.tooltip("NodeRef is already in use elsewhere")
            end
            if ImGui.TreeNodeEx("Streaming Distance", ImGuiTreeNodeFlags.SpanFullWidth) then
                if not self.streamingPropertyWidth then
                    self.streamingPropertyWidth = utils.getTextMaxWidth({ "Visualize", "Distance Preset", "Streaming Distance", "Auto-Set Multiplier", "Custom Reference Point", "Streaming Ref. Point" }) + ImGui.GetStyle().ItemSpacing.x + ImGui.GetCursorPosX()
                end

                style.mutedText("Visualize")
                ImGui.SameLine()
                ImGui.SetCursorPosX(self.streamingPropertyWidth)
                self.visualizeStreamingRange, _ = style.trackedCheckbox(self.object, "##visualizeStreamingRange", self.visualizeStreamingRange)

                style.mutedText("Distance Preset")
                ImGui.SameLine()
                ImGui.SetCursorPosX(self.streamingPropertyWidth)
                -- Tracked, not a raw Combo: the index is serialized (see `save`), so an untracked write
                -- would leave the node's cached JSON stale. Tooltip goes through the combo itself to
                -- avoid stacking a second tooltip on the same item.
                self.streamingPresetIndex, _ = style.trackedCombo(self.object, "##streamingDistancePreset", self.streamingPresetIndex, streamingPresetLabels, 140, {
                    tooltip = "Quickly set Streaming Distance to a common value.\n- Interior | 100: Small rooms and indoor props loaded only when close.\n- Street | 400: Regular city assets visible from nearby streets.\n- District | 1000: Medium-large city chunks visible across a wider district area.\n- Landscape | 5000: Large outdoor landmarks visible from far away.\n- To the Moon | infinite: Keep visible from anywhere; use only for very important assets."
                })
                ImGui.SameLine()
                if ImGui.Button("Apply##streamingDistancePreset") then
                    history.addAction(history.getElementChange(self.object))
                    self.primaryRange = streamingPresetValues[(self.streamingPresetIndex or 0) + 1] or self.primaryRange
                end
                style.tooltip("Apply the selected preset to Streaming Distance.")

                style.mutedText("Streaming Distance")
                ImGui.SameLine()
                ImGui.SetCursorPosX(self.streamingPropertyWidth)
                self.primaryRange, _, _ = field.advancedTrackedFloat(self.object, "##primaryRange", self.primaryRange, {
                    step = 0.1,
                    min = 0,
                    max = 3.4028235e+38,
                    format = "%.1f",
                    width = 90
                })
                ImGui.SameLine()
                local distance = utils.distanceVector(self:getStreamingReferencePoint(), GetPlayer():GetWorldPosition())
                style.styledText(IconGlyphs.AxisArrowInfo, distance > self.primaryRange and 0xFF0000FF or 0xFF00FF00)
                style.tooltip(string.format("Distance to from %s: %.2f", self.streamingRefPointOverride and "reference point" or "node position", distance))

                style.mutedText("Auto-Set Multiplier")
                ImGui.SameLine()
                ImGui.SetCursorPosX(self.streamingPropertyWidth)
                ImGui.SetNextItemWidth(90 * style.viewSize)
                self.streamingMultiplier, _ = ImGui.DragFloat("##autoSetMultiplier", self.streamingMultiplier, 0.01, 0, 50, "x%.2f")
                style.tooltip("Multiplier for streaming values, when using \"Auto-Set\"")

                ImGui.SameLine()

                if ImGui.Button("Auto-Set") then
                    history.addAction(history.getElementChange(self.object))
                    local values = self:calculateStreamingValues(self.streamingMultiplier)

                    self.primaryRange = values.primary
                end

                style.mutedText("Custom Reference Point")
                ImGui.SameLine()
                ImGui.SetCursorPosX(self.streamingPropertyWidth)
                self.streamingRefPointOverride, _ = style.trackedCheckbox(self.object, "##streamingRefPointOverride", self.streamingRefPointOverride)
                style.tooltip("When enabled, streaming distance uses the custom point below.\nWhen disabled, it uses node's position.\nUse this if you want this asset to be visible from a specific, distant location.")

                if self.streamingRefPointOverride then
                    style.mutedText("Streaming Ref. Point")
                    ImGui.SameLine()
                    ImGui.SetCursorPosX(self.streamingPropertyWidth)
                    self.streamingRefPoint.x, _, _ = style.trackedDragFloat(self.object, "##streamingRefPointX", self.streamingRefPoint.x, 0.05, -99999, 99999, "%.2f X", 75)
                    ImGui.SameLine()
                    self.streamingRefPoint.y, _, _ = style.trackedDragFloat(self.object, "##streamingRefPointY", self.streamingRefPoint.y, 0.05, -99999, 99999, "%.2f Y", 75)
                    ImGui.SameLine()
                    self.streamingRefPoint.z, _, _ = style.trackedDragFloat(self.object, "##steamingRefPoinZ", self.streamingRefPoint.z, 0.05, -99999, 99999, "%.2f Z", 75)
                    ImGui.SameLine()
                    if style.drawNoBGConditionalButton(true, IconGlyphs.AccountArrowLeftOutline) then
                        history.addAction(history.getElementChange(self.object))
                        self.streamingRefPoint = gameUtils.getPlayerPosition(editor.active)
                    end
                    style.tooltip("Set the streaming reference point to the player position")
                end

                ImGui.TreePop()
            end
        end
    })

    return properties
end

function spawnable:getGroupedProperties()
    local properties = {}

	properties["streamingProperties"] = {
		name = "World Node",
        id = "worldNode",
		data = {
            multiplier = 1,
            presetIndex = 0,
            maxPropertyWidth = nil
        },
		draw = function(element, entries)
            if not element.groupOperationData["streamingProperties"].maxPropertyWidth then
                element.groupOperationData["streamingProperties"].maxPropertyWidth = utils.getTextMaxWidth({ "Streaming Distances", "Distances Multiplier", "Distance Preset", "NodeRef's", "Custom Reference Point", "Streaming Ref. Point" }) + ImGui.GetStyle().ItemSpacing.x * 4 + ImGui.GetCursorPosX()
            end

            style.mutedText("NodeRef's")
            ImGui.SameLine()
            ImGui.SetCursorPosX(element.groupOperationData["streamingProperties"].maxPropertyWidth)
            if ImGui.Button("Auto-Generate") then
                history.addAction(history.getMultiSelectChange(entries))

                for _, entry in ipairs(entries) do
                    local generated = registry.generate(entry.spawnable.object)
                    entry.spawnable.nodeRef = generated
                end
                registry.invalidate()

                ImGui.ShowToast(ImGui.Toast.new(ImGui.ToastType.Success, 2500, string.format("Auto-Generated NodeRef's for %s nodes", #entries)))
            end

            if ImGui.TreeNodeEx("Streaming Distances", ImGuiTreeNodeFlags.SpanFullWidth) then
                style.mutedText("Distance Preset")
                ImGui.SameLine()
                ImGui.SetCursorPosX(element.groupOperationData["streamingProperties"].maxPropertyWidth)
                ImGui.SetNextItemWidth(140 * style.viewSize)
                element.groupOperationData["streamingProperties"].presetIndex = ImGui.Combo("##groupStreamingDistancePreset", element.groupOperationData["streamingProperties"].presetIndex, streamingPresetLabels, #streamingPresetLabels)
                style.comboValueTooltip(element.groupOperationData["streamingProperties"].presetIndex, streamingPresetLabels, "Quickly set Streaming Distance to a common value.\n- Interior | 100: Small rooms and indoor props loaded only when close.\n- Street | 400: Regular city assets visible from nearby streets.\n- District | 1000: Medium-large city chunks visible across a wider district area.\n- Landscape | 5000: Large outdoor landmarks visible from far away.\n- To the Moon | infinite: Keep visible from anywhere; use only for very important assets.")
                ImGui.SameLine()
                if ImGui.Button("Apply##groupStreamingDistancePreset") then
                    history.addAction(history.getMultiSelectChange(entries))

                    local preset = streamingPresetValues[(element.groupOperationData["streamingProperties"].presetIndex or 0) + 1]
                    for _, entry in ipairs(entries) do
                        entry.spawnable.primaryRange = preset or entry.spawnable.primaryRange
                        entry.spawnable.streamingPresetIndex = element.groupOperationData["streamingProperties"].presetIndex or entry.spawnable.streamingPresetIndex
                    end

                    ImGui.ShowToast(ImGui.Toast.new(ImGui.ToastType.Success, 2500, string.format("Applied streaming distance preset to %s nodes", #entries)))
                end
                style.tooltip("Apply the selected preset to Streaming Distance.")

                style.mutedText("Distances Multiplier")
                ImGui.SetNextItemWidth(80 * style.viewSize)
                ImGui.SameLine()
                ImGui.SetCursorPosX(element.groupOperationData["streamingProperties"].maxPropertyWidth)
                element.groupOperationData["streamingProperties"].multiplier, _ = ImGui.DragFloat("##groupStreamingDistancesMultiplier", element.groupOperationData["streamingProperties"].multiplier, 0.01, 0, 50, "x%.2f")
                style.tooltip("Multiplier for streaming values, when using \"Auto-Set\"")
                ImGui.SameLine()
                if ImGui.Button("Auto-Set") then
                    history.addAction(history.getMultiSelectChange(entries))

                    for _, entry in ipairs(entries) do
                        local values = entry.spawnable:calculateStreamingValues(element.groupOperationData["streamingProperties"].multiplier * entry.spawnable.streamingMultiplier)

                        entry.spawnable.primaryRange = values.primary
                    end

                    ImGui.ShowToast(ImGui.Toast.new(ImGui.ToastType.Success, 2500, string.format("Auto-Set streaming distance for %s nodes", #entries)))
                end

                style.mutedText("Custom Reference Point")
                ImGui.SameLine()
                ImGui.SetCursorPosX(element.groupOperationData["streamingProperties"].maxPropertyWidth)
                if ImGui.Button("On") then
                    history.addAction(history.getMultiSelectChange(entries))

                    for _, entry in ipairs(entries) do
                        entry.spawnable.streamingRefPointOverride = true
                    end

                    ImGui.ShowToast(ImGui.Toast.new(ImGui.ToastType.Success, 2500, string.format("[On] Enabled custom reference point for %s nodes", #entries)))
                end
                ImGui.SameLine()
                if ImGui.Button("Off") then
                    history.addAction(history.getMultiSelectChange(entries))

                    for _, entry in ipairs(entries) do
                        entry.spawnable.streamingRefPointOverride = false
                    end

                    ImGui.ShowToast(ImGui.Toast.new(ImGui.ToastType.Success, 2500, string.format("[Off] Disabled custom reference point for %s nodes", #entries)))
                end

                style.mutedText("Streaming Ref. Point")
                ImGui.SameLine()
                ImGui.SetCursorPosX(element.groupOperationData["streamingProperties"].maxPropertyWidth)
                if ImGui.Button("To Player Position") then
                    history.addAction(history.getMultiSelectChange(entries))

                    for _, entry in ipairs(entries) do
                        entry.spawnable.streamingRefPoint = gameUtils.getPlayerPosition(editor.active)
                    end

                    ImGui.ShowToast(ImGui.Toast.new(ImGui.ToastType.Success, 2500, string.format("Set Streaming Ref. Point to player position for %s nodes", #entries)))
                end

                ImGui.TreePop()
            end
		end,
		entries = { self.object }
	}

    return properties
end

---Returns the world position of a left corner of the asset preview, which shall act as anchor for its HUD text
---@param vertical number? 1 for the top left corner (default), -1 for the bottom left one
function spawnable:getAssetPreviewTextAnchor(vertical)
    return self.position
end

--Should be called once getAssetPreviewTextAnchor will return the correct position (BBOX loaded)
function spawnable:setAssetPreviewTextPostition()
    if not preview.elements["previewFirstLine"] then return end

    local x, y = editor.camera.worldToScreen(self:getAssetPreviewTextAnchor(1))

    local width, height = GetDisplayResolution()
    local factor = width / 2560
    local rx, ry = (x + 1) * width / 2, (- y + 1) * height / 2

    ry = ry + 20 * factor
    rx = rx + 20 * factor

    preview.elements["previewFirstLine"]:SetTranslation(rx, ry)
    preview.elements["previewSecondLine"]:SetTranslation(rx, ry + 40 * factor)
    preview.elements["previewThirdLine"]:SetTranslation(rx, ry + 80 * factor)

    -- The control hint hugs the bottom left corner instead, stacking upwards from it
    local lineCount = preview.controlsLineCount
    if lineCount > 0 then
        local bottomX, bottomY = editor.camera.worldToScreen(self:getAssetPreviewTextAnchor(-1))
        local bx = (bottomX + 1) * width / 2 + 20 * factor
        local by = (- bottomY + 1) * height / 2 - 60 * factor

        for line = 1, lineCount do
            local element = preview.elements[preview.getControlsLineKey(line)]
            if element then
                element:SetTranslation(bx, by - (lineCount - line) * 40 * factor)
            end
        end
    end
end

---Position where the asset preview should be spawned, the actual entity position
---@protected
---@param distance number?
function spawnable:getAssetPreviewPosition(distance)
    if self.assetPreviewType == "backdrop" then
        return editor.getForward((distance or 1) * (68 / (editor.getCameraFOV() or 68)))
    end
    return self.position
end

--Attach any custom components needed
function spawnable:assetPreviewAssemble(entity)
end

--Assumes entity is fully spawned and BBOX is loaded, set to proper position. Called each frame.
function spawnable:assetPreviewSetPosition()
    self.position = self:getAssetPreviewPosition()
    self:update()
end

---Asset preview can be either not enabled, use the current position, or a backdrop (Must be implemented by the object)
---@param state boolean
function spawnable:assetPreview(state)
    self.isAssetPreview = true
    if self.assetPreviewType == "none" then return end

    if state then
        -- Needed, to avoid text being off due to screen curvature effect
        if self.assetPreviewType == "backdrop" and editor.active then
            self.assetPreviewLensDistortion = GameSettings.Get("/accessibility/interface/LensDistortionOverride")
            GameSettings.Set("/accessibility/interface/LensDistortionOverride", true)
        end
        if self.assetPreviewType == "backdrop" then
            self.position = utils.addVector(editor.getCameraPosition() or self.position, Vector4.new(0, 0, -50, 0))
        end
        -- Only move into position once bbox is loaded, see first assetPreviewSetPosition call
        self:spawn()
        self:registerSpawnedAndAttachedCallback(function ()
            self:assetPreviewSetPosition()
            self:setAssetPreviewTextPostition()
        end)
    else
        if self.assetPreviewType == "backdrop" and preview.elements["previewFirstLine"] then
            preview.elements["previewFirstLine"]:SetVisible(false)
            preview.elements["previewSecondLine"]:SetVisible(false)
            preview.elements["previewThirdLine"]:SetVisible(false)
            preview.setControlsHint(nil)
            if editor.active then GameSettings.Set("/accessibility/interface/LensDistortionOverride", self.assetPreviewLensDistortion) end
        end
        self:despawn()
    end
end

---Gets the actual physical size of the spawnable, usually BBOX
---@return table {x, y, z}
function spawnable:getSize()
    return { x = 1, y = 1, z = 1 }
end

---Dimensions of the underlying asset, before any scale is applied.
---Only asset backed spawnables (mesh, entity, ...) have one, everything whose size is defined by
---its own parameters (fog, occluder, colliders, ...) returns nil.
---@return table? {x, y, z}
function spawnable:getBaseSize()
    return nil
end

function spawnable:getBBox()
    local size = self:getSize()
    return {
        min = { x = -size.x / 2, y = -size.y / 2, z = -size.z / 2 },
        max = { x = size.x / 2, y = size.y / 2, z = size.z / 2 }
    }
end

function spawnable:getArrowSize()
    local size = self:getSize()
    local max = math.min(math.max(size.x, size.y, size.z, 0.75) * 0.4, 1)
    return { x = max, y = max, z = max }
end

-- Positioning-arrow scaling constants (see spawnable:getArrowDistanceFactor).
local ARROW_REFERENCE_DISTANCE = 5.0 -- Camera distance (m) at which the base arrow size is kept as-is (factor 1).
local ARROW_MIN_FACTOR = 0.5        -- Never shrink arrows below this fraction of their base size.
local ARROW_MAX_FACTOR = 14.0        -- Cap growth so very distant objects don't spawn huge arrows.
local ARROW_QUANT_STEP = 1.12        -- Geometric bucket size (~12%) used to quantize the factor and avoid per-frame re-toggling.

---Computes the scale factor applied to the positioning-arrow gizmo.
---With distance scaling enabled this keeps the arrows at a roughly constant on-screen size by
---growing them proportionally to the camera distance. The result is quantized into geometric
---buckets so the gizmo only needs to be refreshed when it crosses a bucket, preventing flicker.
---Distance scaling only applies in editor mode: it exists for the free editor camera, and outside
---editor mode nothing drives a per-frame rescale, so a distance factor there would just freeze at
---whatever the camera last saw. Always multiplied by the user `arrowSizeMultiplier`, so the
---multiplier applies even when distance scaling is off or the editor is closed.
---@return number factor
function spawnable:getArrowDistanceFactor()
    local multiplier = settings.arrowSizeMultiplier or 1.0

    if not settings.arrowScaleWithDistance or not editor.active then
        return multiplier
    end

    local player = GetPlayer()
    if not player then return multiplier end
    local cameraComponent = player:GetFPPCameraComponent()
    if not cameraComponent then return multiplier end

    local cameraPosition = cameraComponent:GetLocalToWorld():GetTranslation()
    -- The gizmo sits at the node origin; the bounds centre would move as the node rotates.
    local distance = Vector4.Distance(cameraPosition, self.position)

    local factor = (distance / ARROW_REFERENCE_DISTANCE)
    factor = math.max(ARROW_MIN_FACTOR, math.min(factor, ARROW_MAX_FACTOR))
    -- Snap onto geometric buckets so continuous camera movement only re-scales occasionally.
    factor = ARROW_QUANT_STEP ^ math.floor(math.log(factor) / math.log(ARROW_QUANT_STEP) + 0.5)

    return factor * multiplier
end

---Returns the base arrow size scaled by the current distance/size factor.
---Used both for rendering the gizmo and for building its click hit-boxes so the two stay aligned.
---@param factor number? Precomputed factor from `getArrowDistanceFactor`. Recomputed when omitted.
---@return visualizerScale
function spawnable:getScaledArrowSize(factor)
    factor = factor or self:getArrowDistanceFactor()
    local base = self:getArrowSize()
    return { x = base.x * factor, y = base.y * factor, z = base.z * factor }
end

function spawnable:getCenter()
    return self.position
end

---Returns the active streaming reference point (node position or overridden reference point)
---@return Vector4
function spawnable:getStreamingReferencePoint()
    if self.streamingRefPointOverride then
        return self.streamingRefPoint
    end

    return self.position
end

function spawnable:calculateIntersection(origin, ray)
    local bbox = self:getBBox()

    if not self:getEntity() then
        return { hit = false }
    end

    local result = intersection.getBoxIntersection(origin, ray, self.position, self.rotation, bbox)

    return {
        hit = result.hit,
        position = result.position,
        unscaledHit = result.position, -- Hit result of intersection test with unmodified bbox, for more accurate drop to surface
        collisionType = "bbox",
        distance = result.distance,
        bBox = bbox,
        objectOrigin = self.position,
        objectRotation = self.rotation,
        normal = result.normal
    }
end

---Calculates the streaming distance values for the spawnable based on getSize()
---@param multiplier number
---@return table {primary, secondary}
function spawnable:calculateStreamingValues(multiplier)
    -- TODO: Maybe make the multiplier scale non-linearly, so small things get boosted less than big things
    -- multiplier = math.min(1, math.max(0, falloffRange * math.log(math.max(0, maxAxis + minSize))))
    local scale = self:getSize()

    local primary = math.max(math.max(scale.x, scale.y, scale.z) * multiplier * 60, 25)
    primary = math.min(primary, 200 * multiplier)
    local secondary = primary * 1.2

    return { primary = primary, secondary = secondary }
end

---Keys that identify the class rather than the object, and so must never be restored from a
---saved payload: the class already set them, and an object saved before a class was renamed
---would otherwise keep displaying its old name forever. `modulePath` is what decides which
---class gets instantiated in the first place, so by the time this runs it is already right.
local classIdentityKeys = {
    dataType = true,
    modulePath = true,
    node = true,
    icon = true,
    description = true,
    previewNote = true,
    spawnDataPath = true
}

---Load data blob, position and rotation for spawning
---@param data table
---@param position Vector4
---@param rotation EulerAngles
function spawnable:loadSpawnData(data, position, rotation)
    for key, value in pairs(data) do
        if self[key] ~= nil and not classIdentityKeys[key] then
            self[key] = value
        end
    end

    self.position = position
    self.rotation = rotation
    self.rotationRelative = data.rotationRelative or false

    local presetIndex = data.streamingPresetIndex or self.streamingPresetIndex or 0
    local presetVersion = data.streamingPresetVersion or 1
    -- Only a saved index can predate the current preset list; a class default is already current.
    if data.streamingPresetIndex and presetVersion < streamingPresetVersion and presetIndex >= 2 then
        presetIndex = presetIndex + 1
    end
    self.streamingPresetIndex = math.min(presetIndex, #streamingPresetLabels - 1)

    -- Freshly spawned assets have no serialized primaryRange, so fall back to the default preset's
    -- value to keep Streaming Distance in sync with the selector. Saved assets carry their own.
    local presetRange = streamingPresetValues[self.streamingPresetIndex + 1]
    self.primaryRange = data.primaryRange or presetRange or self.primaryRange or 100

    self.streamingRefPointOverride = data.streamingRefPointOverride or false
    self.streamingRefPoint = data.streamingRefPoint and utils.getVector(data.streamingRefPoint) or Vector4.new(0, 0, 0, 0)

    -- Before any subclass gets to load its own data off the same asset, so a subclass can skip
    -- that work (resource loads, appearance lookups) for an asset that will never spawn.
    self:refreshAssetCheck()
end

---Export the spawnable for WScript import, using same structure for `data` as JSON formated node
---@param key integer Index of the object in the group
---@param length integer Amount of objects in the group
---@return table {position, rotation, scale, type, data}
function spawnable:export(key, length)
    return {
        position = utils.fromVector(self.position),
        streamingRefPoint = utils.fromVector(self:getStreamingReferencePoint()),
        rotation = utils.fromQuaternion(self.rotation:ToQuat()),
        scale = { x = 1, y = 1, z = 1 },
        primaryRange = self.primaryRange,
        secondaryRange = self.primaryRange * 0.85,
        nodeRef = self.nodeRef,
        type = "worldEntityNode",
        name = "[" .. self.dataType .. "] " .. self.object.name,
        data = {
            entityTemplate = {
                DepotPath = {
                    ["$type"] = "ResourcePath",
                    ["$storage"] = "string",
                    ["$value"] = self.spawnData
                }
            },
            appearanceName = {
                ["$type"] = "CName",
                ["$storage"] = "string",
                ["$value"] = self.app
            }
        }
    }
end

---Default streaming preset of a class, in place of the Default Streaming Distance setting; call from `new`.
---@param label string Preset label, e.g. "District".
function spawnable:setDefaultStreamingPreset(label)
    for index, presetLabel in ipairs(streamingPresetLabels) do
        if presetLabel == label then
            self.streamingPresetIndex = index - 1
            self.primaryRange = streamingPresetValues[index]
            return
        end
    end
end

---Nodes exported for this spawnable, in order; most export one.
---@param key integer
---@param length integer
---@return table[] nodes
function spawnable:exportNodes(key, length)
    return { self:export(key, length) }
end

return spawnable
