local style = require("modules/ui/style")
local settings = require("modules/utils/settings")

local colliderColors = { "Red", "Green", "Blue" }
local outlineColors = { "Green", "Red", "Blue", "Orange", "Yellow", "Light Blue", "White", "Black" }

settingsUI = {}

function settingsUI.draw()
    style.sectionHeaderStart("SPAWNING")

    ImGui.Text("Spawn new objects: ")
    ImGui.SameLine()
    if ImGui.RadioButton("At selected", settings.spawnPos == 1) then
        settings.spawnPos = 1
        settings.save()
    end
    style.tooltip("Spawn the new object at the position of the selected object(s), if none are selected, it will spawn in front of the player")
    ImGui.SameLine()

    if ImGui.RadioButton("Always in front of player", settings.spawnPos == 2) then
        settings.spawnPos = 2
        settings.save()
    end
    style.tooltip("Spawn position is relative to the players position and rotation, at the specified distance")

    settings.spawnDist, changed = ImGui.InputFloat("Spawn distance to player", settings.spawnDist, -9999, 9999, "%.1f")
    if changed then settings.save() end
    style.tooltip("Distance from the player to spawn the object at, used for the fallback for \"At selected\", and always used for \"Always in front of player\"")

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

    settings.precisionMultiplier, changed = ImGui.InputFloat("Precision multiplier", settings.precisionMultiplier, 0, 10, "%.3f")
    if changed then settings.save() end
    style.tooltip("When holding shift, the step size will be multiplied by this value")

    style.sectionHeaderEnd()
    style.sectionHeaderStart("VISUALIZERS")

    settings.gizmoActive, changed = ImGui.Checkbox("Show arrows", settings.gizmoActive)
    if changed then settings.save() end
    style.tooltip("Globally enable or disable the arrows")

    settings.gizmoOnSelected, changed = ImGui.Checkbox("Show arrows when element is selected", settings.gizmoOnSelected)
    if changed then settings.save() end
    style.tooltip("Always show the arrows when an element is selected.\nDefault is to only show it when hovering the element or its transform controls.\nEdit mode ignores this setting, and always shows the arrows on the selected element.")

    settings.outlineSelected, changed = ImGui.Checkbox("Outline selected", settings.outlineSelected)
    if changed then settings.save() end
    style.tooltip("Outline the selected element(s) with a color.\nEdit mode ignores this setting, and always shows the outline on the selected element(s).")

    settings.outlineColor, changed = ImGui.Combo("Outline color", settings.outlineColor, outlineColors, #outlineColors)
    if changed then settings.save() end

    style.sectionHeaderEnd()
    style.sectionHeaderStart("COLLIDERS")

    settings.colliderColor, changed = ImGui.Combo("Collider color", settings.colliderColor, colliderColors, #colliderColors)
    if changed then settings.save() end

    style.sectionHeaderEnd()
    style.sectionHeaderStart("MISC")

    settings.headerState, changed = ImGui.Checkbox("Close collapsible headers by default", settings.headerState)
    if changed then settings.save() end

    settings.deleteConfirm, changed = ImGui.Checkbox("Show confirm to delete popup", settings.deleteConfirm)
    if changed then settings.save() end

    settings.despawnOnReload, changed = ImGui.Checkbox("Despawn everything on \"Reload all mods\"", settings.despawnOnReload)
    if changed then settings.save() end

    style.sectionHeaderEnd(true)
end

return settingsUI