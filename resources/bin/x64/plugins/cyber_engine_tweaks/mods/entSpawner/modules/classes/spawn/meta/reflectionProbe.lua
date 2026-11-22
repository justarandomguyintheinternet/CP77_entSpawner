local spawnable = require("modules/classes/spawn/spawnable")
local visualized = require("modules/classes/spawn/visualized")
local style = require("modules/ui/style")
local visualizer = require("modules/utils/preview/visualizer")
local probePool = require("modules/utils/preview/probePool")
local utils = require("modules/utils/core/utils")
local lcHelper = require("modules/utils/ui/lightChannelHelper")
local config = require("modules/utils/core/config")
local history = require("modules/utils/project/history")
local envProbeOptionsCache = nil
local envProbeOptionSetCache = nil
local envProbeLowerCache = nil

-- The engine adds this to an entEnvProbeComponent's priority.
local COMPONENT_PRIORITY_OFFSET = 32
-- Vanilla median of streamingDistance over the largest Scale component (the box half-size).
local STREAMING_DISTANCE_FACTOR = 3.6

local componentPreviewGaps = "Ambient Mode, Reflection Dimming, Sky Scale, Volumetric Fog Ambient, Simple Fog, Capture Offset, No Fade Blend, Sub Scene and priorities below " .. COMPONENT_PRIORITY_OFFSET

---Class for worldReflectionProbeNode
---@class reflection : visualized
---@field public scale {x: number, y: number, z: number}
---@field public edgeScale {x: number, y: number, z: number}
---@field private previewed boolean
---@field private ambientModes table
---@field private neighborModes table
---@field public ambientMode integer
---@field public neighborMode integer
---@field public emissiveScale number
---@field public streamingDistance number
---@field public streamingHeight number
---@field public priority number
---@field public globalProbe boolean
---@field public boxProjection boolean
---@field public allInShadow boolean
---@field public hideSkyColor boolean
---@field public skyScale number
---@field public reflectionDimming number
---@field public volFogAmbient boolean
---@field public brightnessEVClamp integer
---@field public simpleFogColor {r: number, g: number, b: number}
---@field public simpleFogDensity number
---@field public captureOffset {x: number, y: number, z: number}
---@field public blendRange integer
---@field public noFadeBlend boolean
---@field public subScene boolean
---@field public maxPropertyWidth number
---@field public lightChannels boolean[]
---@field public volumeChannels boolean[]
---@field private nodePreview boolean Preview runs on a placeholder node instead of a component.
---@field private nodePreviewFallback string? Why the preview fell back to the component.
---@field private nodePreviewSignature string?
---@field private envProbeOptions string[]?
---@field private envProbeSearch string
---@field private envProbeFilterCache {query: string, results: string[]}?
local reflection = setmetatable({}, { __index = visualized })

---@param value string?
---@return string
local function normalizeProbePath(value)
    return utils.normalizePath(value, { separator = "backslash" })
end

---@param v {x: number, y: number, z: number}
---@return table
local function jsonVector3(v)
    return { ["$type"] = "Vector3", ["X"] = v.x, ["Y"] = v.y, ["Z"] = v.z }
end

function reflection:new()
	local o = visualized.new(self)

    o.spawnListType = "list"
    o.dataType = "Reflection Probe"
    o.spawnDataPath = "data/spawnables/meta/reflectionProbe/"
    o.modulePath = "meta/reflectionProbe"
    o.node = "worldReflectionProbeNode"
    o.description = "Places a reflection probe of variable size. Can be used to make indoors have appropriate base lighting."
    o.icon = IconGlyphs.HomeLightbulbOutline

    -- Spawn New shows a single generic entry instead of the envprobe path browser.
    -- The concrete envprobe can be changed later in node properties.
    o.collapseSpawnList = true
    o.collapsedSpawnListLabel = "Reflection Probe - Default"

    o.scale = { x = 5, y = 5, z = 5 }
    o.edgeScale = { x = 0.98, y = 0.98, z = 0.98 }
    o.previewed = true
    o.previewShape = "box"

    o.ambientModes = utils.enumTable("envUtilsReflectionProbeAmbientContributionMode")
    o.neighborModes = utils.enumTable("envUtilsNeighborMode")

    o.ambientMode = 3
    o.neighborMode = 3
    o.emissiveScale = 1
    o.streamingDistance = 64
    o.streamingHeight = -1
    o.priority = 10
    o.globalProbe = false
    o.boxProjection = true
    o.allInShadow = false
    o.hideSkyColor = false
    o.skyScale = 1
    o.reflectionDimming = 1
    o.volFogAmbient = true
    o.brightnessEVClamp = 8
    o.simpleFogColor = { r = 1, g = 1, b = 1 }
    o.simpleFogDensity = 0
    o.captureOffset = { x = 0, y = 0, z = 0 }
    o.blendRange = 20
    o.noFadeBlend = false
    o.subScene = false
    o.lightChannels = { true, true, true, true, true, true, true, true, true, false, false, false }
    o.volumeChannels = { true, true, true, true, true, true, true, true, true, false, false, false }

    o.nodePreview = false
    o.nodePreviewFallback = nil
    o.nodePreviewSignature = nil

    o.maxPropertyWidth = nil
    o.envProbeOptions = nil
    o.envProbeSearch = ""
    o.envProbeFilterCache = nil

    setmetatable(o, { __index = self })
   	return o
