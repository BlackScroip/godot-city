#!/usr/bin/env python3
"""Recover source-bound embedded Reaper and dragon particles from the APK."""

import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import zipfile

import UnityPy

from recover_chest_effects import package_manifest


ROOT = Path(__file__).resolve().parents[2]
APK_SHA = "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505"
ACTORS = {
    52003: ("myenemy_sishen", "25010901_fx_enemy_sishen_aura_"),
    53001: ("myenemy_feimolong", "_fx_enemy_feimolong_"),
}


def digest(payload):
    return hashlib.sha256(payload).hexdigest()


def glb_nodes(path):
    payload = path.read_bytes()
    size, kind = struct.unpack_from("<II", payload, 12)
    if kind != 0x4E4F534A:
        raise ValueError("Actor GLB has no leading JSON chunk: " + str(path))
    document = json.loads(payload[20:20 + size])
    nodes = document["nodes"]
    joints = {nodes[index]["name"] for skin in document.get("skins", []) for index in skin["joints"]}
    return joints, {node.get("name", "") for node in nodes}, digest(payload)


def inspect_actor(archive, manifest, actor_id, address, prefix, actor_glb):
    asset = next(row for row in manifest["assets"] if row["address"].lower() == address)
    member = "assets/yoo/DefaultPackage/" + manifest["bundles"][asset["bundle"]]["hash"] + ".bundle"
    payload = archive.read(member)
    env = UnityPy.load(payload)
    objects = {(obj.assets_file.name, obj.path_id): obj for obj in env.objects}
    trees = {}

    def tree(obj):
        if obj is None:
            return {}
        key = (obj.assets_file.name, obj.path_id)
        if key not in trees:
            trees[key] = obj.read_typetree()
        return trees[key]

    def resolve(obj, ref):
        if obj is None or not ref or not ref.get("m_PathID"):
            return None
        file_id = ref.get("m_FileID", 0)
        filename = obj.assets_file.name if not file_id else obj.assets_file.externals[file_id - 1].path.rsplit("/", 1)[-1]
        return objects.get((filename, ref["m_PathID"]))

    def components(go):
        found = [resolve(go, row.get("component", row)) for row in tree(go).get("m_Component", [])]
        return {obj.type.name: obj for obj in found if obj is not None}

    def trs(transform):
        data = tree(transform)
        return {"position": data["m_LocalPosition"], "rotation": data["m_LocalRotation"], "scale": data["m_LocalScale"]}

    def source(obj):
        return "%s:%s" % (obj.assets_file.name, obj.path_id)

    joints, nodes, actor_sha = glb_nodes(actor_glb)
    roots = [obj for obj in env.objects if obj.type.name == "GameObject" and prefix in tree(obj).get("m_Name", "")]
    bindings, layers, trails = {}, {}, {}
    for go in roots:
        name = tree(go)["m_Name"]
        ident = name.lower() + "__" + str(go.path_id)
        transform = components(go).get("Transform")
        ancestors = []
        current = resolve(transform, tree(transform).get("m_Father"))
        while current:
            parent_go = resolve(current, tree(current).get("m_GameObject"))
            ancestors.append((current, tree(parent_go).get("m_Name", "")))
            current = resolve(current, tree(current).get("m_Father"))
        anchor_index = next((i for i, (_, n) in enumerate(ancestors) if n in joints), None)
        anchor_kind = "bone"
        if anchor_index is None:
            anchor_index = next((i for i, (_, n) in enumerate(ancestors) if n in nodes), None)
            anchor_kind = "node"
        if anchor_index is None:
            raise ValueError("No imported anchor for " + ident)
        anchor_name = ancestors[anchor_index][1]
        parent_chain = [trs(item[0]) for item in reversed(ancestors[:anchor_index])]
        source_active = bool(tree(go).get("m_IsActive", True))
        bindings[ident] = {
            "actor_id": actor_id,
            "name": name,
            "anchor_kind": anchor_kind,
            "bone": anchor_name if anchor_kind == "bone" else "",
            "node": anchor_name if anchor_kind == "node" else "",
            "parent_transform_chain": parent_chain,
            "effect_root_transform": trs(transform),
            "source_root_active": source_active,
            "source_hierarchy_from_anchor": [anchor_name] + [item[1] for item in reversed(ancestors[:anchor_index])] + [name],
            "source_root": source(go),
            "source_transform": source(transform),
        }
        layers[ident], trails[ident] = {}, []

        def walk(child, chain, inherited, is_root=False):
            if child is None:
                return
            data = tree(child)
            active = inherited and (is_root or bool(data.get("m_IsActive", True)))
            by_type = components(child)
            child_transform = by_type.get("Transform")
            chain = chain + [trs(child_transform)]
            particle = by_type.get("ParticleSystem")
            renderer = tree(by_type.get("ParticleSystemRenderer"))
            if particle:
                key = str(particle.path_id)
                layers[ident][key] = {
                    "active": active,
                    "source_default_active": source_active and active,
                    "transform_chain": chain,
                    "scaling_mode": tree(particle).get("scalingMode"),
                    "renderer": {target: renderer.get(field) for target, field in (
                        ("camera_velocity_scale", "m_CameraVelocityScale"),
                        ("freeform_stretching", "m_FreeformStretching"),
                        ("rotate_with_stretch_direction", "m_RotateWithStretchDirection"),
                        ("sorting_order", "m_SortingOrder"),
                        ("min_particle_size", "m_MinParticleSize"),
                        ("max_particle_size", "m_MaxParticleSize"),
                        ("pivot", "m_Pivot"),
                    )},
                }
            trail = by_type.get("TrailRenderer")
            if trail:
                trails[ident].append({"source_file_id": str(trail.path_id), "source": source(trail),
                                      "name": data.get("m_Name", ""), "active": active,
                                      "source_default_active": source_active and active, "transform_chain": chain})
            for child_ref in tree(child_transform).get("m_Children", []):
                child_transform_obj = resolve(child_transform, child_ref)
                walk(resolve(child_transform_obj, tree(child_transform_obj).get("m_GameObject")), chain, active)

        walk(go, [], True, True)
    return asset, bindings, layers, trails, {
        "actor_id": actor_id, "asset": asset["path"], "bundle_member": member,
        "bundle_sha256": digest(payload), "actor_glb": str(actor_glb), "actor_glb_sha256": actor_sha,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, default=ROOT / "1061664.apk")
    parser.add_argument("--evidence", type=Path, default=Path("/private/tmp/city-region-combat-evidence"))
    parser.add_argument("--output", type=Path, default=ROOT / "goDot/assets/combat_presentation/boss_embedded")
    args = parser.parse_args()
    if digest(args.apk.read_bytes()) != APK_SHA:
        raise ValueError("This recovery requires the user-selected 1061664.apk")
    provenance = json.loads((args.evidence / "provenance.json").read_text())
    if provenance["apk_sha256"] != APK_SHA:
        raise ValueError("Action evidence belongs to a different APK")
    raw = json.loads((args.evidence / "raw-catalog.json").read_text())
    events = []
    for action in ("roar1", "roar2", "roar3"):
        config = raw["ActGroup_feimolong_[%s]" % action]
        for event in config["Events"]:
            if event.get("Enabled") and event.get("EventType") == "EET_SetGameObjectActive":
                names = event.get("EventData", {}).get("gameobjectNames", [])
                if any(name.startswith("241225") for name in names):
                    events.append({"action": action, "trigger_time_ms": event["TriggerTime"],
                                   "active": event["EventData"]["booleanToSet"], "names": names})
    with zipfile.ZipFile(args.apk) as archive:
        manifest_member = next(name for name in archive.namelist() if name.startswith(
            "assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes"))
        manifest_payload = archive.read(manifest_member)
        manifest = package_manifest(manifest_payload)
        bindings, layers, trails, sources = {}, {}, {}, []
        for actor_id, (address, prefix) in ACTORS.items():
            actor_glb = ROOT / ("goDot/assets/enemies/enemy_%s.glb" % actor_id)
            _, actor_bindings, actor_layers, actor_trails, source = inspect_actor(
                archive, manifest, actor_id, address, prefix, actor_glb)
            bindings.update(actor_bindings)
            layers.update(actor_layers)
            trails.update(actor_trails)
            sources.append(source)
    if len(bindings) != 28 or sum(map(len, layers.values())) != 71:
        raise ValueError("Unexpected root or particle inventory")
    with tempfile.TemporaryDirectory(prefix="city-boss-embedded-") as directory:
        folder = Path(directory)
        manifest_path, selection_path = folder / "manifest.json", folder / "selected.json"
        manifest_path.write_text(json.dumps(manifest))
        selection_path.write_text(json.dumps([value[0] for value in ACTORS.values()]))
        subprocess.run([sys.executable, str(Path(__file__).with_name("export_environment_effects.py")),
                        "--apk", str(args.apk), "--manifest", str(manifest_path), "--asset-list", str(selection_path),
                        "--output-directory", str(args.output), "--shared-materials", "--include-root-transform", "--include-trails",
                        "--report", str(args.output / "source-export-report.json")], check=True)
    catalog_path = args.output / "catalog.json"
    catalog = json.loads(catalog_path.read_text())
    materials = json.loads((args.output / "materials.json").read_text())
    original = catalog["effects"]
    effects = {}
    for key, binding in bindings.items():
        source = original[ACTORS[binding["actor_id"]][0]]
        available = {str(row["source_file_id"]): row for row in source["layers"]}
        rows = []
        for particle, metadata in layers[key].items():
            layer = available[particle]
            layer.update({name: value for name, value in metadata.items() if name != "renderer"})
            layer["renderer"].update(metadata["renderer"])
            rows.append(layer)
        available_trails = {str(row["source_file_id"]): row for row in source.get("trails", [])}
        trail_rows = []
        for metadata in trails[key]:
            trail = available_trails[metadata["source_file_id"]]
            trail.update(metadata)
            trail_rows.append(trail)
        texture_paths = sorted({texture["texture"] for layer in rows + trail_rows for ref in layer.get("materials", [])
                                for texture in materials.get(ref["reference"], {}).get("textures", [])})
        effects[key] = {**source, "source_root": binding["source_root"], "source_root_active": binding["source_root_active"],
                        "particle_systems": len(rows), "layers": rows, "trails": trail_rows, "textures": texture_paths}
    catalog["effects"] = effects
    catalog["bindings"] = bindings
    catalog["actors"] = {str(actor_id): [key for key, value in bindings.items() if value["actor_id"] == actor_id] for actor_id in ACTORS}
    catalog["activation_events"] = events
    catalog["source"] = {"apk": str(args.apk), "apk_sha256": APK_SHA, "manifest_member": manifest_member,
                         "manifest_sha256": digest(manifest_payload), "actors": sources}
    catalog["limitations"] = [
        "Static serialized Unity hierarchy and action events, not original APK execution.",
        "Particle materials and shader behaviour are approximated by the Godot renderer.",
        "Six Unity TrailRenderer descriptors are recovered; their rendering requires Godot runtime support.",
    ]
    catalog_path.write_text(json.dumps(catalog, separators=(",", ":"), allow_nan=False) + "\n")
    print(json.dumps({"roots": len(bindings), "particles": sum(map(len, layers.values())),
                      "trails": sum(map(len, trails.values())), "activation_events": len(events)}))


if __name__ == "__main__":
    main()
