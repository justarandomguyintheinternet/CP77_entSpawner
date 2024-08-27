local spawnable = require("modules/classes/spawn/spawnable")
local builder = require("modules/utils/entityBuilder")
local style = require("modules/ui/style")
local utils = require("modules/utils/utils")

---Class for worldStaticLightNode
---@class light : spawnable
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
local light = setmetatable({}, { __index = spawnable })

function light:new()
	local o = spawnable.new(self)

    o.boxColor = {255, 255, 0}
    o.spawnListType = "files"
    o.dataType = "Static Light"
    o.spawnDataPath = "data/spawnables/lights/"
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

    setmetatable(o, { __index = self })
   	return o
end

function light:onAssemble(entity)
    spawnable.onAssemble(self, entity)

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
    entity:AddComponent(component)
end

function light:save()
    local data = spawnable.save(self)
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

    return data
end

function light:getExtraHeight()
    local h = 7 * ImGui.GetStyle().ItemSpacing.y + ImGui.GetFrameHeight() * 4
    if self.lightType == 1 then
        h = h + ImGui.GetStyle().ItemSpacing.y + ImGui.GetFrameHeight()
    end
    return h
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
    spawnable.draw(self)

    self.intensity, changed = style.trackedDragFloat(self.object, "##intensity", self.intensity, 0.1, 0, 9999, "%.1f Intensity", 90)
    if changed then
        self:updateParameters()
    end
    ImGui.SameLine()
    self.color, changed = style.trackedColor(self.object, "##color", self.color, 60)
    if changed then
        self:updateParameters()
    end

    ImGui.PushItemWidth(150)
    if self.lightType == 1 then
        self.innerAngle, changed = style.trackedDragFloat(self.object, "##inner", self.innerAngle, 0.1, 0, 9999, "%.1f Inner Angle", 105)
        if changed then
            self:updateParameters()
        end
        ImGui.SameLine()
        self.outerAngle, changed = style.trackedDragFloat(self.object, "##outer", self.outerAngle, 0.1, 0, 9999, "%.1f Outer Angle", 105)
        if changed then
            self:updateParameters()
        end
    end
    if self.lightType == 1 or self.lightType == 2 then
        self.radius, changed = style.trackedDragFloat(self.object, "##radius", self.radius, 0.25, 0, 9999, "%.1f Radius", 90)
        if changed then
            self:updateParameters()
        end
    end
    if self.lightType == 2 then
        ImGui.SameLine()
        self.capsuleLength, _, finished = style.trackedDragFloat(self.object, "##capsuleLength", self.capsuleLength, 0.05, 0, 9999, "%.2f Length", 90)
        self:updateFull(finished)
        ImGui.SameLine()
    end
    if self.lightType == 1 then
        ImGui.SameLine()
    end
    self.autoHideDistance, _, finished = style.trackedDragFloat(self.object, "##autoHideDistance", self.autoHideDistance, 0.05, 0, 9999, "%.1f Hide Dist.", 90)
    self:updateFull(finished)

    ImGui.Text("Light Type")
    ImGui.SameLine()
    self.lightType, changed = style.trackedCombo(self.object, "##type", self.lightType, self.lightTypes)
    self:updateFull(changed)

    ImGui.Text("Flicker Settings")
    style.tooltip("Controll light flickering, turn up strength to see effect")
    ImGui.SameLine()
    self.flickerPeriod, changed = style.trackedDragFloat(self.object, "##flickerPeriod", self.flickerPeriod, 0.01, 0.05, 9999, "%.2f Period", 90)
    if changed then
        self:updateParameters()
    end
    ImGui.SameLine()
    self.flickerStrength, changed = style.trackedDragFloat(self.object, "##flickerStrength", self.flickerStrength, 0.01, 0, 9999, "%.2f Strength", 90)
    if changed then
        self:updateParameters()
    end
    ImGui.SameLine()
    self.flickerOffset, changed = style.trackedDragFloat(self.object, "##flickerOffset", self.flickerOffset, 0.01, 0, 9999, "%.2f Offset", 90)
    if changed then
        self:updateParameters()
    end

    if self.lightType == 1 then
        self.localShadows, changed = style.trackedCheckbox(self.object, "Local Shadows", self.localShadows)
        self:updateFull(changed)
    end

    ImGui.PopItemWidth()
end

function light:getProperties()
    local properties = spawnable.getProperties(self)
    table.insert(properties, {
        id = self.node,
        name = self.dataType,
        draw = function()
            self:draw()
        end
    })
    return properties
end

function light:export()
    local data = spawnable.export(self)
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
        lightChannel = "LC_Channel1, LC_Channel2, LC_Channel3, LC_Channel4, LC_Channel5, LC_Channel6, LC_Channel7, LC_Channel8, LC_ChannelWorld"
    }

    return data
end

return light