#!/usr/bin/env python3
"""Import player lifecycle presentation events from the selected APK.

Only the manifest and selected Unity bundles are read; no APK tree is extracted.
Requires UnityPy. Output is deterministic and keeps original timing/conditions.
"""

import argparse
import hashlib
import json
from pathlib import Path
import struct
import zipfile

import UnityPy


ACTIONS = ("enterroom", "leftroom", "revival")
PRESENTATION = {
    "EET_PlayAnim", "EET_PlayEffect", "EET_PlaySound", "EET_SetUnitDisplay",
    "EET_TempWeaponBind", "EET_CameraEffect", "EET_CameraFade",
    "EET_ChangeLightIndensity", "EET_BattleTimeScaleModify",
}


class Reader:
    def __init__(self, payload):
        self.payload, self.offset = payload, 0

    def number(self, fmt):
        value = struct.unpack_from("<" + fmt, self.payload, self.offset)[0]
        self.offset += struct.calcsize(fmt)
        return value

    def string(self):
        size = self.number("H")
        value = self.payload[self.offset:self.offset + size].decode("utf-8")
        self.offset += size
        return value

    def array(self, read):
        return [read() for _ in range(self.number("H"))]


def manifest_records(payload):
    # YooAsset 2.3.1 layout, shared with inspect_camp_progression.py.
    reader = Reader(payload)
    reader.number("I")
    reader.string()
    for _ in range(3):
        reader.number("B")
    for _ in range(2):
        reader.number("i")
    for _ in range(4):
        reader.string()
    assets = []
    for _ in range(reader.number("i")):
        address, path, guid = [reader.string() for _ in range(3)]
        reader.array(reader.string)
        bundle = reader.number("i")
        reader.array(lambda: reader.number("i"))
        assets.append({"address": address, "path": path, "bundle": bundle})
    bundles = []
    for _ in range(reader.number("i")):
        name = reader.string()
        reader.number("I")
        digest = reader.string()
        reader.string()
        reader.number("q")
        reader.number("B")
        reader.array(reader.string)
        reader.array(lambda: reader.number("i"))
        bundles.append({"name": name, "hash": digest})
    if reader.offset != len(payload):
        raise ValueError("Manifest has trailing or unparsed bytes")
    return assets, bundles


def digest(payload):
    return hashlib.sha256(payload).hexdigest()


def file_digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def resource_key(value):
    return value.replace("\\", "/").split("/")[-1].removesuffix(".prefab").lower()


def condition(value):
    return {
        "type": value.get("ConditionType", ""),
        "buff": str(value.get("BuffId", "")),
        "exists": value.get("IsExist", False),
        "layers": value.get("CheckLayerCount", 0),
        "compare": value.get("CompareType", ""),
        "property": value.get("PropertyName", ""),
        "value": value.get("Value", ""),
        "raw": json.dumps(value, ensure_ascii=True, separators=(",", ":")),
    }


def event(value, index):
    data = value["EventData"]
    result = {
        "index": index,
        "track": value.get("TrackName", ""),
        "track_index": value.get("TrackIndex", 0),
        "type": value["EventType"],
        "time": value["TriggerTime"] / 1000.0,
        "duration": value["Duration"] / 1000.0,
        "time_ms": value["TriggerTime"],
        "duration_ms": value["Duration"],
        "enabled": value.get("Enabled", True),
        "all": value.get("CheckAllCondition", True),
        "conditions": [condition(item) for item in value.get("Conditions", [])],
        "source_conditions": value.get("Conditions", []),
        "data": data,
        "raw": json.dumps(data, ensure_ascii=True, separators=(",", ":")),
    }
    if result["type"] == "EET_PlayAnim":
        result["anim"] = data["AnimName"]
    elif result["type"] == "EET_PlayEffect":
        definition = data["EffectTriggerDef"]
        result.update(effect=resource_key(definition["EffectName"]),
                      speed=definition.get("EffectSpeed", 1.0),
                      anchor=definition.get("DummyData", {}).get("DummyType", ""),
                      attachment=definition.get("DummyType", ""))
    elif result["type"] == "EET_PlaySound":
        result["sound"] = resource_key(data["SoundName"])
    elif result["type"] == "EET_SetUnitDisplay":
        result["visible"] = data.get("IsActive", True) and not data.get("IsInVisible", False)
    elif result["type"] == "EET_Interrupt":
        result["target"] = data.get("ActionID", "")
    return result


