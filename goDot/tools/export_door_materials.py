#!/usr/bin/env python3
"""Recover airwall mesh materials using the same exact-pointer APK exporter."""
import export_camp_portal_materials as exporter
import json

exporter.OUT = exporter.ROOT / "goDot/assets/environment_effects/doors"
exporter.OUT.mkdir(parents=True, exist_ok=True)
exporter.NAMES = {"25021701_fx_env_airwall", "24040302_fx_env_airwall"}
exporter.MATERIALS = {"mat_fx_25021701_airwall_" + part for part in
                      ("flow", "floorglow", "grid", "glow")}
exporter.main()
temporary = exporter.OUT / "camp_portal_materials.json"
data = json.loads(temporary.read_text())
for material in data["materials"].values():
    material["texture"] = material["texture"].replace("/environment_effects/", "/environment_effects/doors/")
    for slot in material["textures"]:
        slot["texture"] = slot["texture"].replace("/environment_effects/", "/environment_effects/doors/")
(exporter.OUT / "materials.json").write_text(json.dumps(data, indent=2) + "\n")
temporary.unlink()
