local scatteredValue = require("modules/classes/editor/scatteredValue")

---@class scatteredAreaBase
---@field volume number
---@field densityScale number
---@field owner element
local scatteredAreaBase = {}

---@param owner element
---@return scatteredAreaBase
function scatteredAreaBase:new(owner)
	local o = {}
    o.owner = owner
    o.volume = 0
    o.densityScale = 1000 -- 10m³
    
	self.__index = self
   	return setmetatable(o, self)
end

---@param density scatteredValue
---@return number
function scatteredAreaBase:getInstancesCount(density)
    local min = (density.min / self.densityScale) * self.volume
    local max = (density.max / self.densityScale) * self.volume

    return math.floor(math.random(min, max))
end

---@param owner element
---@param data table
---@return scatteredAreaBase
function scatteredAreaBase:load(owner, data)
    local new = self:new(owner)
    new.volume = data.volume
    return new
end

---@return table
function scatteredAreaBase:serialize()
    return {
        volume = self.volume
    }
end

-- Abstract methods to be implemented by subclasses
function scatteredAreaBase:calculateVolume()
    
end

function scatteredAreaBase:getRandomInstancePositionOffset()
    
end

function scatteredAreaBase:draw()
    
end

return scatteredAreaBase
