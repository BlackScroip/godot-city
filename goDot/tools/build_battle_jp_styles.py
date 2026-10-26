"""Build compact JP art metadata from recovered Unity prefab evidence."""

import argparse
import json
from pathlib import Path


def art_style(image):
    rect = image["rect"]
    dimensions = rect["m_SizeDelta"]
    scale = rect["m_LocalScale"]
    return {
        "resource": image["resource"],
        "size": [round(dimensions[axis] * scale[axis], 6) for axis in ("x", "y")],
        "color": [round(image["color"][channel], 8) for channel in ("r", "g", "b", "a")],
    }


def build(reports):
    styles = {}
    for path in reports:
        report = json.loads(path.read_text())
        prefab = report["prefab"]["address"]
        buff_id = prefab.removeprefix("SpecialStateBar_Buff_")
        assert buff_id.isdigit(), prefab
        controller = next(item for item in report["controllers"] if item["script"] == "SpecialStateBar_Buff")
        slots = sum(bool(item["m_PathID"]) for item in controller["fields"]["mSlotPrefabList"])
        images = report["images"]
        style = {"slots": slots}
        for key, suffix in (("empty", "/Image_InActive"), ("full", "/Image_Active")):
            variants = [art_style(image) for image in images if "/Container_Layout/" in image["path"] and image["path"].endswith(suffix)]
            assert variants and all(variant == variants[0] for variant in variants), (prefab, key)
            style[key] = variants[0]
        style["line"] = art_style(next(image for image in images if image["path"] == prefab + "/Image_Bg_Line"))
        markers = [image for image in images if "/Image_Bg_Line/" in image["path"]]
        style["marker"] = {}
        if markers:
            marker = art_style(markers[0])
            assert all(art_style(image) == marker for image in markers), prefab
            marker["positions"] = sorted([[round(image["rect"]["m_AnchoredPosition"][axis], 6) for axis in ("x", "y")] for image in markers])
            style["marker"] = marker
        styles[buff_id] = style
    return dict(sorted(styles.items()))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reports", nargs="+", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    styles = build(args.reports)
    args.output.write_text(json.dumps(styles, ensure_ascii=False, separators=(",", ":")) + "\n")
    print(json.dumps({"output": str(args.output), "slots": {key: style["slots"] for key, style in styles.items()}}))
