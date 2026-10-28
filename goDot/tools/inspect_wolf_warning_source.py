#!/usr/bin/env python3
"""Inspect exact warning particle scaling and shader pass state from the APK."""

import hashlib
import json
from pathlib import Path
import zipfile

import UnityPy

from recover_chest_effects import package_manifest


ROOT = Path(__file__).resolve().parents[2]


def main():
    apk = ROOT / "1061664.apk"
    names = {"fx_other_enemyatkrangerectangle", "fx_other_attackrange360_radius1"}
    env = UnityPy.Environment()
    report = {"evidence_type": "Static packaged particle scaling fields and compiled shader pass states; no APK runtime execution", "particles": [], "shaders": []}
    with apk.open("rb") as stream:
        report["apk_sha256"] = hashlib.file_digest(stream, "sha256").hexdigest()
    if report["apk_sha256"] != "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505":
        raise ValueError("Unexpected APK")
    with zipfile.ZipFile(apk) as archive:
        manifest = package_manifest(archive.read(next(name for name in archive.namelist() if name.startswith(
            "assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes"))))
        assets = [row for row in manifest["assets"] if row["address"] in names]
        primary_files = set()
        for index in sorted({index for asset in assets for index in [asset["bundle"], *asset["deps"]]}):
            member = "assets/yoo/DefaultPackage/" + manifest["bundles"][index]["hash"] + ".bundle"
            bundle = env.load_file(archive.read(member), name=member)
            if index in {asset["bundle"] for asset in assets}:
                primary_files.update(bundle.files)
    objects = {(obj.assets_file.name, obj.path_id): obj for obj in env.objects}
    for obj in env.objects:
        if obj.type.name == "ParticleSystem" and obj.assets_file.name in primary_files:
            data = obj.read_typetree()
            go = objects[(obj.assets_file.name, data["m_GameObject"]["m_PathID"])].read_typetree()
            report["particles"].append({"source": f"{obj.assets_file.name}:{obj.path_id}", "name": go["m_Name"],
                "scalingMode": data.get("scalingMode"), "simulationSpace": data.get("moveWithTransform")})
        elif obj.type.name == "Shader":
            data = obj.read_typetree()
            parsed = data.get("m_ParsedForm", {})
            name = data.get("m_Name") or parsed.get("m_Name", "")
            if name == "AllIn1Vfx/AllIn1VfxSRPBatch":
                report["shaders"].append({"source": f"{obj.assets_file.name}:{obj.path_id}", "name": name,
                    "passes": [{"pass_name": shader_pass.get("m_Name"), "state": shader_pass.get("m_State")} for subshader in parsed.get("m_SubShaders", []) for shader_pass in subshader.get("m_Passes", [])]})
    output = ROOT / "goDot/reports/wolf-warning-source.json"
    output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"particles": report["particles"], "shaders": report["shaders"]}))


if __name__ == "__main__":
    main()
