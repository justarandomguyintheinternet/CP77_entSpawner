local CPS = require("CPStyling")

---@class baseUI
baseUI = {
    spawnUI = require("modules/ui/spawnUI"),
    spawnedUI = require("modules/ui/spawnedUI"),
    favUI = require("modules/ui/favUI"),
    savedUI = require("modules/ui/savedUI"),
    exportUI = require("modules/ui/exportUI"),
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
    ImGui.Begin("Object Spawner 2.0", ImGuiWindowFlags.AlwaysAutoResize)

    if ImGui.BeginTabBar("Tabbar", ImGuiTabItemFlags.NoTooltip) then
        if ImGui.BeginTabItem("Spawn new") then
            baseUI.currentTab = 0
            ImGui.Spacing()
            baseUI.spawnedUI.getGroups()
            baseUI.spawnUI.draw()
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem("Spawned") then
            baseUI.currentTab = 1
            ImGui.Spacing()
            baseUI.spawnedUI.draw()
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem("Saved") then
            baseUI.currentTab = 2
            ImGui.Spacing()
            baseUI.savedUI.draw(spawner)
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem("Export") then
            baseUI.currentTab = 3
            ImGui.Spacing()
            baseUI.exportUI.draw(spawner)
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem("Favorites") then
            baseUI.currentTab = 4
            ImGui.Spacing()
            baseUI.favUI.draw(spawner)
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem("External Mods") then
            baseUI.currentTab = 5
            ImGui.Spacing()
            baseUI.externalUI.draw(spawner)
            ImGui.EndTabItem()
        end

        if ImGui.BeginTabItem("Settings") then
            baseUI.currentTab = 6
            ImGui.Spacing()
            baseUI.settingsUI.draw()
            ImGui.EndTabItem()
        end
        ImGui.EndTabBar()
    end

    ImGui.End()
    -- CPS:setThemeEnd()
end

return baseUI