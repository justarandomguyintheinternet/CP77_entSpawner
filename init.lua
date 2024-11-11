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
local pitch = 0
local utils = require("modules/utils/utils")
local edit = false
local components = {}
local dist = -4
local x = 300

local function screenToWorld(x, y)
    local cameraPosition = GetPlayer():GetFPPCameraComponent():GetLocalToWorld():GetTranslation()
    local cameraRotation = GetPlayer():GetFPPCameraComponent():GetLocalToWorld():GetRotation()
    local pov = Game.GetPlayer():GetFPPCameraComponent():GetFOV()
    local width, height = GetDisplayResolution()

    local vertical = EulerAngles.new(0, pov / 2, 0):GetForward()
    local vecRelative = Vector4.new(vertical.z * (width / height) * x, vertical.y * 1, vertical.z * y, 0)

    vec = Vector4.RotateAxis(vecRelative, Vector4.new(1, 0, 0, 0), math.rad(cameraRotation.pitch))
    vec = Vector4.RotateAxis(vec, Vector4.new(0, 0, 1, 0), math.rad(cameraRotation.yaw))

    return Vector4.new(cameraPosition.x + vec.x, cameraPosition.y + vec.y, cameraPosition.z + vec.z), vecRelative
end

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
    end)

    registerForEvent("onShutdown", function ()
        if settings.despawnOnReload then
            self.baseUI.spawnedUI.root:remove()
        end
    end)

    registerForEvent("onDraw", function()
        style.initialize()

        if self.runtimeData.cetOpen then
            drag.draw()
            self.baseUI.draw(self)
            input.update()

            if not GetPlayer() then return end

            local rot = Game.GetPlayer():GetWorldOrientation():ToEulerAngles()

            if ImGui.IsMouseDragging(ImGuiMouseButton.Middle, 0) then
                local x, y = ImGui.GetMouseDragDelta(ImGuiMouseButton.Middle, 0)
                ImGui.ResetMouseDragDelta(ImGuiMouseButton.Middle)

                if ImGui.IsKeyDown(ImGuiKey.LeftShift) then
                    local camRot = EulerAngles.new(0, pitch, rot.yaw)

                    local pos = GetPlayer():GetWorldPosition()
                    pos = utils.addVector(pos, utils.multVector(camRot:GetUp(), y / 50))
                    pos = utils.subVector(pos, utils.multVector(camRot:GetRight(), x / 50))

                    Game.GetTeleportationFacility():Teleport(Game.GetPlayer(), pos, rot)
                elseif ImGui.IsKeyDown(ImGuiKey.LeftCtrl) then
                    dist = dist + y / 20

                    Game.GetPlayer():GetFPPCameraComponent():SetLocalPosition(Vector4.new(0, dist, 0, 1.0))
                else
                    Game.GetTeleportationFacility():Teleport(Game.GetPlayer(), GetPlayer():GetWorldPosition(), EulerAngles.new(rot.roll, rot.pitch, rot.yaw - x / 20))

                    pitch = pitch - y / 20
                    Game.GetPlayer():GetFPPCameraComponent().pitchMax = pitch
                    Game.GetPlayer():GetFPPCameraComponent().pitchMin = pitch
                end
            else
                Game.GetTeleportationFacility():Teleport(Game.GetPlayer(), GetPlayer():GetWorldPosition(), rot)
            end

            --horizontal = vertical
            -- print(camP.x + vertical.z * 1.7777 * 1, camP.y + vertical.y * 1, camP.z + vertical.z * 1);
            -- camP = Game.GetPlayer():GetFPPCameraComponent():GetLocalToWorld():GetTranslation();
            -- pov = Game.GetPlayer():GetFPPCameraComponent():GetFOV();
            -- vertical = EulerAngles.new(0, pov / 2, 0):GetForward();
            -- vec = Vector4.new(vertical.z * 1.7777 * 1, vertical.y * 1, vertical.z * 1, 0);
            -- vec = Vector4.RotateAxis(vec, Vector4.new(1, 0, 0, 0), math.rad(0));
            -- vec = Vector4.RotateAxis(vec, Vector4.new(0, 0, 1, 0), math.rad(0));
            -- print(camP.x + vec.x, camP.y + vec.y, camP.z + vec.z);

            local width, height = GetDisplayResolution()
            ImGui.SetNextWindowSizeConstraints(250, height, width / 2, height)
            ImGui.SetNextWindowPos(width, 0, ImGuiCond.Always, 1, 0)

            style.pushStyleColor(true, ImGuiCol.WindowBg, 0, 0, 0, 1)
            ImGui.PushStyleVar(ImGuiStyleVar.WindowRounding, 0)

            if ImGui.Begin("Editor", true, ImGuiWindowFlags.NoCollapse + ImGuiWindowFlags.NoTitleBar) then
                local xSize, _ = ImGui.GetWindowSize()

                local centerXCoord = - (xSize / width)
                local _, centerDir = screenToWorld(centerXCoord, 0)
                local camXOffset = ((1 / centerDir.y) * dist) * centerDir.x

                if edit then
                    Game.GetPlayer():GetFPPCameraComponent():SetLocalPosition(Vector4.new(camXOffset, dist, 0, 1.0))
                end

                edit, changed = ImGui.Checkbox("Edit", edit)
                if changed then
                    if edit then
                        components = {}

                        for _, c in pairs(GetPlayer():GetComponents()) do
                            if c:IsA("entIVisualComponent") then
                                table.insert(components, c.name.value)
                                c:Toggle(false)
                            end
                        end

                        Game.GetPlayer():GetFPPCameraComponent():SetLocalPosition(Vector4.new(0, dist, 0, 1.0))
                    else
                        for _, c in pairs(components) do
                            GetPlayer():FindComponentByName(c):Toggle(true)
                        end

                        Game.GetPlayer():GetFPPCameraComponent():SetLocalPosition(Vector4.new(0.0, 0, 0, 1.0))
                    end
                end

                if ImGui.IsKeyDown(ImGuiKey.X) then
                    local x, y = ImGui.GetMousePos()
                    local width, height = GetDisplayResolution()

                    local spec = StaticEntitySpec.new()
                    spec.templatePath = "base\\open_world\\props\\synthetic_can_a_soda.ent"
                    local pos, _ = screenToWorld(((x / width) * 2) - 1, - (((y / height) * 2) - 1))
                    spec.position = pos
                    spec.orientation = Quaternion.new()
                    spec.attached = true
                    Game.GetStaticEntitySystem():SpawnEntity(spec)
                end

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