"""Recover choice-card color/texture evidence directly from a supplied APK."""

import argparse
import hashlib
import json
from pathlib import Path
import struct
import zipfile

import UnityPy
from UnityPy.classes.PPtr import PPtr

from inspect_camp_progression import manifest_records
from recover_route_art import package_dependencies
import inspect_new_camp_native as native_audit


TARGETS = [
    "ATPanel_SelectCharaTalent", "Slot_SelectCharaTalent_v2",
    "Slot_SelectCharaTalent", "ATPanel_SelectCollection", "ATSlot_Item_Square",
]


def digest(payload):
    return hashlib.sha256(payload).hexdigest()


def native_evidence(archive, native_path, stubs):
    data = native_path.read_bytes()
    if data != archive.read("lib/arm64-v8a/libil2cpp.so"):
        raise ValueError("Native image must match the supplied APK")
    metadata = archive.read("assets/bin/Data/Managed/Metadata/global-metadata.dat")
    native_audit.SELECTION = {
        "ATPanel_SelectCharaTalent": ["<InitAllSlot>b__23_0"],
        "ATPanel_SelectCollection": ["<InitAllSlot>b__28_0"],
        "UIHelper_ProjectAT": ["GetCardRareBg", "GetCardRareFg", "GetCardRareLine"],
        "UIOpener_Rogue": ["<OpenSelectCharTalentPanel>b__3_0"],
        "CharacterTalentData": ["GetStarNum"],
    }
    native_audit.SELECTED_OFFSETS = set()
    evidence = native_audit.inspect(native_path, stubs)
    evidence["metadata_sha256"] = digest(metadata)
    evidence["stub_sha256"] = {str(path.relative_to(stubs)): digest(path.read_bytes())
                               for path in sorted({Path(method["stub"]) for method in evidence["methods"]})}
    phoff = struct.unpack_from("<Q", data, 32)[0]
    phsize, phcount = struct.unpack_from("<HH", data, 54)
    segments = [struct.unpack_from("<IIQQQQQQ", data, phoff + index * phsize) for index in range(phcount)]

    def file_at(va):
        return next(offset + va - start for kind, _, offset, start, _, size, _, _ in segments
                    if kind == 1 and start <= va < start + size)

    pointers = {0x65CF820, 0x65CF828, 0x65CF830, 0x65CF838, 0x65CF840, 0x65CF848, 0x65CF850, 0x65CF858}
    shoff = struct.unpack_from("<Q", data, 40)[0]
    shsize, shcount = struct.unpack_from("<HH", data, 58)
    literals, literals_size, literal_data, _ = struct.unpack_from("<4I", metadata, 8)
    references = []
    for index in range(shcount):
        section = struct.unpack_from("<IIQQQQIIQQ", data, shoff + index * shsize)
        if section[1] != 4:
            continue
        for position in range(section[4], section[4] + section[5], section[9] or 24):
            target, info, addend = struct.unpack_from("<QQq", data, position)
            if target not in pointers or info != 1027:
                continue
            encoded = struct.unpack_from("<Q", data, file_at(addend))[0]
            usage_kind, ordinal = (encoded >> 29) & 7, (encoded >> 1) & 0x0FFFFFFF
            if usage_kind != 5 or ordinal >= literals_size // 8:
                continue
            entry = literals + 8 * ordinal
            length, location = struct.unpack_from("<II", metadata, entry)
            references.append({"got_va": hex(target), "relocation_offset": hex(position),
                               "carrier_va": hex(addend), "encoded": hex(encoded), "literal_index": ordinal,
                               "metadata_offset": hex(literal_data + location),
                               "utf8": metadata[literal_data + location:literal_data + location + length].decode("utf-8")})
    evidence["sprite_name_literals"] = references
    return evidence


