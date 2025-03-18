local CodewareVersion = "1.14.1"
local ArchiveXLVersion = "1.20.0"

local settings = require("modules/utils/settings")
local style = require("modules/ui/style")
local editor = require("modules/utils/editor/editor")
local input = require("modules/utils/input")

---@class baseUI
baseUI = {
    spawnUI = require("modules/ui/spawnUI"),
    spawnedUI = require("modules/ui/spawnedUI"),
    savedUI = require("modules/ui/savedUI"),
    exportUI = require("modules/ui/exportUI"),
    settingsUI = require("modules/ui/settingsUI"),
    activeTab = 1,
    loadTabSize = true,
    loadWindowSize = nil,
    mainWindowPosition = { 0, 0 },
    restoreWindowPosition = false,
    requirementsIssues = {}
}

local menuButtonHovered = false

local tabs = {
    {
        id = "spawn",
        name = "Spawn New",
        flags = ImGuiWindowFlags.None,
        defaultSize = { 750, 1000 },
        draw = function ()
            baseUI.spawnedUI.cachePaths()
            baseUI.spawnUI.draw()
        end
    },
    {
        id = "spawned",
        name = "Spawned",
        flags = ImGuiWindowFlags.None,
        defaultSize = { 600, 1200 },
        draw = baseUI.spawnedUI.draw
    },
    {
        id = "saved",
        name = "Saved",
        flags = ImGuiWindowFlags.None,
        defaultSize = { 600, 700 },
        draw = baseUI.savedUI.draw
    },
    {
        id = "export",
        name = "Export",
        flags = ImGuiWindowFlags.None,
        defaultSize = { 600, 700 },
        draw = baseUI.exportUI.draw
    },
    {
        id = "settings",
        name = "Settings",
        flags = ImGuiWindowFlags.AlwaysAutoResize,
        defaultSize = { 600, 1200 },
        draw = baseUI.settingsUI.draw
    }
}

local function isOnlyTab(id)
    for tid, tab in pairs(settings.windowStates) do
        if not tab and tid ~= id then
            return false
        end
    end

    return true
end

local function drawMenuButton()
    ImGui.SameLine()

    local iconWidth, _ = ImGui.CalcTextSize(IconGlyphs.DotsHorizontal)
    ImGui.SetCursorPos(ImGui.GetWindowWidth() - iconWidth - ImGui.GetStyle().WindowPadding.x - 5, (editor.active and 0 or ImGui.GetFrameHeight()) + ImGui.GetStyle().WindowPadding.y)

    style.pushStyleColor(menuButtonHovered, ImGuiCol.Text, style.mutedColor)
    ImGui.SetItemAllowOverlap()
    ImGui.Text(IconGlyphs.DotsHorizontal)
    style.popStyleColor(menuButtonHovered)
    menuButtonHovered = ImGui.IsItemHovered()

    if ImGui.BeginPopupContextItem("##windowMenu", ImGuiPopupFlags.MouseButtonLeft) then
        style.styledText("Separated Tabs:", style.mutedColor, 0.85)

        for _, tab in pairs(tabs) do
            local _, clicked = ImGui.MenuItem(tab.name, '', settings.windowStates[tab.id])
            if clicked and not isOnlyTab(tab.id) then
                settings.windowStates[tab.id] = not settings.windowStates[tab.id]
                settings.save()

                if settings.windowStates[tab.id] then
                    baseUI.loadWindowSize = tab.id
                end
            end
        end

        ImGui.EndPopup()
    end
end

function baseUI.init()
    for _, tab in pairs(tabs) do
        if settings.tabSizes[tab.id] == nil then
            settings.tabSizes[tab.id] = tab.defaultSize
            settings.save()
        end
    end

    if not ArchiveXL then
        table.insert(baseUI.requirementsIssues, "ArchiveXL is not installed")
    elseif not ArchiveXL.Require(ArchiveXLVersion) then
        table.insert(baseUI.requirementsIssues, "ArchiveXL version is outdated, please update to " .. ArchiveXLVersion)
    end

    if not Codeware then
        table.insert(baseUI.requirementsIssues, "Codeware is not installed")
    elseif not Codeware.Require(CodewareVersion) then
        table.insert(baseUI.requirementsIssues, "Codeware version is outdated, please update to " .. CodewareVersion)
    end

    if not Game.GetScriptableServiceContainer():GetService("EntityBuilder") then
        table.insert(baseUI.requirementsIssues, "Redscript part of the mod is not installed")
    end
end

