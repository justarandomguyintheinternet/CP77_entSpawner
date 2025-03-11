local utils = require("modules/utils/utils")
local settings = require("modules/utils/settings")
local history = require("modules/utils/history")

---@class category
---@field name string
---@field icon string
---@field headerOpen boolean
---@field favorites table
local category = {}

function category:new(fUI)
	local o = {}

	o.name = "New Category"
	o.icon = ""
	o.headerOpen = false

	o.favorites = {}

    o.favoritesUI = fUI

	self.__index = self
   	return setmetatable(o, self)
end

---Loads the data from a given table, containing the same data as exported during save()
function category:load(data)
	self.name = data.name
	self.headerOpen = data.headerOpen
    self.icon = data.icon
end

function category:serialize()
	local data = {
		name = self.name,
		modulePath = self.modulePath,
		headerOpen = self.headerOpen,
		propertyHeaderStates = self.propertyHeaderStates,
		visible = self.visible,
		hiddenByParent = self.hiddenByParent,
		expandable = self.expandable,
		selected = self.selected,
		isUsingSpawnables = true,
		childs = {}
	}

	for _, child in pairs(self.childs) do
		table.insert(data.childs, child:serialize())
	end

	return data
end

function category:save()
	local data = self:serialize()

	if self.fileName ~= self.name then
		self.fileName = self.name
	end

	config.saveFile("data/objects/" .. self.fileName .. ".json", data)
end

return category