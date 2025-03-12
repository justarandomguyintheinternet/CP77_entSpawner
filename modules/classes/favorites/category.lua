local utils = require("modules/utils/utils")
local style = require("modules/ui/style")
local config = require("modules/utils/config")
local settings = require("modules/utils/settings")

---@class category
---@field name string
---@field icon string
---@field headerOpen boolean
---@field favorites favorite[]
---@field grouped boolean
---@field favoritesUI favoritesUI
---@field fileName string
---@field openPopup boolean
---@field editName string
---@field changeIconSearch string
---@field isVirtualGroup boolean
---@field virtualGroupTags string[]
---@field virtualGroups category[]
---@field virtualGroupsPS {}
---@field virtualGroupPath string
---@field numFavoritesFiltered number
---@field root category?
local category = {}

---@param fUI favoritesUI
---@return category
function category:new(fUI)
	local o = {}

	o.name = "New Category"
	o.icon = ""
	o.headerOpen = false
	o.favorites = {}
	o.grouped = false

    o.favoritesUI = fUI
	o.fileName = ""
	o.openPopup = false
	o.editName = ""
	o.changeIconSearch = ""

	o.isVirtualGroup = false
	o.virtualGroupPath = ""
	o.virtualGroupTags = {}
	o.virtualGroups = {}
	o.virtualGroupsPS = {}
	o.numFavoritesFiltered = 0
	o.root = nil

	self.__index = self
   	return setmetatable(o, self)
end

---Loads the data from a given table, containing the same data as exported during save()
function category:load(data, fileName)
	self:setName(data.name)
	self.headerOpen = data.headerOpen
    self.icon = data.icon
	self.fileName = fileName
	self.grouped = data.grouped

	self.isVirtualGroup = data.isVirtualGroup or false
	self.virtualGroupPath = data.virtualGroupPath or ""
	self.virtualGroupTags = data.virtualGroupTags or {}
	self.virtualGroupsPS = data.virtualGroupsPS or {}
	self.virtualGroups = {}
	self.root = data.root

	if self.isVirtualGroup then
		self.favorites = data.favorites
		if not self.virtualGroupsPS[self.virtualGroupPath] then
			self.virtualGroupsPS[self.virtualGroupPath] = {
				headerOpen = false,
				grouped = false
			}
			self:save()
		end
		self.headerOpen = self.virtualGroupsPS[self.virtualGroupPath].headerOpen
		self.grouped = self.virtualGroupsPS[self.virtualGroupPath].grouped
	else
		for _, favoriteData in pairs(data.favorites) do
			local favorite = require("modules/classes/favorites/favorite"):new(self.favoritesUI)
			favorite:load(favoriteData)
			self:addFavorite(favorite)
		end
	end

	if self.grouped then
		self:loadVirtualGroups()
	end
end

function category:setName(name)
	self.name = name
	self.editName = name
end

function category:generateFileName()
	self.fileName = utils.createFileName(self.name) .. "_" .. tostring(os.time()) .. ".json"
end

function category:addFavorite(favorite)
	table.insert(self.favorites, favorite)
	favorite:setCategory(self.root or self)

	self:save()

	if self.grouped then
		self:loadVirtualGroups()
	end
end

function category:removeFavorite(favorite)
	for key, data in pairs(self.favorites) do
		if data == favorite then
			table.remove(self.favorites, key)
			break
		end
	end

	self:save()

	if self.grouped then
		self:loadVirtualGroups()
	end
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

