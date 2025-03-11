-- Most of the colors and style has been taken from https://github.com/psiberx/cp2077-red-hot-tools

local history = require("modules/utils/history")
local dragBeingEdited = false

local style = {
    mutedColor = 0xFFA5A19B,
    extraMutedColor = 0x96A5A19B,
    highlightColor = 0xFFDCD8D1,
    elementIndent = 35,
    draggedColor = 0xFF00007F,
    targetedColor = 0xFF00007F,
    regularColor = 0xFFFFFFFF
}

local initialized = false

function style.initialize()
    -- if initialized then return end
    -- TODO: Enable this once done
    style.viewSize = ImGui.GetFontSize() / 15
    initialized = true
end

function style.pushGreyedOut(state)
    if not state then return end

    ImGui.PushStyleColor(ImGuiCol.Button, 0xff777777)
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0xff777777)
    ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0xff777777)

    ImGui.PushStyleColor(ImGuiCol.FrameBg, 0xff777777)
    ImGui.PushStyleColor(ImGuiCol.FrameBgHovered, 0xff777777)
    ImGui.PushStyleColor(ImGuiCol.FrameBgActive, 0xff777777)
end

function style.popGreyedOut(state)
    if not state then return end

    ImGui.PopStyleColor(6)
end

function style.pushStyleColor(state, style, ...)
    if not state then return end

    ImGui.PushStyleColor(style, ...)
end

function style.pushStyleVar(state, style, ...)
    if not state then return end

    ImGui.PushStyleVar(style, ...)
end

---@param state boolean
---@param count number?
function style.popStyleVar(state, count)
    if not state then return end

    ImGui.PopStyleVar(count or 1)
end

---@param state boolean
---@param count number?
function style.popStyleColor(state, count)
    if not state then return end

    ImGui.PopStyleColor(count or 1)
end

function style.tooltip(text)
    if ImGui.IsItemHovered() then
        style.setCursorRelative(8, 8)

        ImGui.SetTooltip(text)
    end
end

function style.setCursorRelative(x, y)
    local xC, yC = ImGui.GetMousePos()
    ImGui.SetNextWindowPos(xC + x * style.viewSize, yC + y * style.viewSize, ImGuiCond.Always)
end

function style.lightToolTip(text)
    if ImGui.IsItemHovered() then
        local x, y = ImGui.GetMousePos()
        ImGui.SetNextWindowPos(x + 5 * style.viewSize, y + 5 * style.viewSize, ImGuiCond.Always)
        if ImGui.Begin("##tooltip", ImGuiWindowFlags.NoResize + ImGuiWindowFlags.NoMove + ImGuiWindowFlags.NoTitleBar + ImGuiWindowFlags.NoBackground) then
            style.mutedText(text)
            ImGui.End()
        end
    end
end

function style.spawnableInfo(info)
    if ImGui.IsItemHovered() then
        style.setCursorRelative(8, 8)

        ImGui.BeginTooltip()
        ImGui.PushTextWrapPos(ImGui.GetFontSize() * 20)

        style.mutedText("Node: ")
        ImGui.Text(info.node)
        ImGui.Spacing()
        style.mutedText("Description: ")
        ImGui.Text(info.description)
        ImGui.Spacing()
        style.mutedText("Preview Note: ")
        ImGui.Text(info.previewNote)

        ImGui.EndTooltip()
    end
end

function style.spacedSeparator()
    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()
end

---@param text string
---@param tooltip string?
function style.sectionHeaderStart(text, tooltip)
    ImGui.PushStyleColor(ImGuiCol.Text, style.mutedColor)
    ImGui.SetWindowFontScale(0.85)
    ImGui.Text(text)

    if tooltip then
        style.tooltip(tooltip)
    end

    ImGui.SetWindowFontScale(1)
    ImGui.PopStyleColor()
    ImGui.Separator()
    ImGui.Spacing()

    ImGui.BeginGroup()
    ImGui.AlignTextToFramePadding()
end

function style.sectionHeaderEnd(noSpacing)
    ImGui.EndGroup()

    if not noSpacing then
        ImGui.Spacing()
        ImGui.Spacing()
    end
end

function style.mutedText(text)
    style.styledText(text, style.mutedColor)
end

---@param text string
---@param color number|table?
---@param size number?
function style.styledText(text, color, size)
    style.pushStyleColor(color ~= nil, ImGuiCol.Text, color)
    ImGui.SetWindowFontScale(size or 1)

    ImGui.Text(text)

    style.popStyleColor(color ~= nil)
    ImGui.SetWindowFontScale(1)
end

function style.pushButtonNoBG(push)
    if push then
        ImGui.PushStyleColor(ImGuiCol.Button, 0)
        ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 1, 1, 1, 0.2)
        ImGui.PushStyleVar(ImGuiStyleVar.ButtonTextAlign, 0.5, 0.5)
    else
        ImGui.PopStyleColor(2)
        ImGui.PopStyleVar()
    end
end

