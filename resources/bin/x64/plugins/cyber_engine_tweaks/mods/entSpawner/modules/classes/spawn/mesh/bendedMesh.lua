local mesh = require("modules/classes/spawn/mesh/mesh")
local spawnable = require("modules/classes/spawn/spawnable")
local style = require("modules/ui/style")
local utils = require("modules/utils/core/utils")
local history = require("modules/utils/project/history")
local intersection = require("modules/utils/editor/intersection")
local visualizer = require("modules/utils/preview/visualizer")
local previewHosts = require("modules/utils/preview/previewHosts")
local bendedPool = require("modules/utils/preview/bendedPool")
local bendedCollisionPreview = require("modules/utils/preview/bendedCollisionPreview")
local field = require("modules/utils/ui/field")
local cache = require("modules/utils/game/cache")
local bendedRig = require("modules/utils/game/bendedRig")
local bendedCollision = require("modules/utils/game/bendedCollision")
local settings = require("modules/utils/core/settings")
local colliderBase = require("modules/classes/spawn/collision/colliderBase")
local colliderColors = colliderBase.getColliderGenerics().colors
local colliderPresets = colliderBase.getColliderGenerics().presets
local colliderMaterials = colliderBase.getColliderGenerics().materials

local COLLISION_CLASSES = { "ground", "raised", "wall" }
local COLLISION_CLASS_LABELS = { ground = "Ground", raised = "Raised", wall = "Wall" }
local DEFAULT_COLLISION_MATERIAL = "concrete.physmat"
local DEFAULT_COLLISION_PRESET = "World Static"
local projectedWireframe = require("modules/utils/editor/projectedWireframe")
local input = require("modules/utils/core/input")

local bendedMesh = setmetatable({}, { __index = mesh })
-- Spawned with the path running away from the camera.
bendedMesh.spawnAlongView = true

local zeroVector3 = { x = 0, y = 0, z = 0 }

local function normalizeVector4(raw, fallback)
    local source = raw or {}
    local f = fallback or Vector4.new(0, 0, 0, 0)

    return Vector4.new(
        utils.toNumber(source.x or source.X, f.x),
        utils.toNumber(source.y or source.Y, f.y),
        utils.toNumber(source.z or source.Z, f.z),
        utils.toNumber(source.w or source.W, f.w)
    )
end

local function copyDeformedBox(box)
    local fallback = {
        min = Vector4.new(-0.5, -0.5, -0.5, 1),
        max = Vector4.new(0.5, 0.5, 0.5, 1)
    }
    local source = box or {}

    local minimum = normalizeVector4(source.min or source.Min, fallback.min)
    local maximum = normalizeVector4(source.max or source.Max, fallback.max)

    return {
        min = Vector4.new(math.min(minimum.x, maximum.x), math.min(minimum.y, maximum.y), math.min(minimum.z, maximum.z), 1),
        max = Vector4.new(math.max(minimum.x, maximum.x), math.max(minimum.y, maximum.y), math.max(minimum.z, maximum.z), 1)
    }
end

local function copyPathPoint(point, fallback)
    local source = point or {}
    local base = fallback or { x = 0, y = 0, z = 0, roll = 0, anchored = false }
    local anchored = utils.toBoolean(source.anchored or source.anchor or source.isAnchored, base.anchored)

    return {
        x = utils.toNumber(source.x or source.X, base.x),
        y = utils.toNumber(source.y or source.Y, base.y),
        z = utils.toNumber(source.z or source.Z, base.z),
        roll = utils.toNumber(source.roll or source.Roll, base.roll),
        anchored = anchored == true
    }
end

local function lerpPathPoint(a, b, t)
    return {
        x = a.x + (b.x - a.x) * t,
        y = a.y + (b.y - a.y) * t,
        z = a.z + (b.z - a.z) * t,
        roll = a.roll + (b.roll - a.roll) * t
    }
end

