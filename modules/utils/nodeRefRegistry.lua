local utils = require("modules/utils/utils")
local settings = require("modules/utils/settings")
local style = require("modules/ui/style")
local history = require("modules/utils/history")

---@class nodeRefRegistry
---@field spawnedUI spawnedUI?
---@field refs table
local registry = {
    spawnedUI = nil,
    refs = {}
}

---@param spawner spawner
function registry.init(spawner)
    registry.spawnedUI = spawner.baseUI.spawnedUI
end

function registry.update()
    registry.refs = {}

    for _, node in pairs(registry.spawnedUI.paths) do
        if utils.isA(node.ref, "spawnableElement") and node.ref.spawnable.nodeRef ~= "" then
            local root = node.ref:getRootParent()

            if not registry.refs[root.name] then
                registry.refs[root.name] = {}
            end
            if registry.refs[root.name][node.ref.spawnable.nodeRef] then
                registry.refs[root.name][node.ref.spawnable.nodeRef].duplicate = true
            else
                registry.refs[root.name][node.ref.spawnable.nodeRef] = { ref = node.ref.spawnable.nodeRef, path = node.path, duplicate = false }
            end
        end
    end
end

function registry.generate(object)
    local generated = "$/"
    if #settings.nodeRefPrefix > 0 then
        generated = generated .. settings.nodeRefPrefix .. "/"
    end
    local rootName = object:getRootParent().name
    local parent = utils.createFileName(string.lower(object.parent.name))
    local root = utils.createFileName(string.lower(rootName))
    local name = utils.createFileName(string.lower(object.name))

    generated = generated .. parent .. "/#" .. root .. "_" .. name

    while registry.refs[rootName] and registry.refs[rootName][generated] do
        generated = utils.generateCopyName(generated)
    end

    return generated
end

function registry.drawNodeRefSelector(width, ref, object, record)
    local finished = false

    ImGui.SetNextItemWidth(width * style.viewSize)
    if (ImGui.BeginCombo("##nodeRefSelector", ref)) then
        local interiorWidth = width - (2 * ImGui.GetStyle().FramePadding.x) - 30
        ref, _, textFieldFinished = style.trackedTextField(object, "##noderef", ref, "$/#foobar", interiorWidth)
        local x, _ = ImGui.GetItemRectSize()

        ImGui.SameLine()
        style.pushButtonNoBG(true)
        if ImGui.Button(IconGlyphs.Close) then
            if record then
                history.addAction(history.getElementChange(object))
            end
            ref = ""
            finished = true
        end
        style.pushButtonNoBG(false)

        local entryHovered = false
        local xButton, _ = ImGui.GetItemRectSize()
        if ImGui.BeginChild("##list", x + xButton + ImGui.GetStyle().ItemSpacing.x, 100 * style.viewSize) then
            for _, node in pairs(registry.refs[object:getRootParent().name] or {}) do
                -- Show everything when "0" is selected, treat it like a wildcard
                if (ref == "0" or node.ref:match(ref)) and node.ref ~= object.spawnable.nodeRef and ImGui.Selectable(utils.shortenPath(node.ref, ((width - 2 * ImGui.GetStyle().FramePadding.x) * style.viewSize) - (ImGui.GetScrollMaxY() > 0 and ImGui.GetStyle().ScrollbarSize or 0), false)) then
                    if record then
                        history.addAction(history.getElementChange(object))
                    end
                    ref = node.ref
                    finished = true
                    ImGui.CloseCurrentPopup()
                end
                entryHovered = entryHovered or ImGui.IsItemHovered()
            end

            ImGui.EndChild()
        end

        ImGui.EndCombo()

        -- Make sure that if text input is used as search, and entry is clicked, that we do not count the finish event from text input, but wait for the selectable to be clicked on the next frame
        if entryHovered and textFieldFinished then
            finished = false
        else
            finished = finished or textFieldFinished
        end
    end

    return ref, finished
end

return registry