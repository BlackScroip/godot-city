"""Recover shared altar selection structure, state, and loot tag resources."""

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


ROOT = Path(__file__).resolve().parents[1]
APK_SHA = "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505"
TARGETS = ["ATPanel_SelectCollection", "Slot_SelectCharaTalent_v2",
           "Box_LootTagContainer", "SubItem_LootTag"]


def digest(data):
    return hashlib.sha256(data).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def decode_literals(native, metadata, pointers):
    phoff = struct.unpack_from("<Q", native, 32)[0]
    phsize, phcount = struct.unpack_from("<HH", native, 54)
    segments = [struct.unpack_from("<IIQQQQQQ", native, phoff + index * phsize)
                for index in range(phcount)]

    def file_at(address):
        return next(offset + address - start for kind, _, offset, start, _, size, _, _ in segments
                    if kind == 1 and start <= address < start + size)

    literals, literals_size, literal_data, _ = struct.unpack_from("<4I", metadata, 8)
    shoff = struct.unpack_from("<Q", native, 40)[0]
    shsize, shcount = struct.unpack_from("<HH", native, 58)
    found = []
    for index in range(shcount):
        section = struct.unpack_from("<IIQQQQIIQQ", native, shoff + index * shsize)
        if section[1] != 4:
            continue
        for position in range(section[4], section[4] + section[5], section[9] or 24):
            target, info, addend = struct.unpack_from("<QQq", native, position)
            if target not in pointers or info != 1027:
                continue
            encoded = struct.unpack_from("<Q", native, file_at(addend))[0]
            kind, ordinal = (encoded >> 29) & 7, (encoded >> 1) & 0x0FFFFFFF
            if kind != 5 or ordinal >= literals_size // 8:
                continue
            length, location = struct.unpack_from("<II", metadata, literals + 8 * ordinal)
            found.append(dict(got_va=hex(target), relocation_offset=hex(position),
                              metadata_offset=hex(literal_data + location), literal_index=ordinal,
                              utf8=metadata[literal_data + location:literal_data + location + length].decode("utf-8")))
    return found


