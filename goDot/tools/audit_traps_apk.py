"""Compare recovered trap configuration with the supplied APK without execution."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import zipfile

import UnityPy
from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM
from inspect_camp_progression import manifest_records


def inspect(apk, root, stubs):
    rules = json.loads((root / "assets/environment_rules.json").read_text())
    combat = json.loads((root / "assets/data/combat.json").read_text())
    traps = {row["ID"]: row for row in rules["Definitions"] if row["Type"] == "EEUT_TriggerTrap"}
    buff_ids = {row["AddBuffData"]["BuffTriggerId"] for row in traps.values()}
    names = {f"EnvUnitCfg_[{key}]" for key in traps} | {f"BuffCfg_[{key}]" for key in buff_ids}
    result = {"schema": 1, "apk": str(apk), "apk_sha256": hashlib.file_digest(apk.open("rb"), "sha256").hexdigest(),
              "evidence_type": "static packaged JSON and ARM64 disassembly", "traps": {}, "buffs": {}, "methods": [],
              "limitations": ["Static configuration and native calls do not observe APK runtime execution."]}
    with zipfile.ZipFile(apk) as archive:
        member = next(n for n in archive.namelist() if n.startswith("assets/yoo/DefaultPackage/DefaultPackage_") and n.endswith(".bytes"))
        payload = archive.read(member)
        assets, bundles = manifest_records(payload)
        result["manifest"] = {"member": member, "sha256": hashlib.sha256(payload).hexdigest()}
        selected = [row for row in assets if row["address"] in names or ("actionenginecfg" in row["path"].lower() and any(f"[{key}]" in row["path"] for key in buff_ids | set(traps)))]
        result["selected_addresses"] = [row["address"] for row in selected]
        for index in sorted({row["bundle"] for row in selected}):
            bundle = bundles[index]
            member = "assets/yoo/DefaultPackage/" + bundle["hash"] + ".bundle"
            raw = archive.read(member)
            for obj in UnityPy.load(raw).objects:
                if obj.type.name != "TextAsset":
                    continue
                asset = obj.read()
                match = re.search(r"\[(\d+)\]", asset.m_Name)
                if not match or match[1] not in buff_ids | set(traps):
                    continue
                script = asset.m_Script
                if isinstance(script, bytes):
                    script = script.decode("utf-8-sig")
                parsed = json.loads(script)
                record = {"member": member, "bundle_sha256": hashlib.sha256(raw).hexdigest(), "path_id": obj.path_id,
                          "asset": asset.m_Name, "sha256": hashlib.sha256(script.encode()).hexdigest(), "data": parsed}
                if asset.m_Name.startswith("EnvUnitCfg_") and match[1] in traps:
                    source = parsed.get("EnvUnitData", parsed)
                    recovered = traps[match[1]]
                    record["differences"] = {key: {"apk": source.get(key), "recovered": value} for key, value in recovered.items() if key not in ["SourceConfig", "Type"] and source.get(key) != value}
                    result["traps"][match[1]] = record
                elif asset.m_Name.startswith("BuffCfg_") and match[1] in buff_ids:
                    source = parsed.get("BuffData", parsed)
                    recovered = next((row.get("raw_data", {}) for row in combat["buffs"] if row["id"] == match[1]), {})
                    record["matches_recovered_raw_data"] = source == recovered
                    result["buffs"][match[1]] = record
        native = archive.read("lib/arm64-v8a/libil2cpp.so")
    result["native_sha256"] = hashlib.sha256(native).hexdigest()
    segments = []
    phoff = struct.unpack_from("<Q", native, 32)[0]
    entsize, count = struct.unpack_from("<HH", native, 54)
    for index in range(count):
        typ, flags, off, va, pa, filesz, memsz, align = struct.unpack_from("<IIQQQQQQ", native, phoff + index * entsize)
        if typ == 1:
            segments.append((off, off + filesz, va))
    def virtual(offset):
        return next(va + offset - lo for lo, hi, va in segments if lo <= offset < hi)
    pattern = re.compile(r'\[Address\(RVA = "0x[0-9A-F]+", Offset = "0x([0-9A-F]+)", Length = "0x([0-9A-F]+)"\)\]\s*(?:\[[^\n]+\]\s*)+([^\n]+)')
    symbols, methods = {}, []
    for file in stubs.rglob("*.cs"):
        for off, length, signature in pattern.findall(file.read_text()):
            offset, length = int(off, 16), int(length, 16)
            try:
                address = virtual(offset)
            except StopIteration:
                continue
            if address not in symbols or "get {" in symbols[address]:
                symbols[address] = file.stem + "." + signature.strip()
            if file.stem == "EnvUnitAttractTrap" or (file.stem == "UnitRuntimeStatus" and "public UnitRuntimeStatus()" in signature) or (file.stem in ["RoleUnit", "Player"] and any(name in signature for name in ["BeAttract(", "CanAttract(", "GetAttribute_Self(", "GetAttribute(EAttributeType"])) or (file.stem == "EnvUnitTriggerTrap" and any(name in signature for name in ["ApplyEffectToUnit", "ProcessUnitList", "RegisterEffectTrigger>b__31_1", "RegisterEnterTrigger>b__30_1", "SwitchState", "Update(", "Message_DisableTrap", "SetWarningLineVisible", "void Init("])):
                methods.append((offset, length, address, signature.strip()))
    disassembler = Cs(CS_ARCH_ARM64, CS_MODE_ARM)
    for offset, length, address, signature in methods:
        instructions = []
        for instruction in disassembler.disasm(native[offset:offset + length], address):
            row = {"address": hex(instruction.address), "mnemonic": instruction.mnemonic, "operands": instruction.op_str}
            if instruction.mnemonic in ["bl", "b"] and instruction.op_str.startswith("#0x"):
                row["callee"] = symbols.get(int(instruction.op_str[1:], 16), "unresolved")
            instructions.append(row)
        result["methods"].append({"name": signature, "address": hex(address), "file_offset": hex(offset), "instructions": instructions})
    result["attract_float_constants"] = {}
    for address in [0x1287EB0, 0x1288154]:
        offset = next(lo + address - va for lo, hi, va in segments if va <= address < va + hi - lo)
        result["attract_float_constants"][hex(address)] = struct.unpack_from("<f", native, offset)[0]
    address = 0x12F24A4 + (94 - 1) * 2
    offset = next(lo + address - va for lo, hi, va in segments if va <= address < va + hi - lo)
    result["player_weight_switch_target"] = hex(0x315FFC8 + 4 * struct.unpack_from("<H", native, offset)[0])
    result["coverage"] = {"recovered_traps": len(traps), "apk_traps": len(result["traps"]), "recovered_buffs": len(buff_ids), "apk_buffs": len(result["buffs"])}
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--stubs", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--sync", action="store_true")
    args = parser.parse_args()
    report = inspect(args.apk, args.root, args.stubs)
    if args.sync:
        rules_path = args.root / "assets/environment_rules.json"
        rules = json.loads(rules_path.read_text())
        for row in rules["Definitions"]:
            record = report["traps"].get(row["ID"])
            if record and row["Type"] == "EEUT_TriggerTrap":
                for key, change in record["differences"].items():
                    row[key] = change["apk"]
        rules_path.write_text(json.dumps(rules, ensure_ascii=False, indent=2) + "\n")
        report["sync_applied"] = True
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report["coverage"]))
