local style = require("modules/ui/style")
local spawnable = require("modules/classes/spawn/spawnable")
local entity = setmetatable({}, { __index = spawnable })

function entity:new()
	local o = spawnable.new(self)

    o.boxColor = {255, 255, 0}
    o.spawnListType = "list"
    o.dataType = "Entity"
    o.modulePath = "entity/entity"

    o.spawnData = ""

    setmetatable(o, { __index = self })
   	return o
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
end

return entity