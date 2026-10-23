#!/usr/bin/env python3
"""Audit recovered FX anchors against the exported particle catalog."""
import collections
import json
import pathlib
import struct


def main():
    project = pathlib.Path(__file__).resolve().parents[1]
    catalog = json.loads((project / "assets/environment_effects/catalog.json").read_text())
    addresses = sorted(catalog["effects"], key=len, reverse=True)
    counts = collections.Counter()
    unmatched = collections.Counter()
    scenes = []
    for path in sorted((project / "assets/environments").glob("*.glb")):
        with path.open("rb") as stream:
            assert stream.read(4) == b"glTF"
            stream.read(8)
            size, kind = struct.unpack("<II", stream.read(8))
            assert kind == 0x4E4F534A
            document = json.loads(stream.read(size))
        bindings = []
        for node in document.get("nodes", []):
            name = node.get("name", "").lower()
            if "_fx_" not in name or name.startswith("audio_"):
                continue
            address = next((key for key in addresses if name == key or name.startswith(key + "_")), None)
            if address:
                counts[address] += 1
                bindings.append({"node": node["name"], "effect": address,
                                 "source_active": node.get("extras", {}).get("unityActive", True)})
            else:
                unmatched[name] += 1
        scenes.append({"scene": path.stem, "bindings": bindings})
    missing_media = []
    for address, effect in catalog["effects"].items():
        for layer in effect.get("layers", []):
            paths = [layer.get("mesh", "")] + [m.get("texture", "") for m in layer.get("materials", [])]
            for resource in paths:
                if resource and not (project / resource.removeprefix("res://")).exists():
                    missing_media.append({"effect": address, "resource": resource})
    report = {"apk_sha256": catalog["apk_sha256"], "scene_count": len(scenes),
              "catalog_effects": len(addresses), "matched_anchors": sum(counts.values()),
              "used_effect_types": len(counts), "bindings_by_effect": dict(counts),
              "unmatched": dict(unmatched), "missing_media": missing_media, "scenes": scenes,
              "scope": "Static GLB anchor/media coverage, not runtime activation or visual equivalence."}
    (project / "reports/environment-effects-coverage.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({key: value for key, value in report.items() if key not in ["scenes", "bindings_by_effect"]}, indent=2))
    return 1 if missing_media or unmatched else 0


if __name__ == "__main__":
    raise SystemExit(main())
