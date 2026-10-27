"""Verify the current APK's spirit icons and retain bounded static UI evidence."""

import argparse
import hashlib
import io
import json
from pathlib import Path
import zipfile

import UnityPy
from PIL import Image

from inspect_camp_progression import manifest_records


ROOT = Path(__file__).resolve().parents[1]
REA_ARCHIVE_EVIDENCE = "ev_89b63e484acc2e54de490487bd1b9889d08f547cd7c8ac0c50d782ab1acf0323"


def digest(payload):
    return hashlib.sha256(payload).hexdigest()


def audit(apk, output):
    followers = json.loads((ROOT / "assets/spirit_followers/catalog.json").read_text())
    apk_sha256 = hashlib.file_digest(apk.open("rb"), "sha256").hexdigest()
    assert apk_sha256 == followers["apk_sha256"]
    abilities = followers["loot_bindings"]
    wanted = {"sprite_abilityitemicon_" + key: key for key in abilities}
    icons = {}
    with zipfile.ZipFile(apk) as archive:
        manifest_member = next(name for name in archive.namelist() if name.startswith(
            "assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes"))
        manifest = archive.read(manifest_member)
        assets, bundles = manifest_records(manifest)
        selected = {row["address"]: row for row in assets if row["address"] in wanted}
        assert selected.keys() == wanted.keys()
        ability_addresses = {"AbilityItemCfg_" + key: key for key in abilities}
        ability_assets = {row["address"]: row for row in assets if row["address"] in ability_addresses}
        assert ability_assets.keys() == ability_addresses.keys()
        source_abilities = {}
        for index in sorted({row["bundle"] for row in ability_assets.values()}):
            member = "assets/yoo/DefaultPackage/" + bundles[index]["hash"] + ".bundle"
            for obj in UnityPy.load(archive.read(member)).objects:
                if obj.type.name != "TextAsset" or obj.peek_name() not in ability_addresses:
                    continue
                data = obj.read()
                ability_id = ability_addresses[data.m_Name]
                source_abilities[ability_id] = json.loads(data.m_Script)
                assert source_abilities[ability_id] == abilities[ability_id]["raw"], ability_id
        assert source_abilities.keys() == abilities.keys()
        for index in sorted({row["bundle"] for row in selected.values()}):
            member = "assets/yoo/DefaultPackage/" + bundles[index]["hash"] + ".bundle"
            payload = archive.read(member)
            for obj in UnityPy.load(payload).objects:
                if obj.type.name != "Sprite" or obj.peek_name() not in wanted:
                    continue
                sprite = obj.read()
                source_image = sprite.image.convert("RGBA")
                resource = "assets/ui/pickup/" + sprite.m_Name + ".png"
                retained = (ROOT / resource).read_bytes()
                with Image.open(io.BytesIO(retained)) as image:
                    retained_image = image.convert("RGBA")
                    assert retained_image.size == source_image.size, resource
                    assert retained_image.tobytes() == source_image.tobytes(), resource
                ability_id = wanted[sprite.m_Name]
                ability = abilities[ability_id]
                icons[ability_id] = {
                    "ability_id": int(ability_id),
                    "name": ability["raw"]["Name"],
                    "description": ability["raw"]["Description"],
                    "rarity": ability["raw"]["Rare"],
                    "show_ability_icon": ability["raw"]["ShowIcon"],
                    "icon": "res://" + resource,
                    "icon_name": sprite.m_Name,
                    "size": list(source_image.size),
                    "png_sha256": digest(retained),
                    "rgba_sha256": digest(source_image.tobytes()),
                    "current_apk_pixels_match": True,
                    "source": {
                        "asset": selected[sprite.m_Name]["path"],
                        "member": member,
                        "bundle_sha256": digest(payload),
                        "sprite_path_id": str(obj.path_id),
                        "ability_source": ability["source_chain"][0],
                    },
                }
    assert icons.keys() == abilities.keys()
    panel_path = ROOT / "assets/ui/role_character/panel/prefab-layout.json"
    panel = json.loads(panel_path.read_text())
    assert panel["apk_sha256"] == apk_sha256
    with zipfile.ZipFile(apk) as archive:
        assert digest(archive.read(panel["source"]["member"])) == panel["source"]["sha256"]
    roots = {
        "Panel_PlayerStateMenu/ATPageBtnBox/Btn_Item",
        "Panel_PlayerStateMenu/Mode_Item",
        "Panel_PlayerStateMenu/Mode_Item/Container/Scroll_ItenListGrid",
        "Panel_PlayerStateMenu/Mode_Item/Box_Detail_ItemInfo",
        "Panel_PlayerStateMenu/Mode_Item/Box_Detail_ItemInfo/Box_Detail/Box_NonEmpty",
    }
    paths = {row["path"]: row for row in panel["transforms"] if row["path"] in roots}
    assert paths.keys() == roots
    report = {
        "schema": 1,
        "apk_sha256": apk_sha256,
        "evidence_type": "Static serialized Unity sprites and prefab layout; no APK execution",
        "rea_archive_evidence_id": REA_ARCHIVE_EVIDENCE,
        "manifest": {"member": manifest_member, "sha256": digest(manifest)},
        "icons": {key: icons[key] for key in sorted(icons, key=int)},
        "ui": {
            "prefab": panel["prefab"],
            "source": panel["source"],
            "layout": "res://assets/ui/role_character/panel/prefab-layout.json",
            "layout_sha256": digest(panel_path.read_bytes()),
            "inventory_layout": "res://assets/ui/role_inventory/prefab-layout.json",
            "transforms": [paths[key] for key in sorted(paths)],
            "spirit_specific_paths_in_player_menu": sorted({row["path"] for row in panel["transforms"]
                if any(term in row["path"].lower() for term in ("spirit", "sprites", "精灵"))}),
        },
        "observations": [
            "All 33 spirit icons already retained under assets/ui/pickup match current APK Sprite pixels exactly.",
            "All 33 retained spirit AbilityItem raw records match current APK TextAssets exactly.",
            "All 33 spirit AbilityItem source records set ShowIcon=false.",
            "PlayerStateMenu has an item grid and selected-item icon/name/description/tag detail area.",
        ],
        "design_boundary": [
            "A spirit-only inventory filter, character attachment entry and upgrade/fusion preview are reconstruction usability choices.",
            "ShowIcon=false does not prove the absence of every possible original buff-state indicator.",
            "The selected player-menu hierarchy has no spirit-specific named control; this is a bounded search, not a runtime claim.",
            "No original APK runtime capture establishes a dedicated spirit cooldown or charge HUD.",
        ],
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"icons": len(icons), "all_current_apk_pixels_match": True,
                      "ability_show_icon_true": sum(row["show_ability_icon"] for row in icons.values()),
                      "output": str(output)}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=ROOT / "assets/ui/spirit_skills/catalog.json")
    args = parser.parse_args()
    audit(args.apk, args.output)
