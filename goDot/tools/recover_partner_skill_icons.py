"""Recover the equipped monster partner skill icons from the supplied APK."""

import argparse
import hashlib
import json
from pathlib import Path
import zipfile

import UnityPy

from inspect_camp_progression import Reader, manifest_records


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets/ui/partner_skills"


def recover(apk):
    skills = json.loads((ROOT / "assets/data/partner_skills.json").read_text())["skills"]
    wanted = {row["icon"] for row in skills}
    environment = UnityPy.Environment()
    sources = {}
    selected = {}
    with zipfile.ZipFile(apk) as archive:
        manifest = next(name for name in archive.namelist() if name.startswith(
            "assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes"))
        payload = archive.read(manifest)
        _, bundles = manifest_records(payload)
        reader = Reader(payload)
        reader.number("I")
        reader.string()
        for _ in range(3): reader.number("B")
        for _ in range(2): reader.number("i")
        for _ in range(4): reader.string()
        for _ in range(reader.number("i")):
            address, path, _ = [reader.string() for _ in range(3)]
            reader.array(reader.string)
            bundle = reader.number("i")
            dependencies = reader.array(lambda: reader.number("i"))
            if address in wanted:
                selected[address] = {"path": path, "bundle": bundle, "dependencies": dependencies}
        missing = wanted - selected.keys()
        if missing:
            raise ValueError("Missing addressed icons: " + ", ".join(sorted(missing)))
        indices = {index for source in selected.values() for index in [source["bundle"], *source["dependencies"]]}
        for index in sorted(indices):
            member = "assets/yoo/DefaultPackage/" + bundles[index]["hash"] + ".bundle"
            payload = archive.read(member)
            loaded = environment.load_file(payload)
            for cab in loaded.files.values():
                if hasattr(cab, "objects"):
                    sources[cab.name] = {"member": member, "sha256": hashlib.sha256(payload).hexdigest()}
    OUTPUT.mkdir(parents=True, exist_ok=True)
    extracted = {}
    for obj in environment.objects:
        if obj.type.name != "Sprite" or obj.peek_name() not in wanted:
            continue
        sprite = obj.read()
        path = OUTPUT / (sprite.m_Name + ".png")
        image = sprite.image
        image.save(path)
        extracted[sprite.m_Name] = {"source": sources[obj.assets_file.name], "path_id": str(obj.path_id),
                                    "asset_path": selected[sprite.m_Name]["path"],
                                    "path": "res://" + str(path.relative_to(ROOT)),
                                    "width": image.width, "height": image.height,
                                    "png_sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
    if wanted - extracted.keys():
        raise ValueError("Unresolved sprites: " + ", ".join(sorted(wanted - extracted.keys())))
    report = {"apk": str(apk.resolve()), "apk_sha256": hashlib.file_digest(apk.open("rb"), "sha256").hexdigest(),
              "manifest": manifest, "sprites": extracted,
              "limit": "Static serialized sprite evidence; no APK process executed."}
    (OUTPUT / "provenance.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"icons": len(extracted), "output": str(OUTPUT)}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    recover(parser.parse_args().apk)
