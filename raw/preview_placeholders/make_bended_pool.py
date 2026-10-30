"""Builds the bended preview pool: one Exterior sector, one prefab variant per worldBendedMeshNode placeholder.

Usage: python make_bended_pool.py <template_sector.json> <block.json> <sector_out.json> <block_out.json>

The template sector/block are WolvenKit JSON exports of wb_preview_placeholders.streamingsector and
all.streamingblock; the spline descriptor is kept as is and the pool descriptor is appended.
Each placeholder sits at the world origin with an identity transform; the preview bakes the world
pose into deformationData and re-attaches the node with ToggleVariant(prefab, "wb_bended_v<N>").
"""
import copy
import json
import sys

sector_in, block_in, sector_out, block_out = sys.argv[1:5]

COUNT = 500
RANGE = 9000.0
ORIGIN = (0.0, 0.0, 0.0)
# Idle placeholders are collapsed to a point so they draw nothing at the origin.
PARK_SCALE = 0.001
MESH = "base\\worlds\\03_night_city\\sectors\\_external\\road_meshes\\bended\\br_bcaafaf2_rt_1x1_with_sidewalks_24m.mesh"
BONES = 9
BONE_STEP = 3.0
REF_ROOT = "$/mods/entSpawner/preview_bended/#"
PREFAB_REF = "$/mods/entSpawner/preview_bended/#all"
VARIANT_PREFIX = "wb_bended_v"
NODE_PREFIX = "wb_preview_bended_"
SECTOR_PATH = "world_builder\\sectors\\wb_preview_bended.streamingsector"
VARIANT_ID_BASE = 3711001000
FLT_MAX = 3.40282347e38


def v4(x, y, z, w):
    return {"$type": "Vector4", "W": w, "X": x, "Y": y, "Z": z}


def parked_matrix(index):
    s = PARK_SCALE
    return {
        "$type": "Matrix",
        "X": v4(s, 0, 0, 0),
        "Y": v4(0, s, 0, 0),
        "Z": v4(0, 0, s, 0),
        "W": v4(ORIGIN[0], ORIGIN[1] + index * BONE_STEP * s, ORIGIN[2], 1),
    }


def node(handle, name):
    return {
        "HandleId": str(handle),
        "Data": {
            "$type": "worldBendedMeshNode",
            "debugName": {"$type": "CName", "$storage": "string", "$value": name},
            "isHostOnly": 0,
            "isVisibleInGame": 1,
            "proxyScale": None,
            "sourcePrefabHash": "0",
            "tag": "None",
            "tagExt": "None",
            "mesh": {"DepotPath": {"$type": "ResourcePath", "$storage": "string", "$value": MESH}, "Flags": "Default"},
            "meshAppearance": {"$type": "CName", "$storage": "string", "$value": "default"},
            "deformationData": [parked_matrix(i) for i in range(BONES)],
            "deformedBox": {"$type": "Box",
                            "Min": v4(ORIGIN[0] - 1, ORIGIN[1] - 1, ORIGIN[2] - 1, 1),
                            "Max": v4(ORIGIN[0] + 1, ORIGIN[1] + 1, ORIGIN[2] + 1, 1)},
            "isBendedRoad": 1,
            "castShadows": "Always",
            "castLocalShadows": "Always",
            "removeFromRainMap": 0,
            "navigationSetting": {"$type": "NavGenNavigationSetting", "navmeshImpact": "Road"},
            "version": 1,
        },
    }


source = json.load(open(sector_in, encoding="utf-8-sig"))
block = json.load(open(block_in, encoding="utf-8-sig"))

sector = copy.deepcopy(source)
root = sector["Data"]["RootChunk"]
template = copy.deepcopy(root["nodeData"]["Data"][0])
root["category"] = "Exterior"
root["level"] = 1
root["nodes"] = []
root["nodeData"]["Data"] = []
root["nodeRefs"] = []
variants = []

for index in range(COUNT):
    name = NODE_PREFIX + str(index)
    root["nodes"].append(node(index, name))

    # Same nodeData shape as the WB exporter: Bounds run from the node position to its streaming
    # reference point, UkFloat1 is the streaming range and MaxStreamingDistance 0.85 of it.
    entry = copy.deepcopy(template)
    entry["NodeIndex"] = index
    entry["Position"] = v4(ORIGIN[0], ORIGIN[1], ORIGIN[2], 0)
    entry["Pivot"] = {"$type": "Vector3", "X": ORIGIN[0], "Y": ORIGIN[1], "Z": ORIGIN[2]}
    entry["Bounds"] = {"$type": "Box", "Max": v4(ORIGIN[0], ORIGIN[1], ORIGIN[2], 0), "Min": v4(ORIGIN[0], ORIGIN[1], ORIGIN[2], 0)}
    entry["UkFloat1"] = RANGE
    entry["MaxStreamingDistance"] = RANGE * 0.85
    entry["QuestPrefabRefHash"] = {"$type": "NodeRef", "$storage": "string", "$value": REF_ROOT + name}
    root["nodeData"]["Data"].append(entry)
    root["nodeRefs"].append({"$type": "NodeRef", "$storage": "string", "$value": REF_ROOT + name})

    variants.append({
        "$type": "worldStreamingSectorVariant",
        "enabledByDefault": 1,
        "name": {"$type": "CName", "$storage": "string", "$value": VARIANT_PREFIX + str(index)},
        "nodeRef": {"$type": "NodeRef", "$storage": "string", "$value": PREFAB_REF},
        "parentVariantID": 0,
        "rangeIndex": index + 1,
        "variantId": VARIANT_ID_BASE + index,
    })

# Range 0 (always on) is empty; range N + 1 holds placeholder N alone.
root["variantIndices"] = [0] + list(range(COUNT))
root["variantNodes"] = [[] for _ in variants]

descriptors = block["Data"]["RootChunk"]["descriptors"]
descriptors[:] = [d for d in descriptors if d["data"]["DepotPath"]["$value"] != SECTOR_PATH]
descriptor = copy.deepcopy(descriptors[0])
descriptor["category"] = "Exterior"
descriptor["level"] = 1
descriptor["data"]["DepotPath"]["$value"] = SECTOR_PATH
descriptor["data"]["Flags"] = "Default"
descriptor["numNodeRanges"] = COUNT + 1
descriptor["variants"] = variants
descriptor["questPrefabNodeRef"] = {"$type": "NodeRef", "$storage": "uint64", "$value": "0"}
# W lanes inverted, as entSpawner's exporter writes them.
descriptor["streamingBox"] = {"$type": "Box",
                              "Max": v4(ORIGIN[0] + RANGE, ORIGIN[1] + RANGE, ORIGIN[2] + RANGE, -FLT_MAX),
                              "Min": v4(ORIGIN[0] - RANGE, ORIGIN[1] - RANGE, ORIGIN[2] - RANGE, FLT_MAX)}
descriptors.append(descriptor)

json.dump(sector, open(sector_out, "w", encoding="utf-8"), indent=2)
json.dump(block, open(block_out, "w", encoding="utf-8"), indent=2)
print("placeholders", COUNT, "ranges", descriptor["numNodeRanges"], "descriptors", len(descriptors))
