"""Recover the selected APK's exact fashion prefabs for character previews."""

import argparse
from concurrent.futures import ProcessPoolExecutor, as_completed
import hashlib
import json
from pathlib import Path
import struct
import zipfile

import numpy as np
import UnityPy

from inspect_camp_progression import manifest_records
from recover_region_actors import ActorExporter, MANIFEST


PROJECT = Path(__file__).resolve().parents[1]
OUTPUT = PROJECT / "assets/characters/fashions"
REPORT = PROJECT / "reports/character-fashion-model-recovery-20261028.json"
EXPECTED_APK = "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505"


def digest(payload):
    return hashlib.sha256(payload).hexdigest()


class FashionExporter(ActorExporter):
    def accessor(self, values, kind, dtype="<f4", target=34962, bounds=False):
        values = np.asarray(values)
        # Unity can store two bone influences; glTF requires four components.
        if kind == "VEC4" and values.ndim == 2 and values.shape[1] < 4:
            values = np.pad(values, ((0, 0), (0, 4 - values.shape[1])))
        return super().accessor(values, kind, dtype, target, bounds)


def valid_accessors(data):
    component_bytes = {5126: 4, 5125: 4, 5123: 2, 5121: 1}
    components = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
    for accessor in data["accessors"]:
        view = data["bufferViews"][accessor["bufferView"]]
        width = component_bytes[accessor["componentType"]] * components[accessor["type"]]
        required = (accessor["count"] - 1) * view.get("byteStride", width) + width + accessor.get("byteOffset", 0)
        if required > view["byteLength"]:
            return False
    return True


def recover_one(apk, row):
    target = OUTPUT / ("fashion_%d.glb" % row["id"])
    evidence_path = target.with_suffix(".conversion.json")
    if target.exists() and evidence_path.exists():
        evidence = json.loads(evidence_path.read_text())
        binary = target.read_bytes()
        data = json.loads(binary[20:20 + struct.unpack_from("<I", binary, 12)[0]])
        if (evidence.get("source_apk_sha256") == EXPECTED_APK
                and evidence.get("prefab") == row["model_prefab_path"]
                and evidence.get("glb_sha256") == digest(binary) and valid_accessors(data)):
            return evidence
    with zipfile.ZipFile(apk) as archive:
        manifest = archive.read(MANIFEST)
        assets, bundles = manifest_records(manifest)
        exporter = FashionExporter(archive, manifest, assets, bundles, row["model_prefab_path"])
        exporter.build()
        exporter.recover_animations()
        for animation in exporter.data.get("animations", []) + exporter.animations:
            if animation["name"].endswith("_loop"):
                animation["name"] += "_clip"
        if exporter.failures or not exporter.data["skins"]:
            raise ValueError("Fashion has incomplete source geometry: %d" % row["id"])
        if not any("idle" in item["name"].lower() for item in exporter.animations):
            raise ValueError("Fashion has no recovered source idle animation: %d" % row["id"])
        if not valid_accessors(exporter.data):
            raise ValueError("Fashion has an invalid glTF buffer accessor: %d" % row["id"])
        exporter.write(target)
        evidence = {
            "id": row["id"], "character_id": row["chara_id"],
            "path": "res://" + str(target.relative_to(PROJECT)),
            "prefab": row["model_prefab_path"], "source_asset": exporter.asset["path"],
            "source_apk_sha256": EXPECTED_APK, "apk_manifest": MANIFEST,
            "glb_sha256": digest(target.read_bytes()), "bytes": target.stat().st_size,
            "meshes": len(exporter.data["meshes"]), "skins": len(exporter.data["skins"]),
            "nodes": len(exporter.data["nodes"]), "animations": exporter.animations,
            "bundle_sources": exporter.bundle_evidence,
            "renderer_sources": exporter.renderer_evidence,
            "materials": exporter.material_sources,
            "unsupported": dict(exporter.unsupported), "failures": exporter.failures,
            "evidence_type": "static packaged fashion prefab, dependency closure, and controller curves",
            "rendering": "Exact source mesh, skin, texture and colors; Unity custom shaders approximated with PBR; particle systems are not converted",
        }
        evidence_path.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n")
        return evidence


