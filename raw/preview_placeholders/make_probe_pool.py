"""Builds the reflection probe preview pool from the WolvenKit 10 JSON of the bended pool sector and the streaming block.

Usage: python make_probe_pool.py <bended_sector.json> <block.json> <count> <sector_out.json> <block_out.json>

Placeholder N is a worldReflectionProbeNode alone in prefab variant wb_probe_vN (range N + 1), off by default.
The block gains (or replaces) the descriptor of world_builder\\sectors\\wb_preview_probes.streamingsector.
probePool.lua's expectedSlots must match the count.
"""
import copy
import json
import sys

bended_in, block_in, count, sector_out, block_out = sys.argv[1:6]
COUNT = int(count)

REF_ROOT = "$/mods/entSpawner/preview_probes/#"
PREFAB_REF = REF_ROOT + "all"
VARIANT_PREFIX = "wb_probe_v"
NODE_PREFIX = "wb_preview_probe_"
SECTOR_PATH = "world_builder\\sectors\\wb_preview_probes.streamingsector"
BENDED_PATH = "world_builder\\sectors\\wb_preview_bended.streamingsector"
VARIANT_ID_BASE = 3711002000


def fnv1a64(text):
    h = 0xCBF29CE484222325
    for b in text.encode():
        h = ((h ^ b) * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return h


def global_node_id(ref):
    # The engine hashes a node ref without its '#'.
    return str(fnv1a64(ref.replace("#", "")))


def vector3(x, y, z):
    return {"$type": "Vector3", "X": x, "Y": y, "Z": z}


def probe_node(index, name):
    return {
        "HandleId": str(index),
        "Data": {
            "$type": "worldReflectionProbeNode",
            "allInShadow": 0,
            "ambientMode": "eOVERRIDE_GI_AMBIENT",
            "blendRange": 20,
            "boxProjection": 1,
            "brightnessEVClamp": 8,
            "captureOffset": vector3(0, 0, 0),
            "debugName": {"$type": "CName", "$storage": "string", "$value": name},
            "edgeScale": vector3(0.98, 0.98, 0.98),
            "emissiveScale": 1,
            "farClipDistance": 4000,
            "globalProbe": 0,
            "hideSkyColor": 0,
            "isHostOnly": 0,
            "isVisibleInGame": 1,
            "lightChannels": "0",
            "nearClipDistance": 0.01,
            "neighborMode": "eONLY_SELF",
            "noFadeBlend": 0,
            "priority": 2,
            "probeDataRef": {
                "DepotPath": {"$type": "ResourcePath", "$storage": "uint64", "$value": "0"},
                "Flags": "Soft",
            },
            "proxyScale": None,
            "reflectionDimming": 1,
            "simpleFogColor": {"$type": "HDRColor", "Alpha": 1, "Blue": 1, "Green": 1, "Red": 1},
            "simpleFogDensity": 0,
            "skyScale": 1,
            "sourcePrefabHash": "0",
            "streamingDistance": 64,
            "streamingHeight": -1,
            "subScene": 0,
            "tag": "None",
            "tagExt": "None",
            "volFogAmbient": 1,
            "volumeChannels": "0",
        },
    }


sector = json.load(open(bended_in, encoding="utf-8-sig"))
block = json.load(open(block_in, encoding="utf-8-sig"))
root = sector["Data"]["RootChunk"]
if root.get("version") != 68:
    sys.exit("expected a version 68 sector, found %s" % root.get("version"))

data0 = root["nodeData"]["Data"][0]
data0 = copy.deepcopy(data0)
data0["nodeFlags"] = "FLAG_AllowForceStreamIn, FLAG_Building"

nodes, data, refs, variant_nodes = [], [], [], []
for index in range(COUNT):
    name = NODE_PREFIX + str(index)
    ref = REF_ROOT + name
    nodes.append(probe_node(index, name))

    entry = copy.deepcopy(data0)
    entry["nodeIdx"] = str(index)
    entry["globalNodeId"]["hash"] = global_node_id(ref)
    data.append(entry)
    variant_nodes.append([copy.deepcopy(entry)])

    refs.append({"$type": "NodeRef", "$storage": "string", "$value": ref})

root["nodes"], root["nodeData"]["Data"], root["nodeRefs"] = nodes, data, refs
# Range 0 (always on) is empty; range N + 1 holds placeholder N alone.
root["variantIndices"] = [0] + list(range(COUNT))
root["variantNodes"] = variant_nodes

descriptors = block["Data"]["RootChunk"]["descriptors"]
template = next(d for d in descriptors if d["data"]["DepotPath"]["$value"] == BENDED_PATH)
descriptor = copy.deepcopy(template)
descriptor["data"]["DepotPath"]["$value"] = SECTOR_PATH
v0 = template["variants"][0]
variants = []
for index in range(COUNT):
    variant = copy.deepcopy(v0)
    variant["name"]["$value"] = VARIANT_PREFIX + str(index)
    variant["nodeRef"]["$value"] = PREFAB_REF
    variant["enabledByDefault"] = 0
    variant["rangeIndex"] = index + 1
    variant["variantId"] = VARIANT_ID_BASE + index
    variants.append(variant)
descriptor["variants"] = variants
descriptor["numNodeRanges"] = COUNT + 1

descriptors[:] = [d for d in descriptors if d["data"]["DepotPath"]["$value"] != SECTOR_PATH]
descriptors.append(descriptor)

json.dump(sector, open(sector_out, "w", encoding="utf-8"), indent=2)
json.dump(block, open(block_out, "w", encoding="utf-8"), indent=2)
print("placeholders", COUNT, "ranges", descriptor["numNodeRanges"], "descriptors", len(descriptors))
