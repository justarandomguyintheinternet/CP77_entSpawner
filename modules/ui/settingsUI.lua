local style = require("modules/ui/style")
local settings = require("modules/utils/settings")
local cache = require("modules/utils/cache")
local utils = require("modules/utils/utils")

local colliderColors = { "Red", "Green", "Blue" }
local outlineColors = { "Green", "Red", "Blue", "Orange", "Yellow", "Light Blue", "White", "Black" }
local windowNames = { "World Builder", "Object Spawner", "Entity Spawner", "World Additor", "World Editing Toolkit", "World Editor", "WheezeKit", "Buildy McBuildface", "Keanus Editing Kit (Kek)", "Redkit at home" }
local materials = { "meatbag.physmat","linoleum.physmat","trash.physmat","plastic.physmat","character_armor.physmat","furniture_upholstery.physmat","metal_transparent.physmat","tire_car.physmat","meat.physmat","metal_car_pipe_steam.physmat","character_flesh.physmat","brick.physmat","character_flesh_head.physmat","leaves.physmat","flesh.physmat","water.physmat","plastic_road.physmat","metal_hollow.physmat","cyberware_flesh.physmat","plaster.physmat","plexiglass.physmat","character_vr.physmat","vehicle_chassis.physmat","sand.physmat","glass_electronics.physmat","leaves_stealth.physmat","tarmac.physmat","metal_car.physmat","tiles.physmat","glass_car.physmat","grass.physmat","concrete.physmat","carpet_techpiercable.physmat","wood_hedge.physmat","stone.physmat","leaves_semitransparent.physmat","metal_catwalk.physmat","upholstery_car.physmat","cyberware_metal.physmat","paper.physmat","leather.physmat","metal_pipe_steam.physmat","metal_pipe_water.physmat","metal_semitransparent.physmat","neon.physmat","glass_dst.physmat","plastic_car.physmat","mud.physmat","dirt.physmat","metal_car_pipe_water.physmat","furniture_leather.physmat","asphalt.physmat","wood_bamboo_poles.physmat","glass_opaque.physmat","carpet.physmat","food.physmat","cyberware_metal_head.physmat","metal_road.physmat","wood_tree.physmat","wood_player_npc_semitransparent.physmat","wood.physmat","metal_car_ricochet.physmat","cardboard.physmat","wood_crown.physmat","metal_ricochet.physmat","plastic_electronics.physmat","glass_semitransparent.physmat","metal_painted.physmat","rubber.physmat","ceramic.physmat","glass_bulletproof.physmat","metal_car_electronics.physmat","trash_bag.physmat","character_cyberflesh.physmat","metal_heavypiercable.physmat","metal.physmat","plastic_car_electronics.physmat","oil_spill.physmat","fabrics.physmat","glass.physmat","metal_techpiercable.physmat","concrete_water_puddles.physmat","character_metal.physmat" }
table.sort(materials, function(a, b) return a < b end)

local settingsUI = {}

