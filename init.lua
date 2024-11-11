-- _                       __          ___
-- | |                      \ \        / / |
-- | | _____  __ _ _ __  _   \ \  /\  / /| |__   ___  ___ _______
-- | |/ / _ \/ _` | '_ \| | | \ \/  \/ / | '_ \ / _ \/ _ \_  / _ \
-- |   <  __/ (_| | | | | |_| |\  /\  /  | | | |  __/  __// /  __/
-- |_|\_\___|\__,_|_| |_|\__,_| \/  \/   |_| |_|\___|\___/___\___|
-------------------------------------------------------------------------------------------------------------------------------
-- This mod was created by keanuWheeze from CP2077 Modding Tools Discord.
--
-- You are free to use this mod as long as you follow the following license guidelines:
--    * It may not be uploaded to any other site without my express permission.
--    * Using any code contained herein in another mod requires full credits / asking me.
--    * You may not fork this code and make your own competing version of this mod available for download without my permission.
--
-------------------------------------------------------------------------------------------------------------------------------

local settings = require("modules/utils/settings")
local builder = require("modules/utils/entityBuilder")
local Cron = require("modules/utils/Cron")
local cache = require("modules/utils/cache")
local drag = require("modules/utils/dragHelper")
local style = require("modules/ui/style")
local history = require("modules/utils/history")
local input = require("modules/utils/input")

---@class spawner
---@field runtimeData {cetOpen: boolean, inGame: boolean, inMenu: boolean}
---@field baseUI baseUI
---@field player any
spawner = {
    player = nil,
    runtimeData = {
        cetOpen = false,
        inGame = false,
        inMenu = false
    },

    e = function(data)
        local red = require("modules/utils/redConverter")
        config.saveFile("wkit.json", red.redDataToJSON(data))
    end,

    i = function(data)
        local red = require("modules/utils/redConverter")
        red.JSONToRedData(config.loadFile("wkit.json"), data)
    end,

    baseUI = require("modules/ui/baseUI"),
    GameUI = require("modules/utils/GameUI")
}

-- local x = collectgarbage("count")
local edit = false

function spawner:new()
    registerForEvent("onHook", function ()
        builder.hook()
    end)

    registerForEvent("onInit", function()
        self.player = Game.GetPlayer()
        settings.load()
        cache.load()
        cache.generateRecordsList()

        self.baseUI.init()
        self.baseUI.savedUI.spawner = self
        self.baseUI.savedUI.backwardComp()
        self.baseUI.savedUI.filter = settings.savedUIFilter
        self.baseUI.spawnUI.filter = settings.spawnUIFilter
        self.baseUI.spawnUI.loadSpawnData(self)

        self.baseUI.spawnedUI.spawner = self
        self.baseUI.spawnedUI.cachePaths()
        self.baseUI.spawnedUI.registerHotkeys()
        self.baseUI.savedUI.reload()

        self.baseUI.exportUI.init()
        history.spawnedUI = self.baseUI.spawnedUI

        self.camera = require("modules/utils/editor/camera")

        Observe('RadialWheelController', 'OnIsInMenuChanged', function(_, isInMenu)
            self.runtimeData.inMenu = isInMenu
        end)

        self.GameUI.OnSessionStart(function()
            self.runtimeData.inGame = true
        end)

        self.GameUI.OnSessionEnd(function()
            self.runtimeData.inGame = false
        end)

        self.runtimeData.inGame = not self.GameUI.IsDetached()
    end)

    registerForEvent("onUpdate", function (dt)
        if self.runtimeData.inGame and not self.runtimeData.inMenu then
            Cron.Update(dt)
        end

        self.camera.deltaTime = dt
    end)

    registerForEvent("onShutdown", function ()
        if settings.despawnOnReload then
            self.baseUI.spawnedUI.root:remove()
        end
    end)

    registerForEvent("onDraw", function()
        style.initialize()
        self.camera.suspend(self.runtimeData.cetOpen)

        if self.runtimeData.cetOpen then
            drag.draw()
            self.baseUI.draw(self)
            input.update()
            self.camera.update()

            local width, height = GetDisplayResolution()
            ImGui.SetNextWindowSizeConstraints(250, height, width / 2, height)
            ImGui.SetNextWindowPos(width, 0, ImGuiCond.Always, 1, 0)

            style.pushStyleColor(true, ImGuiCol.WindowBg, 0, 0, 0, 1)
            ImGui.PushStyleVar(ImGuiStyleVar.WindowRounding, 0)

            if ImGui.Begin("Editor", true, ImGuiWindowFlags.NoCollapse + ImGuiWindowFlags.NoTitleBar) then
                local xSize, _ = ImGui.GetWindowSize()

                self.camera.updateXOffset(- (xSize / width))

                edit, changed = ImGui.Checkbox("Edit", edit)
                if changed then
                    self.camera.toggle(edit)
                end

                -- if ImGui.IsKeyDown(ImGuiKey.X) then
                --     local x, y = ImGui.GetMousePos()
                --     local width, height = GetDisplayResolution()

                --     local spec = StaticEntitySpec.new()
                --     spec.templatePath = "base\\open_world\\props\\synthetic_can_a_soda.ent"
                --     local pos, _ = screenToWorld(((x / width) * 2) - 1, - (((y / height) * 2) - 1))
                --     spec.position = pos
                --     spec.orientation = Quaternion.new()
                --     spec.attached = true
                --     Game.GetStaticEntitySystem():SpawnEntity(spec)
                -- end

                ImGui.End()
            end

            style.popStyleColor(true)
            ImGui.PopStyleVar()
        end

        -- if ImGui.Begin("Collect", ImGuiWindowFlags.AlwaysAutoResize) then
        --     ImGui.Text("Memory delta: " .. string.format("%.2f", collectgarbage("count") - x) .. " KB")
        --     x = collectgarbage("count")
        --     ImGui.End()
        -- end
    end)

    registerForEvent("onOverlayOpen", function()
        self.runtimeData.cetOpen = true
    end)

    registerForEvent("onOverlayClose", function()
        self.runtimeData.cetOpen = false
    end)

    return self
end

return spawner:new()