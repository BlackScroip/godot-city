"""Recover monster Animator state rates without changing the original import catalog."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

import UnityPy


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    combat = json.loads((args.project / "assets/data/combat.json").read_text())
    visuals = json.loads((args.project / "assets/catalog.json").read_text())
    assets = {Path(row["path"]).name.lower(): row for row in manifest["assets"]}
    bundle_evidence = {}
    controllers = {}
    with zipfile.ZipFile(args.apk) as archive:
        def load_bundle(index):
            member = "assets/yoo/DefaultPackage/" + manifest["bundles"][index]["hash"] + ".bundle"
            payload = archive.read(member)
            bundle_evidence[str(index)] = {"member": member, "sha256": hashlib.sha256(payload).hexdigest()}
            return UnityPy.load(payload)

        for obj in load_bundle(5514).objects:
            if obj.type.name == "AnimatorController":
                controllers[obj.path_id] = obj.read_typetree()
        enemies = {}
        for enemy in combat["enemies"]:
            asset = assets[enemy["prefab"].lower()]
            references = []
            for obj in load_bundle(asset["bundle"]).objects:
                if obj.type.name == "Animator":
                    references.append(obj.read_typetree()["m_Controller"]["m_PathID"])
            references = [ref for ref in references if ref in controllers]
            if len(set(references)) != 1:
                raise ValueError("Monster %s has ambiguous Animator references: %s" % (enemy["id"], references))
            controller = controllers[references[0]]
            names = dict(controller["m_TOS"])
            clips = {row["source_name"].lower(): row["name"] for row in visuals["enemies"][str(enemy["id"])]["animations"]}
            states = {}
            for machine in controller["m_Controller"]["m_StateMachineArray"]:
                for entry in machine["data"]["m_StateConstantArray"]:
                    state = entry["data"]
                    name = names.get(state["m_NameID"], "")
                    nodes = [node["data"] for tree in state["m_BlendTreeConstantArray"] for node in tree["data"]["m_NodeArray"]]
                    if not name or not nodes:
                        continue
                    states[name.lower()] = {
                        "source_name": name,
                        "animation": clips.get(name.lower(), ""),
                        "speed": state["m_Speed"],
                        "loop": state["m_Loop"],
                        "path_hash": state["m_FullPathID"],
                        "clip_indices": [node["m_ClipID"] for node in nodes],
                        "speed_parameter_hash": state["m_SpeedParamID"],
                    }
            enemies[str(enemy["id"])] = {
                "prefab": asset["path"],
                "prefab_bundle": asset["bundle"],
                "controller": controller["m_Name"],
                "controller_path_id": str(references[0]),
                "states": states,
            }
    result = {
        "schema": 1,
        "apk_sha256": hashlib.file_digest(args.apk.open("rb"), "sha256").hexdigest(),
        "manifest_sha256": manifest["manifest_sha256"],
        "bundles": bundle_evidence,
        "enemies": enemies,
        "limitations": [
            "Serialized AnimatorController state speed/loop values, linked from each exact prefab Animator reference; static evidence only.",
            "Speed parameter hashes are retained; live parameter values and AnimationController runtime transitions were not observed.",
            "Missing action names, including Griffin Attack2_Part2, are not guessed or added as source aliases.",
        ],
    }
    output = args.project / "assets/data/monster_presentation.json"
    output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps({"path": str(output), "monsters": len(enemies), "states": sum(len(enemy["states"]) for enemy in enemies.values()), "bundles": len(bundle_evidence)}))


if __name__ == "__main__":
    main()
