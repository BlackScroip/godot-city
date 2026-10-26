"""Recover the selected APK's room-entry banner and bounded native evidence."""

import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import zipfile

import UnityPy
from UnityPy.classes.PPtr import PPtr

from inspect_camp_progression import manifest_records
from recover_route_art import package_dependencies
import inspect_new_camp_native as native_audit


def digest(data):
    return hashlib.sha256(data).hexdigest()


def recover(apk, output, report, native, stubs, rea_evidence):
    output.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(apk) as archive:
        manifest_name = next(name for name in archive.namelist() if name.startswith(
            "assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes"))
        manifest = archive.read(manifest_name)
        assets, bundles = manifest_records(manifest)
        asset = next(row for row in assets if row["address"] == "Panel_BattlePlayerCtrl")
        dependencies, bundle_dependencies = package_dependencies(manifest, asset["address"])
        pending = [asset["bundle"], *dependencies]
        seen, primary, sources = set(), [], {}
        environment = UnityPy.Environment()
        while pending:
            index = pending.pop()
            if index in seen:
                continue
            seen.add(index)
            pending.extend(bundle_dependencies[index])
            member = "assets/yoo/DefaultPackage/" + bundles[index]["hash"] + ".bundle"
            payload = archive.read(member)
            loaded = environment.load_file(payload)
            for cab in loaded.files.values():
                if not hasattr(cab, "objects"):
                    continue
                sources[cab.name] = {"member": member, "sha256": digest(payload)}
                if index == asset["bundle"]:
                    primary.extend(cab.objects.values())
        if archive.read("lib/arm64-v8a/libil2cpp.so") != native.read_bytes():
            raise ValueError("Native image does not match the supplied APK")

    def dereference(pointer, owner):
        return PPtr(**pointer, assetsfile=owner.assets_file).deref()

    transforms = {obj.path_id: obj.read_typetree() for obj in primary
                  if obj.type.name in ("Transform", "RectTransform")}
    objects = {obj.path_id: obj.read_typetree() for obj in primary if obj.type.name == "GameObject"}
    by_game_object = {value["m_GameObject"]["m_PathID"]: key for key, value in transforms.items()}

    def hierarchy(transform_id):
        tree = transforms.get(transform_id)
        if not tree:
            return ""
        return hierarchy(tree["m_Father"]["m_PathID"]) + "/" + objects[tree["m_GameObject"]["m_PathID"]]["m_Name"]

    rectangles, components, images, animations = [], [], [], []
    for transform_id, tree in transforms.items():
        path = hierarchy(transform_id)
        if "/Banner_GameStart" in path:
            rectangles.append({"path": path, "fields": tree,
                               "active": objects[tree["m_GameObject"]["m_PathID"]]["m_IsActive"]})
    for obj in primary:
        if obj.type.name not in ("MonoBehaviour", "Animation", "Animator", "CanvasGroup"):
            continue
        tree = obj.read_typetree()
        path = hierarchy(by_game_object.get(tree["m_GameObject"]["m_PathID"]))
        if "/Banner_GameStart" not in path:
            continue
        script = obj.type.name
        if "m_Script" in tree:
            script = dereference(tree["m_Script"], obj).read().m_ClassName
        components.append({"path": path, "script": script, "fields": tree})
        pointer = tree.get("m_Sprite")
        if pointer and pointer["m_PathID"] and "/Old" not in path:
            sprite_obj = dereference(pointer, obj)
            sprite = sprite_obj.read()
            filename = digest(sprite.m_Name.encode())[:16] + ".png"
            target = output / filename
            sprite.image.save(target)
            images.append({"path": path, "name": sprite.m_Name,
                           "resource": "res://assets/ui/region_notice/" + filename,
                           "source": sources.get(sprite_obj.assets_file.name),
                           "png_sha256": digest(target.read_bytes())})
    playback = {}
    for obj in environment.objects:
        if obj.type.name != "AnimationClip":
            continue
        name = obj.peek_name()
        if any(term in name.lower() for term in ("gamestart", "region", "node", "\u8282\u70b9")):
            animations.append({"name": name, "path_id": str(obj.path_id),
                               "source": sources.get(obj.assets_file.name), "fields": obj.read_typetree()})
        if name != "RegionStart":
            continue
        tree = obj.read_typetree()
        frames = []
        for index, pointer in enumerate(tree["m_ClipBindingConstant"]["pptrCurveMapping"]):
            sprite_obj = dereference(pointer, obj)
            sprite = sprite_obj.read()
            target = output / ("frame_%02d.png" % index)
            sprite.image.save(target)
            resource = "res://assets/ui/region_notice/" + target.name
            frames.append(resource)
            images.append({"name": sprite.m_Name, "path_id": str(sprite_obj.path_id),
                           "resource": resource, "source": sources.get(sprite_obj.assets_file.name),
                           "png_sha256": digest(target.read_bytes())})
        names = ["background_active", "root_alpha", "background_alpha", "title_active",
                 "title_alpha", "sound_active", "sprite_frame"]
        tracks = {name: [] for name in names}
        words = tree["m_MuscleClip"]["m_Clip"]["data"]["m_StreamedClip"]["data"]
        position = 0
        while position < len(words):
            time = struct.unpack("<f", struct.pack("<I", words[position]))[0]
            count = words[position + 1]
            position += 2
            for _ in range(count):
                index = words[position]
                coefficients = struct.unpack("<4f", struct.pack("<4I", *words[position + 1:position + 5]))
                position += 5
                if math.isfinite(time):
                    tracks[names[index]].append([max(-1.0, time), *coefficients])
        playback = {"duration": tree["m_MuscleClip"]["m_StopTime"], "frames": frames,
                    "tracks": tracks, "reference_size": [1920, 1080],
                    "top": 43, "height": 341, "title_center_y": 180, "font_size": 42}
    if not playback:
        raise ValueError("Expected the APK's RegionStart animation")
    (output / "animation.json").write_text(json.dumps(playback, ensure_ascii=False, indent=2) + "\n")

    native_audit.SELECTION = {
        "Panel_PlayerBattleCtrl_BattleSysWnd": ["SetBannerDisplay(", "Message_BannerDisplay(", "<SetBannerDisplay>"],
        "RogueRoomManager": ["EnterNextRegionRoute(", "ToRogueRegionMusic("],
    }
    native_audit.SELECTED_OFFSETS = set()
    native_result = native_audit.inspect(native, stubs)
    with apk.open("rb") as stream:
        apk_sha = hashlib.file_digest(stream, "sha256").hexdigest()
    evidence = {"apk_sha256": apk_sha, "rea_inventory_evidence": rea_evidence,
                "evidence_type": "Static Unity resources and local Capstone disassembly; APK not executed",
                "manifest_member": manifest_name, "manifest_sha256": digest(manifest),
                "prefab": asset, "rectangles": rectangles, "components": components,
                "images": images, "animations": animations, "playback": playback, "native": native_result,
                "limitations": ["Recovered declarations identify methods; they are not original source.",
                                "REA establishes APK inventory; local parsers recover Unity and ARM64 facts.",
                                "Static animation curves do not establish runtime playback timing."]}
    report.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"report": str(report), "image_count": len(images),
                      "components": [{"path": row["path"], "script": row["script"]} for row in components if "/Old" not in row["path"]],
                      "animations": [{"name": row["name"], "stop": row["fields"].get("m_MuscleClip", {}).get("m_StopTime")} for row in animations],
                      "methods": len(native_result["methods"])}, ensure_ascii=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for flag in ("apk", "output", "report", "native", "stubs"):
        parser.add_argument("--" + flag, type=Path, required=True)
    parser.add_argument("--rea-evidence", required=True)
    args = parser.parse_args()
    recover(args.apk, args.output, args.report, args.native, args.stubs, args.rea_evidence)