function category:drawEditPopup()
	if ImGui.BeginPopupContextItem("##editCategory" .. self.fileName) then
		self.icon, self.changeIconSearch, changed = self.favoritesUI.drawSelectIcon(self.icon, self.changeIconSearch)
		if changed then
			self:save()
		end

		ImGui.SameLine()

        -- Edit name
        style.setNextItemWidth(200)
        if self.openPopup then
            self.openPopup = false
            ImGui.SetKeyboardFocusHere()
        end
        self.editName, changed = ImGui.InputTextWithHint("##name", "Name...", self.editName, 100)
        if ImGui.IsItemDeactivatedAfterEdit() then
			if not self.favoritesUI.categories[self.editName] then
				self.favoritesUI.updateCategoryName(self.name, self.editName)
				self.name = self.editName
				self:save()
			else
				self.editName = self.name
			end
		end
		if self.name ~= self.editName and self.favoritesUI.categories[self.editName] then
			ImGui.SameLine()
            style.styledText(IconGlyphs.AlertOutline, 0xFF0000FF)
            style.tooltip("Category with this name already exists.")
		end

		-- merge option

		ImGui.Separator()

		-- Confirm / delete
		style.pushButtonNoBG(true)
		if ImGui.Button(IconGlyphs.CheckCircleOutline) then
			ImGui.CloseCurrentPopup()
		end
		style.pushButtonNoBG(false)

		style.pushButtonNoBG(true)
		ImGui.SameLine()
		ImGui.Button(IconGlyphs.Delete)
		if ImGui.BeginPopupContextItem("Delete Category?", ImGuiPopupFlags.MouseButtonLeft) then
			style.mutedText("Are you sure you want to delete this category?")
			if ImGui.Button("Confirm") then
				ImGui.CloseCurrentPopup()
				self:delete()
			end
			ImGui.SameLine()
			if ImGui.Button("Cancle") then
				ImGui.CloseCurrentPopup()
			end
			ImGui.EndPopup()
		end

		style.pushButtonNoBG(false)
		ImGui.EndPopup()
    end

    if self.openPopup then
        ImGui.OpenPopup("##editCategory" .. self.fileName)
    end
end

function category:drawSideButtons()
	ImGui.SetCursorPosY(ImGui.GetCursorPosY() + 2 * (ImGui.GetFontSize() / 15))

    -- Right side buttons
    local settingsX, _ = ImGui.CalcTextSize(IconGlyphs.FileTreeOutline)
    local groupX, _ = ImGui.CalcTextSize(IconGlyphs.CogOutline)
	if self.isVirtualGroup then settingsX = 0 end
	local totalX = settingsX + groupX + ImGui.GetStyle().ItemSpacing.x
    local scrollBarAddition = ImGui.GetScrollMaxY() > 0 and ImGui.GetStyle().ScrollbarSize or 0
    local cursorX = ImGui.GetWindowWidth() - totalX - ImGui.GetStyle().CellPadding.x / 2 - scrollBarAddition + ImGui.GetScrollX()
    ImGui.SetCursorPosX(cursorX)

	local grouped = self.grouped
	style.pushStyleColor(not grouped, ImGuiCol.Text, style.mutedColor)
	ImGui.SetNextItemAllowOverlap()
	if ImGui.Button(IconGlyphs.FileTreeOutline) then
		self.grouped = not self.grouped
		self:loadVirtualGroups()
		self:save()
	end
	style.popStyleColor(not grouped)
	style.tooltip("Group by tags")

	if self.isVirtualGroup then return end

	ImGui.SameLine()
	ImGui.SetCursorPosY(ImGui.GetCursorPosY() + 2 * (ImGui.GetFontSize() / 15))

	ImGui.SetNextItemAllowOverlap()
	if ImGui.Button(IconGlyphs.CogOutline) then
		self.openPopup = true
	end
end

function category:drawEntries(context, entries)
	if self.headerOpen then
		context.depth = context.depth + 1
		for _, entry in pairs(entries) do
			entry:draw(context)
		end
		context.depth = context.depth - 1
	end
end

function category:loadVirtualGroups()
	self.virtualGroups = {}
	local tags = {}

	local anyTag = false
	for _, favorite in pairs(self.favorites) do
		for tag, _ in pairs(favorite.tags) do
			if not self.virtualGroupTags[tag] then
				if not tags[tag] then
					tags[tag] = {}
				end

				table.insert(tags[tag], favorite)
				anyTag = true
			end
		end
	end

	if not anyTag then
		self.grouped = false
		return
	end

	for tag, group in pairs(tags) do
		local cat = require("modules/classes/favorites/category"):new(self.favoritesUI)
		local virtualGroupTags = utils.deepcopy(self.virtualGroupTags)
		virtualGroupTags[tag] = true

		cat:load({
			name = tag,
			headerOpen = false,
			grouped = false,
			favorites = group,
			isVirtualGroup = true,
			virtualGroupTags = virtualGroupTags,
			virtualGroupPath = self.virtualGroupPath .. "/" .. tag,
			virtualGroupsPS = self.virtualGroupsPS,
			root = self.root or self
		}, self.fileName)

		table.insert(self.virtualGroups, cat)
	end
