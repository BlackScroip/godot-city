"""Import the supplied APK's bounty table and bounded native provenance."""

import argparse
import hashlib
import json
from pathlib import Path

import compare_camp_apks
import inspect_new_camp_native


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--native", type=Path, required=True)
    parser.add_argument("--stubs", type=Path, required=True)
    parser.add_argument("--project", type=Path, required=True)
    args = parser.parse_args()
    compare_camp_apks.TABLES = {"ExtraChallengeData"}
    evidence = compare_camp_apks.extract(args.apk)
    if evidence["sha256"] != "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505":
        raise ValueError("Expected the audited 1061664.apk")
    table = evidence["tables"]["ExtraChallengeData"]
    if len(table["data"]) != 56:
        raise ValueError("Unexpected bounty row count")
    inspect_new_camp_native.SELECTION = {
        "GameDataModel_AT": ["GetNewExtraChallengeDic", "DeleteCurExtraChallengeDic", "DecreaseDeletedPenalty", "GetExtraChallengeReward", "Msg_ExtraChallengeState"],
        "ExtraChallengeData": ["get_CurProgress", "get_MaxProgress", "get_IsComplete"],
        "ATGameManager": ["get_ExtraChallengeCount"],
        "ATPanel_ExtraChallenge": ["RegisterItem", "DoGetDelegation"],
    }
    inspect_new_camp_native.SELECTED_OFFSETS = set()
    native = inspect_new_camp_native.inspect(args.native, args.stubs)
    if native["native_sha256"] != "86481018e3b55575e27d0d99a5979299b7fbbdf718698918ab5ebfbbccb68944":
        raise ValueError("Native binary does not match the audited APK")
    payload = json.dumps(table["data"], ensure_ascii=False, separators=(",", ":")) + "\n"
    (args.project / "assets/data/ExtraChallengeData.json").write_text(payload)
    manifest_path = args.project / "assets/data/manifest.json"
    manifest = json.loads(manifest_path.read_text())
    manifest["tables"]["ExtraChallengeData"] = {
        "rows": 56, "sha256": hashlib.sha256(payload.encode()).hexdigest(),
        "source": "APK 1061664: complete independent bounty table",
        "apk_sha256": evidence["sha256"],
        "evidence": {"report": "reports/extra-challenges-apk-evidence.json"},
    }
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, separators=(",", ":")) + "\n")
    evidence["native"] = native
    (args.project / "reports/extra-challenges-apk-evidence.json").write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"rows": 56, "native_methods": len(native["methods"]), "apk_sha256": evidence["sha256"]}))


if __name__ == "__main__":
    main()
