local visualized = require("modules/classes/spawn/visualized")
local style = require("modules/ui/style")
local utils = require("modules/utils/utils")
local history = require("modules/utils/history")

---Class for worldStaticLightNode
---@class light : visualized
---@field public color {r: number, g: number, b: number}
---@field public intensity number
---@field public innerAngle number
---@field public outerAngle number
---@field public radius number
---@field public capsuleLength number
---@field public autoHideDistance number
---@field public flickerStrength number
---@field public flickerPeriod number
---@field public flickerOffset number
---@field public lightType integer
---@field public localShadows boolean
---@field private lightTypes table
---@field private temperature number
---@field private scaleVolFog number
---@field private useInParticles boolean
---@field private useInTransparents boolean
---@field private ev number
---@field private shadowFadeDistance number
---@field private shadowFadeRange number
---@field private contactShadows number
---@field private contactShadowsTypes table
---@field private maxShadowPropertiesWidth number
---@field private maxBasePropertiesWidth number
---@field private maxFlickerPropertiesWidth number
---@field private maxMiscPropertiesWidth number
---@field private spotCapsule boolean
---@field private softness number
---@field private attenuation number
---@field private clampAttenuation boolean
---@field private attenuationTypes table
---@field private sceneSpecularScale number
---@field private sceneDiffuse boolean
---@field private roughnessBias number
---@field private sourceRadius number
---@field private directional boolean
---@field private lightChannels table
local light = setmetatable({}, { __index = visualized })

function light:new()
	local o = visualized.new(self)

    o.spawnListType = "files"
    o.dataType = "Static Light"
    o.spawnDataPath = "data/spawnables/lights/staticLights/"
    o.modulePath = "light/light"
    o.node = "worldStaticLightNode"
    o.description = "Places a static light"
    o.icon = IconGlyphs.LightbulbOn20

    o.color = { 1, 1, 1 }
    o.intensity = 100
    o.innerAngle = 20
    o.outerAngle = 60
    o.radius = 15
    o.capsuleLength = 1
    o.autoHideDistance = 45
    o.flickerStrength = 0
    o.flickerPeriod = 0.2
    o.flickerOffset = 0
    o.lightType = 1
    o.localShadows = true
    o.lightTypes = utils.enumTable("ELightType")
    o.temperature = -1
    o.scaleVolFog = 0
    o.useInParticles = true
    o.useInTransparents = true
    o.ev = 0
    o.shadowFadeDistance = 10
    o.shadowFadeRange = 5
    o.contactShadows = 0
    o.contactShadowsTypes = utils.enumTable("rendContactShadowReciever")
    o.spotCapsule = false
    o.softness = 2
    o.attenuation = 0
    o.attenuationTypes = utils.enumTable("rendLightAttenuation")
    o.sceneSpecularScale = 100
    o.clampAttenuation = false
    o.sceneDiffuse = true
    o.roughnessBias = 0
    o.sourceRadius = 0.05
    o.directional = false
    o.lightChannels = { true, true, true, true, true, true, true, true, true, false, false, false }

    o.maxBasePropertiesWidth = nil
    o.maxShadowPropertiesWidth = nil
    o.maxFlickerPropertiesWidth = nil
    o.maxMiscPropertiesWidth = nil
    o.maxLightChannelsWidth = nil

    o.previewColor = "yellow"

    setmetatable(o, { __index = self })
   	return o
end

function light:loadSpawnData(data, position, rotation)
    visualized.loadSpawnData(self, data, position, rotation)

    self.roughnessBias = math.min(math.max(math.floor(self.roughnessBias), -127), 127) -- Fix for incorrect clamping before
    self.scaleVolFog = math.floor(self.scaleVolFog)
    self.sceneSpecularScale = math.floor(self.sceneSpecularScale)
end

