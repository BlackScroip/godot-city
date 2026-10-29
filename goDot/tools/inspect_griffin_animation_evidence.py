#!/usr/bin/env python3
"""Reproduce the shipped APK evidence for Griffin's missing Part2 state.

Requires UnityPy. Reads only the supplied APK; this is not a runtime test.
"""

import argparse
import hashlib
import json
from pathlib import Path
import struct
import zipfile

import UnityPy


ROOT = Path(__file__).resolve().parents[2]
APK_SHA256 = "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505"
BUNDLE_IDS = {
    "prefab": "5d80bfb9032377374356e35f483b518e",
    "controller": "63ffca709b78820c6dfc245547baebe8",
    "animations": "5cbd5e7f86ddc254c0eeb600f2d0fe14",
    "action": "fec03e1c52d203d39af9e2b014f0782d",
}
GRIFFIN_PART1 = -8615122952939718453
GRIFFIN_DASH = -6047920325342152501
GRIFFIN_EX_ATTACK3 = 8778490218463777921


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, default=ROOT / "1061664.apk")
    parser.add_argument("--model", type=Path, default=ROOT / "goDot/assets/enemies/enemy_23001.glb")
    parser.add_argument("--output", type=Path, help="Optional JSON report")
    args = parser.parse_args()
    with args.apk.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    if digest != APK_SHA256:
        raise ValueError("This evidence query targets a different APK SHA-256")

    model_payload = args.model.read_bytes()
    magic, version, length = struct.unpack_from("<4sII", model_payload)
    json_length, chunk_type = struct.unpack_from("<I4s", model_payload, 12)
    if magic != b"glTF" or version != 2 or length != len(model_payload) or chunk_type != b"JSON":
        raise ValueError("Invalid GLB header or JSON chunk")
    model_json = json.loads(model_payload[20:20 + json_length])
    model_names = [entry.get("name", "") for entry in model_json.get("animations", [])]

    envs, bundles = {}, {}
    with zipfile.ZipFile(args.apk) as archive:
        for name, bundle_id in BUNDLE_IDS.items():
            member = "assets/yoo/DefaultPackage/" + bundle_id + ".bundle"
            payload = archive.read(member)
            envs[name] = UnityPy.load(payload)
            bundles[name] = {"member": member, "sha256": hashlib.sha256(payload).hexdigest()}

    animators = [obj for obj in envs["prefab"].objects if obj.type.name == "Animator"]
    if len(animators) != 1:
        raise ValueError("Expected exactly one Griffin prefab Animator")
    animator = animators[0]
    animator_raw = animator.read_typetree()
    controller_ref = animator_raw["m_Controller"]
    controllers = [obj for obj in envs["controller"].objects if obj.type.name == "AnimatorController"
                   and obj.path_id == controller_ref["m_PathID"]]
    if len(controllers) != 1:
        raise ValueError("Griffin Animator's controller was not resolved")
    controller_obj = controllers[0]
    controller = controller_obj.read_typetree()
    names = dict(controller.get("m_TOS", []))
    states = []
    for machine in controller["m_Controller"].get("m_StateMachineArray", []):
        for wrapped in machine["data"].get("m_StateConstantArray", []):
            state = wrapped["data"]
            states.append(names.get(state["m_NameID"], ""))

    action_objs = [obj for obj in envs["action"].objects if obj.type.name == "TextAsset"
                   and obj.path_id == GRIFFIN_EX_ATTACK3]
    if len(action_objs) != 1:
        raise ValueError("Griffin EX_Attack3 action text was not resolved")
    action = json.loads(action_objs[0].read_typetree()["m_Script"])
    part2_events = [{"trigger_time_ms": event.get("TriggerTime"), "enabled": event.get("Enabled"),
                     "animation": event.get("EventData", {}).get("AnimName")}
                    for event in action.get("Events", [])
                    if event.get("EventType") == "EET_PlayAnim"
                    and event.get("EventData", {}).get("AnimName", "").lower() == "attack2_part2"]

    clip_objects = [obj for obj in envs["animations"].objects if obj.type.name == "AnimationClip"]
    selected = [obj for obj in clip_objects if obj.path_id in (GRIFFIN_PART1, GRIFFIN_DASH)
                or obj.peek_name().lower() == "attack2_part2"]
    clip_data = {}
    for obj in selected:
        clip = obj.read_typetree()
        paths = {binding["path"] for binding in clip["m_ClipBindingConstant"]["genericBindings"]
                 if binding.get("typeID") == 4}
        source_containers = sorted(path for path, pointer in envs["animations"].container.items()
                                   if pointer.m_PathID == obj.path_id)
        clip_data[obj.path_id] = {"name": clip["m_Name"], "asset_file": obj.assets_file.name,
            "source_containers": source_containers, "transform_paths": paths}
    if GRIFFIN_PART1 not in clip_data or GRIFFIN_DASH not in clip_data:
        raise ValueError("Expected Griffin reference clips were not found")
    reference_paths = clip_data[GRIFFIN_PART1]["transform_paths"]
    controller_externals = [str(item.path) for item in controller_obj.assets_file.externals]
    linked_refs = controller.get("m_AnimationClips", [])
    for clip_id, clip in clip_data.items():
        paths = clip.pop("transform_paths")
        clip["path_count"] = len(paths)
        clip["paths_shared_with_griffin_part1"] = len(paths & reference_paths)
        clip["referenced_by_griffin_controller"] = any(
            ref["m_PathID"] == clip_id and ref["m_FileID"] > 0
            and ref["m_FileID"] <= len(controller_externals)
            and clip["asset_file"] in controller_externals[ref["m_FileID"] - 1]
            for ref in linked_refs)
    result = {"apk_sha256": digest, "bundles": bundles,
        "local_glb": {"path": str(args.model), "sha256": hashlib.sha256(model_payload).hexdigest(),
            "animation_names": model_names,
            "contains_attack2_part2": any(name.lower() == "attack2_part2" for name in model_names)},
        "prefab_animator_path_id": animator.path_id,
        "prefab_controller_reference": controller_ref,
        "prefab_external_at_controller_file_id": str(animator.assets_file.externals[controller_ref["m_FileID"] - 1].path),
        "controller": {"path_id": controller_obj.path_id, "name": controller.get("m_Name", ""),
            "asset_file": controller_obj.assets_file.name, "states": states,
            "part2_state_names": [name for name in states if name.lower() == "attack2_part2"]},
        "action": {"path_id": GRIFFIN_EX_ATTACK3, "id": action.get("ActId"),
            "display_name": action.get("Name_EDT"), "part2_events": part2_events},
        "clips": clip_data,
        "limitations": ["Static serialized data and source container names only; no APK runtime execution.",
            "Path-hash overlap is supporting evidence, not a test of animation behavior."]}
    output = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.write_text(output)
    print(output, end="")


if __name__ == "__main__":
    main()
