#!/usr/bin/env python3
"""Retain hash-bound ARM64 hit-feedback evidence from the supplied APK."""

import argparse
import hashlib
import json
import re
import struct
import subprocess
import zipfile
from pathlib import Path

APK_SHA = "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505"
NATIVE_SHA = "86481018e3b55575e27d0d99a5979299b7fbbdf718698918ab5ebfbbccb68944"
NATIVE_MEMBER = "lib/arm64-v8a/libil2cpp.so"
METADATA_MEMBER = "assets/bin/Data/Managed/Metadata/global-metadata.dat"
NAMESPACE = "Assembly-CSharp/Teamelo/ActionEngine"
METHODS = [
    (NAMESPACE, "HitModifyMaterial", "OnHitFeedback", ""),
    (NAMESPACE, "HitModifyMaterial", "Deserialize", ""),
    (NAMESPACE, "URoleUnit", "EnableMaterialEffect_MaskColor_InBeDamage", ""),
    (NAMESPACE, "URoleUnit", "EnableMaterialEffect_MaskColor", ""),
    (NAMESPACE, "URoleUnit", "ResetMaterialEffect_MaskColor", ""),
    (NAMESPACE, "URoleUnit", "UpdateMaterialEffect", ""),
    (NAMESPACE, "URoleUnit", "StartShake", ""),
    (NAMESPACE, "URoleUnit", "Update", ""),
    (NAMESPACE, "URoleUnit", "UpdateShake", ""),
    (NAMESPACE, "URoleUnit", "ResetShake", ""),
    (NAMESPACE, "HitAction", "GetModifyPushPower", ""),
    (NAMESPACE, "HitAction", "OnHitFeedback", ""),
    (NAMESPACE, "RoleUnit", "GetCantBeHurtType", ""),
    (NAMESPACE, "RoleUnit", "SetHitAndUpMove", ""),
    (NAMESPACE, "RoleUnit", "SetPushForce", ""),
    (NAMESPACE, "RoleUnit", "AddAccTenacity", ""),
    (NAMESPACE, "RoleUnit", "UpdateTenacity", ""),
    (NAMESPACE, "RoleUnit", "RecoverTenacityPerSec", ""),
    (NAMESPACE, "RoleUnit", "SetAnimatorLayerWeight", ""),
    (NAMESPACE, "RoleUnit", "PlayAnimation", ""),
    (NAMESPACE, "Player", "SetHitAndUpMove", ""),
    (NAMESPACE, "Monster", "SetHitAndUpMove", ""),
    (NAMESPACE, "ActionStatus", "GetPushTime", ""),
    (NAMESPACE, "ActionStatus", "SetPushForce", ""),
    (NAMESPACE, "ActionStatus", "SetHitAndUpMove", ""),
    (NAMESPACE, "ActionStatus", "ProcessHitAndUpMove", ""),
    (NAMESPACE, "ActionStatus", "GetLocalTimeScale", ""),
    (NAMESPACE, "ActionStatus", "ResetForce", ""),
    ("UnityEngine.CoreModule/UnityEngine", "Material", "SetInt", "string name"),
    ("UnityEngine.CoreModule/UnityEngine", "Material", "SetColor", "string name"),
    ("UnityEngine.CoreModule/UnityEngine", "Material", "SetFloat", "string name"),
    ("UnityEngine.CoreModule/UnityEngine", "Material", "get_shader", ""),
    ("UnityEngine.CoreModule/UnityEngine", "Object", "get_name", ""),
    ("UnityEngine.CoreModule/UnityEngine", "Time", "get_deltaTime", ""),
    ("UnityEngine.CoreModule/UnityEngine", "Random", "Range", "int minInclusive"),
    ("UnityEngine.CoreModule/UnityEngine", "Component", "get_transform", ""),
    ("UnityEngine.CoreModule/UnityEngine", "Transform", "set_localPosition", ""),
    ("mscorlib/System", "String", "op_Equality", ""),
    ("mscorlib/System", "Math", "Log", "double newBase"),
]
METADATA_ONLY = ["HitFeedBackData_Unit", "CombatResultData", "UnitRuntimeStatus", "PlayerProperty", "MonsterProperty", "ActionProperty", "EActionState", "EAttributeType", "ECantBeHurtType"]
MATERIAL_REFERENCES = [
    ("shader_name_equality_operand", 0x65DC678, "NeoShader/NPR_Simple"),
    ("mask_enable_setint_property", 0x65DC688, "_EnableModifyColor"),
    ("mask_color_setcolor_property", 0x65DC680, "_ModifyColor"),
    ("mask_hdr_setfloat_property", 0x65DC670, "_ModifyColorIntensity"),
]
SUPPORT_RANGES = [
    ("metadata_initializer_wrapper", 0x2AA0A00, 0x14),
    ("metadata_initializer_bridge", 0x2ABD654, 0x8),
    ("metadata_usage_decoder", 0x2AF3CD8, 0x1AC),
]
LITERALS = [
    ("damage_mask_duration", 0x1287C20),
    ("push_duration_coefficient_and_min_ratio", 0x1287E18),
    ("hit_action_shake_intensity_and_push_timer_threshold", 0x1287FB4),
    ("hit_action_shake_interval", 0x1287FB0),
    ("property_per_thousand_scale", 0x1288234),
    ("normalization_epsilon", 0x1287F10),
    ("direction_near_zero_threshold", 0x1287C14),
    ("player_hit_layer_weight_special_action", 0x1288124),
    ("player_hit_layer_weight_other_actions", 0x1287E70),
]
ADDRESS = re.compile(
    r'\[Address\(RVA = "(0x[0-9A-Fa-f]+)", Offset = "(0x[0-9A-Fa-f]+)", '
    r'Length = "(0x[0-9A-Fa-f]+)"\)\]'
)
FINDINGS = [
    {"id": "material-hit-gate", "kind": "observation", "methods": ["HitModifyMaterial.OnHitFeedback", "HitModifyMaterial.Deserialize"], "detail": "Reads CombatResultData.CaculateDamage at +0x1c, converts its ObscuredFloat to float, and requires >0. Calls the attackee damage mask only when Attacker != Attackee. The gate is not FinalHpChange. Deserialize is a return-only stub; no per-definition flash duration is read."},
    {"id": "material-property-binding", "kind": "observation", "methods": ["URoleUnit.EnableMaterialEffect_MaskColor", "URoleUnit.EnableMaterialEffect_MaskColor_InBeDamage", "URoleUnit.ResetMaterialEffect_MaskColor", "Material.SetInt", "Material.SetColor", "Material.SetFloat"], "detail": "Iterates the role's SkinnedMeshRenderer materials and requires shader.name == NeoShader/NPR_Simple. Enables with SetInt(_EnableModifyColor,1), SetColor(_ModifyColor,RGBA1), SetFloat(_ModifyColorIntensity,1.5). Reset uses SetInt(...,0), white RGBA1, intensity1. The enable operation is an integer shader property, not keyword enable. The hash-bound relocation, metadata usage decoder, literal bytes and strings are retained."},
    {"id": "material-timer", "kind": "observation", "methods": ["URoleUnit.EnableMaterialEffect_MaskColor_InBeDamage", "URoleUnit.EnableMaterialEffect_MaskColor", "URoleUnit.UpdateMaterialEffect", "URoleUnit.Update", "Time.get_deltaTime"], "detail": "Damage wrapper supplies the exact float32 duration 0.15. A positive timerCover restarts elapsed time at0 and replaces duration. UpdateMaterialEffect adds fTick and resets on elapsed>=duration. URoleUnit.Update supplies Unity Time.deltaTime; this call path does not read BattleTimeScale. Unity timeScale/global callers were not exhaustively audited."},
    {"id": "material-output-separate-evidence", "kind": "observation", "methods": ["URoleUnit.EnableMaterialEffect_MaskColor"], "detail": "The companion hit-mask-shader-static.json and original retained GLES program bind the selected character's empty material keyword set to NeoShader/NPR_Simple. That shader uses the enabled mask color*intensity as the lit endpoint of its shadow ramp, multiplied by MainTex and MainColor, with Fresnel added. White1.5 is not a flat opaque or alpha overlay. Companion evidence is generated separately and is not validated by this native-only command."},
    {"id": "hit-action-admission", "kind": "observation", "methods": ["HitAction.OnHitFeedback"], "detail": "Returns when attacker or attackee is absent, attackee IsDead is true, CombatResultData.IsAttackerMiss is true or IsAttackeeAutoDodge is true. Chooses push direction using PushMode0..3, horizontal normalization and native near-zero fallbacks; those full branches are retained without replacing them with a generic direction or new ability."},
    {"id": "push-modification", "kind": "observation", "methods": ["HitAction.GetModifyPushPower", "HitAction.OnHitFeedback"], "detail": "For nonempty modifier name list, splits names on '|', starts multiplier at1 and adds each attacker named-property value/1000, multiplies authored integer PushPower, then truncates float to integer for finite ordinary inputs. Empty modifier returns base push unchanged. OnHitFeedback then multiplies by (1 + attacker PushForceAddRate attribute96 *0.001), passing that float, authored UpperPower, and float(AccTenacity) to attackee.SetHitAndUpMove; stores LastAttacker_Push and optionally starts model shake."},
    {"id": "cant-be-hurt-admission", "kind": "observation", "methods": ["RoleUnit.GetCantBeHurtType", "RoleUnit.SetHitAndUpMove"], "detail": "Absent ActionStatus or false CanBeHit returns CantSelect1. Otherwise checks BlockRemainTime131>0 -> Block31, then DodgeRemainTime130>0 -> DodgeByHandle21, then GodRemainTime129>0 -> God11, else None0. SetHitAndUpMove rejects every nonzero result before applying tenacity."},
    {"id": "tenacity-accumulation", "kind": "observation", "methods": ["RoleUnit.AddAccTenacity"], "detail": "Rejects accumulation while GodRemainTime129>0, CurShield5>0, CurArmor6>0, or runtime IsWeakTime is already true. Updates CurTenacityAcc += addOriginValue + TenacityAccAddRate100*0.001. This is additive; it does not multiply addOriginValue by (1+rate/1000). At accumulator>=BaseTenacity98, resets accumulator and weak timer to0 and sets IsWeakTime=true."},
    {"id": "tenacity-recovery", "kind": "observation", "methods": ["RoleUnit.UpdateTenacity", "RoleUnit.RecoverTenacityPerSec"], "detail": "While weak, CurWeakTimer += deltaTime; at >=BaseWeakTime101 clears weakness, timer and accumulator. Otherwise recovery subtracts BaseTenacityRecover99*deltaTime from accumulator and clamps at0. No new constant stagger duration appears in these methods."},
    {"id": "weak-push-routing", "kind": "observation", "methods": ["RoleUnit.SetHitAndUpMove", "Player.SetHitAndUpMove", "Monster.SetHitAndUpMove"], "detail": "After the cant-be-hurt gate, base SetHitAndUpMove calls virtual AddAccTenacity and inspects runtime IsWeakTime. Only its true branch and two runtime type checks reach ActionStatus.SetHitAndUpMove, supplying rotation true or false. The base success return reflects the cant-be-hurt result, not AddAccTenacity's return. The precise TypeInfo bindings of the two checks are not independently decoded in this report."},
    {"id": "push-duration-and-resistance", "kind": "observation", "methods": ["ActionStatus.GetPushTime", "ActionStatus.SetHitAndUpMove", "Math.Log"], "detail": "Hit path reads Weight94 and uses100 only when weight==0. Reads PushForceResist95 and UpperForceResist97, but the latter returned value is overwritten in this examined method. Effective push is signed max(abs(push)-pushResist,0). Stores horizontal normalized direction*effectivePush. T = (float(Log(double(1+abs(effectivePush)/weight),2))+1)*float32(0.1). When upperPower<weight, installs push timers only for abs(effectivePush)/weight>=float32(0.1). When upperPower>=weight it clears horizontal push timers and dispatches another property/action path. No vertical impulse is directly applied here; that target remains unresolved."},
    {"id": "push-discrete-motion", "kind": "observation", "methods": ["ActionStatus.ProcessHitAndUpMove", "ActionStatus.GetLocalTimeScale", "ActionStatus.ResetForce"], "detail": "When remaining push timer>float32(0.05), x/z speed is 2*(force/weight)*remaining/T^2. Decrements remaining by dt/GetLocalTimeScale(); negative remainder or a timer<=0.05 resets force. Adds speed*dt/GetLocalTimeScale() to mMoveRelDistance x/z. The exact discrete clock and0.05 cutoff prevent treating raw PushPower as a hand-tuned constant distance. Upper timer is decremented separately; this examined hit setter does not initialize it."},
    {"id": "separate-force-path", "kind": "observation", "methods": ["RoleUnit.SetPushForce", "ActionStatus.SetPushForce"], "detail": "Separate SetPushForce delegates to ActionStatus and uses raw pushPower and raw owner Weight in GetPushTime. It does not share all of the hit setter's resistance/weight fallback gates. Do not silently merge these two native paths."},
    {"id": "hit-animation-layer", "kind": "observation", "methods": ["Player.SetHitAndUpMove", "Monster.SetHitAndUpMove", "RoleUnit.SetAnimatorLayerWeight", "RoleUnit.PlayAnimation"], "detail": "Overrides return after base rejection or when IsWeakTime is true. For nonweak accepted hits, states21,22,31,32,33 (NorAtk,SAtk,SubSkill,MainSkill,Dodge) select layer1 blend weights: player0.4, other states0.7. Player only calls PlayAnimation(PlayerProperty.BeHitBlendStateName,transition0.05,layer1,normalizedTime0) when raw accTenacity>=100. Monster uses MonsterProperty.BeHitBlendStateRatio_SpecialAction(+0x60) versus NormalAction(+0x64), and plays BeHitBlendStateName with transition0/layer1/normalizedTime0. The blend weights are not lock or stagger durations."},
    {"id": "hit-model-shake", "kind": "observation", "methods": ["HitAction.OnHitFeedback", "URoleUnit.StartShake", "URoleUnit.UpdateShake", "URoleUnit.ResetShake", "URoleUnit.Update", "Random.Range", "Transform.set_localPosition"], "detail": "HitAction's enabled flag starts intensity0.05/count5/interval0.02 with X/Z enabled. Update uses Time.deltaTime, requires elapsed>interval, increments count and resets elapsed to0 (one step per Update). For count<=5 it samples Random.Range(int -1,int1) independently twice, multiplies by intensity, and writes art-model localPosition=initialLocalPosition+(xOffset,0,zOffset). The called overload's max is exclusive, so the samples are -1 or0. Count>5 calls ResetShake and restores initial local position. This is local model translation, without a sine curve, spring, screen shake, rotation or generated impulse."},
]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def retained_method(source, method_name, signature_filter):
    lines = source.splitlines()
    matches = []
    for index, line in enumerate(lines):
        address = ADDRESS.search(line)
        if address is None:
            continue
        for end in range(index + 1, min(index + 9, len(lines))):
            candidate = lines[end].strip()
            if candidate.startswith("[") or not candidate:
                continue
            if re.search(r"\b" + re.escape(method_name) + r"\(", candidate) and signature_filter in candidate:
                matches.append({
                    "address_rva_as_printed": address.group(1),
                    "offset": int(address.group(2), 16),
                    "length": int(address.group(3), 16),
                    "metadata_lines": [index + 1, end + 1],
                    "signature": candidate,
                    "metadata_excerpt": "\n".join(lines[index:end + 1]),
                })
            break
    if len(matches) != 1:
        raise ValueError(f"Expected one metadata method for {method_name}/{signature_filter}: {len(matches)}")
    return matches[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", required=True, type=Path)
    parser.add_argument("--lib", required=True, type=Path)
    parser.add_argument("--global-metadata", required=True, type=Path)
    parser.add_argument("--metadata-root", required=True, type=Path)
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1] / "reports/hit-feedback-native-static.json")
    args = parser.parse_args()
    with args.apk.open("rb") as stream:
        apk_hash = hashlib.file_digest(stream, "sha256").hexdigest()
    if apk_hash != APK_SHA:
        raise ValueError("This evidence map is bound to the user-supplied APK hash")
    native = args.lib.read_bytes()
    global_metadata = args.global_metadata.read_bytes()
    with zipfile.ZipFile(args.apk) as archive:
        member_hash = sha(archive.read(NATIVE_MEMBER))
        metadata_hash = sha(archive.read(METADATA_MEMBER))
    if member_hash != NATIVE_SHA or sha(native) != member_hash:
        raise ValueError("Extracted native library differs from the actual APK member")
    if sha(global_metadata) != metadata_hash:
        raise ValueError("Extracted global metadata differs from the actual APK member")
    if native[:6] != b"\x7fELF\x02\x01":
        raise ValueError("Expected little-endian ELF64")
    phoff = struct.unpack_from("<Q", native, 32)[0]
    phentsize, phnum = struct.unpack_from("<HH", native, 54)
    segments = []
    for index in range(phnum):
        kind, flags, offset, virtual, _, filesz, memsz, alignment = struct.unpack_from("<IIQQQQQQ", native, phoff + index * phentsize)
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
    for name, virtual in LITERALS:
        offset = file_at(virtual, 4)
        literals[name] = {"virtual_address": hex(virtual), "file_offset": hex(offset), "bytes": native[offset:offset + 4].hex(), "float32": struct.unpack_from("<f", native, offset)[0]}

    sanity, version, string_table, string_table_bytes, string_data, string_data_bytes = struct.unpack_from("<6I", global_metadata)
    if sanity != 0xFAB11BAF or version != 31 or string_table_bytes % 8:
        raise ValueError("Expected the supplied version-31 IL2CPP metadata string-literal header")
    if string_table + string_table_bytes > len(global_metadata) or string_data + string_data_bytes > len(global_metadata):
        raise ValueError("String literal metadata ranges are invalid")
    needed_slots = {virtual for _, virtual, _ in MATERIAL_REFERENCES}
    relocations = {}
    shoff = struct.unpack_from("<Q", native, 40)[0]
    shentsize, shnum = struct.unpack_from("<HH", native, 58)
    for section_index in range(shnum):
        section = struct.unpack_from("<IIQQQQIIQQ", native, shoff + section_index * shentsize)
        _, kind, _, _, offset, size, _, _, _, entry_size = section
        if kind != 4:
            continue
        if entry_size != 24 or size % entry_size:
            raise ValueError("Unexpected ELF64 RELA entry size")
        for entry_offset in range(offset, offset + size, entry_size):
            virtual, info, addend = struct.unpack_from("<QQq", native, entry_offset)
            if virtual in needed_slots:
                if info != 1027:
                    raise ValueError("Expected a symbol-free R_AARCH64_RELATIVE binding")
                relocations[virtual] = {"rela_file_offset": hex(entry_offset), "rela_bytes": native[entry_offset:entry_offset + entry_size].hex(), "type": info, "addend": addend}
    material_references = {}
    for name, virtual, expected in MATERIAL_REFERENCES:
        relocation = relocations[virtual]
        value_offset = file_at(relocation["addend"], 8)
        encoded = struct.unpack_from("<Q", native, value_offset)[0]
        if (encoded >> 29) & 7 != 5 or encoded & 1 != 1:
            raise ValueError("Expected an encoded string-literal usage")
        index = (encoded >> 1) & 0x0FFFFFFF
        entry_offset = string_table + index * 8
        if index * 8 >= string_table_bytes:
            raise ValueError("String literal index lies outside metadata table")
        length, data_index = struct.unpack_from("<II", global_metadata, entry_offset)
        if data_index + length > string_data_bytes:
            raise ValueError("String literal data lies outside metadata data")
        data_offset = string_data + data_index
        raw = global_metadata[data_offset:data_offset + length]
        if raw.decode("utf-8") != expected:
            raise ValueError("Unexpected native material property binding")
        material_references[name] = {"got_virtual_address": hex(virtual), "got_file_offset": hex(file_at(virtual, 8)), "relocation": relocation, "value_virtual_address": hex(relocation["addend"]), "value_file_offset": hex(value_offset), "encoded_usage_hex": hex(encoded), "usage_kind_high3": (encoded >> 29) & 7, "low_bit": encoded & 1, "index_encoding": "UBFX w8,w0,#1,#28 at VA0x2af3d20", "literal_index": index, "metadata_table_file_offset": hex(entry_offset), "metadata_data_file_offset": hex(data_offset), "bytes": raw.hex(), "utf8": raw.decode("utf-8")}

    switch_offset = file_at(0x18E3765, 7)
    string_branch = 0x2AF3D28 + native[switch_offset + 4] * 4
    if string_branch != 0x2AF3D94:
        raise ValueError("String usage switch does not point to retained metadata string table path")
    native_support = []
    for name, virtual, length in SUPPORT_RANGES:
        offset = file_at(virtual, length)
        command = ["xcrun", "llvm-objdump", "--disassemble", f"--start-address={virtual:#x}", f"--stop-address={virtual + length:#x}", str(args.lib)]
        native_support.append({"range": name, "virtual_address": hex(virtual), "file_offset": hex(offset), "length": length, "code_sha256": sha(native[offset:offset + length]), "command": command, "assembly": subprocess.check_output(command, text=True)})

    metadata_sources = {}
    methods = []
    for namespace, class_name, method_name, signature_filter in METHODS:
        relative_path = f"{namespace}/{class_name}.cs"
        source_path = args.metadata_root / relative_path
        source_bytes = source_path.read_bytes()
        source = source_bytes.decode("utf-8")
        method = retained_method(source, method_name, signature_filter)
        metadata_sources[relative_path] = {"sha256": sha(source_bytes), "field_declarations": [line.strip() for line in source.splitlines() if "//Field offset:" in line], "enum_declarations": [line.strip() for line in source.splitlines() if re.search(r"^\s*\w+ = -?\d+[,]?$", line)]}
        offset, length = method.pop("offset"), method["length"]
        virtual = virtual_at(offset, length)
        command = ["xcrun", "llvm-objdump", "--disassemble", f"--start-address={virtual:#x}", f"--stop-address={virtual + length:#x}", str(args.lib)]
        methods.append({"method": f"{class_name}.{method_name}", "metadata_source": relative_path, **method, "file_offset": hex(offset), "virtual_address": hex(virtual), "code_sha256": sha(native[offset:offset + length]), "command": command, "assembly": subprocess.check_output(command, text=True)})
    for class_name in METADATA_ONLY:
        relative_path = f"{NAMESPACE}/{class_name}.cs"
        source_bytes = (args.metadata_root / relative_path).read_bytes()
        source = source_bytes.decode("utf-8")
        metadata_sources[relative_path] = {"sha256": sha(source_bytes), "field_declarations": [line.strip() for line in source.splitlines() if "//Field offset:" in line], "enum_declarations": [line.strip() for line in source.splitlines() if re.search(r"^\s*\w+ = -?\d+[,]?$", line)]}
    report = {
        "schema": 1,
        "evidence_type": "ordinary-shell-static-disassembly; not REA Evidence and not runtime observation",
        "apk_sha256": apk_hash,
        "member": NATIVE_MEMBER,
        "member_sha256": member_hash,
        "metadata_member": METADATA_MEMBER,
        "metadata_member_sha256": metadata_hash,
        "address_source": "Cpp2IL DiffableCs Address.Offset used as file offset; virtual addresses independently derived from ELF64 PT_LOAD",
        "metadata_sources": metadata_sources,
        "load_segments": segments,
        "literals": literals,
        "metadata_string_header": {"sanity": hex(sanity), "version": version, "string_table": hex(string_table), "string_table_bytes": string_table_bytes, "string_data": hex(string_data), "string_data_bytes": string_data_bytes},
        "material_references": material_references,
        "metadata_usage_decoder_switch": {"virtual_address": "0x18e3765", "file_offset": hex(switch_offset), "bytes": native[switch_offset:switch_offset + 7].hex(), "string_kind5_target": hex(string_branch)},
        "native_support_ranges": native_support,
        "methods": methods,
        "findings": FINDINGS,
        "limitations": [
            "Metadata stubs identify signatures and fields; their empty method bodies are not decompiled logic. Original APK global-metadata bytes are independently verified.",
            "REA active target is shared; this bounded offline follow-up does not change it or fabricate REA Evidence IDs.",
            "Disassembly and data bytes establish static code paths only. No execution, visual fidelity, or FPS is observed by this tool.",
            "The precise TypeInfo binding of the weak-push branches, upper action/property targets, all hit-animation assets, and the complete character controller remain unresolved or outside this bounded investigation.",
            "The companion shader report covers only the selected source character and its exact material keyword sets; no other actor material or entire rendering pipeline is declared equivalent.",
            "Material and model-shake timers receive Unity Time.deltaTime. This report does not exhaustively audit every Unity timeScale setter or caller of the public feedback functions.",
        ],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"output": str(args.output), "methods": len(methods), "apk_sha256": apk_hash, "member_sha256": member_hash, "literals": literals}))


if __name__ == "__main__":
    main()
