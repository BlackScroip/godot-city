"""Retain bounded token/socket/compose evidence from the specified APK native ELF."""

import argparse
import json
from pathlib import Path

import inspect_new_camp_native as native


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native", type=Path, required=True)
    parser.add_argument("--stubs", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    native.SELECTION = {}
    native.SELECTED_OFFSETS = {
        0x2D41FBC, 0x2D43954, 0x2D430B0, 0x2D418FC, 0x2D426F8,
        0x2D42F28, 0x2D41E34, 0x2D45340, 0x2F08D98, 0x2F0BA1C,
        0x2D89704, 0x2D9922C,
    }
    evidence = native.inspect(args.native, args.stubs)
    evidence["apk_sha256"] = "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505"
    evidence["scope"] = "Current-level abilities, per-character token sockets, five-copy composition, tier seeds, rerolls. Unity RNG sequence equivalence is not established."
    args.output.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"output": str(args.output), "methods": len(evidence["methods"]), "native_sha256": evidence["native_sha256"]}))


if __name__ == "__main__":
    main()