end

function category:getFilteredFavorites()
	local entries = {}

	for _, favorite in pairs(self.favorites) do
		if favorite:isMatch(settings.favoritesFilter, settings.filterTags) then
			table.insert(entries, favorite)
		end
	end

	table.sort(entries, function(a, b) return a.name < b.name end)

	return entries
end

function category:getFilteredEntries()
	local entries = {}

	if not self.grouped then
		entries = self:getFilteredFavorites()
	else
		entries = self.virtualGroups

		for _, group in pairs(self.virtualGroups) do
			group.numFavoritesFiltered = #group:getFilteredFavorites()
		end

		table.sort(entries, function(a, b)
			if a.numFavoritesFiltered == b.numFavoritesFiltered then
				return a.name < b.name
			end

			return a.numFavoritesFiltered > b.numFavoritesFiltered
		end)
	end

	return entries
end

---@param context {padding: number, row: number, depth: number}
function category:draw(context)
	local filtered = self:getFilteredEntries()

	if #filtered == 0 and not (#self.favorites == 0) then
		return
	end

	self.favoritesUI.pushRow(context)

	ImGui.PushID(context.row)

	ImGui.SetCursorPosX((context.depth) * 17 * style.viewSize)
	ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, 4 * style.viewSize, context.padding * 2 + style.viewSize)

    local newState = ImGui.Selectable("##category" .. context.row, self.headerOpen, ImGuiSelectableFlags.SpanAllColumns + ImGuiSelectableFlags.AllowOverlap)
	if self.headerOpen ~= newState then
		self.headerOpen = newState
		self:save()
	end
	context.row = context.row + 1

	ImGui.SameLine()
	ImGui.PushStyleColor(ImGuiCol.Button, 0)
	ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 1, 1, 1, 0.2)
	ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 0, 0)
	ImGui.PushStyleVar(ImGuiStyleVar.ButtonTextAlign, 0.5, 0.5)
	ImGui.SetCursorPosY(ImGui.GetCursorPosY() + 1 * style.viewSize)

	ImGui.SetNextItemAllowOverlap()
	if ImGui.Button(self.headerOpen and IconGlyphs.MenuDownOutline or IconGlyphs.MenuRightOutline) then
		self.headerOpen = not self.headerOpen
		self:save()
	end
	ImGui.SameLine()
	if self.icon ~= "" then
		ImGui.AlignTextToFramePadding()
		ImGui.SetCursorPosY(ImGui.GetCursorPosY() + 2 * style.viewSize)
		ImGui.Text(IconGlyphs[self.icon])
	end
	ImGui.SameLine()
	ImGui.AlignTextToFramePadding()
	ImGui.SetNextItemAllowOverlap()
	ImGui.Text(self.name .. ((self.isVirtualGroup and not self.grouped) and (" (" .. #filtered .. ")") or ""))

	ImGui.SameLine()
	self:drawSideButtons()

	ImGui.PopStyleColor(2)
	ImGui.PopStyleVar(3)

	ImGui.PopID()

	if not self.isVirtualGroup then
		self:drawEditPopup()
	end

	self:drawEntries(context, filtered)
end

function category:serialize()
	local data = {
		name = self.name,
		icon = self.icon,
		headerOpen = self.headerOpen,
		grouped = self.grouped,
		virtualGroupsPS = self.virtualGroupsPS,
		favorites = {}
	}

	for _, favorite in pairs(self.favorites) do
		table.insert(data.favorites, favorite:serialize())
	end

	return data
end

function category:save()
	if self.isVirtualGroup then
		self.virtualGroupsPS[self.virtualGroupPath] = {
			headerOpen = self.headerOpen,
			grouped = self.grouped
		}
		self.root:save()
		return
	end

	local data = self:serialize()

	config.saveFile("data/favorite/" .. self.fileName, data)
end

function category:delete()
	if self.isVirtualGroup then return end

	os.remove("data/favorite/" .. self.fileName)
	self.favoritesUI.categories[self.name] = nil
end

return category