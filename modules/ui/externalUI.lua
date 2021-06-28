local CPS = require("CPStyling")
local config = require("modules/utils/config")

externalUI = {
    externalMods = {}
}

function externalUI.draw(spawner)
    if #externalUI.externalMods == 0 then
        ImGui.Text("No external object mods installed!")
    end
    for _, mod in pairs(externalUI.externalMods) do
        local state, changed = ImGui.Checkbox(tostring("##" .. mod.info.modName), mod.config.active)
        if changed then mod.toggle(state) end
        ImGui.SameLine()
        CPS.colorBegin("Text", {0, 255, 0})
        ImGui.Text(mod.info.modName)
        CPS.colorEnd(1)
        ImGui.SameLine()
        ImGui.Text("made by")
        CPS.colorBegin("Text", {0, 255, 255})
        ImGui.SameLine()
        ImGui.Text(mod.info.authorName)
        CPS.colorEnd(1)
    end
end

return externalUI