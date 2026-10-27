"""Reproduce bounded enemy-health ARM64 evidence from the supplied APK."""

import argparse
import bisect
import hashlib
import json
from pathlib import Path
import re
import struct
import zipfile

from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM


APK_SHA256 = "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505"
SELECTION = {
    "HpStateBar": None,
    "EnemyBossHpState": None,
    "Box_UnitState": None,
    "Panel_PlayerBattleCtrl_BattleSysWnd": [
        "CreateEnemyStateBox", "SetEnemyState", "UpdateEnemyState",
        "GetTargetEnemyState", "RemoveEnemyStateBox", "void TickUpdate",
        "UpdateStateFollowEnemy", "UpdateByBattleCtrl",
    ],
    "Panel_PlayerBattleCtrl": ["UpdateBossInfo"],
    "Monster": ["void TickUpdate", "OnHp", "OnDead", "InitData", "void Update", "GetSpecialMonsterName", "get_EnemyType", "get_MonsterStaticStatus", "float GetAttribute("],
    "RoleUnit": ["get_IsLockHp"],
    "BattleUIMgr": ["SetUIFollowWorldPos"],
    "RoleUnitEnhanceManager": ["GetCurEnhanceCombineName"],
    "SlicedFilledImage": ["set_fillAmount"],
}
METHOD_RE = re.compile(
    r'\[Address\(RVA = "0x[0-9A-F]+", Offset = "0x([0-9A-F]+)", Length = "0x([0-9A-F]+)"\)\]'
    r'\s*(?:\[[^\n]+\]\s*)+([^\n]+)'
)


