local CPS = require("CPStyling")
local config = require("modules/utils/config")
local style = require("modules/ui/style")

settingsUI = {}

local function sectionHeaderStart(text)
    ImGui.PushStyleColor(ImGuiCol.Text, style.mutedColor)
    ImGui.SetWindowFontScale(0.85)
    ImGui.Text(text)
    ImGui.SetWindowFontScale(1)
    ImGui.PopStyleColor()
    ImGui.Separator()
    ImGui.Spacing()

    ImGui.BeginGroup()
    ImGui.AlignTextToFramePadding()
end

local function sectionHeaderEnd(noSpacing)
    ImGui.EndGroup()

    if not noSpacing then
        ImGui.Spacing()
        ImGui.Spacing()
    end
end

local function tooltip(text)
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip(text)
    end
end

function settingsUI.draw(spawner)
    sectionHeaderStart("SPAWNING")

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
    tooltip("Spawn position is relative to the players position and rotation, at the specified distance")

    if spawner.settings.spawnPos == 2 then
        spawner.settings.spawnDist, changed = ImGui.InputFloat("Spawn distance to player", spawner.settings.spawnDist, -9999, 9999, "%.1f")
        if changed then config.saveFile("data/config.json", spawner.settings) end
    end

    sectionHeaderEnd()
    sectionHeaderStart("EDITING")

    if ImGui.RadioButton("Make cloned group original groups child", spawner.settings.moveCloneToParent == 1) then
        spawner.settings.moveCloneToParent = 1
        config.saveFile("data/config.json", spawner.settings)
    end
    tooltip("When cloning a group, place the newly created group inside the original one")

    ImGui.SameLine()

    if ImGui.RadioButton("Move cloned group to groups parent", spawner.settings.moveCloneToParent == 2) then
        spawner.settings.moveCloneToParent = 2
        config.saveFile("data/config.json", spawner.settings)
    end
    tooltip("When cloning a group, place the newly created group at the same level as the the one it was cloned from")

    spawner.settings.posSteps, changed = ImGui.InputFloat("Position controls step size", spawner.settings.posSteps, -9999, 9999, "%.3f")
    if changed then config.saveFile("data/config.json", spawner.settings) end

    spawner.settings.rotSteps, changed = ImGui.InputFloat("Rotation controls step size", spawner.settings.rotSteps, -9999, 9999, "%.3f")
    if changed then config.saveFile("data/config.json", spawner.settings) end

    sectionHeaderEnd()
    sectionHeaderStart("MISC")

    spawner.settings.headerState, changed = ImGui.Checkbox("Close collapsible headers by default", spawner.settings.headerState)
    if changed then config.saveFile("data/config.json", spawner.settings) end

    spawner.settings.deleteConfirm, changed = ImGui.Checkbox("Show confirm to delete popup", spawner.settings.deleteConfirm)
    if changed then config.saveFile("data/config.json", spawner.settings) end

    spawner.settings.despawnOnReload, changed = ImGui.Checkbox("Despawn everything on \"Reload all mods\"", spawner.settings.despawnOnReload)
    if changed then config.saveFile("data/config.json", spawner.settings) end

    spawner.settings.groupExport, changed = ImGui.Checkbox("For mod creators: Export option (Output in /export folder)", spawner.settings.groupExport)
    if changed then config.saveFile("data/config.json", spawner.settings) end

    spawner.settings.groupRot, changed = ImGui.Checkbox("EXPERIMENTAL: Group Rotation", spawner.settings.groupRot)
    if changed then config.saveFile("data/config.json", spawner.settings) end

    sectionHeaderEnd(true)
end

return settingsUI