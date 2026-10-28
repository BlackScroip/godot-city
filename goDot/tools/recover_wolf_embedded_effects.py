#!/usr/bin/env python3
"""Recover the wolf's bone-attached rage particles from the exact source APK."""

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
NAMES = (
    "24041201_fx_enemy_senlinlangwang_buff_hair",
    "24041201_fx_enemy_senlinlangwang_buff_tail",
)


def inspect(apk, actor):
    with apk.open("rb") as stream:
        if hashlib.file_digest(stream, "sha256").hexdigest() != APK_SHA:
            raise ValueError("This recovery requires the user-selected 1061664.apk")
    actor_data = actor.read_bytes()
    chunk_length, chunk_type = struct.unpack_from("<II", actor_data, 12)
    if chunk_type != 0x4E4F534A:
        raise ValueError("Actor GLB has no leading JSON chunk")
    gltf = json.loads(actor_data[20:20 + chunk_length])
    joint_names = {gltf["nodes"][index]["name"] for skin in gltf["skins"] for index in skin["joints"]}
    with zipfile.ZipFile(apk) as archive:
        member = next(name for name in archive.namelist() if name.startswith(
            "assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes"))
        payload = archive.read(member)
        manifest = package_manifest(payload)
        asset = next(row for row in manifest["assets"] if row["address"].lower() == "monster_senlinlangwang")
        bundle_member = "assets/yoo/DefaultPackage/" + manifest["bundles"][asset["bundle"]]["hash"] + ".bundle"
        bundle_payload = archive.read(bundle_member)
    env = UnityPy.load(bundle_payload)
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
        name = obj.assets_file.name if not file_id else obj.assets_file.externals[file_id - 1].path.rsplit("/", 1)[-1]
        return objects.get((name, ref["m_PathID"]))

    def components(go):
        found = [resolve(go, row.get("component", row)) for row in tree(go).get("m_Component", [])]
        return {obj.type.name: obj for obj in found if obj is not None}

    def trs(transform):
        data = tree(transform)
        return {"position": data["m_LocalPosition"], "rotation": data["m_LocalRotation"], "scale": data["m_LocalScale"]}

    bindings, active_layers, source_layers = {}, {}, {}
    for name in NAMES:
        matches = [obj for obj in env.objects if obj.type.name == "GameObject" and tree(obj).get("m_Name") == name]
        if len(matches) != 1:
            raise ValueError("Expected one embedded root: " + name)
        go = matches[0]
        transform = components(go)["Transform"]
        parent = resolve(transform, tree(transform).get("m_Father"))
        chain, hierarchy = [], [name]
        while parent is not None:
            parent_go = resolve(parent, tree(parent).get("m_GameObject"))
            parent_name = tree(parent_go).get("m_Name", "")
            hierarchy.insert(0, parent_name)
            if parent_name in joint_names:
                break
            chain.insert(0, trs(parent))
            parent = resolve(parent, tree(parent).get("m_Father"))
        if parent is None:
            raise ValueError("Embedded effect has no imported bone anchor: " + name)
        bindings[name] = {
            "bone": parent_name,
            "parent_transform_chain": chain,
            "effect_root_transform": trs(transform),
            "source_root_active": bool(tree(go).get("m_IsActive", True)),
            "source_hierarchy_from_bone": hierarchy,
            "source_root": "%s:%s" % (go.assets_file.name, go.path_id),
            "source_transform": "%s:%s" % (transform.assets_file.name, transform.path_id),
        }
        active_layers[name] = {}
        source_layers[name] = {}

        def walk(child, inherited, is_root=False):
            data = tree(child)
            active = inherited and (is_root or bool(data.get("m_IsActive", True)))
            by_type = components(child)
            if "ParticleSystem" in by_type:
                ident = str(by_type["ParticleSystem"].path_id)
                active_layers[name][ident] = active
                source_layers[name][ident] = {"scaling_mode": tree(by_type["ParticleSystem"]).get("scalingMode"),
                    "renderer": tree(by_type.get("ParticleSystemRenderer"))}
            transform = by_type.get("Transform")
            for child_ref in tree(transform).get("m_Children", []):
                child_transform = resolve(transform, child_ref)
                walk(resolve(child_transform, tree(child_transform).get("m_GameObject")), active)

        walk(go, True, True)
    source = {
        "apk": str(apk), "apk_sha256": APK_SHA,
        "manifest_member": member, "manifest_sha256": hashlib.sha256(payload).hexdigest(),
        "source_asset": asset["path"], "bundle_member": bundle_member,
        "bundle_sha256": hashlib.sha256(bundle_payload).hexdigest(),
        "actor_glb": str(actor), "actor_glb_sha256": hashlib.sha256(actor_data).hexdigest(),
        "evidence_type": "Static packaged Unity hierarchy, particles, materials and textures; no APK runtime observation",
    }
    # Reuse the existing format-aware exporter with exact embedded roots.
    manifest["assets"] = [dict(asset, address=name, subroot=name) for name in NAMES]
    return manifest, bindings, active_layers, source_layers, source


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, default=ROOT / "1061664.apk")
    parser.add_argument("--actor", type=Path, default=ROOT / "goDot/assets/enemies/enemy_13001.glb")
    parser.add_argument("--output", type=Path, default=ROOT / "goDot/assets/combat_presentation/wolf_embedded")
    parser.add_argument("--report", type=Path, default=ROOT / "goDot/reports/wolf-embedded-effects-source.json")
    args = parser.parse_args()
    manifest, bindings, active_layers, source_layers, source = inspect(args.apk, args.actor)
    args.output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="city-wolf-embedded-") as directory:
        folder = Path(directory)
        manifest_path, selection_path = folder / "manifest.json", folder / "selected.json"
        manifest_path.write_text(json.dumps(manifest))
        selection_path.write_text(json.dumps(list(NAMES)))
        subprocess.run([sys.executable, str(Path(__file__).with_name("export_environment_effects.py")),
            "--apk", str(args.apk), "--manifest", str(manifest_path), "--asset-list", str(selection_path),
            "--output-directory", str(args.output), "--shared-materials", "--include-root-transform",
            "--report", str(args.report)], check=True)
    catalog_path = args.output / "catalog.json"
    catalog = json.loads(catalog_path.read_text())
    for name in NAMES:
        effect = catalog["effects"][name]
        effect["source_root_active"] = bindings[name]["source_root_active"]
        effect["activation"] = "Buff activates the existing embedded root; descendants retain authored active states"
        for layer in effect["layers"]:
            layer["source_active_with_root"] = layer["active"]
            layer["active"] = active_layers[name][layer["source_file_id"]]
            metadata = source_layers[name][layer["source_file_id"]]
            layer["scaling_mode"] = metadata["scaling_mode"]
            for field, source_field in (
                ("camera_velocity_scale", "m_CameraVelocityScale"),
                ("freeform_stretching", "m_FreeformStretching"),
                ("rotate_with_stretch_direction", "m_RotateWithStretchDirection"),
                ("sorting_order", "m_SortingOrder"),
                ("min_particle_size", "m_MinParticleSize"),
                ("max_particle_size", "m_MaxParticleSize"),
                ("pivot", "m_Pivot"),
            ):
                layer["renderer"][field] = metadata["renderer"].get(source_field)
    catalog["bindings"] = bindings
    catalog["source"] = source
    catalog["coordinate_convention"] = "Native numeric Unity XYZ; layer chains include effect-root TRS and exclude ancestor bones. Apply binding parent_transform_chain after bone anchor."
    catalog_path.write_text(json.dumps(catalog, separators=(",", ":")) + "\n")
    report = json.loads(args.report.read_text())
    report["source"] = source
    report["bindings"] = bindings
    report["active_layers"] = active_layers
    report["source_layers"] = source_layers
    report["rea_evidence_ids"] = [
        "ev_a8896527552ba1a1db7688a7924f0bdb5216151e2794890521df7f2a19f75e9c",
        "ev_89b63e484acc2e54de490487bd1b9889d08f547cd7c8ac0c50d782ab1acf0323",
    ]
    report["limitations"].append("REA IDs identify the APK inventory and inspection; this report adds exact format-aware resource extraction bound to that APK SHA-256.")
    args.report.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"effects": {name: {"bone": bindings[name]["bone"], "layers": len(catalog["effects"][name]["layers"])} for name in NAMES}, "errors": report["errors"]}))


if __name__ == "__main__":
    main()
