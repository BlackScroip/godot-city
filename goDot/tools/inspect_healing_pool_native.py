"""Retain hash-bound spring interaction, healing and packaged prefab evidence."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import zipfile

import UnityPy

import inspect_new_camp_native as native_audit
from inspect_camp_progression import manifest_records


APK_SHA = "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505"
NATIVE_SHA = "86481018e3b55575e27d0d99a5979299b7fbbdf718698918ab5ebfbbccb68944"
SELECTION = {
    "RogueRoomManager": ["Msg_DrinkSpring"],
    "BattleGlobalSysAttribute_Rogue": ["GetAttribute(ERogueAttributeType"],
    "RoleUnit": ["public virtual bool ProcessDamageOrHeal", "public virtual float ChangeHP", "IsAntiHeal"],
    "LocalPlayer": ["ProcessDamageOrHeal"],
    "BuffManager": ["OnOwnerHpChange"],
}


def sha(value):
    return hashlib.sha256(value).hexdigest()


def inspect(apk, native_path, metadata_path, stubs):
    native, metadata = native_path.read_bytes(), metadata_path.read_bytes()
    with apk.open("rb") as stream:
        apk_sha = hashlib.file_digest(stream, "sha256").hexdigest()
    if apk_sha != APK_SHA or sha(native) != NATIVE_SHA:
        raise ValueError("Spring audit requires the supplied current APK/native hashes")
    with zipfile.ZipFile(apk) as archive:
        if archive.read("lib/arm64-v8a/libil2cpp.so") != native or archive.read("assets/bin/Data/Managed/Metadata/global-metadata.dat") != metadata:
            raise ValueError("Extracted native/metadata differ from supplied APK")
        manifest_member = next(name for name in archive.namelist() if name.startswith("assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes"))
        manifest = archive.read(manifest_member)
        assets, bundles = manifest_records(manifest)
        addresses = {row["address"]: row for row in assets}
        packaged = []
        for address in ["EnvUnit_Interactable_Spring", "RogueConfigData"]:
            asset = addresses[address]
            member = "assets/yoo/DefaultPackage/" + bundles[asset["bundle"]]["hash"] + ".bundle"
            payload = archive.read(member)
            objects = []
            for obj in UnityPy.load(payload).objects:
                if address == "RogueConfigData":
                    if obj.type.name != "TextAsset":
                        continue
                    tree = obj.read_typetree()
                    if tree.get("m_Name") != address:
                        continue
                    raw = tree["m_Script"]
                    parsed = json.loads(raw.decode("utf-8-sig") if isinstance(raw, bytes) else raw)
                    objects.append({"path_id": str(obj.path_id), "type": obj.type.name, "data": {"DefaultDrinkSpringVfxName": parsed["DefaultDrinkSpringVfxName"]}})
                elif obj.type.name in ["GameObject", "BoxCollider", "Transform", "MonoBehaviour"]:
                    objects.append({"path_id": str(obj.path_id), "type": obj.type.name, "data": obj.read_typetree()})
            packaged.append({"address": address, "member": member, "bundle_sha256": sha(payload), "objects": objects})

    phoff = struct.unpack_from("<Q", native, 32)[0]
    phsize, phcount = struct.unpack_from("<HH", native, 54)
    segments = [struct.unpack_from("<IIQQQQQQ", native, phoff + index * phsize) for index in range(phcount)]

    def file_at(va):
        return next(offset + va - start for kind, _, offset, start, _, size, _, _ in segments if kind == 1 and start <= va < start + size)

    shoff = struct.unpack_from("<Q", native, 40)[0]
    shsize, shcount = struct.unpack_from("<HH", native, 58)
    relocations = {}
    for index in range(shcount):
        section = struct.unpack_from("<IIQQQQIIQQ", native, shoff + index * shsize)
        if section[1] == 4:
            for position in range(section[4], section[4] + section[5], section[9] or 24):
                target, info, addend = struct.unpack_from("<QQq", native, position)
                if info == 1027:
                    relocations[target] = (position, addend)
    literals, literal_bytes, literal_data, _ = struct.unpack_from("<4I", metadata, 8)
    strings, strings_size = struct.unpack_from("<II", metadata, 0x18)
    types, _ = struct.unpack_from("<II", metadata, 0xA0)
    methods, method_bytes = struct.unpack_from("<II", metadata, 0x30)

    def string_at(index):
        end = metadata.index(b"\0", strings + index, strings + strings_size)
        return metadata[strings + index:end].decode("utf-8")

    references = {}

    def reference(va):
        if va not in relocations:
            return None
        position, carrier = relocations[va]
        encoded = struct.unpack_from("<Q", native, file_at(carrier))[0]
        kind, index = (encoded >> 29) & 7, (encoded >> 1) & 0x0FFFFFFF
        if not encoded & 1 or kind != 5 or index >= literal_bytes // 8:
            return None
        entry = literals + 8 * index
        size, offset = struct.unpack_from("<II", metadata, entry)
        return {"got_va": hex(va), "rela_file_offset": hex(position), "carrier_va": hex(carrier), "encoded": hex(encoded), "literal_index": index, "metadata_entry": hex(entry), "utf8": metadata[literal_data + offset:literal_data + offset + size].decode("utf-8")}

    native_audit.SELECTION = SELECTION
    native_audit.SELECTED_OFFSETS = {0x2E740DC}
    evidence = native_audit.inspect(native_path, stubs)
    for method in evidence["methods"]:
        method["evidence_id"] = "healing-native-" + method["file_offset"][2:]
        start, length = int(method["file_offset"], 16), method["length"]
        method["code_sha256"] = sha(native[start:start + length])
        registers = {}
        for instruction in method["instructions"]:
            args, op = instruction["args"], instruction["op"]
            page = re.fullmatch(r"(x\d+), #(0x[0-9a-f]+)", args)
            load = re.fullmatch(r"(x\d+), \[(x\d+)(?:, #(0x[0-9a-f]+))?\]", args)
            if op == "adrp" and page:
                registers[page[1]] = int(page[2], 16)
            elif op == "ldr" and load:
                target, base, displacement = load.groups()
                va = registers.get(base, 0) + int(displacement or "0", 16)
                ref = reference(va)
                if ref:
                    references[hex(va)] = ref
                    instruction["literal"] = ref["utf8"]
                registers.pop(target, None)
            elif op == "bl":
                for register in range(19):
                    registers.pop("x" + str(register), None)

    slots = []
    for index in range(method_bytes // 36):
        off = methods + 36 * index
        name, declaring_type = struct.unpack_from("<II", metadata, off)
        typename, namespace = struct.unpack_from("<II", metadata, types + declaring_type * 88)
        if string_at(typename) in ["RoleUnit", "Player"] and string_at(name) in ["GetAttribute", "ChangeHP", "ProcessDamageOrHeal"]:
            _, _, slot, _ = struct.unpack_from("<HHHH", metadata, off + 28)
            slots.append({"method": string_at(namespace) + "." + string_at(typename) + "." + string_at(name), "metadata_offset": hex(off), "slot": slot, "vtable_function_offset": hex(0x138 + slot * 16)})
    evidence.update({"apk_sha256": apk_sha, "metadata_sha256": sha(metadata), "manifest_member": manifest_member, "manifest_sha256": sha(manifest), "metadata_literal_references": references, "method_slots": slots, "packaged": packaged,
                     "limitations": ["Static disassembly and packaged resource evidence; original APK was not executed.", "No native save/resume serialization for IsSpringUsed has been established; room consumption persistence in Godot is an integration choice.", "Recovered scene transforms are in the existing environment marker exports; the raw prefab establishes local trigger dimensions."]})
    return evidence


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
    print(json.dumps({"output": str(args.output), "methods": len(result["methods"]), "literals": len(result["metadata_literal_references"]), "apk_sha256": result["apk_sha256"]}))
