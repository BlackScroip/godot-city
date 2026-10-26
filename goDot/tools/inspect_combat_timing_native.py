#!/usr/bin/env python3
"""Retain bounded, reproducible static ARM64 evidence from the supplied APK."""

import argparse
import hashlib
import json
import struct
import subprocess
import zipfile
from pathlib import Path

APK_SHA = "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505"
NATIVE_SHA = "86481018e3b55575e27d0d99a5979299b7fbbdf718698918ab5ebfbbccb68944"
MEMBER = "lib/arm64-v8a/libil2cpp.so"
METHODS = [
    ("HitStopFrame.OnHitFeedback", 0x2FECC54, 0x8C),
    ("HitStopFrame.Deserialize", 0x2FEC9D0, 0x1E8),
    ("HitStopFrame.set_StopFrameWeight", 0x2FEC964, 0x1C),
    ("AttackHit.GetBuffModifyValue", 0x2FD5B84, 0x24),
    ("BuffManager.ApplyModifyAttackHit_Val", 0x303A9F0, 0xF0),
    ("SBuffModifyAttackDef.CheckEnableModify", 0x3059BA0, 0x78),
    ("SBuffModifyAttackDef.ModifyAttackHit_Val", 0x3059C18, 0x158),
    ("BattleManager.RegisterSpecialChangeGameTimeScale", 0x308F5B4, 0x1B0),
    ("PlayerPrefsConfig_AT.LoadGameOption", 0x2DBF5C8, 0xB38),
    ("EventBattleTimeScaleModify.Enter", 0x3002634, 0x84),
    ("EventBattleTimeScaleModify.Exit", 0x30026C0, 0x64),
    ("BattleManager.RegisterChangeGameTimeScale", 0x308F494, 0x104),
    ("BattleManager.UnRegisterChangeGameTimeScale", 0x308F598, 0x1C),
    ("BattleManager.UpdateModifyTimeScale", 0x3089C28, 0x48),
    ("BattleManager.Update", 0x30885C4, 0xEF8),
    ("CommonModifyByRegisterFloat.Register", 0x2F38A1C, 0x170),
    ("CommonModifyByRegisterFloat.UnRegister", 0x2F38BF4, 0x208),
    ("CommonModifyByRegisterFloat.Update", 0x2F38DFC, 0x34C),
    ("CommonModifyByRegisterFloat.GetValueByMode", 0x2F39148, 0x1DC),
    ("CheckBuffPlayerMove.Update", 0x3048CD4, 0x124),
    ("CheckBuffPlayerMove.CheckBuff", 0x3048E04, 0xA4),
    ("CheckBuffPlayerMove.Reset", 0x3048DFC, 0x8),
    ("CheckBuffPlayerMove.GetCompareDistance", 0x3048AF8, 0x14C),
    ("SummonUnit_FunnelAttackHit.CheckAttackHitTrigger", 0x3174D74, 0x21C),
    ("SummonUnit_FunnelAttackHit.CreateAttackHitNow", 0x3175920, 0x2EC),
    ("SummonUnit_FunnelAttackHit.ProcessPendingAttackHitCreate", 0x3174660, 0x104),
    ("Time.get_unscaledDeltaTime", 0x5ECDB18, 0x28),
    ("Time.get_maximumDeltaTime", 0x5ECDBC8, 0x28),
]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", required=True, type=Path)
    parser.add_argument("--lib", required=True, type=Path)
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1] / "reports/combat-timing-native-static.json")
    args = parser.parse_args()
    with args.apk.open("rb") as stream:
        apk_hash = hashlib.file_digest(stream, "sha256").hexdigest()
    if apk_hash != APK_SHA:
        raise ValueError("This evidence map is bound to the user-supplied APK hash")
    native = args.lib.read_bytes()
    with zipfile.ZipFile(args.apk) as archive:
        member_hash = sha(archive.read(MEMBER))
    if member_hash != NATIVE_SHA or sha(native) != member_hash:
        raise ValueError("Extracted native library differs from the actual APK member")
    if native[:6] != b"\x7fELF\x02\x01":
        raise ValueError("Expected little-endian ELF64")
    phoff = struct.unpack_from("<Q", native, 32)[0]
    phentsize, phnum = struct.unpack_from("<HH", native, 54)
    segments = []
    for index in range(phnum):
        values = struct.unpack_from("<IIQQQQQQ", native, phoff + index * phentsize)
        kind, flags, offset, virtual, _, filesz, memsz, alignment = values
        if kind == 1:
            segments.append({"offset": offset, "virtual": virtual, "filesz": filesz, "memsz": memsz, "flags": flags, "alignment": alignment})

    def virtual_at(offset, length):
        for segment in segments:
            if segment["offset"] <= offset and offset + length <= segment["offset"] + segment["filesz"]:
                return segment["virtual"] + offset - segment["offset"]
        raise ValueError("Evidence range is outside an ELF load segment")

    def file_at(virtual, length):
        for segment in segments:
            if segment["virtual"] <= virtual and virtual + length <= segment["virtual"] + segment["filesz"]:
                return segment["offset"] + virtual - segment["virtual"]
        raise ValueError("Virtual evidence range is outside an ELF load segment")

    literals = {}
    for name, virtual in [("unit_stop_target_scale", 0x1287D08), ("stop_frame_weight_limit", 0x12882B4)]:
        offset = file_at(virtual, 4)
        literals[name] = {"virtual_address": hex(virtual), "file_offset": hex(offset), "bytes": native[offset:offset + 4].hex(), "float32": struct.unpack_from("<f", native, offset)[0]}
    table_offset = file_at(0x12F2207, 11)
    stop_target = 0x305DC78 + native[table_offset + 10] * 4
    if stop_target != 0x305DD54:
        raise ValueError("The type-11 switch does not point to the retained direct-float branch")

    methods = []
    for name, offset, length in METHODS:
        virtual = virtual_at(offset, length)
        command = ["xcrun", "llvm-objdump", "--disassemble", f"--start-address={virtual:#x}", f"--stop-address={virtual + length:#x}", str(args.lib)]
        assembly = subprocess.check_output(command, text=True)
        methods.append({"method": name, "file_offset": hex(offset), "virtual_address": hex(virtual), "length": length, "code_sha256": sha(native[offset:offset + length]), "command": command, "assembly": assembly})
    report = {
        "schema": 1,
        "evidence_type": "ordinary-shell-static-disassembly; not REA Evidence and not runtime observation",
        "apk_sha256": apk_hash,
        "member": MEMBER,
        "member_sha256": member_hash,
        "address_source": "Cpp2IL DiffableCs Address.Offset used as file offset; virtual addresses independently derived from ELF64 PT_LOAD",
        "load_segments": segments,
        "hit_stop_literals": literals,
        "hit_stop_modifier_switch": {"table_virtual_address": "0x12f2207", "table_file_offset": hex(table_offset), "bytes": native[table_offset:table_offset + 11].hex(), "type_11_branch": hex(stop_target)},
        "literal_milliseconds_to_seconds": {"file_offset": "0x1288234", "float32": struct.unpack_from("<f", native, 0x1288234)[0]},
        "methods": methods,
        "findings": [
            {"id": "source-hit-stop", "kind": "observation", "methods": ["HitStopFrame.OnHitFeedback", "BattleManager.RegisterSpecialChangeGameTimeScale"], "detail": "Unit-hit feedback loads AttackHit at feedback-data+0x28; adds AttackHit.GetBuffModifyValue(type11) to serialized weight; registers type1 UnitStopFrame keyed by that AttackHit. The global target scale is the retained 0.12 float literal. Duration is max(0,weight+modifier)*targetScale*(EnableHitStopFrame/100); duration counts the battle-scaled register clock. SelfAffectedRatio is not read here. A ConditionalWeakTable deduplicates positive registrations by AttackHit identity; distinct hits replace the common UnitStopFrame register key."},
            {"id": "source-hit-stop-modifier", "kind": "observation", "methods": ["AttackHit.GetBuffModifyValue", "BuffManager.ApplyModifyAttackHit_Val", "SBuffModifyAttackDef.CheckEnableModify", "SBuffModifyAttackDef.ModifyAttackHit_Val"], "detail": "AttackHit delegates to its owner's BuffManager, which sums matching buff virtual-method values. SBuffModifyAttackDef only accepts a nonzero ActionAttackDef Id contained in AttackDefIdList. The verified type11 switch branch reads settings+0x70 HitFeedBack_StopFrameAdd directly as float, without multiplying buff layers."},
            {"id": "source-hit-stop-option", "kind": "observation", "methods": ["PlayerPrefsConfig_AT.LoadGameOption"], "anchors": ["VA0x2dc39d8..0x2dc3a4c"], "detail": "PlayerPrefs hit-stop option loads with default100, accepts only0/50/100, and replaces invalid values with100. RegisterSpecialChangeGameTimeScale returns without triggering or recording the AttackHit when this percentage is <=0."},
            {"id": "source-hit-stop-deserialization", "kind": "observation", "methods": ["HitStopFrame.Deserialize", "HitStopFrame.set_StopFrameWeight"], "detail": "The setter clamps weight to0..0.3, but Deserialize stores its parsed float directly at+0x10 and does not call that setter. Recovered serialized weights therefore must not acquire a new runtime0.3 clamp."},
            {"id": "global-enter-exit", "kind": "observation", "methods": ["EventBattleTimeScaleModify.Enter", "EventBattleTimeScaleModify.Exit"], "detail": "Enter passes actor instance string, authored scale and integer event duration multiplied by the retained 0.001 float literal to RegisterChangeGameTimeScale. Exit unregisters the same actor string."},
            {"id": "global-min-register", "kind": "observation", "methods": ["BattleManager.UpdateModifyTimeScale", "CommonModifyByRegisterFloat.GetValueByMode"], "detail": "UpdateModifyTimeScale calls register Update(fTick), then when unpaused calls GetValueByMode(mode0 MinValue,default1) and writes BattleTimeScale(+0x88) and last scale(+0x8c)."},
            {"id": "global-duration-clock", "kind": "observation", "methods": ["BattleManager.Update", "Time.get_unscaledDeltaTime", "Time.get_maximumDeltaTime"], "anchors": ["VA0x308c8bc calls Time.get_unscaledDeltaTime VA0x5ed1b18", "VA0x308c8c8 calls Time.get_maximumDeltaTime VA0x5ed1bc8", "VA0x308c8cc..0x308c8d8 multiplies min(unscaledDeltaTime,maximumDeltaTime) by BattleTimeScale(+0x88), keeping result in s8", "VA0x308c964..0x308c974 and VA0x308d2a0..0x308d2b0 set s8=0 if pause(+0x90)", "VA0x308cf08..0x308cf0c and VA0x308d490..0x308d494 pass s8 as fTick to UpdateModifyTimeScale"], "detail": "Register duration counts battle-scaled time. CommonModify Update subtracts fTick and removes timed entries only below zero; duration -1 is permanent."},
            {"id": "move-distance", "kind": "observation", "methods": ["CheckBuffPlayerMove.Update", "CheckBuffPlayerMove.CheckBuff", "CheckBuffPlayerMove.Reset"], "detail": "When CheckMoveDistance is true, Update accumulates owner position-vector distance. CheckBuff compares distance >= GetCompareDistance. CheckMove and CompareType are used by the separate time branch. Reset zeros accumulated time and distance."},
            {"id": "funnel-phases", "kind": "observation", "methods": ["SummonUnit_FunnelAttackHit.CheckAttackHitTrigger", "SummonUnit_FunnelAttackHit.CreateAttackHitNow"], "detail": "CheckAttackHitTrigger emits TriggerEffectName_NoDelay from funnel transform. Positive TriggerDelayTime queues pending attack creation, otherwise CreateAttackHitNow runs immediately. CreateAttackHitNow emits TriggerEffectName_Delay immediately before creating the attack."},
        ],
        "limitations": [
            "REA Ghidra provider unavailable on this host; no decompiler output or fabricated REA Evidence IDs are supplied.",
            "Metadata names and field identities supplement ARM64 static code. No execution or FPS is observed by this tool.",
            "A register branch for scales below1 can cap duration/scale to3s under a global flag whose meaning remains unresolved; no speculative cap is implemented.",
            "Funnel native Init/Update, target acquisition, custom-message lifetime, exact repeat-count and all attack entity types are outside this bounded static investigation.",
            "Combat emits admission/phase records. World integration and actual device frame pacing require separate verification.",
        ],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"output": str(args.output), "methods": len(methods), "apk_sha256": apk_hash, "member_sha256": member_hash}))


if __name__ == "__main__":
    main()
