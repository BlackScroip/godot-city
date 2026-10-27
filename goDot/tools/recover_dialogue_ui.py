"""Recover exact dialogue UI bindings and bounded gift/relationship evidence."""

import argparse
import hashlib
import io
import json
import math
from pathlib import Path
import re
import struct
import zipfile

import UnityPy
from UnityPy.classes.PPtr import PPtr
from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM

from inspect_camp_progression import manifest_records
from recover_route_art import package_dependencies


ROOT = Path(__file__).resolve().parents[1]
EXPECTED_APK = "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505"
REA_ID = "ev_89b63e484acc2e54de490487bd1b9889d08f547cd7c8ac0c50d782ab1acf0323"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def safe(value):
    if isinstance(value, float) and not math.isfinite(value):
        return str(value)
    if isinstance(value, dict):
        return {str(key): safe(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [safe(item) for item in value]
    return value


def recover(apk, output, stubs):
    with apk.open("rb") as stream:
        apk_sha = hashlib.file_digest(stream, "sha256").hexdigest()
    if apk_sha != EXPECTED_APK:
        raise ValueError("APK differs from the explicitly selected 1061664.apk")
    output.mkdir(parents=True, exist_ok=True)
    environment, sources, loaded_indices, objects = UnityPy.Environment(), {}, set(), {}
    report = {"schema": 1, "apk_sha256": apk_sha, "rea_evidence_id": REA_ID,
              "evidence_type": "Static Unity serialization and bounded ARM64 disassembly; APK not executed",
              "prefabs": {}, "sprites": {}, "config": {}, "stories": {}, "native": {}}
    with zipfile.ZipFile(apk) as archive:
        manifest_member = next(n for n in archive.namelist() if n.startswith(
            "assets/yoo/DefaultPackage/DefaultPackage_") and n.endswith(".bytes"))
        manifest = archive.read(manifest_member)
        assets, bundles = manifest_records(manifest)
        report["manifest"] = {"member": manifest_member, "sha256": sha(manifest)}

        def load(address, dependencies=True):
            asset = next(row for row in assets if row["address"] == address)
            deps, edges = package_dependencies(manifest, address) if dependencies else ([], {})
            pending = [asset["bundle"], *deps]
            while pending:
                index = pending.pop()
                if index in loaded_indices:
                    continue
                loaded_indices.add(index)
                if dependencies:
                    pending.extend(edges[index])
                member = "assets/yoo/DefaultPackage/" + bundles[index]["hash"] + ".bundle"
                payload = archive.read(member)
                loaded = environment.load_file(payload)
                objects[index] = []
                for cab in loaded.files.values():
                    if not hasattr(cab, "objects"):
                        continue
                    sources[cab.name] = {"bundle_index": index, "member": member,
                                         "name": bundles[index]["name"], "sha256": sha(payload)}
                    objects[index].extend(cab.objects.values())
            return asset, objects[asset["bundle"]]

        def loc(obj):
            return {"path_id": str(obj.path_id), "cab": obj.assets_file.name,
                    "source": sources[obj.assets_file.name]}

        def deref(pointer, obj):
            return PPtr(**pointer, assetsfile=obj.assets_file).deref()

        def sprite(pointer, owner, path):
            obj = deref(pointer, owner)
            key = obj.assets_file.name + ":" + str(obj.path_id)
            if key not in report["sprites"]:
                data = obj.read()
                img = data.image.convert("RGBA")
                stream = io.BytesIO()
                img.save(stream, format="PNG")
                filename = {"跳过箭头图标": "skip.png", "好感度外框": "relationship.png",
                            "分割线四": "speaker_mark.png", "提示点": "attention.png",
                            "对话按钮_底": "choice.png", "图案_感叹号": "exclamation.png"}.get(data.m_Name, sha(key.encode())[:16] + ".png")
                (output / filename).write_bytes(stream.getvalue())
                tree = obj.read_typetree()
                report["sprites"][key] = {"name": data.m_Name, "size": list(img.size),
                    "resource": "res://" + str((output / filename).relative_to(ROOT)),
                    "png_sha256": sha(stream.getvalue()), "border": tree.get("m_Border"),
                    "rect": tree.get("m_Rect"), "bindings": [], **loc(obj)}
            report["sprites"][key]["bindings"].append(path)
            return report["sprites"][key]

        for name in ("Panel_BattlePlayerCtrl", "Wide", "Btn_InteractableAct_TypeNaninovel",
                     "ButtonList", "ChoiceHandlerButton", "ATPanel_PopGetItemInfoTipAnim"):
            asset, primary = load(name)
            game_objects = {obj.path_id: obj.read_typetree() for obj in primary
                            if obj.type.name == "GameObject"}
            transforms = {obj.path_id: obj.read_typetree() for obj in primary
                          if obj.type.name in ("Transform", "RectTransform")}
            by_go = {tree["m_GameObject"]["m_PathID"]: key for key, tree in transforms.items()}

            def path(tid):
                if tid not in transforms:
                    return ""
                tree = transforms[tid]
                return path(tree["m_Father"]["m_PathID"]) + "/" + game_objects[
                    tree["m_GameObject"]["m_PathID"]]["m_Name"]

            paths = {tid: path(tid) for tid in transforms}
            selected = {tid for tid, p in paths.items() if name != "Panel_BattlePlayerCtrl"
                        or any(term in p for term in ("Naninovel", "Relationship"))}
            rows = []
            for obj in primary:
                tree = obj.read_typetree()
                tid = obj.path_id if obj.path_id in transforms else by_go.get(
                    tree.get("m_GameObject", {}).get("m_PathID", obj.path_id))
                if tid not in selected:
                    continue
                row = {"path": paths[tid], "type": obj.type.name, "fields": tree, **loc(obj)}
                if obj.type.name == "MonoBehaviour" and tree.get("m_Script", {}).get("m_PathID"):
                    row["class"] = deref(tree["m_Script"], obj).read().m_ClassName
                if tree.get("m_Sprite", {}).get("m_PathID"):
                    row["sprite"] = sprite(tree["m_Sprite"], obj, paths[tid])["resource"]
                rows.append(row)
            report["prefabs"][name] = {"asset": asset, "nodes": rows}

        _, symbols_primary = load("图案_感叹号")
        symbol = next(obj for obj in symbols_primary if obj.type.name == "Sprite"
                      and obj.peek_name() == "图案_感叹号")
        sprite({"m_FileID": 0, "m_PathID": symbol.path_id}, symbol, "explicit-address")

        _, tables = load("NPCData", dependencies=False)
        for obj in tables:
            if obj.type.name != "TextAsset" or obj.peek_name() not in (
                    "NPCData", "NPCFunctionData", "RelationshipTokenData"):
                continue
            data = obj.read()
            raw = data.m_Script
            if isinstance(raw, bytes):
                raw = raw.decode("utf-8-sig")
            report["config"][data.m_Name] = {"data": json.loads(raw), "sha256": sha(raw.encode()), **loc(obj)}
        _, stories = load("talkcfg_npc_130000_cn", dependencies=False)
        selected_stories = {"talkcfg_npc_130000_cn", "talkcfg_npc_139201", "talkcfg_npc_139101_cn",
                            "talkcfg_npc_139900_cn", "talkcfg_npc_130201_cn", "talkcfg_npc_130301_cn"}
        selected_stories.update("talkcfg_npc_13980" + str(i) + "_cn" for i in range(10))
        for obj in stories:
            if obj.type.name not in ("MonoBehaviour", "TextAsset"):
                continue
            if obj.peek_name() in selected_stories:
                report["stories"][obj.peek_name()] = {"fields": obj.read_typetree(), **loc(obj)}
        native = archive.read("lib/arm64-v8a/libil2cpp.so")
        metadata = archive.read("assets/bin/Data/Managed/Metadata/global-metadata.dat")
    report["native"]["sha256"] = sha(native)
    phoff = struct.unpack_from("<Q", native, 32)[0]
    entsize, count = struct.unpack_from("<HH", native, 54)
    segments = []
    for index in range(count):
        typ, flags, off, va, pa, filesz, memsz, align = struct.unpack_from(
            "<IIQQQQQQ", native, phoff + index * entsize)
        if typ == 1:
            segments.append((off, off + filesz, va))

    def virtual(offset):
        return next(va + offset - lo for lo, hi, va in segments if lo <= offset < hi)

    def file_offset(va):
        return next(lo + va - base for lo, hi, base in segments if base <= va < base + hi - lo)

    shoff = struct.unpack_from("<Q", native, 40)[0]
    shentsize, shcount = struct.unpack_from("<HH", native, 58)
    relocs = {}
    for index in range(shcount):
        section = struct.unpack_from("<IIQQQQIIQQ", native, shoff + index * shentsize)
        if section[1] == 4:
            for position in range(section[4], section[4] + section[5], section[9] or 24):
                target, info, addend = struct.unpack_from("<QQq", native, position)
                relocs[target] = addend
    entries, entries_size, strings, strings_size = struct.unpack_from("<4I", metadata, 8)

    pattern = re.compile(r'\[Address\(RVA = "0x[0-9A-F]+", Offset = "0x([0-9A-F]+)", Length = "0x([0-9A-F]+)"\)\]\s*(?:\[[^\n]+\]\s*)+([^\n]+)')
    skip_classes = {"NaninovelManager", "Panel_PlayerBattleCtrl", "ControlPanelSkipButton_Custom",
                    "ControlPanelSkipButton", "BattleManager", "ScriptPlayer"}
    selection = {"EnvUnitNPC", "NPCData", "NPCFunctionData"}
    skip_terms = ("Skip", "Naninovel", "StoryTalking", "OnAwake_Battle", "InitPanel_Battle")
    symbols, records = {}, []
    for stub in stubs.rglob("*.cs"):
        for match in pattern.finditer(stub.read_text()):
            offset, length = int(match[1], 16), int(match[2], 16)
            address = virtual(offset)
            symbols.setdefault(address, []).append(stub.stem + "." + match[3])
            if stub.stem in selection or (stub.stem in skip_classes and any(
                    term in match[3] for term in skip_terms)):
                records.append((stub, match[3], offset, length, address))
    engine = Cs(CS_ARCH_ARM64, CS_MODE_ARM)
    engine.detail = True
    methods = []
    for stub, signature, offset, length, address in records:
        instructions = []
        registers = {}
        for ins in engine.disasm(native[offset:offset + length], address):
            row = {"address": hex(ins.address), "instruction": ins.mnemonic + " " + ins.op_str}
            if ins.mnemonic in ("bl", "b") and ins.op_str.startswith("#0x"):
                row["target_names"] = symbols.get(int(ins.op_str[1:], 16), [])
            match = re.fullmatch(r"(x\d+), \[(x\d+), #(0x[0-9a-f]+)\]", ins.op_str)
            if ins.mnemonic == "ldr" and match and match[2] in registers:
                got = registers[match[2]] + int(match[3], 0)
                try:
                    encoded = struct.unpack_from("<Q", native, file_offset(relocs[got]))[0]
                    if encoded >> 29 == 5:
                        literal_index = (encoded & 0x1fffffff) >> 1
                        size, location = struct.unpack_from("<II", metadata, entries + 8 * literal_index)
                        row["literal"] = metadata[strings + location:strings + location + size].decode()
                        row["literal_source"] = {"got": hex(got), "literal_index": literal_index,
                                                 "metadata_offset": hex(strings + location)}
                except (KeyError, StopIteration):
                    pass
            instructions.append(row)
            for register in ins.regs_access()[1]:
                registers.pop(ins.reg_name(register), None)
            if ins.mnemonic in ("bl", "blr"):
                for register in range(19):
                    registers.pop("x" + str(register), None)
            if ins.mnemonic == "adrp":
                reg, value = ins.op_str.split(", #")
                registers[reg] = int(value, 0)
        methods.append({"class": stub.stem, "signature": signature, "stub": str(stub),
                        "file_offset": hex(offset), "address": hex(address), "length": length,
                        "instructions": instructions})
    report["native"]["methods"] = methods
    report["native"]["metadata_sha256"] = sha(metadata)
    report["native"]["limitations"] = "Cpp2IL stubs supply declarations; instructions are independently decoded from packaged native bytes. Indirect targets may be unresolved."
    (output / "source.json").write_text(json.dumps(safe(report), ensure_ascii=False, indent=2) + "\n")
    skip_report = {"apk": str(apk), "apk_sha256": apk_sha,
                   "native_sha256": report["native"]["sha256"],
                   "metadata_sha256": report["native"]["metadata_sha256"],
                   "methods": [method for method in methods if method["class"] in skip_classes],
                   "limitations": report["native"]["limitations"]}
    (output / "skip_native.json").write_text(json.dumps(safe(skip_report), ensure_ascii=False, indent=2) + "\n")
    compact_layout = {}
    retained_fields = {"m_AnchorMin", "m_AnchorMax", "m_AnchoredPosition", "m_SizeDelta", "m_Pivot",
                       "m_LocalScale", "m_fontSize", "m_fontColor", "m_FontData", "m_text", "m_Color",
                       "m_Padding", "m_ChildAlignment", "m_Spacing", "m_PreferredWidth", "m_PreferredHeight"}
    for prefab, value in report["prefabs"].items():
        rows = []
        for node in value["nodes"]:
            if "/ControlPanel" in node["path"]:
                continue
            fields = {key: val for key, val in node["fields"].items() if key in retained_fields}
            if fields or node.get("sprite"):
                rows.append({"path": node["path"], "type": node.get("class", node["type"]),
                             "fields": fields, "sprite": node.get("sprite")})
        compact_layout[prefab] = rows
    (output / "layout.json").write_text(json.dumps(safe(compact_layout), ensure_ascii=False, indent=2) + "\n")
    compact_stories = {}
    for name, story in report["stories"].items():
        rows = []
        for ref in story["fields"]["references"]["RefIds"]:
            data = ref.get("data", {})
            if "playbackSpot" not in data:
                continue
            params = {key: value["value"] for key, value in data.items()
                      if isinstance(value, dict) and value.get("hasValue")}
            rows.append({"line": data["playbackSpot"]["lineIndex"], "class": ref["type"]["class"],
                         "params": params})
        compact_stories[name] = rows
    (output / "stories.json").write_text(json.dumps(compact_stories, ensure_ascii=False, indent=2) + "\n")
    mapping = {entry["name"]: entry["resource"] for entry in report["sprites"].values()}
    (output / "resource_map.json").write_text(json.dumps(mapping, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"output": str(output), "sprites": len(mapping), "prefabs": list(report["prefabs"]),
                      "stories": list(report["stories"]), "methods": len(methods)}, ensure_ascii=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", required=True, type=Path)
    parser.add_argument("--output", default=ROOT / "assets/ui/dialogue", type=Path)
    parser.add_argument("--stubs", default=Path("/private/tmp/city-new-map-addresses/DiffableCs"), type=Path)
    args = parser.parse_args()
    recover(args.apk, args.output, args.stubs)