def findings():
    observations = [
        {
            "id": "apk-health-fill",
            "evidence": ["apk-health-native-0x2d0d1ec", "apk-health-native-0x2d0e594", "apk-health-native-0x2d0e664"],
            "statement": "HpStateBar.Init clamps finite input to [0,2], stores main=min(value,1), and overcap=max(value-1,0). The overcap image is active exactly when its clamped [0,1] value is positive. Amount mode writes Image.fillAmount; Scale mode writes Transform.localScale=(value,1,1). There is no multi-segment counter in these methods.",
            "key_instructions": ["0x2d0d1f4..0x2d0d21c", "0x2d0d238..0x2d0d254", "0x2d0e608..0x2d0e644"],
        },
        {
            "id": "apk-health-follow",
            "evidence": ["apk-health-native-0x2d0e74c"],
            "statement": "Update applies the main value immediately and smooths follow += (main-follow)*0.1 once per rendered Update. This interpolation is not multiplied by deltaTime. Amount reads follow.fillAmount, Scale reads follow.transform.localScale.x. deltaTime only advances the shake limiter's one-second timer in this method.",
            "key_instructions": ["0x2d0e7a8..0x2d0e7e0", "0x2d0e848..0x2d0e870"],
        },
        {
            "id": "apk-health-hit-shake",
            "evidence": ["apk-health-native-0x2d0d1ec", "apk-health-native-0x2d0e4c0", "apk-health-native-0x2d0e8bc", "apk-health-native-0x2d0e74c"],
            "statement": "Init triggers shake if new main or overcap decreases. TriggerShake permits three calls per one-second window, completes an existing tween, then DOPunchScale(Vector3.one*strength,duration,vibrato,elasticity=0). Constructor defaults are strength=0.15,duration=0.12,vibrato=8; serialized prefab overrides remain possible. ChangeAnim is an empty ret.",
            "key_instructions": ["0x2d0d218..0x2d0d234", "0x2d0e4cc..0x2d0e4f8", "0x2d0e534..0x2d0e564", "0x2d0e758..0x2d0e77c"],
        },
        {
            "id": "apk-health-normal-elite",
            "evidence": ["apk-health-native-0x30f5ac8", "apk-health-native-0x315e7e0", "apk-health-native-0x30c7114"],
            "statement": "For Normal=0 and Elite=1, first init sets DisplayHp=true, DisplaySheildBar=true, DisplayDamageTotal=false, DisplayEliteIcon=(type==Elite), and DisplayText=(GetSpecialMonsterName()!=empty). Text is that special name, not a numeric HP caption. The special name is localized active enhancement names joined with spaces, then one space and MonsterStaticStatus.Name; no enhancements returns empty. Each update supplies GetAttribute(CurHpRatio=3)*0.001 to HP and GetAttribute(CurArmor=6)/GetAttribute(MaxHp=1) to the field named SheildBar.",
            "key_instructions": ["0x30f5e70..0x30f5f0c", "0x30f5f18..0x30f5f80", "0x315e818..0x315e890", "0x30c7218..0x30c7274"],
        },
        {
            "id": "apk-health-visibility-follow",
            "evidence": ["apk-health-native-0x30f5ac8", "apk-health-native-0x2d0d080", "apk-health-native-0x30e7100", "apk-health-native-0x315cd9c", "apk-health-native-0x30f67cc"],
            "statement": "Monster runtime init hides its original world HUD, keys EnemyStateBoxId by unit ID, and creates a separate state box. Normal uses the normal prefab; every nonzero type uses the elite prefab. Live Normal/Elite/Boss boxes call SwitchDisplay(true); dead units call false while retaining follow; deleted units remove the box. SwitchDisplay changes CanvasGroup.alpha by (target-alpha)*0.2 per invocation. Follow projects URoleUnit's HUD target Transform position to screen then UI anchoredPosition. Boss overhead boxes initialize all five display flags false.",
            "key_instructions": ["0x315d0bc..0x315d138", "0x30f6890..0x30f68b4", "0x30f5d28..0x30f5e5c", "0x2d0d0ec..0x2d0d130", "0x30f5ff8..0x30f6028"],
        },
        {
            "id": "apk-health-boss-selection-values",
            "evidence": ["apk-health-native-0x30eb75c", "apk-health-native-0x2d0de10"],
            "statement": "UpdateBossInfo selects the first entry of GetCurWaveAliveBossList, activates the boss panel while one exists and hides it otherwise. HP comes from GetAttribute(CurHp=2), GetAttribute(MaxHp=1). UpdateHpInfo sends current/total to HpStateBar and formats each raw float with Single.ToString(\"f0\"), joined by '/'. It applies no preceding Ceil/Floor operation. Name comes from MonsterStaticStatus.Name. UpdateBossInfo does not call UpdateLevel or UpdateSpecialBarInfo.",
            "key_instructions": ["0x30eb7dc..0x30eb834", "0x30eb83c..0x30eb888", "0x2d0dedc..0x2d0df18", "0x30eb8ec..0x30eb92c"],
        },
        {
            "id": "apk-health-boss-shield",
            "evidence": ["apk-health-native-0x30eb75c", "apk-health-native-0x2d0df50", "apk-health-native-0x2e2df08"],
            "statement": "Boss shield uses GetAttribute(CurSheild=5), truncated to int, and max HP. Positive shield enables first layer and computes r=curShield/maxHp. Native comparisons replace r in the inclusive interval [0.01,0.05] with 0.05; other positive ratios remain unchanged. First layer receives r. Second layer is active only when r>1 and receives r-1; each SlicedFilledImage setter clamps its own fill. Shield<=0 disables both layers, zeros both fills, and clears text. Positive text is Int32.ToString(\"f0\").",
            "key_instructions": ["0x30eb894..0x30eb8e8", "0x2d0e018..0x2d0e0c0", "0x2d0e0c4..0x2d0e174", "0x2d0e178..0x2d0e1f4"],
        },
        {
            "id": "apk-health-special-api",
            "evidence": ["apk-health-native-0x2d0e214"],
            "statement": "UpdateSpecialBarInfo(display,current,total) supplies current/total to its HpStateBar, toggles that bar's GameObject with display, and formats its text with f0/f0. The text object's visibility is not toggled in this method. The complete executable-section B/BL scan found no direct incoming calls to this method or UpdateLevel.",
            "key_instructions": ["0x2d0e2a0..0x2d0e2cc", "0x2d0e304..0x2d0e35c"],
        },
        {
            "id": "apk-health-lock-animation",
            "evidence": ["apk-health-native-0x2d0dc58", "apk-health-native-0x2d0dd10"],
            "statement": "SetBossMonster only resets on an object change: previous lock=false and animation GameObject hidden. TickUpdate exits for null/dead bosses. On an IsLockHp state transition it activates the animation object and plays BattlePlayerCtrl_BossInvincible when true or BattlePlayerCtrl_BossInvincible_Close when false. The state comes from RoleUnit.mIsLockHpActive at +0x1a0; prior state is EnemyBossHpState+0x78.",
            "key_instructions": ["0x2d0dc88..0x2d0dcfc", "0x2d0dd54..0x2d0dd74", "0x2d0dda8..0x2d0ddfc"],
        },
    ]
    inferences = [
        {"id": "apk-health-inference-overcap", "based_on": ["apk-health-fill"], "statement": "The supported excess HP display is one extra layer up to 200% max HP; this bounded path does not support arbitrary numbered boss segments."},
        {"id": "apk-health-inference-armor-name", "based_on": ["apk-health-normal-elite", "apk-health-boss-shield"], "statement": "The ordinary/elite component named SheildBar displays armor, while the boss SlicedFilledImage pair displays shield. Reimplementations should bind those two sources separately despite the misleading common field naming."},
    ]
    unknowns = [
        "Original APK execution, exact frame timing and runtime screen captures were not observed in this offline task.",
        "No direct B/BL callers were found for special-bar or boss-level update APIs. Reflection, virtual/indirect calls, remote configuration and exceptional runtime paths are outside this negative-search boundary; no Monster special-bar source can be asserted.",
        "Visual prefab geometry, textures, serialized shake overrides and AnimationClip curves are outside this native report; consult the separate matching-APK prefab report.",
        "No guard for totalValue==0 or maxHp==0 is present in the selected division sites. NaN/infinity edge behavior is not inferred as intended gameplay behavior.",
    ]
    return observations, inferences, unknowns


