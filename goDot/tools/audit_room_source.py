"""Verify normalized rooms against the selected APK without executing Android."""

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import zipfile

import UnityPy
from inspect_camp_progression import manifest_records


APK_SHA = "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505"
PROJECT = Path(__file__).resolve().parents[1]


def audit(apk):
    with apk.open("rb") as stream:
        apk_identity = hashlib.file_digest(stream, "sha256").hexdigest()
    if apk_identity != APK_SHA:
        raise ValueError("Selected APK differs from the evidence identity")
    with zipfile.ZipFile(apk) as archive:
        member = next(name for name in archive.namelist() if name.startswith(
            "assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes"))
        assets, bundles = manifest_records(archive.read(member))
        record = next(asset for asset in assets if asset["address"] == "NodeData")
        bundle = "assets/yoo/DefaultPackage/" + bundles[record["bundle"]]["hash"] + ".bundle"
        raw = archive.read(bundle)
        table = next(obj.read() for obj in UnityPy.load(raw).objects
                     if obj.type.name == "TextAsset" and obj.peek_name() == "NodeData")
        nodes = json.loads(table.m_Script)
    campaign = json.loads((PROJECT / "assets/data/campaign.json").read_text())
    imported = {row["Id"]: row for row in campaign["Nodes"]}
    active = {row["Id"]: row for row in nodes if row["IsActive"]
              and row.get("GenerateRule", {}).get("NodeLevel", 0) > 0}
    failures, checks = [], 0

    def check(value, description):
        nonlocal checks
        checks += 1
        if not value:
            failures.append(description)

    check(active.keys() == imported.keys(), "Active room identity set differs")
    aliases = {
        "Region": "NodeLevel", "MinDifficulty": "ActiveDifficultyLevel_Min",
        "MaxDifficulty": "ActiveDifficultyLevel_Max", "MinDepth": "MinDepthAtLevel",
        "MaxDepth": "MaxDepthAtLevel", "MaxAppearTime": "MaxAppearTime",
        "AppearChance": "AppearChance", "Priority": "GeneratePriority",
        "CanConnect": "IsCanConnectivity",
    }
    types = {1: "Shop", 2: "Battle", 3: "Rest", 5: "Treasure", 11: "Event",
             12: "Entrance", 13: "Curse", 14: "TreasureTrial"}
    for identity, original in active.items():
        current = imported.get(identity, {})
        for key in ("Type", "Name", "IconName", "IncrementOptions"):
            check(current.get(key) == original.get(key), f"{identity}: {key}")
        for key, source in aliases.items():
            check(current.get(key) == original["GenerateRule"].get(source), f"{identity}: {key}")
        check(current.get("StageId") == original["AttributeSet"]["StageId"], f"{identity}: StageId")
        flow = "Boss" if original["IsFirstOrFinal"] == 2 else types.get(original["Type"])
        check(current.get("Flow") == flow, f"{identity}: Flow")
        check(current.get("FirstOrFinal") == original["IsFirstOrFinal"], f"{identity}: FirstOrFinal")
        scene = PROJECT / "assets/environments" / (current.get("SceneName", "") + ".glb")
        check(scene.is_file(), f"{identity}: missing scene {scene.name}")
        markers = scene.with_suffix(".markers.json")
        check(markers.is_file(), f"{identity}: missing source markers")
        for key, source in (("FightType", "FightType"), ("FightData", "FightData"),
                            ("TrialData", None)):
            if key == "TrialData" and original["Type"] != 14:
                continue
            expected = original["AttributeSet"] if source is None else original["AttributeSet"].get(source, "" if key == "FightType" else {})
            check(current.get(key) == expected, f"{identity}: {key}")
    marker_counts = Counter()
    for sidecar in (PROJECT / "assets/environments").glob("LevelMap_*.markers.json"):
        for marker in json.loads(sidecar.read_text()).get("semantic_markers", []):
            if marker.get("Type") == "EEUT_UIInteractable":
                marker_counts[json.loads(marker["DataJson"]).get("UIBtnName", "")] += 1
    return {
        "passed": not failures, "checks": checks, "failures": failures,
        "apk_sha256": apk_identity,
        "evidence_type": "APK serialized configuration; no Android execution",
        "node_member": bundle, "node_bundle_sha256": hashlib.sha256(raw).hexdigest(),
        "node_path_id": str(table.object_reader.path_id), "active_rooms": len(active),
        "flow_counts": dict(Counter(row["Flow"] for row in imported.values())),
        "scene_interactions": dict(sorted(marker_counts.items())),
        "limitations": ["Serialized room comparison does not establish runtime timing or random sequence parity."],
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = audit(args.apk)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({key: result[key] for key in ("passed", "checks", "active_rooms", "failures")}))
    raise SystemExit(0 if result["passed"] else 1)
