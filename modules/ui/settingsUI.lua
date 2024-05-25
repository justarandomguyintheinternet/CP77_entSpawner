local style = require("modules/ui/style")
local settings = require("modules/utils/settings")

settingsUI = {}

function settingsUI.draw()
    style.sectionHeaderStart("SPAWNING")

    ImGui.Text("Spawn new objects: ")
    ImGui.SameLine()
    if ImGui.RadioButton("At player pos", settings.spawnPos == 1) then
        settings.spawnPos = 1
        settings.save()
    end
    ImGui.SameLine()

    if ImGui.RadioButton("In front of player", settings.spawnPos == 2) then
        settings.spawnPos = 2
        settings.save()
    end
    style.tooltip("Spawn position is relative to the players position and rotation, at the specified distance")

    if settings.spawnPos == 2 then
        settings.spawnDist, changed = ImGui.InputFloat("Spawn distance to player", settings.spawnDist, -9999, 9999, "%.1f")
        if changed then settings.save() end
    end

    style.sectionHeaderEnd()
    style.sectionHeaderStart("EDITING")

    if ImGui.RadioButton("Make cloned group original groups child", settings.moveCloneToParent == 1) then
        settings.moveCloneToParent = 1
        settings.save()
    end
    style.tooltip("When cloning a group, place the newly created group inside the original one")

    ImGui.SameLine()

    if ImGui.RadioButton("Move cloned group to groups parent", settings.moveCloneToParent == 2) then
        settings.moveCloneToParent = 2
        settings.save()
    end
    style.tooltip("When cloning a group, place the newly created group at the same level as the the one it was cloned from")

    settings.posSteps, changed = ImGui.InputFloat("Position controls step size", settings.posSteps, -9999, 9999, "%.4f")
    if changed then settings.save() end

    settings.rotSteps, changed = ImGui.InputFloat("Rotation controls step size", settings.rotSteps, -9999, 9999, "%.4f")
    if changed then settings.save() end

    style.sectionHeaderEnd()
    style.sectionHeaderStart("MISC")

    settings.headerState, changed = ImGui.Checkbox("Close collapsible headers by default", settings.headerState)
    if changed then settings.save() end

    settings.deleteConfirm, changed = ImGui.Checkbox("Show confirm to delete popup", settings.deleteConfirm)
    if changed then settings.save() end

    settings.despawnOnReload, changed = ImGui.Checkbox("Despawn everything on \"Reload all mods\"", settings.despawnOnReload)
    if changed then settings.save() end

    settings.groupExport, changed = ImGui.Checkbox("For mod creators: Export option (Output in /export folder)", settings.groupExport)
    if changed then settings.save() end

    settings.groupRot, changed = ImGui.Checkbox("EXPERIMENTAL: Group Rotation", settings.groupRot)
    if changed then settings.save() end

    style.sectionHeaderEnd(true)
end

return settingsUI