#!/usr/bin/env python3
"""Record the selected APK's native particle velocity-limit equation."""

import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import zipfile

from capstone import Cs, CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN


ROOT = Path(__file__).resolve().parents[2]
APK_SHA = "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505"
UNITY_SHA = "714df8d408240c2decb1e940953337bf3e0ffefdc9f0f74373635c344e9b7a52"


def f32(value):
    return struct.unpack("<f", struct.pack("<f", value))[0]


def inspect(apk):
    assert hashlib.file_digest(apk.open("rb"), "sha256").hexdigest() == APK_SHA
    with zipfile.ZipFile(apk) as archive:
        native = archive.read("lib/arm64-v8a/libunity.so")
    assert hashlib.sha256(native).hexdigest() == UNITY_SHA
    program_offset = struct.unpack_from("<Q", native, 32)[0]
    entry_size, count = struct.unpack_from("<HH", native, 54)
    segments = [struct.unpack_from("<IIQQQQQQ", native, program_offset + i * entry_size)
                for i in range(count)]

    def file_offset(address):
        segment = next(s for s in segments if s[0] == 1 and s[3] <= address < s[3] + s[5])
        return segment[2] + address - segment[3]

    disassembler = Cs(CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN)
    blocks = []
    for label, start, end in (
        ("dampen_weight", 0x1044548, 0x10445C8),
        ("speed_limit_selection", 0x1044AEC, 0x1044B34),
        ("powf_plt", 0x17663D0, 0x17663E0),
    ):
        offset = file_offset(start)
        code = native[offset:offset + end - start]
        instructions = [dict(va=hex(i.address), op=i.mnemonic, args=i.op_str)
                        for i in disassembler.disasm(code, start)]
        blocks.append(dict(label=label, va=hex(start), file_offset=hex(offset),
                           length=len(code), sha256=hashlib.sha256(code).hexdigest(),
                           instructions=instructions))
    assert sum(i["op"] == "bl" and i["args"] == "#0x17663d0"
               for i in blocks[0]["instructions"]) == 4
    assert any(i["op"] == "fmov" and "#30.00000000" in i["args"]
               for i in blocks[0]["instructions"])
    section_offset = struct.unpack_from("<Q", native, 40)[0]
    entry_size, count = struct.unpack_from("<HH", native, 58)
    sections = [struct.unpack_from("<IIQQQQIIQQ", native, section_offset + i * entry_size)
                for i in range(count)]
    powf_import = None
    for section in sections:
        if section[1] != 4:
            continue
        symbols = sections[section[6]]
        strings = sections[symbols[6]]
        for offset in range(section[4], section[4] + section[5], section[9]):
            address, info, _ = struct.unpack_from("<QQq", native, offset)
            if address != 0x17DEC08:
                continue
            symbol = struct.unpack_from("<IBBHQQ", native, symbols[4] + (info >> 32) * symbols[9])
            start = strings[4] + symbol[0]
            name = native[start:native.index(b"\0", start)].decode()
            assert name == "powf"
            powf_import = dict(name=name, got_va=hex(address), relocation_file_offset=hex(offset))
    assert powf_import
    catalog = json.loads((ROOT / "goDot/assets/environment_effects/chest_catalog.json").read_text())
    layer = next(layer for layer in catalog["effects"]["24050602_fx_env_treasureboxcurseopen"]["layers"]
                 if layer["name"] == "24050602_treasureboxcurseopen_smoke")
    module = layer["modules"]["ClampVelocityModule"]
    keys = module["magnitude"]["maxCurve"]["m_Curve"]
    assert len(keys) == 2 and keys[0]["value"] == 1.0
    assert keys[0]["outSlope"] == keys[1]["inSlope"] == 0.0
    fixtures = []
    for duration in (0.6, 0.9, 1.2):
        for initial_speed in (3.0, 5.0, 7.0):
            speed, elapsed = initial_speed, 0.0
            values = [dict(time=0.0, speed=speed)]
            for index in range(1, math.ceil(duration * 60) + 1):
                current = min(index / 60.0, duration)
                phase = current / duration
                smooth = phase * phase * (3.0 - 2.0 * phase)
                limit = keys[0]["value"] + (keys[1]["value"] - keys[0]["value"]) * smooth
                weight = f32(1.0 - f32(math.pow(f32(1.0 - module["dampen"]),
                                               f32(f32(current - elapsed) * 30.0))))
                if speed > limit:
                    speed = f32(speed + f32(f32(limit - speed) * weight))
                values.append(dict(time=current, speed=speed))
                elapsed = current
            fixtures.append(dict(duration=duration, initial_speed=initial_speed, samples=values))
    return dict(apk_sha256=APK_SHA, libunity_sha256=UNITY_SHA, native_blocks=blocks,
                powf_import=powf_import, source_layer=layer["name"],
                source_initial=layer["initial"], source_module=module,
                equation="speed > limit ? speed + (limit - speed) * (1 - powf(1 - dampen, abs(dt) * 30)) : speed",
                reference_hz=60, reference_kind="numerical fixtures derived from the native equation, not runtime observations",
                fixtures=fixtures,
                limitations=["Source random seeds are not replayed; the implementation samples the original independent speed/lifetime ranges.",
                             "Speed curves use a 60 Hz reference and linear interpolation between samples.",
                             "Support is bounded to the chest smoke magnitude limit with zero drag and no external forces."])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, default=ROOT / "1061664.apk")
    parser.add_argument("--output", type=Path, default=ROOT / "goDot/reports/chest-smoke-velocity-native-20261028.json")
    args = parser.parse_args()
    result = inspect(args.apk)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(dict(output=str(args.output), blocks=len(result["native_blocks"]), fixtures=len(result["fixtures"]))))