def main(args):
    with args.apk.open("rb") as stream:
        apk_hash = hashlib.file_digest(stream, "sha256").hexdigest()
    if apk_hash != EXPECTED_APK:
        raise ValueError("This recovery is bound to the user-selected 1061664.apk")
    with zipfile.ZipFile(args.apk) as archive:
        manifest = archive.read(MANIFEST)
        assets, bundles = manifest_records(manifest)
        asset = next(item for item in assets if item["address"] == "CharaFashionConfigData")
        member = "assets/yoo/DefaultPackage/" + bundles[asset["bundle"]]["hash"] + ".bundle"
        payload = archive.read(member)
        source = next(obj for obj in UnityPy.load(payload).objects
                      if obj.type.name == "TextAsset" and obj.peek_name() == "CharaFashionConfigData")
        text = source.read().m_Script
        if isinstance(text, bytes):
            text = text.decode("utf-8-sig")
        rows = json.loads(text)
        local_rows = json.loads((PROJECT / "assets/ui/role_character/CharaFashionConfigData.json").read_text())
        if rows != local_rows:
            raise ValueError("Local fashion table differs from the supplied APK")
        lookup = {item["address"]: item for item in assets}
        names = set(archive.namelist())
        inventory = []
        for row in rows:
            found = lookup.get(row["model_prefab_path"])
            bundle_member = "assets/yoo/DefaultPackage/" + bundles[found["bundle"]]["hash"] + ".bundle" if found else ""
            inventory.append({"id": row["id"], "prefab": row["model_prefab_path"],
                              "manifest_match": bool(found), "packaged": bundle_member in names,
                              "member": bundle_member})
        if not all(item["packaged"] for item in inventory):
            raise ValueError("At least one requested fashion prefab is absent from the APK")
        table_evidence = {"source_asset": asset["path"], "member": member,
                          "bundle_sha256": digest(payload), "path_id": str(source.path_id)}
    selected = [row for row in rows if not args.fashion or row["id"] in args.fashion]
    OUTPUT.mkdir(parents=True, exist_ok=True)
    failures = []
    with ProcessPoolExecutor(max_workers=args.jobs) as pool:
        tasks = {pool.submit(recover_one, args.apk, row): row["id"] for row in selected}
        for task in as_completed(tasks):
            ident = tasks[task]
            try:
                evidence = task.result()
                print(json.dumps({"id": ident, "meshes": evidence["meshes"],
                                  "animations": len(evidence["animations"]), "bytes": evidence["bytes"]}), flush=True)
            except Exception as error:
                failures.append({"id": ident, "error": str(error)})
                print(json.dumps(failures[-1]), flush=True)
    models = {}
    for row in rows:
        path = OUTPUT / ("fashion_%d.conversion.json" % row["id"])
        if not path.exists():
            continue
        evidence = json.loads(path.read_text())
        keys = ["id", "character_id", "path", "prefab", "source_asset", "glb_sha256", "meshes", "skins"]
        models[str(row["id"])] = {key: evidence[key] for key in keys}
        models[str(row["id"])]["animations"] = [item["name"] for item in evidence["animations"]]
    catalog = {"schema": 1, "apk_sha256": apk_hash, "models": models}
    (OUTPUT / "catalog.json").write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n")
    report = {"apk_sha256": apk_hash, "manifest": MANIFEST, "manifest_sha256": digest(manifest),
              "table": table_evidence, "inventory": inventory, "exported": len(models),
              "failures": failures, "completed": not failures and len(models) == len(rows),
              "limitations": ["Static recovery only; original APK runtime was not executed.",
                              "Custom Unity shaders use PBR approximation; particles and unsupported non-TRS animation bindings are retained in evidence, not claimed as converted."]}
    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"exported": len(models), "failures": failures, "completed": report["completed"]}), flush=True)
    return 1 if failures else 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--fashion", type=int, action="append")
    parser.add_argument("--jobs", type=int, default=2)
    raise SystemExit(main(parser.parse_args()))
