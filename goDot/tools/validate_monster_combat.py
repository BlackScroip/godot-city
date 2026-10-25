#!/usr/bin/env python3
"""Run source monster integration checks and focused combat regressions."""

import argparse
import json
from pathlib import Path
import subprocess
import time


ROOT = Path(__file__).resolve().parents[1]
TESTS = [
    "enemy_ai", "monster_spawn", "monster_spawn_world", "monster_combat",
    "monster_presentation", "monster_skill", "monster_world", "campaign", "save_recovery", "combat", "projectile",
    "attack_motion", "impact_feedback", "heavy_attack", "heavy_presentation",
    "animation_motion", "runtime", "feel", "world_interactions",
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="/Applications/Godot.app/Contents/MacOS/Godot")
    parser.add_argument("--tests", nargs="+", choices=TESTS, default=TESTS)
    args = parser.parse_args()
    rows = []
    for name in args.tests:
        log = ROOT / "reports" / f"monster-regression-{name}.log"
        started = time.monotonic()
        try:
            result = subprocess.run(
                [args.godot, "--headless", "--fixed-fps", "60", "--path", str(ROOT),
                 "--log-file", str(log.with_suffix(".engine.log")),
                 "--script", f"res://tests/{name}_test.gd"],
                capture_output=True, text=True, timeout=240,
            )
            output = result.stdout + result.stderr
            exit_code = result.returncode
        except subprocess.TimeoutExpired as error:
            stdout = error.stdout or b""
            stderr = error.stderr or b""
            output = stdout.decode(errors="replace") + stderr.decode(errors="replace")
            output += "\nTEST TIMEOUT after 240 seconds\n"
            exit_code = -1
        log.write_text(output)
        passed = exit_code == 0 and not any(marker in output for marker in ["SCRIPT ERROR:", "SHADER ERROR:"])
        rows.append({"test": name, "passed": passed, "exit_code": exit_code,
                     "seconds": round(time.monotonic() - started, 3), "log": str(log)})
        print(f"{name}: {'passed' if passed else 'FAILED'}", flush=True)
    report = {"passed": all(row["passed"] for row in rows), "tests": rows,
              "scope": "Headless source and integration regressions. GPU captures and device acceptance are separate."}
    (ROOT / "reports" / "monster-regressions.json").write_text(json.dumps(report, indent=2) + "\n")
    raise SystemExit(0 if report["passed"] else 1)


if __name__ == "__main__":
    main()
