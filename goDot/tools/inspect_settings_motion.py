"""Verify settings motion evidence for the selected APK without executing it."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
import zipfile


PROJECT = Path(__file__).resolve().parents[1]


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def method_declaration(source, name):
    pattern = r'\[Address\(RVA = "0x([0-9A-Fa-f]+)", Offset = "0x([0-9A-Fa-f]+)", Length = "0x([0-9A-Fa-f]+)"\)\][\s\S]*?\n\s*([^\n]*\b' + re.escape(name) + r'\([^\n]+)'
    matches = list(re.finditer(pattern, source))
    if not matches:
        raise ValueError("Missing declaration: " + name)
    # Stop at the nearest Address attribute rather than an earlier method.
    fragment = matches[-1].group(0)
    attributes = list(re.finditer(r'\[Address\(RVA = "0x([0-9A-Fa-f]+)", Offset = "0x([0-9A-Fa-f]+)", Length = "0x([0-9A-Fa-f]+)"\)\]', fragment))
    address = attributes[-1]
    return {"name": name, "file_offset": int(address[2], 16), "length": int(address[3], 16), "declaration": fragment.splitlines()[-1].strip()}


def elf_mapping(data, file_offset=None, virtual_address=None):
    if data[:6] != b"\x7fELF\x02\x01":
        raise ValueError("Expected a little-endian ELF64 image")
    table = struct.unpack_from("<Q", data, 32)[0]
    stride, count = struct.unpack_from("<HH", data, 54)
    for index in range(count):
        kind, _, offset, address, _, size, _, _ = struct.unpack_from("<IIQQQQQQ", data, table + index * stride)
        if kind != 1:
            continue
        if file_offset is not None and offset <= file_offset < offset + size:
            return file_offset - offset + address
        if virtual_address is not None and address <= virtual_address < address + size:
            return virtual_address - address + offset
    raise ValueError("Address is outside file-backed ELF load segments")


def inspect(apk, native, stubs):
    layout = json.loads((PROJECT / "assets/ui/settings/option/prefab-layout.json").read_text())
    apk_hash = digest(apk)
    if apk_hash != layout["apk_sha256"]:
        raise ValueError("The recovered layout belongs to a different APK")
    with zipfile.ZipFile(apk) as archive:
        bundle_hash = hashlib.sha256(archive.read(layout["source"]["member"])).hexdigest()
    if bundle_hash != layout["source"]["sha256"]:
        raise ValueError("The settings bundle differs from the recovered layout")
    previous = json.loads((PROJECT / "reports/settings-native-source.json").read_text())
    if digest(native) != previous["native_sha256"]:
        raise ValueError("The native library differs from the prior APK evidence")
    native_bytes = native.read_bytes()
    source = (stubs / "Assembly-CSharp/Teamelo/ProjectAT/ATPanel_Option.cs").read_text()
    methods = []
    for name in ["MoveActiveSlotTo", "PlayBtnClickAnim", "PlayBtnDeSelectAnim"]:
        method = method_declaration(source, name)
        method["virtual_address"] = elf_mapping(native_bytes, file_offset=method["file_offset"])
        result = subprocess.run(["r2", "-n", "-a", "arm", "-b", "64", "-q", "-c", f'pDj {method["length"]} @ {method["file_offset"]}', str(native)], capture_output=True, text=True, check=True, timeout=30)
        method["instructions"] = [{"file_offset": row["addr"], "opcode": row["opcode"], "bytes": row["bytes"]} for row in json.loads(result.stdout)]
        methods.append(method)
    move = methods[0]
    code_delta = move["virtual_address"] - move["file_offset"]
    base = None
    duration_address = None
    for row in move["instructions"]:
        opcode = row["opcode"]
        match = re.fullmatch(r"adrp x8, (0x[0-9a-f]+)", opcode)
        if match:
            base = int(match[1], 16) + code_delta
        match = re.fullmatch(r"ldr s3, \[x8, (0x[0-9a-f]+)\]", opcode)
        if match and base is not None:
            duration_address = base + int(match[1], 16)
    if duration_address is None:
        raise ValueError("The expected DOLocalMove duration load was not found")
    constant_offset = elf_mapping(native_bytes, virtual_address=duration_address)
    duration = struct.unpack_from("<f", native_bytes, constant_offset)[0]
    shortcut = (stubs / "DOTween/DG/Tweening/ShortcutExtensions.cs").read_text()
    callee = method_declaration(shortcut, "DOLocalMove")
    if not any(row["opcode"] == "b " + hex(callee["file_offset"]) for row in move["instructions"]):
        raise ValueError("The expected DOLocalMove tail call was not found")
    prefix = "Slot_Setting_ShowPopDamage/PageBtnBox"
    elements = []
    for row in layout["images"]:
        if row["path"].endswith(prefix) or row["path"].endswith(prefix + "/Slot_Active"):
            elements.append({"path": row["path"], "sprite": row["sprite"], "color": row["color"], "size": row["rect"]["m_SizeDelta"], "position": row["rect"]["m_AnchoredPosition"]})
    return {
        "evidence_type": "Bounded static APK, recovered Unity prefab, ELF load mapping and ARM64 disassembly; original APK not executed",
        "parent_rea_evidence_id": "ev_89b63e484acc2e54de490487bd1b9889d08f547cd7c8ac0c50d782ab1acf0323",
        "apk_sha256": apk_hash,
        "settings_bundle": {"member": layout["source"]["member"], "sha256": bundle_hash},
        "native_sha256": previous["native_sha256"],
        "elements": elements,
        "methods": methods,
        "move_callee": callee,
        "move_duration": {"seconds": duration, "constant_virtual_address": duration_address, "constant_file_offset": constant_offset, "argument": "s3: DOLocalMove duration after Vector3 s0/s1/s2"},
        "limitations": ["ScrollRect inertia and elasticity were not recovered", "Global DOTween default easing was not recovered", "The reconstruction uses cubic-out easing and UI-speed scaling as implementation choices", "These are local static observations, not new REA-native Evidence records or observations of APK execution"],
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--native", type=Path, required=True)
    parser.add_argument("--stubs", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = inspect(args.apk, args.native, args.stubs)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"output": str(args.output), "duration": report["move_duration"]["seconds"], "elements": len(report["elements"]), "methods": len(report["methods"])}))
