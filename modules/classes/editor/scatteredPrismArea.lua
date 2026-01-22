local scatteredValue = require("modules/classes/editor/scatteredValue")
local scatteredAreaBase = require("modules/classes/editor/scatteredAreaBase")

---@class scatteredPrismArea : scatteredAreaBase
---@field v1 Vector2
---@field v2 Vector2
---@field v3 Vector2
---@field z number
local scatteredPrismArea = scatteredAreaBase:new()

---@param owner element
---@return scatteredPrismArea
function scatteredPrismArea:new(owner)
	local o = scatteredAreaBase:new(owner)
    
    o.v1 = { x = 0, y = 0 }
    o.v2 = { x = 1, y = 1 }
    o.v3 = { x = -1, y = 1 }
    o.z = 0

	self.__index = self
   	local outClass = setmetatable(o, self)
    return outClass
end

function scatteredPrismArea:calculateVolume()
    local cross = (self.v2.x - self.v1.x) * (self.v3.y - self.v1.y) - (self.v2.y - self.v1.y) * (self.v3.x - self.v1.x)
    local triArea = 0.5 * math.abs(cross)
    local h = self.z

    -- to avoid no instances when area is a flat shape
    if h == 0 then
        h = 1
    end

    self.volume = triArea * h
end

---@return Vector4
function scatteredPrismArea:getRandomInstancePositionOffset()
    -- Generate random point on triangle surface using barycentric coordinates
    local r1 = math.random()
    local r2 = math.random()
    local sqrt_r1 = math.sqrt(r1)
    
    local u = 1 - sqrt_r1
    local v = r2 * sqrt_r1
    
    local x = self.v1.x + u * (self.v2.x - self.v1.x) + v * (self.v3.x - self.v1.x)
    local y = self.v1.y + u * (self.v2.y - self.v1.y) + v * (self.v3.y - self.v1.y)
    
    local z = math.random(0, self.z)

    return Vector4.new(x, y, z, 1)
end

---@return void
function scatteredPrismArea:draw()

end

---@param owner element
---@param data table
---@return scatteredPrismArea
function scatteredPrismArea:load(owner, data)
    local new = scatteredAreaBase.load(self, owner, data)
    
    new.v1 = { x = data.v1.x, y = data.v1.y }
    new.v2 = { x = data.v2.x, y = data.v2.y }
    new.v3 = { x = data.v3.x, y = data.v3.y }
    new.z = data.z
    
    new:calculateVolume()

    return new
end

---@return table
function scatteredPrismArea:serialize()
    local baseData = scatteredAreaBase.serialize(self)

    baseData.v1 = { x = self.v1.x, y = self.v1.y }
    baseData.v2 = { x = self.v2.x, y = self.v2.y }
    baseData.v3 = { x = self.v3.x, y = self.v3.y }
    baseData.z = self.z

    return baseData
end

return scatteredPrismArea