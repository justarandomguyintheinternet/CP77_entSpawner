local utils = require("modules/utils/utils")
local settings = require("modules/utils/settings")
local history = require("modules/utils/history")

---@class favorite
---@field name string
---@field tags table
---@field data positionable
---@field category category?
local favorite = {}

---@param fUI favoritesUI
---@return favorite
function favorite:new(fUI)
	local o = {}

	o.name = "New Favorite"
    o.tags = {}
    o.data = nil
    o.category = nil

    o.favoritesUI = fUI

	self.__index = self
   	return setmetatable(o, self)
end

---Loads the data from a given table, containing the same data as exported during serialize()
function favorite:load(data)
	self.name = data.name
    self.tags = data.tags
    self.data = data.data
end

function favorite:setCategory(category)
    self.category = category
end

function favorite:serialize()
	local data = {
		name = self.name,
        tags = self.tags,
        data = self.data
	}

	return data
end

return favorite