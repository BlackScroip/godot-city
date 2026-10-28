#!/usr/bin/env python3
"""Verify and retain monster knockback evidence from the selected APK."""

import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import zipfile

from inspect_hit_feedback_native import (
    APK_SHA, METADATA_MEMBER, NATIVE_MEMBER, NATIVE_SHA, retained_method,
)

ROOT = Path(__file__).resolve().parents[1]
NAMESPACE = "Assembly-CSharp/Teamelo/ActionEngine/"
METHODS = {
    "HitAction": ["HitAction", "Deserialize", "OnHitFeedback", "GetModifyPushPower"],
    "FrameEntity": ["SetHitPointPosAndDir"],
    "PhysicalEntity": ["SetHitPointPosAndDir"],
    "ActionStatus": ["Update", "TickAction", "ProcessMoving", "GetLocalTimeScale",
                     "SetHitAndUpMove", "ProcessHitAndUpMove", "ResetForce", "Reset", "OnActionStart",
                     "ProcessEventList", "TriggerEvent", "ChangeAction", "ProcessDurationEventExit"],
    "EventActionSpeedScale": ["Enter", "Exit", "Update", "Execute"],
    "RoleUnit": ["Update", "SetHitAndUpMove"],
}


def digest(value):
    return hashlib.sha256(value).hexdigest()


