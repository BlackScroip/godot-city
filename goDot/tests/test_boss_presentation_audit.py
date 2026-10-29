#!/usr/bin/env python3
"""Regression tests for the offline Boss presentation inventory."""

import ast
import hashlib
import io
import re
import struct
import sys
import unittest
from pathlib import Path
import zipfile


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import audit_boss_presentation as audit


def layer(name="burst", cycles=1, active=True):
    return {"name": name, "active": active, "renderer": {"enabled": True, "render_mode": 0},
        "materials": [{"reference": "material"}], "emission": {"enabled": True,
            "rateOverTime": {"scalar": 0}, "m_Bursts": [{"countCurve": {"scalar": 3}, "cycleCount": cycles}]},
        "initial": {"maxNumParticles": 4, "startLifetime": {"scalar": 1}}}


class BossPresentationAuditTest(unittest.TestCase):
    def test_scanner_fields_match_existing_coverage(self):
        tree = ast.parse((ROOT / "tools/audit_skill_presentation.py").read_text())
        constants = {node.targets[0].id: ast.literal_eval(node.value) for node in tree.body
            if isinstance(node, ast.Assign) and len(node.targets) == 1
            and isinstance(node.targets[0], ast.Name) and node.targets[0].id in ("VISUAL_FIELDS", "PLACEHOLDERS")}
        self.assertEqual(audit.VISUAL_FIELDS, constants["VISUAL_FIELDS"])
        self.assertEqual(audit.PLACEHOLDERS, constants["PLACEHOLDERS"])

    def test_disabled_actions_and_recursive_dependencies(self):
        action = {"events": [
            {"enabled": False, "raw": '{"EffectName":"disabled.prefab"}'},
            {"raw": '{"EffectName":"direct.prefab","BuffTriggerId":"1"}',
             "conditions": [{"raw": '{"CheckEnemyBuffId":"missing"}'}]},
        ], "hits": []}
        indexes = {"buff": {"1": {"raw_data": {"EffectName": "buff.prefab", "AddSummonUnitId": "2"}}},
            "summon": {"2": {"raw_data": {"EffectName": "summon.prefab", "BuffTriggerId": "1"}}},
            "damage": {}}
        result = audit.trace(audit.enabled_action_values(action), indexes)
        self.assertEqual(set(result["resources"]), {"direct", "buff", "summon"})
        self.assertEqual(result["dependencies"]["buff"], ["1", "missing"])
        self.assertEqual(result["missing_dependencies"]["buff"], ["missing"])
        self.assertEqual(result["dependencies"]["summon"], ["2"])

    def test_particle_budget_counts_cycles_and_excludes_disabled_layers(self):
        effect = {"layers": [layer("a", 6), layer("b", 6), layer("c", 6),
            layer("d", 6), layer("inactive", 6, False),
            {**layer("renderer_disabled", 6), "renderer": {"enabled": False}},
            {**layer("no_material", 6), "materials": [{"reference": "missing"}]},
            {**layer("no_mesh", 6), "renderer": {"enabled": True, "render_mode": 4}, "mesh": ""}]}
        full = audit.budget_profile(effect, {"material": {"name": "x"}})
        self.assertEqual(full["eligible_layers"], 4)
        self.assertEqual(full["requested_emitters"], 24)
        self.assertEqual(full["requested_particle_slots"], 72)
        self.assertEqual(full["emitting_layers"], 4)
        self.assertTrue(full["emitting_layers_fit_budgets"])
        self.assertTrue(full["emitter_limit_exceeded"])
        self.assertFalse(full["particle_limit_exceeded_without_emitter_cap"])

    def test_budget_overrides_match_godot_effect_configuration(self):
        source = (ROOT / "scripts/presentation/authored_effect.gd").read_text()
        burst_match = re.search(r"const BOSS_BURST_LAYERS := (\{.*?^\})", source, re.MULTILINE | re.DOTALL)
        override_match = re.search(r"const BOSS_LOW_EMITTER_OVERRIDES := (\{[^\n]*\})", source)
        self.assertIsNotNone(burst_match)
        self.assertIsNotNone(override_match)
        self.assertEqual(audit.BOSS_BURST_EFFECTS, set(ast.literal_eval(burst_match.group(1))))
        self.assertEqual(audit.BOSS_LOW_EMITTER_OVERRIDES, ast.literal_eval(override_match.group(1)))
        self.assertRegex(source, r"BOSS_LOW_EMITTER_OVERRIDES\.get\(source_name,\s*12\)\)\s*if low_quality else 28")
        self.assertRegex(source, r"return 8 if low_quality else 18")
        self.assertRegex(source, r"clampi\(int\(burst\.get\(\"cycleCount\",\s*1\)\),\s*1,\s*10 if boss_burst_effect else 6\)")

    def test_boss_burst_cap_and_quality_budgets(self):
        library = {"material": {"name": "x"}}
        for name in audit.BOSS_BURST_EFFECTS:
            with self.subTest(effect=name):
                # Godot normalizes the prefab basename before selecting its budget.
                effect = {"source": "Assets/FX/" + name.upper() + ".prefab", "layers": [layer(cycles=99)]}
                full = audit.budget_profile(effect, library)
                low = audit.budget_profile(effect, library, True)
                self.assertEqual(full["requested_emitters"], 10)
                self.assertEqual(low["requested_emitters"], 10)
                self.assertEqual(full["requested_particle_slots"], 30)
                self.assertEqual(full["emitter_budget"], 28)
                self.assertEqual(low["emitter_budget"], audit.BOSS_LOW_EMITTER_OVERRIDES.get(name, 12))
                self.assertEqual((full["particle_budget"], low["particle_budget"]), (384, 144))
        generic = {"source": "Assets/FX/ordinary.prefab", "layers": [layer(cycles=99)]}
        self.assertEqual(audit.budget_profile(generic, library)["requested_emitters"], 6)
        self.assertEqual(audit.budget_profile(generic, library)["emitter_budget"], 18)
        self.assertEqual(audit.budget_profile(generic, library, True)["emitter_budget"], 8)

    def test_boss_budget_thresholds_include_flower_low_override(self):
        library = {"material": {"name": "x"}}
        flower = "26071801_fx_enemy_mojiehua_attack3_duyejidang"
        dragon = "24120601_fx_enemy_feimolong_bullet_lighting_thunderwarning"
        layers = [layer(str(index)) for index in range(15)]
        for name, expected_budget, exceeded, layers_fit in [
            (flower, 15, False, True), (dragon, 12, True, False),
        ]:
            with self.subTest(effect=name, quality="low"):
                profile = audit.budget_profile({"source": name + ".prefab", "layers": layers}, library, True)
                self.assertEqual(profile["requested_emitters"], 15)
                self.assertEqual(profile["emitter_budget"], expected_budget)
                self.assertEqual(profile["emitter_limit_exceeded"], exceeded)
                self.assertEqual(profile["emitting_layers_fit_budgets"], layers_fit)
        for last_cycles, exceeded in [(8, False), (9, True)]:
            with self.subTest(last_cycles=last_cycles, quality="full"):
                effect = {"source": dragon + ".prefab", "layers": [layer(cycles=10), layer(cycles=10), layer(cycles=last_cycles)]}
                profile = audit.budget_profile(effect, library)
                self.assertEqual(profile["requested_emitters"], 20 + last_cycles)
                self.assertEqual(profile["emitter_budget"], 28)
                self.assertEqual(profile["emitter_limit_exceeded"], exceeded)

    def test_zero_probability_and_separate_particle_budget(self):
        single = layer(cycles=100)
        single["emission"]["m_Bursts"][0]["probability"] = 0
        high_rate = {**layer(), "emission": {"enabled": True, "rateOverTime": {"scalar": 100}, "m_Bursts": []},
            "initial": {"maxNumParticles": 100, "startLifetime": {"scalar": 1}}}
        profile = audit.budget_profile({"layers": [single] + [high_rate] * 5}, {"material": {"name": "x"}})
        self.assertEqual(profile["requested_emitters"], 5)
        self.assertEqual(profile["requested_particle_slots"], 480)
        self.assertTrue(profile["particle_limit_exceeded_without_emitter_cap"])

    def test_manifest_parser_and_exact_apk_resource_classification(self):
        def number(fmt, value):
            return struct.pack("<" + fmt, value)

        def string(value):
            raw = value.encode("utf-8")
            return number("H", len(raw)) + raw

        empty_array = number("H", 0)
        asset = string("effect") + string("Assets/FX/effect.prefab") + string("guid") + empty_array + number("i", 0) + empty_array
        bundle = string("fx.bundle") + number("I", 0) + string("bundlehash") + string("") + number("q", 0) + number("B", 0) + empty_array + empty_array
        header = number("I", 1) + string("version") + bytes(3) + number("i", 0) * 2 + string("") * 4
        payload = header + number("i", 1) + asset + number("i", 1) + bundle
        assets, bundles = audit.manifest_records(payload)
        self.assertEqual(assets[0]["address"], "effect")
        self.assertEqual(bundles[0]["hash"], "bundlehash")
        with self.assertRaises(ValueError):
            audit.manifest_records(payload + b"x")
        data = io.BytesIO()
        with zipfile.ZipFile(data, "w") as archive:
            archive.writestr("assets/yoo/DefaultPackage/bundlehash.bundle", b"original bundle")
        with zipfile.ZipFile(data) as archive:
            source_hash = hashlib.sha256(b"original bundle").hexdigest()
            media = {"effects": {"effect": {"layers": [{}], "source_sha256": source_hash},
                "not_in_apk": {"layers": [{}], "source_sha256": source_hash}}}
            lookup = audit.ApkResources(archive, assets, bundles, media, {})
            self.assertEqual(lookup.get("effect")["status"], "authored_particles")
            self.assertEqual(lookup.get("effect")["source_bundle_sha256"], source_hash)
            self.assertEqual(lookup.get("not_in_apk")["status"], "exact_resource_absent")
            self.assertEqual(lookup.get("effect")["source_bundle_sha256"], lookup.hashes[0])
            self.assertEqual(len(lookup.hashes), 1)
            source = {"bundle": "assets/yoo/DefaultPackage/bundlehash.bundle", "bundle_sha256": source_hash}
            self.assertTrue(lookup.source_bundle_matches(source))
            self.assertFalse(lookup.source_bundle_matches({**source, "bundle_sha256": "wrong"}))
            self.assertIsNone(lookup.source_bundle_matches({}))

    def test_animation_mapping_distinguishes_absence_from_fallback(self):
        model = {"animations": [{"name": "walk", "source_name": "Move"}, {"name": "attack1", "source_name": "Attack1"}]}
        action = {"events": [{"type": "EET_PlayAnim", "anim": "Attack1"},
            {"type": "EET_PlayAnim", "anim": "run"}, {"type": "EET_PlayAnim", "anim": "attack9"}]}
        result = audit.animation_mappings(action, model, {})
        self.assertEqual([entry["status"] for entry in result], ["catalog_match", "catalog_fallback_match", "not_listed_in_model_metadata"])

    def test_missing_model_and_animation_event_counts_are_not_conflated(self):
        catalog = {"enemies": [{"id": 1, "rank": "Boss", "group": "g", "prefab": "missing.prefab"}],
            "actions": [{"key": "g/a", "group": "g", "events": [
                {"type": "EET_PlayAnim", "anim": "Attack1"},
                {"type": "EET_PlayAnim", "anim": "Attack1"},
                {"type": "EET_PlayAnim", "anim": "Attack2", "enabled": False}]}],
            "ai_graphs": {}, "buffs": [], "summons": [], "damage_definitions": {}}
        report = audit.audit(catalog, {"apk_sha256": "current", "resources": {}},
            {"apk_sha256": "current", "effects": {}}, {}, {"enemies": {}}, {})
        boss = report["bosses"][0]
        self.assertFalse(boss["model_catalog_entry_present"])
        self.assertFalse(boss["model_file_exists"])
        self.assertIsNone(boss["source_prefab_present_in_manifest"])
        self.assertEqual(boss["animation_mapping_status_counts"], {"not_listed_in_model_metadata": 2})

    def test_other_apk_controller_is_reported_not_rejected(self):
        catalog = {"enemies": [{"id": 1, "rank": "Boss", "group": "g"}], "actions": [], "ai_graphs": {},
            "buffs": [], "summons": [], "damage_definitions": {}}
        report = audit.audit(catalog, {"apk_sha256": "current", "resources": {}},
            {"apk_sha256": "current", "effects": {}}, {}, {"enemies": {}},
            {"apk_sha256": "older", "enemies": {"1": {"states": {}}}})
        self.assertFalse(report["bosses"][0]["controller_apk_matches_effect_apk"])
        self.assertEqual(report["bosses"][0]["actor_prefab_embedded_effects"], "not_audited")
        with self.assertRaises(ValueError):
            audit.audit(catalog, {"apk_sha256": "one"}, {"apk_sha256": "two"}, {}, {}, {})


if __name__ == "__main__":
    unittest.main()
