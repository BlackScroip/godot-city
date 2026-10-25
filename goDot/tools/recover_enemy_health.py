"""Recover the exact enemy numerical table from the supplied reference APK.

Requires UnityPy. Usage: python3 tools/recover_enemy_health.py /path/to/reference.apk
"""
import argparse
import hashlib
import zipfile
from pathlib import Path

import UnityPy

APK_HASH = "8b6b62e21360f8170fc70d86279e88ab04c7c9c6d0d91f659e76a48bdbdb4ea3"
MEMBER = "assets/yoo/DefaultPackage/f9245ea11c0a88ee49d98bf76b0e1d67.bundle"
CONTENT_HASH = "1d26e9fed0145bb94ae99e8614385fc396d727746028d36fcffbbda360832231"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path)
    args = parser.parse_args()
    if hashlib.sha256(args.apk.read_bytes()).hexdigest() != APK_HASH:
        raise SystemExit("APK differs from the analyzed reference; resolve its manifest first")
    with zipfile.ZipFile(args.apk) as archive:
        bundle = archive.read(MEMBER)
    for obj in UnityPy.load(bundle).objects:
        if obj.type.name != "TextAsset":
            continue
        asset = obj.read()
        if asset.m_Name != "EnemyNumericalConfigData":
            continue
        text = asset.m_Script
        if isinstance(text, bytes):
            text = text.decode("utf-8-sig")
        if hashlib.sha256(text.encode()).hexdigest() != CONTENT_HASH:
            raise SystemExit("Recovered TextAsset content differs from the recorded source")
        output = Path(__file__).resolve().parents[1] / "assets/data/EnemyNumericalConfigData.json"
        output.write_text(text)
        print(output)
        return
    raise SystemExit("EnemyNumericalConfigData TextAsset missing")


if __name__ == "__main__":
    main()
