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

    self.strength, changed = ImGui.DragFloat("##strength", self.strength, 0.5, 0, 9999, "%.1f Light Intensity")
    self.color, changed = ImGui.ColorEdit3("##color", self.color)
end

function light:export()
    local data = spawnable.export(self)
    data.type = "worldStaticLightNode"
    data.data = {
        color = {
            ["Red"] = math.floor(self.color[1] * 255),
            ["Green"] = math.floor(self.color[2] * 255),
            ["Blue"] = math.floor(self.color[3] * 255)
        },
        intensity = self.strength
    }

    return data
end

return light