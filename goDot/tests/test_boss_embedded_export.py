import json
from pathlib import Path
import unittest


PROJECT = Path(__file__).resolve().parents[1]
ASSETS = PROJECT / "assets/combat_presentation/boss_embedded"
APK_SHA = "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505"


class BossEmbeddedExportTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog = json.loads((ASSETS / "catalog.json").read_text())
        cls.materials = json.loads((ASSETS / "materials.json").read_text())
        cls.audit = json.loads((ASSETS / "prefab-audit.json").read_text())

    def test_boss_inventory_is_scoped_to_exact_prefab_bundles(self):
        self.assertEqual(self.audit["apk_sha256"], APK_SHA)
        rows = {row["id"]: row for row in self.audit["bosses"]}
        self.assertEqual(len(rows), 10)
        self.assertEqual(sum(row["status"] == "inspected" for row in rows.values()), 9)
        self.assertEqual((rows[13001]["particle_systems"], rows[13001]["trail_renderers"]), (5, 0))
        self.assertEqual((rows[52003]["particle_systems"], rows[52003]["trail_renderers"]), (8, 0))
        self.assertEqual((rows[53001]["particle_systems"], rows[53001]["trail_renderers"]), (63, 6))
        self.assertEqual(rows[33002]["status"], "unavailable_or_ambiguous")
        self.assertFalse(rows[33002]["candidate_from_imported_actor"])

    def test_trails_keep_source_parameters_material_and_textures(self):
        self.assertEqual(self.catalog["apk_sha256"], APK_SHA)
        seen = set()
        trail_roots = []
        for key in self.catalog["actors"]["53001"]:
            effect = self.catalog["effects"][key]
            binding = self.catalog["bindings"][key]
            for trail in effect["trails"]:
                trail_roots.append(binding)
                self.assertTrue(trail["active"] and trail["enabled"] and trail["emitting"])
                self.assertFalse(trail["source_default_active"])
                self.assertEqual(len(trail["transform_chain"]), 3)
                self.assertAlmostEqual(trail["duration"], 0.2)
                self.assertAlmostEqual(trail["min_vertex_distance"], 0.25)
                self.assertAlmostEqual(trail["width_multiplier"], 1.5)
                self.assertEqual(len(trail["width_curve"]["m_Curve"]), 2)
                self.assertEqual(trail["color_gradient"]["m_NumAlphaKeys"], 4)
                self.assertNotIn(trail["source_file_id"], seen)
                seen.add(trail["source_file_id"])
                self.assertEqual(len(trail["materials"]), 1)
                material = self.materials[trail["materials"][0]["reference"]]
                self.assertEqual(material["name"], "mat_fx_24122501_trail_trail")
                self.assertEqual({item["property"] for item in material["textures"]}, {"_FadeTex", "_MainTex"})
                for item in material["textures"]:
                    self.assertIn(item["texture"], effect["textures"])
                    self.assertTrue((PROJECT / item["texture"].removeprefix("res://")).is_file())
        self.assertEqual(len(seen), 6)
        self.assertEqual({binding["bone"] for binding in trail_roots}, {
            "Bone L Wing_1 05", "Bone L Wing_2 02", "Bone L Wing_3 02",
            "Bone R Wing_1 05", "Bone R Wing_2 02", "Bone R Wing_3 02",
        })

    def test_each_root_preloads_all_of_its_material_textures(self):
        for key, effect in self.catalog["effects"].items():
            for layer in effect["layers"] + effect["trails"]:
                for reference in layer["materials"]:
                    self.assertIn(reference["reference"], self.materials, key)
                    material = self.materials[reference["reference"]]
                    for item in material["textures"]:
                        self.assertIn(item["texture"], effect["textures"], key)
                        self.assertTrue((PROJECT / item["texture"].removeprefix("res://")).is_file(), key)


if __name__ == "__main__":
    unittest.main()
