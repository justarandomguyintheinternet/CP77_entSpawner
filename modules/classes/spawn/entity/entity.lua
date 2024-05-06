local style = require("modules/ui/style")
local spawnable = require("modules/classes/spawn/spawnable")
local entity = setmetatable({}, { __index = spawnable })
local builder = require("modules/utils/entityBuilder")
local utils = require("modules/utils/utils")

function entity:new()
	local o = spawnable.new(self)

    o.boxColor = {255, 255, 0}
    o.spawnListType = "list"
    o.dataType = "Entity"
    o.modulePath = "entity/entity"

    o.apps = {}
    o.appIndex = 0

    o.spawnData = ""

    setmetatable(o, { __index = self })
   	return o
end

function entity:loadSpawnData(data, position, rotation, spawner)
    spawnable.loadSpawnData(self, data, position, rotation, spawner)

    builder.registerLoadResource(self.spawnData, function (resource)
        for _, appearance in ipairs(resource.appearances) do
            table.insert(self.apps, appearance.name.value)
        end
    end)

    self.appIndex = utils.indexValue(self.apps, self.app) - 1
end

function entity:draw()
    spawnable.draw(self)

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()

    if ImGui.Button("Copy Path to Clipboard") then
        ImGui.SetClipboardText(self.spawnData)
    end
    style.tooltip("Copies the template path / record of the object to the clipboard")

    ImGui.SameLine()

    style.pushGreyedOut(#self.apps == 0)

    local list = self.apps

    if #self.apps == 0 then
        list = {"No apps"}
    end

    ImGui.SetNextItemWidth(150)
    local index, changed = ImGui.Combo("##app", self.appIndex, list, #list)
    if changed and #self.apps > 0 then
        self.appIndex = index
        self.app = self.apps[self.appIndex + 1]

        local entity = self:getEntity()

        if entity then
            entity:ScheduleAppearanceChange(self.app)
        end
    end
    style.popGreyedOut(#self.apps == 0)
end

return entity