function light:onAssemble(entity)
    visualized.onAssemble(self, entity)

    local component = gameLightComponent.new()
    component.name = "light"
    component.color = Color.new({ Red = math.floor(self.color[1] * 255), Green = math.floor(self.color[2] * 255), Blue = math.floor(self.color[3] * 255), Alpha = 255 })
    component.intensity = self.intensity
    component.turnOnByDefault = true
    component.innerAngle = self.innerAngle
    component.outerAngle = self.outerAngle
    component.radius = self.radius
    component.capsuleLength = self.capsuleLength
    component.autoHideDistance = self.autoHideDistance
    component:SetFlickerParams(self.flickerStrength, self.flickerPeriod, self.flickerOffset)
    component.type = Enum.new("ELightType", self.lightType)
    component.enableLocalShadows = self.localShadows
    component.temperature = self.temperature
    component.scaleVolFog = self.scaleVolFog
    component.useInParticles = self.useInParticles
    component.useInTransparents = self.useInTransparents
    component.EV = self.ev
    component.shadowFadeDistance = self.shadowFadeDistance
    component.shadowFadeRange = self.shadowFadeRange
    component.contactShadows = Enum.new("rendContactShadowReciever", self.contactShadows)
    component.spotCapsule = self.spotCapsule
    component.softness = self.softness
    component.attenuation = Enum.new("rendLightAttenuation", self.attenuation)
    component.clampAttenuation = self.clampAttenuation
    component.sceneSpecularScale = self.sceneSpecularScale
    component.sceneDiffuse = self.sceneDiffuse
    component.roughnessBias = self.roughnessBias
    component.sourceRadius = self.sourceRadius
    component.directional = self.directional

    entity:AddComponent(component)
end

function light:save()
    local data = visualized.save(self)

    data.color = { self.color[1], self.color[2], self.color[3] }
    data.intensity = self.intensity
    data.innerAngle = self.innerAngle
    data.outerAngle = self.outerAngle
    data.radius = self.radius
    data.capsuleLength = self.capsuleLength
    data.autoHideDistance = self.autoHideDistance
    data.flickerStrength = self.flickerStrength
    data.flickerPeriod = self.flickerPeriod
    data.flickerOffset = self.flickerOffset
    data.lightType = self.lightType
    data.temperature = self.temperature
    data.scaleVolFog = self.scaleVolFog
    data.useInParticles = self.useInParticles
    data.useInTransparents = self.useInTransparents
    data.ev = self.ev
    data.shadowFadeDistance = self.shadowFadeDistance
    data.shadowFadeRange = self.shadowFadeRange
    data.contactShadows = self.contactShadows
    data.spotCapsule = self.spotCapsule
    data.softness = self.softness
    data.attenuation = self.attenuation
    data.clampAttenuation = self.clampAttenuation
    data.sceneSpecularScale = self.sceneSpecularScale
    data.sceneDiffuse = self.sceneDiffuse
    data.roughnessBias = self.roughnessBias
    data.localShadows = self.localShadows
    data.sourceRadius = self.sourceRadius
    data.directional = self.directional
    data.lightChannels = utils.deepcopy(self.lightChannels)

    return data
end

---Update the light parameters without respawning (Color, Intensity, Angles, Radius, Flicker)
---@protected
function light:updateParameters()
    local entity = self:getEntity()

    if not entity then return end

    local comp = entity:FindComponentByName("light")
    comp:SetColor(Color.new({ Red = math.floor(self.color[1] * 255), Green = math.floor(self.color[2] * 255), Blue = math.floor(self.color[3] * 255) }))
    comp:SetIntensity(math.floor(self.intensity))
    comp:SetAngles(self.innerAngle, self.outerAngle)
    comp:SetRadius(self.radius)
    comp:SetFlickerParams(self.flickerStrength, self.flickerPeriod, self.flickerOffset)
end

---Respawn the light to update parameters, if changed
---@param changed boolean
---@protected
function light:updateFull(changed)
    if changed and self:isSpawned() then self:respawn() end
end