function baseUI.draw(spawner)
    if #baseUI.requirementsIssues > 0 then
        if ImGui.Begin("Object Spawner Error", ImGuiWindowFlags.AlwaysAutoResize) then
            style.mutedText("The following issues are preventing Object Spawner from running:")

            for _, issue in pairs(baseUI.requirementsIssues) do
                ImGui.Text(issue)
            end

            ImGui.End()
        end
        return
    end

    input.resetContext()
    local screenWidth, screenHeight = GetDisplayResolution()
    local editorActive = editor.active

    if baseUI.loadTabSize and not editorActive then
        ImGui.SetNextWindowSize(settings.tabSizes[tabs[baseUI.activeTab].id][1], settings.tabSizes[tabs[baseUI.activeTab].id][2])
        baseUI.loadTabSize = false
    end
    if editorActive then
        ImGui.SetNextWindowSizeConstraints(screenWidth / 8, screenHeight, screenWidth / 2, screenHeight)
        ImGui.SetNextWindowPos(screenWidth, 0, ImGuiCond.Always, 1, 0)
        if baseUI.loadTabSize then
            if settings.editorWidth == 0 then
                settings.editorWidth = settings.tabSizes.spawned[1]
            end
            ImGui.SetNextWindowSize(settings.editorWidth, screenHeight)
        end
        baseUI.loadTabSize = false
    end
    if baseUI.restoreWindowPosition then
        ImGui.SetNextWindowPos(baseUI.mainWindowPosition[1], baseUI.mainWindowPosition[2], ImGuiCond.Always, 0, 0)
        baseUI.restoreWindowPosition = false
    end

    style.pushStyleColor(editorActive, ImGuiCol.WindowBg, 0, 0, 0, 1)
    style.pushStyleVar(editorActive, ImGuiStyleVar.WindowRounding, 0)

    local flags = tabs[baseUI.activeTab].flags
    if editorActive then
        flags = flags + ImGuiWindowFlags.NoCollapse + ImGuiWindowFlags.NoTitleBar
    end

    if ImGui.Begin("Object Spawner 2.0", flags) then
        input.updateContext("main")

        if not editorActive then
            baseUI.mainWindowPosition = { ImGui.GetWindowPos() }
        end

        local x, y = ImGui.GetWindowSize()
        if not editorActive and (x ~= settings.tabSizes[tabs[baseUI.activeTab].id][1] or y ~= settings.tabSizes[tabs[baseUI.activeTab].id][2]) then
            settings.tabSizes[tabs[baseUI.activeTab].id] = { math.min(x, 5000), math.min(y, 3500) }
            settings.save()
        end
        if editorActive and x ~= settings.editorWidth then
            settings.editorWidth = x
            settings.save()
        end

        editor.camera.updateXOffset(- (x / screenWidth))

        if ImGui.BeginTabBar("Tabbar", ImGuiTabItemFlags.NoTooltip) then
            for key, tab in ipairs(tabs) do
                if settings.windowStates[tab.id] == nil then
                    settings.windowStates[tab.id] = false
                    settings.save()
                end

                if not settings.windowStates[tab.id] then
                    if ImGui.BeginTabItem(tab.name) then
                        if baseUI.activeTab ~= key then
                            baseUI.activeTab = key
                            baseUI.loadTabSize = true
                        end
                        ImGui.Spacing()
                        tab.draw(spawner)
                        ImGui.EndTabItem()
                    end
                else
                    ImGui.SetTabItemClosed(tab.name)
                end
            end
            ImGui.EndTabBar()
        end

        drawMenuButton()

        ImGui.End()
    end

    style.popStyleColor(editorActive)
    style.popStyleVar(editorActive)

    for key, tab in pairs(tabs) do
        if settings.windowStates[tab.id] then
            if baseUI.loadWindowSize == tab.id then
                ImGui.SetNextWindowSize(settings.tabSizes[tab.id][1], settings.tabSizes[tab.id][2])
                baseUI.loadWindowSize = nil
            end

            settings.windowStates[tab.id] = ImGui.Begin(tab.name, true, tabs[key].flags)
            input.updateContext("main")

            local x, y = ImGui.GetWindowSize()
            if x ~= settings.tabSizes[tab.id][1] or y ~= settings.tabSizes[tab.id][2] then
                settings.tabSizes[tab.id] = { x, y }
                settings.save()
            end

            if not settings.windowStates[tab.id] then
                settings.save()
            end
            tab.draw(spawner)

            if settings.windowStates[tab.id] then
                ImGui.End()
            end
        end
    end

    baseUI.spawnUI.drawPopup()

    input.context.viewport.hovered = not input.context.main.hovered
    input.context.viewport.focused = not input.context.main.focused
end

return baseUI