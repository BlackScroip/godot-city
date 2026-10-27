"""Read the selected APK's small-map pivot, spacing and viewport evidence."""

import argparse
import hashlib
import json
from pathlib import Path
import zipfile

import UnityPy
from UnityPy.classes.PPtr import PPtr

from inspect_camp_progression import manifest_records
from inspect_map_selection_native import APK_SHA
from recover_route_art import package_dependencies


def inspect(apk):
    with apk.open("rb") as stream:
        apk_sha = hashlib.file_digest(stream, "sha256").hexdigest()
    if apk_sha != APK_SHA:
        raise ValueError("Expected the user-supplied 1061664.apk")
    result = {"apk": str(apk), "apk_sha256": apk_sha, "prefabs": []}
    with zipfile.ZipFile(apk) as archive:
        manifest_name = next(name for name in archive.namelist() if name.startswith(
            "assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes"))
        manifest = archive.read(manifest_name)
        assets, bundles = manifest_records(manifest)
        for address in ("ATPanel_RoadMapSelect", "ATSlot_RoadMapNode"):
            asset = next(row for row in assets if row["address"] == address)
            dependencies, edges = package_dependencies(manifest, address)
            pending, seen = [asset["bundle"], *dependencies], set()
            env, primary, sources = UnityPy.Environment(), [], []
            while pending:
                index = pending.pop()
                if index in seen:
                    continue
                seen.add(index)
                pending.extend(edges[index])
                member = "assets/yoo/DefaultPackage/" + bundles[index]["hash"] + ".bundle"
                payload = archive.read(member)
                loaded = env.load_file(payload)
                sources.append({"member": member, "sha256": hashlib.sha256(payload).hexdigest()})
                if index == asset["bundle"]:
                    primary = [obj for file in loaded.files.values() if hasattr(file, "objects")
                               for obj in file.objects.values()]

            def deref(pointer, owner):
                return PPtr(**pointer, assetsfile=owner.assets_file).deref()

            def rect(obj):
                if obj.type.name != "RectTransform":
                    tree = obj.read_typetree()
                    go = deref(tree["m_GameObject"], obj)
                    obj = next(component for entry in go.read_typetree()["m_Component"]
                               if (component := deref(entry["component"], go)).type.name == "RectTransform")
                tree = obj.read_typetree()
                return {"path_id": str(obj.path_id), "file": obj.assets_file.name,
                        "name": deref(tree["m_GameObject"], obj).peek_name(),
                        "fields": {key: tree[key] for key in (
                            "m_AnchorMin", "m_AnchorMax", "m_AnchoredPosition",
                            "m_SizeDelta", "m_Pivot", "m_LocalScale")}}

            record = {"asset": asset, "sources": sources}
            for obj in primary:
                if obj.type.name != "MonoBehaviour":
                    continue
                tree = obj.read_typetree()
                if "mFirtNodeInitPos" in tree:
                    record["layout"] = {key: tree[key] for key in (
                        "mFirtNodeInitPos", "mColumnNodeSpace", "mLineNodeSpace")}
                    record["slot_rect"] = rect(deref(tree["mPrefab_Slot"], obj))
                    scroll = deref(tree["mScrollview_Slot"], obj)
                    scroll_tree = scroll.read_typetree()
                    record["content_rect"] = rect(deref(scroll_tree["m_Content"], scroll))
                    record["viewport_rect"] = rect(deref(scroll_tree["m_Viewport"], scroll))
                elif "stateArray_NoReachable" in tree:
                    record["slot_rect"] = rect(obj)
            if "slot_rect" not in record:
                raise ValueError("Small-map slot not found: " + address)
            result["prefabs"].append(record)
    result["limitations"] = ["Static serialized layout; no Android runtime was executed."]
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    evidence = inspect(args.apk)
    args.output.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"output": str(args.output), "prefabs": len(evidence["prefabs"])}))