function light:draw()
    visualized.draw(self)

    if not self.maxBasePropertiesWidth then
        self.maxBasePropertiesWidth = utils.getTextMaxWidth({ "Visualize Position", "Light Type", "Intensity", "EV", "Color", "Angles", "Radius", "Spot Capsule", "Softness" }) + 2 * ImGui.GetStyle().ItemSpacing.x + ImGui.GetCursorPosX()
    end

    self:drawPreviewCheckbox("Visualize Position", self.maxBasePropertiesWidth)

    style.mutedText("Light Type")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxBasePropertiesWidth)
    self.lightType, changed = style.trackedCombo(self.object, "##type", self.lightType, self.lightTypes)
    self:updateFull(changed)

    style.mutedText("Intensity")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxBasePropertiesWidth)
    self.intensity, changed = style.trackedDragFloat(self.object, "##intensity", self.intensity, 0.1, 0, 9999, "%.1f", 50)
    if changed then
        self:updateScale()
        self:updateParameters()
    end

    style.mutedText("EV")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxBasePropertiesWidth)
    self.ev, _, finished = style.trackedDragFloat(self.object, "##ev", self.ev, 0.1, 0, 9999, "%.1f", 50)
    self:updateFull(finished)

    style.mutedText("Color")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxBasePropertiesWidth)
    self.color, changed = style.trackedColor(self.object, "##color", self.color, 60)
    if changed then
        self:updateParameters()
    end

    if self.lightType == 1 or (self.lightType == 2 and self.spotCapsule) then
        style.mutedText("Angles")
        ImGui.SameLine()
        ImGui.SetCursorPosX(self.maxBasePropertiesWidth)
        self.innerAngle, changed, finished = style.trackedDragFloat(self.object, "##inner", self.innerAngle, 0.1, 0, 9999, "%.1f Inner", 105)
        if changed then
            self:updateParameters()
        end
        if self.lightType == 2 then
            self:updateFull(finished)
        end

        ImGui.SameLine()
        self.outerAngle, changed, finished = style.trackedDragFloat(self.object, "##outer", self.outerAngle, 0.1, 0, 9999, "%.1f Outer", 105)
        if changed then
            self:updateParameters()
        end
        if self.lightType == 2 then
            self:updateFull(finished)
        end

        style.mutedText("Softness")
        ImGui.SameLine()
        ImGui.SetCursorPosX(self.maxBasePropertiesWidth)
        self.softness, _, finished = style.trackedDragFloat(self.object, "##softness", self.softness, 0.05, 0, 9999, "%.2f", 90)
        self:updateFull(finished)
    end
    if self.lightType == 1 or self.lightType == 2 then
        style.mutedText("Radius")
        ImGui.SameLine()
        ImGui.SetCursorPosX(self.maxBasePropertiesWidth)
        self.radius, changed = style.trackedDragFloat(self.object, "##radius", self.radius, 0.25, 0, 9999, "%.1f", 90)
        if changed then
            self:updateParameters()
        end
        style.tooltip("How far the light source emitts light")
    end
    if self.lightType == 2 then
        style.mutedText("Capsule Length")
        ImGui.SameLine()
        ImGui.SetCursorPosX(self.maxBasePropertiesWidth)
        self.capsuleLength, changed, finished = style.trackedDragFloat(self.object, "##capsuleLength", self.capsuleLength, 0.05, 0, 9999, "%.2f", 90)
        self:updateFull(finished)
        if changed then
            self:updateScale()
        end

        style.mutedText("Spot Capsule")
        ImGui.SameLine()
        ImGui.SetCursorPosX(self.maxBasePropertiesWidth)
        self.spotCapsule, changed = style.trackedCheckbox(self.object, "##spotCapsule", self.spotCapsule)
        self:updateFull(changed)
    end

    if ImGui.TreeNodeEx("Shadow Settings") then
        if not self.maxShadowPropertiesWidth then
            self.maxShadowPropertiesWidth = utils.getTextMaxWidth({ "Contact Shadows", "Local Shadows", "Shadow Fade Distance", "Shadow Fade Range" }) + 2 * ImGui.GetStyle().ItemSpacing.x + ImGui.GetCursorPosX()
        end

        style.mutedText("Contact Shadows")
        ImGui.SameLine()
        ImGui.SetCursorPosX(self.maxShadowPropertiesWidth)
        self.contactShadows, changed = style.trackedCombo(self.object, "##contactShadows", self.contactShadows, self.contactShadowsTypes)
        self:updateFull(changed)

        if self.lightType == 1 or lightType == 2 then
            style.mutedText("Local Shadows")
            ImGui.SameLine()
            ImGui.SetCursorPosX(self.maxShadowPropertiesWidth)
            self.localShadows, changed = style.trackedCheckbox(self.object, "##localShadows", self.localShadows)
            self:updateFull(changed)
        end

        style.mutedText("Shadow Fade Distance")
        ImGui.SameLine()
        ImGui.SetCursorPosX(self.maxShadowPropertiesWidth)
        self.shadowFadeDistance, _, finished = style.trackedDragFloat(self.object, "##shadowFadeDistance", self.shadowFadeDistance, 0.01, 0, 9999, "%.1f", 75)
        self:updateFull(finished)

        style.mutedText("Shadow Fade Range")
        ImGui.SameLine()
        ImGui.SetCursorPosX(self.maxShadowPropertiesWidth)
        self.shadowFadeRange, _, finished = style.trackedDragFloat(self.object, "##shadowFadeRange", self.shadowFadeRange, 0.01, 0, 9999, "%.1f", 75)
        self:updateFull(finished)

        ImGui.TreePop()
    end

    if ImGui.TreeNodeEx("Flicker Settings") then
        if not self.maxFlickerPropertiesWidth then
            self.maxFlickerPropertiesWidth = utils.getTextMaxWidth({ "Flicker Period", "Flicker Strength", "Flicker Offset" }) + 2 * ImGui.GetStyle().ItemSpacing.x + ImGui.GetCursorPosX()
        end

        style.mutedText("Flicker Period")
        ImGui.SameLine()
        ImGui.SetCursorPosX(self.maxFlickerPropertiesWidth)
        self.flickerPeriod, changed = style.trackedDragFloat(self.object, "##flickerPeriod", self.flickerPeriod, 0.01, 0.05, 9999, "%.2f", 85)
        if changed then
            self:updateParameters()
        end

        style.mutedText("Flicker Strength")
        ImGui.SameLine()
        ImGui.SetCursorPosX(self.maxFlickerPropertiesWidth)
        self.flickerStrength, changed = style.trackedDragFloat(self.object, "##flickerStrength", self.flickerStrength, 0.01, 0, 9999, "%.2f", 85)
        if changed then
            self:updateParameters()
        end

        style.mutedText("Flicker Offset")
        ImGui.SameLine()
        ImGui.SetCursorPosX(self.maxFlickerPropertiesWidth)
        self.flickerOffset, changed = style.trackedDragFloat(self.object, "##flickerOffset", self.flickerOffset, 0.01, 0, 9999, "%.2f", 85)
        if changed then
            self:updateParameters()
        end

        ImGui.TreePop()
    end

    if ImGui.TreeNodeEx("Light Channels") then
        self.lightChannels = style.drawLightChannelsSelector(self.object, self.lightChannels)
        ImGui.TreePop()
    end

    if ImGui.TreeNodeEx("Misc. Settings") then
        if not self.maxShadowPropertiesWidth then
            self.maxShadowPropertiesWidth = utils.getTextMaxWidth({ "Directional", "Use in particles", "Use in transparents", "Scale Vol. Fog", "Auto Hide Distance", "Attenuation Mode", "Clamp Attenuation", "Specular Scale", "Scene Diffuse", "Roughness Bias", "Source Radius" }) + 2 * ImGui.GetStyle().ItemSpacing.x + ImGui.GetCursorPosX()
        end

        style.mutedText("Use in particles")
        ImGui.SameLine()
        ImGui.SetCursorPosX(self.maxShadowPropertiesWidth)
        self.useInParticles, changed = style.trackedCheckbox(self.object, "##useInParticles", self.useInParticles)
        self:updateFull(changed)

        style.mutedText("Use in transparents")
        ImGui.SameLine()
        ImGui.SetCursorPosX(self.maxShadowPropertiesWidth)
        self.useInTransparents, changed = style.trackedCheckbox(self.object, "##useInTransparents", self.useInTransparents)
        self:updateFull(changed)

        style.mutedText("Scale Vol. Fog")
        ImGui.SameLine()
        ImGui.SetCursorPosX(self.maxShadowPropertiesWidth)
        self.scaleVolFog, _, finished = style.trackedDragInt(self.object, "##scaleVolFog", self.scaleVolFog, 0, 255, 110)
        self:updateFull(finished)

        style.mutedText("Scene Diffuse")
        ImGui.SameLine()
        ImGui.SetCursorPosX(self.maxShadowPropertiesWidth)
        self.sceneDiffuse, changed = style.trackedCheckbox(self.object, "##sceneDiffuse", self.sceneDiffuse)
        self:updateFull(changed)

        style.mutedText("Specular Scale")
        ImGui.SameLine()
        ImGui.SetCursorPosX(self.maxShadowPropertiesWidth)
        self.sceneSpecularScale, _, finished = style.trackedDragInt(self.object, "##sceneSpecularScale", self.sceneSpecularScale, 0, 255, 110)
        self:updateFull(finished)

        style.mutedText("Roughness Bias")
        ImGui.SameLine()
        ImGui.SetCursorPosX(self.maxShadowPropertiesWidth)
        self.roughnessBias, _, finished = style.trackedDragInt(self.object, "##roughnessBias", self.roughnessBias, -127, 127, 110)
        self:updateFull(finished)

        style.mutedText("Source Radius")
        ImGui.SameLine()
        ImGui.SetCursorPosX(self.maxShadowPropertiesWidth)
        self.sourceRadius, _, finished = style.trackedDragFloat(self.object, "##sourceRadius", self.sourceRadius, 0.0025, 0, 9999, "%.3f", 110)
        self:updateFull(finished)

        style.mutedText("Auto Hide Distance")
        ImGui.SameLine()
        ImGui.SetCursorPosX(self.maxShadowPropertiesWidth)
        self.autoHideDistance, _, finished = style.trackedDragFloat(self.object, "##autoHideDistance", self.autoHideDistance, 0.05, 0, 9999, "%.1f", 110)
        self:updateFull(finished)

        style.mutedText("Attenuation Mode")
        ImGui.SameLine()
        ImGui.SetCursorPosX(self.maxShadowPropertiesWidth)
        self.attenuation, changed = style.trackedCombo(self.object, "##attenuation", self.attenuation, self.attenuationTypes, 110)
        self:updateFull(changed)

        style.mutedText("Clamp Attenuation")
        ImGui.SameLine()
        ImGui.SetCursorPosX(self.maxShadowPropertiesWidth)
        self.clampAttenuation, changed = style.trackedCheckbox(self.object, "##clampAttenuation", self.clampAttenuation)
        self:updateFull(changed)

        style.mutedText("Directional")
        ImGui.SameLine()
        ImGui.SetCursorPosX(self.maxShadowPropertiesWidth)
        self.directional, changed = style.trackedCheckbox(self.object, "##directional", self.directional)
        self:updateFull(changed)

        ImGui.TreePop()
    end

    ImGui.PopItemWidth()
