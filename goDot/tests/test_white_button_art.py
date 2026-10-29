import sys
import unittest
from pathlib import Path

from PIL import Image

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT / "tools"))
from repair_white_button_art import repair


class WhiteButtonArtTest(unittest.TestCase):
    def test_all_source_copies_have_clean_symmetric_edges(self):
        ui = PROJECT / "assets" / "ui"
        paths = list(ui.rglob("*39ebe9c97d*.png"))
        paths += [ui / "camp/construction/65b90a2ce6b4d078.png",
                  ui / "camp/developer/__ui-______.png",
                  ui / "startup/b7edf5bd5ebd76a7.png"]
        self.assertEqual(len(paths), 21)
        for path in paths:
            with self.subTest(path=path), Image.open(path) as image:
                rgba = image.convert("RGBA")
                width, height = rgba.size
                left = rgba.crop((0, 0, width // 2, height))
                right = rgba.crop((width // 2, 0, width, height))
                self.assertEqual(left.tobytes(), right.transpose(Image.Transpose.FLIP_LEFT_RIGHT).tobytes())
                self.assertEqual(rgba.getpixel((0, 0))[3], 0)
                self.assertGreater(rgba.getpixel((width // 2, height // 2))[0], 240)

    def test_recovery_preserves_source_right_half(self):
        source = Image.new("RGBA", (250, 75), (10, 20, 30, 255))
        source.paste((255, 255, 255, 255), (125, 0, 250, 75))
        repaired = repair(source)
        self.assertEqual(repaired.getpixel((0, 0)), (255, 255, 255, 255))
        self.assertEqual(repaired.crop((125, 0, 250, 75)).tobytes(), source.crop((125, 0, 250, 75)).tobytes())


if __name__ == "__main__":
    unittest.main()
