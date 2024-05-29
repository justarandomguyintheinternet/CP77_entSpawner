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

spawner = {
    runtimeData = {
        cetOpen = false,
        inGame = false,
        inMenu = false
    },

    baseUI = require("modules/ui/baseUI"),
    GameUI = require("modules/utils/GameUI")
}

function spawner:new()
    registerForEvent("onHook", function ()
        builder.hook()
    end)

    registerForEvent("onInit", function()
        settings.load()
        cache.load()
        cache.generateRecordsList()

        self.baseUI.savedUI.spawner = self
        self.baseUI.savedUI.backwardComp()
        self.baseUI.savedUI.filter = settings.savedUIFilter
        self.baseUI.spawnUI.filter = settings.spawnUIFilter
        self.baseUI.spawnUI.loadSpawnData(self)

        self.baseUI.favUI.load(self)
        self.baseUI.spawnedUI.spawner = self
        self.baseUI.spawnedUI.getGroups()
        self.baseUI.savedUI.reload()

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
            self.baseUI.savedUI.run(self)
        end
    end)

    registerForEvent("onShutdown", function ()
        if settings.despawnOnReload then
            self.baseUI.spawnedUI.despawnAll()
        end
    end)

    registerForEvent("onDraw", function()
        if self.runtimeData.cetOpen then
            self.baseUI.draw(self)
        end
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