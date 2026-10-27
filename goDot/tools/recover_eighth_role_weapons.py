"""Recover configured eighth-role weapon models directly from the selected APK."""

import argparse
import hashlib
import json
from pathlib import Path
import zipfile

import numpy as np
import UnityPy

from inspect_camp_progression import manifest_records
from recover_region_actors import ActorExporter


PROJECT = Path(__file__).resolve().parents[1]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main(apk):
    source = json.loads((PROJECT / "assets/data/WeaponData.json").read_text())
    rows = [row for row in source if 801 <= int(row["id"]) <= 805]
    report = {"apk_sha256": hashlib.file_digest(apk.open("rb"), "sha256").hexdigest(),
              "evidence_type": "static APK manifest, exact WeaponActionCfg text and referenced prefab meshes", "weapons": [], "icons": []}
    icon_mapping = {}
    with zipfile.ZipFile(apk) as archive:
        manifest_name = next(name for name in archive.namelist() if name.startswith(
            "assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes"))
        manifest = archive.read(manifest_name)
        assets, bundles = manifest_records(manifest)
        addresses = {row["address"]: row for row in assets}
        for row in rows:
            for field in ["square_icon_name", "full_icon_name"]:
                icon_name = row[field]
                if icon_name not in addresses:
                    report["icons"].append({"address": icon_name, "status": "exact_sprite_address_absent_from_manifest"})
                    continue
                icon_asset = addresses[icon_name]
                icon_member = "assets/yoo/DefaultPackage/" + bundles[icon_asset["bundle"]]["hash"] + ".bundle"
                icon_payload = archive.read(icon_member)
                icon_object = next(obj for obj in UnityPy.load(icon_payload).objects
                                   if obj.type.name == "Sprite" and obj.peek_name() == icon_name)
                icon_target = PROJECT / "assets/ui/role_weapon/weapon_icons" / (icon_name + ".png")
                icon_target.parent.mkdir(parents=True, exist_ok=True)
                icon_object.read().image.save(icon_target)
                icon_path = "res://" + str(icon_target.relative_to(PROJECT))
                icon_mapping[icon_name] = icon_path
                report["icons"].append({"address": icon_name, "status": "imported", "source": icon_member,
                                        "bundle_sha256": sha(icon_payload), "path_id": str(icon_object.path_id),
                                        "output": icon_path, "png_sha256": sha(icon_target.read_bytes())})
            name = "WeaponActionCfg_[" + str(row["res_id"]) + "]"
            item = {"id": int(row["id"]), "res_id": row["res_id"], "action_config": name}
            report["weapons"].append(item)
            if name not in addresses:
                item["status"] = "exact_action_config_absent_from_manifest"
                continue
            asset = addresses[name]
            member = "assets/yoo/DefaultPackage/" + bundles[asset["bundle"]]["hash"] + ".bundle"
            payload = archive.read(member)
            text = next(obj.read().m_Script for obj in UnityPy.load(payload).objects
                        if obj.type.name == "TextAsset" and obj.peek_name() == name)
            config = json.loads(text)
            item.update(config=config, config_member=member, config_bundle_sha256=sha(payload))
            prefab = config["Prefab"].removesuffix(".prefab")
            if prefab not in addresses:
                item["status"] = "referenced_prefab_absent_from_manifest"
                continue
            exporter = ActorExporter(archive, manifest, assets, bundles, prefab)
            exporter.build()
            target = PROJECT / ("assets/weapons/weapon_%d.glb" % int(row["id"]))
            exporter.write(target)
            minimum = np.min(np.asarray([pair[0] for pair in exporter.bounds]), axis=0)
            maximum = np.max(np.asarray([pair[1] for pair in exporter.bounds]), axis=0)
            metadata = {"id": int(row["id"]), "path": "res://" + str(target.relative_to(PROJECT)),
                        "source": exporter.asset["path"], "source_apk_sha256": report["apk_sha256"],
                        "bounds": {"min": minimum.tolist(), "max": maximum.tolist(), "size": (maximum - minimum).tolist()},
                        "nodes": len(exporter.data["nodes"]), "meshes": len(exporter.data["meshes"]),
                        "skins": len(exporter.data["skins"]), "bytes": target.stat().st_size,
                        "animations": [], "bundle_sources": exporter.bundle_evidence,
                        "rendering": "Exact source meshes, hierarchy, materials and textures; custom Unity shader approximated with PBR"}
            conversion = dict(metadata, renderer_sources=exporter.renderer_evidence, materials=exporter.material_sources,
                              failures=exporter.failures, action_config=item, evidence_type=report["evidence_type"])
            target.with_suffix(".conversion.json").write_text(json.dumps(conversion, ensure_ascii=False, indent=2) + "\n")
            item.update(status="imported", metadata=metadata, glb_sha256=sha(target.read_bytes()))
    (PROJECT / "reports/eighth-role-weapon-import.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    (PROJECT / "assets/ui/role_weapon/weapon_icon_resource_map.json").write_text(json.dumps(icon_mapping, ensure_ascii=False, indent=2) + "\n")
    (PROJECT / "assets/ui/role_weapon/weapon_icon_provenance.json").write_text(json.dumps({"apk_sha256": report["apk_sha256"], "icons": report["icons"]}, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps([{key: row[key] for key in ("id", "res_id", "status")} for row in report["weapons"]]))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    main(parser.parse_args().apk)
