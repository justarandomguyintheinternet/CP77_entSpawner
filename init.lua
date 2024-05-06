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
local builder = require("modules/utils/entityBuilder")

spawner = {
    runtimeData = {
        cetOpen = false,
        inGame = false,
        inMenu = false
    },

    defaultSettings = {
        spawnPos = 1,
        spawnDist = 3,
        spawnNewSortAlphabetical = false,
        posSteps = 0.05,
        rotSteps = 0.05,
        despawnOnReload = true,
        groupRot = false,
        headerState = true,
        deleteConfirm = true,
        moveCloneToParent = 1,
        groupExport = false,
        autoSpawnRange = 1000,
        spawnUIOnlyNames = false,
        appFetchTrys = 150,
        editor = {
            color = 1
        }
    },

    settings = {},
    baseUI = require("modules/ui/baseUI"),
    fetcher = require("modules/utils/appFetcher"),
    GameUI = require("modules/utils/GameUI")
}

function spawner:new()
    registerForEvent("onHook", function ()
        builder.hook()
    end)

    registerForEvent("onInit", function()
        config.tryCreateConfig("data/config.json", self.defaultSettings)
        config.backwardComp("data/config.json", self.defaultSettings)
        config.tryCreateConfig("data/apps.json", {})
        self.settings = config.loadFile("data/config.json")
        self.baseUI.savedUI.spawner = self
        self.baseUI.savedUI.backwardComp()
        self.baseUI.spawnUI.loadSpawnData(self)
        self.baseUI.favUI.load(self)
        self.baseUI.spawnedUI.spawner = self
        self.baseUI.spawnedUI.getGroups()
        self.baseUI.spawnedUI.init(self)
        self.baseUI.savedUI.reload()

        local p = require("modules/classes/spawn/parent"):new("Parent")
        print(p:getAge(), p:getName())

        local c = require("modules/classes/spawn/child"):new("Child")
        print(c:getAge(), c:getName(), c:getOriginalAge())
        c:isInSchool()

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

    registerForEvent("onUpdate", function ()
        if self.runtimeData.inGame and not self.runtimeData.inMenu then
            self.baseUI.savedUI.run(self)
            self.fetcher.update()
        end
    end)

    registerForEvent("onShutdown", function ()
        if self.settings.despawnOnReload then
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