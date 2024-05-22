local spawnable = require("modules/classes/spawn/spawnable")
local builder = require("modules/utils/entityBuilder")
local style = require("modules/ui/style")
local utils = require("modules/utils/utils")

---Class for worldStaticLightNode
---@class light : spawnable
---@field public color table {r: number, g: number, b: number}
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
local light = setmetatable({}, { __index = spawnable })

function light:new()
	local o = spawnable.new(self)

    o.boxColor = {255, 255, 0}
    o.spawnListType = "files"
    o.dataType = "Static Light"
    o.spawnDataPath = "data/spawnables/lights/"
    o.modulePath = "light/light"

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
    entity:AddComponent(component)
end

function light:save()
    local data = spawnable.save(self)
    data.color = self.color
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
    if not self:isSpawned() then return end

    if changed then
        self:despawn()
        self:spawn()
    end
end

function light:draw()
    spawnable.draw(self)

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()

    ImGui.SetNextItemWidth(150)
    self.intensity, changed = ImGui.DragFloat("##intensity", self.intensity, 0.1, 0, 9999, "%.1f Intensity")
    if changed then
        self:updateParameters()
    end
    ImGui.SameLine()
    self.color, changed = ImGui.ColorEdit3("##color", self.color)
    if changed then
        self:updateParameters()
    end

    ImGui.PushItemWidth(150)
    if self.lightType == 1 then
        self.innerAngle, changed = ImGui.DragFloat("##inner", self.innerAngle, 0.1, 0, 9999, "%.1f Inner Angle")
        if changed then
            self:updateParameters()
        end
        ImGui.SameLine()
        self.outerAngle, changed = ImGui.DragFloat("##outer", self.outerAngle, 0.1, 0, 9999, "%.1f Outer Angle")
        if changed then
            self:updateParameters()
        end
        ImGui.SameLine()
    end
    if self.lightType == 1 or self.lightType == 2 then
        self.radius, changed = ImGui.DragFloat("##radius", self.radius, 0.25, 0, 9999, "%.1f Radius")
        if changed then
            self:updateParameters()
        end
    end
    if self.lightType == 2 then
        ImGui.SameLine()
        self.capsuleLength, _ = ImGui.DragFloat("##capsuleLength", self.capsuleLength, 0.05, 0, 9999, "%.2f Length")
        self:updateFull(ImGui.IsItemDeactivatedAfterEdit())
        ImGui.SameLine()
    end
    if self.lightType == 1 then
        ImGui.SameLine()
    end
    self.autoHideDistance, _ = ImGui.DragFloat("##autoHideDistance", self.autoHideDistance, 0.05, 0, 9999, "%.2f Hide Dist.")
    self:updateFull(ImGui.IsItemDeactivatedAfterEdit())

    ImGui.Text("Light Type")
    ImGui.SameLine()
    self.lightType, changed = ImGui.Combo("##type", self.lightType, self.lightTypes, #self.lightTypes)
    self:updateFull(ImGui.IsItemDeactivatedAfterEdit())

    ImGui.Text("Flicker Settings")
    style.tooltip("Controll light flickering, turn up strength to see effect")
    ImGui.SameLine()
    self.flickerPeriod, changed = ImGui.DragFloat("##flickerPeriod", self.flickerPeriod, 0.01, 0, 9999, "%.2f Period")
    if changed then
        self.flickerPeriod = math.max(self.flickerPeriod, 0.05)
        self:updateParameters()
    end
    ImGui.SameLine()
    self.flickerStrength, changed = ImGui.DragFloat("##flickerStrength", self.flickerStrength, 0.01, 0, 9999, "%.2f Strength")
    if changed then
        self:updateParameters()
    end
    ImGui.SameLine()
    self.flickerOffset, changed = ImGui.DragFloat("##flickerOffset", self.flickerOffset, 0.01, 0, 9999, "%.2f Offset")
    if changed then
        self:updateParameters()
    end

    if self.lightType == 1 then
        self.localShadows, changed = ImGui.Checkbox("Local Shadows", self.localShadows)
        self:updateFull(ImGui.IsItemDeactivatedAfterEdit())
    end

    ImGui.PopItemWidth()
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
            ["Blue"] = math.floor(self.color[3] * 255)
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
        type = self.lightTypes[self.lightType + 1]
    }

    return data
end

return light