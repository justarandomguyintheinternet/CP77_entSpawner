local hud = require("modules/utils/hud")

local preview = {}

function preview.addLight(entity, intensity, ev, distance)
    local component = gameLightComponent.new()
    component.name = "light"
    component.intensity = intensity or 5
    component.turnOnByDefault = true
    component.innerAngle = 179
    component.outerAngle = 179
    component.radius = 5
    component.type = ELightType.LT_Spot
    component.useInParticles = false
    component.useInTransparents = false
    component.EV = ev or 0.75
    component:SetLocalOrientation(EulerAngles.new(0, 0, 180):ToQuat())
    component:SetLocalPosition(Vector4.new(0, distance or 1, 0, 0))
    entity:AddComponent(component)
end

function preview.addHUD()
    local width, _ = GetDisplayResolution()
    local factor = width / 2560

    hud.addHUDText("previewFirstLine", 30 * factor, 730, 180)
    hud.addHUDText("previewSecondLine", 30 * factor, 730, 180 + 45 * factor)
end

return preview