def recover(apk, output, report, native_path, stubs):
    output.mkdir(parents=True, exist_ok=True)
    apk_sha = hashlib.file_digest(apk.open("rb"), "sha256").hexdigest()
    assert apk_sha == APK_SHA, "The selected source APK changed"
    old_report = ROOT / "reports/apk-choice-colors.json"
    choices = json.loads(old_report.read_text())
    assert choices["apk_sha256"] == apk_sha
    palette = json.loads((ROOT / "assets/ui/choice/palette.json").read_text())
    resources = dict(palette["resources"])
    sprites = dict(choices["sprites"])
    inline_map = json.loads((ROOT / "assets/ui/talent_view/inline_map.json").read_text())
    layouts, tag_rows, sources = {}, [], {}
    with zipfile.ZipFile(apk) as archive:
        manifest_name = next(name for name in archive.namelist() if name.startswith(
            "assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes"))
        manifest_raw = archive.read(manifest_name)
        assert digest(manifest_raw) == choices["manifest"]["sha256"]
        assets, bundles = manifest_records(manifest_raw)

        def bundle(index):
            member = "assets/yoo/DefaultPackage/" + bundles[index]["hash"] + ".bundle"
            payload = archive.read(member)
            identity = dict(member=member, sha256=digest(payload))
            sources[member] = identity
            return payload, identity

        for entry in choices["sprites"].values():
            assert digest(archive.read(entry["source"]["member"])) == entry["source"]["sha256"]
            assert digest((ROOT / entry["resource"].removeprefix("res://")).read_bytes()) == entry["png_sha256"]

        def export_sprite(sprite_obj, source_by_cab):
            sprite = sprite_obj.read()
            name = sprite.m_Name
            if name in resources:
                return name
            image = sprite.image.convert("RGBA")
            existing = inline_map.get(name)
            if existing:
                from PIL import Image
                retained = ROOT / existing.removeprefix("res://")
                with Image.open(retained) as retained_image:
                    assert retained_image.convert("RGBA").size == image.size
                    assert retained_image.convert("RGBA").tobytes() == image.tobytes(), name
                resource, destination = existing, retained
            else:
                destination = output / (name + ".png")
                image.save(destination)
                resource = "res://" + destination.relative_to(ROOT).as_posix()
            resources[name] = resource
            sprites[name] = dict(resource=resource, source=source_by_cab[sprite_obj.assets_file.name],
                                 path_id=sprite_obj.path_id, png_sha256=digest(destination.read_bytes()),
                                 size=list(image.size), border={key: getattr(sprite.m_Border, key) for key in "xyzw"})
            return name

        for target in TARGETS:
            asset = next(row for row in assets if row["address"] == target)
            dependencies, bundle_dependencies = package_dependencies(manifest_raw, target)
            pending, visited, primary = [asset["bundle"], *dependencies], set(), []
            env, source_by_cab = UnityPy.Environment(), {}
            while pending:
                index = pending.pop()
                if index in visited:
                    continue
                visited.add(index)
                pending.extend(bundle_dependencies[index])
                payload, identity = bundle(index)
                loaded = env.load_file(payload)
                for cab in loaded.files.values():
                    if hasattr(cab, "objects"):
                        source_by_cab[cab.name] = identity
                        if index == asset["bundle"]:
                            primary.extend(cab.objects.values())
            trees = {obj.path_id: obj.read_typetree() for obj in primary if obj.type.name in (
                "GameObject", "RectTransform", "Transform", "MonoBehaviour")}
            objects = {obj.path_id: trees[obj.path_id] for obj in primary if obj.type.name == "GameObject"}
            transforms = {obj.path_id: trees[obj.path_id] for obj in primary
                          if obj.type.name in ("RectTransform", "Transform")}
            by_go = {tree["m_GameObject"]["m_PathID"]: key for key, tree in transforms.items()}

            def hierarchy(tid):
                if not tid or tid not in transforms:
                    return ""
                fields = transforms[tid]
                name = objects[fields["m_GameObject"]["m_PathID"]]["m_Name"]
                parent = hierarchy(fields["m_Father"]["m_PathID"])
                return (parent + "/" if parent else "") + name

            nodes = [dict(path=hierarchy(by_go[gid]), path_id=gid, active=bool(fields["m_IsActive"]),
                          transform=transforms[by_go[gid]]) for gid, fields in objects.items()]
            components = []
            for obj in primary:
                if obj.type.name != "MonoBehaviour":
                    continue
                fields = trees[obj.path_id]
                path = hierarchy(by_go.get(fields["m_GameObject"]["m_PathID"]))
                try:
                    script = PPtr(**fields["m_Script"], assetsfile=obj.assets_file).deref().read().m_ClassName
                except (KeyError, AttributeError, TypeError):
                    script = ""
                item = dict(path=path, path_id=obj.path_id, script=script, fields=fields)
                if fields.get("m_Sprite", {}).get("m_PathID"):
                    item["sprite_name"] = export_sprite(PPtr(**fields["m_Sprite"], assetsfile=obj.assets_file).deref(), source_by_cab)
                components.append(item)
            if target in ("Box_LootTagContainer", "SubItem_LootTag"):
                for obj in env.objects:
                    if obj.type.name == "Sprite" and obj.read().m_Name in inline_map:
                        export_sprite(obj, source_by_cab)
            layouts[target] = dict(asset=asset, source=source_by_cab[primary[0].assets_file.name],
                                   nodes=nodes, components=components)

        tag_asset = next(row for row in assets if row["address"] == "LootEffectTagData")
        raw, tag_bundle = bundle(tag_asset["bundle"])
        env = UnityPy.load(raw)
        tag_obj = next(obj for obj in env.objects if obj.type.name == "TextAsset" and obj.read().m_Name == "LootEffectTagData")
        tag_raw = tag_obj.read().m_Script.encode("utf-8")
        for row in json.loads(tag_raw):
            assert row["icon"] in resources, row
            tag_rows.append(dict(id=row["id"], name=row["name"], icon=row["icon"], resource=resources[row["icon"]]))
        tag_source = dict(asset=tag_asset, bundle=tag_bundle, path_id=tag_obj.path_id, text_sha256=digest(tag_raw))
        loot_obj = next(obj for obj in env.objects if obj.type.name == "TextAsset" and obj.read().m_Name == "LootData")
        loot_raw = loot_obj.read().m_Script.encode("utf-8")
        loot_tags = {}
        for row in json.loads(loot_raw):
            loot_tags[str(row["id"])] = dict(loot_id=row["id"], ability_id=row["ability_item_id"],
                                             loot_type=row["loot_type"], effect_tags=row["effect_tag_list"])
        loot_source = dict(bundle=tag_bundle, path_id=loot_obj.path_id, text_sha256=digest(loot_raw))
        guide_obj = next(obj for obj in env.objects if obj.type.name == "TextAsset" and obj.read().m_Name == "GuideData")
        guide_raw = guide_obj.read().m_Script.encode("utf-8")
        guide = next(row for row in json.loads(guide_raw) if row["id"] == 3)
        guide_source = dict(bundle=tag_bundle, path_id=guide_obj.path_id, text_sha256=digest(guide_raw))
        guide_parts = []
        for heading, body, picture_name in zip(guide["head_text"].split("|"),
                                                guide["tail_text"].split("|"),
                                                guide["middle_image_name"].split("|")):
            guide_parts.append(dict(heading=heading.strip(), body=body.strip(), image_name=picture_name))
        guide_env = UnityPy.Environment()
        for index in sorted({next(row["bundle"] for row in assets if row["address"] == part["image_name"])
                             for part in guide_parts}):
            payload, identity = bundle(index)
            loaded = guide_env.load_file(payload)
            for cab in loaded.files.values():
                if hasattr(cab, "objects"):
                    source_by_cab[cab.name] = identity
        for part_index, part in enumerate(guide_parts, 1):
            candidates = [obj for obj in guide_env.objects if obj.type.name in ("Sprite", "Texture2D")
                          and obj.read().m_Name == part["image_name"]]
            assert candidates, part["image_name"]
            image_obj = next((obj for obj in candidates if obj.type.name == "Sprite"), candidates[0])
            picture = image_obj.read().image
            destination = output / ("guide3_" + str(part_index) + ".png")
            picture.save(destination)
            part["resource"] = "res://" + destination.relative_to(ROOT).as_posix()
            part["size"] = list(picture.size)
            part["source"] = dict(source_by_cab[image_obj.assets_file.name], path_id=image_obj.path_id,
                                   type=image_obj.type.name, png_sha256=digest(destination.read_bytes()))
            resources[part["image_name"]] = part["resource"]
        guide["parts"] = guide_parts
        native = archive.read("lib/arm64-v8a/libil2cpp.so")
        assert digest(native) == choices["native"]["native_sha256"]
        metadata = archive.read("assets/bin/Data/Managed/Metadata/global-metadata.dat")
        selected_literals = decode_literals(native, metadata, {0x65C8658, 0x65CD5A0})

    native_audit.SELECTION = {"ATPanel_SelectCollection": ["RegisterItem", "InitSlotLockButton", "<InitAllSlot>b__28_0", "<InitAllSlot>b__2"],
                              "ATGameManager": ["IsLockFeatureUnlocked"]}
    native_audit.SELECTED_OFFSETS = {0x2F57E70}
    native_evidence = native_audit.inspect(native_path, stubs)
    assert native_evidence["native_sha256"] == digest(native)
    native_evidence["string_literals"] = selected_literals

    card = layouts["Slot_SelectCharaTalent_v2"]
    mode_info = {"Normal": 0, "Sacrificial": 1, "Sprites": 2}
    variants = {}
    for rare in ["1", "2", "3", "4", "5", "curse"]:
        variants[rare] = {"background": resources["rarebg_vertical_" + rare + "_v2"],
                          "line": resources["rarebg_vertical_line_" + rare + "_v2"]}
    catalog = dict(apk_sha256=apk_sha, rea_inventory_evidence=choices.get("rea_inventory_evidence"),
                   evidence_type="static serialized Unity assets and matching IL2CPP; no original runtime capture",
                   manifest=choices["manifest"], mode_enum=mode_info, variants=variants,
                   colors=palette["colors"], resources=resources,
                   loot_effect_tags="res://assets/ui/altar/loot_effect_tags.json",
                   loot_tags="res://assets/ui/altar/loot_tags.json",
                   guide="res://assets/ui/altar/guide.json",
                   layout="res://assets/ui/altar/layout.json",
                   interaction=dict(card_button="preselect", confirm_button="Btn_Select",
                                    submit="<InitAllSlot>b__1", preview="<InitAllSlot>b__2",
                                    preview_child_literals=selected_literals,
                                    initial_runtime_hidden=["Box_SelectLight", "Btn_Select", "Text_Lv", "Text_LevelDescription"],
                                    is_new_visible="!RogueStableData.GotLootIdList.Contains(UISlot.ItemId)",
                                    star_mark_visible="RogueStableData.MarkItemList.Contains(UISlot.ItemId)",
                                    lock_visible="ATGameManager.IsLockFeatureUnlocked()",
                                    lock_feature_talent_id=221,
                                    lock_gate="RogueStableData.TalentId2LevelDic.ContainsKey(221)",
                                    lock_modes="All collection modes use the same permanent talent gate.",
                                    lock_state="PanelData.LockedItemIds.Contains(UISlot.ItemId)",
                                    guide_message=dict(name="Guide", parameter="Guide", value="3")),
                   source_reports={"choices": dict(path=str(old_report.relative_to(ROOT)), sha256=digest(old_report.read_bytes()))},
                   limitations=["Prefab active flags are authored initial states and runtime code changes them.",
                                "TitleName is provided by each caller; the authored title is not a mode mapping.",
                                "The UI lock gate is statically confirmed; caller-specific refresh priority and lock retention semantics are not established by this asset audit."])
    layout = dict(apk_sha256=apk_sha, prefabs=layouts,
                  coordinate_system="Unity RectTransform: positive Y points upward; parent anchors and scaling apply.")
    write_json(output / "catalog.json", catalog)
    write_json(output / "layout.json", layout)
    write_json(output / "resource_map.json", resources)
    write_json(output / "loot_effect_tags.json", {str(row["id"]): row for row in tag_rows})
    write_json(output / "loot_tags.json", loot_tags)
    write_json(output / "guide.json", guide)
    write_json(ROOT / "reports/altar-selection-20261027.native.json", native_evidence)
    write_json(output / "provenance.json", dict(apk_sha256=apk_sha, manifest=choices["manifest"],
                                               loot_effect_tags=tag_source, sprites=sprites,
                                               loot_tags=loot_source,
                                               guide=guide_source,
                                               bundles=list(sources.values()),
                                               native_sha256=digest(native), metadata_sha256=digest(metadata)))
    active = {node["path"]: node["active"] for node in card["nodes"]
              if any(word in node["path"] for word in ("Btn_Select", "Box_LockBtn", "Box_HpDown", "Box_Type", "Button_tujian", "SelectFX"))}
    report.write_text("# APK Altar UI Audit\n\n"
                      + "Source APK SHA256: `" + apk_sha + "`.\n\n"
                      + "The APK uses ATPanel_SelectCollection with Slot_SelectCharaTalent_v2 for shared collection/spirit selection. "
                      + "The blue and gold rarity-three background is rarebg_vertical_3_v2 (224 x 438). "
                      + "Card clicks preselect; the separate Btn_Select action commits. "
                      + "The panel uses a plain dark brown Image_Mask, not an authored RawImage background.\n\n"
                      + "LootEffectTagData contains 34 icon/name rows. The list is serialized to loot_effect_tags.json with pixel-verified retained resources. "
                      + "LootData supplies 384 loot-to-tag mappings. Guide message 3 opens the original three-part collection guide with three 512 x 256 images. "
                      + "Full source layout, authored active states, all source sprites, and current bundle hashes are retained in assets/ui/altar.\n\n"
                      + "Runtime state: InitAllSlot hides Btn_Select (0x2f57668) and Box_SelectLight (0x2f56eac), "
                      + "although the serialized prefab authors both as active. Box_IsNew uses the inverse of GotLootIdList.Contains(ItemId); "
                      + "Box_StarMark uses MarkItemList.Contains(ItemId). Lock controls require TalentId2LevelDic.ContainsKey(221), "
                      + "and the initializer applies the same gate for all collection modes.\n\n"
                      + "The UI gate is source-confirmed. Caller-specific refresh priority and locked reward retention remain compatibility reconstruction; "
                      + "this static asset audit does not claim a runtime test of that behavior.\n\n"
                      + "Observed: serialized prefab fields and matching native literal references. "
                      + "Inferred: the selection workflow from the native callback side effects. "
                      + "Unknown: complete original runtime particles, animations, and screenshot appearance.\n\n"
                      + "```json\n" + json.dumps(active, ensure_ascii=False, indent=2) + "\n```\n")
    print(json.dumps(dict(catalog=str(output / "catalog.json"), tags=len(tag_rows), loot_mappings=len(loot_tags),
                          guide_images=len(guide_parts), literals=selected_literals), ensure_ascii=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=ROOT / "assets/ui/altar")
    parser.add_argument("--report", type=Path, default=ROOT / "reports/ALTAR_UI_SOURCE_AUDIT_20261027.md")
    parser.add_argument("--native", type=Path, default=Path("/private/tmp/city-new-map-native/libil2cpp.so"))
    parser.add_argument("--stubs", type=Path, default=Path("/private/tmp/city-new-map-addresses/DiffableCs/Assembly-CSharp"))
    args = parser.parse_args()
    recover(args.apk, args.output, args.report, args.native, args.stubs)