local function catmullRomScalar(p0, p1, p2, p3, t)
    local t2 = t * t
    local t3 = t2 * t
    return 0.5 * (
        (2 * p1) +
        (-p0 + p2) * t +
        (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
        (-p0 + 3 * p1 - 3 * p2 + p3) * t3
    )
end

local function catmullRomPathPoint(p0, p1, p2, p3, t)
    return {
        x = catmullRomScalar(p0.x, p1.x, p2.x, p3.x, t),
        y = catmullRomScalar(p0.y, p1.y, p2.y, p3.y, t),
        z = catmullRomScalar(p0.z, p1.z, p2.z, p3.z, t),
        -- Keep roll interpolation linear to avoid angular overshoot.
        roll = p1.roll + (p2.roll - p1.roll) * t
    }
end

local pathUpAxisOptions = {
    "World Z (Up)",
    "World Y",
    "World X"
}

local pathInterpolationOptions = {
    "Linear (Segmented)",
    "Catmull-Rom (Smooth)",
    "Bezier (Auto Handles)"
}

-- Stored 1-based: 1 = legacy (by index, chord end tangents), 2 = along the curve.
local PATH_SOLVER_LEGACY = 1
local PATH_SOLVER_CURVE = 2
local pathSolverOptions = {
    "By Index (Legacy)",
    "Along Curve"
}
local PATH_CURVE_SAMPLES_PER_BONE = 12

-- Stored 1-based. Curve: free control points, bones resampled along it. Bones: one point per bone.
local PATH_MODE_CURVE = 1
local PATH_MODE_BONES = 2
local pathModeOptions = {
    "Curve Mode",
    "Bone Mode (advanced)"
}
local pathModeTooltips = {
    "Place a few control points, the bones follow the curve.",
    "Edit every bone of the rig, anchoring the ones to keep."
}
local miscLabels = { "Remove From Rain Map", "Navigation Impact", "Cast Local Shadows", "Cast Shadows" }
local LENGTH_MODE_FIT = 1
local LENGTH_MODE_KEEP = 2
local lengthModeOptions = {
    "Fit to Curve",
    "Keep Rest Length"
}
local CURVE_SAMPLES_PER_SEGMENT = 48
-- In-world line of a Curve mode path: one segment per this many meters, at least this many per curve segment.
local CURVE_DRAW_STEP = 1
local CURVE_DRAW_MIN_PER_SEGMENT = 12
local CURVE_DRAW_MAX_SEGMENTS = 160

local PATH_PREVIEW_FOCUS_POINT = 1
local PATH_PREVIEW_LINE_THICKNESS = 0.04
local PATH_PREVIEW_POINT_SCALE = 0.01
local PATH_PREVIEW_FRAME_LENGTH = 0.22
-- A single entity crashes the game past roughly this many components, so the path preview
-- is spread over host entities holding this many each rather than piled onto the mesh.
local PATH_PREVIEW_COMPONENTS_PER_HOST = 256
local PATH_PREVIEW_MAX_SEGMENTS = 320
local PATH_PREVIEW_MAX_FRAMES = 80
local PATH_POINT_ANCHOR_COLOR = 0xFFE6D8AD
local BEZIER_AUTO_HANDLE_FACTOR = 1 / 3
local BEZIER_NEIGHBOR_HANDLE_FACTOR = 0.5

local deformationClipboardKey = "bendedMeshDeformationData"

local function toTypedVector4(vector)
    return {
        ["$type"] = "Vector4",
        X = vector.x,
        Y = vector.y,
        Z = vector.z,
        W = vector.w
    }
end

local function toTypedMatrix(matrix)
    return {
        ["$type"] = "Matrix",
        X = toTypedVector4(matrix.X),
        Y = toTypedVector4(matrix.Y),
        Z = toTypedVector4(matrix.Z),
        W = toTypedVector4(matrix.W)
    }
end

local function transformPointWithFrame(frame, point)
    local right = frame.right or { x = 1, y = 0, z = 0 }
    local forward = frame.forward or { x = 0, y = 1, z = 0 }
    local up = frame.up or { x = 0, y = 0, z = 1 }
    local position = frame.position or { x = 0, y = 0, z = 0 }

    return Vector4.new(
        right.x * point.x + forward.x * point.y + up.x * point.z + position.x,
        right.y * point.x + forward.y * point.y + up.y * point.z + position.y,
        right.z * point.x + forward.z * point.y + up.z * point.z + position.z,
        1
    )
end

local function getDefaultNavmeshImpactIndex(enumValues)
    local index = utils.indexValue(enumValues, "Road")
    if index == -1 then
        return 0
    end

    return math.max(index - 1, 0)
end

local function normalizeDirection(vec)
    local length = math.sqrt(vec.x * vec.x + vec.y * vec.y + vec.z * vec.z)
    if length <= 0.000001 then
        return { x = 0, y = 0, z = 0 }
    end

    return {
        x = vec.x / length,
        y = vec.y / length,
        z = vec.z / length
    }
end

local function dot(a, b)
    return a.x * b.x + a.y * b.y + a.z * b.z
end

local function cross(a, b)
    return {
        x = a.y * b.z - a.z * b.y,
        y = a.z * b.x - a.x * b.z,
        z = a.x * b.y - a.y * b.x
    }
end

local function isDirectionZero(vec)
    return math.abs(vec.x) < 0.000001 and math.abs(vec.y) < 0.000001 and math.abs(vec.z) < 0.000001
end

---@param point table?
---@return table curvePoint `{ x, y, z, roll, dir?, lenIn?, lenOut? }`; `dir` set means a manual tangent.
local function copyCurvePoint(point)
    local source = point or {}
    local copy = {
        x = utils.toNumber(source.x, 0),
        y = utils.toNumber(source.y, 0),
        z = utils.toNumber(source.z, 0),
        roll = utils.toNumber(source.roll, 0)
    }

    if type(source.dir) == "table" then
        local dir = normalizeDirection({ x = utils.toNumber(source.dir.x, 0), y = utils.toNumber(source.dir.y, 0), z = utils.toNumber(source.dir.z, 0) })
        if not isDirectionZero(dir) then
            copy.dir = dir
            copy.lenIn = tonumber(source.lenIn)
            copy.lenOut = tonumber(source.lenOut)
        end
    end

    return copy
end

local function length3(vec)
    return math.sqrt(vec.x * vec.x + vec.y * vec.y + vec.z * vec.z)
end

local function cubicBezierScalar(p0, p1, p2, p3, t)
    local oneMinusT = 1 - t
    local oneMinusT2 = oneMinusT * oneMinusT
    local t2 = t * t

    return oneMinusT2 * oneMinusT * p0
        + 3 * oneMinusT2 * t * p1
        + 3 * oneMinusT * t2 * p2
        + t2 * t * p3
end

local function bezierAutoPathPoint(previousPoint, startPoint, endPoint, nextPoint, t)
    local segment = {
        x = endPoint.x - startPoint.x,
        y = endPoint.y - startPoint.y,
        z = endPoint.z - startPoint.z
    }
    local segmentLength = length3(segment)

    if segmentLength <= 0.000001 then
        return {
            x = startPoint.x,
            y = startPoint.y,
            z = startPoint.z,
            roll = startPoint.roll + (endPoint.roll - startPoint.roll) * t
        }
    end

    local segmentDirection = normalizeDirection(segment)
    local startDirection = normalizeDirection({
        x = endPoint.x - previousPoint.x,
        y = endPoint.y - previousPoint.y,
        z = endPoint.z - previousPoint.z
    })
    local endDirection = normalizeDirection({
        x = nextPoint.x - startPoint.x,
        y = nextPoint.y - startPoint.y,
        z = nextPoint.z - startPoint.z
    })

    if isDirectionZero(startDirection) or dot(startDirection, segmentDirection) < 0 then
        startDirection = segmentDirection
    end
    if isDirectionZero(endDirection) or dot(endDirection, segmentDirection) < 0 then
        endDirection = segmentDirection
    end

    local startNeighborLength = length3({
        x = startPoint.x - previousPoint.x,
        y = startPoint.y - previousPoint.y,
        z = startPoint.z - previousPoint.z
    })
    local endNeighborLength = length3({
        x = nextPoint.x - endPoint.x,
        y = nextPoint.y - endPoint.y,
        z = nextPoint.z - endPoint.z
    })

    local startHandleLength = segmentLength * BEZIER_AUTO_HANDLE_FACTOR
    local endHandleLength = segmentLength * BEZIER_AUTO_HANDLE_FACTOR

    if startNeighborLength > 0.000001 then
        startHandleLength = math.min(startHandleLength, startNeighborLength * BEZIER_NEIGHBOR_HANDLE_FACTOR)
    end
    if endNeighborLength > 0.000001 then
        endHandleLength = math.min(endHandleLength, endNeighborLength * BEZIER_NEIGHBOR_HANDLE_FACTOR)
    end

    local startControl = {
        x = startPoint.x + startDirection.x * startHandleLength,
        y = startPoint.y + startDirection.y * startHandleLength,
        z = startPoint.z + startDirection.z * startHandleLength
    }
    local endControl = {
        x = endPoint.x - endDirection.x * endHandleLength,
        y = endPoint.y - endDirection.y * endHandleLength,
        z = endPoint.z - endDirection.z * endHandleLength
    }

    return {
        x = cubicBezierScalar(startPoint.x, startControl.x, endControl.x, endPoint.x, t),
        y = cubicBezierScalar(startPoint.y, startControl.y, endControl.y, endPoint.y, t),
        z = cubicBezierScalar(startPoint.z, startControl.z, endControl.z, endPoint.z, t),
        -- Keep roll interpolation linear to avoid angular overshoot.
        roll = startPoint.roll + (endPoint.roll - startPoint.roll) * t
    }
end

local function getPathUpAxis(index)
    if index == 1 then
        return { x = 0, y = 1, z = 0 }
    end

    if index == 2 then
        return { x = 1, y = 0, z = 0 }
    end

    return { x = 0, y = 0, z = 1 }
end

local function buildBasisFromForward(forward, upHint)
    local f = normalizeDirection(forward)
    if isDirectionZero(f) then
        f = { x = 0, y = 1, z = 0 }
    end

    local right = normalizeDirection(cross(f, upHint or { x = 0, y = 0, z = 1 }))
    if isDirectionZero(right) then
        right = normalizeDirection(cross(f, { x = 0, y = 1, z = 0 }))
    end
    if isDirectionZero(right) then
        right = normalizeDirection(cross(f, { x = 1, y = 0, z = 0 }))
    end
    if isDirectionZero(right) then
        right = { x = 1, y = 0, z = 0 }
    end

    local up = normalizeDirection(cross(right, f))
    if isDirectionZero(up) then
        up = { x = 0, y = 0, z = 1 }
    end

    right = normalizeDirection(cross(f, up))
    return right, f, up
end

local function rotateAroundAxis(vector, axis, angleRadians)
    local axisNormalized = normalizeDirection(axis)
    if isDirectionZero(axisNormalized) then
        return vector
    end

    local cosTheta = math.cos(angleRadians)
    local sinTheta = math.sin(angleRadians)
    local crossAxisVector = cross(axisNormalized, vector)
    local axisDotVector = dot(axisNormalized, vector)

    return {
        x = vector.x * cosTheta + crossAxisVector.x * sinTheta + axisNormalized.x * axisDotVector * (1 - cosTheta),
        y = vector.y * cosTheta + crossAxisVector.y * sinTheta + axisNormalized.y * axisDotVector * (1 - cosTheta),
        z = vector.z * cosTheta + crossAxisVector.z * sinTheta + axisNormalized.z * axisDotVector * (1 - cosTheta)
    }
end

function bendedMesh:new()
    local o = mesh.new(self)

    o.dataType = "Bended Mesh"
    o.modulePath = "mesh/bendedMesh"
    o.spawnDataPath = "data/spawnables/mesh/bended/"
    o.node = "worldBendedMeshNode"
    o.description = "Places a world bended mesh node with path-based deformation editing and deformed bounding box."
    o.previewNote = "Deformation is previewed through a placeholder world node; without Codeware the mesh is shown undeformed."
    o.icon = IconGlyphs.SineWave

    o.isBendedRoad = true
    o.removeFromRainMap = false
    o.navmeshImpactEnum = utils.enumTable("NavGenNavmeshImpact")
    if #o.navmeshImpactEnum == 0 then
        o.navmeshImpactEnum = { "Road" }
    end
    o.navigationImpact = getDefaultNavmeshImpactIndex(o.navmeshImpactEnum)
    o.castLocalShadows = 1
    o.castShadows = 1
    o.deformedBox = copyDeformedBox(nil)
    o.pathPoints = { { x = 0, y = 0, z = 0, roll = 0, anchored = true } }
    o.pathLooped = false
    o.pathUseAlgorithm = true
    o.pathInterpolation = 1
    o.pathUpAxis = 0
    o.pathSolver = PATH_SOLVER_CURVE
    o.pathMode = PATH_MODE_CURVE
    o.pathLengthMode = LENGTH_MODE_FIT
    o.curvePoints = {}
    o.continuationRepeatShape = false
    o.importedDeformation = nil
    o.pathPreviewEnabled = false
    o.deformedPreviewEnabled = true
    o.liveCollisionEnabled = true
    o.collisionShapeVisible = false
    -- Hierarchy visualization helper: In-World Path Viz and Show Collision together.
    o.previewed = false
    o.exportCollision = true
    o.collisionMaterials = { ground = "", raised = "", wall = "" }
    o.collisionPresets = { ground = DEFAULT_COLLISION_PRESET, raised = DEFAULT_COLLISION_PRESET, wall = DEFAULT_COLLISION_PRESET }
    o.collisionMaterialSearch = {}
    o.collisionPresetSearch = {}
    o.viewportHandlesEnabled = true
    o.magneticEnds = true
    o.linkJoinedEnds = true
    o.deformedPreviewSignature = nil
    o.deformedPreviewIssue = nil
    o.pathPreviewSegmentCount = 0
    o.pathPreviewControlCount = 0
    o.pathPreviewFrameCount = 0
    o.pathPreviewSubdivisionCount = 0
    o.version = 0
    o.pendingAutoFit = false
    o.maxPropertyWidth = nil

    o.hideGenerate = true
    o.convertTarget = 0

    setmetatable(o, { __index = self })
    o:setDefaultStreamingPreset("District")
    return o
end

function bendedMesh:loadSpawnData(data, position, rotation)
    mesh.loadSpawnData(self, data, position, rotation)

    self.isBendedRoad = utils.toBoolean(data.isBendedRoad, true)
    self.removeFromRainMap = utils.toBoolean(data.removeFromRainMap, false)
    self.version = data.version or self.version

    local navigationImpact = data.navigationImpact
    if navigationImpact == nil and data.navigationSetting then
        navigationImpact = data.navigationSetting.navmeshImpact
    end

    if type(navigationImpact) == "string" then
        local index = utils.indexValue(self.navmeshImpactEnum, navigationImpact)
        self.navigationImpact = math.max(index - 1, 0)
    elseif type(navigationImpact) == "number" then
        self.navigationImpact = math.max(0, math.min(math.floor(navigationImpact), math.max(0, #self.navmeshImpactEnum - 1)))
    end

    self.deformedBox = copyDeformedBox(data.deformedBox)

    self.pathLooped = utils.toBoolean(data.pathLooped, self.pathLooped)
    self.pathUseAlgorithm = utils.toBoolean(data.pathUseAlgorithm, self.pathUseAlgorithm)
    self.pathInterpolation = math.max(0, math.min(math.floor(utils.toNumber(data.pathInterpolation, self.pathInterpolation)), #pathInterpolationOptions - 1))
    self.pathUpAxis = math.max(0, math.min(math.floor(utils.toNumber(data.pathUpAxis, self.pathUpAxis)), #pathUpAxisOptions - 1))

    -- Paths saved before the solver existed keep the legacy placement they were authored with.
    local defaultSolver = (type(data.pathPoints) == "table" and #data.pathPoints > 0) and PATH_SOLVER_LEGACY or PATH_SOLVER_CURVE
    self.pathSolver = math.max(1, math.min(math.floor(utils.toNumber(data.pathSolver, defaultSolver)), #pathSolverOptions))
    self.continuationRepeatShape = utils.toBoolean(data.continuationRepeatShape, self.continuationRepeatShape)

    -- Paths saved before the curve editor existed open in the per-bone editor.
    local defaultMode = (type(data.pathPoints) == "table" and #data.pathPoints > 0 and type(data.curvePoints) ~= "table") and PATH_MODE_BONES or PATH_MODE_CURVE
    self.pathMode = math.max(1, math.min(math.floor(utils.toNumber(data.pathMode, defaultMode)), #pathModeOptions))
    self.pathLengthMode = math.max(1, math.min(math.floor(utils.toNumber(data.pathLengthMode, self.pathLengthMode)), #lengthModeOptions))
    self.curvePoints = {}
    for _, point in ipairs(type(data.curvePoints) == "table" and data.curvePoints or {}) do
        table.insert(self.curvePoints, copyCurvePoint(point))
    end
    self._curveKey = nil
    self.importedDeformation = type(data.importedDeformation) == "table" and data.importedDeformation or nil

    self.pathPreviewEnabled = utils.toBoolean(data.pathPreviewEnabled, self.pathPreviewEnabled)
    self.deformedPreviewEnabled = utils.toBoolean(data.deformedPreviewEnabled, self.deformedPreviewEnabled)
    self.liveCollisionEnabled = utils.toBoolean(data.liveCollisionEnabled, self.liveCollisionEnabled)
    self.collisionShapeVisible = utils.toBoolean(data.collisionShapeVisible, self.collisionShapeVisible)
    self:syncPreviewed()
    self.exportCollision = utils.toBoolean(data.exportCollision, self.exportCollision)
    -- Fresh tables: the payload may be shared with the project cache or the clipboard.
    local materials, presets = {}, {}
    for _, class in ipairs(COLLISION_CLASSES) do
        local material = type(data.collisionMaterials) == "table" and data.collisionMaterials[class] or nil
        local preset = type(data.collisionPresets) == "table" and data.collisionPresets[class] or nil
        materials[class] = type(material) == "string" and material or ""
        presets[class] = type(preset) == "string" and preset ~= "" and preset or DEFAULT_COLLISION_PRESET
    end
    self.collisionMaterials = materials
    self.collisionPresets = presets
    self.viewportHandlesEnabled = utils.toBoolean(data.viewportHandlesEnabled, self.viewportHandlesEnabled)
    self.magneticEnds = utils.toBoolean(data.magneticEnds, self.magneticEnds)
    self.linkJoinedEnds = utils.toBoolean(data.linkJoinedEnds, self.linkJoinedEnds)

    self.pathPoints = {}
    for _, point in ipairs(data.pathPoints or {}) do
        table.insert(self.pathPoints, copyPathPoint(point))
    end

    self:ensurePathPoints()
    self:requestRig()

    self.pendingAutoFit = true
    self:updatePathVisualization()
end

function bendedMesh:onAssemble(entity)
    mesh.onAssemble(self, entity)
    self:updatePathVisualization()
end

---Hierarchy visualization helper state: on while the path or the collision is shown.
function bendedMesh:syncPreviewed()
    self.previewed = self.pathPreviewEnabled or self.collisionShapeVisible
end

---Hierarchy visualization helper: turns In-World Path Viz and Show Collision on or off together.
---@param state boolean
function bendedMesh:setPreview(state)
    self.pathPreviewEnabled = state
    self.collisionShapeVisible = state
    self.previewed = state
    self:refreshCollisionPreview()
    self:refreshArrowScale()
end

function bendedMesh:updateScale()
    mesh.updateScale(self)
    self:updatePathVisualization()
    self:applyEntityMeshVisibility()
end

---@protected
---@param changed boolean
function bendedMesh:updateShadowSettings(changed)
    mesh.updateShadowSettings(self, changed)
    if not changed then return end

    self:applyEntityMeshVisibility()
    self:refreshDeformedPreview()
end

---@param direction integer?
---@return boolean changed
function bendedMesh:cycleAppearance(direction)
    local changed = mesh.cycleAppearance(self, direction)
    if changed then
        self:refreshDeformedPreview()
    end

    return changed
end

function bendedMesh:save()
    self:ensurePathPoints()
    self:applyPathAlgorithmToNonAnchored()

    if self.bBoxLoaded then
        self:autoFitDeformedBox()
    end

    local data = mesh.save(self)
    local normalizedBox = self:getNormalizedDeformedBox()

    data.isBendedRoad = self.isBendedRoad
    data.removeFromRainMap = self.removeFromRainMap
    data.navigationImpact = self.navigationImpact
    data.version = self.version
    data.pathLooped = self.pathLooped
    data.pathUseAlgorithm = self.pathUseAlgorithm
    data.pathInterpolation = self.pathInterpolation
    data.pathUpAxis = self.pathUpAxis
    data.pathSolver = self.pathSolver
    data.pathMode = self.pathMode
    data.pathLengthMode = self.pathLengthMode
    data.curvePoints = {}
    for _, point in ipairs(self.curvePoints or {}) do
        table.insert(data.curvePoints, copyCurvePoint(point))
    end
    data.continuationRepeatShape = self.continuationRepeatShape
    data.importedDeformation = self.importedDeformation
    data.pathPreviewEnabled = self.pathPreviewEnabled
    data.deformedPreviewEnabled = self.deformedPreviewEnabled
    data.liveCollisionEnabled = self.liveCollisionEnabled
    data.collisionShapeVisible = self.collisionShapeVisible
    data.exportCollision = self.exportCollision
    data.collisionMaterials = utils.deepcopy(self.collisionMaterials)
    data.collisionPresets = utils.deepcopy(self.collisionPresets)
    data.viewportHandlesEnabled = self.viewportHandlesEnabled
    data.magneticEnds = self.magneticEnds
    data.linkJoinedEnds = self.linkJoinedEnds
    data.pathPoints = {}
    data.deformedBox = {
        min = { x = normalizedBox.min.x, y = normalizedBox.min.y, z = normalizedBox.min.z, w = 1 },
        max = { x = normalizedBox.max.x, y = normalizedBox.max.y, z = normalizedBox.max.z, w = 1 }
    }

    for _, point in ipairs(self.pathPoints) do
        table.insert(data.pathPoints, copyPathPoint(point))
    end

    return data
end

function bendedMesh:isDeformationClipboardPayloadValid(payload)
    if type(payload) ~= "table" then
        return false
    end

    local hasPath = type(payload.pathPoints) == "table" and #payload.pathPoints > 0
    return hasPath
end

function bendedMesh:getDeformationClipboardPayload()
    self:ensurePathPoints()
    self:applyPathAlgorithmToNonAnchored()

    local payload = {
        version = 4,
        pathLooped = self.pathLooped,
        pathUseAlgorithm = self.pathUseAlgorithm,
        pathInterpolation = self.pathInterpolation,
        pathUpAxis = self.pathUpAxis,
        pathSolver = self.pathSolver,
        pathMode = self.pathMode,
        pathLengthMode = self.pathLengthMode,
        pathPoints = {},
        curvePoints = {}
    }

    for _, point in ipairs(self.pathPoints or {}) do
        table.insert(payload.pathPoints, copyPathPoint(point))
    end
    for _, point in ipairs(self.curvePoints or {}) do
        table.insert(payload.curvePoints, copyCurvePoint(point))
    end

    return payload
end

function bendedMesh:applyDeformationClipboardPayload(payload)
    if not self:isDeformationClipboardPayloadValid(payload) then
        return false
    end

    local hasPath = type(payload.pathPoints) == "table" and #payload.pathPoints > 0

    if payload.pathLooped ~= nil then
        self.pathLooped = utils.toBoolean(payload.pathLooped, self.pathLooped)
    end
    if payload.pathUseAlgorithm ~= nil then
        self.pathUseAlgorithm = utils.toBoolean(payload.pathUseAlgorithm, self.pathUseAlgorithm)
    end
    if payload.pathInterpolation ~= nil then
        self.pathInterpolation = math.max(0, math.min(math.floor(utils.toNumber(payload.pathInterpolation, self.pathInterpolation)), #pathInterpolationOptions - 1))
    end
    if payload.pathUpAxis ~= nil then
        self.pathUpAxis = math.max(0, math.min(math.floor(utils.toNumber(payload.pathUpAxis, self.pathUpAxis)), #pathUpAxisOptions - 1))
    end
    if payload.pathSolver ~= nil then
        self.pathSolver = math.max(1, math.min(math.floor(utils.toNumber(payload.pathSolver, self.pathSolver)), #pathSolverOptions))
    end

    if payload.pathLengthMode ~= nil then
        self.pathLengthMode = math.max(1, math.min(math.floor(utils.toNumber(payload.pathLengthMode, self.pathLengthMode)), #lengthModeOptions))
    end

    -- A curve fits any rig, so it is pasted as a curve even across meshes with other bone counts.
    local hasCurve = payload.pathMode == PATH_MODE_CURVE and type(payload.curvePoints) == "table" and #payload.curvePoints >= 2
    self.pathPoints = {}
    if hasPath then
        for _, point in ipairs(payload.pathPoints) do
            table.insert(self.pathPoints, copyPathPoint(point))
        end
    end
    if hasCurve then
        self.pathMode = PATH_MODE_CURVE
        self.curvePoints = {}
        for _, point in ipairs(payload.curvePoints) do
            table.insert(self.curvePoints, copyCurvePoint(point))
        end
        self._curveKey = nil
    elseif hasPath then
        self.pathMode = PATH_MODE_BONES
    end
    self:ensurePathPoints()

    self:autoFitDeformedBox()

    self:refreshArrowScale()
    return true
end

function bendedMesh:getMeshBoundLengthAlongDirection(direction)
    local axis = normalizeDirection(direction or { x = 0, y = 1, z = 0 })
    if isDirectionZero(axis) then
        axis = { x = 0, y = 1, z = 0 }
    end

    local extentX = math.abs((self.bBox.max and self.bBox.max.x or 0.5) - (self.bBox.min and self.bBox.min.x or -0.5))
    local extentY = math.abs((self.bBox.max and self.bBox.max.y or 0.5) - (self.bBox.min and self.bBox.min.y or -0.5))
    local extentZ = math.abs((self.bBox.max and self.bBox.max.z or 0.5) - (self.bBox.min and self.bBox.min.z or -0.5))

    local projected = math.abs(axis.x) * extentX + math.abs(axis.y) * extentY + math.abs(axis.z) * extentZ
    if projected < 0.001 then
        projected = math.max(extentX, extentY, extentZ, 1)
    end

    return projected
end

---World pose of a path frame: position through T * R * S, axes through R * S, re-orthonormalized.
---@param frame table Path frame in local space.
---@return table frame `{ position, right, forward, up }` in world space.
function bendedMesh:pathFrameToWorld(frame)
    local quat = self.rotation:ToQuat()
    local scale = self.scale or { x = 1, y = 1, z = 1 }

    local function direction(v)
        local rotated = quat:Transform(Vector4.new(v.x * scale.x, v.y * scale.y, v.z * scale.z, 0))
        return { x = rotated.x, y = rotated.y, z = rotated.z }
    end

    local position = self:getWorldPointFromLocal(frame.position)
    local forward = normalizeDirection(direction(frame.forward))
    if isDirectionZero(forward) then
        forward = { x = 0, y = 1, z = 0 }
    end

    local right = normalizeDirection(cross(forward, direction(frame.up)))
    if isDirectionZero(right) then
        right = normalizeDirection(direction(frame.right))
    end
    if isDirectionZero(right) then
        right = { x = 1, y = 0, z = 0 }
    end

    return {
        position = { x = position.x, y = position.y, z = position.z },
        right = right,
        forward = forward,
        up = normalizeDirection(cross(right, forward))
    }
end

---Rotates a vector around world Z.
---@param v table
---@param degrees number
---@return table
local function rotateYaw(v, degrees)
    local angle = math.rad(degrees)
    local c, s = math.cos(angle), math.sin(angle)
    return { x = v.x * c - v.y * s, y = v.x * s + v.y * c, z = v.z }
end

---@param flat table
---@return table frame
local function frameFromFlat(flat)
    return {
        right = { x = flat[1], y = flat[2], z = flat[3] },
        forward = { x = flat[5], y = flat[6], z = flat[7] },
        up = { x = flat[9], y = flat[10], z = flat[11] },
        position = { x = flat[13], y = flat[14], z = flat[15] }
    }
end

---Creates a bended mesh of the same asset joined to one end of this one.
---The new mesh only takes a yaw, so its `World Z` up axis stays the world's; slope and bank are
---carried by its path instead.
---@param fromStart boolean? Join to the start of this mesh instead of its end.
---@return boolean
function bendedMesh:createContinuationMesh(fromStart)
    if not self.object or not self.object.parent or self.object:isLocked() then
        return false
    end

    local frames = self:getSampledPathFrames()
    local count = #frames
    if count == 0 then
        return false
    end

    local data = self.object:serialize()
    if not data or not data.spawnable then
        return false
    end

    local repeatShape = self.continuationRepeatShape and count >= 2
    local distances = nil
    if not repeatShape then
        distances = self:getRestDistances()
        local pointCount = self:getMeshBonesQuantity() or count
        if not distances or #distances ~= pointCount then
            distances = {}
            local step = self:getMeshBoundLengthAlongDirection({ x = 0, y = 1, z = 0 }) / math.max(1, pointCount - 1)
            for index = 1, pointCount do
                distances[index] = (index - 1) * step
            end
        end
    end

    ---Frames of the new mesh, in the space `sourceFrames` are given in.
    local function buildDesired(sourceFrames, spacing)
        local target = fromStart and sourceFrames[1] or sourceFrames[count]
        local desired = {}
        local motion = nil

        if repeatShape then
            -- Same curve again: the rigid motion taking the far end of this mesh onto the joined end.
            local far = fromStart and sourceFrames[count] or sourceFrames[1]
            motion = bendedRig.mul(bendedRig.inverse(bendedRig.fromFrame(far)), bendedRig.fromFrame(target))
            for index, frame in ipairs(sourceFrames) do
                desired[index] = frameFromFlat(bendedRig.mul(bendedRig.fromFrame(frame), motion))
            end
        else
            -- Straight, at the rest spacing of the rig.
            local offset = fromStart and distances[#distances] or 0
            for index, distance in ipairs(distances) do
                local along = (distance - offset) * spacing
                desired[index] = {
                    right = target.right,
                    forward = target.forward,
                    up = target.up,
                    position = {
                        x = target.position.x + target.forward.x * along,
                        y = target.position.y + target.forward.y * along,
                        z = target.position.z + target.forward.z * along
                    }
                }
            end
        end

        return desired, target, motion
    end

    local localFrames = {}
    local objectPosition, objectYaw, upAxis
    local continuationCurvePoints = nil

    local function addLocalFrame(right, forward, up, position)
        table.insert(localFrames, {
            X = { x = right.x, y = right.y, z = right.z },
            Y = { x = forward.x, y = forward.y, z = forward.z },
            Z = { x = up.x, y = up.y, z = up.z },
            W = { x = position.x, y = position.y, z = position.z }
        })
    end

    if math.abs(self.rotation.pitch or 0) < 0.0001 and math.abs(self.rotation.roll or 0) < 0.0001 then
        -- A yaw-only mesh keeps its rotation and scale, so the new path is built in this mesh's
        -- own space and joins exactly even under a non-uniform scale.
        local desired, target, motion = buildDesired(frames, 1)
        local center = target.position
        local world = self:getWorldPointFromLocal(center)

        if motion and self:isCurveMode() then
            -- The control points move with the same motion; rolls are read back from the moved frames.
            local moved = {}
            for index, frame in ipairs(self:getCurveFrames()) do
                local m = bendedRig.mul(bendedRig.fromFrame(frame), motion)
                moved[index] = {
                    X = { x = m[1], y = m[2], z = m[3] },
                    Y = { x = m[5], y = m[6], z = m[7] },
                    Z = { x = m[9], y = m[10], z = m[11] },
                    W = { x = m[13] - center.x, y = m[14] - center.y, z = m[15] - center.z }
                }
            end

            continuationCurvePoints = {}
            for index, point in ipairs(bendedMesh.pathPointsFromMatrices(moved, self.pathUpAxis)) do
                local source = self.curvePoints[index]
                local curvePoint = { x = point.x, y = point.y, z = point.z, roll = point.roll }
                if source.dir then
                    curvePoint.dir = { x = moved[index].Y.x, y = moved[index].Y.y, z = moved[index].Y.z }
                    curvePoint.lenIn, curvePoint.lenOut = source.lenIn, source.lenOut
                end
                continuationCurvePoints[index] = curvePoint
            end

            local joined = fromStart and #continuationCurvePoints or 1
            if not continuationCurvePoints[joined].dir then
                local axis = moved[joined].Y
                continuationCurvePoints[joined].dir = { x = axis.x, y = axis.y, z = axis.z }
            end
        end

        objectPosition = { x = world.x, y = world.y, z = world.z }
        objectYaw = self.rotation.yaw or 0
        upAxis = self.pathUpAxis

        for _, frame in ipairs(desired) do
            addLocalFrame(frame.right, frame.forward, frame.up, {
                x = frame.position.x - center.x,
                y = frame.position.y - center.y,
                z = frame.position.z - center.z
            })
        end
    else
        -- A pitched or rolled mesh hands over to a yaw-only one, so `World Z` is the world's up
        -- again; slope and bank move into the path. Exact for a uniform scale.
        local worldFrames = {}
        for index, frame in ipairs(frames) do
            worldFrames[index] = self:pathFrameToWorld(frame)
        end
        local target = fromStart and worldFrames[1] or worldFrames[count]

        local restPoints = self:getRestPoints()
        local restDirection = { x = 0, y = 1, z = 0 }
        if restPoints and #restPoints > 1 then
            restDirection = { x = restPoints[#restPoints].x - restPoints[1].x, y = restPoints[#restPoints].y - restPoints[1].y, z = 0 }
        end

        objectYaw = self.rotation.yaw or 0
        if length3(restDirection) > 0.000001 and length3({ x = target.forward.x, y = target.forward.y, z = 0 }) > 0.000001 then
            objectYaw = math.deg(math.atan2(target.forward.y, target.forward.x) - math.atan2(restDirection.y, restDirection.x))
        end

        local scale = self.scale or { x = 1, y = 1, z = 1 }
        local sx, sy, sz = utils.toNumber(scale.x, 1), utils.toNumber(scale.y, 1), utils.toNumber(scale.z, 1)
        if math.abs(sx) < 0.000001 then sx = 1 end
        if math.abs(sy) < 0.000001 then sy = 1 end
        if math.abs(sz) < 0.000001 then sz = 1 end

        local localForward = rotateYaw(target.forward, -objectYaw)
        local spacing = 1 / math.max(0.000001, length3({ x = localForward.x / sx, y = localForward.y / sy, z = localForward.z / sz }))
        local desired = buildDesired(worldFrames, spacing)

        objectPosition = target.position
        upAxis = 0

        for _, frame in ipairs(desired) do
            local v = rotateYaw({
                x = frame.position.x - objectPosition.x,
                y = frame.position.y - objectPosition.y,
                z = frame.position.z - objectPosition.z
            }, -objectYaw)
            addLocalFrame(rotateYaw(frame.right, -objectYaw), rotateYaw(frame.forward, -objectYaw), rotateYaw(frame.up, -objectYaw),
                { x = v.x / sx, y = v.y / sy, z = v.z / sz })
        end
    end

    local continuationPathPoints = bendedMesh.pathPointsFromMatrices(localFrames, upAxis)
    for index, point in ipairs(continuationPathPoints) do
        if repeatShape then
            point.anchored = self:isPathPointAnchored(index)
        else
            point.anchored = index == 1 or index == #continuationPathPoints
        end
    end

    data.name = utils.generateCopyName(self.object.name)
    data.spawnable.position = { x = objectPosition.x, y = objectPosition.y, z = objectPosition.z, w = 0 }
    data.spawnable.rotation = { roll = 0, pitch = 0, yaw = objectYaw }
    data.spawnable.nodeRef = ""
    data.spawnable.pathLooped = false
    data.spawnable.pathUpAxis = upAxis
    data.spawnable.pathSolver = self.pathSolver
    data.spawnable.importedDeformation = nil
    data.spawnable.deformedBox = nil
    data.spawnable.pathPoints = continuationPathPoints
    data.spawnable.pathMode = PATH_MODE_BONES
    data.spawnable.curvePoints = nil

    if self:isCurveMode() then
        local curvePoints = continuationCurvePoints
        if not curvePoints and not repeatShape then
            -- Two points; the joined one keeps the tangent, so bending the new mesh stays smooth.
            local first, last = localFrames[1], localFrames[#localFrames]
            local joined = fromStart and last or first
            curvePoints = {
                { x = first.W.x, y = first.W.y, z = first.W.z, roll = continuationPathPoints[1].roll },
                { x = last.W.x, y = last.W.y, z = last.W.z, roll = continuationPathPoints[#continuationPathPoints].roll }
            }
            curvePoints[fromStart and 2 or 1].dir = { x = joined.Y.x, y = joined.Y.y, z = joined.Y.z }
        end

        if curvePoints then
            data.spawnable.pathMode = PATH_MODE_CURVE
            data.spawnable.curvePoints = curvePoints
        end
    end

    local newElement = require("modules/classes/editor/spawnableElement"):new(self.object.sUI)
    newElement:load(data)

    local parent = self.object.parent
    local index = utils.indexValue(parent.childs, self.object)
    if index < 1 then
        index = #parent.childs + 1
    elseif not fromStart then
        index = index + 1
    end
    newElement:setParent(parent, index)

    if self.object.sUI and self.object.sUI.unselectAll then
        self.object.sUI.unselectAll()
    end
    newElement:setSelected(true)
    if self.object.sUI then
        if self.object.sUI.requestScrollToElement then
            self.object.sUI.requestScrollToElement(newElement)
        else
            self.object.sUI.scrollToSelected = true
            self.object.sUI.scrollTargetId = newElement.id
            self.object.sUI.scrollRetryCount = 0
        end
    end

    history.addAction(history.getInsert({ newElement }))
    ImGui.ShowToast(ImGui.Toast.new(ImGui.ToastType.Success, 2500, "Created continuation bended mesh"))
    return true
end

function bendedMesh:getWorldPointFromLocal(localPoint)
    local objectQuat = self.rotation:ToQuat()
    local scaledLocal = self:toScaledLocalPoint(localPoint)
    local worldOffset = objectQuat:Transform(Vector4.new(scaledLocal.x, scaledLocal.y, scaledLocal.z, 0))

    return Vector4.new(
        self.position.x + worldOffset.x,
        self.position.y + worldOffset.y,
        self.position.z + worldOffset.z,
        0
    )
end

function bendedMesh:ensurePathPoints()
    self.pathPoints = self.pathPoints or {}
    if self:isCurveMode() then
        self:syncCurveBones()
    end
    if #self.pathPoints == 0 then
        local defaultPoints = self:getRestPoints()
        if type(defaultPoints) == "table" and #defaultPoints > 0 then
            for _, point in ipairs(defaultPoints) do
                table.insert(self.pathPoints, copyPathPoint(point))
            end
        end

        if #self.pathPoints == 0 then
            table.insert(self.pathPoints, { x = 0, y = 0, z = 0, roll = 0, anchored = true })
        end
    end

    for index, point in ipairs(self.pathPoints) do
        -- A point that says nothing about being anchored is one the payload never authored, and
        -- the two ends of a path are anchored by default. That is a third state on top of the
        -- boolean, so it is settled here rather than through a coercion fallback.
        local authored = point.anchored or point.anchor or point.isAnchored

        if authored == nil then
            point.anchored = index == 1 or index == #self.pathPoints
        else
            point.anchored = utils.toBoolean(authored)
        end
    end

    if #self.pathPoints >= 1 then
        self.pathPoints[1].anchored = true
    end
    if #self.pathPoints >= 2 then
        self.pathPoints[#self.pathPoints].anchored = true
    end
end

function bendedMesh:isPathPointAnchored(index)
    local pathPoints = self.pathPoints or {}

    if index <= 1 or index >= #pathPoints then
        return true
    end

    local point = pathPoints[index]
    return point and point.anchored == true or false
end

---@param interpolation integer
---@param anchorCount integer
---@return table point
local function interpolateAnchorSpan(interpolation, anchorCount, previousPoint, startPoint, endPoint, nextPoint, t)
    if interpolation == 2 then
        return bezierAutoPathPoint(previousPoint, startPoint, endPoint, nextPoint, t)
    elseif interpolation == 1 and anchorCount >= 3 then
        return catmullRomPathPoint(previousPoint, startPoint, endPoint, nextPoint, t)
    end

    return lerpPathPoint(startPoint, endPoint, t)
end

---Samples one anchor span and returns its cumulative arc length table.
---@return table samples `{ t, length }` pairs, from t = 0 to t = 1.
local function sampleAnchorSpan(interpolation, anchorCount, previousPoint, startPoint, endPoint, nextPoint, sampleCount)
    local samples = { { t = 0, length = 0 } }
    local last = startPoint
    local total = 0

    for index = 1, sampleCount do
        local t = index / sampleCount
        local point = interpolateAnchorSpan(interpolation, anchorCount, previousPoint, startPoint, endPoint, nextPoint, t)
        total = total + length3({ x = point.x - last.x, y = point.y - last.y, z = point.z - last.z })
        samples[index + 1] = { t = t, length = total }
        last = point
    end

    return samples
end

---@param samples table From `sampleAnchorSpan`.
---@param fraction number Share of the span's arc length.
---@return number t
local function spanParameterAtFraction(samples, fraction)
    local total = samples[#samples].length
    if total <= 0.000001 then
        return fraction
    end

    local target = fraction * total
    for index = 2, #samples do
        local previous, current = samples[index - 1], samples[index]
        if current.length >= target then
            local width = current.length - previous.length
            local blend = width > 0.000001 and (target - previous.length) / width or 0
            return previous.t + (current.t - previous.t) * blend
        end
    end

    return 1
end

function bendedMesh:applyPathAlgorithmToNonAnchored()
    self:ensurePathPoints()

    if not self.pathUseAlgorithm or self:isCurveMode() then
        return false
    end

    if #self.pathPoints <= 2 then
        return false
    end

    local interpolation = math.max(0, math.min(math.floor(self.pathInterpolation or 0), #pathInterpolationOptions - 1))
    local alongCurve = self.pathSolver == PATH_SOLVER_CURVE
    local restDistances = alongCurve and self:getRestDistances() or nil
    local anchorIndices = {}

    for index = 1, #self.pathPoints do
        if self:isPathPointAnchored(index) then
            table.insert(anchorIndices, index)
        end
    end

    if #anchorIndices < 2 then
        return false
    end

    local changedAny = false

    for anchorOrder = 1, #anchorIndices - 1 do
        local startIndex = anchorIndices[anchorOrder]
        local endIndex = anchorIndices[anchorOrder + 1]
        local span = endIndex - startIndex

        if span > 1 then
            local startPoint = self.pathPoints[startIndex]
            local endPoint = self.pathPoints[endIndex]
            local previousAnchorIndex = anchorIndices[math.max(anchorOrder - 1, 1)]
            local nextAnchorIndex = anchorIndices[math.min(anchorOrder + 2, #anchorIndices)]
            local previousAnchorPoint = self.pathPoints[previousAnchorIndex] or startPoint
            local nextAnchorPoint = self.pathPoints[nextAnchorIndex] or endPoint

            local samples = nil
            if alongCurve then
                samples = sampleAnchorSpan(interpolation, #anchorIndices, previousAnchorPoint, startPoint, endPoint, nextAnchorPoint, span * PATH_CURVE_SAMPLES_PER_BONE)
            end

            for pointIndex = startIndex + 1, endIndex - 1 do
                if not self:isPathPointAnchored(pointIndex) then
                    local t = (pointIndex - startIndex) / span
                    local computed

                    if samples then
                        -- Bones keep the rig's own spacing ratios along the curve.
                        if restDistances then
                            local width = restDistances[endIndex] - restDistances[startIndex]
                            if width > 0.000001 then
                                t = (restDistances[pointIndex] - restDistances[startIndex]) / width
                            end
                        end

                        computed = interpolateAnchorSpan(interpolation, #anchorIndices, previousAnchorPoint, startPoint, endPoint, nextAnchorPoint, spanParameterAtFraction(samples, t))
                        computed.roll = startPoint.roll + (endPoint.roll - startPoint.roll) * t
                    else
                        computed = interpolateAnchorSpan(interpolation, #anchorIndices, previousAnchorPoint, startPoint, endPoint, nextAnchorPoint, t)
                    end

                    local point = self.pathPoints[pointIndex]
                    if point then
                        if math.abs((point.x or 0) - computed.x) > 0.000001
                            or math.abs((point.y or 0) - computed.y) > 0.000001
                            or math.abs((point.z or 0) - computed.z) > 0.000001
                            or math.abs((point.roll or 0) - computed.roll) > 0.000001 then
                            changedAny = true
                        end

                        point.x = computed.x
                        point.y = computed.y
                        point.z = computed.z
                        point.roll = computed.roll
                    end
                end
            end
        end
    end

    return changedAny
end

---Rig of the mesh, or nil while it loads or for a rig that cannot follow a path.
---@return bendedRigData?
function bendedMesh:getRig()
    local data = bendedRig.get(self.spawnData)
    if data and data.linear then
        return data
    end

    return nil
end

---Loads the rig; once it arrives the path is refreshed against the real bind pose.
function bendedMesh:requestRig()
    local path = self.spawnData
    local data = bendedRig.get(path, function (rigData)
        if self.spawnData == path then
            self:onRigReady(rigData)
        end
    end)

    if data then
        self:onRigReady(data)
    end
end

---@param rigData bendedRigData?
function bendedMesh:onRigReady(rigData)
    if not rigData or not rigData.linear then return end

    self._restCache = nil
    self:adoptRigRestPoints(rigData)
    self:applyImportedDeformation(rigData)
    self.pendingAutoFit = true
    self.deformedPreviewSignature = nil
    self:updatePathVisualization()
end

---Bone positions at rest: from the rig once loaded, from the static rig table before that.
---@return table[]? points `{ x, y, z, roll }`, shared; copy before editing.
function bendedMesh:getRestPoints()
    local rigData = self:getRig()
    if rigData then
        return rigData.rest
    end

    if not self._staticRest or self._staticRest.path ~= self.spawnData then
        self._staticRest = { path = self.spawnData, points = cache.getDefaultBendedPathPoints(self.spawnData) }
    end

    return self._staticRest.points
end

---Cumulative rest distance of every bone, or nil when it does not match the path.
---@return number[]?
function bendedMesh:getRestDistances()
    local rigData = self:getRig()
    local count = #(self.pathPoints or {})

    if rigData then
        return #rigData.distances == count and rigData.distances or nil
    end

    local points = self:getRestPoints()
    if not points or #points ~= count then
        return nil
    end

    local distances = { 0 }
    for index = 2, #points do
        local a, b = points[index - 1], points[index]
        distances[index] = distances[index - 1] + length3({ x = b.x - a.x, y = b.y - a.y, z = b.z - a.z })
    end

    return distances
end

---Paths still on the static rig table's defaults move onto the exact rest pose of the rig.
---@param rigData bendedRigData
function bendedMesh:adoptRigRestPoints(rigData)
    local defaults = cache.getDefaultBendedPathPoints(self.spawnData)
    local points = self.pathPoints or {}

    if not defaults or #defaults ~= #points or #points ~= #rigData.rest then return end

    for index, point in ipairs(points) do
        local default = defaults[index]
        if math.abs(point.x - default.x) > 0.001 or math.abs(point.y - default.y) > 0.001 or math.abs(point.z - default.z) > 0.001 then
            return
        end
    end

    for index, point in ipairs(points) do
        local rest = rigData.rest[index]
        point.x, point.y, point.z = rest.x, rest.y, rest.z
    end
end

---Turns a deformation imported from a world node back into path frames: `F = Frest * inverseBind * D`.
---@param rigData bendedRigData
function bendedMesh:applyImportedDeformation(rigData)
    local imported = self.importedDeformation
    if not imported then return end
    self.importedDeformation = nil

    if #imported ~= #rigData.inverseBind or #imported ~= #(self.pathPoints or {}) then return end

    local restFrames = self:buildRestFrames(rigData.rest)
    local matrices = {}
    for index, deformation in ipairs(imported) do
        local frame = bendedRig.mul(bendedRig.mul(bendedRig.fromFrame(restFrames[index]), rigData.inverseBind[index]), deformation)
        matrices[index] = {
            X = { x = frame[1], y = frame[2], z = frame[3] },
            Y = { x = frame[5], y = frame[6], z = frame[7] },
            Z = { x = frame[9], y = frame[10], z = frame[11] },
            W = { x = frame[13], y = frame[14], z = frame[15] }
        }
    end

    local points = bendedMesh.pathPointsFromMatrices(matrices, self.pathUpAxis)
    for index, point in ipairs(points) do
        point.anchored = self.pathPoints[index].anchored
    end
    self.pathPoints = points
end

---@return integer?
function bendedMesh:getMeshBonesQuantity()
    local rigData = bendedRig.get(self.spawnData)
    if rigData then
        return #rigData.inverseBind
    end

    local resourceData = self.meshResourceData
    if not resourceData then
        resourceData = cache.getMeshResource(self.spawnData)
    end

    if resourceData and type(resourceData.rigMatrices) == "table" and #resourceData.rigMatrices > 0 then
        return #resourceData.rigMatrices
    end

    return cache.getDefaultBendedMatrixCount(self.spawnData)
end

function bendedMesh:makeDefaultPathPointAfterCurrent(index)
    self:ensurePathPoints()

    local current = self.pathPoints[index]

    if not current then
        return { x = 0, y = 0, z = 0, roll = 0, anchored = false }
    end

    local axis = { x = 0, y = 1, z = 0 }
    if index < #self.pathPoints and self.pathPoints[index + 1] then
        axis = normalizeDirection({
            x = self.pathPoints[index + 1].x - current.x,
            y = self.pathPoints[index + 1].y - current.y,
            z = self.pathPoints[index + 1].z - current.z
        })
    elseif index > 1 and self.pathPoints[index - 1] then
        axis = normalizeDirection({
            x = current.x - self.pathPoints[index - 1].x,
            y = current.y - self.pathPoints[index - 1].y,
            z = current.z - self.pathPoints[index - 1].z
        })
    end

    if isDirectionZero(axis) then
        axis = { x = 0, y = 1, z = 0 }
    end

    local offset
    if index == #self.pathPoints then
        if index > 1 and self.pathPoints[index - 1] then
            offset = utils.distanceVector(zeroVector3, {
                x = current.x - self.pathPoints[index - 1].x,
                y = current.y - self.pathPoints[index - 1].y,
                z = current.z - self.pathPoints[index - 1].z
            })
            if offset < 0.001 then
                offset = self:getMeshBoundLengthAlongDirection(axis)
            end
        else
            offset = self:getMeshBoundLengthAlongDirection(axis)
        end
    elseif index < #self.pathPoints and self.pathPoints[index + 1] then
        offset = utils.distanceVector(zeroVector3, {
            x = self.pathPoints[index + 1].x - current.x,
            y = self.pathPoints[index + 1].y - current.y,
            z = self.pathPoints[index + 1].z - current.z
        })
    else
        offset = self:getMeshBoundLengthAlongDirection(axis)
    end

    if offset < 0.001 then
        offset = 1
    end

    return {
        x = current.x + axis.x * offset,
        y = current.y + axis.y * offset,
        z = current.z + axis.z * offset,
        roll = current.roll or 0,
        anchored = false
    }
end

function bendedMesh:getSampledPathPoints()
    self:ensurePathPoints()
    self:applyPathAlgorithmToNonAnchored()

    local controlPoints = self.pathPoints
    local sampled = {}
    local sampleInfo = {}
    local looped = self.pathLooped and #controlPoints > 2

    local curveMode = self:isCurveMode()
    for index, point in ipairs(controlPoints) do
        local copy = copyPathPoint(point)
        copy.tangent = point.tangent
        table.insert(sampled, copy)
        if not curveMode and self:isPathPointAnchored(index) then
            table.insert(sampleInfo, { isControlPoint = true, controlPointIndex = index })
        else
            table.insert(sampleInfo, { isControlPoint = false, controlPointIndex = nil })
        end
    end

    if #sampled == 0 then
        table.insert(sampled, { x = 0, y = 0, z = 0, roll = 0, anchored = true })
        table.insert(sampleInfo, { isControlPoint = true, controlPointIndex = 1 })
    end

    return sampled, looped, sampleInfo
end

---Tangent at a path point. Inner points use their neighbours; ends use the chord, or with
---`smoothEnds` the tangent of the parabola through the three end points.
---@return table direction
local function getPathTangent(points, index, looped, smoothEnds)
    local own = points[index] and points[index].tangent
    if own then
        local direction = normalizeDirection(own)
        if not isDirectionZero(direction) then
            return direction
        end
    end

    local count = #points
    if count <= 1 then
        return { x = 0, y = 1, z = 0 }
    end

    local previousIndex = index - 1
    local nextIndex = index + 1
    if looped then
        if previousIndex < 1 then previousIndex = count end
        if nextIndex > count then nextIndex = 1 end
    end

    local previous = points[previousIndex]
    local nextPoint = points[nextIndex]
    local current = points[index]
    local forward

    if previous and nextPoint then
        forward = { x = nextPoint.x - previous.x, y = nextPoint.y - previous.y, z = nextPoint.z - previous.z }
    else
        if nextPoint then
            forward = { x = nextPoint.x - current.x, y = nextPoint.y - current.y, z = nextPoint.z - current.z }
        else
            forward = { x = current.x - previous.x, y = current.y - previous.y, z = current.z - previous.z }
        end

        if smoothEnds and count >= 3 then
            local p0, p1, p2
            if index == 1 then
                p0, p1, p2 = points[1], points[2], points[3]
            else
                p0, p1, p2 = points[count - 2], points[count - 1], points[count]
            end

            local h1 = length3({ x = p1.x - p0.x, y = p1.y - p0.y, z = p1.z - p0.z })
            local h2 = length3({ x = p2.x - p1.x, y = p2.y - p1.y, z = p2.z - p1.z })

            if h1 > 0.000001 and h2 > 0.000001 then
                local a, b, c
                if index == 1 then
                    a, b, c = -(2 * h1 + h2) / (h1 * (h1 + h2)), (h1 + h2) / (h1 * h2), -h1 / (h2 * (h1 + h2))
                else
                    a, b, c = h2 / (h1 * (h1 + h2)), -(h1 + h2) / (h1 * h2), (h1 + 2 * h2) / (h2 * (h1 + h2))
                end

                local smooth = {
                    x = a * p0.x + b * p1.x + c * p2.x,
                    y = a * p0.y + b * p1.y + c * p2.y,
                    z = a * p0.z + b * p1.z + c * p2.z
                }
                if dot(smooth, forward) > 0 then
                    forward = smooth
                end
            end
        end
    end

    forward = normalizeDirection(forward)
    if isDirectionZero(forward) then
        return { x = 0, y = 1, z = 0 }
    end

    return forward
end

---Frames of a list of path points: tangent forward, up from the up axis, then the point's roll.
---@param points table[]
---@param looped boolean
---@param upAxisIndex integer
---@param smoothEnds boolean
---@return table[] frames `{ position, right, forward, up }`
local function buildPathFrames(points, looped, upAxisIndex, smoothEnds)
    local upHint = getPathUpAxis(upAxisIndex)
    local frames = {}
    local lastRight = nil

    for index, point in ipairs(points) do
        local forward = getPathTangent(points, index, looped, smoothEnds)
        local right, _, up = buildBasisFromForward(forward, upHint)

        if lastRight and dot(right, lastRight) < 0 then
            right = { x = -right.x, y = -right.y, z = -right.z }
            up = { x = -up.x, y = -up.y, z = -up.z }
        end

        local roll = utils.toNumber(point.roll, 0)
        if math.abs(roll) > 0.001 then
            local angle = math.rad(roll)
            right = normalizeDirection(rotateAroundAxis(right, forward, angle))
            up = normalizeDirection(rotateAroundAxis(up, forward, angle))
        end

        local upReference = normalizeDirection({
            x = upHint.x - dot(upHint, forward) * forward.x,
            y = upHint.y - dot(upHint, forward) * forward.y,
            z = upHint.z - dot(upHint, forward) * forward.z
        })
        if not isDirectionZero(upReference) and dot(up, upReference) < 0 then
            right = { x = -right.x, y = -right.y, z = -right.z }
            up = { x = -up.x, y = -up.y, z = -up.z }
        end

        table.insert(frames, {
            position = { x = point.x, y = point.y, z = point.z },
            right = right,
            forward = forward,
            up = up
        })

        lastRight = right
    end

    if #frames == 0 then
        frames = {
            {
                position = { x = 0, y = 0, z = 0 },
                right = { x = 1, y = 0, z = 0 },
                forward = { x = 0, y = 1, z = 0 },
                up = { x = 0, y = 0, z = 1 }
            }
        }
    end

    return frames
end

function bendedMesh:getSampledPathFrames()
    local sampledPoints, looped, sampleInfo = self:getSampledPathPoints()
    local frames = buildPathFrames(sampledPoints, looped, self.pathUpAxis, self.pathSolver == PATH_SOLVER_CURVE)

    for index, frame in ipairs(frames) do
        local info = sampleInfo[index]
        frame.isControlPoint = info and info.isControlPoint == true or false
        frame.controlPointIndex = info and info.controlPointIndex or nil
    end

    return frames
end

---Frames of the bones at rest, built the same way as the path's.
---@param restPoints table[]
---@return table[]
function bendedMesh:buildRestFrames(restPoints)
    return buildPathFrames(restPoints, false, self.pathUpAxis, self.pathSolver == PATH_SOLVER_CURVE)
end

---Per-bone rest correction. `pre = bind * Frest^-1` turns a path frame into the bone's deformation,
---so the rest path gives back the bind pose whatever the rig's axes. `restInverse = Frest^-1`
---maps mesh-space geometry into the bone's frame. `pre` is nil until the rig is loaded.
---@param count integer Path point count.
---@return table[]? corrections
function bendedMesh:getRestCorrections(count)
    local restPoints = self:getRestPoints()
    if not restPoints or #restPoints ~= count or count == 0 then
        return nil
    end

    local rigData = self:getRig()
    local key = table.concat({ tostring(self.spawnData), tostring(rigData ~= nil), tostring(self.pathUpAxis), tostring(self.pathSolver), tostring(count) }, "|")
    if self._restCache and self._restCache.key == key then
        return self._restCache.corrections
    end

    local corrections = {}
    for index, frame in ipairs(self:buildRestFrames(restPoints)) do
        local restInverse = bendedRig.inverse(bendedRig.fromFrame(frame))
        corrections[index] = {
            restInverse = restInverse,
            pre = rigData and bendedRig.mul(rigData.bind[index], restInverse) or nil
        }
    end

    self._restCache = { key = key, corrections = corrections }
    return corrections
end

---Deformation matrices, one per bone, in the node's local space.
---@param updateBox boolean Refit the deformed box as well.
---@return table[] matrices `{ X, Y, Z, W }` Vector4 rows.
function bendedMesh:rebuildMatricesFromPath(updateBox)
    local frames = self:getSampledPathFrames()
    local matrices = self:matricesFromFrames(frames)

    if updateBox then
        self:autoFitDeformedBox(frames)
    end

    return matrices
end

---Deformation matrices of a set of bone frames, in the node's local space.
---@param frames table[]
---@return table[] matrices `{ X, Y, Z, W }` Vector4 rows.
function bendedMesh:matricesFromFrames(frames)
    local corrections = self:getRestCorrections(#frames)
    local matrices = {}

    for index, frame in ipairs(frames) do
        local m = bendedRig.fromFrame(frame)
        local pre = corrections and corrections[index].pre
        if pre then
            m = bendedRig.mul(pre, m)
        end

        matrices[index] = {
            X = Vector4.new(m[1], m[2], m[3], 0),
            Y = Vector4.new(m[5], m[6], m[7], 0),
            Z = Vector4.new(m[9], m[10], m[11], 0),
            W = Vector4.new(m[13], m[14], m[15], 1)
        }
    end

    return matrices
end

---Length of the path through its bones, and the rig's length at rest.
---@return number length
---@return number? restLength
function bendedMesh:getPathLengths()
    local sampled, looped = self:getSampledPathPoints()
    local length = 0
    for index = 2, #sampled do
        local a, b = sampled[index - 1], sampled[index]
        length = length + length3({ x = b.x - a.x, y = b.y - a.y, z = b.z - a.z })
    end
    if looped and #sampled > 2 then
        local a, b = sampled[#sampled], sampled[1]
        length = length + length3({ x = b.x - a.x, y = b.y - a.y, z = b.z - a.z })
    end

    local distances = self:getRestDistances()
    return length, distances and distances[#distances] or nil
end

local function subtract(a, b)
    return { x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }
end

local function smoothstep(t)
    return t * t * (3 - 2 * t)
end

---Tangent direction and handle lengths of every curve point. Auto tangents follow the bisector of
---the neighbouring chords; auto ends aim at the next point's handle, like a natural spline.
---@param points table[]
---@param looped boolean
---@return table[] tangents `{ dir, lenIn, lenOut }`
local function getCurveTangents(points, looped)
    local count = #points
    local tangents = {}

    local function neighbour(index)
        if looped then
            return points[(index - 1) % count + 1]
        end
        return points[index]
    end

    for index, point in ipairs(points) do
        local previous = neighbour(index - 1)
        local nextPoint = neighbour(index + 1)
        local chordIn = previous and length3(subtract(point, previous)) or nil
        local chordOut = nextPoint and length3(subtract(nextPoint, point)) or nil
        local dir = point.dir

        if not dir and previous and nextPoint and chordIn > 0.000001 and chordOut > 0.000001 then
            local a = subtract(point, previous)
            local b = subtract(nextPoint, point)
            dir = normalizeDirection({
                x = a.x / chordIn + b.x / chordOut,
                y = a.y / chordIn + b.y / chordOut,
                z = a.z / chordIn + b.z / chordOut
            })
            if isDirectionZero(dir) then dir = nil end
        end

        tangents[index] = {
            dir = dir,
            lenIn = point.lenIn or (chordIn and chordIn / 3) or 0,
            lenOut = point.lenOut or (chordOut and chordOut / 3) or 0
        }
    end

    -- Open ends (and degenerate points) aim at the neighbour's handle.
    for index, point in ipairs(points) do
        if not tangents[index].dir then
            local nextPoint, previous = points[index + 1], points[index - 1]
            local dir
            if nextPoint then
                local handle = nextPoint
                local nextTangent = tangents[index + 1]
                if nextTangent.dir and count > 2 then
                    handle = {
                        x = nextPoint.x - nextTangent.dir.x * nextTangent.lenIn,
                        y = nextPoint.y - nextTangent.dir.y * nextTangent.lenIn,
                        z = nextPoint.z - nextTangent.dir.z * nextTangent.lenIn
                    }
                end
                dir = normalizeDirection(subtract(handle, point))
            elseif previous then
                local handle = previous
                local previousTangent = tangents[index - 1]
                if previousTangent.dir and count > 2 then
                    handle = {
                        x = previous.x + previousTangent.dir.x * previousTangent.lenOut,
                        y = previous.y + previousTangent.dir.y * previousTangent.lenOut,
                        z = previous.z + previousTangent.dir.z * previousTangent.lenOut
                    }
                end
                dir = normalizeDirection(subtract(point, handle))
            end

            if not dir or isDirectionZero(dir) then
                dir = { x = 0, y = 1, z = 0 }
            end
            tangents[index].dir = dir
        end
    end

    return tangents
end

---Cubic Bezier segments between curve points.
---@return table[] segments `{ p0, c0, c1, p1, r0, r1 }`
local function buildCurveSegments(points, looped)
    local tangents = getCurveTangents(points, looped)
    local segments = {}
    local count = #points
    local last = looped and count or count - 1

    for index = 1, last do
        local a, b = points[index], points[index % count + 1]
        local ta, tb = tangents[index], tangents[index % count + 1]
        table.insert(segments, {
            p0 = a,
            c0 = { x = a.x + ta.dir.x * ta.lenOut, y = a.y + ta.dir.y * ta.lenOut, z = a.z + ta.dir.z * ta.lenOut },
            c1 = { x = b.x - tb.dir.x * tb.lenIn, y = b.y - tb.dir.y * tb.lenIn, z = b.z - tb.dir.z * tb.lenIn },
            p1 = b,
            r0 = a.roll or 0,
            r1 = b.roll or 0
        })
    end

    return segments, tangents
end

local function bezierPoint(segment, t)
    return {
        x = cubicBezierScalar(segment.p0.x, segment.c0.x, segment.c1.x, segment.p1.x, t),
        y = cubicBezierScalar(segment.p0.y, segment.c0.y, segment.c1.y, segment.p1.y, t),
        z = cubicBezierScalar(segment.p0.z, segment.c0.z, segment.c1.z, segment.p1.z, t)
    }
end

local function bezierDerivative(segment, t)
    local u = 1 - t
    local function axis(key)
        return 3 * u * u * (segment.c0[key] - segment.p0[key])
            + 6 * u * t * (segment.c1[key] - segment.c0[key])
            + 3 * t * t * (segment.p1[key] - segment.c1[key])
    end

    local d = normalizeDirection({ x = axis("x"), y = axis("y"), z = axis("z") })
    if isDirectionZero(d) then
        d = normalizeDirection(subtract(segment.p1, segment.p0))
    end
    return d
end

---Dense arc-length table over all segments.
---@return table[] samples `{ s, segment, t }`
---@return number length
local function sampleCurveSegments(segments)
    local samples = {}
    local total = 0

    for segmentIndex, segment in ipairs(segments) do
        local previous = segment.p0
        if segmentIndex == 1 then
            table.insert(samples, { s = 0, segment = 1, t = 0 })
        end

        for step = 1, CURVE_SAMPLES_PER_SEGMENT do
            local t = step / CURVE_SAMPLES_PER_SEGMENT
            local point = bezierPoint(segment, t)
            total = total + length3(subtract(point, previous))
            table.insert(samples, { s = total, segment = segmentIndex, t = t })
            previous = point
        end
    end

    return samples, total
end

---Curve position, tangent and roll at arc length `s`. Past the end the curve continues straight.
---Segment and parameter at arc length `s`, clamped to the curve.
---@return integer segment
---@return number t
local function locateCurve(samples, total, s)
    if s <= 0 then
        return 1, 0
    end
    if s >= total then
        return samples[#samples].segment, 1
    end

    local low, high = 1, #samples
    while high - low > 1 do
        local middle = math.floor((low + high) / 2)
        if samples[middle].s < s then low = middle else high = middle end
    end

    local a, b = samples[low], samples[high]
    local blend = (b.s - a.s) > 0.000001 and (s - a.s) / (b.s - a.s) or 0
    local ta = a.segment == b.segment and a.t or 0
    return b.segment, ta + (b.t - ta) * blend
end

local function evaluateCurveAt(segments, samples, total, s)
    local function at(segmentIndex, t)
        local segment = segments[segmentIndex]
        local position = bezierPoint(segment, t)
        return position, bezierDerivative(segment, t), segment.r0 + (segment.r1 - segment.r0) * smoothstep(t)
    end

    if s >= total then
        local position, tangent, roll = at(#segments, 1)
        local extra = s - total
        return { x = position.x + tangent.x * extra, y = position.y + tangent.y * extra, z = position.z + tangent.z * extra }, tangent, roll
    end
    return at(locateCurve(samples, total, s))
end

---@return boolean
function bendedMesh:isCurveMode()
    return self.pathMode == PATH_MODE_CURVE
end

---Rest distances for a bone count, falling back to even spacing.
---@param count integer
---@return number[] distances
function bendedMesh:getRestDistancesFor(count)
    local rigData = self:getRig()
    if rigData and #rigData.distances == count then
        return rigData.distances
    end

    local points = self:getRestPoints()
    local distances = { 0 }
    if points and #points == count then
        for index = 2, #points do
            distances[index] = distances[index - 1] + length3(subtract(points[index], points[index - 1]))
        end
        return distances
    end

    for index = 2, count do
        distances[index] = index - 1
    end
    return distances
end

---Two curve points at the rest ends of the rig, or the anchored bones of the current path.
function bendedMesh:ensureCurvePoints()
    self.curvePoints = self.curvePoints or {}
    if #self.curvePoints >= 2 then return end

    local source = {}
    local hasBones = type(self.pathPoints) == "table" and #self.pathPoints >= 2
    if hasBones then
        for index, point in ipairs(self.pathPoints) do
            if index == 1 or index == #self.pathPoints or point.anchored then
                table.insert(source, point)
            end
        end
    else
        local rest = self:getRestPoints()
        if rest and #rest >= 2 then
            source = { rest[1], rest[#rest] }
        else
            source = { { x = 0, y = 0, z = 0 }, { x = 0, y = self:getMeshBoundLengthAlongDirection({ x = 0, y = 1, z = 0 }), z = 0 } }
        end
    end

    self.curvePoints = {}
    for _, point in ipairs(source) do
        table.insert(self.curvePoints, copyCurvePoint(point))
    end
end

---Places the bones along the curve. Cached on everything the placement depends on.
function bendedMesh:syncCurveBones()
    self:ensureCurvePoints()

    local count = self:getMeshBonesQuantity() or #(self.pathPoints or {})
    if count < 2 then count = 2 end
    local looped = self.pathLooped and #self.curvePoints > 2

    local keyParts = { tostring(self.spawnData), tostring(count), tostring(looped), tostring(self.pathLengthMode), tostring(self:getRig() ~= nil) }
    for _, point in ipairs(self.curvePoints) do
        table.insert(keyParts, string.format("%.5f,%.5f,%.5f,%.4f", point.x, point.y, point.z, point.roll or 0))
        if point.dir then
            table.insert(keyParts, string.format("%.5f,%.5f,%.5f,%s,%s", point.dir.x, point.dir.y, point.dir.z, tostring(point.lenIn), tostring(point.lenOut)))
        end
    end
    local key = table.concat(keyParts, "|")
    if key == self._curveKey and self.pathPoints and #self.pathPoints == count then return end
    self._curveKey = key

    local segments = buildCurveSegments(self.curvePoints, looped)
    local samples, total = sampleCurveSegments(segments)
    local distances = self:getRestDistancesFor(count)
    local restTotal = distances[#distances]
    local keepLength = self.pathLengthMode == LENGTH_MODE_KEEP and not looped
    self._curveLength = total

    local bones = {}
    for index = 1, count do
        local s
        if keepLength then
            s = distances[index]
        elseif looped then
            local gap = restTotal / math.max(1, count - 1)
            s = restTotal + gap > 0 and distances[index] / (restTotal + gap) * total or 0
        else
            s = restTotal > 0 and distances[index] / restTotal * total or (index - 1) / (count - 1) * total
        end

        local position, tangent, roll = evaluateCurveAt(segments, samples, total, s)
        bones[index] = {
            x = position.x, y = position.y, z = position.z,
            roll = roll,
            anchored = index == 1 or index == count,
            tangent = tangent
        }
    end

    self.pathPoints = bones
end

---Number of meshes Split into Chain would make: the Pieces setting, or the automatic count.
---1 when the curve fits one mesh or cannot be split.
---@return integer
function bendedMesh:getSplitCount()
    if not self:isCurveMode() or self.pathLooped or self.pathLengthMode ~= LENGTH_MODE_FIT then return 1 end

    local chain = self._toolSettings and self._toolSettings.chainCount
    if chain and chain > 0 then return chain end
    return (self:getAutoChainCount())
end

---Deformation matrices of each piece Split into Chain would make, in the node's local space.
---@param count integer
---@return table[] pieces One matrix list per piece.
function bendedMesh:getSplitPieceMatrices(count)
    local pieces = {}
    for index, frames in ipairs(self:getSplitPieceFrames(count)) do
        pieces[index] = self:matricesFromFrames(frames)
    end
    return pieces
end

---Bone frames of each piece Split into Chain would make, in mesh space.
---@param count integer
---@return table[] pieces One frame list per piece.
function bendedMesh:getSplitPieceFrames(count)
    local bones = self:getMeshBonesQuantity() or #self.pathPoints
    local segments = buildCurveSegments(self.curvePoints, false)
    local samples, total = sampleCurveSegments(segments)
    local distances = self:getRestDistancesFor(bones)
    local restTotal = distances[#distances]
    local span = total / count
    local pieces = {}

    for piece = 1, count do
        local points = {}
        for index = 1, bones do
            local fraction = restTotal > 0 and distances[index] / restTotal or (index - 1) / math.max(1, bones - 1)
            local position, tangent, roll = evaluateCurveAt(segments, samples, total, span * (piece - 1 + fraction))
            points[index] = { x = position.x, y = position.y, z = position.z, roll = roll, tangent = tangent }
        end
        pieces[piece] = buildPathFrames(points, false, self.pathUpAxis, self.pathSolver == PATH_SOLVER_CURVE)
    end

    return pieces
end

---Points along the curve at even arc-length steps, in mesh space, for drawing it.
---@param maxSegments integer
---@return table[] points
function bendedMesh:getCurveDrawPoints(maxSegments)
    local segments = buildCurveSegments(self.curvePoints, self.pathLooped and #self.curvePoints > 2)
    local samples, total = sampleCurveSegments(segments)
    local count = math.min(maxSegments, math.max(#segments * CURVE_DRAW_MIN_PER_SEGMENT, math.ceil(total / CURVE_DRAW_STEP)))

    local points = {}
    for index = 0, count do
        points[index + 1] = (evaluateCurveAt(segments, samples, total, total * index / count))
    end
    return points
end

---Resolved tangent of every curve point, for the editor and the overlay.
---@return table[]
function bendedMesh:getCurveTangents()
    self:ensureCurvePoints()
    return getCurveTangents(self.curvePoints, self.pathLooped and #self.curvePoints > 2)
end

---Curve length and the rig's rest length.
---@return number length
---@return number? restLength
function bendedMesh:getCurveLength()
    self:ensureCurvePoints()
    local segments = buildCurveSegments(self.curvePoints, self.pathLooped and #self.curvePoints > 2)
    local _, total = sampleCurveSegments(segments)
    local count = self:getMeshBonesQuantity()
    local distances = count and self:getRestDistancesFor(count) or nil
    return total, distances and distances[#distances] or nil
end

---Frame at each curve point, in mesh space.
---@return table[]
function bendedMesh:getCurveFrames()
    local tangents = self:getCurveTangents()
    local frames = {}
    for index, point in ipairs(self.curvePoints) do
        local frame = buildPathFrames({ { x = point.x, y = point.y, z = point.z, roll = point.roll, tangent = tangents[index].dir } }, false, self.pathUpAxis, true)[1]
        frame.isControlPoint = true
        frame.controlPointIndex = index
        frames[index] = frame
    end
    return frames
end

---Switches between the curve and the per-bone editor, keeping the shape.
---@param mode integer
function bendedMesh:setPathMode(mode)
    if mode == self.pathMode then return end

    if mode == PATH_MODE_CURVE then
        self.curvePoints = {}
        self:ensurePathPoints()
        self.pathMode = PATH_MODE_CURVE
        self:ensureCurvePoints()
        self._curveKey = nil
    else
        self:ensurePathPoints()
        self.pathMode = PATH_MODE_BONES
        for _, point in ipairs(self.pathPoints) do
            point.anchored = true
            point.tangent = nil
        end
    end
end

---Heading and slope (degrees) of a direction in mesh space; heading 0 is +Y, positive turns left.
local function directionToAngles(dir)
    return math.deg(math.atan2(-dir.x, dir.y)), math.deg(math.asin(math.max(-1, math.min(1, dir.z))))
end

local function anglesToDirection(heading, slope)
    local h, s = math.rad(heading), math.rad(slope)
    return { x = -math.sin(h) * math.cos(s), y = math.cos(h) * math.cos(s), z = math.sin(s) }
end

---Inserts a curve point on the curve halfway along the segment after `index`.
---@param index integer
function bendedMesh:insertCurvePointAfter(index)
    local looped = self.pathLooped and #self.curvePoints > 2
    local segments = buildCurveSegments(self.curvePoints, looped)
    local segment = segments[index]
    if not segment then return end

    local samples, _ = sampleCurveSegments({ segment })
    local position = evaluateCurveAt({ segment }, samples, samples[#samples].s, samples[#samples].s / 2)
    local a, b = self.curvePoints[index], self.curvePoints[index % #self.curvePoints + 1]
    table.insert(self.curvePoints, index + 1, {
        x = position.x, y = position.y, z = position.z,
        roll = ((a.roll or 0) + (b.roll or 0)) / 2
    })
end

---Appends a curve point past the end, along the end tangent.
function bendedMesh:appendCurvePoint()
    local count = #self.curvePoints
    local last = self.curvePoints[count]
    local tangents = self:getCurveTangents()
    local dir = tangents[count].dir
    local step = length3(subtract(last, self.curvePoints[count - 1] or { x = last.x, y = last.y - 1, z = last.z }))
    if step < 0.01 then step = 1 end

    table.insert(self.curvePoints, {
        x = last.x + dir.x * step, y = last.y + dir.y * step, z = last.z + dir.z * step,
        roll = last.roll or 0
    })
end


function bendedMesh:matrixToPreviewFrame(matrix)
    local axisX = normalizeDirection({
        x = utils.toNumber(matrix and matrix.X and (matrix.X.x or matrix.X.X), 1),
        y = utils.toNumber(matrix and matrix.X and (matrix.X.y or matrix.X.Y), 0),
        z = utils.toNumber(matrix and matrix.X and (matrix.X.z or matrix.X.Z), 0)
    })
    local axisY = normalizeDirection({
        x = utils.toNumber(matrix and matrix.Y and (matrix.Y.x or matrix.Y.X), 0),
        y = utils.toNumber(matrix and matrix.Y and (matrix.Y.y or matrix.Y.Y), 1),
        z = utils.toNumber(matrix and matrix.Y and (matrix.Y.z or matrix.Y.Z), 0)
    })
    local axisZ = normalizeDirection({
        x = utils.toNumber(matrix and matrix.Z and (matrix.Z.x or matrix.Z.X), 0),
        y = utils.toNumber(matrix and matrix.Z and (matrix.Z.y or matrix.Z.Y), 0),
        z = utils.toNumber(matrix and matrix.Z and (matrix.Z.z or matrix.Z.Z), 1)
    })
    local position = {
        x = utils.toNumber(matrix and matrix.W and (matrix.W.x or matrix.W.X), 0),
        y = utils.toNumber(matrix and matrix.W and (matrix.W.y or matrix.W.Y), 0),
        z = utils.toNumber(matrix and matrix.W and (matrix.W.z or matrix.W.Z), 0)
    }

    if isDirectionZero(axisX) then axisX = { x = 1, y = 0, z = 0 } end
    if isDirectionZero(axisY) then axisY = { x = 0, y = 1, z = 0 } end
    if isDirectionZero(axisZ) then axisZ = { x = 0, y = 0, z = 1 } end

    return {
        position = position,
        right = axisX,
        forward = axisY,
        up = axisZ,
        isControlPoint = matrix and matrix.isControlPoint == true,
        controlPointIndex = matrix and matrix.controlPointIndex or nil
    }
end

---Rebuilds the editor path from a set of deformation matrices, inverting
---`rebuildMatricesFromPath`. One matrix is one path point: its W column is the point itself, and
---the twist of its up axis against the untwisted basis of the same forward direction is the
---point's roll. Every rebuilt point comes back anchored, so the path algorithm leaves an
---imported deformation exactly as it was authored.
---@param matrices table Deformation matrices, in node order.
---@param upAxisIndex integer? Up axis to read the twist against, `World Z` by default.
---@return table pathPoints
function bendedMesh.pathPointsFromMatrices(matrices, upAxisIndex)
    local clampedUpAxisIndex = math.max(0, math.min(math.floor(utils.toNumber(upAxisIndex, 0)), #pathUpAxisOptions - 1))
    local upHint = getPathUpAxis(clampedUpAxisIndex)
    local pathPoints = {}

    for _, matrix in ipairs(matrices or {}) do
        local frame = bendedMesh:matrixToPreviewFrame(matrix)
        local _, _, untwistedUp = buildBasisFromForward(frame.forward, upHint)
        local twist = cross(untwistedUp, frame.up)
        local roll = math.deg(math.atan2(dot(twist, frame.forward), dot(untwistedUp, frame.up)))

        if math.abs(roll) < 0.001 then
            roll = 0
        end

        table.insert(pathPoints, {
            x = frame.position.x,
            y = frame.position.y,
            z = frame.position.z,
            roll = roll,
            anchored = true
        })
    end

    return pathPoints
end

---Pool of host entities the path preview lives on. A long path draws far more components than
---one entity can hold, and all four families (segments, control points, subdivisions, frames)
---share that ceiling, so none of them live on the mesh entity itself.
---@return previewHostPool
function bendedMesh:getPathPreviewHosts()
    if not self._pathPreviewHosts then
        self._pathPreviewHosts = previewHosts.new(PATH_PREVIEW_COMPONENTS_PER_HOST, function ()
            self._pathPreviewAssembling = true
            local ok, err = pcall(self.updatePathVisualization, self)
            self._pathPreviewAssembling = false
            if not ok then error(err) end
        end)
    end

    return self._pathPreviewHosts
end

function bendedMesh:getPathPreviewComponent(name, meshPath, appearance)
    if not self:getEntity() then
        return nil
    end

    local host = self:getPathPreviewHosts():hostForName(name, self.position, self.rotation)
    if not host then
        return nil
    end

    local component = host:FindComponentByName(name)
    if component then
        return component
    end

    if appearance == "green" then
        appearance = "lime"
    end

    component = entMeshComponent.new()
    component.name = name
    component.mesh = ResRef.FromString(meshPath)
    component.meshAppearance = appearance or "default"
    component.visualScale = Vector3.new(0.01, 0.01, 0.01)
    component.isEnabled = false

    if not self._pathPreviewAssembling then
        self._pathPreviewRehost = true
    end

    -- Keep preview components bound to a stable placed parent so runtime-added
    -- components retain valid local transforms (same pattern as visualizer.lua).
    visualizer.bindToPlacedParent(host, component)

    host:AddComponent(component)
    return component
end

function bendedMesh:togglePathPreviewComponent(name, state)
    local component = self:getPathPreviewHosts():findComponentByName(name)

    if component then
        component:Toggle(state)
    end
end

function bendedMesh:despawn()
    self:getPathPreviewHosts():despawn()
    self:releasePreviewPieces(0)
    bendedCollisionPreview.release(self)
    self.deformedPreviewSignature = nil
    mesh.despawn(self)
end

function bendedMesh:update()
    mesh.update(self)
    -- Hosts hold the preview in mesh-local coordinates, so they follow the mesh when it moves.
    self:getPathPreviewHosts():updateTransforms(self.position, self.rotation)
    self:refreshDeformedPreview()
end

---Fingerprint of everything the deformed preview depends on.
---@return string
function bendedMesh:getDeformedPreviewSignature()
    local parts = {
        tostring(self.spawnData), tostring(self.app),
        tostring(self.castShadows), tostring(self.castLocalShadows),
        tostring(self.pathLooped), tostring(self.pathUseAlgorithm),
        tostring(self.pathInterpolation), tostring(self.pathUpAxis),
        tostring(self.pathSolver), tostring(self:getRig() ~= nil)
    }
    local function add(...)
        for _, value in ipairs({ ... }) do
            table.insert(parts, string.format("%.4f", utils.toNumber(value, 0)))
        end
    end

    add(self.position.x, self.position.y, self.position.z)
    add(self.rotation.roll, self.rotation.pitch, self.rotation.yaw)
    add(self.scale.x, self.scale.y, self.scale.z)

    local box = self:getNormalizedDeformedBox()
    add(box.min.x, box.min.y, box.min.z, box.max.x, box.max.y, box.max.z)

    for _, point in ipairs(self.pathPoints or {}) do
        add(point.x, point.y, point.z, point.roll)
        table.insert(parts, point.anchored and "a" or "f")
    end

    return table.concat(parts, "|")
end

---World-space payload for the placeholder node: path matrices composed with T * R * S.
---@param matrices table[]? Local deformation, defaults to the path's.
---@return bendedPoolPayload? payload
---@return string? issue
function bendedMesh:buildDeformedPreviewPayload(matrices)
    matrices = matrices or self:rebuildMatricesFromPath(false)
    local bones = self:getMeshBonesQuantity()

    if bones and bones ~= #matrices then
        return nil, string.format("Path has %d points but the mesh has %d bones.", #matrices, bones)
    end

    local quat = self.rotation:ToQuat()
    local scale = self.scale or { x = 1, y = 1, z = 1 }
    local position = self.position

    local function toWorld(v, isPoint)
        local rotated = quat:Transform(Vector4.new(v.x * scale.x, v.y * scale.y, v.z * scale.z, 0))
        if isPoint then
            return rotated.x + position.x, rotated.y + position.y, rotated.z + position.z
        end

        return rotated.x, rotated.y, rotated.z
    end

    local payloadMatrices = {}
    for i, matrix in ipairs(matrices) do
        local xx, xy, xz = toWorld(matrix.X)
        local yx, yy, yz = toWorld(matrix.Y)
        local zx, zy, zz = toWorld(matrix.Z)
        local wx, wy, wz = toWorld(matrix.W, true)

        payloadMatrices[i] = { xx, xy, xz, 0, yx, yy, yz, 0, zx, zy, zz, 0, wx, wy, wz, 1 }
    end

    local box = self:getNormalizedDeformedBox()
    local minimum = { math.huge, math.huge, math.huge }
    local maximum = { -math.huge, -math.huge, -math.huge }
    for _, cx in ipairs({ box.min.x, box.max.x }) do
        for _, cy in ipairs({ box.min.y, box.max.y }) do
            for _, cz in ipairs({ box.min.z, box.max.z }) do
                local corner = { toWorld({ x = cx, y = cy, z = cz }, true) }
                for axis = 1, 3 do
                    minimum[axis] = math.min(minimum[axis], corner[axis])
                    maximum[axis] = math.max(maximum[axis], corner[axis])
                end
            end
        end
    end

    local app = self.app
    if app == nil or app == "" then
        app = "default"
    end

    return {
        mesh = self.spawnData,
        appearance = app,
        matrices = payloadMatrices,
        box = { minimum[1], minimum[2], minimum[3], maximum[1], maximum[2], maximum[3] },
        castShadows = self.shadowCastingModeEnum[self.castShadows + 1],
        castLocalShadows = self.shadowCastingModeEnum[self.castLocalShadows + 1]
    }
end

---Brings the deformed mesh and the live collision up to date with the path.
function bendedMesh:refreshDeformedPreview()
    self:refreshDeformedMesh()
    self:refreshCollisionPreview()
end

---Convex collision pieces deformed by the current path, in the mesh entity's local space (scaled).
---An unsplit curve gives the pieces of the chain a split would make, like the preview and the export.
---@return bendedCollisionShape[]? shapes
---@return string? issue
function bendedMesh:getCollisionShapes()
    local rigData = self:getRig()
    local source = bendedCollision.get(self.spawnData)

    if not source then
        return nil, "No collision data for this mesh."
    end
    if not rigData then
        return nil, "Waiting for the mesh rig."
    end

    if self:isCurveMode() then
        self:syncCurveBones()
    end

    local splitCount = self:getSplitCount()
    local pieces = splitCount > 1 and self:getSplitPieceMatrices(splitCount) or { self:rebuildMatricesFromPath(false) }
    local shapes = {}
    for _, matrices in ipairs(pieces) do
        local deformed = bendedCollision.deform(source, bendedCollision.getSkinMatrices(rigData, matrices))
        if not deformed then
            return nil, "The path does not drive every bone of the mesh."
        end
        for _, shape in ipairs(deformed) do
            table.insert(shapes, shape)
        end
    end

    local scale = self.scale or { x = 1, y = 1, z = 1 }
    if scale.x ~= 1 or scale.y ~= 1 or scale.z ~= 1 then
        for _, shape in ipairs(shapes) do
            for _, point in ipairs(shape.points) do
                point.x, point.y, point.z = point.x * scale.x, point.y * scale.y, point.z * scale.z
            end
        end
    end

    for _, shape in ipairs(shapes) do
        local material = self.collisionMaterials[shape.class]
        if material and material ~= "" then
            shape.material = material
        end
        shape.preset = self.collisionPresets[shape.class] or DEFAULT_COLLISION_PRESET
    end

    return shapes
end

---Fingerprint of the collision settings, on top of the deformation.
---@return string
function bendedMesh:getCollisionSettingsSignature()
    local parts = {}
    for _, class in ipairs(COLLISION_CLASSES) do
        table.insert(parts, tostring(self.collisionMaterials[class]))
        table.insert(parts, tostring(self.collisionPresets[class]))
    end
    return table.concat(parts, "|")
end

---Keeps the live collision in step with the path; it is rebuilt once the shape stops changing.
function bendedMesh:refreshCollisionPreview()
    if not self.liveCollisionEnabled or self.isAssetPreview or not self:getEntity() then
        bendedCollisionPreview.release(self)
        return
    end

    if self:isCurveMode() then
        self:syncCurveBones()
    end

    bendedCollisionPreview.request(self, self:getDeformedPreviewSignature() .. "#" .. self:getSplitCount() .. "#" .. self:getCollisionSettingsSignature())
    bendedCollisionPreview.setVisual(self, self.collisionShapeVisible and colliderColors[settings.colliderColor + 1] or nil)
end

---Pushes the current deformation to a placeholder node when anything it depends on changed.
function bendedMesh:refreshDeformedMesh()
    local active = self.deformedPreviewEnabled and not self.isAssetPreview and self:getEntity() ~= nil

    if not active then
        if self.deformedPreviewSignature then
            self:releasePreviewPieces(0)
            self.deformedPreviewSignature = nil
            self:applyEntityMeshVisibility()
        end
        return
    end

    if self:isCurveMode() then
        self:syncCurveBones()
    end

    -- An unsplit curve longer than the mesh is previewed as the chain a split would make.
    local count = self:getSplitCount()
    local signature = self:getDeformedPreviewSignature() .. "#" .. count
    if signature == self.deformedPreviewSignature then return end
    self.deformedPreviewSignature = signature

    local payloads, issue = {}, nil
    if count > 1 then
        for index, matrices in ipairs(self:getSplitPieceMatrices(count)) do
            payloads[index], issue = self:buildDeformedPreviewPayload(matrices)
            if not payloads[index] then
                payloads = {}
                break
            end
        end
    else
        payloads[1], issue = self:buildDeformedPreviewPayload()
    end
    self.deformedPreviewIssue = issue
    self.deformedPreviewPieces = #payloads

    if #payloads == 0 then
        self:releasePreviewPieces(0)
        self:applyEntityMeshVisibility()
        return
    end

    self:releasePreviewPieces(#payloads)
    for index, payload in ipairs(payloads) do
        bendedPool.submit(self:getPreviewPieceOwner(index), payload)
    end
end

---Pool owner of preview piece `index`; the mesh itself owns the first.
---@param index integer
---@return table
function bendedMesh:getPreviewPieceOwner(index)
    if index == 1 then return self end

    self._previewPieceOwners = self._previewPieceOwners or {}
    local owner = self._previewPieceOwners[index]
    if not owner then
        owner = {}
        self._previewPieceOwners[index] = owner
    end
    return owner
end

---Releases the preview pieces past `count`.
---@param count integer
function bendedMesh:releasePreviewPieces(count)
    if count < 1 then
        bendedPool.release(self)
    end
    for index, owner in pairs(self._previewPieceOwners or {}) do
        if index > count then
            bendedPool.release(owner)
            self._previewPieceOwners[index] = nil
        end
    end
end

---Hides the undeformed entity mesh while the placeholder shows the deformed one.
function bendedMesh:applyEntityMeshVisibility()
    local entity = self:getEntity()
    if not entity then return end

    local component = entity:FindComponentByName("mesh")
    if component then
        component:Toggle(not bendedPool.isShowing(self))
    end
end

---Called by the pool once the placeholder first displays this mesh.
function bendedMesh:onBendedPreviewShown()
    self:applyEntityMeshVisibility()
end

function bendedMesh:hidePathPreviewOverflow(prefix, used, previousCount)
    for i = used + 1, previousCount do
        self:togglePathPreviewComponent(prefix .. tostring(i), false)
    end
end

function bendedMesh:toScaledLocalPoint(point)
    local scale = self.scale or { x = 1, y = 1, z = 1 }
    return {
        x = point.x * scale.x,
        y = point.y * scale.y,
        z = point.z * scale.z
    }
end

function bendedMesh:getPathPreviewFrameLength()
    local extentX = math.abs((self.bBox.max and self.bBox.max.x or 0.5) - (self.bBox.min and self.bBox.min.x or -0.5))
    local extentY = math.abs((self.bBox.max and self.bBox.max.y or 0.5) - (self.bBox.min and self.bBox.min.y or -0.5))
    local extentZ = math.abs((self.bBox.max and self.bBox.max.z or 0.5) - (self.bBox.min and self.bBox.min.z or -0.5))
    local maxExtent = math.max(extentX, extentY, extentZ, 0.1)

    return math.max(0.02, math.min(4, maxExtent * PATH_PREVIEW_FRAME_LENGTH))
end

function bendedMesh:getMeshWidthRange()
    local minX = self.bBox and self.bBox.min and self.bBox.min.x or -0.5
    local maxX = self.bBox and self.bBox.max and self.bBox.max.x or 0.5

    if minX > maxX then
        minX, maxX = maxX, minX
    end

    if math.abs(maxX - minX) < 0.0001 then
        minX = -0.5
        maxX = 0.5
    end

    return minX, maxX
end

function bendedMesh:renderPathPreviewLine(namePrefix, index, startPoint, endPoint, appearance, thickness)
    local component = self:getPathPreviewComponent(namePrefix .. tostring(index), "base\\spawner\\cube_aligned.mesh", appearance)
    if not component then
        return false
    end

    local diff = {
        x = endPoint.x - startPoint.x,
        y = endPoint.y - startPoint.y,
        z = endPoint.z - startPoint.z
    }
    local length = utils.distanceVector(zeroVector3, diff)
    if length <= 0.0001 then
        component:Toggle(false)
        return false
    end

    local direction = Vector4.new(diff.x, diff.y, diff.z, 0)
    local rotation = direction:ToRotation()
    local yaw = rotation.yaw + 90
    local roll = rotation.pitch

    component.visualScale = Vector3.new(math.max(0.0001, length / 2), thickness, thickness)
    component:SetLocalOrientation(EulerAngles.new(roll, 0, yaw):ToQuat())
    component:SetLocalPosition(Vector4.new(startPoint.x, startPoint.y, startPoint.z, 0))
    component:Toggle(true)
    component:RefreshAppearance()

    return true
end

function bendedMesh:renderPathControlPoint(index, point)
    local component = self:getPathPreviewComponent("bendPathCtrl" .. tostring(index), "base\\environment\\ld_kit\\marker.mesh", "yellow")
    if not component then
        return false
    end

    local scaledPoint = self:toScaledLocalPoint(point)
    component.visualScale = Vector3.new(PATH_PREVIEW_POINT_SCALE, PATH_PREVIEW_POINT_SCALE, PATH_PREVIEW_POINT_SCALE)
    component:SetLocalPosition(Vector4.new(scaledPoint.x, scaledPoint.y, scaledPoint.z, 0))
    component:SetLocalOrientation(EulerAngles.new(0, 0, 0):ToQuat())
    component:Toggle(true)
    component:RefreshAppearance()

    return true
end

function bendedMesh:renderPathSubdivisionMarker(index, frame, xMin, xMax, thickness, color)
    local originLocal = frame.position or { x = 0, y = 0, z = 0 }
    local axisX = normalizeDirection(frame.right or { x = 1, y = 0, z = 0 })
    if isDirectionZero(axisX) then
        axisX = { x = 1, y = 0, z = 0 }
    end

    local startLocal = {
        x = originLocal.x + axisX.x * xMin,
        y = originLocal.y + axisX.y * xMin,
        z = originLocal.z + axisX.z * xMin
    }
    local endLocal = {
        x = originLocal.x + axisX.x * xMax,
        y = originLocal.y + axisX.y * xMax,
        z = originLocal.z + axisX.z * xMax
    }

    local startPoint = self:toScaledLocalPoint(startLocal)
    local endPoint = self:toScaledLocalPoint(endLocal)

    return self:renderPathPreviewLine("bendPathDirMain", index, startPoint, endPoint, color or "red", thickness)
end

function bendedMesh:renderPathFrameWithPrefix(prefix, index, frame, axisLength, thickness, options)
    local originLocal = frame.position or { x = 0, y = 0, z = 0 }
    local axisX = normalizeDirection(frame.right or { x = 1, y = 0, z = 0 })
    local axisY = normalizeDirection(frame.forward or { x = 0, y = 1, z = 0 })
    local axisZ = normalizeDirection(frame.up or { x = 0, y = 0, z = 1 })

    if isDirectionZero(axisX) then axisX = { x = 1, y = 0, z = 0 } end
    if isDirectionZero(axisY) then axisY = { x = 0, y = 1, z = 0 } end
    if isDirectionZero(axisZ) then axisZ = { x = 0, y = 0, z = 1 } end

    local xMin = options and options.xRangeMin
    local xMax = options and options.xRangeMax
    local hasWidthRange = xMin ~= nil and xMax ~= nil
    local xStartLocal = hasWidthRange and {
        x = originLocal.x + axisX.x * xMin,
        y = originLocal.y + axisX.y * xMin,
        z = originLocal.z + axisX.z * xMin
    } or originLocal
    local xEndLocal = hasWidthRange and {
        x = originLocal.x + axisX.x * xMax,
        y = originLocal.y + axisX.y * xMax,
        z = originLocal.z + axisX.z * xMax
    } or {
        x = originLocal.x + axisX.x * axisLength,
        y = originLocal.y + axisX.y * axisLength,
        z = originLocal.z + axisX.z * axisLength
    }
    local yEndLocal = {
        x = originLocal.x + axisY.x * axisLength,
        y = originLocal.y + axisY.y * axisLength,
        z = originLocal.z + axisY.z * axisLength
    }
    local zEndLocal = {
        x = originLocal.x + axisZ.x * axisLength,
        y = originLocal.y + axisZ.y * axisLength,
        z = originLocal.z + axisZ.z * axisLength
    }

    local origin = self:toScaledLocalPoint(originLocal)
    local xStart = self:toScaledLocalPoint(xStartLocal)
    local xEnd = self:toScaledLocalPoint(xEndLocal)
    local yEnd = self:toScaledLocalPoint(yEndLocal)
    local zEnd = self:toScaledLocalPoint(zEndLocal)

    local colorX = options and options.uniformColor or "red"
    local colorY = options and options.uniformColor or "green"
    local colorZ = options and options.uniformColor or "blue"
    local drawn = false
    drawn = self:renderPathPreviewLine(prefix .. "X", index, xStart, xEnd, colorX, thickness) or drawn
    drawn = self:renderPathPreviewLine(prefix .. "Y", index, origin, yEnd, colorY, thickness) or drawn
    drawn = self:renderPathPreviewLine(prefix .. "Z", index, origin, zEnd, colorZ, thickness) or drawn

    return drawn
end

function bendedMesh:renderPathFrame(index, frame, axisLength, thickness, options)
    return self:renderPathFrameWithPrefix("bendPathFrame", index, frame, axisLength, thickness, options)
end

function bendedMesh:hideFrameTriplet(prefix, index)
    self:togglePathPreviewComponent(prefix .. "X" .. tostring(index), false)
    self:togglePathPreviewComponent(prefix .. "Y" .. tostring(index), false)
    self:togglePathPreviewComponent(prefix .. "Z" .. tostring(index), false)
end

function bendedMesh:updatePathVisualization()
    local entity = self:getEntity()
    if not entity then return end
    self:ensurePathPoints()
    self:refreshDeformedPreview()

    local showPreview = (not self.isAssetPreview) and self.pathPreviewEnabled
    if not showPreview then
        -- Despawning the hosts drops every preview component with them, which is cheaper than
        -- hiding them one by one and leaves nothing behind while the preview is off.
        self:getPathPreviewHosts():despawn()
        self.pathPreviewSegmentCount = 0
        self.pathPreviewControlCount = 0
        self.pathPreviewSubdivisionCount = 0
        self.pathPreviewFrameCount = 0
        self.pathPreviewHandleCount = 0
        return
    end

    local segmentThickness = PATH_PREVIEW_LINE_THICKNESS
    local looped = self.pathLooped and #self.pathPoints > 2
    local frames = self:getSampledPathFrames()
    local curveMode = self:isCurveMode()
    local controlFrames = {}
    if curveMode then
        controlFrames = self:getCurveFrames()
    else
        for _, frame in ipairs(frames) do
            if frame.isControlPoint then
                table.insert(controlFrames, frame)
            end
        end
    end
    local widthMin, widthMax = self:getMeshWidthRange()
    local previousSegmentCount = self.pathPreviewSegmentCount
    local previousControlCount = self.pathPreviewControlCount
    local previousSubdivisionCount = self.pathPreviewSubdivisionCount
    local previousFrameCount = self.pathPreviewFrameCount

    -- Curve mode draws the curve itself; the bones of one unsplit mesh are too sparse to follow it.
    local linePoints = {}
    if curveMode then
        linePoints = self:getCurveDrawPoints(CURVE_DRAW_MAX_SEGMENTS)
    elseif #frames > 1 then
        for i, frame in ipairs(frames) do
            linePoints[i] = frame.position
        end
        if looped then
            table.insert(linePoints, frames[1].position)
        end
    end

    -- Bone markers follow the pieces the preview shows.
    local markerFrames = frames
    local splitCount = self:getSplitCount()
    if splitCount > 1 then
        markerFrames = {}
        for _, pieceFrames in ipairs(self:getSplitPieceFrames(splitCount)) do
            for _, frame in ipairs(pieceFrames) do
                table.insert(markerFrames, frame)
            end
        end
    end

    local usedSegments = 0
    local requiredSegments = math.max(0, #linePoints - 1)

    -- Spawn every host this pass needs up front, so a path that just grew converges in a single
    -- redraw instead of one per host. Overshooting only costs a host the trim below gives back.
    local requiredFrameComponents = math.min(#markerFrames, PATH_PREVIEW_MAX_SEGMENTS)
        + 3 * math.min(#frames, PATH_PREVIEW_MAX_FRAMES) + 3
    local requiredHandles = curveMode and 2 * #controlFrames or 0
    local requiredComponents = requiredSegments + #self.pathPoints + #controlFrames + requiredHandles + requiredFrameComponents
    self:getPathPreviewHosts():ensure(requiredComponents, self.position, self.rotation)

    for i = 1, requiredSegments do
        local startPoint = self:toScaledLocalPoint(linePoints[i])
        local endPoint = self:toScaledLocalPoint(linePoints[i + 1])
        local nextIndex = usedSegments + 1
        if self:renderPathPreviewLine("bendPathSeg", nextIndex, startPoint, endPoint, "cyan", segmentThickness) then
            usedSegments = nextIndex
        end
    end

    self:hidePathPreviewOverflow("bendPathSeg", usedSegments, previousSegmentCount)
    self.pathPreviewSegmentCount = usedSegments

    local usedControls = 0

    for _, frame in ipairs(controlFrames) do
        if frame.position then
            local nextIndex = usedControls + 1
            if self:renderPathControlPoint(nextIndex, frame.position) then
                usedControls = nextIndex
            end
        end
    end

    self:hidePathPreviewOverflow("bendPathCtrl", usedControls, previousControlCount)
    self.pathPreviewControlCount = usedControls

    local usedHandles = 0
    if curveMode then
        for index, tangent in ipairs(self:getCurveTangents()) do
            local point = self.curvePoints[index]
            local origin = self:toScaledLocalPoint(point)
            for _, side in ipairs({ { length = -tangent.lenIn }, { length = tangent.lenOut } }) do
                if math.abs(side.length) > 0.001 then
                    local tip = self:toScaledLocalPoint({
                        x = point.x + tangent.dir.x * side.length,
                        y = point.y + tangent.dir.y * side.length,
                        z = point.z + tangent.dir.z * side.length
                    })
                    if self:renderPathPreviewLine("bendPathHandle", usedHandles + 1, origin, tip, point.dir and "orange" or "white", segmentThickness * 0.6) then
                        usedHandles = usedHandles + 1
                    end
                end
            end
        end
    end
    self:hidePathPreviewOverflow("bendPathHandle", usedHandles, self.pathPreviewHandleCount or 0)
    self.pathPreviewHandleCount = usedHandles

    local frameLength = self:getPathPreviewFrameLength()
    local frameThickness = math.max(0.002, segmentThickness * 0.75)
    local subdivisionThickness = math.max(0.0015, frameThickness * 0.85)
    local usedSubdivisions = 0
    local maxSubdivisions = PATH_PREVIEW_MAX_SEGMENTS

    if maxSubdivisions > 0 then
        for _, frame in ipairs(markerFrames) do
            if usedSubdivisions >= maxSubdivisions then break end
            if frame and not frame.isControlPoint then
                local nextIndex = usedSubdivisions + 1
                if self:renderPathSubdivisionMarker(nextIndex, frame, widthMin, widthMax, subdivisionThickness, "red") then
                    usedSubdivisions = nextIndex
                end
            end
        end
    end

    self:hidePathPreviewOverflow("bendPathDirMain", usedSubdivisions, previousSubdivisionCount)
    self.pathPreviewSubdivisionCount = usedSubdivisions

    local usedFrames = 0
    local maxFrames = PATH_PREVIEW_MAX_FRAMES
    for _, frame in ipairs(controlFrames) do
        if usedFrames >= maxFrames then break end
        if frame then
            local nextIndex = usedFrames + 1
            if self:renderPathFrame(nextIndex, frame, frameLength, frameThickness, {
                xRangeMin = widthMin,
                xRangeMax = widthMax
            }) then
                usedFrames = nextIndex
            end
        end
    end

    for i = usedFrames + 1, previousFrameCount do
        self:hideFrameTriplet("bendPathFrame", i)
    end
    self.pathPreviewFrameCount = usedFrames

    if #frames > 0 then
        local focusFrame = nil

        for _, frame in ipairs(controlFrames) do
            if frame.controlPointIndex == PATH_PREVIEW_FOCUS_POINT then
                focusFrame = frame
                break
            end
        end

        if not focusFrame then
            focusFrame = frames[1]
        end

        if focusFrame then
            self:renderPathFrameWithPrefix("bendPathFocusFrame", 1, focusFrame, frameLength, math.max(0.002, frameThickness * 1.1), {
                xRangeMin = widthMin,
                xRangeMax = widthMax
            })
        else
            self:hideFrameTriplet("bendPathFocusFrame", 1)
        end
    else
        self:hideFrameTriplet("bendPathFocusFrame", 1)
    end

    local hosts = self:getPathPreviewHosts()

    -- A component added to an attached host never renders; fresh hosts redraw everything while
    -- they assemble, without touching the mesh itself.
    if self._pathPreviewRehost then
        self._pathPreviewRehost = false
        hosts:despawn()
        self.pathPreviewSegmentCount = 0
        self.pathPreviewControlCount = 0
        self.pathPreviewSubdivisionCount = 0
        self.pathPreviewFrameCount = 0
        self.pathPreviewHandleCount = 0
        hosts:ensure(requiredComponents, self.position, self.rotation)
        return
    end

    if not hosts.pending then
        hosts:trim(math.max(1, hosts:getChunkCount(hosts.nextSlot)))
    end
end

function bendedMesh:autoFitDeformedBox(frames)
    self.deformedBox = self:computeDeformedBox(frames)
end

---Box of the mesh deformed by `frames`, in mesh space.
---@param frames table[]?
---@return table box `{ min, max }` Vector4.
function bendedMesh:computeDeformedBox(frames)
    local baseMin = self.bBox and self.bBox.min or Vector4.new(-0.5, -0.5, -0.5, 0)
    local baseMax = self.bBox and self.bBox.max or Vector4.new(0.5, 0.5, 0.5, 0)
    frames = frames or self:getSampledPathFrames()

    local corners = {
        Vector4.new(baseMin.x, baseMin.y, baseMin.z, 1),
        Vector4.new(baseMax.x, baseMin.y, baseMin.z, 1),
        Vector4.new(baseMin.x, baseMax.y, baseMin.z, 1),
        Vector4.new(baseMax.x, baseMax.y, baseMin.z, 1),
        Vector4.new(baseMin.x, baseMin.y, baseMax.z, 1),
        Vector4.new(baseMax.x, baseMin.y, baseMax.z, 1),
        Vector4.new(baseMin.x, baseMax.y, baseMax.z, 1),
        Vector4.new(baseMax.x, baseMax.y, baseMax.z, 1)
    }

    -- Geometry around a bone moves with `Frest^-1 * F`, so each bone carries the mesh box with it.
    local corrections = self:getRestCorrections(#frames)
    local transformed = {}
    for index, frame in ipairs(frames) do
        if corrections then
            local m = bendedRig.mul(corrections[index].restInverse, bendedRig.fromFrame(frame))
            for _, corner in ipairs(corners) do
                local p = bendedRig.transformPoint(m, corner)
                table.insert(transformed, Vector4.new(p.x, p.y, p.z, 1))
            end
        else
            for _, corner in ipairs(corners) do
                table.insert(transformed, transformPointWithFrame(frame, corner))
            end
        end
    end

    if #transformed == 0 then
        return copyDeformedBox(nil)
    end

    local minimum, maximum = utils.getVector4BBox(transformed)
    minimum.w = 1
    maximum.w = 1
    return {
        min = minimum,
        max = maximum
    }
end

--- Viewport handles ---------------------------------------------------------------------------

local HANDLE_POINT_RADIUS = 6
local HANDLE_TIP_RADIUS = 4
local HANDLE_PICK_RADIUS = 11
local HANDLE_CURVE_PICK_RADIUS = 20
local HANDLE_CURVE_SAMPLES = 32
local HOVER_ARROW_LENGTH = 6

local handleColors = {
    path = 0xC8FFE000,
    point = 0xFF33CCFF,
    pointHover = 0xFFFFFFFF,
    pointActive = 0xFF2E8BFF,
    pointJoined = 0xFFE860E0,
    pointRemove = 0xFF3333FF,
    pointInsert = 0xFF66E666,
    pointInsertLine = 0x9666E666,
    tangentAuto = 0xC8D0D0D0,
    tangentManual = 0xFF2EA0FF,
    snapCandidate = 0xFFA0A0A0,
    hint = 0xFFE8E8E8,
    hintTitle = 0xFF33CCFF,
    hintBackground = 0xB4141414
}

local function isKeyDown(...)
    for _, key in ipairs({ ... }) do
        if ImGui.IsKeyDown(key) then return true end
    end
    return false
end

---Mesh-space point (before scale) of a world point.
---@param world table
---@return table
function bendedMesh:worldToLocalPoint(world)
    local quat = self.rotation:ToQuat()
    local offset = { x = world.x - self.position.x, y = world.y - self.position.y, z = world.z - self.position.z }
    local scale = self.scale or { x = 1, y = 1, z = 1 }

    local function component(axis, s)
        local a = quat:Transform(axis)
        local value = offset.x * a.x + offset.y * a.y + offset.z * a.z
        return math.abs(s) > 0.000001 and value / s or value
    end

    return {
        x = component(Vector4.new(1, 0, 0, 0), scale.x),
        y = component(Vector4.new(0, 1, 0, 0), scale.y),
        z = component(Vector4.new(0, 0, 1, 0), scale.z)
    }
end

---@return boolean
function bendedMesh:wantsViewportOverlay()
    return not self.isAssetPreview
        and self.object ~= nil
        and self.object.selected == true
end

---Whether the editing handles are drawn and interactive.
---@return boolean
function bendedMesh:hasViewportHandles()
    return self.viewportHandlesEnabled ~= false and self:wantsViewportOverlay() and not self.object:isLocked()
end

---Handles of the current edit mode, in world space.
---@return table[] handles `{ kind = "point"|"tangent", index, side?, world }`
function bendedMesh:getViewportHandles()
    local handles = {}
    self:ensurePathPoints()

    if self:isCurveMode() then
        local looped = self.pathLooped and #self.curvePoints > 2
        local tangents = self:getCurveTangents()

        for index, point in ipairs(self.curvePoints) do
            local world = self:getWorldPointFromLocal(point)
            table.insert(handles, { kind = "point", index = index, world = world })

            local tangent = tangents[index]
            for _, side in ipairs({ "in", "out" }) do
                -- Open ends have one handle that shapes nothing.
                local used = looped or (side == "in" and index > 1) or (side == "out" and index < #self.curvePoints)
                local length = side == "in" and -tangent.lenIn or tangent.lenOut
                if used and math.abs(length) > 0.001 then
                    table.insert(handles, {
                        kind = "tangent", index = index, side = side, anchor = world,
                        world = self:getWorldPointFromLocal({
                            x = point.x + tangent.dir.x * length,
                            y = point.y + tangent.dir.y * length,
                            z = point.z + tangent.dir.z * length
                        })
                    })
                end
            end
        end
    else
        self:applyPathAlgorithmToNonAnchored()
        for index, point in ipairs(self.pathPoints) do
            if self:isPathPointAnchored(index) then
                table.insert(handles, { kind = "point", index = index, world = self:getWorldPointFromLocal(point) })
            end
        end
    end

    return handles
end

---Applies a dragged handle's new world position.
---@param handle table
---@param world table
function bendedMesh:moveViewportHandle(handle, world)
    local target = self:worldToLocalPoint(world)

    if handle.kind == "point" then
        local point = self:isCurveMode() and self.curvePoints[handle.index] or self.pathPoints[handle.index]
        if not point then return end
        point.x, point.y, point.z = target.x, target.y, target.z
    else
        local point = self.curvePoints[handle.index]
        if not point then return end

        local offset = { x = target.x - point.x, y = target.y - point.y, z = target.z - point.z }
        local length = length3(offset)
        if length < 0.01 then return end

        if not point.dir then
            local tangent = self:getCurveTangents()[handle.index]
            point.lenIn, point.lenOut = tangent.lenIn, tangent.lenOut
        end

        local sign = handle.side == "in" and -1 or 1
        point.dir = { x = sign * offset.x / length, y = sign * offset.y / length, z = sign * offset.z / length }
        if handle.side == "in" then
            point.lenIn = length
        else
            point.lenOut = length
        end
    end

    self:ensurePathPoints()
    self:updatePathVisualization()
end

---Closest point of the curve under the cursor, as an insertion after control point `index`.
---@return integer? index Segment start.
---@return table? local Mesh-space position on the curve.
function bendedMesh:pickCurveInsertion(screen, mouseX, mouseY)
    local looped = self.pathLooped and #self.curvePoints > 2
    local segments = buildCurveSegments(self.curvePoints, looped)
    local best, bestIndex, bestPoint = HANDLE_CURVE_PICK_RADIUS, nil, nil

    -- Distance to the projected polyline, so the pick follows the curve between samples.
    local bestT, bestSegment = nil, nil
    for index, segment in ipairs(segments) do
        local previous, previousT = nil, 0
        for step = 0, HANDLE_CURVE_SAMPLES do
            local t = step / HANDLE_CURVE_SAMPLES
            local projected = projectedWireframe.projectWorldPoint(screen, self:getWorldPointFromLocal(bezierPoint(segment, t)))
            if projected and not projected.behind then
                if previous then
                    local dx, dy = projected.x - previous.x, projected.y - previous.y
                    local lengthSquared = dx * dx + dy * dy
                    local u = lengthSquared > 0.0001 and math.max(0, math.min(1, ((mouseX - previous.x) * dx + (mouseY - previous.y) * dy) / lengthSquared)) or 0
                    local distance = math.sqrt((previous.x + dx * u - mouseX) ^ 2 + (previous.y + dy * u - mouseY) ^ 2)
                    if distance < best then
                        best, bestIndex, bestSegment = distance, index, segment
                        bestT = math.max(0.01, math.min(0.99, previousT + (t - previousT) * u))
                    end
                end
                previous, previousT = projected, t
            else
                previous = nil
            end
        end
    end

    if bestSegment then
        bestPoint = bezierPoint(bestSegment, bestT)
    end

    return bestIndex, bestPoint
end

---Where a drag of the current handle lands this frame, from the modifiers held.
local function getDragTarget(self, drag, editor)
    local origin = GetPlayer():GetFPPCameraComponent():GetLocalToWorld():GetTranslation()
    local ray = editor.getScreenToWorldRay()

    local mode = "plane"
    if isKeyDown(ImGuiKey.LeftCtrl, ImGuiKey.RightCtrl) then
        mode = "snap"
    elseif isKeyDown(ImGuiKey.X) then
        mode = "x"
    elseif isKeyDown(ImGuiKey.Y) then
        mode = "y"
    elseif isKeyDown(ImGuiKey.Z, ImGuiKey.LeftShift, ImGuiKey.RightShift) then
        mode = "z"
    end

    -- A modifier change restarts the drag from where the handle is now.
    if mode ~= drag.mode then
        drag.mode = mode
        drag.start = { x = drag.current.x, y = drag.current.y, z = drag.current.z }
        drag.reference = nil
    end

    if mode == "snap" then
        local hit = editor.getRaySceneIntersection(ray, origin, { [self.object.id] = true }, true)
        if hit and hit.hit and hit.result and hit.result.position then
            local p = hit.result.position
            return { x = p.x, y = p.y, z = p.z }
        end
        return nil
    end

    if mode == "plane" then
        if math.abs(ray.z) < 0.0001 then return nil end
        local distance = (drag.start.z - origin.z) / ray.z
        if distance <= 0 then return nil end
        local hit = { x = origin.x + ray.x * distance, y = origin.y + ray.y * distance, z = drag.start.z }
        drag.reference = drag.reference or { x = hit.x - drag.start.x, y = hit.y - drag.start.y, z = 0 }
        return { x = hit.x - drag.reference.x, y = hit.y - drag.reference.y, z = drag.start.z }
    end

    local axis = Vector4.new(mode == "x" and 1 or 0, mode == "y" and 1 or 0, mode == "z" and 1 or 0, 0)
    local start = Vector4.new(drag.start.x, drag.start.y, drag.start.z, 0)
    local t = intersection.getTClosestToRay(start, axis, origin, ray)
    drag.reference = drag.reference or t
    local along = t - drag.reference
    return { x = drag.start.x + axis.x * along, y = drag.start.y + axis.y * along, z = drag.start.z + axis.z * along }
end

---Hint box: the current action as a title, a blank line, then the hotkeys.
---@param drawList table
---@param title string
---@param text string
---@param titleColor number?
local function drawHint(drawList, x, y, title, text, titleColor)
    local body = text and ("\n\n" .. text) or ""
    local width, height = ImGui.CalcTextSize(title .. body)
    ImGui.ImDrawListAddRectFilled(drawList, x + 14, y + 14, x + 22 + width, y + 20 + height, handleColors.hintBackground, 4)
    ImGui.ImDrawListAddText(drawList, ImGui.GetFontSize(), x + 18, y + 17, titleColor or handleColors.hintTitle, title)
    ImGui.ImDrawListAddText(drawList, ImGui.GetFontSize(), x + 18, y + 17, handleColors.hint, body)
end

local dragModeLabels = {
    plane = "horizontal",
    x = "along X",
    y = "along Y",
    z = "vertical",
    snap = "on the surface"
}

---Draws the editing handles, and marks the end or point hovered in the properties.
---@param screen table
---@param drawList table
function bendedMesh:drawViewportOverlay(screen, drawList)
    -- Set by `draw` every frame a button or row is hovered, consumed here.
    local hoveredEnd, hoveredPoint, hoveredSnap = self._hoveredEnd, self._hoveredPoint, self._hoveredSnap
    self._hoveredEnd, self._hoveredPoint, self._hoveredSnap = nil, nil, nil
    if not self:wantsViewportOverlay() then return end

    if self:hasViewportHandles() then
        self:drawViewportHandles(screen, drawList)
    end
    self:drawHoveredIndicator(screen, drawList, hoveredEnd, hoveredPoint)
    if hoveredSnap then
        self:drawSnapIndicator(screen, drawList, hoveredSnap == "start")
    end
end

---Marks the end a Continue button acts on, or the point a row edits.
---@param screen table
---@param drawList table
---@param hoveredEnd string? `start` or `end`.
---@param hoveredPoint table? `{ kind = "curve"|"bone", index }`
function bendedMesh:drawHoveredIndicator(screen, drawList, hoveredEnd, hoveredPoint)
    local world, title, text, arrow
    if hoveredEnd then
        local frames = self:getSampledPathFrames()
        local atStart = hoveredEnd == "start"
        local frame = self:pathFrameToWorld(frames[atStart and 1 or #frames])
        local s = atStart and -1 or 1
        local p, f = frame.position, frame.forward
        world = Vector4.new(p.x, p.y, p.z, 1)
        arrow = Vector4.new(p.x + s * f.x * HOVER_ARROW_LENGTH, p.y + s * f.y * HOVER_ARROW_LENGTH, p.z + s * f.z * HOVER_ARROW_LENGTH, 1)
        title = atStart and "Start" or "End"
        text = atStart and "The new mesh is joined here, before the first point." or "The new mesh is joined here, after the last point."
    elseif hoveredPoint then
        local points = hoveredPoint.kind == "curve" and self.curvePoints or self.pathPoints
        local point = points and points[hoveredPoint.index]
        if not point then return end
        local p = self:getWorldPointFromLocal(point)
        world = Vector4.new(p.x, p.y, p.z, 1)
        title = (hoveredPoint.kind == "curve" and "Point " or "Bone ") .. hoveredPoint.index
    else
        return
    end

    if arrow then
        projectedWireframe.drawWorldLine(drawList, screen, world, arrow, { color = handleColors.pointActive, thickness = 3 })
    end

    local projected = projectedWireframe.projectWorldPoint(screen, world)
    if not projected or projected.behind then return end
    ImGui.ImDrawListAddCircle(drawList, projected.x, projected.y, HANDLE_POINT_RADIUS + 6, 0xC8000000, -1, 4)
    ImGui.ImDrawListAddCircle(drawList, projected.x, projected.y, HANDLE_POINT_RADIUS + 6, handleColors.pointActive, -1, 2)
    ImGui.ImDrawListAddCircleFilled(drawList, projected.x, projected.y, HANDLE_POINT_RADIUS - 1, handleColors.pointActive, -1)
    drawHint(drawList, projected.x, projected.y, title, text, handleColors.pointActive)
end

---Draws the editing handles and runs their mouse interaction.
---@param screen table
---@param drawList table
function bendedMesh:drawViewportHandles(screen, drawList)
    local editor = require("modules/utils/editor/editor")
    local handles = self:getViewportHandles()
    local curveMode = self:isCurveMode()

    -- The curve itself in Curve mode, the path through the bones otherwise.
    local linePoints = self.pathPoints
    if curveMode then
        self:syncCurveBones()
        if not self._overlayCurve or self._overlayCurve.key ~= self._curveKey then
            self._overlayCurve = { key = self._curveKey, points = self:getCurveDrawPoints(CURVE_DRAW_MAX_SEGMENTS) }
        end
        linePoints = self._overlayCurve.points
    end

    local previous = nil
    for _, point in ipairs(linePoints) do
        local world = self:getWorldPointFromLocal(point)
        if previous then
            projectedWireframe.drawWorldLine(drawList, screen, previous, world, { color = handleColors.path, thickness = 2 })
        end
        previous = world
    end

    local mouseX, mouseY = ImGui.GetMousePos()
    local interactive = editor.active and not editor.grab and not editor.rotate and not editor.scale
        and (input.context.viewport.hovered or self._handleDrag ~= nil)
        and (self._handleDrag ~= nil or not input.isUIInputActive())
    local altDown = isKeyDown(ImGuiKey.LeftAlt, ImGuiKey.RightAlt)

    local hovered, hoveredDistance = nil, HANDLE_PICK_RADIUS
    for _, handle in ipairs(handles) do
        handle.screen = projectedWireframe.projectWorldPoint(screen, handle.world)
        if interactive and handle.screen and not handle.screen.behind then
            local distance = math.sqrt((handle.screen.x - mouseX) ^ 2 + (handle.screen.y - mouseY) ^ 2)
            -- Points win ties over the tangent tips sitting on top of them.
            if distance < hoveredDistance or (handle.kind == "point" and hovered and hovered.kind ~= "point" and distance < HANDLE_PICK_RADIUS) then
                hovered, hoveredDistance = handle, distance
            end
        end
    end

    local drag = self._handleDrag

    -- Where an Alt+click would add a point: on the curve under the cursor, else at the end.
    -- Alt+Ctrl always adds at the start.
    local insertion = nil
    local atStart = isKeyDown(ImGuiKey.LeftCtrl, ImGuiKey.RightCtrl)
    if interactive and altDown and curveMode and not drag and not hovered then
        local index, localPoint = nil, nil
        if not atStart then
            index, localPoint = self:pickCurveInsertion(screen, mouseX, mouseY)
        end
        if index then
            insertion = { index = index, localPoint = localPoint }
        else
            local hit = editor.getCursorSceneHit({ [self.object.id] = true })
            if hit and hit.hit and hit.result and hit.result.position then
                local position = hit.result.position
                insertion = { world = { x = position.x, y = position.y, z = position.z }, atStart = atStart }
            end
        end
    end

    if drag then
        if ImGui.IsMouseDown(ImGuiMouseButton.Left) then
            local target = getDragTarget(self, drag, editor)
            if target then
                drag.current = target

                -- Alt: a linked end lets go of the meshes joined to it, a free point snaps onto nearby points.
                drag.snap = nil
                drag.candidates = nil
                if altDown and drag.handle.kind == "point" and curveMode then
                    if drag.partners and #drag.partners > 0 then
                        drag.detached = drag.detached or {}
                        for _, partner in ipairs(drag.partners) do
                            drag.detached[partner.mesh] = true
                        end
                        drag.partners = {}
                    end
                    drag.candidates = self:collectPointSnapCandidates(drag.detached, drag.handle.index)
                    drag.snap = bendedMesh.findPointSnap(screen, mouseX, mouseY, drag.candidates)
                    if drag.snap then
                        target = drag.snap.position
                    end
                end

                self:moveViewportHandle(drag.handle, target)
                local isEnd = drag.handle.index == 1 or drag.handle.index == #self.curvePoints
                if drag.snap and drag.snap.frame and isEnd then
                    self:joinPointToEnd(drag.handle.index, drag.snap)
                    self:ensurePathPoints()
                    self:updatePathVisualization()
                elseif drag.snap and drag.snap.ownEnd then
                    self:joinOwnEnds(drag.handle.index)
                    self:ensurePathPoints()
                    self:updatePathVisualization()
                end
                self:syncJoinedEnds(drag.handle.index, drag.partners)
            end
        else
            self._handleDrag = nil
            self:autoFitDeformedBox()
            self:refreshArrowScale()
            for _, partner in ipairs(drag.partners or {}) do
                if partner.mesh ~= self then
                    partner.mesh:autoFitDeformedBox()
                    partner.mesh:refreshArrowScale()
                end
            end
        end
    elseif interactive and ImGui.IsMouseClicked(ImGuiMouseButton.Left) then
        if hovered and not altDown then
            -- Meshes joined at a dragged end move with it, in the same undo step.
            local partners = curveMode and self:findJoinedEnds(hovered.index) or {}
            local elements = { self.object }
            for _, partner in ipairs(partners) do
                if partner.mesh ~= self then
                    table.insert(elements, partner.element)
                end
            end
            if #elements > 1 then
                history.addAction(history.getMultiSelectChange(elements))
            else
                history.addAction(history.getElementChange(self.object))
            end
            -- Surface snap raycasts must not land on the collision of the meshes being dragged.
            bendedCollisionPreview.suspend(self)
            for _, partner in ipairs(partners) do
                if partner.mesh ~= self then
                    bendedCollisionPreview.suspend(partner.mesh)
                end
            end
            self._handleDrag = {
                handle = { kind = hovered.kind, index = hovered.index, side = hovered.side },
                current = { x = hovered.world.x, y = hovered.world.y, z = hovered.world.z },
                partners = partners
            }
            self._handleDrag.start = self._handleDrag.current
        elseif altDown and curveMode then
            if hovered and hovered.kind == "point" then
                if #self.curvePoints > 2 then
                    history.addAction(history.getElementChange(self.object))
                    table.remove(self.curvePoints, hovered.index)
                    self:ensurePathPoints()
                    self:autoFitDeformedBox()
                    self:refreshArrowScale()
                end
            elseif hovered and hovered.kind == "tangent" then
                history.addAction(history.getElementChange(self.object))
                local point = self.curvePoints[hovered.index]
                point.dir, point.lenIn, point.lenOut = nil, nil, nil
                self:ensurePathPoints()
                self:autoFitDeformedBox()
                self:refreshArrowScale()
            elseif insertion then
                history.addAction(history.getElementChange(self.object))
                if insertion.index then
                    local index, localPoint = insertion.index, insertion.localPoint
                    local a, b = self.curvePoints[index], self.curvePoints[index % #self.curvePoints + 1]
                    table.insert(self.curvePoints, index + 1, {
                        x = localPoint.x, y = localPoint.y, z = localPoint.z,
                        roll = ((a.roll or 0) + (b.roll or 0)) / 2
                    })
                else
                    local target = self:worldToLocalPoint(insertion.world)
                    local position = insertion.atStart and 1 or #self.curvePoints + 1
                    local neighbour = insertion.atStart and self.curvePoints[1] or self.curvePoints[#self.curvePoints]
                    table.insert(self.curvePoints, position, {
                        x = target.x, y = target.y, z = target.z,
                        roll = neighbour.roll or 0
                    })
                end
                insertion = nil
                self:ensurePathPoints()
                self:autoFitDeformedBox()
                self:refreshArrowScale()
            end
        elseif altDown and hovered and hovered.kind == "point" and hovered.index > 1 and hovered.index < #self.pathPoints then
            history.addAction(history.getElementChange(self.object))
            self.pathPoints[hovered.index].anchored = false
            self:ensurePathPoints()
            self:autoFitDeformedBox()
            self:refreshArrowScale()
        end
    end

    -- Handles may have moved during the drag; draw from the latest positions.
    if self._handleDrag then
        handles = self:getViewportHandles()
        for _, handle in ipairs(handles) do
            handle.screen = projectedWireframe.projectWorldPoint(screen, handle.world)
        end
    end

    local active = self._handleDrag and self._handleDrag.handle
    local function isSame(a, b)
        return a and b and a.kind == b.kind and a.index == b.index and a.side == b.side
    end

    -- Alt+drag: every point the dragged one can snap onto. This curve's own end is already a handle.
    for _, candidate in ipairs(self._handleDrag and self._handleDrag.candidates or {}) do
        if not candidate.ownEnd then
            local position = candidate.position
            local projected = projectedWireframe.projectWorldPoint(screen, Vector4.new(position.x, position.y, position.z, 1))
            if projected and not projected.behind then
                ImGui.ImDrawListAddCircleFilled(drawList, projected.x, projected.y, HANDLE_TIP_RADIUS + 1.5, 0xC8000000, -1)
                ImGui.ImDrawListAddCircleFilled(drawList, projected.x, projected.y, HANDLE_TIP_RADIUS, handleColors.snapCandidate, -1)
            end
        end
    end

    for _, handle in ipairs(handles) do
        if handle.kind == "tangent" and handle.screen and not handle.screen.behind then
            local manual = self.curvePoints[handle.index] and self.curvePoints[handle.index].dir ~= nil
            local color = manual and handleColors.tangentManual or handleColors.tangentAuto
            projectedWireframe.drawWorldLine(drawList, screen, handle.anchor, handle.world, { color = color, thickness = 1.5 })
            local radius = (isSame(handle, hovered) or isSame(handle, active)) and HANDLE_TIP_RADIUS + 2 or HANDLE_TIP_RADIUS
            ImGui.ImDrawListAddRectFilled(drawList, handle.screen.x - radius, handle.screen.y - radius, handle.screen.x + radius, handle.screen.y + radius, color, 1)
        end
    end

    -- Ends joined to another mesh's end move together.
    local joined = {}
    if curveMode then
        for _, index in ipairs({ 1, #self.curvePoints }) do
            joined[index] = #self:findJoinedEnds(index) > 0
        end
    end

    -- Alt+click on the hovered point removes it (Curve) or releases its anchor (Bones).
    local removable = altDown and not self._handleDrag and hovered and hovered.kind == "point"
        and (curveMode and #self.curvePoints > 2 or (not curveMode and hovered.index > 1 and hovered.index < #self.pathPoints))

    for _, handle in ipairs(handles) do
        if handle.kind == "point" and handle.screen and not handle.screen.behind then
            local color = handleColors.point
            if isSame(handle, active) then
                color = handleColors.pointActive
            elseif isSame(handle, hovered) then
                color = removable and handleColors.pointRemove or handleColors.pointHover
            elseif joined[handle.index] then
                color = handleColors.pointJoined
            end
            ImGui.ImDrawListAddCircleFilled(drawList, handle.screen.x, handle.screen.y, HANDLE_POINT_RADIUS + 1.5, 0xC8000000, -1)
            ImGui.ImDrawListAddCircleFilled(drawList, handle.screen.x, handle.screen.y, HANDLE_POINT_RADIUS, color, -1)
        end
    end

    if insertion then
        local world = insertion.world or self:getWorldPointFromLocal(insertion.localPoint)
        world = Vector4.new(world.x, world.y, world.z, 1)
        local projected = projectedWireframe.projectWorldPoint(screen, world)
        if projected and not projected.behind then
            if not insertion.index then
                local neighbour = self:getWorldPointFromLocal(self.curvePoints[insertion.atStart and 1 or #self.curvePoints])
                projectedWireframe.drawWorldLine(drawList, screen, neighbour, world, { color = handleColors.pointInsertLine, thickness = 1.5 })
            end
            ImGui.ImDrawListAddCircleFilled(drawList, projected.x, projected.y, HANDLE_POINT_RADIUS + 1.5, 0xC8000000, -1)
            ImGui.ImDrawListAddCircleFilled(drawList, projected.x, projected.y, HANDLE_POINT_RADIUS, handleColors.pointInsert, -1)
        end
    end

    local snap = self._handleDrag and self._handleDrag.snap
    if snap then
        local projected = projectedWireframe.projectWorldPoint(screen, Vector4.new(snap.position.x, snap.position.y, snap.position.z, 1))
        if projected and not projected.behind then
            ImGui.ImDrawListAddCircle(drawList, projected.x, projected.y, HANDLE_POINT_RADIUS + 6, handleColors.pointActive, -1, 2)
        end
    end

    if interactive and (hovered or self._handleDrag) then
        local title, text, titleColor
        if self._handleDrag then
            local dragged = self._handleDrag.handle
            local target = dragged.kind == "tangent" and ("the tangent of point " .. dragged.index) or ("point " .. dragged.index)
            if self._handleDrag.snap then
                title = IconGlyphs.Magnet .. " Snapping " .. target .. " to " .. tostring(self._handleDrag.snap.name)
            else
                title = "Moving " .. target .. " " .. dragModeLabels[self._handleDrag.mode or "plane"]
            end
            text = "Hold: Horizontal (X/Y, hold X or Y to lock an axis)\nShift / Z: vertical (Z)\nCtrl: snap to the surface"
            if curveMode and dragged.kind == "point" then
                text = text .. "\nAlt: detach linked ends, snap to nearby points and to this mesh's other end"
            end
        elseif hovered.kind == "tangent" then
            title = altDown and ("Reset the tangent of point " .. hovered.index) or ("Tangent of point " .. hovered.index)
            text = "Drag: edit the tangent\nAlt+click: back to automatic"
        else
            if removable then
                title = (curveMode and "Remove point " or "Release the anchor of point ") .. hovered.index
                titleColor = handleColors.pointRemove
            elseif altDown then
                title = curveMode and "A curve keeps at least 2 points" or "The ends stay anchored"
            else
                title = "Point " .. hovered.index
            end
            text = curveMode and "Drag: move\nAlt+click: remove the point" or "Drag: move\nAlt+click: release the anchor"
        end
        drawHint(drawList, mouseX, mouseY, title, text, titleColor)
    elseif interactive and altDown and curveMode then
        local title, titleColor = "No surface under the cursor", nil
        if insertion then
            title = insertion.index and "Insert a point on the curve" or (insertion.atStart and "Add a point at the start" or "Add a point at the end")
            titleColor = handleColors.pointInsert
        end
        drawHint(drawList, mouseX, mouseY, title, "Alt+click on the curve: insert a point\nAlt+click elsewhere: add a point at the end\nAlt+Ctrl+click: add a point at the start", titleColor)
    end

    if interactive then
        editor.handleCapture.hovered = editor.handleCapture.hovered or hovered ~= nil or (altDown and curveMode)
    end
    editor.handleCapture.dragging = editor.handleCapture.dragging or self._handleDrag ~= nil
end

--- Shape tools --------------------------------------------------------------------------------

local SNAP_END_RANGE = 30
local toolShapeOptions = { "Arc", "S-Curve", "Ramp", "Helix", "Catenary" }

local function composeLocal(origin, f, l, u, a, b, c)
    return {
        x = origin.x + f.x * a + l.x * b + u.x * c,
        y = origin.y + f.y * a + l.y * b + u.y * c,
        z = origin.z + f.z * a + l.z * b + u.z * c
    }
end

---Arc (or helix with `height`) in the plane of `f` and `l`, starting at `origin` along `f`.
---Positive angles turn towards `l`. Segments of at most 90 degrees keep the Bezier fit tight.
local function generateArc(origin, f, l, u, radius, angleDegrees, height, roll)
    local total = math.rad(math.abs(angleDegrees))
    local sign = angleDegrees >= 0 and 1 or -1
    local count = math.max(1, math.ceil(total / (math.pi / 2) - 0.000001))
    local step = total / count
    local rate = total > 0 and height / total or 0
    local handle = 4 / 3 * math.tan(step / 4) * math.sqrt(radius * radius + rate * rate)
    local points = {}

    for index = 0, count do
        local a = index * step
        local position = composeLocal(origin, f, l, u, radius * math.sin(a), sign * radius * (1 - math.cos(a)), rate * a)
        local dir = normalizeDirection(composeLocal({ x = 0, y = 0, z = 0 }, f, l, u, radius * math.cos(a), sign * radius * math.sin(a), rate))
        table.insert(points, { x = position.x, y = position.y, z = position.z, roll = roll, dir = dir, lenIn = handle, lenOut = handle })
    end

    return points
end

---Two points with parallel tangents: an S-curve sideways (`side`) or a ramp upwards (`rise`).
local function generateOffsetCurve(origin, f, l, u, forward, side, rise, roll)
    local finish = composeLocal(origin, f, l, u, forward, side, rise)
    return {
        { x = origin.x, y = origin.y, z = origin.z, roll = roll, dir = { x = f.x, y = f.y, z = f.z }, lenIn = forward / 2, lenOut = forward / 2 },
        { x = finish.x, y = finish.y, z = finish.z, roll = roll, dir = { x = f.x, y = f.y, z = f.z }, lenIn = forward / 2, lenOut = forward / 2 }
    }
end

---@return number
local function curvePointsLength(points)
    local _, total = sampleCurveSegments(buildCurveSegments(points, false))
    return total
end

---Start of the current curve: first point, horizontal heading, its left and up.
---@return table origin
---@return table f
---@return table l
---@return table u
---@return number roll
function bendedMesh:getToolBase()
    self:ensureCurvePoints()
    local first = self.curvePoints[1]
    local dir = self:getCurveTangents()[1].dir
    local f = normalizeDirection({ x = dir.x, y = dir.y, z = 0 })
    if isDirectionZero(f) then
        f = { x = 0, y = 1, z = 0 }
    end

    return { x = first.x, y = first.y, z = first.z }, f, { x = -f.y, y = f.x, z = 0 }, { x = 0, y = 0, z = 1 }, first.roll or 0
end

---Rest length of the mesh, or the curve's when the rig is unknown.
---@return number
function bendedMesh:getToolLength()
    local count = self:getMeshBonesQuantity()
    local distances = count and self:getRestDistancesFor(count) or nil
    if distances and distances[#distances] > 0.001 and (bendedRig.get(self.spawnData) or self:getRestPoints()) then
        return distances[#distances]
    end

    return (self:getCurveLength())
end

---Replaces the curve and refreshes everything that depends on it. One history entry.
---@param points table[]
function bendedMesh:applyToolCurve(points)
    history.addAction(history.getElementChange(self.object))
    if not self:isCurveMode() then
        self:setPathMode(PATH_MODE_CURVE)
    end

    self.curvePoints = {}
    for _, point in ipairs(points) do
        table.insert(self.curvePoints, copyCurvePoint(point))
    end
    self._curveKey = nil
    self:refreshAfterTool()
end

function bendedMesh:refreshAfterTool()
    self._curveKey = nil
    self:ensurePathPoints()
    self:autoFitDeformedBox()
    self:refreshArrowScale()
end

---Builds the selected shape from the tool settings.
---@return table[]? points
function bendedMesh:generateToolShape()
    local tool = self:getToolSettings()
    local origin, f, l, u, roll = self:getToolBase()
    local length = tool.length or self:getToolLength()

    if tool.shape == 1 or tool.shape == 4 then
        local height = tool.shape == 4 and tool.height or 0
        local angle = tool.angle
        length = self:getToolLength()
        if tool.matchLength and tool.radius > 0.001 then
            local flat = math.sqrt(math.max(0, length * length - height * height))
            angle = (angle >= 0 and 1 or -1) * math.deg(flat / tool.radius)
        end
        return generateArc(origin, f, l, u, tool.radius, angle, height, roll)
    end

    if tool.shape == 2 or tool.shape == 3 then
        local side = tool.shape == 2 and tool.offset or 0
        local rise = tool.shape == 3 and tool.height or 0

        -- Forward run whose curve is `length` long.
        local low, high = 0, length
        for _ = 1, 40 do
            local middle = (low + high) / 2
            if curvePointsLength(generateOffsetCurve(origin, f, l, u, middle, side, rise, roll)) < length then
                low = middle
            else
                high = middle
            end
        end
        return generateOffsetCurve(origin, f, l, u, math.max(0.01, (low + high) / 2), side, rise, roll)
    end

    if tool.shape == 5 then
        -- Parabolic sag between the current ends; a cubic per quarter reproduces it exactly.
        local a, b = self.curvePoints[1], self.curvePoints[#self.curvePoints]
        local points = {}
        for index = 0, 4 do
            local t = index / 4
            local position = {
                x = a.x + (b.x - a.x) * t,
                y = a.y + (b.y - a.y) * t,
                z = a.z + (b.z - a.z) * t - 4 * tool.sag * t * (1 - t)
            }
            local derivative = { x = b.x - a.x, y = b.y - a.y, z = (b.z - a.z) - 4 * tool.sag * (1 - 2 * t) }
            local handle = length3(derivative) * 0.25 / 3
            table.insert(points, {
                x = position.x, y = position.y, z = position.z,
                roll = (a.roll or 0) + ((b.roll or 0) - (a.roll or 0)) * t,
                dir = normalizeDirection(derivative), lenIn = handle, lenOut = handle
            })
        end
        return points
    end

    return nil
end

---Banks each control point into its turn: inside down, `maxBank` at `fullRadius` or tighter.
---@param maxBank number Degrees.
---@param fullRadius number Meters.
function bendedMesh:applyAutoBank(maxBank, fullRadius)
    history.addAction(history.getElementChange(self.object))
    local tangents = self:getCurveTangents()
    local count = #self.curvePoints

    for index, point in ipairs(self.curvePoints) do
        local before = math.max(1, index - 1)
        local after = math.min(count, index + 1)
        local a, b = tangents[before].dir, tangents[after].dir
        local turn = math.atan2(a.x * b.y - a.y * b.x, a.x * b.x + a.y * b.y)
        local pa, pb = self.curvePoints[before], self.curvePoints[after]
        local distance = length3({ x = pb.x - pa.x, y = pb.y - pa.y, z = 0 })
        local curvature = distance > 0.001 and turn / distance or 0
        local bank = maxBank * math.min(1, math.abs(curvature) * fullRadius)
        -- Positive roll lowers the right side, so a left turn (positive) banks negative.
        point.roll = curvature > 0 and -bank or bank
    end

    self:refreshAfterTool()
end

---Resamples the curve every `spacing` meters and drops each point onto the ground below it.
---@param spacing number
---@param offset number Height above the ground.
---@return boolean
function bendedMesh:drapeOnGround(spacing, offset)
    local editor = require("modules/utils/editor/editor")
    if not editor.interface then
        ImGui.ShowToast(ImGui.Toast.new(ImGui.ToastType.Warning, 3000, "Ground raycast is not ready yet; move the player once and try again."))
        return false
    end

    -- The ground below must not be the mesh's own collision.
    bendedCollisionPreview.withoutCollision(self, function ()
        self:drapeOnGroundNow(editor, spacing, offset)
    end)
    return true
end

---@param editor table
---@param spacing number
---@param offset number
function bendedMesh:drapeOnGroundNow(editor, spacing, offset)
    local looped = self.pathLooped and #self.curvePoints > 2
    local segments = buildCurveSegments(self.curvePoints, looped)
    local samples, total = sampleCurveSegments(segments)
    local count = math.max(1, math.floor(total / math.max(0.5, spacing) + 0.5))
    local points = {}
    local missed = 0

    for index = 0, count do
        if not (looped and index == count) then
            local position, _, roll = evaluateCurveAt(segments, samples, total, total * index / count)
            local world = self:getWorldPointFromLocal(position)
            local result = editor.interface:RaycastWithASingleGroup(
                Vector4.new(world.x, world.y, world.z + 50, 1),
                Vector4.new(world.x, world.y, world.z - 200, 1),
                "PlayerBlocker"
            )

            if result and result:IsValid() then
                world = { x = world.x, y = world.y, z = result.position.z + offset }
                position = self:worldToLocalPoint(world)
            else
                missed = missed + 1
            end
            table.insert(points, { x = position.x, y = position.y, z = position.z, roll = roll })
        end
    end

    self:applyToolCurve(points)
    if missed > 0 then
        ImGui.ShowToast(ImGui.Toast.new(ImGui.ToastType.Warning, 3000, string.format("%d point(s) found no ground below and kept their height.", missed)))
    end
end

---Puts control point `index` on another mesh's end, with its tangent and bank, so the two meet
---smoothly. Start meets an end and end meets a start head-on; like ends face each other.
---@param index integer
---@param target table `{ frame, isStart }` from `collectOtherEnds`.
function bendedMesh:joinPointToEnd(index, target)
    local frame = target.frame
    local atStart = index == 1
    local s = (atStart == target.isStart) and -1 or 1

    local position = self:worldToLocalPoint(frame.position)
    local forward = self:worldDirectionToLocal(frame.position, { x = s * frame.forward.x, y = s * frame.forward.y, z = s * frame.forward.z })
    local right = self:worldDirectionToLocal(frame.position, { x = s * frame.right.x, y = s * frame.right.y, z = s * frame.right.z })
    local up = self:worldDirectionToLocal(frame.position, frame.up)
    local roll = bendedMesh.pathPointsFromMatrices({ { X = right, Y = forward, Z = up, W = position } }, self.pathUpAxis)[1].roll

    local point = self.curvePoints[index]
    point.x, point.y, point.z = position.x, position.y, position.z
    point.dir = forward
    point.roll = roll
end

---Nearest other mesh end or intersection port within `SNAP_END_RANGE` of one end of this curve.
---@param atStart boolean
---@return table? target `{ frame, isStart, name }` from `collectOtherEnds`
---@return table position World position of this curve's end.
function bendedMesh:findSnapTarget(atStart)
    local mine = self:getWorldPointFromLocal(self.curvePoints[atStart and 1 or #self.curvePoints])
    local best, bestDistance = nil, SNAP_END_RANGE

    for _, other in ipairs(self:collectOtherEnds()) do
        local p = other.frame.position
        local distance = length3({ x = p.x - mine.x, y = p.y - mine.y, z = p.z - mine.z })
        if distance < bestDistance then
            best, bestDistance = other, distance
        end
    end

    return best, mine
end

---Joins one end of this curve to the nearest end of another bended mesh, position and tangent.
---@param atStart boolean
---@param options table? `{ quiet, noHistory }`
---@return boolean
function bendedMesh:snapEndToNearest(atStart, options)
    options = options or {}
    local index = atStart and 1 or #self.curvePoints
    local best = self:findSnapTarget(atStart)

    if not best then
        if options.quiet then return false end
        ImGui.ShowToast(ImGui.Toast.new(ImGui.ToastType.Warning, 3000, string.format("No bended mesh end or intersection port within %d m.", SNAP_END_RANGE)))
        return false
    end

    if not options.noHistory then
        history.addAction(history.getElementChange(self.object))
    end
    self:joinPointToEnd(index, best)
    self:refreshAfterTool()

    if options.quiet then return true end
    ImGui.ShowToast(ImGui.Toast.new(ImGui.ToastType.Success, 2500, "Joined to " .. tostring(best.name)))
    return true
end

---Marks the end a Snap button moves, the end or port it joins, and a line between them.
---@param screen table
---@param drawList table
---@param atStart boolean
function bendedMesh:drawSnapIndicator(screen, drawList, atStart)
    if not self.curvePoints or #self.curvePoints == 0 then return end
    local target, mine = self:findSnapTarget(atStart)
    local from = Vector4.new(mine.x, mine.y, mine.z, 1)
    local to = target and Vector4.new(target.frame.position.x, target.frame.position.y, target.frame.position.z, 1)

    if to then
        projectedWireframe.drawWorldLine(drawList, screen, from, to, { color = 0xC8000000, thickness = 5 })
        projectedWireframe.drawWorldLine(drawList, screen, from, to, { color = handleColors.pointJoined, thickness = 3 })
    end

    local function marker(world, color, title, text)
        local projected = projectedWireframe.projectWorldPoint(screen, world)
        if not projected or projected.behind then return end
        ImGui.ImDrawListAddCircle(drawList, projected.x, projected.y, HANDLE_POINT_RADIUS + 6, 0xC8000000, -1, 4)
        ImGui.ImDrawListAddCircle(drawList, projected.x, projected.y, HANDLE_POINT_RADIUS + 6, color, -1, 2)
        ImGui.ImDrawListAddCircleFilled(drawList, projected.x, projected.y, HANDLE_POINT_RADIUS - 1, color, -1)
        drawHint(drawList, projected.x, projected.y, title, text, color)
    end

    local title = atStart and "Start" or "End"
    if not to then
        marker(from, handleColors.pointActive, title, string.format("No bended mesh end or intersection port within %d m.", SNAP_END_RANGE))
        return
    end
    local distance = length3({ x = to.x - from.x, y = to.y - from.y, z = to.z - from.z })
    marker(from, handleColors.pointActive, title, string.format("Moves %.2f m to join this point.", distance))
    marker(to, handleColors.pointJoined, tostring(target.name), target.port and "Road port" or (target.isStart and "Start" or "End"))
end

---Runs the path the other way round, keeping its shape and bank.
function bendedMesh:reversePath()
    history.addAction(history.getElementChange(self.object))

    if self:isCurveMode() then
        local reversed = {}
        for index = #self.curvePoints, 1, -1 do
            local point = self.curvePoints[index]
            local copy = { x = point.x, y = point.y, z = point.z, roll = -(point.roll or 0) }
            if point.dir then
                copy.dir = { x = -point.dir.x, y = -point.dir.y, z = -point.dir.z }
                copy.lenIn, copy.lenOut = point.lenOut, point.lenIn
            end
            table.insert(reversed, copy)
        end
        self.curvePoints = reversed
    else
        self:ensurePathPoints()
        local reversed = {}
        for index = #self.pathPoints, 1, -1 do
            local point = self.pathPoints[index]
            table.insert(reversed, { x = point.x, y = point.y, z = point.z, roll = -(point.roll or 0), anchored = point.anchored })
        end
        self.pathPoints = reversed
    end

    self:refreshAfterTool()
end

---Mirrors the path across the mesh's local Y/Z plane.
function bendedMesh:mirrorPath()
    history.addAction(history.getElementChange(self.object))

    local points = self:isCurveMode() and self.curvePoints or self.pathPoints
    for _, point in ipairs(points) do
        point.x = -point.x
        point.roll = -(point.roll or 0)
        if point.dir then
            point.dir = { x = -point.dir.x, y = point.dir.y, z = point.dir.z }
        end
    end

    self:refreshAfterTool()
end

---Moves the node's origin onto the first point without moving the mesh.
function bendedMesh:recenterPivot()
    local points = self:isCurveMode() and self.curvePoints or self.pathPoints
    local first = points[1]
    if not first then return end

    history.addAction(history.getElementChange(self.object))
    local world = self:getWorldPointFromLocal(first)
    local offset = { x = first.x, y = first.y, z = first.z }
    for _, point in ipairs(points) do
        point.x, point.y, point.z = point.x - offset.x, point.y - offset.y, point.z - offset.z
    end

    self.object:setPosition(Vector4.new(world.x, world.y, world.z, 0))
    self:refreshAfterTool()
end

---Keeps only the node's yaw; its pitch and roll move into the curve, so `World Z` is up again.
---@return boolean
function bendedMesh:bakeRotation()
    if math.abs(self.rotation.pitch or 0) < 0.0001 and math.abs(self.rotation.roll or 0) < 0.0001 then
        ImGui.ShowToast(ImGui.Toast.new(ImGui.ToastType.Info, 2500, "The mesh only has a yaw already."))
        return false
    end

    history.addAction(history.getElementChange(self.object))
    local yaw = self.rotation.yaw or 0
    local scale = self.scale or { x = 1, y = 1, z = 1 }
    local frames = self:getCurveFrames()
    local matrices = {}

    for index, frame in ipairs(frames) do
        local world = self:pathFrameToWorld(frame)
        local offset = rotateYaw({ x = world.position.x - self.position.x, y = world.position.y - self.position.y, z = world.position.z - self.position.z }, -yaw)
        matrices[index] = {
            X = rotateYaw(world.right, -yaw),
            Y = rotateYaw(world.forward, -yaw),
            Z = rotateYaw(world.up, -yaw),
            W = { x = offset.x / scale.x, y = offset.y / scale.y, z = offset.z / scale.z }
        }
    end

    local rebuilt = bendedMesh.pathPointsFromMatrices(matrices, self.pathUpAxis)
    for index, point in ipairs(self.curvePoints) do
        local new = rebuilt[index]
        point.x, point.y, point.z, point.roll = new.x, new.y, new.z, new.roll
        if point.dir then
            local d = matrices[index].Y
            point.dir = normalizeDirection({ x = d.x / scale.x, y = d.y / scale.y, z = d.z / scale.z })
        end
    end

    self.object:setRotation(EulerAngles.new(0, 0, yaw))
    self:refreshAfterTool()
    return true
end

--- Chains and joined ends ----------------------------------------------------------------------

local MAGNET_RANGE = 2
local JOINED_END_TOLERANCE = 0.02
local POINT_SNAP_PIXELS = 18

local function lerpPoint(a, b, t)
    return { x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t, z = a.z + (b.z - a.z) * t }
end

---De Casteljau split of a cubic at `t`.
---@return table left `{ p0, p1, p2, p3 }`
---@return table right
local function splitCubic(p0, p1, p2, p3, t)
    local a, b, c = lerpPoint(p0, p1, t), lerpPoint(p1, p2, t), lerpPoint(p2, p3, t)
    local d, e = lerpPoint(a, b, t), lerpPoint(b, c, t)
    local f = lerpPoint(d, e, t)
    return { p0, a, d, f }, { f, e, c, p3 }
end

---Control points of `segment` restricted to `[ta, tb]`.
local function subSegment(segment, ta, tb)
    local _, right = splitCubic(segment.p0, segment.c0, segment.c1, segment.p1, ta)
    local u = (1 - ta) > 0.000001 and (tb - ta) / (1 - ta) or 0
    local left = splitCubic(right[1], right[2], right[3], right[4], u)
    return left
end

---Curve points reproducing exactly the stretch of curve between arc lengths `s0` and `s1`.
---Every point gets a manual tangent, so the piece keeps its shape whatever its neighbours do.
local function extractCurveRange(segments, samples, total, s0, s1)
    local first, t0 = locateCurve(samples, total, s0)
    local last, t1 = locateCurve(samples, total, s1)
    if t1 <= 0.000001 and last > first then
        last, t1 = last - 1, 1
    end

    local points = {}
    for index = first, last do
        local segment = segments[index]
        local ta = index == first and t0 or 0
        local tb = index == last and t1 or 1

        if tb - ta > 0.000001 then
            local q = subSegment(segment, ta, tb)
            local outHandle = subtract(q[2], q[1])
            local inHandle = subtract(q[4], q[3])

            if #points == 0 then
                table.insert(points, {
                    x = q[1].x, y = q[1].y, z = q[1].z,
                    roll = segment.r0 + (segment.r1 - segment.r0) * smoothstep(ta),
                    dir = normalizeDirection(outHandle), lenIn = length3(outHandle), lenOut = length3(outHandle)
                })
            else
                points[#points].lenOut = length3(outHandle)
            end

            local lastDir = normalizeDirection(inHandle)
            if isDirectionZero(lastDir) then
                lastDir = normalizeDirection(subtract(q[4], q[1]))
            end
            table.insert(points, {
                x = q[4].x, y = q[4].y, z = q[4].z,
                roll = segment.r0 + (segment.r1 - segment.r0) * smoothstep(tb),
                dir = lastDir, lenIn = length3(inHandle), lenOut = length3(inHandle)
            })
        end
    end

    for _, point in ipairs(points) do
        if isDirectionZero(point.dir) then
            point.dir = nil
            point.lenIn, point.lenOut = nil, nil
        end
    end

    return points
end

---World direction of a mesh-space direction leaving mesh-space point `p`.
function bendedMesh:localDirectionToWorld(p, dir)
    local a = self:getWorldPointFromLocal(p)
    local b = self:getWorldPointFromLocal({ x = p.x + dir.x, y = p.y + dir.y, z = p.z + dir.z })
    return normalizeDirection({ x = b.x - a.x, y = b.y - a.y, z = b.z - a.z })
end

---Mesh-space direction of a world direction leaving world point `world`.
function bendedMesh:worldDirectionToLocal(world, dir)
    local a = self:worldToLocalPoint(world)
    local b = self:worldToLocalPoint({ x = world.x + dir.x, y = world.y + dir.y, z = world.z + dir.z })
    return normalizeDirection({ x = b.x - a.x, y = b.y - a.y, z = b.z - a.z })
end

---Ends of every other bended mesh in the scene, and the road ports of placed intersections, in world space.
---@return table[] ends `{ mesh, name, isStart, frame, port? }`
function bendedMesh:collectOtherEnds()
    local ends = {}
    local sUI = self.object and self.object.sUI
    if not sUI then return ends end
    sUI.ensureCache()

    for _, entry in ipairs(sUI.paths) do
        local other = entry.ref and entry.ref.spawnable
        if other and other ~= self and other.modulePath == self.modulePath and other.getSampledPathFrames
            and entry.ref.visible ~= false and not (entry.ref.isLocked and entry.ref:isLocked()) then
            local frames = other:getSampledPathFrames()
            table.insert(ends, { mesh = other, name = entry.ref.name, isStart = true, frame = other:pathFrameToWorld(frames[1]) })
            table.insert(ends, { mesh = other, name = entry.ref.name, isStart = false, frame = other:pathFrameToWorld(frames[#frames]) })
        elseif other and other.getPortEnds and entry.ref.visible ~= false then
            for _, port in ipairs(other:getPortEnds()) do
                table.insert(ends, port)
            end
        end
    end

    return ends
end

---Points a dragged control point can snap onto: other bended meshes' ends and Curve mode control
---points, intersection road ports, and this curve's other end. Meshes in `excluded` are skipped.
---@param excluded table<table, boolean>?
---@param dragIndex integer? Dragged control point: an end also snaps onto this curve's other end.
---@return table[] candidates `{ position, name, frame?, isStart?, ownEnd? }`; `frame` is set on ends and ports.
function bendedMesh:collectPointSnapCandidates(excluded, dragIndex)
    local candidates = {}

    for _, other in ipairs(self:collectOtherEnds()) do
        if not (excluded and excluded[other.mesh]) then
            table.insert(candidates, { position = other.frame.position, frame = other.frame, isStart = other.isStart, name = other.name })
        end
    end

    local sUI = self.object and self.object.sUI
    for _, entry in ipairs(sUI and sUI.paths or {}) do
        local other = entry.ref and entry.ref.spawnable
        if other and other ~= self and other.modulePath == self.modulePath and other.isCurveMode and other:isCurveMode()
            and not (excluded and excluded[other]) then
            for index, point in ipairs(other.curvePoints or {}) do
                if index > 1 and index < #other.curvePoints then
                    local world = other:getWorldPointFromLocal(point)
                    table.insert(candidates, { position = { x = world.x, y = world.y, z = world.z }, name = entry.ref.name })
                end
            end
        end
    end

    local opposite = dragIndex and self:getOppositeEnd(dragIndex)
    if opposite and not (excluded and excluded[self]) then
        local world = self:getWorldPointFromLocal(self.curvePoints[opposite])
        table.insert(candidates, {
            position = { x = world.x, y = world.y, z = world.z },
            ownEnd = opposite,
            name = opposite == 1 and "the start of this mesh" or "the end of this mesh"
        })
    end

    return candidates
end

---Nearest snap candidate under the cursor.
---@param screen table
---@param mouseX number
---@param mouseY number
---@param candidates table[] From `collectPointSnapCandidates`.
---@return table? snap
function bendedMesh.findPointSnap(screen, mouseX, mouseY, candidates)
    local best, bestDistance = nil, POINT_SNAP_PIXELS

    for _, candidate in ipairs(candidates) do
        local position = candidate.position
        local projected = projectedWireframe.projectWorldPoint(screen, Vector4.new(position.x, position.y, position.z, 1))
        if projected and not projected.behind then
            local distance = math.sqrt((projected.x - mouseX) ^ 2 + (projected.y - mouseY) ^ 2)
            if distance < bestDistance then
                best, bestDistance = candidate, distance
            end
        end
    end

    return best
end

---Other end of an open curve of at least 3 points, when `index` is an end. Both ends can be joined.
---@param index integer
---@return integer?
function bendedMesh:getOppositeEnd(index)
    local count = #self.curvePoints
    if not self:isCurveMode() or self.pathLooped or count < 3 then return nil end
    if index == 1 then return count end
    if index == count then return 1 end
    return nil
end

---Joins end `index` onto the other end of this curve: same position and bank, one shared tangent.
---@param index integer
function bendedMesh:joinOwnEnds(index)
    local opposite = self:getOppositeEnd(index)
    if not opposite then return end

    local point, target = self.curvePoints[index], self.curvePoints[opposite]
    local first, last = self.curvePoints[1], self.curvePoints[#self.curvePoints]
    local dir = target.dir
    if not dir then
        -- Same tangent as a looped curve would get at the seam.
        local previous, nextPoint = self.curvePoints[#self.curvePoints - 1], self.curvePoints[2]
        local a = subtract(last, previous)
        local b = subtract(nextPoint, first)
        local la, lb = length3(a), length3(b)
        if la < 0.000001 or lb < 0.000001 then return end
        dir = normalizeDirection({ x = a.x / la + b.x / lb, y = a.y / la + b.y / lb, z = a.z / la + b.z / lb })
        if isDirectionZero(dir) then return end
    end

    point.x, point.y, point.z = target.x, target.y, target.z
    point.roll = target.roll
    point.dir = { x = dir.x, y = dir.y, z = dir.z }
    target.dir = { x = dir.x, y = dir.y, z = dir.z }
end

---Curve-mode meshes whose first or last control point sits on control point `index` of this one.
---@param index integer
---@return table[] partners `{ mesh, index, flip }`
function bendedMesh:findJoinedEnds(index)
    if not self:isCurveMode() or self.linkJoinedEnds == false then return {} end
    if index ~= 1 and index ~= #self.curvePoints then return {} end

    local world = self:getWorldPointFromLocal(self.curvePoints[index])
    local partners = {}

    -- Both ends of this curve joined together: they continue each other.
    local opposite = self:getOppositeEnd(index)
    if opposite then
        local p = self:getWorldPointFromLocal(self.curvePoints[opposite])
        if length3({ x = p.x - world.x, y = p.y - world.y, z = p.z - world.z }) < JOINED_END_TOLERANCE then
            table.insert(partners, { mesh = self, element = self.object, index = opposite, flip = false })
        end
    end

    local sUI = self.object and self.object.sUI
    if not sUI then return partners end
    sUI.ensureCache()

    for _, entry in ipairs(sUI.paths) do
        local other = entry.ref and entry.ref.spawnable
        if other and other ~= self and other.modulePath == self.modulePath and other.isCurveMode and other:isCurveMode()
            and not (entry.ref.isLocked and entry.ref:isLocked()) then
            other:ensureCurvePoints()
            for _, otherIndex in ipairs({ 1, #other.curvePoints }) do
                local p = other:getWorldPointFromLocal(other.curvePoints[otherIndex])
                if length3({ x = p.x - world.x, y = p.y - world.y, z = p.z - world.z }) < JOINED_END_TOLERANCE then
                    -- Like ends (start on start, end on end) face each other.
                    table.insert(partners, { mesh = other, element = entry.ref, index = otherIndex, flip = (index == 1) == (otherIndex == 1) })
                end
            end
        end
    end

    return partners
end

---Carries control point `index` (position and tangent) over to the meshes joined there.
---@param index integer
---@param partners table[]
function bendedMesh:syncJoinedEnds(index, partners)
    if not partners or #partners == 0 then return end

    local point = self.curvePoints[index]
    local world = self:getWorldPointFromLocal(point)
    local worldDir = self:localDirectionToWorld(point, self:getCurveTangents()[index].dir)

    for _, partner in ipairs(partners) do
        local other = partner.mesh
        local target = other.curvePoints[partner.index]
        if target then
            local position = other:worldToLocalPoint(world)
            local s = partner.flip and -1 or 1
            target.x, target.y, target.z = position.x, position.y, position.z
            target.dir = other:worldDirectionToLocal(world, { x = s * worldDir.x, y = s * worldDir.y, z = s * worldDir.z })
            other:ensurePathPoints()
            other:updatePathVisualization()
        end
    end
end

---Cuts the curve into `count` meshes of this asset, each on its own stretch of the same curve.
---This mesh keeps the first stretch; the others are inserted after it.
---@param count integer
---@return boolean
function bendedMesh:splitIntoChain(count)
    if not self.object or not self.object.parent or self.object:isLocked() then return false end
    if not self:isCurveMode() then
        ImGui.ShowToast(ImGui.Toast.new(ImGui.ToastType.Warning, 3000, "Split into Chain works in Curve mode."))
        return false
    end
    if self.pathLooped then
        ImGui.ShowToast(ImGui.Toast.new(ImGui.ToastType.Warning, 3000, "A looped curve cannot be split into a chain.\nTurn Looped off and drag one end onto the other with Alt."))
        return false
    end

    count = math.max(2, math.floor(count))
    local segments = buildCurveSegments(self.curvePoints, false)
    local samples, total = sampleCurveSegments(segments)
    local pieces = {}
    for index = 1, count do
        pieces[index] = extractCurveRange(segments, samples, total, total * (index - 1) / count, total * index / count)
    end

    local change = history.getElementChange(self.object)
    local template = self.object:serialize()

    self.curvePoints = {}
    for _, point in ipairs(pieces[1]) do
        table.insert(self.curvePoints, copyCurvePoint(point))
    end
    self.pathLengthMode = LENGTH_MODE_FIT
    self:getToolSettings().chainCount = nil
    self:refreshAfterTool()

    local parent = self.object.parent
    local insertAt = utils.indexValue(parent.childs, self.object) + 1
    local name = self.object.name
    local created = {}

    for index = 2, count do
        local data = utils.deepcopy(template)
        local first = pieces[index][1]
        local world = self:getWorldPointFromLocal(first)
        local points = {}
        for _, point in ipairs(pieces[index]) do
            local copy = copyCurvePoint(point)
            copy.x, copy.y, copy.z = copy.x - first.x, copy.y - first.y, copy.z - first.z
            table.insert(points, copy)
        end

        name = utils.generateCopyName(name)
        data.name = name
        data.spawnable.position = { x = world.x, y = world.y, z = world.z, w = 0 }
        data.spawnable.nodeRef = ""
        data.spawnable.pathMode = PATH_MODE_CURVE
        data.spawnable.pathLengthMode = LENGTH_MODE_FIT
        data.spawnable.curvePoints = points
        data.spawnable.pathPoints = nil
        data.spawnable.deformedBox = nil
        data.spawnable.importedDeformation = nil

        local element = require("modules/classes/editor/spawnableElement"):new(self.object.sUI)
        element:load(data)
        element:setParent(parent, insertAt)
        insertAt = insertAt + 1
        table.insert(created, element)
    end

    history.addAction(history.getComposite({ change, history.getInsert(created) }))
    ImGui.ShowToast(ImGui.Toast.new(ImGui.ToastType.Success, 2500, string.format("Split into %d bended meshes", count)))
    return true
end

---Number of meshes that fit the curve with the least stretch.
---@return integer count
---@return number stretch Percent.
function bendedMesh:getAutoChainCount()
    local length = self._curveLength or self:getCurveLength()
    local rest = self:getToolLength()
    if rest <= 0.001 then return 1, 0 end

    local count = math.max(1, math.floor(length / rest + 0.5))
    return count, (length / (count * rest) - 1) * 100
end

---Hierarchy row badges: whether the collision is exported, curve needing a split.
---@return table[]
function bendedMesh:getExtraStateIcons()
    local icons = {}

    if bendedCollision.get(self.spawnData) then
        table.insert(icons, {
            icon = IconGlyphs.TextureBox,
            tooltip = self.exportCollision and "Collision included during export" or "Collision not included during export",
            color = self.exportCollision and style.mutedColor or style.warnColor
        })
    end

    local count = self:getSplitCount()
    if count > 1 then
        table.insert(icons, {
            icon = IconGlyphs.SetSplit,
            tooltip = string.format("This curve needs %d meshes.\nThe preview and the export already split it; use Split into Chain to edit the pieces.", count),
            color = style.mutedColor
        })
    end

    return icons
end

--- Magnetic ends while moving the mesh with the gizmo ----------------------------------------

---Puts the yaw back to what it was before the magnet turned the mesh.
function bendedMesh:releaseMagnet()
    if self._magnet and self.object then
        self.object:setRotation(EulerAngles.new(self.rotation.roll, self.rotation.pitch, self._magnet.yaw))
    end
    self._magnet = nil
end

---Called by the editor after each gizmo move: snaps an end onto a nearby bended mesh end.
function bendedMesh:onEditorMove()
    if self.magneticEnds == false or ImGui.IsKeyDown(ImGuiKey.LeftAlt) or ImGui.IsKeyDown(ImGuiKey.RightAlt) then
        self:releaseMagnet()
        return
    end

    local frames = self:getSampledPathFrames()
    local mine = { [true] = self:pathFrameToWorld(frames[1]), [false] = self:pathFrameToWorld(frames[#frames]) }
    local best, bestDistance = nil, MAGNET_RANGE

    for _, other in ipairs(self:collectOtherEnds()) do
        for _, atStart in ipairs({ true, false }) do
            local p, q = mine[atStart].position, other.frame.position
            local distance = length3({ x = p.x - q.x, y = p.y - q.y, z = p.z - q.z })
            if distance < bestDistance then
                best, bestDistance = { other = other, atStart = atStart }, distance
            end
        end
    end

    if not best then
        self:releaseMagnet()
        return
    end

    self._magnet = self._magnet or { yaw = self.rotation.yaw }
    local other = best.other
    local flip = best.atStart == other.isStart
    local s = flip and -1 or 1
    local desired = { x = s * other.frame.forward.x, y = s * other.frame.forward.y }
    local current = mine[best.atStart].forward

    local yawOnly = math.abs(self.rotation.pitch or 0) < 0.0001 and math.abs(self.rotation.roll or 0) < 0.0001
    if yawOnly and length3({ x = desired.x, y = desired.y, z = 0 }) > 0.001 and length3({ x = current.x, y = current.y, z = 0 }) > 0.001 then
        local turn = math.deg(math.atan2(desired.y, desired.x) - math.atan2(current.y, current.x))
        self.object:setRotation(EulerAngles.new(0, 0, (self.rotation.yaw or 0) + turn))
    end

    local joined = self:pathFrameToWorld(frames[best.atStart and 1 or #frames]).position
    local target = other.frame.position
    self.object:setPosition(Vector4.new(
        self.position.x + target.x - joined.x,
        self.position.y + target.y - joined.y,
        self.position.z + target.z - joined.z,
        0
    ))
    self._magnet.atStart = best.atStart
end

---Called by the editor once the move is recorded: matches the joined end's tangent and bank too.
function bendedMesh:onEditorMoveEnd()
    local magnet = self._magnet
    self._magnet = nil
    if magnet and magnet.atStart ~= nil and self:isCurveMode() then
        self:snapEndToNearest(magnet.atStart, { quiet = true, noHistory = true })
    end
end

function bendedMesh:onEditorMoveCancel()
    self._magnet = nil
end

---Transient settings of the tools panel.
---@return table
function bendedMesh:getToolSettings()
    if not self._toolSettings then
        self._toolSettings = {
            shape = 1, radius = 20, angle = 90, height = 4, offset = 4, sag = 1,
            matchLength = false, length = nil,
            maxBank = 6, fullBankRadius = 30,
            drapeSpacing = 6, drapeOffset = 0.05
        }
    end
    return self._toolSettings
end

local toolLabels = { "Shape", "Radius", "Angle", "Height", "Offset", "Length", "Sag", "Match Mesh Length", "Max Bank", "Full Bank Radius", "Spacing", "Height Offset" }

local function toolLabel(self, label)
    style.mutedText(label)
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.toolPropertyWidth)
end

local function toolFloat(self, label, id, value, speed, min, max, format, tooltip)
    toolLabel(self, label)
    ImGui.SetNextItemWidth(110 * style.viewSize)
    local newValue, changed = ImGui.DragFloat(id, value, speed, min, max, format)
    if tooltip then style.tooltip(tooltip) end
    return newValue, changed
end

---Pieces count and Split into Chain, highlighted while the curve needs more than one mesh.
function bendedMesh:drawSplitControls()
    local tool = self:getToolSettings()
    local locked = self.object and self.object:isLocked()
    local splitCount = self:getSplitCount()

    ImGui.BeginDisabled(not self:isCurveMode() or locked or self.pathLooped)
    local autoCount, autoStretch = self:getAutoChainCount()
    style.mutedText("Pieces")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    ImGui.SetNextItemWidth(110 * style.viewSize)
    local chainCount, changed = ImGui.DragInt("##toolChainCount", tool.chainCount or 0, 0.1, 0, 200, tool.chainCount and tool.chainCount > 0 and "%d" or "Auto")
    tool.chainCount = chainCount
    if changed then
        self:updatePathVisualization()
    end
    style.tooltip(string.format("How many meshes to cut the curve into.\nAuto picks the count that stretches the mesh least: %d (%+.1f%%).", autoCount, autoStretch))
    chainCount = (tool.chainCount and tool.chainCount > 0) and tool.chainCount or autoCount
    ImGui.SameLine()
    style.mutedText(string.format("%+.1f%%", (self:getCurveLength() / (chainCount * math.max(0.001, self:getToolLength())) - 1) * 100))
    style.tooltip("Stretch of each piece at this count.")

    local label = style.resolveActionLabelNoIconOnly(IconGlyphs.SetSplit, string.format("Split into Chain (%d)", chainCount), "bendedSplitIntoChain")
    local clicked
    if splitCount > 1 then
        clicked = style.warnButton(label)
    else
        clicked = ImGui.Button(label)
    end
    if clicked then
        self:splitIntoChain(chainCount)
    end
    style.tooltip((splitCount > 1 and string.format("This curve needs %d meshes. The preview and the export already split it.\n\n", splitCount) or "")
        .. "Cuts the curve into that many meshes of this asset, each on its own stretch of the same curve.\nThis mesh keeps the first stretch; the others are added right after it.\n\nDraw a long curve first (handles, Alt+click, shapes), then split it.\nFor a closed ring, turn Looped off and drag one end onto the other with Alt.", ImGuiHoveredFlags.AllowWhenDisabled)
    ImGui.EndDisabled()
end

function bendedMesh:drawShapeTools()
    if not ImGui.TreeNodeEx("Shape Tools", ImGuiTreeNodeFlags.SpanFullWidth) then
        return
    end

    -- One tree level deeper than the other properties, so the label column is measured here.
    if not self.toolPropertyWidth then
        self.toolPropertyWidth = math.max(self.maxPropertyWidth, utils.getTextMaxWidth(toolLabels) + 2 * ImGui.GetStyle().ItemSpacing.x + ImGui.GetCursorPosX())
    end

    local tool = self:getToolSettings()
    local curveMode = self:isCurveMode()
    local locked = self.object and self.object:isLocked()

    style.sectionHeaderStart("SHAPE")
    toolLabel(self, "Shape")
    ImGui.SetNextItemWidth(140 * style.viewSize)
    tool.shape = ImGui.Combo("##toolShape", tool.shape - 1, toolShapeOptions, #toolShapeOptions) + 1

    if tool.shape == 1 or tool.shape == 4 then
        tool.radius = math.max(0.1, (toolFloat(self, "Radius", "##toolRadius", tool.radius, 0.1, 0.1, 10000, "%.2f m")))
        ImGui.BeginDisabled(tool.matchLength)
        tool.angle = toolFloat(self, "Angle", "##toolAngle", tool.angle, 0.5, -1440, 1440, "%.1f deg", "Positive turns left, negative turns right.")
        ImGui.EndDisabled()
        if tool.shape == 4 then
            tool.height = toolFloat(self, "Height", "##toolHeight", tool.height, 0.05, -1000, 1000, "%.2f m", "Total rise over the turn.")
        end
        toolLabel(self, "Match Mesh Length")
        tool.matchLength = ImGui.Checkbox("##toolMatchLength", tool.matchLength)
        style.tooltip("Picks the angle so the curve is exactly as long as the mesh.\nThe sign of Angle still sets the turn side.")
    elseif tool.shape == 2 then
        tool.offset = toolFloat(self, "Offset", "##toolOffset", tool.offset, 0.05, -1000, 1000, "%.2f m", "Sideways shift at the end.\nPositive goes left.")
        local length, lengthChanged = toolFloat(self, "Length", "##toolLength", tool.length or self:getToolLength(), 0.1, 0.1, 10000, "%.2f m", "Curve length. Starts at the mesh length.")
        if lengthChanged then tool.length = length end
    elseif tool.shape == 3 then
        tool.height = toolFloat(self, "Height", "##toolHeight", tool.height, 0.05, -1000, 1000, "%.2f m", "Rise at the end, eased at both ends.")
        local length, lengthChanged = toolFloat(self, "Length", "##toolLength", tool.length or self:getToolLength(), 0.1, 0.1, 10000, "%.2f m", "Curve length. Starts at the mesh length.")
        if lengthChanged then tool.length = length end
    elseif tool.shape == 5 then
        tool.sag = toolFloat(self, "Sag", "##toolSag", tool.sag, 0.01, -1000, 1000, "%.2f m", "How far the middle hangs below the line between the two ends.\nThe ends stay where they are.")
    end

    ImGui.BeginDisabled(locked)
    if ImGui.Button("Apply Shape") then
        local points = self:generateToolShape()
        if points then
            self:applyToolCurve(points)
        end
    end
    ImGui.EndDisabled()
    style.tooltip(tool.shape == 5 and "Replaces the curve with a hanging cable between its two ends."
        or "Replaces the curve with this shape.\nIt starts at the first point and keeps its heading, so a joined mesh stays joined.")
    ImGui.SameLine()
    if ImGui.Button("Reset Length##toolResetLength") then
        tool.length = nil
    end
    style.tooltip("Set Length back to the mesh length.")
    style.sectionHeaderEnd()

    style.sectionHeaderStart("BANK")
    ImGui.BeginDisabled(not curveMode or locked)
    tool.maxBank = toolFloat(self, "Max Bank", "##toolMaxBank", tool.maxBank, 0.1, 0, 60, "%.1f deg", "Bank reached in turns at or tighter than Full Bank Radius.")
    tool.fullBankRadius = math.max(0.1, (toolFloat(self, "Full Bank Radius", "##toolFullBankRadius", tool.fullBankRadius, 0.5, 0.1, 10000, "%.1f m", "Turns this tight or tighter get the full bank.\nWider turns get proportionally less.")))
    if ImGui.Button("Auto Bank") then
        self:applyAutoBank(tool.maxBank, tool.fullBankRadius)
    end
    style.tooltip("Sets each point's roll from the turn around it, inside edge down.")
    ImGui.SameLine()
    if ImGui.Button("Clear Bank") then
        history.addAction(history.getElementChange(self.object))
        for _, point in ipairs(self.curvePoints) do point.roll = 0 end
        self:refreshAfterTool()
    end
    style.tooltip("Sets every point's roll back to 0.")
    ImGui.EndDisabled()
    style.sectionHeaderEnd()

    style.sectionHeaderStart("GROUND")
    ImGui.BeginDisabled(not curveMode or locked)
    tool.drapeSpacing = math.max(0.5, (toolFloat(self, "Spacing", "##toolDrapeSpacing", tool.drapeSpacing, 0.1, 0.5, 1000, "%.1f m", "Distance between the points the curve is rebuilt with.")))
    tool.drapeOffset = toolFloat(self, "Height Offset", "##toolDrapeOffset", tool.drapeOffset, 0.01, -100, 100, "%.2f m", "Height of each point above the ground.")
    if ImGui.Button("Drape on Ground") then
        self:drapeOnGround(tool.drapeSpacing, tool.drapeOffset)
    end
    style.tooltip("Rebuilds the curve with a point every Spacing meters,\nthen drops each one onto the ground below it.")
    ImGui.EndDisabled()
    style.sectionHeaderEnd()

    style.sectionHeaderStart("PATH")
    ImGui.BeginDisabled(not curveMode or locked)
    if ImGui.Button(style.resolveActionLabelNoIconOnly(IconGlyphs.SourceCommitStart, "Snap Start", "bendedSnapStart")) then
        self:snapEndToNearest(true)
    end
    if ImGui.IsItemHovered() then
        self._hoveredSnap = "start"
    end
    style.tooltip(string.format("Joins the first point to the nearest end of another bended mesh,\nor road port of a placed intersection, within %d m.\nPosition, tangent and bank are matched.", SNAP_END_RANGE))
    ImGui.SameLine()
    if ImGui.Button(style.resolveActionLabelNoIconOnly(IconGlyphs.SourceCommitEnd, "Snap End", "bendedSnapEnd")) then
        self:snapEndToNearest(false)
    end
    if ImGui.IsItemHovered() then
        self._hoveredSnap = "end"
    end
    style.tooltip(string.format("Joins the last point to the nearest end of another bended mesh,\nor road port of a placed intersection, within %d m.\nPosition, tangent and bank are matched.", SNAP_END_RANGE))
    ImGui.SameLine()
    if ImGui.Button("Bake Rotation") then
        self:bakeRotation()
    end
    style.tooltip("Keeps only the node's yaw and moves its pitch and roll into the curve,\nso World Z is the world's up again.")
    ImGui.EndDisabled()

    ImGui.BeginDisabled(locked)
    if ImGui.Button(style.resolveActionLabelNoIconOnly(IconGlyphs.SwapHorizontal, "Reverse", "bendedReverse")) then
        self:reversePath()
    end
    style.tooltip("Runs the path the other way round.")
    ImGui.SameLine()
    if ImGui.Button(style.resolveActionLabelNoIconOnly(IconGlyphs.Mirror, "Mirror", "bendedMirror")) then
        self:mirrorPath()
    end
    style.tooltip("Mirrors the path left to right.")
    ImGui.SameLine()
    if ImGui.Button("Recenter Pivot") then
        self:recenterPivot()
    end
    style.tooltip("Moves the node's origin onto the first point. The mesh does not move.")
    ImGui.EndDisabled()
    style.sectionHeaderEnd(true)

    if not curveMode then
        style.styledTextWrapped(IconGlyphs.InformationOutline .. "  Bank, ground, snap and bake work in Curve mode. A shape switches the mesh to Curve mode.", style.extraMutedColor)
    end

    ImGui.TreePop()
end

function bendedMesh:drawAppearanceSelector()
    local list = self.apps
    style.pushGreyedOut(#self.apps <= 1)

    if #list == 0 then
        list = { "No apps" }
    end

    style.mutedText("Appearance")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.appSearch = self.appSearch or ""
    local selectedApp = self.app
    if selectedApp == nil or selectedApp == "" then
        selectedApp = list[1] or "default"
    end

    local changed
    selectedApp, self.appSearch, changed = style.trackedSearchDropdown(
        "##bendedApp",
        "Search appearance...",
        selectedApp,
        self.appSearch,
        list,
        {
            element = self.object,
            width = 180,
            matchContentWidth = true,
            tooltip = "Select the mesh appearance"
        }
    )

    if changed and #self.apps > 0 then
        self.app = selectedApp
        self.appIndex = math.max(utils.indexValue(self.apps, self.app) - 1, 0)

        local entity = self:getEntity()
        if entity then
            local component = entity:FindComponentByName("mesh")
            if component then
                component.meshAppearance = CName.new(self.app)
                component:LoadAppearance()
                self:setOutline(self.outline)
            end
        end

        self:refreshDeformedPreview()
    end

    ImGui.SameLine()
    ImGui.BeginDisabled(#self.apps <= 1)
    style.pushButtonNoBG(true)
    if ImGui.Button(IconGlyphs.SkipPrevious .. "##cyclePreviousBendedAppearance") then
        self:cycleAppearance(-1)
    end
    style.tooltip("Select the previous mesh appearance.")
    ImGui.SameLine()
    if ImGui.Button(IconGlyphs.SkipNext .. "##cycleBendedAppearance") then
        self:cycleAppearance()
    end
    style.tooltip("Select the next mesh appearance.")
    style.pushButtonNoBG(false)
    ImGui.EndDisabled()
    style.popGreyedOut(#self.apps <= 1)
    ImGui.SameLine()
    style.pushButtonNoBG(true)
    if ImGui.Button(IconGlyphs.Reload .. "##reloadBendedAppearanceList") then
        self:reloadAppearances()
    end
    style.pushButtonNoBG(false)
    style.tooltip("Reload appearance list for this asset and refresh cached data.")
end

function bendedMesh:refreshArrowScale()
    local entity = self:getEntity()
    if not entity then return end

    visualizer.updateScale(entity, self:getArrowSize(), "arrows")
    self:setOutline(self.outline)
    self:updatePathVisualization()
end

---Marks the point of the row group just ended for the viewport, while it is hovered or edited.
---@param kind string `curve` or `bone`.
---@param index integer
function bendedMesh:trackHoveredRow(kind, index)
    if ImGui.IsItemHovered(ImGuiHoveredFlags.AllowWhenBlockedByActiveItem) or ImGui.IsItemActive() then
        self._hoveredPoint = { kind = kind, index = index }
    end
end

function bendedMesh:drawPathPointEditor(index, point, pointCount)
    local changedAny = false
    local anyAnchorChanged = false
    local changed
    local forcedAnchored = index == 1 or index == pointCount
    local anchored = forcedAnchored or point.anchored == true

    if forcedAnchored then
        point.anchored = true
        
        ImGui.BeginDisabled(true)
        style.pushStyleColor(true, ImGuiCol.Text, 0.25, 0.62, 0.97, 1.0)
        style.toggleButton(IconGlyphs.Anchor .. "##pathPointAnchor" .. tostring(index), anchored)
        style.popStyleColor(true)
        style.tooltip("First and last points are always anchored.")
        ImGui.EndDisabled()
    else
        style.pushStyleColor(anchored, ImGuiCol.Text, 0.25, 0.62, 0.97, 1.0)
        local nextAnchored, clicked = style.toggleButton(IconGlyphs.Anchor .. "##pathPointAnchor" .. tostring(index), anchored)
        style.popStyleColor(anchored)
        if clicked then
            history.addAction(history.getElementChange(self.object))
            point.anchored = nextAnchored == true
            anchored = point.anchored == true
            changedAny = true
            anyAnchorChanged = true
        end
        style.tooltip(anchored and "Anchored point" or "Non-anchored point")
    end

    ImGui.SameLine()
    ImGui.BeginDisabled(not anchored)

    point.x, changed, _ = field.advancedTrackedFloat(self.object, "##pathPointX" .. tostring(index), point.x, {suffix = " X", width = 60})
    changedAny = changedAny or changed
    ImGui.SameLine()
    point.y, changed, _ = field.advancedTrackedFloat(self.object, "##pathPointY" .. tostring(index), point.y, {suffix = " Y", width = 60})
    changedAny = changedAny or changed
    ImGui.SameLine()
    point.z, changed, _ = field.advancedTrackedFloat(self.object, "##pathPointZ" .. tostring(index), point.z, {suffix = " Z", width = 60})
    changedAny = changedAny or changed

    ImGui.SameLine()
    ImGui.Dummy(8 * style.viewSize, 0)
    ImGui.SameLine()
    point.roll, changed, _ = field.advancedTrackedFloat(self.object, "##pathPointRoll" .. tostring(index), point.roll, {suffix = " Roll"})
    changedAny = changedAny or changed
    style.tooltip("Roll in degrees around the local forward axis.")

    ImGui.SameLine()
    ImGui.Dummy(8 * style.viewSize, 0)
    ImGui.EndDisabled()

    return changedAny, anyAnchorChanged
end

function bendedMesh:drawPathVisualizationSettings()
    if not ImGui.TreeNodeEx("Visualization", ImGuiTreeNodeFlags.SpanFullWidth) then
        return false
    end

    self:ensurePathPoints()

    local changedAny = false
    local changed

    style.mutedText(style.resolveActionLabelNoIconOnly(IconGlyphs.TriangleWave, "Deformed Preview"))
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.deformedPreviewEnabled, changed = style.trackedCheckbox(self.object, "##deformedPreviewEnabled", self.deformedPreviewEnabled)
    changedAny = changedAny or changed
    style.tooltip("Show the real deformed mesh through a World Builder placeholder node.\nNeeds Codeware; otherwise the mesh stays undeformed.")

    if self.deformedPreviewEnabled and not self.isAssetPreview then
        local status = bendedPool.getStatus(self)
        ImGui.SameLine()

        if self.deformedPreviewIssue then
            style.mutedText(IconGlyphs.AlertOutline)
            style.tooltip(self.deformedPreviewIssue)
        elseif status == "active" then
            style.mutedText(IconGlyphs.CheckCircleOutline)
            local pieces = self.deformedPreviewPieces or 1
            style.tooltip(pieces > 1 and string.format("Deformed preview active, shown as the %d pieces Split into Chain would make.", pieces) or "Deformed preview active.")
        elseif status == "pending" then
            style.mutedText(IconGlyphs.TimerSandEmpty)
            style.tooltip(bendedPool.lastReason ~= "" and ("Waiting for a placeholder node.\n" .. bendedPool.lastReason) or "Waiting for a placeholder node.")
        else
            style.mutedText(IconGlyphs.AlertOutline)
            style.tooltip(bendedPool.lastReason ~= "" and bendedPool.lastReason or "Deformed preview unavailable; the mesh is shown undeformed.")
        end
    end

    style.mutedText(style.resolveActionLabelNoIconOnly(IconGlyphs.TextureBox, "Live Collision"))
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.liveCollisionEnabled, changed = style.trackedCheckbox(self.object, "##liveCollisionEnabled", self.liveCollisionEnabled)
    if changed then
        self:refreshCollisionPreview()
    end
    style.tooltip("Give the mesh real collision in the editor, following its deformation.\nRebuilt once the path stops changing.")

    if self.liveCollisionEnabled and not self.isAssetPreview then
        local status, count, issue = bendedCollisionPreview.getStatus(self)
        ImGui.SameLine()

        if status == "active" then
            style.mutedText(IconGlyphs.CheckCircleOutline)
            style.tooltip(string.format("Collision active: %d convex pieces.", count))
        elseif status == "pending" then
            style.mutedText(IconGlyphs.TimerSandEmpty)
            style.tooltip("Collision is rebuilt once the path stops changing.")
        elseif status == "none" then
            style.mutedText(IconGlyphs.AlertOutline)
            style.tooltip(issue or "No collision.")
        end
    end

    style.mutedText(style.resolveActionLabelNoIconOnly(IconGlyphs.EyeOutline, "Show Collision"))
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    ImGui.BeginDisabled(not self.liveCollisionEnabled)
    self.collisionShapeVisible, changed = style.trackedCheckbox(self.object, "##collisionShapeVisible", self.collisionShapeVisible)
    ImGui.EndDisabled()
    if changed then
        self:syncPreviewed()
        self:refreshCollisionPreview()
    end
    style.tooltip("Show the live collision as a hologram in the collider color (Settings > Colliders).\nUses bended preview placeholders: one per 251 triangles.\nAlso toggled by the visualization helper button in the hierarchy.")

    if self.collisionShapeVisible and self.liveCollisionEnabled and not self.isAssetPreview then
        local shown, total = bendedCollisionPreview.getVisualStatus(self)
        if total > 0 then
            ImGui.SameLine()
            if shown == total then
                style.mutedText(IconGlyphs.CheckCircleOutline)
                style.tooltip(string.format("Collision shown with %d placeholder(s).", total))
            else
                style.mutedText(IconGlyphs.TimerSandEmpty)
                style.tooltip(string.format("%d of %d placeholder(s) shown.\n%s", shown, total, bendedPool.lastReason ~= "" and bendedPool.lastReason or "Waiting for placeholder nodes."))
            end
        end
    end

    style.mutedText(style.resolveActionLabelNoIconOnly(IconGlyphs.VectorBezier, "Viewport Handles"))
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.viewportHandlesEnabled, changed = style.trackedCheckbox(self.object, "##viewportHandlesEnabled", self.viewportHandlesEnabled)
    style.tooltip("While the mesh is selected in editor mode, drag its points and tangents in the viewport.\n\nHold: Horizontal (X/Y, hold X or Y to lock an axis).\nShift / Z: vertical (Z).\nCtrl: snap to the surface under the cursor.\nAlt: detach linked ends, snap to nearby points and to this mesh's other end.\n\nAlt+click on a point: remove it.\nAlt+click on a tangent tip: back to automatic.\nAlt+click on the curve: insert a point.\nAlt+click elsewhere: add a point at the end.\nAlt+Ctrl+click: add a point at the start.")

    style.mutedText(style.resolveActionLabelNoIconOnly(IconGlyphs.Magnet, "Magnetic Ends"))
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.magneticEnds, changed = style.trackedCheckbox(self.object, "##magneticEnds", self.magneticEnds)
    style.tooltip("While the mesh is moved with the gizmo, an end that comes within " .. MAGNET_RANGE .. " m\nof another bended mesh's end, or of a placed intersection's road port,\nsnaps onto it and turns to follow it.\nOn release the joined tangent and bank are matched too.\n\nHold Alt while moving to place the mesh freely.")

    style.mutedText(style.resolveActionLabelNoIconOnly(IconGlyphs.LinkVariant, "Linked Ends"))
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.linkJoinedEnds, changed = style.trackedCheckbox(self.object, "##linkJoinedEnds", self.linkJoinedEnds)
    style.tooltip("Dragging a first or last point in the viewport also moves\nthe end of any bended mesh joined there, tangent included.\nJoined points are drawn in purple.\n\nHold Alt while dragging to detach the point from them.\nHold Alt on a free point to snap it onto nearby points.\nDrag one end onto the other with Alt to close the curve into a ring.")

    style.mutedText(style.resolveActionLabelNoIconOnly(IconGlyphs.MapMarkerMultipleOutline, "In-World Path Viz"))
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.pathPreviewEnabled, changed = style.trackedCheckbox(self.object, "##pathPreviewEnabled", self.pathPreviewEnabled)
    if changed then
        self:syncPreviewed()
    end
    changedAny = changedAny or changed
    style.tooltip("Show path overlays (points, segments, and local frames) in the world.\nAlso toggled by the visualization helper button in the hierarchy.")

    ImGui.TreePop()
    return changedAny
end

---Offset of a point row's fields from the row start: end icon, index and spacing.
---@param count integer Number of rows.
---@return number
local function pointFieldsOffset(count)
    local spacing = ImGui.GetStyle().ItemSpacing.x
    return ImGui.CalcTextSize(IconGlyphs.SourceCommitStart) + ImGui.CalcTextSize(tostring(count)) + 3 * spacing
end

---Row of one curve point: position, roll, tangent mode, insert and delete.
---@param fieldsX number Cursor X of the fields column.
---@return boolean changed
---@return boolean topologyChanged
function bendedMesh:drawCurvePointEditor(index, point, tangent, fieldsX)
    local changedAny = false
    local topologyChanged = false
    local changed
    local count = #self.curvePoints

    point.x, changed = field.advancedTrackedFloat(self.object, "##curvePointX", point.x, { suffix = " X", width = 60 })
    changedAny = changedAny or changed
    ImGui.SameLine()
    point.y, changed = field.advancedTrackedFloat(self.object, "##curvePointY", point.y, { suffix = " Y", width = 60 })
    changedAny = changedAny or changed
    ImGui.SameLine()
    point.z, changed = field.advancedTrackedFloat(self.object, "##curvePointZ", point.z, { suffix = " Z", width = 60 })
    changedAny = changedAny or changed

    ImGui.SameLine()
    ImGui.Dummy(8 * style.viewSize, 0)
    ImGui.SameLine()
    point.roll, changed = field.advancedTrackedFloat(self.object, "##curvePointRoll", point.roll or 0, { suffix = " Roll" })
    changedAny = changedAny or changed
    style.tooltip("Bank in degrees around the curve. Eased between points.")

    ImGui.SameLine()
    local manual = point.dir ~= nil
    style.pushStyleColor(manual, ImGuiCol.Text, 0.25, 0.62, 0.97, 1.0)
    local _, clicked = style.toggleButton(IconGlyphs.VectorBezier .. "##curveTangentMode", manual)
    style.popStyleColor(manual)
    style.tooltip(manual and "Manual tangent.\nClick to go back to an automatic one." or "Automatic tangent.\nClick to set heading, slope and handle lengths by hand.")
    if clicked then
        history.addAction(history.getElementChange(self.object))
        if manual then
            point.dir, point.lenIn, point.lenOut = nil, nil, nil
        else
            point.dir = { x = tangent.dir.x, y = tangent.dir.y, z = tangent.dir.z }
            point.lenIn, point.lenOut = tangent.lenIn, tangent.lenOut
        end
        changedAny = true
    end

    local looped = self.pathLooped and count > 2
    local canInsert = index < count or looped
    ImGui.SameLine()
    ImGui.BeginDisabled(not canInsert)
    if ImGui.Button(IconGlyphs.PlusCircleMultipleOutline) and canInsert then
        history.addAction(history.getElementChange(self.object))
        self:insertCurvePointAfter(index)
        changedAny, topologyChanged = true, true
    end
    ImGui.EndDisabled()
    style.tooltip("Insert a control point on the curve after this one.")

    ImGui.SameLine()
    ImGui.BeginDisabled(count <= 2)
    if style.dangerButton(IconGlyphs.DeleteOutline) and count > 2 then
        history.addAction(history.getElementChange(self.object))
        table.remove(self.curvePoints, index)
        changedAny, topologyChanged = true, true
    end
    ImGui.EndDisabled()
    style.tooltip("Remove this control point.")

    if point.dir and not topologyChanged then
        ImGui.SetCursorPosX(fieldsX)
        local heading, slope = directionToAngles(point.dir)
        local headingChanged, slopeChanged
        heading, headingChanged = field.advancedTrackedFloat(self.object, "##curvePointHeading", heading, { suffix = " Heading", width = 96, step = 0.1 })
        style.tooltip("Tangent direction around the mesh's up axis, in degrees.\n0 points along +Y, positive turns left.")
        ImGui.SameLine()
        slope, slopeChanged = field.advancedTrackedFloat(self.object, "##curvePointSlope", slope, { suffix = " Slope", width = 84, step = 0.1, min = -89.9, max = 89.9 })
        style.tooltip("Tangent slope in degrees.")
        if headingChanged or slopeChanged then
            point.dir = anglesToDirection(heading, slope)
            changedAny = true
        end

        ImGui.SameLine()
        ImGui.Dummy(8 * style.viewSize, 0)
        ImGui.SameLine()
        point.lenIn, changed = field.advancedTrackedFloat(self.object, "##curvePointLenIn", point.lenIn or tangent.lenIn, { suffix = " In", width = 60, min = 0 })
        changedAny = changedAny or changed
        style.tooltip("Length of the incoming handle.\nLonger keeps the direction further into the curve.")
        ImGui.SameLine()
        point.lenOut, changed = field.advancedTrackedFloat(self.object, "##curvePointLenOut", point.lenOut or tangent.lenOut, { suffix = " Out", width = 60, min = 0 })
        changedAny = changedAny or changed
        style.tooltip("Length of the outgoing handle.")
    end

    return changedAny, topologyChanged
end

function bendedMesh:drawCurveEditor()
    self:ensurePathPoints()

    local needsUpdate = false
    local topologyChanged = false
    local changed

    style.mutedText("Up Axis")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.pathUpAxis, changed = style.trackedCombo(self.object, "##pathUpAxis", self.pathUpAxis, pathUpAxisOptions, 160, {
        tooltip = "Reference axis for constructing local right/up basis from path direction"
    })
    needsUpdate = needsUpdate or changed

    style.mutedText("Loop Path")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.pathLooped, changed = style.trackedCheckbox(self.object, "##pathLooped", self.pathLooped)
    needsUpdate = needsUpdate or changed

    style.mutedText("Length Mode")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    local lengthIndex
    lengthIndex, changed = style.trackedCombo(self.object, "##pathLengthMode", self.pathLengthMode - 1, lengthModeOptions, 180, {
        tooltip = "Fit to Curve: the bones spread over the whole curve.\nThe mesh stretches to the curve's length.\n\nKeep Rest Length: the bones keep the mesh's own spacing from the start.\nThe mesh ends where its length runs out,\nor carries on straight past the last point."
    })
    if changed then
        self.pathLengthMode = math.max(1, math.min(math.floor(lengthIndex) + 1, #lengthModeOptions))
    end
    needsUpdate = needsUpdate or changed

    ImGui.Dummy(0, 8 * style.viewSize)
    local bones = self:getMeshBonesQuantity()
    style.mutedText("Mesh bones quantity : " .. (bones and tostring(bones) or "Unknown") .. " " .. IconGlyphs.Bone)
    style.tooltip("Bones are placed along the curve automatically.")

    local curveLength, restLength = self:getCurveLength()
    if restLength and restLength > 0.000001 then
        if self.pathLengthMode == LENGTH_MODE_KEEP and not self.pathLooped then
            style.mutedText(string.format("Length : curve %.2f m, mesh %.2f m", curveLength, restLength))
        else
            local stretch = (curveLength / restLength - 1) * 100
            local text = string.format("Length : %.2f m (base %.2f m, %+.1f%%)", curveLength, restLength, stretch)
            if math.abs(stretch) > 2 then
                style.styledText(IconGlyphs.AlertOutline .. " " .. text, 0xFF4CB8FF)
            else
                style.mutedText(text)
            end
        end
    else
        style.mutedText(string.format("Length : %.2f m", curveLength))
    end
    style.tooltip("Curve length in the mesh's own units (before scale).")

    if bendedRig.get(self.spawnData) and not self:getRig() then
        style.styledTextWrapped(IconGlyphs.AlertOutline .. "  This mesh's bones form a grid rather than a line, so a path cannot drive them correctly.", style.extraMutedColor)
    end

    local tangents = self:getCurveTangents()
    local fieldsX = ImGui.GetCursorPosX() + pointFieldsOffset(#self.curvePoints)
    for index, point in ipairs(self.curvePoints) do
        ImGui.PushID("curvePoint" .. index)
        ImGui.BeginGroup()

        if index == 1 then
            ImGui.Text(IconGlyphs.SourceCommitStart)
        elseif index == #self.curvePoints then
            ImGui.Text(IconGlyphs.SourceCommitEnd)
        else
            ImGui.Text(IconGlyphs.SourceCommit)
        end
        ImGui.SameLine()
        style.mutedText(tostring(index))
        ImGui.SameLine()
        ImGui.SetCursorPosX(fieldsX)

        local pointChanged, pointTopology = self:drawCurvePointEditor(index, point, tangents[index], fieldsX)
        needsUpdate = needsUpdate or pointChanged
        topologyChanged = topologyChanged or pointTopology

        ImGui.EndGroup()
        self:trackHoveredRow("curve", index)
        ImGui.PopID()
        if pointTopology then break end
    end

    if ImGui.Button(IconGlyphs.PlusCircleOutline .. "##appendCurvePoint") then
        history.addAction(history.getElementChange(self.object))
        self:appendCurvePoint()
        needsUpdate, topologyChanged = true, true
    end
    style.tooltip("Add a control point past the end, along the end tangent.")
    ImGui.Dummy(0, 8 * style.viewSize)

    if needsUpdate then
        self:ensurePathPoints()
        self:autoFitDeformedBox()
        self:refreshArrowScale()
    end
end

function bendedMesh:drawPathEditor()
    for mode, label in ipairs(pathModeOptions) do
        if mode > 1 then ImGui.SameLine() end
        local selected = self.pathMode == mode
        if style.switchTabButton(label .. "##pathMode" .. mode, selected, nil, 0) and not selected then
            history.addAction(history.getElementChange(self.object))
            self:setPathMode(mode)
            self:autoFitDeformedBox()
            self:refreshArrowScale()
        end
        style.tooltip(pathModeTooltips[mode])
    end

    if self:isCurveMode() then
        self:drawCurveEditor()
        return
    end

    self:ensurePathPoints()
    self:applyPathAlgorithmToNonAnchored()

    local pathVisualizationNeedsUpdate = false
    local pathTopologyChanged = false
    local meshBonesQuantity = self:getMeshBonesQuantity()
    local canEditPointCount = meshBonesQuantity == nil
    local changed

    style.mutedText("Up Axis")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.pathUpAxis, changed = style.trackedCombo(self.object, "##pathUpAxis", self.pathUpAxis, pathUpAxisOptions, 160, {
        tooltip = "Reference axis for constructing local right/up basis from path direction"
    })
    pathVisualizationNeedsUpdate = pathVisualizationNeedsUpdate or changed

    style.mutedText("Loop Path")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.pathLooped, changed = style.trackedCheckbox(self.object, "##pathLooped", self.pathLooped)
    pathVisualizationNeedsUpdate = pathVisualizationNeedsUpdate or changed
    pathTopologyChanged = pathTopologyChanged or changed

    style.mutedText("Use Algorithm")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.pathUseAlgorithm, changed = style.trackedCheckbox(self.object, "##pathUseAlgorithm", self.pathUseAlgorithm)
    if changed and self.pathUseAlgorithm then
        self:applyPathAlgorithmToNonAnchored()
    end
    pathVisualizationNeedsUpdate = pathVisualizationNeedsUpdate or changed
    style.tooltip("When enabled, non-anchored points are computed from anchored points.")

    if self.pathUseAlgorithm then
        style.mutedText("Path Algorithm")
        ImGui.SameLine()
        ImGui.SetCursorPosX(self.maxPropertyWidth)
        self.pathInterpolation, changed = style.trackedCombo(self.object, "##pathInterpolation", self.pathInterpolation, pathInterpolationOptions, 180, {
            tooltip = "Linear interpolates non-anchored points between anchors.\nCatmull-Rom smooths with cubic interpolation.\nBezier builds smooth segments from neighboring anchors using auto handles."
        })
        if changed then
            self.pathInterpolation = math.max(0, math.min(math.floor(self.pathInterpolation), #pathInterpolationOptions - 1))
            self:applyPathAlgorithmToNonAnchored()
        end
        pathVisualizationNeedsUpdate = pathVisualizationNeedsUpdate or changed
    end

    style.mutedText("Bone Placement")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    local solverIndex
    solverIndex, changed = style.trackedCombo(self.object, "##pathSolver", self.pathSolver - 1, pathSolverOptions, 180, {
        tooltip = "Along Curve: non-anchored bones follow the curve with the rig's own spacing,\nso the mesh does not stretch unevenly, and the ends bend along the curve.\n\nBy Index: bones sit at even steps of the curve parameter, as older projects did."
    })
    if changed then
        self.pathSolver = math.max(1, math.min(math.floor(solverIndex) + 1, #pathSolverOptions))
        self:applyPathAlgorithmToNonAnchored()
    end
    pathVisualizationNeedsUpdate = pathVisualizationNeedsUpdate or changed

    ImGui.Dummy(0, 8 * style.viewSize)
    style.mutedText("Mesh bones quantity : " .. (meshBonesQuantity and tostring(meshBonesQuantity) or "Unknown") .. " " .. IconGlyphs.Bone)
    style.tooltip("Each bended mesh has a rig with specific number of bones.\nEach deformation point refers to a mesh bone.")

    local pathLength, restLength = self:getPathLengths()
    if restLength and restLength > 0.000001 then
        local stretch = (pathLength / restLength - 1) * 100
        local text = string.format("Length : %.2f m (base %.2f m, %+.1f%%)", pathLength, restLength, stretch)
        if math.abs(stretch) > 2 then
            style.styledText(IconGlyphs.AlertOutline .. " " .. text, 0xFF4CB8FF)
        else
            style.mutedText(text)
        end
    else
        style.mutedText(string.format("Length : %.2f m", pathLength))
    end
    style.tooltip("Path length through the bones, in the mesh's own units (before scale).\nAway from the rest length, the mesh stretches or squashes.")

    if bendedRig.get(self.spawnData) and not self:getRig() then
        style.styledTextWrapped(IconGlyphs.AlertOutline .. "  This mesh's bones form a grid rather than a line, so a path cannot drive them correctly.", style.extraMutedColor)
    end

    local fieldsX = ImGui.GetCursorPosX() + pointFieldsOffset(#self.pathPoints)
    for index, point in ipairs(self.pathPoints) do
        ImGui.PushID(index)
        ImGui.BeginGroup()
        local deleteRequested = false

        if index == 1 then
            ImGui.Text(IconGlyphs.SourceCommitStart)
        elseif index == #self.pathPoints then
            ImGui.Text(IconGlyphs.SourceCommitEnd)
        else
            ImGui.Text(IconGlyphs.SourceCommit)
        end

        ImGui.SameLine()
        style.mutedText(tostring(index))
        ImGui.SameLine()
        ImGui.SetCursorPosX(fieldsX)

        local pointChanged, anchorChanged = self:drawPathPointEditor(index, point, #self.pathPoints)
        pathVisualizationNeedsUpdate = pathVisualizationNeedsUpdate or pointChanged
        pathTopologyChanged = pathTopologyChanged or anchorChanged

        if canEditPointCount then
            local canInsertPoint = index < #self.pathPoints
            ImGui.BeginDisabled(not canInsertPoint)
            ImGui.SameLine()
            if ImGui.Button(IconGlyphs.PlusCircleMultipleOutline) and canInsertPoint then
                history.addAction(history.getElementChange(self.object))
                local midpoint = lerpPathPoint(point, self.pathPoints[index + 1], 0.5)
                midpoint.anchored = false
                table.insert(self.pathPoints, index + 1, midpoint)
                self:ensurePathPoints()
                pathVisualizationNeedsUpdate = true
                pathTopologyChanged = true
            end
            ImGui.EndDisabled()
            style.tooltip("Insert a deformation point between this and the next point")
        end

        ImGui.SameLine()
        ImGui.BeginDisabled(index == 1 or not point.anchored)
        if ImGui.Button(IconGlyphs.ArrowUp) and index > 1 then
            history.addAction(history.getElementChange(self.object))
            self.pathPoints[index], self.pathPoints[index - 1] = self.pathPoints[index - 1], self.pathPoints[index]
            self:ensurePathPoints()
            pathVisualizationNeedsUpdate = true
            pathTopologyChanged = true
        end
        ImGui.EndDisabled()
        style.tooltip("Move the point before")

        ImGui.SameLine()
        ImGui.BeginDisabled(index == #self.pathPoints or not point.anchored)
        if ImGui.Button(IconGlyphs.ArrowDown) and index < #self.pathPoints then
            history.addAction(history.getElementChange(self.object))
            self.pathPoints[index], self.pathPoints[index + 1] = self.pathPoints[index + 1], self.pathPoints[index]
            self:ensurePathPoints()
            pathVisualizationNeedsUpdate = true
            pathTopologyChanged = true
        end
        ImGui.EndDisabled()
        style.tooltip("Move the point after")

        if canEditPointCount then
            ImGui.SameLine()
            local canRemove = #self.pathPoints > 1
            ImGui.BeginDisabled(not canRemove)
            if style.dangerButton(IconGlyphs.DeleteOutline) and canRemove then
                deleteRequested = true
            end
            ImGui.EndDisabled()
        end

        ImGui.EndGroup()
        self:trackHoveredRow("bone", index)
        ImGui.PopID()

        if deleteRequested then
            history.addAction(history.getElementChange(self.object))
            table.remove(self.pathPoints, index)
            self:ensurePathPoints()
            pathVisualizationNeedsUpdate = true
            pathTopologyChanged = true
            break
        end
    end

    if canEditPointCount then
        if ImGui.Button(IconGlyphs.PlusCircleOutline) then
            history.addAction(history.getElementChange(self.object))
            table.insert(self.pathPoints, self:makeDefaultPathPointAfterCurrent(#self.pathPoints))
            self:ensurePathPoints()
            pathVisualizationNeedsUpdate = true
            pathTopologyChanged = true
        end
        style.tooltip("Add a new deformation point at the end.")
    end
    ImGui.Dummy(0, 8 * style.viewSize)

    if pathVisualizationNeedsUpdate then
        self:ensurePathPoints()
        self:applyPathAlgorithmToNonAnchored()
        self:autoFitDeformedBox()
        self:refreshArrowScale()

    end
end

function bendedMesh:drawDeformationMatrices()
    if not ImGui.TreeNodeEx("Path Deformation", ImGuiTreeNodeFlags.SpanFullWidth + ImGuiTreeNodeFlags.DefaultOpen) then
        return
    end

    if ImGui.Button(style.resolveActionLabelNoIconOnly(IconGlyphs.ContentCopy, "Copy Data", "bendedCopyData")) then
        utils.insertClipboardValue(deformationClipboardKey, self:getDeformationClipboardPayload())
    end
    style.tooltip("Copy path deformation settings to clipboard for pasting into another bended mesh.")

    ImGui.SameLine()
    local clipboardPayload = utils.getClipboardValue(deformationClipboardKey)
    local canPaste = self:isDeformationClipboardPayloadValid(clipboardPayload)
    ImGui.BeginDisabled(not canPaste)
    if ImGui.Button(style.resolveActionLabelNoIconOnly(IconGlyphs.ContentPaste, "Paste Data", "bendedPasteData")) and canPaste then
        history.addAction(history.getElementChange(self.object))
        self:applyDeformationClipboardPayload(clipboardPayload)
    end
    ImGui.EndDisabled()
    style.tooltip("Paste copied path deformation data from another bended mesh.")

    local canCreateContinuation = self.object and self.object.parent and (not self.object:isLocked())
    ImGui.BeginDisabled(not canCreateContinuation)
    if ImGui.Button(style.resolveActionLabelNoIconOnly(IconGlyphs.RayEndArrow, "Continue From Start", "bendedContinueFromStart")) and canCreateContinuation then
        self:createContinuationMesh(true)
    end
    if ImGui.IsItemHovered(ImGuiHoveredFlags.AllowWhenDisabled) then
        self._hoveredEnd = "start"
    end
    style.tooltip("Create a new bended mesh of the same asset joined to the start of this one.")
    ImGui.SameLine()
    if ImGui.Button(style.resolveActionLabelNoIconOnly(IconGlyphs.RayStartArrow, "Continue From End", "bendedContinueFromEnd")) and canCreateContinuation then
        self:createContinuationMesh(false)
    end
    if ImGui.IsItemHovered(ImGuiHoveredFlags.AllowWhenDisabled) then
        self._hoveredEnd = "end"
    end
    style.tooltip("Create a new bended mesh of the same asset joined to the end of this one.")
    ImGui.EndDisabled()
    ImGui.SameLine()
    self.continuationRepeatShape, _ = style.trackedCheckbox(self.object, "Repeat Curve##continuationRepeatShape", self.continuationRepeatShape)
    style.tooltip("The new mesh repeats this mesh's curve instead of starting straight.")

    self:drawSplitControls()
    self:drawShapeTools()

    if ImGui.TreeNodeEx("Advanced", ImGuiTreeNodeFlags.SpanFullWidth) then
        self:drawPathEditor()
        ImGui.TreePop()
    end

    ImGui.TreePop()
end

function bendedMesh:drawMiscSettings()
    if not ImGui.TreeNodeEx("Misc", ImGuiTreeNodeFlags.SpanFullWidth) then
        return
    end

    -- One tree level deeper than the other properties, so the label column is measured here.
    if not self.miscPropertyWidth then
        self.miscPropertyWidth = math.max(self.maxPropertyWidth, utils.getTextMaxWidth(miscLabels) + 2 * ImGui.GetStyle().ItemSpacing.x + ImGui.GetCursorPosX())
    end

    style.mutedText("Remove From Rain Map")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.miscPropertyWidth)
    self.removeFromRainMap, _ = style.trackedCheckbox(self.object, "##removeFromRainMap", self.removeFromRainMap)

    style.mutedText("Navigation Impact")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.miscPropertyWidth)
    self.navigationImpact = math.max(0, math.min(self.navigationImpact or 0, math.max(0, #self.navmeshImpactEnum - 1)))
    self.navigationImpact, _ = style.trackedCombo(self.object, "##navigationImpact", self.navigationImpact, self.navmeshImpactEnum, 160)

    style.mutedText("Cast Local Shadows")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.miscPropertyWidth)
    local changed
    self.castLocalShadows, changed = style.trackedCombo(self.object, "##bendedCastLocalShadows", self.castLocalShadows, self.shadowCastingModeEnum, 120)
    self:updateShadowSettings(changed)

    style.mutedText("Cast Shadows")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.miscPropertyWidth)
    self.castShadows, changed = style.trackedCombo(self.object, "##bendedCastShadows", self.castShadows, self.shadowCastingModeEnum, 120)
    self:updateShadowSettings(changed)

    ImGui.TreePop()
end

---Physics material of a collision class: the one set on this node, else the mesh's own.
---@param class string
---@return string
function bendedMesh:getCollisionMaterial(class)
    local material = self.collisionMaterials[class]
    if material and material ~= "" then return material end
    local source = bendedCollision.get(self.spawnData)
    return source and source.materials and source.materials[class] or DEFAULT_COLLISION_MATERIAL
end

---Material and preset selectors of one collision class.
---@param class string
---@return boolean changed
function bendedMesh:drawCollisionClass(class)
    local changed = false

    style.mutedText(COLLISION_CLASS_LABELS[class])
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)

    local current = self:getCollisionMaterial(class)
    local selected = current
    for index, name in ipairs(colliderMaterials) do
        if name == current then
            selected = colliderBase.getMaterialDisplayByIndex(index - 1)
            break
        end
    end

    local materialChanged
    selected, self.collisionMaterialSearch[class], materialChanged = style.trackedSearchDropdown(
        "##collisionMaterial" .. class,
        "Search material...",
        selected,
        self.collisionMaterialSearch[class] or "",
        colliderBase.getMaterialDisplayOptions(),
        { element = self.object, width = 150, matchContentWidth = true, tooltip = "Physics material. Defaults to the mesh's own." }
    )
    if materialChanged then
        local index = colliderBase.getMaterialIndexByDisplay(selected)
        if index then
            self.collisionMaterials[class] = colliderMaterials[index + 1]
            changed = true
        end
    end

    ImGui.SameLine()
    local presetChanged
    local preset = self.collisionPresets[class]
    preset, self.collisionPresetSearch[class], presetChanged = style.trackedSearchDropdown(
        "##collisionPreset" .. class,
        "Search preset...",
        preset,
        self.collisionPresetSearch[class] or "",
        colliderPresets,
        { element = self.object, width = 150, matchContentWidth = true, tooltip = "Collision preset." }
    )
    if presetChanged then
        self.collisionPresets[class] = preset
        changed = true
    end

    return changed
end

function bendedMesh:drawCollisionSettings()
    if not ImGui.TreeNodeEx("Collision", ImGuiTreeNodeFlags.SpanFullWidth) then
        return
    end

    local anyChanged = false
    for _, class in ipairs(COLLISION_CLASSES) do
        anyChanged = self:drawCollisionClass(class) or anyChanged
    end

    if anyChanged then
        self:refreshCollisionPreview()
    end

    ImGui.TreePop()
end

function bendedMesh:draw()
    if self.pendingAutoFit and self.bBoxLoaded then
        self:autoFitDeformedBox()
        self.pendingAutoFit = false
        self:refreshArrowScale()
    end

    spawnable.draw(self)

    if not self.maxPropertyWidth then
        self.maxPropertyWidth = utils.getTextMaxWidth({
            "Appearance",
            "Bended Road",
            "Remove From Rain Map",
            "Navigation Impact",
            "Cast Local Shadows",
            "Cast Shadows",
            "Looped Path",
            "Use Algorithm",
            "Path Algorithm",
            "Bone Placement",
            "Length Mode",
            "Mesh bones quantity",
            style.resolveActionLabelNoIconOnly(IconGlyphs.TriangleWave, "Deformed Preview"),
            style.resolveActionLabelNoIconOnly(IconGlyphs.TextureBox, "Live Collision"),
            style.resolveActionLabelNoIconOnly(IconGlyphs.EyeOutline, "Show Collision"),
            style.resolveActionLabelNoIconOnly(IconGlyphs.Export, "Export Collision"),
            style.resolveActionLabelNoIconOnly(IconGlyphs.VectorBezier, "Viewport Handles"),
            style.resolveActionLabelNoIconOnly(IconGlyphs.Magnet, "Magnetic Ends"),
            style.resolveActionLabelNoIconOnly(IconGlyphs.LinkVariant, "Linked Ends"),
            "Pieces",
            style.resolveActionLabelNoIconOnly(IconGlyphs.MapMarkerMultipleOutline, "In-World Path Viz"),
            "Ground",
            "Raised",
            "Wall"
        }) + 2 * ImGui.GetStyle().ItemSpacing.x + ImGui.GetCursorPosX()
    end

    self:drawAppearanceSelector()

    style.mutedText("Bended Road")
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.isBendedRoad, _ = style.trackedCheckbox(self.object, "##isBendedRoad", self.isBendedRoad)

    style.mutedText(style.resolveActionLabelNoIconOnly(IconGlyphs.Export, "Export Collision"))
    ImGui.SameLine()
    ImGui.SetCursorPosX(self.maxPropertyWidth)
    self.exportCollision, _ = style.trackedCheckbox(self.object, "##exportCollision", self.exportCollision)
    style.tooltip("Export the collision pieces with the mesh.\nThe bended meshes of a group share one collision node, placed after the last of them.")

    local visualizationChanged = self:drawPathVisualizationSettings()
    if visualizationChanged then
        self:refreshArrowScale()
    end
    self:drawCollisionSettings()
    self:drawDeformationMatrices()
    self:drawMiscSettings()
    self:drawConversionSelector("##bendedMeshConverterType", "Lossy Conversion##bendedMeshSingle")
end

function bendedMesh:getProperties()
    return self:addNodeProperty(spawnable.getProperties(self))
end

function bendedMesh:getNormalizedDeformedBox()
    local min = self.deformedBox.min
    local max = self.deformedBox.max

    return {
        min = {
            x = math.min(min.x, max.x),
            y = math.min(min.y, max.y),
            z = math.min(min.z, max.z)
        },
        max = {
            x = math.max(min.x, max.x),
            y = math.max(min.y, max.y),
            z = math.max(min.z, max.z)
        }
    }
end

function bendedMesh:getSize()
    local box = self:getNormalizedDeformedBox()
    return utils.getBoxSize(box, self.scale)
end

function bendedMesh:getBBox()
    local box = self:getNormalizedDeformedBox()
    return utils.getScaledBBox(box, self.scale)
end

function bendedMesh:getCenter()
    local box = self:getNormalizedDeformedBox()
    return utils.getBoxCenter(box, self.scale, self.rotation, self.position)
end

function bendedMesh:calculateIntersection(origin, ray)
    if not self:getEntity() then
        return { hit = false }
    end

    local box = self:getNormalizedDeformedBox()
    local scaleFactor = intersection.getResourcePathScalingFactor(self.spawnData, self:getSize())

    local scaledBBox = utils.getScaledBBoxWithFactor(box, self.scale, scaleFactor)
    local result = intersection.getBoxIntersection(origin, ray, self.position, self.rotation, scaledBBox)

    local unscaledHit
    if result.hit then
        unscaledHit = intersection.getBoxIntersection(origin, ray, self.position, self.rotation, intersection.unscaleBBox(self.spawnData, self:getSize(), scaledBBox))
    end

    return {
        hit = result.hit,
        position = result.position,
        unscaledHit = unscaledHit and unscaledHit.position or result.position,
        collisionType = "bbox",
        distance = result.distance,
        bBox = scaledBBox,
        objectOrigin = self.position,
        objectRotation = self.rotation,
        normal = result.normal
    }
end

---Collision pieces in world space, rounded to the millimetre, for the export.
---@return table? collision `{ pieces = { { class, material, preset, points = { x, y, z, ... } } } }`
---@return string? issue
function bendedMesh:getExportCollision()
    local shapes, issue = self:getCollisionShapes()
    if not shapes then
        return nil, issue
    end

    local quat = self.rotation:ToQuat()
    local position = self.position
    local function round(value)
        return math.floor(value * 1000 + 0.5) / 1000
    end

    local pieces = {}
    for _, shape in ipairs(shapes) do
        local points = {}
        for _, point in ipairs(shape.points) do
            local world = quat:Transform(Vector4.new(point.x, point.y, point.z, 0))
            table.insert(points, round(world.x + position.x))
            table.insert(points, round(world.y + position.y))
            table.insert(points, round(world.z + position.z))
        end
        table.insert(pieces, { class = shape.class, material = shape.material, preset = shape.preset, points = points })
    end

    return { pieces = pieces }
end

function bendedMesh:export()
    local matrices = self:rebuildMatricesFromPath(self.bBoxLoaded)
    return self:exportPiece(matrices, self:getNormalizedDeformedBox())
end

---Nodes of the export: an unsplit curve gives the chain Split into Chain would make, the project is left as is.
---@param key integer
---@param length integer
---@return table[] nodes
function bendedMesh:exportNodes(key, length)
    local count = self:getSplitCount()
    if count <= 1 then
        return { self:export(key, length) }
    end

    local nodes = {}
    for index, frames in ipairs(self:getSplitPieceFrames(count)) do
        -- Pieces after the first sit on their own first bone, as Split into Chain places them.
        local origin
        if index > 1 then
            origin = frames[1].position
            local shifted = {}
            for i, frame in ipairs(frames) do
                local copy = {}
                for field, value in pairs(frame) do
                    copy[field] = value
                end
                copy.position = { x = frame.position.x - origin.x, y = frame.position.y - origin.y, z = frame.position.z - origin.z }
                shifted[i] = copy
            end
            frames = shifted
        end

        local node = self:exportPiece(self:matricesFromFrames(frames), self:computeDeformedBox(frames), origin)
        node.name = string.format("%s (%d/%d)", node.name, index, count)
        if index > 1 then
            node.nodeRef = (self.nodeRef or "") ~= "" and (self.nodeRef .. "_" .. index) or ""
        end
        table.insert(nodes, node)
    end

    return nodes
end

---Node of one deformation.
---@param matrices table[] Deformation matrices, in the node's local space.
---@param normalizedBox table Deformed box, in the node's local space.
---@param origin table? Mesh-space point the node sits on, from the mesh's own position.
---@return table node
function bendedMesh:exportPiece(matrices, normalizedBox, origin)
    local app = self.app
    if app == "" then
        app = "default"
    end

    local data = spawnable.export(self)
    if origin then
        local position = self:getWorldPointFromLocal(origin)
        data.position = utils.fromVector(position)
        if not self.streamingRefPointOverride then
            data.streamingRefPoint = utils.fromVector(position)
        end
    end
    data.type = "worldBendedMeshNode"
    data.scale = self.scale
    data.data = {
        mesh = {
            DepotPath = {
                ["$storage"] = "string",
                ["$value"] = self.spawnData
            }
        },
        meshAppearance = {
            ["$storage"] = "string",
            ["$value"] = app
        },
        deformationData = {},
        deformedBox = {
            ["$type"] = "Box",
            Min = toTypedVector4(Vector4.new(normalizedBox.min.x, normalizedBox.min.y, normalizedBox.min.z, 1)),
            Max = toTypedVector4(Vector4.new(normalizedBox.max.x, normalizedBox.max.y, normalizedBox.max.z, 1))
        },
        isBendedRoad = self.isBendedRoad and 1 or 0,
        castShadows = self.shadowCastingModeEnum[self.castShadows + 1],
        castLocalShadows = self.shadowCastingModeEnum[self.castLocalShadows + 1],
        removeFromRainMap = self.removeFromRainMap and 1 or 0,
        navigationSetting = {
            ["$type"] = "NavGenNavigationSetting",
            navmeshImpact = self.navmeshImpactEnum[self.navigationImpact + 1] or "Road"
        },
        version = self.version or 0
    }

    for _, matrix in ipairs(matrices) do
        table.insert(data.data.deformationData, toTypedMatrix(matrix))
    end

    return data
end

return bendedMesh