function style.toggleButton(text, state)
    style.pushStyleColor(not state, ImGuiCol.Text, style.mutedColor)
    style.pushButtonNoBG(true)
	ImGui.Button(text)
	style.popStyleColor(not state)
	style.pushButtonNoBG(false)
	if ImGui.IsItemClicked() then
		return not state, true
	end
    return state, false
end

function style.setNextItemWidth(width)
    ImGui.SetNextItemWidth(width * style.viewSize)
end

function style.trackedCheckbox(element, text, state, disabled)
    ImGui.BeginDisabled(disabled == true)
    local newState, changed = ImGui.Checkbox(text, state)
    ImGui.EndDisabled()
    if changed then
        history.addAction(history.getElementChange(element))
    end
    return newState, changed
end

function style.trackedDragFloat(element, text, value, step, min, max, format, width)
    width = width or 80
    ImGui.SetNextItemWidth(width * style.viewSize)
    local newValue, changed = ImGui.DragFloat(text, value, step, min, max, format)

    local finished = ImGui.IsItemDeactivatedAfterEdit()
	if finished then
		dragBeingEdited = false
	end
	if changed and not dragBeingEdited then
		history.addAction(history.getElementChange(element))
		dragBeingEdited = true
	end

    newValue = math.max(newValue, min)
    newValue = math.min(newValue, max)

    return newValue, changed, finished
end

function style.trackedIntInput(element, text, value, min, max, width)
    width = width or 80
    ImGui.SetNextItemWidth(width * style.viewSize)
    local newValue, changed = ImGui.InputInt(text, value, min, max)

    local finished = ImGui.IsItemDeactivatedAfterEdit()
	if finished then
		dragBeingEdited = false
	end
	if changed and not dragBeingEdited then
		history.addAction(history.getElementChange(element))
		dragBeingEdited = true
	end

    newValue = math.max(newValue, min)
    newValue = math.min(newValue, max)

    return newValue, changed, finished
end

function style.trackedCombo(element, text, selected, options, width)
    width = width or 100
    ImGui.SetNextItemWidth(width * style.viewSize)

    local newValue, changed = ImGui.Combo(text, selected, options, #options)

    if changed then
        history.addAction(history.getElementChange(element))
    end
    return newValue, changed
end

function style.trackedColor(element, name, color, width)
    width = width or 80
    width = width * 3 + 2 * ImGui.GetStyle().ItemSpacing.x
    ImGui.SetNextItemWidth(width * style.viewSize)

    local newValue, changed = ImGui.ColorEdit3(name, color)

    local finished = ImGui.IsItemDeactivatedAfterEdit()
	if finished then
		dragBeingEdited = false
	end
	if changed and not dragBeingEdited then
		history.addAction(history.getElementChange(element))
		dragBeingEdited = true
	end

    return newValue, changed, finished
end

function style.trackedTextField(element, text, value, hint, width)
    if width == -1 then
        width = (ImGui.GetWindowContentRegionWidth() - ImGui.GetCursorPosX()) / style.viewSize
        width = math.max(width, 140)
    end

    width = width or 80
    ImGui.SetNextItemWidth(width * style.viewSize)
    local newValue, changed = ImGui.InputTextWithHint(text, hint, value, 500)

    local finished = ImGui.IsItemDeactivatedAfterEdit()
	if finished then
        newValue = string.gsub(newValue, "[\128-\255]", "")
		dragBeingEdited = false
	end
	if changed and not dragBeingEdited then
		history.addAction(history.getElementChange(element))
		dragBeingEdited = true
	end

    return newValue, changed, finished
end

function style.getMaxWidth(min)
    local width = (ImGui.GetWindowContentRegionWidth() - ImGui.GetCursorPosX())
    width = math.max(width, min)

    return width / style.viewSize
end

function style.trackedSearchDropdown(element, text, searchHint, value, options, width)
    local finished = false

    ImGui.SetNextItemWidth(width * style.viewSize)
    if (ImGui.BeginCombo(text, value)) then
        local interiorWidth = width - (2 * ImGui.GetStyle().FramePadding.x) - 30
        value, _, finished = style.trackedTextField(element, "##search", value, searchHint, interiorWidth)
        local x, _ = ImGui.GetItemRectSize()

        ImGui.SameLine()
        style.pushButtonNoBG(true)
        if ImGui.Button(IconGlyphs.Close) then
            history.addAction(history.getElementChange(element))
            value = ""
            finished = true
        end
        style.pushButtonNoBG(false)

        local xButton, _ = ImGui.GetItemRectSize()
        if ImGui.BeginChild("##list", x + xButton + ImGui.GetStyle().ItemSpacing.x, 120 * style.viewSize) then
            for _, option in pairs(options) do
                if option:lower():match(value:lower()) and ImGui.Selectable(option) then
                    history.addAction(history.getElementChange(element))
                    value = option
                    finished = true
                    ImGui.CloseCurrentPopup()
                end
            end

            ImGui.EndChild()
        end

        ImGui.EndCombo()
    end

    return value, finished
end

return style