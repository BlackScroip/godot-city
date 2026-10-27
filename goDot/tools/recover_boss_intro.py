"""Recover the selected APK's active Boss introduction UI and exact curves."""

import argparse
import hashlib
import json
import math
from pathlib import Path
import zipfile

import UnityPy
from UnityPy.classes.PPtr import PPtr

from inspect_camp_progression import manifest_records
from recover_route_art import package_dependencies


EXPECTED_APK = "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505"
ROOT = "/Panel_BattlePlayerCtrl/BattleSysWnd/Container_BannerEffect/Banner_BossAppear_Show"
SKIP = "/Panel_BattlePlayerCtrl/BattleSysWnd/Toggle_BossShowSkip"
RESOURCE_ROOT = "res://assets/ui/boss_intro/"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def json_safe(value):
    if isinstance(value, float) and not math.isfinite(value):
        return "Infinity" if value > 0 else "-Infinity" if value < 0 else "NaN"
    if isinstance(value, dict):
        return {str(key): json_safe(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [json_safe(item) for item in value]
    return value


def write_json(path, value):
    path.write_text(json.dumps(json_safe(value), ensure_ascii=False, indent=2,
                               allow_nan=False) + "\n")


def vector(value):
    return [value[key] for key in ("x", "y", "z", "w") if key in value]


def rgba(value):
    return [value[key] for key in ("r", "g", "b", "a")]


def recover(apk, output, report, rea_evidence):
    with apk.open("rb") as stream:
        apk_sha = hashlib.file_digest(stream, "sha256").hexdigest()
    if apk_sha != EXPECTED_APK:
        raise ValueError("APK digest differs from the explicitly selected artifact")
    output.mkdir(parents=True, exist_ok=True)
    environment = UnityPy.Environment()
    sources, primary = {}, []
    with zipfile.ZipFile(apk) as archive:
        manifest_name = next(name for name in archive.namelist() if name.startswith(
            "assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes"))
        manifest = archive.read(manifest_name)
        assets, bundles = manifest_records(manifest)
        asset = next(row for row in assets if row["address"] == "Panel_BattlePlayerCtrl")
        dependencies, bundle_dependencies = package_dependencies(manifest, asset["address"])
        pending, loaded_indices = [asset["bundle"], *dependencies], set()
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
                if not hasattr(cab, "objects"):
                    continue
                sources[cab.name] = {"bundle_index": index, "bundle_name": bundles[index]["name"],
                                     "bundle_hash": bundles[index]["hash"], "member": member,
                                     "sha256": digest(payload)}
                if index == asset["bundle"]:
                    primary.extend(cab.objects.values())

    def dereference(pointer, owner):
        return PPtr(**pointer, assetsfile=owner.assets_file).deref()

    def location(obj):
        return {"path_id": str(obj.path_id), "cab": obj.assets_file.name,
                "source": sources.get(obj.assets_file.name)}

    def script_name(obj, tree):
        if "m_Script" not in tree:
            return obj.type.name
        return dereference(tree["m_Script"], obj).read().m_ClassName

    transforms = {obj.path_id: obj.read_typetree() for obj in primary
                  if obj.type.name in ("RectTransform", "Transform")}
    game_objects = {obj.path_id: obj.read_typetree() for obj in primary if obj.type.name == "GameObject"}
    by_game_object = {tree["m_GameObject"]["m_PathID"]: key for key, tree in transforms.items()}
    primary_by_id = {obj.path_id: obj for obj in primary}

    def hierarchy(transform_id):
        if transform_id not in transforms:
            return ""
        tree = transforms[transform_id]
        return hierarchy(tree["m_Father"]["m_PathID"]) + "/" + game_objects[
            tree["m_GameObject"]["m_PathID"]]["m_Name"]

    def selection(path):
        if path == ROOT or path.startswith(ROOT + "/"):
            return "nodes", path[len(ROOT):].lstrip("/")
        if path == SKIP or path.startswith(SKIP + "/"):
            return "skip", path[len(SKIP):].lstrip("/")
        return None, None

    catalog = {"apk_sha256": apk_sha, "reference_size": [1920, 1080],
               "prefab_address": asset["address"], "root": ROOT,
               "nodes": {}, "tracks": [], "audio": [], "skip": {"root": SKIP, "nodes": {}},
               "sprites": {}, "fonts": {}, "animation": {}}
    rectangles, components, images, animations, sound_graph = [], [], [], [], []
    unresolved = []

    for transform_id, tree in transforms.items():
        path = hierarchy(transform_id)
        scope, relative = selection(path)
        if scope is None:
            continue
        owner = primary_by_id[transform_id]
        parent = transforms.get(tree["m_Father"]["m_PathID"], {})
        siblings = [pointer["m_PathID"] for pointer in parent.get("m_Children", [])]
        angle = tree["m_LocalRotation"]
        z_rotation = math.degrees(math.atan2(2 * (angle["w"] * angle["z"] + angle["x"] * angle["y"]),
                                            1 - 2 * (angle["y"] ** 2 + angle["z"] ** 2)))
        node = {"path": relative, "name": path.rsplit("/", 1)[-1],
                "parent": relative.rsplit("/", 1)[0] if "/" in relative else "",
                "sibling_index": siblings.index(transform_id) if transform_id in siblings else 0,
                "active": bool(game_objects[tree["m_GameObject"]["m_PathID"]]["m_IsActive"]),
                "rect": {"anchor_min": vector(tree.get("m_AnchorMin", {"x": 0.5, "y": 0.5})),
                         "anchor_max": vector(tree.get("m_AnchorMax", {"x": 0.5, "y": 0.5})),
                         "anchored_position": vector(tree.get("m_AnchoredPosition", {"x": 0.0, "y": 0.0})),
                         "size_delta": vector(tree.get("m_SizeDelta", {"x": 0.0, "y": 0.0})),
                         "pivot": vector(tree.get("m_Pivot", {"x": 0.5, "y": 0.5})),
                         "scale": vector(tree["m_LocalScale"]), "rotation_degrees": z_rotation},
                "source": location(owner)}
        target = catalog["nodes"] if scope == "nodes" else catalog["skip"]["nodes"]
        target[relative] = node
        rectangles.append({"path": path, "active": node["active"], "fields": tree, **location(owner)})

    def sprite_info(pointer, owner):
        if not pointer or not pointer.get("m_PathID"):
            return None
        obj = dereference(pointer, owner)
        sprite = obj.read()
        key = obj.assets_file.name + ":" + str(obj.path_id)
        if key not in catalog["sprites"]:
            filename = digest(key.encode())[:16] + ".png"
            target = output / filename
            image = sprite.image
            image.save(target)
            tree = obj.read_typetree()
            entry = {"name": sprite.m_Name, "texture": RESOURCE_ROOT + filename,
                     "image_size": list(image.size), "sprite_rect": tree["m_Rect"],
                     "sprite_pivot": tree["m_Pivot"], "border": tree["m_Border"],
                     "pixels_per_unit": tree["m_PixelsToUnits"],
                     "png_sha256": digest(target.read_bytes()), **location(obj)}
            catalog["sprites"][key] = entry
            images.append(entry)
        return catalog["sprites"][key]

    def font_info(pointer, owner):
        if not pointer or not pointer.get("m_PathID"):
            return None
        obj = dereference(pointer, owner)
        key = obj.assets_file.name + ":" + str(obj.path_id)
        if key in catalog["fonts"]:
            return catalog["fonts"][key]
        tree = obj.read_typetree()
        entry = {"name": tree.get("m_Name"), "face_info": tree.get("m_FaceInfo"),
                 "source_font_guid": tree.get("m_SourceFontFileGUID"), **location(obj)}
        source_pointer = tree.get("m_SourceFontFile")
        source = None
        if source_pointer and source_pointer["m_PathID"]:
            source = dereference(source_pointer, obj)
            entry["source_font_selection"] = "direct serialized pointer"
        else:
            face = tree.get("m_FaceInfo", {})
            family = "".join(character.lower() for character in face.get("m_FamilyName", "") if character.isalnum())
            style = "".join(character.lower() for character in face.get("m_StyleName", "") if character.isalnum())
            candidates = []
            for candidate in environment.objects:
                if candidate.type.name != "Font":
                    continue
                name = "".join(character.lower() for character in candidate.peek_name() if character.isalnum())
                if family.startswith("alibabapuhuiti") and "alibabapuhuiti" in name and style in name:
                    candidates.append(candidate)
            if len(candidates) == 1:
                source = candidates[0]
                entry["source_font_selection"] = "inferred matching packaged Font family/style; TMP source pointer is null"
        if source is not None:
            data = source.read()
            font_bytes = bytes(data.m_FontData)
            if font_bytes:
                filename = "font_" + digest(font_bytes)[:16] + ".ttf"
                (output / filename).write_bytes(font_bytes)
                entry.update({"resource": RESOURCE_ROOT + filename, "sha256": digest(font_bytes),
                              "source_font": location(source)})
        catalog["fonts"][key] = entry
        return entry

    selected_audio = []
    bound_clip = None
    for obj in primary:
        if obj.type.name not in ("MonoBehaviour", "Animation", "Animator", "CanvasGroup", "AudioSource"):
            continue
        tree = obj.read_typetree()
        path = hierarchy(by_game_object.get(tree.get("m_GameObject", {}).get("m_PathID")))
        scope, relative = selection(path)
        script = script_name(obj, tree)
        if script == "Panel_PlayerBattleCtrl_BattleSysWnd":
            components.append({"path": path, "script": script, "fields": tree, **location(obj)})
            catalog["owner_bindings"] = {key: str(value["m_PathID"]) for key, value in tree.items()
                                         if key.startswith("Banner_BossAppear") or key == "Toggle_BossAppearSkip"}
        if scope is None:
            continue
        components.append({"path": path, "script": script, "fields": tree, **location(obj)})
        target = catalog["nodes"] if scope == "nodes" else catalog["skip"]["nodes"]
        node = target[relative]
        node.setdefault("components", []).append(script)
        node.setdefault("component_fields", []).append({"script": script, "fields": tree,
                                                        "path_id": str(obj.path_id)})
        if "m_Sprite" in tree:
            sprite = sprite_info(tree["m_Sprite"], obj)
            node["image"] = {"texture": sprite["texture"] if sprite else "", "color": rgba(tree["m_Color"]),
                             "type": tree.get("m_Type", 0), "fill_amount": tree.get("m_FillAmount", 1.0),
                             "preserve_aspect": bool(tree.get("m_PreserveAspect", 0)),
                             "sprite_rect": sprite["sprite_rect"] if sprite else None,
                             "sprite_pivot": sprite["sprite_pivot"] if sprite else None,
                             "sprite_name": sprite["name"] if sprite else "",
                             "pixels_per_unit_multiplier": tree.get("m_PixelsPerUnitMultiplier", 1.0)}
        if script == "TextMeshProUGUI":
            font = font_info(tree.get("m_fontAsset"), obj)
            node["text"] = {"text": tree["m_text"], "font_size": tree["m_fontSize"],
                            "font_style": tree["m_fontStyle"], "font_weight": tree["m_fontWeight"],
                            "color": rgba(tree["m_fontColor"]), "graphic_color": rgba(tree["m_Color"]),
                            "horizontal_alignment": tree["m_HorizontalAlignment"],
                            "vertical_alignment": tree["m_VerticalAlignment"],
                            "auto_sizing": bool(tree["m_enableAutoSizing"]),
                            "character_spacing": tree["m_characterSpacing"],
                            "margin": vector(tree["m_margin"]), "font": font}
            for field in ("m_sharedMaterial", "m_fontMaterial"):
                pointer = tree.get(field)
                if pointer and pointer["m_PathID"]:
                    material = dereference(pointer, obj)
                    mt = material.read_typetree()
                    node["text"][field] = {"name": mt.get("m_Name"), "saved_properties": mt.get("m_SavedProperties"),
                                                 "shader_keywords": mt.get("m_ShaderKeywords"),
                                                 "valid_keywords": mt.get("m_ValidKeywords"),
                                                 **location(material)}
                    properties = mt.get("m_SavedProperties", {})
                    floats = dict(properties.get("m_Floats", []))
                    colors = dict(properties.get("m_Colors", []))
                    if field == "m_sharedMaterial":
                        node["text"]["style"] = {
                            "face_color": rgba(colors.get("_FaceColor", {"r": 1, "g": 1, "b": 1, "a": 1})),
                            "face_dilate": floats.get("_FaceDilate", 0.0),
                            "outline_color": rgba(colors.get("_OutlineColor", {"r": 0, "g": 0, "b": 0, "a": 1})),
                            "outline_width": floats.get("_OutlineWidth", 0.0),
                            "underlay_color": rgba(colors.get("_UnderlayColor", {"r": 0, "g": 0, "b": 0, "a": 0})),
                            "underlay_offset": [floats.get("_UnderlayOffsetX", 0.0), floats.get("_UnderlayOffsetY", 0.0)],
                            "underlay_dilate": floats.get("_UnderlayDilate", 0.0),
                            "underlay_softness": floats.get("_UnderlaySoftness", 0.0),
                            "gradient_scale": floats.get("_GradientScale", 0.0),
                            "shader_keywords": mt.get("m_ShaderKeywords"),
                            "valid_keywords": mt.get("m_ValidKeywords"),
                            "vertex_gradient_enabled": bool(tree["m_enableVertexGradient"]),
                            "vertex_gradient": tree["m_fontColorGradient"],
                        }
        if script in ("Shadow", "Outline"):
            node.setdefault("text_effects", []).append({"script": script, "fields": tree})
        if script == "CanvasGroup":
            node["canvas_group"] = {"alpha": tree["m_Alpha"], "interactable": tree["m_Interactable"],
                                    "blocks_raycasts": tree["m_BlocksRaycasts"]}
        if script in ("HorizontalLayoutGroup", "VerticalLayoutGroup", "ContentSizeFitter", "LayoutElement"):
            node.setdefault("layouts", []).append({"script": script, "fields": tree})
            node["layout"] = {"script": script, "fields": tree}
        if script == "Toggle":
            node["toggle"] = {"script": script, "fields": tree}
        if script.startswith("DOTween"):
            node.setdefault("tweens", []).append({"script": script, "fields": tree})
        if script == "AudioContainer":
            selected_audio.append((relative, obj, tree))
        if scope == "nodes" and relative == "" and script == "Animation":
            bound_clip = dereference(tree["m_Animation"], obj)

    if bound_clip is None:
        raise ValueError("Active Boss Show animation was not bound")
    clip = bound_clip.read_typetree()
    animations.append({"name": clip["m_Name"], "fields": clip, **location(bound_clip)})
    for kind, property_name in (("m_FloatCurves", None), ("m_ScaleCurves", "m_LocalScale"),
                                ("m_PositionCurves", "m_LocalPosition"), ("m_EulerCurves", "localEulerAnglesRaw")):
        for curve in clip[kind]:
            catalog["tracks"].append({"path": curve["path"], "property": property_name or curve["attribute"],
                                       "kind": "step" if curve.get("attribute") == "m_IsActive" else "hermite",
                                       "keys": curve["curve"]["m_Curve"],
                                       "pre_infinity": curve["curve"]["m_PreInfinity"],
                                       "post_infinity": curve["curve"]["m_PostInfinity"]})
    catalog["duration"] = max(key["time"] for track in catalog["tracks"] for key in track["keys"])
    catalog["animation"] = {"name": clip["m_Name"], "sample_rate": clip["m_SampleRate"],
                            "legacy": clip["m_Legacy"], "duration_source": "maximum serialized curve key time",
                            "muscle_stop_time": clip["m_MuscleClip"]["m_StopTime"], **location(bound_clip)}

    for relative, owner, tree in selected_audio:
        event = dereference(tree["S_SoundEvent"], owner)
        event_tree = event.read_typetree()
        sound_graph.append({"fields": event_tree, **location(event)})
        internal = event_tree["internals"]
        timeline = internal["data"]["timelineSoundContainerData"]
        for index, pointer in enumerate(internal["soundContainers"]):
            container = dereference(pointer, event)
            ct = container.read_typetree()
            sound_graph.append({"fields": ct, **location(container)})
            settings = ct["internals"]["data"]
            for clip_pointer in ct["internals"]["audioClips"]:
                audio_obj = dereference(clip_pointer, container)
                audio = audio_obj.read()
                samples = audio.samples
                for sample_index, sample in enumerate(samples.values()):
                    filename = ("boss_appear" if "bossappear" in relative else "intro_sting")
                    filename += ("_" + str(sample_index) if sample_index else "") + ".wav"
                    (output / filename).write_bytes(sample)
                    track = next(row for row in catalog["tracks"] if row["path"] == relative and row["property"] == "m_IsActive")
                    start = next(key["time"] for key in track["keys"] if key["value"] > 0.5)
                    catalog["audio"].append({"path": relative, "resource": RESOURCE_ROOT + filename,
                                              "name": audio.m_Name, "start": start,
                                              "duration": audio.m_Length, "frequency": audio.m_Frequency,
                                              "channels": audio.m_Channels, "sha256": digest(sample),
                                              "event_volume_db": timeline[index]["volumeDecibel"],
                                              "container_volume_db": settings["volumeDecibel"],
                                              "pitch_random_enabled": bool(settings["pitchRandomEnable"]),
                                              "pitch_random_range_semitones": settings["pitchRandomRangeSemitoneBipolar"],
                                              "container": location(container), "event": location(event),
                                              **location(audio_obj)})
                if not samples:
                    unresolved.append("Audio sample extraction unavailable: " + audio.m_Name)

    catalog["limitations"] = [
        "Static resource recovery; the Android application was not executed.",
        "The active owner binds Show; the Old Normal and CloseUp fields are null.",
        "UI reference coordinates use the project's 1920 by 1080 canvas convention; layout groups can override child rectangles.",
        "Camera, gameplay pause, runtime text and animation-speed assignment require separate native behavior evidence.",
        "Infinite animation tangents are encoded as strings to preserve valid JSON; treat them as stepped segments.",
    ]
    write_json(output / "catalog.json", catalog)
    evidence = {"apk_sha256": apk_sha, "rea_inventory_evidence": rea_evidence,
                "evidence_type": "Static Unity prefab, AnimationClip, sprite, font and audio recovery; APK not executed",
                "manifest_member": manifest_name, "manifest_sha256": digest(manifest),
                "prefab": asset, "bundle_sources": sources, "rectangles": rectangles,
                "components": components, "images": images, "animations": animations,
                "sound_graph": sound_graph, "catalog": catalog,
                "unknowns": unresolved, "limitations": catalog["limitations"]}
    write_json(report, evidence)
    print(json.dumps({"report": str(report), "catalog": str(output / "catalog.json"),
                      "nodes": len(catalog["nodes"]), "tracks": len(catalog["tracks"]),
                      "sprites": len(images), "audio": len(catalog["audio"]),
                      "duration": catalog["duration"], "unknowns": unresolved}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--rea-evidence", required=True)
    args = parser.parse_args()
    recover(args.apk, args.output, args.report, args.rea_evidence)
