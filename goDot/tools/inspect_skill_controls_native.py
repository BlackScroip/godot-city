"""Retain current-APK skill input and icon-scale evidence without execution."""

import argparse
import hashlib
import json
from pathlib import Path
import struct
import zipfile

import UnityPy

import inspect_new_camp_native as native_audit


APK_SHA = "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505"
NATIVE_SHA = "86481018e3b55575e27d0d99a5979299b7fbbdf718698918ab5ebfbbccb68944"
PREFAB_MEMBER = "assets/yoo/DefaultPackage/c77908234c52fdfb5f6694d3dc60f5dd.bundle"
NATIVE_MEMBER = "lib/arm64-v8a/libil2cpp.so"
SELECTION = {
    "Panel_PlayerBattleCtrl": [
        "RegisterBattleBtnDel()", "<RegisterBattleBtnDel>b__82_",
        "RegisterActSkillUIUpdate()", "UpdateAutoAttack()",
        "ClickBtn(", "Panel_PlayerBattleCtrl()",
    ],
    "PlayerControll_SkillActSlotBase": [
        "RegisterTouchEvent()", "<RegisterTouchEvent>b__31_",
    ],
    "HanderCtrlSys": ["RegisterTouchEvent()", "<RegisterTouchEvent>b__26_2"],
    "PEListener": ["Update()", "OnPointerDown(", "OnPointerUp("],
    "LocalPlayer": ["OnMessagePlayerController(", "OnActionStart("],
    "Player": ["OnActionStart("],
    "ActionInterruptSkillSwitch": ["Enter(", "ExcuteActModify("],
    "Button": ["OnPointerClick(", "Press()"],
    "PropertyName": ["PropertyName()"],
}
METHOD_SLOTS = {
    "normal_down": 0x65D8C08,
    "normal_long": 0x65D8C10,
    "normal_up": 0x65D8C18,
    "skill1_down": 0x65D8C38,
    "skill1_long": 0x65D8C40,
    "skill1_up": 0x65D8C20,
    "skill2_down": 0x65D8C28,
    "dodge_down": 0x65D8C30,
    "icon_down": 0x65D96C8,
    "icon_up": 0x65D96D0,
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def inspect(apk, native_path, stubs):
    with apk.open("rb") as stream:
        apk_sha = hashlib.file_digest(stream, "sha256").hexdigest()
    if apk_sha != APK_SHA:
        raise ValueError("This evidence map requires the user-supplied APK hash")
    native = native_path.read_bytes()
    if digest(native) != NATIVE_SHA:
        raise ValueError("Native hash does not match the selected APK version")
    with zipfile.ZipFile(apk) as archive:
        if digest(archive.read(NATIVE_MEMBER)) != NATIVE_SHA:
            raise ValueError("Native library differs from the actual APK member")
        prefab = archive.read(PREFAB_MEMBER)
    segments = []
    phoff = struct.unpack_from("<Q", native, 32)[0]
    entry_size, count = struct.unpack_from("<HH", native, 54)
    for index in range(count):
        kind, _, offset, virtual, _, size, _, _ = struct.unpack_from(
            "<IIQQQQQQ", native, phoff + index * entry_size)
        if kind == 1:
            segments.append((offset, virtual, size))

    def file_at(virtual):
        return next(offset + virtual - start for offset, start, size in segments
                    if start <= virtual < start + size)

    native_audit.SELECTION = SELECTION
    native_audit.SELECTED_OFFSETS = set()
    evidence = native_audit.inspect(native_path, stubs)
    for method in evidence["methods"]:
        offset, length = int(method["file_offset"], 16), method["length"]
        method["bytes"] = native[offset:offset + length].hex()
        method["source_sha256"] = digest(Path(method["stub"]).read_bytes())
    bindings = {}
    by_slot = {value: name for name, value in METHOD_SLOTS.items()}
    shoff = struct.unpack_from("<Q", native, 40)[0]
    shsize, shcount = struct.unpack_from("<HH", native, 58)
    for index in range(shcount):
        section = struct.unpack_from("<IIQQQQIIQQ", native, shoff + index * shsize)
        _, kind, _, _, offset, size, _, _, _, stride = section
        if kind != 4:
            continue
        for pos in range(offset, offset + size, stride):
            virtual, info, addend = struct.unpack_from("<QQq", native, pos)
            if virtual not in by_slot:
                continue
            encoded_offset = file_at(addend)
            encoded = struct.unpack_from("<Q", native, encoded_offset)[0]
            if info != 1027 or (encoded >> 29) & 7 != 3:
                raise ValueError("Expected relative method-definition metadata usage")
            bindings[by_slot[virtual]] = {
                "slot_va": hex(virtual), "rela_file_offset": hex(pos),
                "rela_bytes": native[pos:pos + stride].hex(),
                "encoded_value_va": hex(addend), "encoded_value": hex(encoded),
                "method_definition_token": hex(0x06000001 + ((encoded >> 1) & 0x0FFFFFFF)),
            }
    if len(bindings) != len(METHOD_SLOTS):
        raise ValueError("Not all delegate bindings were retained")
    literals = {}
    for name, virtual in (("pressed_icon_scale", 0x1287E20), ("clickbtn_duration", 0x12882B4)):
        offset = file_at(virtual)
        literals[name] = {
            "virtual_address": hex(virtual), "file_offset": hex(offset),
            "bytes": native[offset:offset + 4].hex(),
            "float32": struct.unpack_from("<f", native, offset)[0],
        }
    table_va = 0x12F247E
    table_offset = file_at(table_va)
    control_cases = {
        str(index): hex(0x3157BB0 + 4 * struct.unpack_from("<H", native, table_offset + index * 2)[0])
        for index in range(12)
    }

    environment = UnityPy.load(prefab)
    objects = {obj.path_id: obj.read_typetree() for obj in environment.objects
               if obj.type.name == "GameObject"}
    transforms = {obj.path_id: obj.read_typetree() for obj in environment.objects
                  if obj.type.name in ("Transform", "RectTransform")}
    by_game_object = {value["m_GameObject"]["m_PathID"]: key for key, value in transforms.items()}

    def hierarchy(game_object):
        name = objects[game_object]["m_Name"]
        transform = transforms.get(by_game_object.get(game_object), {})
        parent = transforms.get(transform.get("m_Father", {}).get("m_PathID"))
        return (hierarchy(parent["m_GameObject"]["m_PathID"]) + "/" if parent else "") + name

    serialized = []
    for obj in environment.objects:
        if obj.type.name != "MonoBehaviour":
            continue
        tree = obj.read_typetree()
        path = hierarchy(tree["m_GameObject"]["m_PathID"])
        if "Skill_NormalAttack" in tree:
            fields = {key: value for key, value in tree.items() if "LongPress" in key}
            kind = "Panel_PlayerBattleCtrl (field-identified)"
        elif "LongPressTrigTime" in tree and "/SkillSlot_" in path and "MonsterSupport" not in path:
            fields = {key: tree[key] for key in ("LongPressTrigTime", "LongPressTrigIntervalTime")}
            kind = "PEListener (field-identified)"
        elif "hander" in tree and "canvasGroup_Container" in tree and "image_SkillIcon" in tree:
            fields = {key: tree[key] for key in ("hander", "image_SkillIcon")}
            icon_id = fields["image_SkillIcon"]["m_PathID"]
            icon = next(item for item in environment.objects if item.path_id == icon_id).read_typetree()
            fields["icon_target_path"] = hierarchy(icon["m_GameObject"]["m_PathID"])
            kind = "PlayerControll_SkillActSlotBase (field-identified)"
        elif "buttonGroups" in tree:
            fields, kind = tree, "UnityBtnClickAnim candidate (field-identified)"
        else:
            continue
        serialized.append({"path": path, "path_id": str(obj.path_id), "kind": kind, "fields": fields})
    evidence.update({
        "apk": str(apk), "apk_sha256": apk_sha,
        "delegate_bindings": bindings, "literals": literals,
        "localplayer_switch": {
            "table_va": hex(table_va), "table_file_offset": hex(table_offset),
            "bytes": native[table_offset:table_offset + 24].hex(), "case_targets": control_cases,
        },
        "prefab": {"member": PREFAB_MEMBER, "sha256": digest(prefab), "selected_components": serialized},
        "limitations": [
            "Static ARM64 and serialized prefab evidence; original Android/iOS runtime was not executed.",
            "Cpp2IL declarations supply identities, fields and file offsets only; their empty method bodies are not decompiled behavior.",
            "ELF executable segment virtual addresses differ from file offsets by 0x4000 for selected methods.",
            "Input command dispatch and direct property writes are covered; all downstream character action graphs are not.",
        ],
    })
    return evidence


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", required=True, type=Path)
    parser.add_argument("--native", required=True, type=Path)
    parser.add_argument("--stubs", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    result = inspect(args.apk, args.native, args.stubs)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"output": str(args.output), "native_sha256": result["native_sha256"],
                      "method_count": len(result["methods"]), "bindings": len(result["delegate_bindings"])}))
