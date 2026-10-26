#!/usr/bin/env python3
"""Retain APK-bound ARM64 boss action, health-lock and one-shot shield evidence."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
import zipfile

from inspect_hit_feedback_native import (
    APK_SHA, METADATA_MEMBER, NATIVE_MEMBER, NATIVE_SHA, retained_method,
)


NAMESPACE = "Assembly-CSharp/Teamelo/ActionEngine/"
SOURCE_PATHS = {"StringExtention": "Assembly-CSharp/StringExtention.cs"}
METHODS = {
    "SBuffLockHp": [
        "Init", "RefreshSettingData", "OnOwnerHpChange",
        "IsCurrentLockHpHighestMinInOwner", "TriggerLowerBoundBuffNextFrame",
        "MoveNext", "OnDispose", "SBuffLockHp",
    ],
    "SBuffLockHpSettingData": ["SBuffLockHpSettingData"],
    "RoleUnit": [
        "ChangeHP", "RemoveAllLockHpBuff", "ClampHpByLockRate",
        "OnActiveLockHp", "get_IsLockHp", "SetLockHpActive", "ChangeSheild",
    ],
    "BuffManager": ["OnOwnerHpChange"],
    "BuffTriggerDefProperty": ["AddBuff"],
    "Player": ["OnActiveLockHp"],
    "SBuffShield": ["Init", "CaculateShield", "OnDispose"],
    "BattleManager": ["EnterBattleShow_EnemyBoss"],
    "ActionStatus": [
        "HasAction", "PreChangeAction", "ProcessHandleActionInterrupt",
        "TickAction", "ChangeAction",
    ],
    "StringExtention": ["IsNotNullAndEmpty"],
}
METADATA_ONLY = [
    "Buff", "SBuffLockHpProperty", "SBuffShieldProperty",
    "SBuffShieldSettingsData", "EAttributeType", "Monster", "MonsterProperty",
]
FINDINGS = [
    {
        "id": "negative-count-means-unlimited", "kind": "observation",
        "methods": ["SBuffLockHp.OnOwnerHpChange"],
        "virtual_ranges": ["0x305c6a4-0x305c6e0", "0x305c76c-0x305c80c"],
        "detail": "Config MaxLockCount at setting+0x28 uses its sign bit to choose the unlimited branch. Any negative value has unlimited lower-bound protection; it is not compared to an increasing used-count. Runtime mLockHealthCount at buff+0xb0 is remaining finite uses.",
    },
    {
        "id": "health-range-and-admission", "kind": "observation",
        "methods": ["SBuffLockHp.OnOwnerHpChange"],
        "virtual_ranges": ["0x305c648-0x305c6d4", "0x305c810-0x305c858"],
        "detail": "Requires current owner, selected setting, layer count at+0x9c>=1 and highest-min predicate success. Reads MaxHp attribute1. Upper=min(MaxHp,MaxHp*(float32(MaxPrecent)*float32(0.001))); lower=max(1,MaxHp*(float32(MinPrecent)*float32(0.001))). Candidate is curValue+changeValue. Unlimited or positive finite remaining uses apply both bounds. Exhausted finite remaining applies only the upper bound. Writes clampedHP-curValue back through changeValue. Nonpositive final HP schedules removal via BuffManager.RemoveBuff.",
    },
    {
        "id": "finite-consumption-only-at-damage-floor", "kind": "observation",
        "methods": ["SBuffLockHp.OnOwnerHpChange"],
        "virtual_ranges": ["0x305c6d8-0x305c730"],
        "detail": "Finite count decrements only when changeValue<0, candidate<lower and the clamped result<=lower. A heal or upper-cap adjustment does not consume a finite use. Stores remaining-1, sets owner.mIsLockHpActive(+0x1a0)=true, then invokes OnActiveLockHp. No same-frame grace period appears here: a second hit after remaining reaches0 receives no lower-bound protection.",
    },
    {
        "id": "highest-live-lower-bound-wins", "kind": "observation",
        "methods": ["SBuffLockHp.IsCurrentLockHpHighestMinInOwner"],
        "virtual_ranges": ["0x305c8c0-0x305c99c"],
        "detail": "Scans the manager's complete buff list. Excludes self, disposed entries and entries without settings. Another SBuffLockHp suppresses this entire handler only if its configured MaxLockCount is negative or its remaining count>=1, and its MinPrecent is strictly greater than this setting's MinPrecent. Equal minima do not suppress one another. Suppression also bypasses this handler's upper cap.",
    },
    {
        "id": "count-initialization-and-refresh", "kind": "observation",
        "methods": ["SBuffLockHp.Init", "SBuffLockHp.RefreshSettingData"],
        "virtual_ranges": ["0x305c3e4-0x305c438", "0x305c570-0x305c5d4"],
        "detail": "Initializes mLockHealthCount from selected MaxLockCount and remembers the configured maximum at+0xb8. On refresh, a negative maximum sets remaining=-1; moving from a negative previous maximum to finite sets remaining to the new maximum. Otherwise clips existing remaining to[0,newMaximum], preserving consumption instead of refilling. mLockCountInited at+0xb4 prevents repeated initialization.",
    },
    {
        "id": "unlimited-trigger-contradicts-editor-text", "kind": "observation",
        "methods": ["SBuffLockHp.OnOwnerHpChange", "SBuffLockHp.TriggerLowerBoundBuffNextFrame", "SBuffLockHp.MoveNext"],
        "virtual_ranges": ["0x305c77c-0x305c80c", "0x305c9b0-0x305caf0", "0x305cc1c-0x305ccc8"],
        "detail": "The setting editor annotation says negative MaxLockCount is unlimited and does not trigger the active buff. This APK's native unlimited branch instead sets the active flag, invokes OnActiveLockHp and schedules ActiveTriggerBuff whenever clamping changes candidate, including an upper-bound correction. Neither the scheduling method nor its coroutine excludes negative MaxLockCount. Native instructions take precedence over the stale editor annotation.",
    },
    {
        "id": "deferred-trigger-and-exhausted-removal", "kind": "observation",
        "methods": ["SBuffLockHp.TriggerLowerBoundBuffNextFrame", "SBuffLockHp.MoveNext", "BuffTriggerDefProperty.AddBuff"],
        "virtual_ranges": ["0x305ca14-0x305cae0", "0x305cbf8-0x305ccc8"],
        "detail": "With the scene coroutine host available, the coroutine first yields null, then on its next continuation requires owner, manager and selected settings, calls ActiveTriggerBuff.AddBuff and removes the original lock buff only when remaining==0. Unlimited remaining=-1 is not removed. With no coroutine host, the fallback directly calls ActiveTriggerBuff.AddBuff; the examined fallback lacks the coroutine's count-zero cleanup. Scheduler behavior and exact rendered-frame latency are not runtime-observed.",
    },
    {
        "id": "health-call-order-and-active-flag", "kind": "observation",
        "methods": ["RoleUnit.ChangeHP", "RoleUnit.RemoveAllLockHpBuff", "SBuffLockHp.OnDispose", "RoleUnit.OnActiveLockHp", "RoleUnit.get_IsLockHp", "RoleUnit.SetLockHpActive", "Player.OnActiveLockHp"],
        "virtual_ranges": ["0x31676cc-0x3167800", "0x305c448-0x305c458", "0x316b258-0x316b26c"],
        "detail": "ChangeHP calls BuffManager.OnOwnerHpChange(ref changeValue,currentHP) before final health/death processing. A negative change leaving health<1 clears all health-lock buffs before death. Lock disposal clears owner+0x1a0. RoleUnit.OnActiveLockHp is a return-only stub; its getter/setter only read/write that bool. Player's override follows a message/effect dispatch path and does not install a GodRemainTime timer in this examined method. Do not treat the notification bool as an additional damage immunity window.",
    },
    {
        "id": "constructor-and-independent-hp-cap", "kind": "observation",
        "methods": ["SBuffLockHpSettingData.SBuffLockHpSettingData", "RoleUnit.ClampHpByLockRate"],
        "virtual_ranges": ["0x305be78-0x305be88", "0x31654b8-0x3165598"],
        "detail": "Lock setting constructor defaults MaxPrecent=1000,MinPrecent=1,MaxLockCount=-1. The misspelled Precent names are original metadata. RoleUnit.ClampHpByLockRate independently uses attribute146 HpMaxLimitLockRate to cap currentHP at MaxHp*(1000-rate)*0.001 when rate>0; it is separate from SBuffLockHp's health floor.",
    },
    {
        "id": "shield-one-shot-init", "kind": "observation",
        "methods": ["SBuffShield.Init", "SBuffShield.OnDispose"],
        "virtual_ranges": ["0x3069cd8-0x3069e00", "0x3069f98-0x3069f9c"],
        "detail": "Init selects the level setting, calls CaculateShield once, and returns false after calculation. When selection is missing, AttribSource Self0 can fall back to the first setting in a nonempty list; CasterUnit1 does not use that fallback. OnDispose only delegates to the base buff implementation. This shield buff is an init-time change to the role's shield amount, rather than a retained timer that grants shield repeatedly.",
    },
    {
        "id": "shield-calculation", "kind": "observation",
        "methods": ["SBuffShield.CaculateShield", "RoleUnit.ChangeSheild"],
        "virtual_ranges": ["0x3069e14-0x3069f8c"],
        "detail": "Property AttribSource0 uses the current manager owner and1 uses caster as the attribute source and shield recipient. Reads the configured attribute. For Add mode and a present caster, multiplier=1+caster.ShieldEmpower(attribute12)*0.001; otherwise multiplier=1. Computes float32(attribute*MulValue*0.001+AddValue*0.001)*multiplier, truncates to integer, takes abs for Reduce mode, applies positive MinShieldValue/MaxShieldValue limits, negates Reduce mode and calls RoleUnit.ChangeSheild. This source choice is preserved rather than assuming every shield affects the current owner.",
    },
    {
        "id": "boss-show-requests-configured-action", "kind": "observation",
        "methods": ["BattleManager.EnterBattleShow_EnemyBoss", "ActionStatus.PreChangeAction", "ActionStatus.HasAction", "StringExtention.IsNotNullAndEmpty"],
        "virtual_ranges": ["0x308f7f0-0x308f864", "0x2fd685c-0x2fd6898"],
        "detail": "EnterBattleShow_EnemyBoss reads boss.MonsterProperty at+0x1a8, checks BossAct at property+0x40 for nonempty text and requests it through boss.ActionStatus(+0xa8).PreChangeAction at VA0x308f84c. VA0x308f844 only loads the BossAct argument; it is not a ChangeAction call. PreChangeAction calls HasAction, then writes an existing action id to mInterruptNextActionId at ActionStatus+0xc0. It does not enter the requested action synchronously. The same boss-show method subsequently reads BossActTime at property+0x48. This proves a pending BossAct request during boss presentation, not that FirstAct at property+0x38 is absent or bypassed during initialization.",
    },
    {
        "id": "pending-action-consumed-after-tick-work", "kind": "observation",
        "methods": ["ActionStatus.TickAction", "ActionStatus.ProcessHandleActionInterrupt", "ActionStatus.ChangeAction", "StringExtention.IsNotNullAndEmpty"],
        "virtual_ranges": ["0x2fd3d28-0x2fd3d74", "0x2fd4720-0x2fd477c"],
        "detail": "TickAction processes current-action events, attack definitions and movement before calling ProcessHandleActionInterrupt at VA0x2fd3d50. That method checks the pending id for nonempty text, calls ChangeAction at VA0x2fd4758 with interrupt=true in w3, then clears mInterruptNextActionId and returns whether a request was present. A handled pending request bypasses the following action-interrupt-list processing. Exact deltaTime at the ChangeAction call and rendered-frame timing are not established here. Selecting BossAct as a spawn-time first action in a reconstruction is a scheduling choice; it is not equivalent to this native deferred request.",
    },
]


def sha(payload):
    return hashlib.sha256(payload).hexdigest()


def source_evidence(raw):
    lines = raw.decode("utf-8").splitlines()
    return {
        "sha256": sha(raw),
        "field_metadata_excerpts": [
            {"line": index + 1, "excerpt": "\n".join(lines[max(0, index - 4):index + 1])}
            for index, line in enumerate(lines) if "//Field offset:" in line
        ],
        "editor_annotations": [
            {"line": index + 1, "text": line.strip()}
            for index, line in enumerate(lines) if "[EditorProperty(" in line
        ],
        "enum_declarations": [
            {"line": index + 1, "text": line.strip()}
            for index, line in enumerate(lines) if re.search(r"^\s*\w+ = -?\d+[,]?$", line)
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--lib", type=Path, required=True)
    parser.add_argument("--global-metadata", type=Path, required=True)
    parser.add_argument("--metadata-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1] / "reports/boss-health-native-static.json")
    args = parser.parse_args()
    with args.apk.open("rb") as stream:
        if hashlib.file_digest(stream, "sha256").hexdigest() != APK_SHA:
            raise ValueError("This native report requires the audited APK")
    native = args.lib.read_bytes()
    metadata = args.global_metadata.read_bytes()
    with zipfile.ZipFile(args.apk) as archive:
        if sha(native) != NATIVE_SHA or sha(archive.read(NATIVE_MEMBER)) != NATIVE_SHA:
            raise ValueError("Native library does not match the APK")
        if metadata != archive.read(METADATA_MEMBER):
            raise ValueError("Global metadata does not match the APK")
    if native[:6] != b"\x7fELF\x02\x01":
        raise ValueError("Expected little-endian ELF64")
    if struct.unpack_from("<II", metadata) != (0xFAB11BAF, 31):
        raise ValueError("Expected audited IL2CPP metadata version31")
    phoff = struct.unpack_from("<Q", native, 32)[0]
    phentsize, phnum = struct.unpack_from("<HH", native, 54)
    segments = []
    for index in range(phnum):
        kind, flags, offset, va, _, filesz, memsz, alignment = struct.unpack_from("<IIQQQQQQ", native, phoff + index * phentsize)
        if kind == 1:
            segments.append({"file_offset": offset, "virtual_address": va, "file_size": filesz, "memory_size": memsz, "flags": flags, "alignment": alignment})

    def virtual_at(offset, length):
        for segment in segments:
            if segment["file_offset"] <= offset and offset + length <= segment["file_offset"] + segment["file_size"]:
                return segment["virtual_address"] + offset - segment["file_offset"]
        raise ValueError("Evidence range lies outside ELF PT_LOAD")

    methods, sources = [], {}
    for cls, names in METHODS.items():
        relative = SOURCE_PATHS.get(cls, NAMESPACE + cls + ".cs")
        raw = (args.metadata_root / relative).read_bytes()
        sources[relative] = source_evidence(raw)
        for name in names:
            method = retained_method(raw.decode("utf-8"), name, "")
            offset, length = method.pop("offset"), method["length"]
            va = virtual_at(offset, length)
            command = ["xcrun", "llvm-objdump", "--disassemble", "--start-address=" + hex(va), "--stop-address=" + hex(va + length), str(args.lib)]
            methods.append({"method": cls + "." + name, "metadata_source": relative, **method,
                            "file_offset": hex(offset), "virtual_address": hex(va),
                            "code_sha256": sha(native[offset:offset + length]),
                            "command": command, "assembly": subprocess.check_output(command, text=True)})
    for cls in METADATA_ONLY:
        relative = NAMESPACE + cls + ".cs"
        sources[relative] = source_evidence((args.metadata_root / relative).read_bytes())
    literals = {}
    for name, offset, fmt in [
        ("per_thousand_scale", 0x1288234, "<f"),
        ("lock_default_max_and_min", 0x1289180, "<ii"),
    ]:
        size = struct.calcsize(fmt)
        payload = native[offset:offset + size]
        literals[name] = {"file_offset": hex(offset), "virtual_address": hex(virtual_at(offset, size)),
                          "bytes": payload.hex(), "values": list(struct.unpack(fmt, payload))}
    report = {
        "schema": 1, "evidence_type": "ordinary-shell-static-disassembly; not REA Evidence and not runtime observation",
        "apk_sha256": APK_SHA, "member": NATIVE_MEMBER, "member_sha256": NATIVE_SHA,
        "metadata_member": METADATA_MEMBER, "metadata_member_sha256": sha(metadata),
        "address_source": "Cpp2IL DiffableCs Address.Offset identifies file ranges; virtual addresses are independently derived from ELF64 PT_LOAD",
        "elf_load_segments": segments, "metadata_sources": sources,
        "literals": literals, "methods": methods, "findings": FINDINGS,
        "limitations": [
            "No APK execution, live frame timing, visual parity or device performance was observed.",
            "Cpp2IL stubs identify signatures, fields and annotations; their empty bodies are not executable logic. Conclusions use retained native bytes and disassembly.",
            "Raw APK member and global metadata bytes are hash-bound; metadata source hashes retain labels but do not prove Cpp2IL generation independently.",
            "Coroutine scheduling is inferred from its retained state machine. Fallback behavior without a live host is kept separate.",
            "The boss presentation's pending action request is retained; this report does not establish FirstAct initialization order or exact presentation/tick timing.",
            "This report does not verify all serialized Boss configurations or AI/action transitions across APK versions.",
        ],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"output": str(args.output), "methods": len(methods), "findings": len(FINDINGS), "apk_sha256": APK_SHA}))


if __name__ == "__main__":
    main()