---@param spawner spawner
function settingsUI.draw(spawner)
    style.sectionHeaderStart("SPAWNING")

    ImGui.PushItemWidth(120 * style.viewSize)
    local pos, changed = ImGui.Combo("##spawnPos", settings.spawnPos - 1, { "At selected", "Screen center" }, 2)
    settings.spawnPos = pos + 1
    if changed then settings.save() end
    if settings.spawnPos == 1 then
        style.tooltip("Spawn the new object at the position of the selected object(s), if none are selected, it will spawn in front of the player")
    else
        style.tooltip("Spawn position is relative to the camera position and orientation.")
    end
    ImGui.SameLine()
    ImGui.Text("Spawn new objects")

    settings.spawnDist, changed = ImGui.InputFloat("Spawn distance from camera", settings.spawnDist, -9999, 9999, "%.1f")
    if changed then settings.save() end
    style.tooltip("Distance from the camera to spawn the object at, used for the fallback for \"At selected\", and always used for \"Screen center\"")

    settings.setLoadedGroupAsSpawnNew, changed = ImGui.Checkbox("Set group as target on load", settings.setLoadedGroupAsSpawnNew)
    if changed then settings.save() end
    style.tooltip("Set group as \"Target Group\" when loading it from the \"Saved\" tab")

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

    settings.draggingThreshold, changed = ImGui.InputFloat("Dragging Threshold", settings.draggingThreshold, 0, 100, "%.1f")
    if changed then
        style.initialize(true)
        settings.save()
    end
    style.tooltip("A threshold for all dragging operations, such as the ones in the scene hierarchy.")

    settings.nodeRefPrefix, changed = ImGui.InputTextWithHint("NodeRef Prefix", "", settings.nodeRefPrefix, 128)
    if changed then settings.save() end
    style.tooltip("Prefix to add when auto generating NodeRef")

    settings.defaultColliderMaterial, changed = ImGui.Combo("Default Collider Material", settings.defaultColliderMaterial, materials, #materials)
    if changed then settings.save() end

    style.sectionHeaderEnd()
    style.sectionHeaderStart("EDITOR MODE")

    settings.cameraMovementSpeed, changed = ImGui.InputFloat("Camera Movement Speed", settings.cameraMovementSpeed, 0, 10, "%.2f")
    if changed then settings.save() end

    settings.cameraRotateSpeed, changed = ImGui.InputFloat("Camera Rotation Speed", settings.cameraRotateSpeed, 0, 10, "%.2f")
    if changed then settings.save() end

    settings.cameraZoomSpeed, changed = ImGui.InputFloat("Camera Zoom Speed", settings.cameraZoomSpeed, 0, 10, "%.2f")
    if changed then settings.save() end

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

    settings.defaultAISpotNPC, changed = ImGui.InputTextWithHint("Default AI Spot NPC", "Character.", settings.defaultAISpotNPC, 128)
    if changed then
        settings.defaultAISpotNPC = string.gsub(settings.defaultAISpotNPC, "[\128-\255]", "")
        settings.save()
    end

    settings.defaultAISpotSpeed, changed = ImGui.InputFloat("Default AI Spot Animation Speed", settings.defaultAISpotSpeed, 0, 25, "%.1f")
    if changed then settings.save() end

    style.sectionHeaderEnd()
    style.sectionHeaderStart("COLLIDERS")

    settings.colliderColor, changed = ImGui.Combo("Collider color", settings.colliderColor, colliderColors, #colliderColors)
    if changed then settings.save() end

    style.sectionHeaderEnd()
    style.sectionHeaderStart("CACHE")

    if ImGui.TreeNodeEx("Cache Exlusions", ImGuiTreeNodeFlags.SpanFullWidth) then
        style.tooltip("List of resource paths for which properties (E.g. Appearances, BBOX) should not be cached")

        local x, _ = ImGui.GetContentRegionAvail()
        if ImGui.BeginChild("##list", -1, 115 * style.viewSize) then
            x = x - (30 * style.viewSize) - (ImGui.GetScrollMaxY() > 0 and ImGui.GetStyle().ScrollbarSize or 0)
            for key, exclusion in pairs(settings.cacheExlusions) do
                ImGui.PushID(key)
                ImGui.SetNextItemWidth(x)
                settings.cacheExlusions[key], changed = ImGui.InputTextWithHint("##exclusion", "base\\entity.ent", exclusion, 128)
                if changed then
                    settings.save()
                end
                ImGui.SameLine()
                if ImGui.Button(IconGlyphs.Delete) then
                    table.remove(settings.cacheExlusions, key)
                    settings.save()
                end
                ImGui.PopID()
            end

            if ImGui.Button("+") then
                table.insert(settings.cacheExlusions, "")
                settings.save()
            end

            ImGui.EndChild()
        end

        ImGui.TreePop()
    else
        style.tooltip("List of resource paths for which properties (E.g. Appearances, BBOX) should not be cached")
    end

    if ImGui.Button("Clear cache") then
        cache.reset()
        ImGui.ShowToast(ImGui.Toast.new(ImGui.ToastType.Success, 2500, "Cleared cache"))
    end
    style.tooltip("Clears the cache")

    style.sectionHeaderEnd()
    style.sectionHeaderStart("MISC")

    settings.headerState, changed = ImGui.Checkbox("Close collapsible headers by default", settings.headerState)
    if changed then settings.save() end

    settings.deleteConfirm, changed = ImGui.Checkbox("Show confirm to delete popup", settings.deleteConfirm)
    if changed then settings.save() end

    settings.despawnOnReload, changed = ImGui.Checkbox("Despawn everything on \"Reload all mods\"", settings.despawnOnReload)
    if changed then settings.save() end

    settings.ignoreHiddenDuringExport, changed = ImGui.Checkbox("Ignore hidden elements during export", settings.ignoreHiddenDuringExport)
    if changed then settings.save() end

    local index, changed = ImGui.Combo("Main Window Name", math.max(0, utils.indexValue(windowNames, settings.mainWindowName) - 1), windowNames, #windowNames)
    if changed then
        settings.mainWindowName = windowNames[index + 1]
        spawner.baseUI.restoreWindowPosition = true
        spawner.baseUI.loadTabSize = true
        settings.save()
    end

    ImGui.PopItemWidth()
    style.sectionHeaderEnd(true)
end

return settingsUI