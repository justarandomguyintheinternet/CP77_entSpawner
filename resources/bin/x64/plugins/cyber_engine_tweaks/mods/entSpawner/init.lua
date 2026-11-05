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

local about = require("modules/utils/core/about")
local settings = require("modules/utils/core/settings")
local config = require("modules/utils/core/config")
local backup = require("modules/utils/project/backup")
local logger = require("modules/utils/core/logger")
local saveState = require("modules/utils/project/saveState")
local builder = require("modules/utils/game/entityBuilder")
local Cron = require("modules/utils/vendor/Cron")
local groupLoadManager = require("modules/utils/pipeline/groupLoadManager")
local groupExportManager = require("modules/utils/pipeline/groupExportManager")
local persistenceManager = require("modules/utils/pipeline/persistenceManager")
local sessionSnapshot = require("modules/utils/pipeline/sessionSnapshot")
local cache = require("modules/utils/game/cache")
local style = require("modules/ui/style")
local history = require("modules/utils/project/history")
local input = require("modules/utils/core/input")
local registry = require("modules/utils/game/nodeRefRegistry")
local rht = require("modules/utils/interop/rhtPlugin")
local preview = require("modules/utils/preview/previewUtils")
local previewSyncManager = require("modules/utils/preview/previewSyncManager")
local bendedPool = require("modules/utils/preview/bendedPool")
local bendedCollisionPreview = require("modules/utils/preview/bendedCollisionPreview")

---@class spawner
---@field runtimeData {cetOpen: boolean, inGame: boolean, inMenu: boolean}
---@field baseUI baseUI
---@field player any
---@field version string
---@field about table
spawner = {
    player = nil,
    runtimeData = {
        cetOpen = false,
        inGame = false,
        inMenu = false
    },

    -- Public API for other mods, reached through GetMod("entSpawner"):
    -- version / getVersion() for the mod version, about for the full metadata (author, maintainer,
    -- contributors, dependency descriptors), getDependencies() for their current state.
    version = about.version,
    about = about,

    ---@return string
    getVersion = function()
        return about.version
    end,

    ---@return aboutDependencyStatus[]
    getDependencies = function()
        return about.getDependencies()
    end,

    e = function(data)
        local red = require("modules/utils/interop/redConverter")
        config.saveFile("wkit.json", red.redDataToJSON(data))
    end,

    i = function(data)
        local red = require("modules/utils/interop/redConverter")
        red.JSONToRedData(config.loadFile("wkit.json"), data)
    end,

    baseUI = require("modules/ui/baseUI"),
    editor = require("modules/utils/editor/editor"),
    GameUI = require("modules/utils/vendor/GameUI")
}

-- local x = collectgarbage("count")

