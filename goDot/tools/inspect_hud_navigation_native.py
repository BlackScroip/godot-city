"""Retain current-APK HUD navigation prefab and bounded ARM64 evidence."""

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
PREFAB_MEMBER = "assets/yoo/DefaultPackage/c77908234c52fdfb5f6694d3dc60f5dd.bundle"
NATIVE_MEMBER = "lib/arm64-v8a/libil2cpp.so"
METADATA_MEMBER = "assets/bin/Data/Managed/Metadata/global-metadata.dat"
SELECTION = {
    "Box_MainPageMenuArea": ["Awake", "OnEnable", "ApplyDisplaySwitchConstraint", "SetButtonActive", "Msg_Display", "Anim_ClickBtn"],
    "Box_RougeRes": ["UpdateValue", "OnEnable", "UpdateUIInfo"],
    "Slot_ResBox": ["SetDisplay", "Start()", "SyncValue", "Update", "Slot_ResBox()"],
    "ATGameManager": ["SendMsg_Display", "SwitchProcessState", "Update_MainPageMenu", "Msg_OpenCatMealMenu_MealBuff"],
    "UIOpener_AT": ["OpenCloudSavePanel", "OpenGoComment", "Msg_OpenRogueDifficultyPanel"],
    "ATPop_GoComment": ["RegisterItem"],
    "Panel_PlayerBattleCtrl": ["SwitchPlayerCtrl", "SetModeGroup", "Msg_ModeGroup"],
}
LOCALIZATION_KEYS = {
    "keyname_CloudSave_FirstTip", "ATPanel_CloudSave_CannotOpenInBattle",
    "keyname_GoComment", "keyname_Btn_CatMealBuff_Name", "keyname_Btn_OptionMenu_Name",
    "ATPanel_RogueLevelDifficulty_SelectDifficulty", "keyword_Hint", "keyword_Sure", "keyword_Cancel",
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def configuration_evidence(archive):
    member = next(name for name in archive.namelist() if name.startswith(
        "assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes"))
    manifest = archive.read(member)
    assets, bundles = manifest_records(manifest)
    selected = [asset for asset in assets if asset["address"] == "RogueConfigData"
                or asset["address"].startswith("LocalizationData_")]
    addresses = {asset["address"]: asset for asset in selected}
    tables = {}
    for index in sorted({asset["bundle"] for asset in selected}):
        bundle_member = "assets/yoo/DefaultPackage/" + bundles[index]["hash"] + ".bundle"
        payload = archive.read(bundle_member)
        for obj in UnityPy.load(payload).objects:
            if obj.type.name != "TextAsset":
                continue
            asset = obj.read()
            if asset.m_Name not in addresses:
                continue
            text = asset.m_Script
            raw = text if isinstance(text, bytes) else text.encode("utf-8")
            parsed = json.loads(raw.decode("utf-8-sig"))
            if asset.m_Name == "RogueConfigData":
                data = {key: value for key, value in parsed.items() if key == "URL_GoComment"}
            else:
                data = [row for row in parsed if row.get("key") in LOCALIZATION_KEYS]
            if not data:
                continue
            tables[asset.m_Name] = {"manifest_asset": addresses[asset.m_Name],
                                    "member": bundle_member, "bundle_sha256": sha(payload),
                                    "path_id": str(obj.path_id), "text_asset_sha256": sha(raw),
                                    "data": data}
    return {"manifest_member": member, "manifest_sha256": sha(manifest), "tables": tables,
            "scope": "Exact selected packaged values; external URLs were not opened."}


def inspect(apk, native_path, metadata_path, stubs, component_map):
    native, metadata = native_path.read_bytes(), metadata_path.read_bytes()
    with apk.open("rb") as stream:
        apk_sha = hashlib.file_digest(stream, "sha256").hexdigest()
    if apk_sha != APK_SHA or sha(native) != NATIVE_SHA:
        raise ValueError("HUD address map requires the audited current APK and native hashes")
    with zipfile.ZipFile(apk) as archive:
        if archive.read(NATIVE_MEMBER) != native or archive.read(METADATA_MEMBER) != metadata:
            raise ValueError("Extracted native/metadata must match the APK members")
        prefab = archive.read(PREFAB_MEMBER)
        configuration = configuration_evidence(archive)
    phoff = struct.unpack_from("<Q", native, 32)[0]
    phsize, phcount = struct.unpack_from("<HH", native, 54)
    segments = [struct.unpack_from("<IIQQQQQQ", native, phoff + index * phsize)
                for index in range(phcount)]

    def file_at(va):
        return next(offset + va - start for kind, _, offset, start, _, size, _, _ in segments
                    if kind == 1 and start <= va < start + size)

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
    literals, literals_size, literal_data, literal_size = struct.unpack_from("<4I", metadata, 8)
    strings, strings_size = struct.unpack_from("<II", metadata, 0x18)
    typedefs, typebytes = struct.unpack_from("<II", metadata, 0xA0)
    methods, methodbytes = struct.unpack_from("<II", metadata, 0x30)

    def read_string(index):
        end = metadata.index(b"\0", strings + index, strings + strings_size)
        return metadata[strings + index:end].decode("utf-8")

    types = {}
    for ordinal in range(typebytes // 88):
        offset = typedefs + ordinal * 88
        name, namespace, byval = struct.unpack_from("<III", metadata, offset)
        types[byval] = read_string(namespace) + "." + read_string(name)

    def reference(va):
        if va not in relocations:
            return None
        position, carrier = relocations[va]
        try:
            offset = file_at(carrier)
        except StopIteration:
            return None
        encoded = struct.unpack_from("<Q", native, offset)[0]
        kind, index = (encoded >> 29) & 7, (encoded >> 1) & 0x0FFFFFFF
        result = {"got_va": hex(va), "rela_file_offset": hex(position),
                  "rela_bytes": native[position:position + 24].hex(),
                  "carrier_va": hex(carrier), "encoded": hex(encoded), "usage_kind": kind}
        if not encoded & 1:
            return None
        if kind == 5 and index < literals_size // 8:
            entry = literals + 8 * index
            length, location = struct.unpack_from("<II", metadata, entry)
            result.update({"literal_index": index, "metadata_entry": hex(entry),
                           "metadata_data": hex(literal_data + location),
                           "utf8": metadata[literal_data + location:literal_data + location + length].decode("utf-8")})
        elif kind == 3 and index < methodbytes // 36:
            off = methods + 36 * index
            name, declaring_type = struct.unpack_from("<II", metadata, off)
            typeoff = typedefs + declaring_type * 88
            typename, namespace = struct.unpack_from("<II", metadata, typeoff)
            result.update({"method_definition_token": hex(0x06000001 + index),
                           "method": read_string(namespace) + "." + read_string(typename) + "." + read_string(name)})
        elif kind in (1, 2):
            result["type"] = types.get(index, "type-index:" + str(index))
        return result

    native_audit.SELECTION = SELECTION
    native_audit.SELECTED_OFFSETS = {0x2FAF2DC}
    evidence = native_audit.inspect(native_path, stubs)
    references = {}
    for method in evidence["methods"]:
        offset, length = int(method["file_offset"], 16), method["length"]
        method["bytes"] = native[offset:offset + length].hex()
        method["stub_sha256"] = sha(Path(method["stub"]).read_bytes())
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
                    instruction["metadata_reference"] = hex(va)
                registers.pop(target, None)
            elif op == "bl":
                for register in range(19):
                    registers.pop("x" + str(register), None)

    environment = UnityPy.load(prefab)
    objects = {obj.path_id: obj.read_typetree() for obj in environment.objects
               if obj.type.name == "GameObject"}
    transforms = {obj.path_id: obj.read_typetree() for obj in environment.objects
                  if obj.type.name in ("Transform", "RectTransform")}
    by_go = {value["m_GameObject"]["m_PathID"]: ident for ident, value in transforms.items()}

    def hierarchy(go):
        transform = transforms.get(by_go.get(go), {})
        parent = transforms.get(transform.get("m_Father", {}).get("m_PathID"))
        return (hierarchy(parent["m_GameObject"]["m_PathID"]) + "/" if parent else "") + objects[go]["m_Name"]

    scripts = {int(row["path_id"]): row["script"] for row in component_map["components"]}
    serialized, controls = [], []
    for obj in environment.objects:
        if obj.type.name != "MonoBehaviour":
            continue
        tree = obj.read_typetree()
        go = tree["m_GameObject"]["m_PathID"]
        path = hierarchy(go)
        if "/Box_MainPageMenuArea" not in path:
            continue
        if scripts.get(obj.path_id) in ("Box_MainPageMenuArea", "Box_RougeRes", "Slot_ResBox"):
            serialized.append({"path_id": str(obj.path_id), "script": scripts[obj.path_id],
                               "path": path, "active": objects[go]["m_IsActive"], "fields": tree})
        if any(key in tree for key in ("m_Sprite", "m_Text", "m_text", "Localization_KeyId", "m_OnClick", "m_Spacing", "m_CellSize")):
            controls.append({"path_id": str(obj.path_id), "script": scripts.get(obj.path_id),
                             "path": path, "fields": tree})
    game_objects = []
    for ident, obj in objects.items():
        path = hierarchy(ident)
        if "/Box_MainPageMenuArea" not in path:
            continue
        transform = transforms[by_go[ident]]
        parent = transforms.get(transform["m_Father"]["m_PathID"], {})
        order = next((index for index, ptr in enumerate(parent.get("m_Children", []))
                      if ptr["m_PathID"] == by_go[ident]), 0)
        game_objects.append({"path_id": str(ident), "path": path, "active": obj["m_IsActive"],
                             "sibling_index": order, "rect_transform": transform})
    evidence.update({"apk": str(apk), "apk_sha256": apk_sha, "metadata_sha256": sha(metadata),
                     "metadata_references": references,
                     "configuration": configuration,
                     "selected_float_literals": [{"va": hex(va), "file_offset": hex(file_at(va)),
                                                   "bytes": native[file_at(va):file_at(va) + 4].hex(),
                                                   "float32": struct.unpack_from("<f", native, file_at(va))[0],
                                                   "purpose": purpose}
                                                  for va, purpose in (
                                                      (0x1287D00, "Resource total text initial scale"),
                                                      (0x1287D08, "Resource total text blue color component"),
                                                      (0x1287E20, "Resource total text green color component"),
                                                      (0x1287F74, "Resource total text scale return duration"))],
                     "prefab": {"member": PREFAB_MEMBER, "sha256": sha(prefab),
                                "controllers": serialized, "controls": controls, "game_objects": game_objects},
                     "limitations": ["Static prefab/native evidence; original APK runtime was not executed.",
                                     "Cpp2IL empty declaration bodies are identities, not decompilation.",
                                     "Prefab active flags alone do not establish runtime visibility.",
                                     "Sequential register tracking labels direct GOT loads only and is not control-flow analysis."]})
    return evidence


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--native", type=Path, required=True)
    parser.add_argument("--metadata", type=Path, required=True)
    parser.add_argument("--stubs", type=Path, required=True)
    parser.add_argument("--component-map", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = inspect(args.apk, args.native, args.metadata, args.stubs,
                     json.loads(args.component_map.read_text()))
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"output": str(args.output), "methods": len(result["methods"]),
                      "metadata_references": len(result["metadata_references"]),
                      "controllers": len(result["prefab"]["controllers"])}))