def digest(data):
    return hashlib.sha256(data).hexdigest()


def inspect(apk, native, metadata, stubs):
    apk_sha256 = digest(apk.read_bytes())
    if apk_sha256 != APK_SHA256:
        raise ValueError("APK identity differs from the task target")
    data = native.read_bytes()
    metadata_data = metadata.read_bytes()
    with zipfile.ZipFile(apk) as package:
        native_member = "lib/arm64-v8a/libil2cpp.so"
        metadata_member = "assets/bin/Data/Managed/Metadata/global-metadata.dat"
        if digest(package.read(native_member)) != digest(data):
            raise ValueError("Native file does not match APK")
        if digest(package.read(metadata_member)) != digest(metadata_data):
            raise ValueError("Metadata file does not match APK")
    phoff = struct.unpack_from("<Q", data, 32)[0]
    entsize, count = struct.unpack_from("<HH", data, 54)
    segments = []
    for i in range(count):
        typ, _, off, va, _, filesz, _, _ = struct.unpack_from("<IIQQQQQQ", data, phoff + i * entsize)
        if typ == 1:
            segments.append((off, off + filesz, va))

    def virtual(offset):
        return next(va + offset - lo for lo, hi, va in segments if lo <= offset < hi)

    def file_offset(address):
        return next(lo + address - va for lo, hi, va in segments if va <= address < va + hi - lo)

    shoff = struct.unpack_from("<Q", data, 40)[0]
    shsize, shcount, shstrings = struct.unpack_from("<HHH", data, 58)
    sections = [struct.unpack_from("<IIQQQQIIQQ", data, shoff + i * shsize) for i in range(shcount)]
    string_section = sections[shstrings]
    section_names = data[string_section[4]:string_section[4] + string_section[5]]
    relocations, code_sections = {}, []
    for section in sections:
        name = section_names[section[0]:].split(b"\0", 1)[0].decode()
        if name == ".rela.dyn":
            for pos in range(section[4], section[4] + section[5], 24):
                destination, kind, addend = struct.unpack_from("<QQq", data, pos)
                if kind == 0x403:
                    relocations[destination] = addend
        if section[2] & 4:
            code_sections.append(section)

    def literal(slot):
        pointer = relocations[slot]
        encoded = struct.unpack_from("<Q", data, file_offset(pointer))[0]
        if encoded >> 29 != 5:
            raise ValueError("Selected slot is not an encoded IL2CPP string literal")
        index = (encoded & 0x1fffffff) >> 1
        literals, _, literal_data, _ = struct.unpack_from("<IIII", metadata_data, 8)
        length, start = struct.unpack_from("<II", metadata_data, literals + index * 8)
        return {"slot_va": hex(slot), "relative_relocation_addend_va": hex(pointer), "encoded_usage": hex(encoded),
                "metadata_literal_index": index, "metadata_literal_offset": hex(literal_data + start),
                "text": metadata_data[literal_data + start:literal_data + start + length].decode()}

    symbols, selected, stub_files, all_methods = {}, [], {}, []
    for file in sorted(stubs.rglob("*.cs")):
        content = file.read_bytes()
        methods = METHOD_RE.findall(content.decode())
        for off, length, declaration in methods:
            offset, length = int(off, 16), int(length, 16)
            try:
                address = virtual(offset)
            except StopIteration:
                continue
            symbol = file.stem + "." + declaration.strip()
            symbols.setdefault(address, []).append(symbol)
            all_methods.append((address, address + length, file, offset, length, declaration.strip()))
            if file.stem in SELECTION and (
                SELECTION[file.stem] is None or
                any(term in declaration for term in SELECTION[file.stem])
            ):
                selected.append((file, offset, length, declaration.strip(), address))
                stub_files[str(file.relative_to(stubs))] = digest(content)
    all_methods.sort(key=lambda row: row[0])
    addresses = [row[0] for row in all_methods]
    reference_targets = {
        virtual(0x2D0A214): "EnemyBossHpState.UpdateSpecialBarInfo",
        virtual(0x2D0A418): "EnemyBossHpState.UpdateLevel",
        virtual(0x2D094C0): "Box_UnitState.UpdateText",
        virtual(0x30F27CC): "Panel_PlayerBattleCtrl_BattleSysWnd.CreateEnemyStateBox",
    }
    references = {name: [] for name in reference_targets.values()}
    for code_section in code_sections:
        for word_index, (word,) in enumerate(struct.iter_unpack("<I", data[code_section[4]:code_section[4] + code_section[5]])):
            if word & 0x7C000000 != 0x14000000:
                continue
            address = code_section[3] + word_index * 4
            immediate = word & 0x3FFFFFF
            if immediate & 0x2000000:
                immediate -= 0x4000000
            target = address + immediate * 4
            if target not in reference_targets:
                continue
            index = bisect.bisect_right(addresses, address) - 1
            owner = all_methods[index] if index >= 0 and address < all_methods[index][1] else None
            row = {"caller_va": hex(address), "target_va": hex(target), "op": "bl" if word & 0x80000000 else "b",
                   "caller": symbols.get(owner[0], []) if owner else []}
            references[reference_targets[target]].append(row)
            if owner:
                begin, _, file, offset, length, declaration = owner
                selected.append((file, offset, length, declaration, begin))
                stub_files[str(file.relative_to(stubs))] = digest(file.read_bytes())
    decoder = Cs(CS_ARCH_ARM64, CS_MODE_ARM)
    methods, seen = [], set()
    for file, offset, length, declaration, address in selected:
        if offset in seen:
            continue
        seen.add(offset)
        instructions = []
        for ins in decoder.disasm(data[offset:offset + length], address):
            row = {"offset": hex(offset + ins.address - address), "va": hex(ins.address), "op": ins.mnemonic, "args": ins.op_str}
            if ins.mnemonic in ("b", "bl") and ins.op_str.startswith("#"):
                row["callees"] = symbols.get(int(ins.op_str[1:], 16), [])
            instructions.append(row)
        methods.append({"evidence_id": "apk-health-native-" + hex(address), "class": file.stem, "declaration": declaration,
                        "stub": str(file), "file_offset": hex(offset), "va": hex(address), "length": length,
                        "native_bytes_sha256": digest(data[offset:offset + length]), "instructions": instructions})
    observations, inferences, unknowns = findings()
    return {
        "apk": str(apk), "apk_sha256": apk_sha256,
        "native": str(native), "native_member": native_member, "native_sha256": digest(data),
        "metadata": str(metadata), "metadata_member": metadata_member, "metadata_sha256": digest(metadata_data),
        "apk_member_identity_verified": True,
        "stubs": str(stubs), "stub_files_sha256": stub_files,
        "stub_manifest_sha256": digest(json.dumps(stub_files, sort_keys=True).encode()),
        "evidence_type": "offline static ARM64 disassembly; no APK runtime executed",
        "stub_limit": "Cpp2IL address/name/field annotations are a secondary mapping; instruction bytes are from the identity-verified APK member.",
        "literal_evidence": [literal(slot) for slot in [0x65B9A60, 0x65B9A68, 0x65B31F0, 0x65AF090, 0x65AC9D0, 0x65AD0F0]],
        "float_evidence": [{"va": hex(address), "file_offset": hex(file_offset(address)),
                            "bytes": data[file_offset(address):file_offset(address) + 4].hex(),
                            "value": struct.unpack_from("<f", data, file_offset(address))[0]}
                           for address in [0x1287E18, 0x1287FB4, 0x1288154, 0x1288A10, 0x1288A14, 0x1288184, 0x1288234]],
        "direct_branch_reference_boundary": "All aligned AArch64 B/BL instructions in every SHF_EXECINSTR APK ARM64 ELF section (.text, il2cpp, .plt). Excludes reflection, virtual/indirect calls and runtime-generated code.",
        "direct_branch_references": references,
        "observations": observations, "inferences": inferences, "unknowns": unknowns, "methods": methods,
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--native", type=Path, required=True)
    parser.add_argument("--metadata", type=Path, required=True)
    parser.add_argument("--stubs", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = inspect(args.apk, args.native, args.metadata, args.stubs)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"output": str(args.output), "apk_sha256": result["apk_sha256"], "native_sha256": result["native_sha256"], "methods": len(result["methods"])}))
