local drag = {
    origin = nil,
    hovered = nil,
    dragging = false,
}

function drag.draw()
    local dragging = ImGui.IsMouseDragging(0)

    if dragging and not drag.dragging then
        drag.origin = drag.hovered
        if drag.origin then
            drag.origin.beingDragged = true
        end
    elseif not dragging and drag.dragging then
        if drag.origin and drag.hovered then
            drag.hovered.beingTargeted = false
            drag.origin:dropIn(drag.hovered)
        end
        if drag.origin then
            drag.origin.beingDragged = false
            drag.origin = nil
        end
    end

    drag.dragging = dragging
end

function drag.draggableHoveredIn(draggable)
    if drag.origin then
        if drag.origin == draggable then
            return
        end

        if draggable.targetable then
            draggable.beingTargeted = true
        else
            return
        end
    end

    drag.hovered = draggable
end

function drag.draggableHoveredOut(draggable)
    drag.hovered = nil

    if drag.origin then
        draggable.beingTargeted = false
    end
end

return drag