def recover(apk, report, output, native_path, stubs, rea_evidence):
    output.mkdir(parents=True, exist_ok=True)
    evidence = {"apk_sha256": hashlib.file_digest(apk.open("rb"), "sha256").hexdigest(),
                "evidence_type": "static Unity serialized prefab fields and extracted sprites; no APK runtime observation",
                "rea_inventory_evidence": rea_evidence, "prefabs": {}, "sprites": {}}
    with zipfile.ZipFile(apk) as archive:
        manifest_name = next(name for name in archive.namelist() if name.startswith(
            "assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes"))
        manifest = archive.read(manifest_name)
        evidence["manifest"] = {"member": manifest_name, "sha256": digest(manifest)}
        assets, bundles = manifest_records(manifest)
        evidence["native"] = native_evidence(archive, native_path, stubs)
        for target in TARGETS:
            selected = next(asset for asset in assets if asset["address"] == target)
            dependencies, bundle_dependencies = package_dependencies(manifest, target)
            pending, loaded_indices, primary = [selected["bundle"], *dependencies], set(), []
            environment, sources = UnityPy.Environment(), {}
            while pending:
                index = pending.pop()
                if index in loaded_indices:
                    continue
                loaded_indices.add(index)
                pending.extend(bundle_dependencies[index])
                member = "assets/yoo/DefaultPackage/" + bundles[index]["hash"] + ".bundle"
                payload = archive.read(member)
                loaded = environment.load_file(payload)
                for cab in loaded.files.values():
                    if hasattr(cab, "objects"):
                        sources[cab.name] = {"member": member, "sha256": digest(payload)}
                        if index == selected["bundle"]:
                            primary.extend(cab.objects.values())

            def dereference(pointer, owner):
                return PPtr(**pointer, assetsfile=owner.assets_file).deref()

            def export_sprite(sprite_obj):
                sprite = sprite_obj.read()
                if sprite.m_Name in evidence["sprites"]:
                    return sprite.m_Name
                filename = digest(sprite.m_Name.encode("utf-8"))[:16] + ".png"
                sprite.image.save(output / filename)
                evidence["sprites"][sprite.m_Name] = {
                    "resource": "res://assets/ui/choice/" + filename,
                    "source": sources.get(sprite_obj.assets_file.name), "path_id": sprite_obj.path_id,
                    "png_sha256": digest((output / filename).read_bytes()),
                    "size": list(sprite.image.size),
                    "border": {key: getattr(sprite.m_Border, key) for key in "xyzw"},
                }
                return sprite.m_Name

            transforms = {obj.path_id: obj.read_typetree() for obj in primary
                          if obj.type.name in ("Transform", "RectTransform")}
            objects = {obj.path_id: obj.read_typetree() for obj in primary if obj.type.name == "GameObject"}
            by_game_object = {tree["m_GameObject"]["m_PathID"]: key for key, tree in transforms.items()}

            def hierarchy(transform_id):
                if not transform_id or transform_id not in transforms:
                    return ""
                tree = transforms[transform_id]
                parent = hierarchy(tree["m_Father"]["m_PathID"])
                return (parent + "/" if parent else "") + objects[tree["m_GameObject"]["m_PathID"]]["m_Name"]

            components = []
            for obj in primary:
                if obj.type.name != "MonoBehaviour":
                    continue
                tree = obj.read_typetree()
                try:
                    script = dereference(tree["m_Script"], obj).read().m_ClassName
                except (KeyError, AttributeError, TypeError):
                    script = ""
                item = {"path_id": obj.path_id,
                        "path": hierarchy(by_game_object.get(tree["m_GameObject"]["m_PathID"])),
                        "script": script, "fields": tree}
                material_pointer = tree.get("m_sharedMaterial")
                if material_pointer and material_pointer["m_PathID"]:
                    material_obj = dereference(material_pointer, obj)
                    item["font_material"] = {"source": sources.get(material_obj.assets_file.name),
                                             "path_id": material_obj.path_id, "fields": material_obj.read_typetree()}
                sprite_pointer = tree.get("m_Sprite")
                if sprite_pointer and sprite_pointer["m_PathID"]:
                    sprite_obj = dereference(sprite_pointer, obj)
                    item["sprite_name"] = export_sprite(sprite_obj)
                components.append(item)
            for obj in environment.objects:
                if obj.type.name == "Sprite" and obj.read().m_Name.startswith(("rarebg_vertical_", "slotfg_rare_square_")):
                    export_sprite(obj)
            evidence["prefabs"][target] = {
                "asset": selected, "source": sources[primary[0].assets_file.name], "components": components,
                "transforms": [{"path": hierarchy(key), "fields": tree} for key, tree in transforms.items()],
            }
    components = evidence["prefabs"]["Slot_SelectCharaTalent_v2"]["components"]

    def color(suffix, field="m_fontColor"):
        tree = next(item["fields"] for item in components if item["path"].endswith(suffix) and field in item["fields"])
        return [tree[field][key] for key in "rgba"]

    settings = {"apk_sha256": evidence["apk_sha256"], "resources": {
        name: entry["resource"] for name, entry in evidence["sprites"].items()},
        "colors": {"title": color("/Text_Name"), "effect": color("/Text_EffectDescription"),
                   "level_description": color("/Text_LevelDescription"), "level": color("/Text_Lv"),
                   "choose": color("/Text_Select"), "background_tint": color("/Image_Bg", "m_Color")},
    }
    collection = next(item["fields"] for item in evidence["prefabs"]["ATPanel_SelectCollection"]["components"]
                      if item["script"] == "ATPanel_SelectCollection")
    for field in ("curse_title_color", "curse_desc_color"):
        settings["colors"][field] = [collection[field][key] for key in "rgba"]
    settings["button_colors"] = next(item["fields"]["m_Colors"] for item in components
                                     if item["path"].endswith("/Btn_Select") and item["script"] == "Button")
    settings["button_transition"] = next(item["fields"]["m_Transition"] for item in components
                                         if item["path"].endswith("/Btn_Select") and item["script"] == "Button")
    settings["text_materials"] = {suffix: next(item["font_material"]["fields"]["m_SavedProperties"]
        for item in components if item["path"].endswith("/" + suffix) and "font_material" in item)
        for suffix in ("Text_Name", "Text_EffectDescription", "Text_LevelDescription", "Text_Lv", "Text_Select")}
    (output / "palette.json").write_text(json.dumps(settings, ensure_ascii=False, indent=2) + "\n")
    report.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"report": str(report), "sprites": len(evidence["sprites"]),
                      "prefabs": list(evidence["prefabs"])}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--native", type=Path, required=True)
    parser.add_argument("--stubs", type=Path, required=True)
    parser.add_argument("--rea-inventory-evidence", required=True)
    args = parser.parse_args()
    recover(args.apk, args.report, args.output, args.native, args.stubs, args.rea_inventory_evidence)
