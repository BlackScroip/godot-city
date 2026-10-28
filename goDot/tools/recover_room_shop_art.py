"""Recover the supplied APK's merchant panel sprites and layout."""

from pathlib import Path
import json
import shutil
import tempfile

from recover_camp_developer_ui import recover


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[2]
    with tempfile.TemporaryDirectory(prefix="city-room-shop-") as temporary:
        staged = Path(temporary)
        recover(root / "1061664.apk", staged, "ATPanel_Shop", "room_shop")
        source = staged / "room_shop"
        layout = json.loads((source / "prefab-layout.json").read_text())
        mapping = {}
        for sprite in layout["sprites"]:
            sprite["path"] = "res://assets/ui/room_shop/" + Path(sprite["path"]).name
            mapping[sprite["name"]] = sprite["path"]
        (source / "prefab-layout.json").write_text(json.dumps(layout, ensure_ascii=False, indent=2) + "\n")
        (source / "resource_map.json").write_text(json.dumps(mapping, ensure_ascii=False, indent=2) + "\n")
        shutil.copytree(source, root / "goDot/assets/ui/room_shop", dirs_exist_ok=True)
