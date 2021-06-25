local CPS = require("CPStyling")

baseUI = {
    spawnUI = require("modules/ui/spawnUI"),
    spawnedUI = require("modules/ui/spawnedUI"),
    favUI = require("modules/ui/favUI"),
    savedUI = require("modules/ui/savedUI"),
    settingsUI = require("modules/ui/settingsUI")
}

function baseUI.draw(spawner)
    CPS:setThemeBegin()
    ImGui.Begin("Object Spawner 1.1", ImGuiWindowFlags.AlwaysAutoResize)

    if ImGui.BeginTabBar("Tabbar", ImGuiTabBarFlags.NoTooltip) then
        CPS.styleBegin("TabRounding", 0)

        if ImGui.BeginTabItem("Spawn new") then
            baseUI.spawnUI.draw(spawner)
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem("Spawned") then
            baseUI.spawnedUI.draw(spawner)
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem("Saved") then
            baseUI.savedUI.draw(spawner)
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem("Favorites") then
            baseUI.favUI.draw(spawner)
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem("Settings") then
            baseUI.settingsUI.draw(spawner)
            ImGui.EndTabItem()
        end

        CPS.styleEnd(1)
        ImGui.EndTabBar()
    end

    ImGui.End()
    CPS:setThemeEnd()
end

return baseUI