def clock_boundary_example():
    """Derive a fixed-tick example without claiming an APK runtime observation."""
    combat_path = ROOT / "assets/data/combat.json"
    combat_bytes = combat_path.read_bytes()
    action = next(row for row in json.loads(combat_bytes)["actions"]
                  if row["key"] == "ActGroup_wolf/attack2")
    events = [row for row in action["events"] if row["type"] == "EET_ActionSpeedScale"
              and row.get("enabled")]
    if len(events) != 1 or events[0]["conditions"]:
        raise ValueError("Expected the unconditional wolf attack2 speed event")
    event = events[0]
    event_rate = json.loads(event["raw"])["ScaleSpeed"]
    if (action["speed"], event["time"], event["duration"], event_rate) != (1, 0, 0.2, 0.5):
        raise ValueError("Unexpected wolf attack2 clock example")

    def f32(value):
        return struct.unpack("<f", struct.pack("<f", value))[0]

    cursor, elapsed, rate, entered, active = 0, 0, 1.0, False, False
    samples = []
    for frame in range(1, 27):
        rate_before = rate
        delta_ms = int(f32(f32(f32(1.0 / 60.0) * f32(rate_before)) * f32(1000.0)))
        delta_ms = min(delta_ms, round(action["duration"] * 1000) - cursor)
        cursor += delta_ms
        transition = "none"
        if not entered and cursor >= 0:
            entered, active, elapsed, rate = True, True, 0, event_rate
            transition = "enter"
        if active:
            elapsed += delta_ms
            if elapsed > round(event["duration"] * 1000):
                active, rate, transition = False, 1.0, "exit"
        samples.append({"frame": frame, "rate_before": rate_before, "delta_ms": delta_ms,
                        "cursor_ms": cursor, "event_runtime_ms": elapsed, "rate_after": rate,
                        "motion_delta": f32(f32(f32(delta_ms) * f32(0.001)) / f32(rate)),
                        "transition": transition})
    return {"evidence_type": "Static code-derived trace; not an APK runtime measurement",
            "catalog_path": str(combat_path), "catalog_sha256": digest(combat_bytes),
            "imported_action_source": action["source"], "action_key": action["key"],
            "action_sha256": digest(json.dumps(action, sort_keys=True, separators=(",", ":")).encode()),
            "duration": action["duration"], "speed": action["speed"], "event": event,
            "assumptions": ["An ordinary ChangeAction just completed, so event multiplier is initially 1.",
                            "Each owner tick is float32(1/60); no stop, pause, buff speed or interruption occurs.",
                            "The imported action JSON is retained evidence; its old RecoveredUnity path is currently absent."],
            "samples": samples}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--lib", type=Path, required=True)
    parser.add_argument("--global-metadata", type=Path, required=True)
    parser.add_argument("--metadata-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=ROOT / "reports/monster-knockback-native-20261028.json")
    args = parser.parse_args()
    with args.apk.open("rb") as stream:
        if hashlib.file_digest(stream, "sha256").hexdigest() != APK_SHA:
            raise ValueError("Unexpected APK identity")
    native = args.lib.read_bytes()
    metadata = args.global_metadata.read_bytes()
    with zipfile.ZipFile(args.apk) as archive:
        if digest(native) != NATIVE_SHA or native != archive.read(NATIVE_MEMBER):
            raise ValueError("Native input differs from the selected APK")
        if metadata != archive.read(METADATA_MEMBER):
            raise ValueError("Metadata differs from the selected APK")
    phoff = struct.unpack_from("<Q", native, 32)[0]
    phentsize, phnum = struct.unpack_from("<HH", native, 54)
    segments = [struct.unpack_from("<IIQQQQQQ", native, phoff + i * phentsize) for i in range(phnum)]

    def virtual_at(offset):
        return next(row[3] + offset - row[2] for row in segments
                    if row[0] == 1 and row[2] <= offset < row[2] + row[5])

    def file_at(address):
        return next(row[2] + address - row[3] for row in segments
                    if row[0] == 1 and row[3] <= address < row[3] + row[5])

    verified_reports = []
    for name in ["hit-feedback-native-static.json", "monster-hit-rules-native-static.json"]:
        payload = (ROOT / "reports" / name).read_bytes()
        report = json.loads(payload)
        if report["apk_sha256"] != APK_SHA or report["member_sha256"] != NATIVE_SHA:
            raise ValueError("Retained report has a different subject")
        for row in report["methods"]:
            offset, length = int(row["file_offset"], 16), row["length"]
            if digest(native[offset:offset + length]) != row["code_sha256"]:
                raise ValueError("Retained code hash mismatch: " + row["method"])
        verified_reports.append({"path": name, "sha256": digest(payload), "verified_methods": len(report["methods"])})

    methods = []
    for cls, names in METHODS.items():
        relative = NAMESPACE + cls + ".cs"
        source = (args.metadata_root / relative).read_bytes()
        for name in names:
            method = retained_method(source.decode("utf-8"), name, "")
            offset, length = method.pop("offset"), method["length"]
            address = virtual_at(offset)
            command = ["xcrun", "llvm-objdump", "--disassemble",
                       "--start-address=" + hex(address), "--stop-address=" + hex(address + length), str(args.lib)]
            methods.append(dict(method, method=cls + "." + name, metadata_source=relative,
                                metadata_source_sha256=digest(source), file_offset=hex(offset),
                                virtual_address=hex(address), code_sha256=digest(native[offset:offset + length]),
                                assembly=subprocess.check_output(command, text=True)))
    literals = {}
    for name, address in {"hit_point_radius_ratio": 0x1287E20, "direction_epsilon": 0x1287F10,
                          "near_zero_squared": 0x1287C14, "push_ratio_and_time": 0x1287E18,
                          "push_timer_cutoff": 0x1287FB4}.items():
        offset = file_at(address)
        value = native[offset:offset + 4]
        literals[name] = {"virtual_address": hex(address), "file_offset": hex(offset),
                          "bytes": value.hex(), "float32": struct.unpack("<f", value)[0]}
    table = file_at(0x12F20C8)
    report = {
        "schema": 1, "apk_sha256": APK_SHA, "member": NATIVE_MEMBER, "member_sha256": NATIVE_SHA,
        "metadata_member": METADATA_MEMBER, "metadata_sha256": digest(metadata),
        "evidence_type": "Verified APK members, ARM64 bytes/disassembly and IL2CPP metadata; no runtime execution",
        "rea_inventory_evidence_id": "ev_a8896527552ba1a1db7688a7924f0bdb5216151e2794890521df7f2a19f75e9c",
        "rea_artifact_evidence_id": "ev_89b63e484acc2e54de490487bd1b9889d08f547cd7c8ac0c50d782ab1acf0323",
        "verified_reports": verified_reports, "methods": methods, "literals": literals,
        "clock_boundary_source_example": clock_boundary_example(),
        "direction_jump_table": {"virtual_address": "0x12f20c8", "file_offset": hex(table),
                                 "bytes": native[table:table + 4].hex(),
                                 "base": "0x2fec6c8", "branch_addresses": ["0x2fec6c8", "0x2fec904", "0x2fec6f0", "0x2fec74c"]},
        "findings": [
            {"id": "directions", "type": "static-observation", "methods": ["HitAction.OnHitFeedback"],
             "detail": "PushMode0=attacker forward,1=attackee position minus attacker position,2=HitPointDir,3=attackee position minus HitPointPos. Modes2/3 test the stored xyz Dir/Pos against squared length float32(1e-10), falling back to mode1 only then. All branches discard y and normalize only above float32(1e-5); there is no additional forward fallback. Target rotation uses the negative normalized direction, independently of the sign of push power."},
            {"id": "hit-point-producer", "type": "static-observation", "methods": ["FrameEntity.SetHitPointPosAndDir", "PhysicalEntity.SetHitPointPosAndDir"],
             "detail": "Let C be target CenterPosition and E the attack entity origin. HitPointPos=C+flat(normalize3D(E-C))*target.Radius*float32(0.9). FrameEntity uses its retained StartPosition for E and sets HitPointDir=C-E. PhysicalEntity uses its current GameObject transform position for E and transform.forward for HitPointDir."},
            {"id": "force-and-replacement", "type": "static-observation", "methods": ["ActionStatus.SetHitAndUpMove", "ActionStatus.ProcessHitAndUpMove"],
             "detail": "Signed effective force subtracts PushForceResist from absolute power and clamps at zero. Weight includes current action WeightAddValue and falls back to100 only if zero. All admitted weak hits overwrite force. Low branch only refreshes duration and remaining if abs(force)/weight>=float32(0.1); upper>=weight clears both horizontal timers and sets hit_2. Low duration is float32((float32(log2(float32(1+float32(abs(force)/weight))))+1)*float32(0.1)). Process samples current weight and pre-decrement remaining, producing speed=2*(force/weight)*remaining/T^2 and explicit Euler displacement. Remaining<=float32(.05) resets force. A negative remaining after subtraction resets force but retains that step's sampled displacement."},
            {"id": "action-clock", "type": "static-observation", "methods": ["RoleUnit.Update", "ActionStatus.Update", "ActionStatus.TickAction", "ActionStatus.ProcessMoving", "ActionStatus.GetLocalTimeScale"],
             "detail": "RoleUnit.Update sends pause-adjusted fTick*mStopTickScale to ActionStatus.Update. Update multiplies by local action scale, converts to milliseconds with truncation; TickAction clips to action remaining milliseconds. ProcessMoving converts milliseconds to float seconds, then ProcessHitAndUpMove divides by current local scale. Thus local speed cancels except for millisecond quantization, action-end clipping and intervening speed events; owner stop and battle time remain effective. RoleUnit+0x14e is mIsDeleted and skips action update, not a logic-pause flag."},
            {"id": "clock-call-order", "type": "static-observation", "methods": ["ActionStatus.Update", "ActionStatus.TickAction", "ActionStatus.ProcessEventList", "ActionStatus.ProcessMoving"],
             "detail": "Update samples the old local scale before quantizing delta. TickAction updates the integer action cursor and clips only at the full action duration. It calls ProcessEventList at VA0x2fd3d30, ProcessAttackDefList at VA0x2fd3d3c, and ProcessMoving at VA0x2fd3d48, each once with the same integer delta. This path does not split a tick at speed-event boundaries. ProcessHitAndUpMove queries the current scale after event effects."},
            {"id": "duration-event-boundaries", "type": "static-observation", "methods": ["ActionStatus.ProcessEventList", "ActionStatus.TriggerEvent", "EventActionSpeedScale.Enter", "EventActionSpeedScale.Exit"],
             "detail": "ProcessEventList enters every pending eligible event with TriggerTime<=new action cursor (VA0x2fd3f5c..0x2fd3f6c). TriggerEvent invokes duration Enter, appends the event to the active update list, and initializes its dictionary runtime to0 (VA0x2fd4e8c..0x2fd4f48). The same ProcessEventList invocation increments all active event runtimes, including newly entered events, by the entire deltaMs. It queues Exit only when runtime>Duration, not at equality (VA0x2fd4050..0x2fd4080). All new Enter calls precede all queued Exit calls. Exit calls are then performed in active-list order (VA0x2fd41bc..0x2fd4258)."},
            {"id": "speed-event-assignment", "type": "static-observation", "methods": ["EventActionSpeedScale.Enter", "EventActionSpeedScale.Exit", "EventActionSpeedScale.Update", "EventActionSpeedScale.Execute"],
             "detail": "Enter(VA0x3006068) assigns event.ScaleSpeed(+0x18) into owner.ActionStatus.ActionEventScaleSpeedModify(+0x34). Exit(VA0x3006090) assigns1. Update and Execute are return-only stubs. Overlapping speed events do not multiply and do not restore an earlier event's rate; an earlier event exiting after a later event enters can overwrite the later rate with1."},
            {"id": "clock-action-entry", "type": "static-observation", "methods": ["ActionStatus.ChangeAction", "ActionStatus.Reset", "ActionStatus.OnActionStart"],
             "detail": "Ordinary ChangeAction calls OnActionStart at VA0x2fd58cc and Reset at VA0x2fd58d4, then returns. It does not immediately call TickAction or ProcessEventList. Reset sets integer cursor0 and event/buff multipliers1. A time-zero speed event is therefore first entered during the next TickAction, after that tick was quantized using the prior multiplier1. Force/timers survive these action changes."},
            {"id": "minimum-clock-model", "type": "reconstruction-inference", "methods": ["ActionStatus.Update", "ActionStatus.TickAction", "ActionStatus.ProcessEventList", "ActionStatus.TriggerEvent", "EventActionSpeedScale.Enter", "EventActionSpeedScale.Exit"],
             "detail": "A faithful isolated motion clock needs persistent integer cursor, pending-event index, insertion-ordered active duration timers, and the last assigned event multiplier. Initialize that clock for each action entry, maintain it even without an active hit force, sample old scale for integer quantization, advance/enter/update/exit events, then divide by the newly resulting scale. Computing the multiplier from an absolute half-open window at the end cursor cannot reproduce these boundaries. A separate reconstructed motion clock does not make the existing float action engine or conditional buff event order identical to the original."},
            {"id": "action-lifecycle", "type": "static-observation", "methods": ["ActionStatus.Reset", "ActionStatus.OnActionStart", "ActionStatus.ResetForce"],
             "detail": "Reset and OnActionStart do not clear force+0x88, duration+0x94 or remaining+0x98. Force is not lost on ordinary action changes. ResetForce clears those fields. Monster admission remains based on weakness and authored action tenacity; this force path adds no blanket attack-name immunity."},
        ],
        "limitations": [
            "Metadata stubs supply identity and address ranges, not executable C# source.",
            "These are static observations and local reconstruction tests, not an original APK playthrough.",
            "Godot uses its existing CharacterBody3D collider dimensions and collision solver; Unity collision results are not claimed bit-identical.",
        ],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"methods": len(methods), "verified_prior_methods": sum(row["verified_methods"] for row in verified_reports),
                      "literals": {key: value["float32"] for key, value in literals.items()}, "report": str(args.output)}))


if __name__ == "__main__":
    main()