def load_json(path):
    return json.loads(path.read_text())


def import_lifecycle(apk, project):
    apk_sha = file_digest(apk)
    media = load_json(project / "assets/combat_presentation/catalog.json")
    models = load_json(project / "assets/catalog.json")
    actions, resource_names, omitted = {}, {"effects": set(), "sounds": set(), "animations": set()}, {}
    bundle_cache, bundle_sources = {}, {}
    with zipfile.ZipFile(apk) as archive:
        names = [name for name in archive.namelist() if name.startswith(
            "assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes")]
        if len(names) != 1:
            raise ValueError("Expected one DefaultPackage binary manifest: " + repr(names))
        manifest_name = names[0]
        manifest_payload = archive.read(manifest_name)
        assets, bundles = manifest_records(manifest_payload)
        addresses = {row["address"]: row for row in assets}

        def bundle(index):
            if index not in bundle_cache:
                member = "assets/yoo/DefaultPackage/" + bundles[index]["hash"] + ".bundle"
                payload = archive.read(member)
                bundle_cache[index] = payload
                bundle_sources[index] = {"bundle": index, "bundle_name": bundles[index]["name"],
                                         "bundle_member": member, "bundle_sha256": digest(payload)}
            return bundle_cache[index]

        for action_id in ACTIONS:
            address = "ActGroup_playerchara_[" + action_id + "]"
            record = addresses[address]
            selected = []
            for obj in UnityPy.load(bundle(record["bundle"])).objects:
                if obj.type.name != "TextAsset":
                    continue
                item = obj.read()
                if item.m_Name == address:
                    raw = item.m_Script
                    payload = raw if isinstance(raw, bytes) else raw.encode("utf-8", "surrogateescape")
                    selected.append((obj.path_id, payload, json.loads(payload.decode("utf-8-sig"))))
            if len(selected) != 1:
                raise ValueError("Expected one exact TextAsset for " + address)
            path_id, payload, raw_action = selected[0]
            if raw_action["ActId"] != action_id:
                raise ValueError("Action identity mismatch: " + address)
            events = [event(item, index) for index, item in enumerate(raw_action["Events"])
                      if item["EventType"] in PRESENTATION]
            omitted[action_id] = [event(item, index) for index, item in enumerate(raw_action["Events"])
                                  if item["EventType"] not in PRESENTATION]
            actions[action_id] = {
                "id": action_id, "duration": raw_action["TotalTime"] / 1000.0,
                "duration_ms": raw_action["TotalTime"], "speed": raw_action["PlaySpeed"],
                "source": {"address": address, "asset_path": record["path"],
                           **bundle_sources[record["bundle"]], "text_asset_path_id": str(path_id),
                           "json_sha256": digest(payload)},
                "events": events,
                "interrupts": [event(item, index) for index, item in enumerate(raw_action.get("Interrupts", []))],
                "source_event_count": len(raw_action["Events"]),
            }
            for row in events:
                for field, group in (("effect", "effects"), ("sound", "sounds"), ("anim", "animations")):
                    if row.get(field):
                        resource_names[group].add(row[field])

        resources = {"effects": {}, "sounds": {}, "animations": {}}
        for category in ("effects", "sounds"):
            for key in sorted(resource_names[category]):
                record = addresses.get(key)
                if record is None:
                    raise ValueError("Missing exact source manifest resource: " + key)
                bundle(record["bundle"])
                resources[category][key] = {"address": key, "asset_path": record["path"],
                                             **bundle_sources[record["bundle"]]}
        for name in sorted(resource_names["animations"]):
            matches = []
            for character_id, character in models["characters"].items():
                for animation in character.get("animations", []):
                    if animation.get("source_name") == name:
                        matches.append({"character_id": int(character_id), "model": character["path"],
                                        **animation})
            resources["animations"][name] = {"source_name": name, "imported": matches}

    source = {"apk": apk.name, "apk_sha256": apk_sha, "manifest_member": manifest_name,
              "manifest_sha256": digest(manifest_payload),
              "evidence_type": "static APK manifest and Unity TextAsset configuration",
              "evidence_report": "res://reports/player-lifecycle-source.json"}
    limitations = [
        "Static source configuration is not observation of original APK execution.",
        "Source millisecond timing, conditions, event order, effect speed, attachment and raw event data are preserved without acceleration.",
        "Revival input movement is outside this presentation import and retained in the evidence report.",
        "Source revival also permits sys_idle at 1.667 seconds although the action TotalTime is 2.5 seconds; both values are retained.",
        "Source enterroom defines transfer animations only for buff 100000 through 600000. No lance/blade event is invented.",
        "Source leftroom requests orb@skill_shenzhijianglin unconditionally; the current model catalog supplies that clip for character 6 only.",
        "Godot particle rendering and custom shader equivalence retain the limitations recorded in the existing presentation catalog.",
    ]
    result = {"schema": 1, "time_unit": "seconds", "source": source,
              "actions": actions, "resources": resources, "limitations": limitations}
    imported = {"effects": {}, "sounds": {}, "animations": resources["animations"]}
    missing = []
    for key in sorted(resource_names["effects"]):
        entry = media.get("effects", {}).get(key, {})
        imported["effects"][key] = {"present": bool(entry), "source": entry.get("source", ""),
                                    "source_sha256": entry.get("source_sha256", ""),
                                    "particle_systems": entry.get("particle_systems", 0),
                                    "layers": len(entry.get("layers", [])),
                                    "unsupported": entry.get("unsupported", [])}
        if not entry or not entry.get("layers"):
            missing.append("effect:" + key)
    for key in sorted(resource_names["sounds"]):
        layers = media.get("audio", {}).get(key, [])
        clips = sorted({clip for layer in layers for clip in layer.get("clips", [])})
        clip_files = [{"path": clip, "exists": (project / clip.removeprefix("res://")).is_file(),
                       "sha256": file_digest(project / clip.removeprefix("res://"))
                       if (project / clip.removeprefix("res://")).is_file() else ""} for clip in clips]
        imported["sounds"][key] = {"present": bool(layers), "layers": layers, "clips": clip_files}
        if not layers or any(not item["exists"] for item in clip_files):
            missing.append("sound:" + key)
    rea = []
    evidence_path = project / "reports/RESOURCE_APK_REA_EVIDENCE.json"
    if evidence_path.is_file():
        evidence = load_json(evidence_path)
        rea = [{"evidence_id": record["evidence_id"], "operation": record["operation"]}
               for record in evidence.get("records", [])
               if record.get("subject", {}).get("digest", {}).get("sha256") == apk_sha]
    report = {"schema": 1, "source": source, "rea_evidence": rea,
              "observed": {"actions": {key: {"duration": value["duration"],
                                "source_event_count": value["source_event_count"],
                                "imported_event_count": len(value["events"]),
                                "source": value["source"]} for key, value in actions.items()},
                           "resources": resources, "current_imports": imported},
              "excluded_gameplay_events": omitted, "missing_imported_media": missing,
              "inferences": ["Existing particle/audio assets can be reused by the lifecycle event consumer because exact event resource keys resolve in the imported catalog."],
              "unknowns": ["Original runtime callback, camera shader and animation retargeting behavior are not established by these static action records."],
              "limitations": limitations}
    if missing:
        raise ValueError("Required lifecycle media are incomplete: " + repr(missing))
    return result, report


def write_or_check(path, value, check):
    payload = json.dumps(value, indent=2, ensure_ascii=True) + "\n"
    if check:
        if not path.is_file() or path.read_text() != payload:
            raise ValueError("Generated lifecycle output differs: " + str(path))
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(payload)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    result, report = import_lifecycle(args.apk, args.project)
    output = args.output or args.project / "assets/data/player_lifecycle.json"
    report_path = args.report or args.project / "reports/player-lifecycle-source.json"
    write_or_check(output, result, args.check)
    write_or_check(report_path, report, args.check)
    print(json.dumps({"output": str(output), "report": str(report_path), "check": args.check,
                      "actions": {key: len(value["events"]) for key, value in result["actions"].items()},
                      "resources": {key: len(value) for key, value in result["resources"].items()}}))


if __name__ == "__main__":
    main()
