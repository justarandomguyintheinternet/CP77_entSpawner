local CPS = require("CPStyling")
local config = require("modules/utils/config")

settingsUI = {}

function settingsUI.draw(spawner)
    ImGui.Text("Spawn new objects: ")
    ImGui.SameLine()
    if ImGui.RadioButton("At player pos", spawner.settings.spawnPos == 1) then
        spawner.settings.spawnPos = 1
        config.saveFile("data/config.json", spawner.settings)
    end
    ImGui.SameLine()

    if ImGui.RadioButton("In front of player", spawner.settings.spawnPos == 2) then
        spawner.settings.spawnPos = 2
        config.saveFile("data/config.json", spawner.settings)
    end

    if spawner.settings.spawnPos == 2 then
        spawner.settings.spawnDist, changed = ImGui.InputFloat("Spawn distance to player", spawner.settings.spawnDist, -9999, 9999, "%.1f")
        if changed then config.saveFile("data/config.json", spawner.settings) end
    end

    spawner.settings.posSteps, changed = ImGui.InputFloat("Position controls step size", spawner.settings.posSteps, -9999, 9999, "%.3f")
    if changed then config.saveFile("data/config.json", spawner.settings) end

    spawner.settings.rotSteps, changed = ImGui.InputFloat("Rotation controls step size", spawner.settings.rotSteps, -9999, 9999, "%.3f")
    if changed then config.saveFile("data/config.json", spawner.settings) end

    spawner.settings.autoSpawnRange, changed = ImGui.InputFloat("Default auto spawn range", spawner.settings.autoSpawnRange, -9999, 9999, "%.1f")
    if changed then config.saveFile("data/config.json", spawner.settings) end

    spawner.settings.appFetchTrys, changed = ImGui.InputInt("Appearance Fetching Tries", spawner.settings.appFetchTrys, -9999, 9999)
    if changed then config.saveFile("data/config.json", spawner.settings) end

    spawner.settings.headerState, changed = CPS.CPToggle("Collapsible headers default state", "Closed", "Open", spawner.settings.headerState, 100 , 25)
    if changed then config.saveFile("data/config.json", spawner.settings) end

    spawner.settings.deleteConfirm, changed = ImGui.Checkbox("Show confirm to delete popup", spawner.settings.deleteConfirm)
    if changed then config.saveFile("data/config.json", spawner.settings) end

    spawner.settings.despawnOnReload, changed = ImGui.Checkbox("Despawn everything on \"Reload all mods\"", spawner.settings.despawnOnReload)
    if changed then config.saveFile("data/config.json", spawner.settings) end

    if ImGui.RadioButton("Make cloned group original groups child", spawner.settings.moveCloneToParent == 1) then
        spawner.settings.moveCloneToParent = 1
        config.saveFile("data/config.json", spawner.settings)
    end

    ImGui.SameLine()

    if ImGui.RadioButton("Move cloned group to groups parent", spawner.settings.moveCloneToParent == 2) then
        spawner.settings.moveCloneToParent = 2
        config.saveFile("data/config.json", spawner.settings)
    end

    spawner.settings.groupExport, changed = ImGui.Checkbox("For mod creators: Export option (Output in /export folder)", spawner.settings.groupExport)
    if changed then config.saveFile("data/config.json", spawner.settings) end

    spawner.settings.groupRot, changed = ImGui.Checkbox("EXPERIMENTAL: Group Rotation", spawner.settings.groupRot)
    if changed then config.saveFile("data/config.json", spawner.settings) end
end

return settingsUI