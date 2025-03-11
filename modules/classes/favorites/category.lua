local utils = require("modules/utils/utils")
local settings = require("modules/utils/settings")
local history = require("modules/utils/history")

---@class category
---@field name string
---@field icon string
---@field headerOpen boolean
---@field favorites favorite[]
---@field fileName string
---@field favoritesUI favoritesUI
local category = {}

function category:new(fUI)
	local o = {}

	o.name = "New Category"
	o.icon = ""
	o.headerOpen = false
	o.favorites = {}

    o.favoritesUI = fUI
	o.fileName = ""

	self.__index = self
   	return setmetatable(o, self)
end

---Loads the data from a given table, containing the same data as exported during save()
function category:load(data, fileName)
	self.name = data.name
	self.headerOpen = data.headerOpen
    self.icon = data.icon
	self.fileName = fileName

	for _, favoriteData in pairs(data.favorites) do
		local favorite = require("modules/classes/favorites/favorite"):new(self.favoritesUI)
		favorite:load(favoriteData)
		self:addFavorite(favorite)
	end
end

function category:generateFileName()
	self.fileName = utils.createFileName(self.name) .. "_" .. tostring(os.time()) .. ".json"
end

function category:addFavorite(favorite)
	table.insert(self.favorites, favorite)
	favorite:setCategory(self)

	self:save()
end

function category:removeFavorite(favorite)
	for key, data in pairs(self.favorites) do
		if data == favorite then
			table.remove(self.favorites, key)
			break
		end
	end

	self:save()
end

function category:isNameDuplicate(name)
	local found = 0

	for _, favorite in pairs(self.favorites) do
		if favorite.name == name and found < 2 then
			found = found + 1
			if found == 2 then
				return true
			end
		end
	end

	return false
end

function category:serialize()
	local data = {
		name = self.name,
		icon = self.icon,
		headerOpen = self.headerOpen,
		favorites = {}
	}

	for _, favorite in pairs(self.favorites) do
		table.insert(data.favorites, favorite:serialize())
	end

	return data
end

function category:save()
	local data = self:serialize()

	config.saveFile("data/favorite/" .. self.fileName, data)
end

return category