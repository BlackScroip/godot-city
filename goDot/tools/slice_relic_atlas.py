"""Slice generated inventory sheets and retain per-item source coordinates."""
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "assets/art_generated/relics"


def runs(values):
    groups = []
    for value in values:
        if not groups or value > groups[-1][-1] + 1:
            groups.append([])
        groups[-1].append(value)
    return groups


def detect(source):
    image = Image.open(source).convert("RGB")
    width, height = image.size
    pixels = image.load()
    xs = [x for x in range(width) if sum(min(pixels[x, y]) > 190 for y in range(20, height - 60)) / (height - 80) > 0.7]
    ys = [y for y in range(height) if sum(min(pixels[x, y]) > 190 for x in range(width)) / width > 0.85]
    columns = [round(sum(group) / len(group)) for group in runs(xs)]
    rows = [group[0] if len(group) > 10 else round(sum(group) / len(group)) for group in runs(ys)]
    return image, columns, rows


def audit(source):
    image, xs, ys = detect(source)
    cells = []
    for row, (top, bottom) in enumerate(zip(ys, ys[1:])):
        for column, (left, right) in enumerate(zip(xs, xs[1:])):
            cells.append({"row": row + 1, "column": column + 1, "rect": [left + 2, top + 2, right - 2, bottom - 2]})
    (ART / f"{source.stem}-grid.json").write_text(json.dumps({"source": source.name, "columns": len(xs) - 1, "rows": len(ys) - 1, "cells": cells}, indent=2) + "\n")
    for page in range(3):
        preview = Image.new("RGB", (1000, (len(ys) - 1) * 120), "#e9eceb")
        draw = ImageDraw.Draw(preview)
        for cell in cells:
            column, row = cell["column"] - 1, cell["row"] - 1
            if column // 10 != page:
                continue
            tile = image.crop(tuple(cell["rect"]))
            tile.thumbnail((94, 94), Image.Resampling.LANCZOS)
            point = ((column % 10) * 100 + (100 - tile.width) // 2, row * 120 + 20)
            preview.paste(tile, point)
            draw.text(((column % 10) * 100 + 5, row * 120 + 3), f"{row+1}:{column+1}", fill="#111111")
        preview.save(ART / f"audit-{page+1}.png")
    print(json.dumps({"source": source.name, "columns": len(xs)-1, "rows": len(ys)-1, "cells": len(cells)}))


def install():
    manifest = json.loads((ART / "manifest.json").read_text())
    assignments = json.loads((ART / "source-assignments.json").read_text())
    missing = json.loads((ART / "missing-items.json").read_text())
    supplement = ART / "relic-atlas-supplement.png"
    _, sx, sy = detect(supplement)
    if len(sx) != 11 or len(sy) != 7:
        raise ValueError(f"Supplement must be audited as 10x6, got {len(sx)-1}x{len(sy)-1}")
    for index, item in enumerate(missing):
        assignments[str(item["id"])] = {"source": supplement.name, "row": index // 10 + 1, "column": index % 10 + 1}
    if len(assignments) != len(manifest["items"]):
        raise ValueError("Unmapped relics remain")
    sources = {entry["source"]: detect(ART / entry["source"]) for entry in assignments.values()}
    hashes = set()
    atlas = Image.new("RGBA", (27 * 128, 9 * 128), (0, 0, 0, 0))
    preview = Image.new("RGB", (18 * 100, 14 * 125), "#e9eceb")
    labels = ImageDraw.Draw(preview)
    for index, item in enumerate(manifest["items"]):
        source = assignments[str(item["id"])]
        image, xs, ys = sources[source["source"]]
        column, row = source["column"] - 1, source["row"] - 1
        inset_x = max(7, round((xs[column+1] - xs[column]) * 0.12))
        inset_y = max(7, round((ys[row+1] - ys[row]) * 0.12))
        rect = (xs[column] + inset_x, ys[row] + inset_y, xs[column+1] - inset_x, ys[row+1] - inset_y)
        subject = image.crop(rect).convert("RGBA")
        scale = min(112 / subject.width, 112 / subject.height)
        background = subject.getpixel((0, 0))
        subject = subject.resize((round(subject.width * scale), round(subject.height * scale)), Image.Resampling.LANCZOS)
        tile = Image.new("RGBA", (128, 128), background)
        tile.alpha_composite(subject, ((128-subject.width)//2, (128-subject.height)//2))
        frame = ImageDraw.Draw(tile)
        frame.rounded_rectangle((1, 1, 126, 126), radius=6, outline=item["hex"], width=3)
        target = ART / f"relic_{item['id']}.png"
        tile.save(target)
        digest = hashlib.sha256(target.read_bytes()).hexdigest()
        if digest in hashes:
            raise ValueError(f"Duplicate image: {item['name']}")
        hashes.add(digest)
        item["source"] = {**source, "rect": list(rect)}
        item["sha256"] = digest
        item["cell"] = {"column": index % 27, "row": index // 27}
        atlas.alpha_composite(tile, ((index % 27)*128, (index // 27)*128))
        small = tile.resize((88, 88), Image.Resampling.LANCZOS).convert("RGB")
        point = ((index % 18)*100 + 6, (index // 18)*125 + 28)
        preview.paste(small, point)
        labels.text(((index % 18)*100 + 6, (index // 18)*125 + 5), f"{item['id']}  {item['rarity']}*", fill="#111111")
    atlas.save(ART / "relic-atlas.png")
    preview.save(ROOT / "reports/relic-art-contact-sheet.png")
    manifest["sheet"].update({"source": "relic-atlas.png", "width": 3456, "height": 1152, "cell_size": 128})
    manifest["generator"] = "built-in imagegen spritesheets; audited semantic slicing and deterministic rarity frames"
    manifest["installed"] = True
    (ART / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    (ART / "source-assignments.json").write_text(json.dumps(assignments, indent=2) + "\n")
    print(json.dumps({"installed": len(hashes), "atlas": str(ART / "relic-atlas.png"), "size": [3456,1152]}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--audit", type=Path)
    parser.add_argument("--install", action="store_true")
    args = parser.parse_args()
    if args.audit:
        audit(args.audit)
    elif args.install:
        install()
