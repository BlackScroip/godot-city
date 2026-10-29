"""Repair atlas bleed in the symmetric source white-button sprite."""

import hashlib
from pathlib import Path

from PIL import Image

SOURCE_SHA256 = {
    "d557dbc1e6c5ad718194dd315e1d878c464f3becac81c087d2c3892985f4dacf",
    "922f2e030787fe0f57a6bc7fc0e2c004e7ee01e727575dbda78701f48de1b2f1",
}
SPRITE_NAME = "几何ui-椭圆白色按钮"


def repair(image: Image.Image) -> Image.Image:
    if image.size not in {(250, 75), (284, 84)}:
        raise ValueError(f"Unexpected white-button dimensions: {image.size}")
    image = image.convert("RGBA")
    width, height = image.size
    right = image.crop((width // 2, 0, width, height))
    image.paste(right.transpose(Image.Transpose.FLIP_LEFT_RIGHT), (0, 0))
    return image


def main() -> None:
    assets = Path(__file__).resolve().parents[1] / "assets"
    count = 0
    for path in assets.rglob("*.png"):
        if hashlib.sha256(path.read_bytes()).hexdigest() not in SOURCE_SHA256:
            continue
        with Image.open(path) as source:
            fixed = repair(source)
        fixed.save(path)
        print(path.relative_to(assets))
        count += 1
    print(f"Repaired {count} copies")


if __name__ == "__main__":
    main()