function spawner:new()
    registerForEvent("onInit", function()
        self.player = Game.GetPlayer()
        settings.load()
        previewSyncManager.reset()
        cache.load()
        cache.generateRecordsList()

        -- Validate the backup folder tree (the sandbox cannot create it, so a missing folder has to
        -- surface in the log rather than silently failing at the first save), and clear any write
        -- artifacts a crash mid-save left behind.
        backup.init()
        local sweptTemp = config.sweepTempFiles("data/objects")
        if sweptTemp > 0 then
            logger:info("[Spawner] Removed " .. tostring(sweptTemp) .. " stale temp file(s) from data/objects")
        end

        self.baseUI.init()
        self.baseUI.savedUI.spawner = self
        self.baseUI.savedUI.backwardComp()
        self.baseUI.savedUI.filter = settings.savedUIFilter
        self.baseUI.spawnUI.filter = settings.spawnUIFilter
        self.baseUI.spawnUI.loadSpawnData(self)
        self.baseUI.spawnUI.prefabsUI.init(self)
        self.baseUI.spawnUI.favoritesUI.init(self)

        self.baseUI.spawnedUI.spawner = self
        self.baseUI.spawnedUI.cachePaths()
        self.baseUI.spawnedUI.registerHotkeys()
        self.baseUI.savedUI.reload()

        self.baseUI.exportUI.init(self)
        history.spawnedUI = self.baseUI.spawnedUI
        saveState.spawnedUI = self.baseUI.spawnedUI
        -- Reads only the snapshot's index line, so this stays cheap no matter how big the payload is.
        sessionSnapshot.init()
        registry.init(self)

        self.editor.init(self)
        rht.init(self)

        Game.GetScriptableServiceContainer():GetService("EntityBuilder"):Initialize()
        builder.init()

        if not ModArchiveExists("scc_collision.archive") then
            print("[World Builder] scc_collision.archive not found. Collision mesh preview will not be available.\nIf you wish to have collision mesh previews, please download the optional \"Collision Mesh Preview\" archive from either the World Builder page on Nexus or GitHub, and install it.")
        end

        Observe('RadialWheelController', 'OnIsInMenuChanged', function(_, isInMenu)
            self.runtimeData.inMenu = isInMenu
        end)

        -- fromRecursive = true on both: visibility still propagates to every child, it only gates the
        -- history action, which would otherwise snapshot the whole tree and truncate the redo tail.
        -- Engine-driven, not a user edit, so dirty marking is suppressed too.
        local function setRootVisible(state)
            saveState.pushSuppress()
            local ok, err = pcall(function()
                self.baseUI.spawnedUI.root:setVisible(state, true)
            end)
            saveState.popSuppress()

            if not ok then
                logger:error("[Spawner] Failed to apply root visibility: " .. tostring(err))
            end
        end

        self.GameUI.OnSessionStart(function()
            self.runtimeData.inGame = true
            previewSyncManager.reset()
            bendedPool.reset()
            bendedCollisionPreview.reset()
            setRootVisible(true)
            preview.addHUD()
        end)

        self.GameUI.OnSessionEnd(function()
            self.runtimeData.inGame = false
            setRootVisible(false)
            preview.elements = {}
            previewSyncManager.reset()
            bendedPool.reset()
            bendedCollisionPreview.reset()
        end)

        self.runtimeData.inGame = not self.GameUI.IsDetached()

        if self.runtimeData.inGame then
            preview.addHUD()
        end
    end)

    registerForEvent("onUpdate", function (dt)
        if not self.editor then return end

        -- Keep Cron alive while a queued group pipeline is active, even if menu state is reported as open.
        if self.runtimeData.inGame and (not self.runtimeData.inMenu or groupLoadManager.isActive() or groupExportManager.isActive()) then
            Cron.Update(dt)
            previewSyncManager.update(dt)
            bendedPool.update()
            bendedCollisionPreview.update(dt)
        end

        -- Deliberately outside the guard above: this is pure Lua over already-cached state, and it is
        -- time-based. Gating it on "in game and not in a menu" would stop the auto-save clock exactly
        -- while someone is tabbed out, which is when a crash is most likely to cost work.
        persistenceManager.update(dt)

        if self.editor.camera then
            self.editor.camera.deltaTime = dt
        end
    end)

    registerForEvent("onShutdown", function ()
        -- Explicit saves are queued onto a frame-budgeted pipeline, so a reload can arrive while some
        -- are still waiting. Finish them here rather than dropping work the user asked to save.
        persistenceManager.flushPendingManualSaves()
        bendedPool.setInstantDissolve(false)

        if settings.despawnOnReload then
            self.baseUI.spawnedUI.root:remove()
        end
    end)

    registerForEvent("onDraw", function()
        if not self.editor then return end

        style.initialize(true)
        self.editor.suspend(self.runtimeData.cetOpen)
        bendedCollisionPreview.onDraw(self.runtimeData.cetOpen)

        if self.runtimeData.cetOpen then
            self.editor.onDraw()
            self.baseUI.draw(self)
            input.update()
        else
            self.baseUI.spawnUI.hidden()
        end

        -- if ImGui.Begin("Collect", ImGuiWindowFlags.AlwaysAutoResize) then
        --     ImGui.Text("Memory delta: " .. string.format("%.2f", collectgarbage("count") - x) .. " KB")
        --     x = collectgarbage("count")
        --     ImGui.End()
        -- end
    end)

    registerForEvent("onOverlayOpen", function()
        self.runtimeData.cetOpen = true
        bendedPool.setInstantDissolve(true)
    end)

    registerForEvent("onOverlayClose", function()
        self.runtimeData.cetOpen = false
        bendedPool.setInstantDissolve(false)

        -- Arrow distance scaling is driven from onDraw, which stops running here. Reset now so no
        -- gizmo is left frozen at the size it had for a far-away camera. (editor.toggle does the same
        -- on its own exit path, this covers closing the overlay without editor mode ever being on.)
        if self.editor and self.editor.resetArrowScale then
            self.editor.resetArrowScale()
        end
    end)

    return self
end

return spawner:new()
