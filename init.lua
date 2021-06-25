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

local config = require("modules/utils/config")

spawner = {
    runtimeData = {
        cetOpen = false,
        inGame = false,
        inMenu = false
    },

    defaultSettings = {
        spawnPos = 1,
        spawnDist = 3,
        posSteps = 0.05,
        rotSteps = 0.05,
        despawnOnReload = true,
        groupRot = false,
        headerState = true,
        deleteConfirm = true,
        moveCloneToParent = 1,
        groupExport = false,
        autoSpawnRange = 500,
        spawnUIOnlyNames = false
    },

    settings = {},
    baseUI = require("modules/ui/baseUI"),
    GameUI = require("modules/utils/GameUI")
}

function spawner:new()
    registerForEvent("onInit", function()
        config.tryCreateConfig("data/config.json", spawner.defaultSettings)
        config.backwardComp("data/config.json", spawner.defaultSettings)
        spawner.settings = config.loadFile("data/config.json")
        spawner.baseUI.spawnUI.loadPaths()
        spawner.baseUI.favUI.load(spawner)
        spawner.baseUI.spawnedUI.spawner = spawner
        spawner.baseUI.spawnedUI.getGroups()
        spawner.baseUI.savedUI.spawner = spawner
        spawner.baseUI.savedUI.reload()

        Observe('RadialWheelController', 'OnIsInMenuChanged', function(_, isInMenu)
            spawner.runtimeData.inMenu = isInMenu
        end)

        spawner.GameUI.OnSessionStart(function()
            spawner.runtimeData.inGame = true
        end)

        spawner.GameUI.OnSessionEnd(function()
            spawner.runtimeData.inGame = false
        end)

        spawner.runtimeData.inGame = not spawner.GameUI.IsDetached()
    end)

    registerForEvent("onUpdate", function ()
        if spawner.runtimeData.inGame and not spawner.runtimeData.inMenu then
            spawner.baseUI.savedUI.run(spawner)
        end
    end)

    registerForEvent("onShutdown", function ()
        if spawner.settings.despawnOnReload then
            spawner.baseUI.spawnedUI.despawnAll()
        end
    end)

    registerForEvent("onDraw", function()
        if spawner.runtimeData.cetOpen then
            spawner.baseUI.draw(spawner)
        end
    end)

    registerForEvent("onOverlayOpen", function()
        spawner.runtimeData.cetOpen = true
    end)

    registerForEvent("onOverlayClose", function()
        spawner.runtimeData.cetOpen = false
    end)

    return spawner

end

return spawner:new()