end

function reflection:loadEnvProbeOptions()
    if self.envProbeOptions then
        return
    end

    if not envProbeOptionsCache or not envProbeOptionSetCache then
        envProbeOptionsCache = {}
        envProbeOptionSetCache = {}
        envProbeLowerCache = {}
        local entries = config.loadLists(self.spawnDataPath) or {}

        for _, entry in ipairs(entries) do
            local path = normalizeProbePath(entry and entry.data and entry.data.spawnData or entry and entry.name)
            if path ~= "" then
                local key = string.lower(path)
                if not envProbeOptionSetCache[key] then
                    envProbeOptionSetCache[key] = true
                    envProbeLowerCache[path] = key
                    table.insert(envProbeOptionsCache, path)
                end
            end
        end
    end
    if not envProbeLowerCache then
        envProbeLowerCache = {}
        for _, option in ipairs(envProbeOptionsCache or {}) do
            envProbeLowerCache[option] = string.lower(option)
        end
    end

    self.envProbeOptions = envProbeOptionsCache
end

---@param searchValue string?
---@return string[]
function reflection:getFilteredEnvProbeOptions(searchValue)
    self:loadEnvProbeOptions()

    local options = self.envProbeOptions or {}
    local query = string.lower(utils.trimString(searchValue))
    if query == "" then
        self.envProbeFilterCache = {
            query = "",
            results = options
        }
        return options
    end

    local source = options
    local filterCache = self.envProbeFilterCache
    if filterCache and filterCache.results then
        local previousQuery = filterCache.query or ""
        if previousQuery ~= "" and query:sub(1, #previousQuery) == previousQuery then
            source = filterCache.results
        end
    end

    local results = {}
    for _, option in ipairs(source) do
        local optionLower = (envProbeLowerCache and envProbeLowerCache[option]) or string.lower(option)
        if string.find(optionLower, query, 1, true) then
            table.insert(results, option)
        end
    end

    self.envProbeFilterCache = {
        query = query,
        results = results
    }

    return results
end

---@return string[]
function reflection:getEnvProbeSelectorOptions()
    self:loadEnvProbeOptions()
    return self.envProbeOptions or {}
end

---@param probePath string
---@param recordHistory boolean?
---@return boolean changed
function reflection:setEnvProbe(probePath, recordHistory)
    local nextProbe = normalizeProbePath(probePath)
    if nextProbe == "" or nextProbe == self.spawnData then
        return false
    end

    if recordHistory and self.object then
        history.addAction(history.getElementChange(self.object))
    end

    self.spawnData = nextProbe
    self:refreshPreview()

    return true
end

---Selects an adjacent envprobe resource, wrapping at either end of the list.
---@param direction integer? Positive selects the next resource; negative selects the previous one.
---@return boolean changed
function reflection:cycleEnvProbe(direction)
    local options = self:getEnvProbeSelectorOptions()
    local optionCount = #options
    if optionCount <= 1 then
        return false
    end

    direction = (tonumber(direction) or 1) < 0 and -1 or 1

    local currentIndex = utils.indexValue(options, normalizeProbePath(self.spawnData))
    if type(currentIndex) ~= "number" or currentIndex < 1 or currentIndex > optionCount then
        currentIndex = direction > 0 and 0 or 1
    end

    local nextIndex = ((currentIndex - 1 + direction) % optionCount) + 1

    return self:setEnvProbe(options[nextIndex], true)
end

---Node property values shared by the export and the node preview.
---@return table
function reflection:getNodeProperties()
    return {
        probeDataRef = self.spawnData,
        priority = math.floor(self.priority),
        globalProbe = self.globalProbe,
        boxProjection = self.boxProjection,
        neighborMode = self.neighborModes[self.neighborMode],
        edgeScale = { x = self.edgeScale.x, y = self.edgeScale.y, z = self.edgeScale.z },
        lightChannels = utils.deepcopy(self.lightChannels),
        emissiveScale = self.emissiveScale,
        reflectionDimming = self.reflectionDimming,
        simpleFogColor = { r = self.simpleFogColor.r, g = self.simpleFogColor.g, b = self.simpleFogColor.b },
        simpleFogDensity = self.simpleFogDensity,
        skyScale = self.skyScale,
        allInShadow = self.allInShadow,
        hideSkyColor = self.hideSkyColor,
        volFogAmbient = self.volFogAmbient,
        brightnessEVClamp = math.floor(self.brightnessEVClamp),
        ambientMode = self.ambientModes[self.ambientMode],
        captureOffset = { x = self.captureOffset.x, y = self.captureOffset.y, z = self.captureOffset.z },
        volumeChannels = utils.deepcopy(self.volumeChannels),
        blendRange = math.floor(self.blendRange),
        streamingDistance = self.streamingDistance,
        streamingHeight = self.streamingHeight,
        subScene = self.subScene,
        noFadeBlend = self.noFadeBlend
    }
end

---Writes node property values onto a worldReflectionProbeNode definition.
---@param definition worldReflectionProbeNode
---@param props table From `getNodeProperties`.
local function writeNodeDefinition(definition, props)
    local fogColor = HDRColor.new()
    fogColor.Red = props.simpleFogColor.r
    fogColor.Green = props.simpleFogColor.g
    fogColor.Blue = props.simpleFogColor.b
    fogColor.Alpha = 1

    definition.probeDataRef = ResRef.FromString(props.probeDataRef or "")
    definition.priority = props.priority
    definition.globalProbe = props.globalProbe
    definition.boxProjection = props.boxProjection
    definition.neighborMode = Enum.new("envUtilsNeighborMode", props.neighborMode)
    definition.edgeScale = Vector3.new(props.edgeScale.x, props.edgeScale.y, props.edgeScale.z)
    definition.lightChannels = lcHelper.getMask(props.lightChannels)
    definition.emissiveScale = props.emissiveScale
    definition.reflectionDimming = props.reflectionDimming
    definition.simpleFogColor = fogColor
    definition.simpleFogDensity = props.simpleFogDensity
    definition.skyScale = props.skyScale
    definition.allInShadow = props.allInShadow
    definition.hideSkyColor = props.hideSkyColor
    definition.volFogAmbient = props.volFogAmbient
    definition.brightnessEVClamp = props.brightnessEVClamp
    definition.ambientMode = Enum.new("envUtilsReflectionProbeAmbientContributionMode", props.ambientMode)
    definition.captureOffset = Vector3.new(props.captureOffset.x, props.captureOffset.y, props.captureOffset.z)
    definition.volumeChannels = lcHelper.getMask(props.volumeChannels)
    definition.blendRange = props.blendRange
    definition.streamingDistance = props.streamingDistance
    definition.streamingHeight = props.streamingHeight
    definition.subScene = props.subScene
    definition.noFadeBlend = props.noFadeBlend
end

---Adds the approximate component preview, used when no placeholder node is available.
---@param entity entEntity
function reflection:addPreviewComponent(entity)
    local props = self:getNodeProperties()

    local component = entEnvProbeComponent.new()
    component.name = "probe"
    component.probeDataRef = ResRef.FromString(self.spawnData)
    component.priority = math.max(0, props.priority - COMPONENT_PRIORITY_OFFSET)
    component.globalProbe = props.globalProbe
    component.boxProjection = props.boxProjection
    component.allInShadow = props.allInShadow
    component.hideSkyColor = props.hideSkyColor
    component.size = Vector3.new(self.scale.x, self.scale.y, self.scale.z)
    component.edgeScale = Vector3.new(props.edgeScale.x, props.edgeScale.y, props.edgeScale.z)
    component.neighborMode = Enum.new("envUtilsNeighborMode", props.neighborMode)
    component.emissiveScale = props.emissiveScale
    component.streamingDistance = props.streamingDistance
    component.streamingHeight = props.streamingHeight
    component.blendRange = props.blendRange
    -- Uint8 on the component, Int8 on the node: same byte.
    component.brightnessEVClamp = props.brightnessEVClamp % 256
    component.lightChannels = lcHelper.getMask(props.lightChannels)
    component.volumeChannels = lcHelper.getMask(props.volumeChannels)
    entity:AddComponent(component)
end

---Whether this probe should preview through a placeholder node.
---@return boolean
function reflection:canUseNodePreview()
    return not self.isAssetPreview and self.nodePreviewFallback == nil and probePool.isAvailable()
end

---@return string
function reflection:getNodePreviewSignature()
    local parts = { tostring(self.spawnData) }
    local function add(...)
        for _, value in ipairs({ ... }) do
            table.insert(parts, tostring(value))
        end
    end

    add(self.position.x, self.position.y, self.position.z)
    add(self.rotation.roll, self.rotation.pitch, self.rotation.yaw)
    add(self.scale.x, self.scale.y, self.scale.z)

    for key, value in pairs(self:getNodeProperties()) do
        if type(value) == "table" then
            local entries = {}
            for k, v in pairs(value) do
                table.insert(entries, tostring(k) .. "=" .. tostring(v))
            end
            table.sort(entries)
            value = table.concat(entries, ",")
        end
        table.insert(parts, key .. "=" .. tostring(value))
    end
    table.sort(parts)

    return table.concat(parts, "|")
end

---Sends the current state to the placeholder node, if anything changed.
---@return boolean ok False when the pool refused it.
function reflection:submitNodePreview()
    if not self.nodePreview then return true end

    local signature = self:getNodePreviewSignature()
    if signature == self.nodePreviewSignature then return true end

    local props = self:getNodeProperties()
    local queued = probePool.submit(self, {
        position = Vector4.new(self.position.x, self.position.y, self.position.z, 1),
        orientation = self.rotation:ToQuat(),
        scale = { x = self.scale.x, y = self.scale.y, z = self.scale.z },
        write = function(definition)
            writeNodeDefinition(definition, props)
        end
    })
    if not queued then return false end

    self.nodePreviewSignature = signature
    return true
end

---Submits the current state, or switches to the component preview if the pool refuses it.
function reflection:syncNodePreview()
    if not self:submitNodePreview() then
        self:onProbePreviewUnavailable()
    end
end

---Called by the pool when no placeholder node can show this probe.
function reflection:onProbePreviewUnavailable()
    self.nodePreviewFallback = probePool.lastReason ~= "" and probePool.lastReason or "No probe placeholder is available."
    probePool.release(self)
    self:respawn()
end

---Called by the pool when a slot frees up after this probe fell back for lack of one.
function reflection:onProbePreviewSlotFree()
    if self.nodePreviewFallback and self:isSpawned() then
        self:retryNodePreview()
    end
end

---Applies a property change to whichever preview is active.
function reflection:refreshPreview()
    if self.nodePreview and self:isSpawned() then
        self:syncNodePreview()
    else
        self:respawn()
    end
end

---Called by the grouped light channel operation.
function reflection:onLightChannelsChanged()
    self:refreshPreview()
end

---Whether the last widget's edit should be applied: on release, or on a step button click.
---@param changed boolean
---@param finished boolean
---@return boolean
local function editDone(changed, finished)
    return finished or (changed and not ImGui.IsItemActive())
end

---Drops the component fallback and tries the placeholder node again.
function reflection:retryNodePreview()
    self.nodePreviewFallback = nil
    self:respawn()
end

function reflection:onAssemble(entity)
    spawnable.onAssemble(self, entity)

    visualizer.addBox(entity, { x = self.scale.x, y = self.scale.y, z = self.scale.z }, "seashell")

    self.nodePreview = self:canUseNodePreview()
    self.nodePreviewSignature = nil
    if self.nodePreview and not self:submitNodePreview() then
        self.nodePreview = false
    end
    if not self.nodePreview then
        self:addPreviewComponent(entity)
    end

    visualizer.updateScale(entity, self:getArrowSize(), "arrows")
    visualizer.toggleAll(entity, self.previewed)
end

function reflection:spawn()
    self:spawnAsPlaceholderEntity()
end

function reflection:despawn()
    probePool.release(self)
    self.nodePreview = false
    self.nodePreviewSignature = nil
    spawnable.despawn(self)
end

function reflection:update()
    spawnable.update(self)
    self:syncNodePreview()
end

-- Table fields that loadSpawnData would otherwise share with its long-lived payload.
local ownedTableFields = { "scale", "edgeScale", "captureOffset", "simpleFogColor", "lightChannels", "volumeChannels" }

function reflection:loadSpawnData(data, position, rotation)
    visualized.loadSpawnData(self, data, position, rotation)

    for _, key in ipairs(ownedTableFields) do
        self[key] = utils.deepcopy(self[key])
    end
end

function reflection:save()
    local data = visualized.save(self)

    data.scale = { x = self.scale.x, y = self.scale.y, z = self.scale.z }
    data.edgeScale = { x = self.edgeScale.x, y = self.edgeScale.y, z = self.edgeScale.z }
    data.ambientMode = self.ambientMode
    data.neighborMode = self.neighborMode
    data.emissiveScale = self.emissiveScale
    data.streamingDistance = self.streamingDistance
    data.streamingHeight = self.streamingHeight
    data.allInShadow = self.allInShadow
    data.priority = self.priority
    data.globalProbe = self.globalProbe
    data.boxProjection = self.boxProjection
    data.hideSkyColor = self.hideSkyColor
    data.skyScale = self.skyScale
    data.reflectionDimming = self.reflectionDimming
    data.volFogAmbient = self.volFogAmbient
    data.brightnessEVClamp = self.brightnessEVClamp
    data.simpleFogColor = { r = self.simpleFogColor.r, g = self.simpleFogColor.g, b = self.simpleFogColor.b }
    data.simpleFogDensity = self.simpleFogDensity
    data.captureOffset = { x = self.captureOffset.x, y = self.captureOffset.y, z = self.captureOffset.z }
    data.blendRange = self.blendRange
    data.noFadeBlend = self.noFadeBlend
    data.subScene = self.subScene
    data.lightChannels = utils.deepcopy(self.lightChannels)
    data.volumeChannels = utils.deepcopy(self.volumeChannels)

    return data
end

---@protected
function reflection:updateScale(finished)
    if finished then
        self:refreshPreview()
        return
    end

    local entity = self:getEntity()
    if not entity then return end

    visualizer.updateScale(entity, self:getArrowSize(), "arrows")
    visualizer.updateScale(entity, { x = self.scale.x, y = self.scale.y, z = self.scale.z }, "box")
    self:syncNodePreview()
end

---Scale is the half-size: the influence box spans ±Scale, as measured in game for the node and the component.
function reflection:getSize()
    return { x = self.scale.x * 2, y = self.scale.y * 2, z = self.scale.z * 2 }
end

---Draws a muted label and moves the cursor to the property column.
---@param label string
function reflection:propertyLabel(label)
    style.mutedText(label)
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
end

---@param label string
---@param id string
---@param key string Boolean field name.
---@param tooltip string?
function reflection:drawCheckboxProperty(label, id, key, tooltip)
    self:propertyLabel(label)
    local changed
    self[key], changed = style.trackedCheckbox(self.object, id, self[key])
    if tooltip then style.tooltip(tooltip) end
    if changed then
        self:refreshPreview()
    end
end

---@param label string
---@param id string
---@param key string Number field name.
---@param step number
---@param min number
---@param max number
---@param format string
---@param tooltip string?
function reflection:drawFloatProperty(label, id, key, step, min, max, format, tooltip)
    self:propertyLabel(label)
    local finished
    self[key], _, finished = style.trackedDragFloat(self.object, id, self[key], step, min, max, format, 80)
    if tooltip then style.tooltip(tooltip) end
    if finished then
        self:refreshPreview()
    end
end

---@param label string
---@param idPrefix string
---@param key string Vector field name.
---@param step number
---@param min number
---@param max number
---@param format string
function reflection:drawVectorProperty(label, idPrefix, key, step, min, max, format)
    self:propertyLabel(label)
    local vector = self[key]
    for index, axis in ipairs({ "x", "y", "z" }) do
        if index > 1 then ImGui.SameLine() end
        local finished
        vector[axis], _, finished = style.trackedDragFloat(self.object, idPrefix .. axis, vector[axis], step, min, max, format .. " " .. axis:upper(), 60)
        if finished then
            self:refreshPreview()
        end
    end
end

function reflection:drawPreviewStatus()
    self:propertyLabel("Preview")

    if self.nodePreview then
        local status = probePool.getStatus(self)
        if status == "active" then
            style.styledText(IconGlyphs.CheckCircleOutline .. " Exact", style.successColor)
            style.tooltip("Shown through a World Builder placeholder node, like the exported probe.")
        else
            style.mutedText(IconGlyphs.TimerSandEmpty .. " Waiting for a placeholder node")
            style.tooltip(probePool.lastReason ~= "" and probePool.lastReason or "The placeholder node is being set up.")
        end
        return
    end

    style.styledText(IconGlyphs.AlertOutline .. " Approximate", style.warnColor)
    local reason = self.nodePreviewFallback or (self.isAssetPreview and "Asset previews use a component." or "Codeware is not installed, or the World Builder archive is out of date.")
    style.tooltip(reason .. "\nThe component preview ignores " .. componentPreviewGaps .. ".")

    if self.nodePreviewFallback then
        ImGui.SameLine()
        style.pushButtonNoBG(true)
        if ImGui.Button(IconGlyphs.Refresh .. "##retryProbeNodePreview") then
            self:retryNodePreview()
        end
        style.pushButtonNoBG(false)
        style.tooltip("Try the placeholder node preview again.")
    end
end

function reflection:draw()
    spawnable.draw(self)

    if not self.maxPropertyWidth then
        self.maxPropertyWidth = utils.getTextMaxWidth({ "Env Probe", "Preview", "Visualize outline", "Ambient Mode", "Neighbor Mode", "Priority", "Global Probe", "Box Projection", "Emissive Scale", "Edge Scale", "All In Shadow", "Hide Sky Color", "Sky Scale", "Reflection Dimming", "Volumetric Fog Ambient", "Brightness EV Clamp", "Simple Fog Color", "Simple Fog Density", "Capture Offset", "Streaming Distance", "Streaming Height", "Blend Range", "No Fade Blend", "Sub Scene" }) + 2 * ImGui.GetStyle().ItemSpacing.x + ImGui.GetCursorPosX()
    end

    style.mutedText("Env Probe")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    local envProbeOptions = self:getEnvProbeSelectorOptions()
    local selectorWidth = style.getRowFieldWidth({ IconGlyphs.SkipPrevious, IconGlyphs.SkipNext }, 260)
    local selectorPixelWidth = selectorWidth * style.viewSize
    local itemWidth = math.max(80, selectorPixelWidth - (2 * ImGui.GetStyle().FramePadding.x) - ImGui.GetStyle().ItemSpacing.x)
    local selectorOptions = self:getFilteredEnvProbeOptions(self.envProbeSearch)
    local selectedProbe = normalizeProbePath(self.spawnData)
    local changed
    selectedProbe, self.envProbeSearch, changed = style.trackedSearchDropdown(
        "##envProbePath",
        "Search envprobe...",
        selectedProbe,
        self.envProbeSearch,
        selectorOptions,
        {
            element = self.object,
            width = selectorWidth,
            matchContentWidth = false,
            allowCustom = true,
            optionDisplayFn = function(optionText)
                return utils.shortenPath(optionText, itemWidth, true)
            end,
            optionTooltipFn = function(optionText)
                return optionText
            end,
            optionExistsFn = function(optionText)
                return envProbeOptionSetCache and envProbeOptionSetCache[string.lower(normalizeProbePath(optionText))] == true
            end,
            optionFilterFn = function(optionText, query)
                local optionLower = (envProbeLowerCache and envProbeLowerCache[optionText]) or string.lower(optionText)
                return string.find(optionLower, query, 1, true) ~= nil
            end,
            tooltip = "Select the envprobe resource used by this reflection probe."
        }
    )

    if changed then
        -- The tracked dropdown already pushed history.
        self:setEnvProbe(selectedProbe, false)
    end

    local greyOut = #envProbeOptions <= 1
    ImGui.SameLine()
    style.pushGreyedOut(greyOut)
    style.pushButtonNoBG(true)
    ImGui.BeginDisabled(greyOut)
    if ImGui.Button(IconGlyphs.SkipPrevious .. "##cyclePreviousEnvProbe") then
        self:cycleEnvProbe(-1)
    end
    style.tooltip("Select the previous envprobe resource.")
    ImGui.SameLine()
    if ImGui.Button(IconGlyphs.SkipNext .. "##cycleNextEnvProbe") then
        self:cycleEnvProbe()
    end
    style.tooltip("Select the next envprobe resource.")
    ImGui.EndDisabled()
    style.pushButtonNoBG(false)
    style.popGreyedOut(greyOut)

    self:drawPreviewStatus()
    self:drawPreviewCheckbox("Visualize outline", self.maxPropertyWidth)

    self:propertyLabel("Ambient Mode")
    local value, changed = style.trackedCombo(self.object, "##ambientMode", self.ambientMode - 1, self.ambientModes, 225)
    style.tooltip("How much of the diffuse ambient light inside the box comes from this probe. OVERRIDE_GI replaces the global illumination.")
    if changed then
        self.ambientMode = value + 1
        self:refreshPreview()
    end

    self:propertyLabel("Neighbor Mode")
    local value, changed = style.trackedCombo(self.object, "##neighborMode", self.neighborMode - 1, self.neighborModes, 112)
    style.tooltip("Which other probes complete this one when relighting and blending.")
    if changed then
        self.neighborMode = value + 1
        self:refreshPreview()
    end

    self:propertyLabel("Priority")
    local finished
    self.priority, changed, finished = style.trackedIntInput(self.object, "##priority", self.priority, 0, 255, 80, 1, 5)
    local priorityDone = editDone(changed, finished)
    style.tooltip("Wins over overlapping probes of lower priority. Vanilla local probes use 1 to 20, district probes 2 or 3.")
    if priorityDone then
        self:refreshPreview()
    end

    self:drawCheckboxProperty("Global Probe", "##globalProbe", "globalProbe", "District-wide probe. Disables box projection.")
    self:drawCheckboxProperty("Box Projection", "##boxProjection", "boxProjection", "Corrects reflection parallax against the box.")
    self:drawFloatProperty("Emissive Scale", "##emissiveScale", "emissiveScale", 0.01, 0, 50, "%.2f", "Multiplies the emissive texels of the envprobe.")
    self:drawVectorProperty("Edge Scale", "##edge", "edgeScale", 0.01, 0, 1, "%.2f")
    style.tooltip("Part of the box at full weight before the fade toward its edges.")

    if ImGui.TreeNodeEx("Look") then
        self:drawCheckboxProperty("All In Shadow", "##allInShadow", "allInShadow", "Treats the whole probe as shadowed from the sun (interiors).")
        self:drawCheckboxProperty("Hide Sky Color", "##hideSkyColor", "hideSkyColor", "Does not tint the probe with the sky color (windowless interiors).")
        self:drawFloatProperty("Sky Scale", "##skyScale", "skyScale", 0.01, 0, 50, "%.2f", "Multiplies the sky texels of the envprobe.")
        self:drawFloatProperty("Reflection Dimming", "##reflectionDimming", "reflectionDimming", 0.01, 0, 1, "%.2f", "Specular reflection factor.")
        self:drawCheckboxProperty("Volumetric Fog Ambient", "##volFogAmbient", "volFogAmbient", "Feeds the ambient light of the volumetric fog.")

        self:propertyLabel("Brightness EV Clamp")
        self.brightnessEVClamp, changed, finished = style.trackedIntInput(self.object, "##brightnessEVClamp", self.brightnessEVClamp, -128, 127, 80, 1, 1)
        local clampDone = editDone(changed, finished)
        style.tooltip("Brightness ceiling in EV.")
        if clampDone then
            self:refreshPreview()
        end

        self:propertyLabel("Simple Fog Color")
        local color, colorChanged, colorFinished = style.trackedColor(self.object, "##simpleFogColor", { self.simpleFogColor.r, self.simpleFogColor.g, self.simpleFogColor.b }, 60)
        local colorDone = editDone(colorChanged, colorFinished)
        self.simpleFogColor = { r = color[1], g = color[2], b = color[3] }
        if colorDone then
            self:refreshPreview()
        end
        self:drawFloatProperty("Simple Fog Density", "##simpleFogDensity", "simpleFogDensity", 0.001, 0, 10, "%.3f", "Simple fog applied by the probe. 0 disables it.")
        ImGui.TreePop()
    end

    if ImGui.TreeNodeEx("Capture") then
        self:drawVectorProperty("Capture Offset", "##captureOffset", "captureOffset", 0.01, -1000, 1000, "%.2f")
        style.tooltip("Offset of the point the envprobe was captured from, relative to the node.")
        ImGui.TreePop()
    end

    if ImGui.TreeNodeEx("Streaming") then
        self:propertyLabel("Streaming Distance")
        self.streamingDistance, _, finished = style.trackedDragFloat(self.object, "##streamingDistance", self.streamingDistance, 0.1, 0, 9999, "%.1f", 80)
        style.tooltip("Distance from which the probe is active.")
        if finished then
            self:refreshPreview()
        end
        ImGui.SameLine()
        if ImGui.Button("Auto##probeStreamingDistance") then
            history.addAction(history.getElementChange(self.object))
            self.streamingDistance = math.floor(STREAMING_DISTANCE_FACTOR * math.max(self.scale.x, self.scale.y, self.scale.z) * 10 + 0.5) / 10
            self:refreshPreview()
        end
        style.tooltip(string.format("%.1f x the largest Scale value (the box half-size), the vanilla median.", STREAMING_DISTANCE_FACTOR))

        self:drawFloatProperty("Streaming Height", "##streamingHeight", "streamingHeight", 0.1, -1, 9999, "%.1f", "Vertical streaming limit. -1 disables it.")

        self:propertyLabel("Blend Range")
        self.blendRange, changed, finished = style.trackedIntInput(self.object, "##blendRange", self.blendRange, 0, 255, 80, 1, 5)
        local blendDone = editDone(changed, finished)
        style.tooltip("Blend range between probes.")
        if blendDone then
            self:refreshPreview()
        end

        self:drawCheckboxProperty("No Fade Blend", "##noFadeBlend", "noFadeBlend", "Shows the probe at once when it streams in.")
        self:drawCheckboxProperty("Sub Scene", "##subScene", "subScene")
        ImGui.TreePop()
    end

    if ImGui.TreeNodeEx("Light Channels") then
        local channels, channelsChanged = style.drawLightChannelsSelector(self.object, self.lightChannels)
        self.lightChannels = channels
        if channelsChanged then
            self:refreshPreview()
        end
        ImGui.TreePop()
    end

    if ImGui.TreeNodeEx("Volume Channels") then
        local channels, channelsChanged = style.drawLightChannelsSelector(self.object, self.volumeChannels)
        self.volumeChannels = channels
        if channelsChanged then
            self:refreshPreview()
        end
        ImGui.TreePop()
    end
end

function reflection:getProperties()
    return self:addNodeProperty(spawnable.getProperties(self))
end

function reflection:getGroupedProperties()
    local properties = spawnable.getGroupedProperties(self)

    properties["visualization"] = {
		name = "Visualization",
        id = "reflection",
		data = {},
		draw = function(_, entries)
            ImGui.Text("Reflection Probe")

            ImGui.SameLine()

            ImGui.PushID("reflection")

			if ImGui.Button("Off") then
				for _, entry in ipairs(entries) do
                    if entry.spawnable.node == "worldReflectionProbeNode" then
                        entry.spawnable:setPreview(false)
                    end
				end
			end

            ImGui.SameLine()

            if ImGui.Button("On") then
				for _, entry in ipairs(entries) do
                    if entry.spawnable.node == "worldReflectionProbeNode" then
                        entry.spawnable:setPreview(true)
                    end
				end
			end

            ImGui.PopID()
		end,
		entries = { self.object }
	}
    properties["lcGrouped"] = lcHelper.getGroupedProperties(self)

    return properties
end

function reflection:export()
    local props = self:getNodeProperties()
    local data = spawnable.export(self)
    data.type = "worldReflectionProbeNode"
    data.scale = self.scale
    data.data = {
        probeDataRef = {
            DepotPath = {
                ["$storage"] = "string",
                ["$value"] = props.probeDataRef
            },
        },
        priority = props.priority,
        globalProbe = props.globalProbe and 1 or 0,
        boxProjection = props.boxProjection and 1 or 0,
        neighborMode = props.neighborMode,
        edgeScale = jsonVector3(props.edgeScale),
        lightChannels = utils.buildBitfieldString(props.lightChannels, style.lightChannelEnum),
        emissiveScale = props.emissiveScale,
        reflectionDimming = props.reflectionDimming,
        simpleFogColor = {
            ["$type"] = "HDRColor",
            ["Red"] = props.simpleFogColor.r,
            ["Green"] = props.simpleFogColor.g,
            ["Blue"] = props.simpleFogColor.b,
            ["Alpha"] = 1
        },
        simpleFogDensity = props.simpleFogDensity,
        skyScale = props.skyScale,
        allInShadow = props.allInShadow and 1 or 0,
        hideSkyColor = props.hideSkyColor and 1 or 0,
        volFogAmbient = props.volFogAmbient and 1 or 0,
        brightnessEVClamp = props.brightnessEVClamp,
        ambientMode = props.ambientMode,
        captureOffset = jsonVector3(props.captureOffset),
        volumeChannels = utils.buildBitfieldString(props.volumeChannels, style.lightChannelEnum),
        blendRange = props.blendRange,
        streamingDistance = props.streamingDistance,
        streamingHeight = props.streamingHeight,
        subScene = props.subScene and 1 or 0,
        noFadeBlend = props.noFadeBlend and 1 or 0
    }

    return data
end

return reflection
