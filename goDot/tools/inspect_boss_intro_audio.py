"""Bind focused Boss UI audio evidence to the supplied APK and ARM64 library."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess


APK_SHA = "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505"
LIB_SHA = "86481018e3b55575e27d0d99a5979299b7fbbdf718698918ab5ebfbbccb68944"
METHODS = {
    "AudioContainer": ["OnEnable()", "Play_Sonity(", "OnUpdate_Sonity()", "OnDestroy()"],
    "Voice": ["SetPitchRatioUpdate("],
    "SoundContainerInternalsData": ["GetPitchBaseAndRandom()"],
}
DECLARATION = re.compile(
    r'\[Address\(RVA = "0x[0-9A-F]+", Offset = "0x([0-9A-F]+)", Length = "0x([0-9A-F]+)"\)\]'
    r'\s*(?:\[[^\n]+\]\s*)+([^\n]+)'
)


def inspect(args):
    apk_sha = hashlib.file_digest(args.apk.open("rb"), "sha256").hexdigest()
    data = args.lib.read_bytes()
    lib_sha = hashlib.sha256(data).hexdigest()
    if apk_sha != APK_SHA or lib_sha != LIB_SHA:
        raise ValueError("Inputs do not match the selected APK and extracted library")
    segments = []
    phoff = struct.unpack_from("<Q", data, 32)[0]
    size, count = struct.unpack_from("<HH", data, 54)
    for index in range(count):
        kind, _, offset, va, _, filesz, _, _ = struct.unpack_from(
            "<IIQQQQQQ", data, phoff + index * size)
        if kind == 1:
            segments.append((offset, offset + filesz, va))
    symbols, selected = {}, []
    for source in args.stubs.rglob("*.cs"):
        for offset_text, length_text, declaration in DECLARATION.findall(source.read_text()):
            offset, length = int(offset_text, 16), int(length_text, 16)
            if not length:
                continue
            va = next(base + offset - low for low, high, base in segments if low <= offset < high)
            name = source.stem + "." + declaration.strip()
            symbols.setdefault(va, name)
            if any(token in declaration for token in METHODS.get(source.stem, [])):
                selected.append((name, offset, va, length))
    methods = []
    for name, offset, va, length in selected:
        assembly = subprocess.check_output([
            "xcrun", "llvm-objdump", "--disassemble", "--start-address=" + hex(va),
            "--stop-address=" + hex(va + length), str(args.lib)], text=True)
        calls = []
        for target in re.findall(r"\s(?:bl|b)\s+(0x[0-9a-f]+)", assembly):
            calls.append({"va": target, "symbol": symbols.get(int(target, 16), "unresolved")})
        methods.append({"method": name, "file_offset": hex(offset), "va": hex(va),
                        "length": hex(length), "calls": calls, "assembly": assembly})
    catalog = json.loads(args.catalog.read_text())
    report = {
        "apk_sha256": apk_sha, "lib_sha256": lib_sha, "methods": methods,
        "audio": catalog["audio"],
        "observed": [
            "AudioContainer.Play_Sonity calls SoundEvent.Play(owner) without pitch parameters.",
            "AudioContainer.OnUpdate_Sonity polls state without applying a battle speed to pitch.",
            "SoundContainerInternalsData.GetPitchBaseAndRandom multiplies base pitch by a semitone conversion of a symmetric random range.",
            "Both selected sound containers use base pitch 1 and random range 0.25 semitones.",
            "AudioContainer has OnDestroy cleanup and no declared OnDisable handler in these recovered stubs.",
        ],
        "implementation_inference": "Play UI sounds at recovered randomized pitch independently of the 3x banner clock; allow natural audio completion, and stop voices on explicit cancellation or scene teardown.",
        "limits": "Static analysis of selected entry/update/pitch methods. No Android audio capture or exhaustive Sonity mixer analysis was performed.",
    }
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"output": str(args.output), "methods": len(methods), "apk_sha256": apk_sha}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for option in ["apk", "lib", "stubs", "catalog", "output"]:
        parser.add_argument("--" + option, type=Path, required=True)
    inspect(parser.parse_args())
