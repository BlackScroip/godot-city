"""Measure captured Godot monster frames and create an unmodified-frame contact sheet."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageStat


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    results = []
    failures = []
    capture_times = []
    source_files = [
        "scripts/presentation/recovered_particle.gdshader",
        "scripts/presentation/authored_effect.gd",
        "scripts/presentation/combat_presentation.gd",
        "scripts/presentation/recovered_effect_material.gd",
        "scripts/actor.gd", "scripts/world.gd", "scripts/domain/combat.gd",
        "assets/data/monster_presentation.json",
        "assets/data/monster_presentation_tuning.json",
        "assets/combat_presentation/catalog.json",
    ]
    revision = {}
    for name in source_files:
        source_path = args.project / name
        revision[name] = {"sha256": hashlib.sha256(source_path.read_bytes()).hexdigest(), "mtime": source_path.stat().st_mtime}
    latest_source = max(entry["mtime"] for entry in revision.values())

    def inspect_capture(reference):
        path = args.project / reference.removeprefix("res://")
        modified = path.stat().st_mtime
        capture_times.append(modified)
        if modified < latest_source:
            failures.append("Capture predates current presentation sources %s" % reference)
        image = Image.open(path).convert("RGB")
        width, height = image.size
        crop = image.crop((width // 5, height // 8, width * 4 // 5, height * 7 // 8))
        ground = Image.new("RGB", crop.size, image.getpixel((8, height - 8)))
        delta = ImageChops.difference(crop, ground)
        mask = delta.convert("L").point(lambda value: 255 if value > 16 else 0)
        foreground = sum(mask.histogram()[1:])
        variance = max(ImageStat.Stat(crop).var)
        if foreground < 100 or variance < 2:
            failures.append("Blank monster frame %s" % reference)
        return image, {"path": reference, "width": width, "height": height, "foreground_pixels": foreground, "channel_variance_max": round(variance, 3), "captured_at": datetime.fromtimestamp(modified, timezone.utc).isoformat()}

    for quality in ["full", "low"]:
        source = args.project / ("reports/monster-presentation-visual-%s.json" % quality)
        if not source.exists():
            failures.append("Missing %s report" % quality)
            continue
        report = json.loads(source.read_text())
        shots = report["shots"]
        sheet = Image.new("RGB", (6 * 256, math.ceil(len(shots) / 6) * 168), "#20272a")
        draw = ImageDraw.Draw(sheet)
        for index, shot in enumerate(shots):
            captures = []
            images = []
            for reference in shot["captures"]:
                image, metrics = inspect_capture(reference)
                captures.append(metrics)
                images.append(image)
            if not images:
                failures.append("No rendered captures %s %s" % (quality, shot["enemy"]))
                continue
            x, y = (index % 6) * 256, (index // 6) * 168
            sheet.paste(images[0].resize((256, 144), Image.Resampling.LANCZOS), (x, y + 24))
            draw.text((x + 6, y + 5), "%d | %s" % (shot["enemy"], shot["action"]), fill="white")
            results.append({"enemy": shot["enemy"], "quality": quality, "action": shot["action"], "captures": captures})
        sheet.save(args.project / ("reports/monster-presentation-%s-contact-sheet.png" % quality))
    complete_bosses = []
    for enemy in [23001, 52003]:
        for quality in ["full", "low"]:
            source = args.project / ("reports/monster-presentation-visual-%s-%d-complete.json" % (quality, enemy))
            report = json.loads(source.read_text())
            for shot in report["shots"]:
                captures = [inspect_capture(reference)[1] for reference in shot["captures"]]
                complete_bosses.append({"enemy": enemy, "quality": quality, "action": shot["action"], "captures": captures})
    result = {"passed": not failures, "failures": failures, "shots": results, "complete_bosses": complete_bosses, "source_revision": revision, "capture_start": datetime.fromtimestamp(min(capture_times), timezone.utc).isoformat(), "capture_end": datetime.fromtimestamp(max(capture_times), timezone.utc).isoformat(), "generated_at": datetime.now(timezone.utc).isoformat(), "scope": "Pixel checks exclude the label and compare the central scene with its ground pixel. They detect blank frames, not original-APK shader equivalence or mobile frame rate. Every capture must postdate all hashed presentation sources. Contact sheets resize actual captured frames without generating new visual content."}
    path = args.project / "reports/monster-presentation-pixel-audit.json"
    path.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"passed": result["passed"], "shots": len(results), "complete_bosses": len(complete_bosses), "failures": failures, "report": str(path)}))
    raise SystemExit(0 if not failures else 1)


if __name__ == "__main__":
    main()
