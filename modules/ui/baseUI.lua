local CPS = require("CPStyling")

baseUI = {
    spawnUI = require("modules/ui/spawnUI"),
    spawnedUI = require("modules/ui/spawnedUI"),
    favUI = require("modules/ui/favUI"),
    savedUI = require("modules/ui/savedUI"),
    externalUI = require("modules/ui/externalUI"),
    settingsUI = require("modules/ui/settingsUI"),
    currentTab = 0
}

function baseUI.getResizeFlag()
    if baseUI.currentTab == 0 then
        return ImGuiWindowFlags.None
    else
        return ImGuiWindowFlags.AlwaysAutoResize
    end
end

function baseUI.draw(spawner)
    -- CPS:setThemeBegin()
    ImGui.Begin("Object Spawner 1.4", ImGuiWindowFlags.AlwaysAutoResize)

    if ImGui.BeginTabBar("Tabbar", ImGuiTabItemFlags.NoTooltip) then
        if ImGui.BeginTabItem("Spawn new") then
            baseUI.currentTab = 0
            baseUI.spawnUI.draw(spawner)
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem("Spawned") then
            baseUI.currentTab = 1
            baseUI.spawnedUI.draw(spawner)
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem("Saved") then
            baseUI.currentTab = 2
            baseUI.savedUI.draw(spawner)
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem("Favorites") then
            baseUI.currentTab = 3
            baseUI.favUI.draw(spawner)
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem("External Mods") then
            baseUI.currentTab = 4
            baseUI.externalUI.draw(spawner)
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem("Settings") then
            baseUI.currentTab = 5
            ImGui.Spacing()
            baseUI.settingsUI.draw(spawner)
            ImGui.EndTabItem()
        end
        ImGui.EndTabBar()
    end

    ImGui.End()
    -- CPS:setThemeEnd()
end

return baseUI