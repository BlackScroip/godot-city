"""Recover missing public awakening and Petra token sprites from audited APK 1061664."""

import argparse
import hashlib
import json
from pathlib import Path
import zipfile

import UnityPy

from inspect_camp_progression import Reader, manifest_records


ROOT = Path(__file__).resolve().parents[1]
APK_SHA256 = "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def addressed_dependencies(payload):
    reader = Reader(payload)
    reader.number("I")
    reader.string()
    for _ in range(3):
        reader.number("B")
    for _ in range(2):
        reader.number("i")
    for _ in range(4):
        reader.string()
    result = {}
    for _ in range(reader.number("i")):
        address, path, _ = [reader.string() for _ in range(3)]
        reader.array(reader.string)
        bundle = reader.number("i")
        dependencies = reader.array(lambda: reader.number("i"))
        result[address] = {"path": path, "bundle": bundle, "dependencies": dependencies}
    return result


def recover(apk, output):
    with apk.open("rb") as stream:
        apk_digest = hashlib.file_digest(stream, "sha256").hexdigest()
    if apk_digest != APK_SHA256:
        raise ValueError("Expected the audited 1061664.apk; refusing to mix package versions")
    base_icons = json.loads((ROOT / "assets/ui/resource_map.json").read_text())
    target = output / "awakening"
    target.mkdir(parents=True, exist_ok=True)
    config_sources, configs, sources, missing = {}, {}, {}, []
    environment = UnityPy.Environment()
    with zipfile.ZipFile(apk) as archive:
        manifest_name = next(name for name in archive.namelist() if name.startswith(
            "assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes"))
        manifest = archive.read(manifest_name)
        _, bundles = manifest_records(manifest)
        lookup = addressed_dependencies(manifest)

        def member(index):
            return "assets/yoo/DefaultPackage/" + bundles[index]["hash"] + ".bundle"

        for name in ["CharaTalentAwakeTreeData", "RelationshipTokenData"]:
            asset = lookup[name]
            bundle_member = member(asset["bundle"])
            payload = archive.read(bundle_member)
            obj = next(obj for obj in UnityPy.load(payload).objects
                       if obj.type.name == "TextAsset" and obj.peek_name() == name)
            text = obj.read().m_Script
            if isinstance(text, bytes):
                text = text.decode("utf-8-sig")
            configs[name] = json.loads(text)
            config_sources[name] = {"asset": asset["path"], "member": bundle_member,
                                    "bundle_sha256": sha(payload), "path_id": str(obj.path_id),
                                    "text_sha256": sha(text.encode("utf-8"))}

        public_nodes = [row for row in configs["CharaTalentAwakeTreeData"]
                        if not row.get("is_admin_mode", False) and row.get("is_enabled", True)]
        wanted = {row["icon_name"] for row in public_nodes if row["icon_name"] not in base_icons}
        wanted.update(row["icon_name"] for row in configs["RelationshipTokenData"]
                      if int(row["material_id"]) == 50081)
        selected = {name: lookup[name] for name in wanted if name in lookup}
        missing.extend({"name": name, "reason": "absent from package address manifest"}
                       for name in sorted(wanted - selected.keys()))
        indices = {index for asset in selected.values()
                   for index in [asset["bundle"], *asset["dependencies"]]}
        for index in sorted(indices):
            bundle_member = member(index)
            payload = archive.read(bundle_member)
            loaded = environment.load_file(payload)
            for cab in loaded.files.values():
                if hasattr(cab, "objects"):
                    sources[cab.name] = {"member": bundle_member, "bundle_sha256": sha(payload)}

        sprites = {}
        for obj in environment.objects:
            if obj.type.name != "Sprite" or obj.peek_name() not in selected:
                continue
            name = obj.peek_name()
            source = sources[obj.assets_file.name]
            if source["member"] == member(selected[name]["bundle"]):
                if name in sprites:
                    raise ValueError("Ambiguous addressed Sprite: " + name)
                sprites[name] = obj

        mapping, records = {}, []
        for name in sorted(selected):
            if name not in sprites:
                missing.append({"name": name, "reason": "addressed bundle contains no matching Sprite"})
                continue
            obj = sprites[name]
            try:
                image = obj.read().image.convert("RGBA")
            except Exception as error:
                missing.append({"name": name, "reason": "Sprite decode failed: " + str(error)})
                continue
            bounds = image.getchannel("A").getbbox()
            if bounds is None:
                missing.append({"name": name, "reason": "decoded Sprite is fully transparent"})
                continue
            folder = "awakening" if name.startswith("sprite_awake_") else "relationship_tokens"
            destination = output / folder / (name + ".png")
            destination.parent.mkdir(parents=True, exist_ok=True)
            image.save(destination)
            resource = "res://" + destination.relative_to(ROOT).as_posix()
            mapping[name] = resource
            records.append({"name": name, "path": resource, "source_asset": selected[name]["path"],
                            "source": sources[obj.assets_file.name], "sprite_path_id": str(obj.path_id),
                            "width": image.width, "height": image.height, "alpha_bounds": bounds,
                            "rgba_sha256": sha(image.tobytes()), "png_sha256": sha(destination.read_bytes())})

    map_path = output / "resource_map.json"
    all_mapping = json.loads(map_path.read_text()) if map_path.exists() else {}
    for name, path in mapping.items():
        if name in all_mapping and all_mapping[name] != path:
            raise ValueError("Refusing to replace an existing different sprite mapping: " + name)
        all_mapping[name] = path
    map_path.write_text(json.dumps(all_mapping, indent=2) + "\n")
    (target / "resource_map.json").write_text(json.dumps(mapping, indent=2) + "\n")
    report = {"apk": str(apk.resolve()), "apk_sha256": apk_digest,
              "manifest": {"member": manifest_name, "sha256": sha(manifest)},
              "config_sources": config_sources, "public_awakening_nodes": len(public_nodes),
              "requested_names": sorted(wanted), "sprites": records, "missing": missing,
              "limits": "Static addressed Sprite decoding from the verified APK. No generated or redrawn pixels, target execution, or visual/runtime parity claim."}
    (target / "provenance.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"requested": len(wanted), "recovered": len(records), "missing": missing,
                      "provenance": str(target / "provenance.json")}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=ROOT / "assets/ui/camp")
    args = parser.parse_args()
    recover(args.apk, args.output)
