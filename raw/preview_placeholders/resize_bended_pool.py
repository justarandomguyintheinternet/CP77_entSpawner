"""Resizes the bended preview pool, from the WolvenKit 10 JSON of its sector and streaming block.

Usage: python resize_bended_pool.py <sector.json> <block.json> <count> <sector_out.json> <block_out.json>

The inputs are convert_to_json exports of world_builder\\sectors\\wb_preview_bended.streamingsector and
world_builder\\all.streamingblock (version 68 sector). Placeholder N is a copy of placeholder 0 with its own
debug name, node ref, global node id and prefab variant (range N + 1). make_bended_pool.py builds the pool
from scratch but reads the WolvenKit 9 JSON layout; this one keeps every other field as it is.
bendedPool.lua's slotCount must match the count.
"""
import copy
import json
import sys

sector_in, block_in, count, sector_out, block_out = sys.argv[1:6]
COUNT = int(count)

REF_ROOT = "$/mods/entSpawner/preview_bended/#"
VARIANT_PREFIX = "wb_bended_v"
NODE_PREFIX = "wb_preview_bended_"
SECTOR_PATH = "world_builder\\sectors\\wb_preview_bended.streamingsector"
VARIANT_ID_BASE = 3711001000


def fnv1a64(text):
    h = 0xCBF29CE484222325
    for b in text.encode():
        h = ((h ^ b) * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return h


def global_node_id(ref):
    # The engine hashes a node ref without its '#'.
    return str(fnv1a64(ref.replace("#", "")))


sector = json.load(open(sector_in, encoding="utf-8-sig"))
block = json.load(open(block_in, encoding="utf-8-sig"))
root = sector["Data"]["RootChunk"]
if root.get("version") != 68:
    sys.exit("expected a version 68 sector, found %s" % root.get("version"))

node0, data0, var0 = root["nodes"][0], root["nodeData"]["Data"][0], root["variantNodes"][0][0]
nodes, data, refs, variant_nodes = [], [], [], []
for index in range(COUNT):
    name = NODE_PREFIX + str(index)
    ref = REF_ROOT + name

    node = copy.deepcopy(node0)
    node["HandleId"] = str(index)
    node["Data"]["debugName"]["$value"] = name
    nodes.append(node)

    for template, out in ((data0, data), (var0, None)):
        entry = copy.deepcopy(template)
        entry["nodeIdx"] = str(index)
        entry["globalNodeId"]["hash"] = global_node_id(ref)
        if out is not None:
            out.append(entry)
        else:
            variant_nodes.append([entry])

    refs.append({"$type": "NodeRef", "$storage": "string", "$value": ref})

root["nodes"], root["nodeData"]["Data"], root["nodeRefs"] = nodes, data, refs
# Range 0 (always on) is empty; range N + 1 holds placeholder N alone.
root["variantIndices"] = [0] + list(range(COUNT))
root["variantNodes"] = variant_nodes

descriptor = next(d for d in block["Data"]["RootChunk"]["descriptors"] if d["data"]["DepotPath"]["$value"] == SECTOR_PATH)
v0 = descriptor["variants"][0]
variants = []
for index in range(COUNT):
    variant = copy.deepcopy(v0)
    variant["name"]["$value"] = VARIANT_PREFIX + str(index)
    variant["rangeIndex"] = index + 1
    variant["variantId"] = VARIANT_ID_BASE + index
    variants.append(variant)
descriptor["variants"] = variants
descriptor["numNodeRanges"] = COUNT + 1

json.dump(sector, open(sector_out, "w", encoding="utf-8"), indent=2)
json.dump(block, open(block_out, "w", encoding="utf-8"), indent=2)
print("placeholders", COUNT, "ranges", descriptor["numNodeRanges"])
