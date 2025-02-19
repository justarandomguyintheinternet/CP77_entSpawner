local hud = {
    elements = {}
}

function hud.addHUDText(key, size, x, y)
    local text = inkText.new()
    text:SetText("")
    text:SetFontSize(size)
    text:SetAnchor(inkEAnchor.TopLeft)
    text:SetAnchorPoint(0.5, 0.5)
    text:SetVisible(false)
    text:SetFontFamily("base\\gameplay\\gui\\fonts\\orbitron\\orbitron.inkfontfamily")
    text:SetStyle("base\\gameplay\\gui\\common\\main_colors.inkstyle")
    text:BindProperty("tintColor", "MainColors.Blue")
    text:SetTranslation(x, y)
    text:SetFitToContent(false)
    text:SetHorizontalAlignment(textHorizontalAlignment.Left)
    text:Reparent(Game.GetInkSystem():GetLayer("inkHUDLayer"):GetVirtualWindow())

    hud.elements[key] = text
end

return hud