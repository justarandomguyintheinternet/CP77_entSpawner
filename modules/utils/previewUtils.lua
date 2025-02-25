local preview = {
    elements = {}
}

function preview.addHUDText(key, size, x, y, color)
    color = color or "MainColors.Blue"

    local text = inkText.new()
    text:SetText("")
    text:SetFontSize(size)
    text:SetAnchor(inkEAnchor.TopLeft)
    text:SetAnchorPoint(0.5, 0.5)
    text:SetVisible(false)
    text:SetFontFamily("base\\gameplay\\gui\\fonts\\orbitron\\orbitron.inkfontfamily")
    text:SetStyle("base\\gameplay\\gui\\common\\main_colors.inkstyle")
    text:BindProperty("tintColor", color)
    text:SetTranslation(x, y)
    text:SetFitToContent(false)
    text:SetHorizontalAlignment(textHorizontalAlignment.Left)
    text:Reparent(Game.GetInkSystem():GetLayer("inkHUDLayer"):GetVirtualWindow())

    preview.elements[key] = text
end

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

    preview.addHUDText("previewFirstLine", 30 * factor, 730, 180)
    preview.addHUDText("previewSecondLine", 30 * factor, 730, 180 + 45 * factor)
    preview.addHUDText("previewThirdLine", 30 * factor, 730, 180 + 90 * factor, "MainColors.Red")
end

function preview.getBackplaneSize(size)
    return size / 10
end

function preview.getTopLeft(backplaneSize)
    return backplaneSize / 2
end

return preview