end

function light:getProperties()
    local properties = visualized.getProperties(self)
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

function light:getVisualizerSize()
    local size = math.max(math.min(0.35, ((self.intensity / 10000) * (self.lightType == 2 and self.capsuleLength / 2 or 1))), 0.05)
    return { x = size, y = size, z = size }
end

function light:getSize()
    return { x = 0.02, y = 0.2, z = 0.2 }
end

function light:getBBox()
    return {
        min = { x = -0.01, y = -0.01, z = -0.1 },
        max = { x = 0.01, y = 0.01, z = 0.1 }
    }
end

function light:export()
    local data = visualized.export(self)
    data.type = "worldStaticLightNode"

    data.data = {
        autoHideDistance = self.autoHideDistance,
        capsuleLength = self.capsuleLength,
        color = {
            ["Red"] = math.floor(self.color[1] * 255),
            ["Green"] = math.floor(self.color[2] * 255),
            ["Blue"] = math.floor(self.color[3] * 255),
            ["Alpha"] = 255
        },
        enableLocalShadows = self.localShadows and 1 or 0,
        flicker = {
            ["flickerPeriod"] = self.flickerPeriod,
            ["flickerStrength"] = self.flickerStrength,
            ["positionOffset"] = self.flickerOffset
        },
        innerAngle = self.innerAngle,
        intensity = self.intensity,
        outerAngle = self.outerAngle,
        radius = self.radius,
        type = self.lightTypes[self.lightType + 1],
        allowDistantLight = 0,
        lightChannel = utils.buildBitfieldString(self.lightChannels, style.lightChannelEnum),
        scaleVolFog = self.scaleVolFog,
        useInParticles = self.useInParticles and 1 or 0,
        useInTransparents = self.useInTransparents and 1 or 0,
        EV = self.ev,
        shadowFadeDistance = self.shadowFadeDistance,
        shadowFadeRange = self.shadowFadeRange,
        contactShadows = self.contactShadowsTypes[self.contactShadows + 1],
        spotCapsule = self.spotCapsule and 1 or 0,
        softness = self.softness,
        attenuation = self.attenuationTypes[self.attenuation + 1],
        clampAttenuation = self.clampAttenuation and 1 or 0,
        sceneSpecularScale = self.sceneSpecularScale,
        sceneDiffuse = self.sceneDiffuse and 1 or 0,
        roughnessBias = self.roughnessBias,
        sourceRadius = self.sourceRadius,
        directional = self.directional and 1 or 0
    }

    return data
end

return light