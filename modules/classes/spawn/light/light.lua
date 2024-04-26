local spawnable = require("modules/classes/spawn/spawnable")
local light = setmetatable({}, { __index = spawnable })

function light:new()
	local o = spawnable.new(self)

    o.boxColor = {255, 255, 0}
    o.spawnListType = "files"
    o.dataType = "Static Light"
    o.spawnDataPath = "data/spawnables/lights/"
    o.modulePath = "light/light"

    o.spawnData = ""
    o.color = { 1, 1, 1 }
    o.strength = 100

    setmetatable(o, { __index = self })
   	return o
end

function light:save()
    local data = spawnable.save(self)
    data.color = self.color
    data.strength = self.strength

    return data
end

function light:draw()
    spawnable.draw(self)

    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()

    self.strength, changed = ImGui.DragFloat("##strength", self.strength, 0.5, 0, 9999, "%.1f Light Strength")
    self.color, changed = ImGui.ColorEdit3("##color", self.color)
end

return light