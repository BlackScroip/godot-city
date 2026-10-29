#!/usr/bin/env python3
"""Audit imported Boss visual references, dependencies and effect budgets.

This is an offline audit of already extracted APK records. It does not extract
or execute the APK and does not claim that a mapped effect was rendered.
"""

import argparse
from collections import Counter, deque
import hashlib
import json
import math
from pathlib import Path
import struct
import zipfile

from import_region_combat import references, walk


ROOT = Path(__file__).resolve().parents[1]
VISUAL_FIELDS = {
    "EffectName", "Effect", "ModlePrefab", "EntityEndEffect", "mEntityEndEffect_Floor",
    "TargetEffect", "AimEffect", "KeepEffect", "StartEffect", "EndEffect",
    "PlayEffectWhenLayerMax", "HitEffect_OnTarget", "HitEffect_UnitCenter",
    "DetectionEffectName", "ReplaceEffectName", "Prefab", "PickUpEffect",
    "EffectName_Start", "EffectName_Loop", "EffectName_End", "HitEffect", "DestoryEffect",
    "InitEffect", "BeAttackEffect", "TriggerEffectName_Delay", "TriggerEffectName_NoDelay",
    "BounceEffect", "CounterFx",
}
PLACEHOLDERS = {"triggereffectname_delay", "triggereffectname_nodelay"}
EX_BUFFS = ("45400001", "45400002", "45400003", "45400004", "45400005", "45400006", "45400010")
# Keep these limits aligned with AuthoredEffect.emitter_budget and configure.
# The unit tests compare the effect names and overrides with the Godot source.
BOSS_BURST_EFFECTS = {
    "26071801_fx_enemy_mojiehua_attack3_duyejidang",
    "26091901_fx_enemy_dilong_roartostone_fall",
    "24120601_fx_enemy_feimolong_bullet_lighting_thunderwarning",
    "24120901_fx_enemy_feimolong_bullet_lighting_darkwarning",
}
BOSS_LOW_EMITTER_OVERRIDES = {"26071801_fx_enemy_mojiehua_attack3_duyejidang": 15}


def load(path):
    return json.loads(path.read_text())


def resource_key(value):
    return value.replace("\\", "/").split("/")[-1].removesuffix(".prefab").lower()


class ManifestReader:
    def __init__(self, payload):
        self.payload, self.offset = payload, 0

    def number(self, fmt):
        value = struct.unpack_from("<" + fmt, self.payload, self.offset)[0]
        self.offset += struct.calcsize(fmt)
        return value

    def string(self):
        size = self.number("H")
        value = self.payload[self.offset:self.offset + size].decode("utf-8")
        self.offset += size
        return value

    def array(self, read):
        return [read() for _ in range(self.number("H"))]


def manifest_records(payload):
    # Same YooAsset 2.3.1 manifest layout as import_player_lifecycle.py.
    reader = ManifestReader(payload)
    reader.number("I")
    reader.string()
    for _ in range(3):
        reader.number("B")
    for _ in range(2):
        reader.number("i")
    for _ in range(4):
        reader.string()
    assets = []
    for _ in range(reader.number("i")):
        address, path, _ = (reader.string() for _ in range(3))
        reader.array(reader.string)
        bundle = reader.number("i")
        dependencies = reader.array(lambda: reader.number("i"))
        assets.append({"address": address, "path": path, "bundle": bundle, "deps": dependencies})
    bundles = []
    for _ in range(reader.number("i")):
        name = reader.string()
        reader.number("I")
        digest = reader.string()
        reader.string()
        reader.number("q")
        reader.number("B")
        reader.array(reader.string)
        reader.array(lambda: reader.number("i"))
        bundles.append({"name": name, "hash": digest})
    if reader.offset != len(payload):
        raise ValueError("APK manifest has trailing or unparsed bytes")
    return assets, bundles


class ApkResources:
    """Look up exact manifest names and hash only referenced source bundles."""
    def __init__(self, archive, assets, bundles, media, followers):
        self.archive = archive
        self.assets = {resource_key(asset["address"]): asset for asset in assets}
        self.bundles = bundles
        self.media = media
        self.followers = followers
        self.hashes = {}
        self.member_hashes = {}

    def member_hash(self, member):
        if member not in self.member_hashes:
            self.member_hashes[member] = hashlib.sha256(self.archive.read(member)).hexdigest()
        return self.member_hashes[member]

    def source_bundle_matches(self, source):
        member, expected = source.get("bundle", ""), source.get("bundle_sha256", "")
        if not member or not expected:
            return None
        try:
            return self.member_hash(member) == expected
        except KeyError:
            return False

    def get(self, name, default=None):
        asset = self.assets.get(name)
        if name in self.media.get("audio", {}) or (asset and "/Prefabs/BattleSys/Role/" in asset["path"]):
            return default
        effect = self.media.get("effects", {}).get(name, {})
        follower = self.followers.get("effects", {}).get(name, {})
        status = ("exact_resource_absent" if not asset else "authored_follower" if follower else "authored_particles" if effect.get("layers")
            else "authored_model" if effect.get("models") else "source_present_unrendered" if asset else "exact_resource_absent")
        expected_hash = ""
        if asset:
            index = asset["bundle"]
            if index not in self.hashes:
                member = "assets/yoo/DefaultPackage/" + self.bundles[index]["hash"] + ".bundle"
                self.hashes[index] = self.member_hash(member)
            expected_hash = self.hashes[index]
        return {"status": status, "source_bundle_sha256": expected_hash, "source_asset": asset,
            "follower_style": follower}


def visual_references(value, pointer=""):
    if isinstance(value, dict):
        for field, child in value.items():
            path = pointer + "/" + field.replace("~", "~0").replace("/", "~1")
            if field in VISUAL_FIELDS and isinstance(child, str) and child:
                name = resource_key(child)
                if name not in PLACEHOLDERS:
                    yield name, path
            yield from visual_references(child, path)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from visual_references(child, pointer + "/" + str(index))


def raw_value(row):
    value = row.get("raw_data", row.get("raw", row)) if isinstance(row, dict) else row
    return json.loads(value) if isinstance(value, str) else value


def enabled_action_values(action):
    result = []
    for kind in ("events", "hits"):
        for index, row in enumerate(action.get(kind, [])):
            if not row.get("enabled", True):
                continue
            result.append((f"{kind}/{index}", raw_value(row)))
            for condition_index, condition in enumerate(row.get("conditions", [])):
                result.append((f"{kind}/{index}/conditions/{condition_index}", raw_value(condition)))
    return result


def trace(values, indexes, extra_refs=None):
    """Conservative dependency closure, including condition/clear-only IDs."""
    found = {}
    seen = {kind: set() for kind in indexes}
    missing = {kind: set() for kind in indexes}
    pending = deque((kind, str(ident)) for kind, ids in (extra_refs or {}).items() for ident in ids)

    def collect(label, value):
        for name, pointer in visual_references(value):
            found.setdefault(name, set()).add(label + pointer)
        for kind, ids in references(value).items():
            pending.extend((kind, ident) for ident in ids)

    for label, value in values:
        collect(label, value)
    while pending:
        kind, ident = pending.popleft()
        if ident in seen[kind]:
            continue
        seen[kind].add(ident)
        value = indexes[kind].get(ident)
        if value is None:
            missing[kind].add(ident)
        else:
            collect(f"{kind}:{ident}", raw_value(value))
    return {
        "resources": {name: sorted(locations) for name, locations in sorted(found.items())},
        "dependencies": {kind: sorted(ids) for kind, ids in seen.items()},
        "missing_dependencies": {kind: sorted(ids) for kind, ids in missing.items()},
    }


def scalar(value, fallback=0.0):
    if isinstance(value, (int, float)):
        return float(value)
    return float(value.get("scalar", fallback)) if isinstance(value, dict) else fallback


def max_scalar(value, fallback=0.0):
    upper = scalar(value, fallback)
    if isinstance(value, dict) and int(value.get("minMaxState", 0)) in (2, 3):
        return max(upper, float(value.get("minScalar", upper)))
    return upper


def animation_mappings(action, model, states):
    clips = model.get("animations", []) if isinstance(model, dict) else []
    names = {str(clip.get("name", "")) for clip in clips}
    aliases = {}
    for clip in clips:
        source = str(clip.get("source_name", clip.get("name", ""))).lower()
        aliases.setdefault(source, str(clip.get("name", "")))
        aliases.setdefault(source.replace("@", "_"), str(clip.get("name", "")))
    mappings = []
    for row in action.get("events", []):
        if not row.get("enabled", True) or row.get("type") != "EET_PlayAnim" or not row.get("anim"):
            continue
        source = row["anim"]
        state = states.get(source.lower(), {})
        candidate = str(state.get("animation", "")) if str(state.get("animation", "")) in names else source
        candidate = aliases.get(candidate.lower(), candidate)
        if candidate in names:
            status = "catalog_match"
        else:
            alternatives = {"idle": ["idle", "stand", "wait"], "run": ["run", "walk", "move"],
                "attack": ["attack", "atk", "skill"], "dodge": ["dodge", "roll", "dash", "run"],
                "death": ["death", "die", "dead"], "hit": ["hit_1", "behit", "hurt", "hit"]}
            matches = [name for token in alternatives.get(candidate, [candidate]) for name in names if token.lower() in name.lower()]
            candidate = sorted(matches)[0] if matches else ""
            status = "catalog_fallback_match" if candidate else "not_listed_in_model_metadata"
        mappings.append({"requested": source, "status": status, "catalog_clip": candidate})
    return mappings


def effective_layer(layer, library):
    if not layer.get("active", True):
        return False
    renderer = layer.get("renderer", {})
    if not renderer.get("enabled", True) or int(renderer.get("render_mode", 0)) == 5:
        return False
    if int(renderer.get("render_mode", 0)) == 4 and not layer.get("mesh", ""):
        return False
    materials = layer.get("materials", [])
    if not any(library.get(str(value.get("reference", ""))) if "reference" in value else value for value in materials):
        return False
    return layer.get("emission", {}).get("enabled", True)


def budget_profile(effect, library, low_quality=False):
    """Count enabled source work before runtime caps, not rendered particles.

    Burst cycles consume separate logical emitters up to the runtime cycle cap.
    Requested particles include the per-emitter (96/32) and source caps, but
    not overall emitter or particle allocation, or reduced-quality sampling.
    This does not predict which equally prioritised layer survives.
    """
    source_name = Path(str(effect.get("source", "")).replace("\\", "/")).stem.lower()
    boss_burst_effect = source_name in BOSS_BURST_EFFECTS
    eligible = [layer for layer in effect.get("layers", []) if effective_layer(layer, library)]
    emitter_count = 0
    emitting_layers = 0
    particle_count = 0
    per_layer_cap = 32 if low_quality else 96
    for layer in eligible:
        before = emitter_count
        emission, initial = layer.get("emission", {}), layer.get("initial", {})
        limit = per_layer_cap
        if int(initial.get("maxNumParticles", 0)) > 0:
            limit = min(limit, int(initial["maxNumParticles"]))
        bursts = emission.get("m_Bursts", [])
        rate = scalar(emission.get("rateOverTime", {}))
        if bursts and rate <= 0:
            for burst in bursts:
                if float(burst.get("probability", 1)) <= 0:
                    continue
                cycles = max(1, min(int(burst.get("cycleCount", 1)), 10 if boss_burst_effect else 6))
                emitter_count += cycles
                particle_count += cycles * max(1, min(int(scalar(burst.get("countCurve", {}), 1)), limit))
        else:
            lifetime = max(0.02, min(max_scalar(initial.get("startLifetime", {}), 0.3), 8.0))
            count = sum(scalar(burst.get("countCurve", {}), 1) for burst in bursts)
            emitter_count += 1
            particle_count += max(1, min(math.ceil(max(count, rate * lifetime)), limit))
        if emitter_count > before:
            emitting_layers += 1
    if boss_burst_effect:
        emitter_budget = BOSS_LOW_EMITTER_OVERRIDES.get(source_name, 12) if low_quality else 28
    else:
        emitter_budget = 8 if low_quality else 18
    particle_budget = 144 if low_quality else 384
    return {"eligible_layers": len(eligible), "emitting_layers": emitting_layers,
        "requested_emitters": emitter_count,
        "requested_particle_slots": particle_count, "emitter_budget": emitter_budget,
        "particle_budget": particle_budget, "emitter_limit_exceeded": emitter_count > emitter_budget,
        "emitting_layers_fit_budgets": emitting_layers <= emitter_budget and emitting_layers <= particle_budget,
        "particle_limit_exceeded_without_emitter_cap": particle_count > particle_budget}


def resource_details(name, coverage, media, library, project=ROOT):
    record = coverage.get("resources", {}).get(name)
    if record is None:
        return {"status": "unclassified_reference", "note": "Excluded actor or audio reference, not classified as a missing effect."}
    style = record.get("follower_style") or media.get("effects", {}).get(name, {})
    expected_hash = record.get("source_bundle_sha256", "")
    bound = bool(expected_hash) and style.get("source_sha256") == expected_hash
    imported = record.get("status") in ("authored_particles", "authored_model", "authored_follower")
    status = record.get("status", "unclassified_reference")
    if imported and not bound:
        status = "import_missing_or_stale"
    result = {"status": status, "source_binding_verified": bound,
        "source_asset": record.get("source_asset"), "unsupported": style.get("unsupported", [])}
    if style:
        paths = set(style.get("textures", []))
        paths.update(layer.get("mesh", "") for layer in style.get("layers", []))
        paths.update(model.get("scene", "") for model in style.get("models", []))
        result["missing_local_files"] = sorted(path for path in paths if path.startswith("res://") and not (project / path[6:]).is_file())
        result["full_quality"] = budget_profile(style, library)
        result["reduced_quality"] = budget_profile(style, library, True)
    return result


def audit(catalog, coverage, media, library, asset_catalog, presentation, project=ROOT):
    hashes = {value for value in (coverage.get("apk_sha256"), media.get("apk_sha256")) if value}
    if len(hashes) > 1:
        raise ValueError("APK hashes differ between the imported presentation catalogs")
    indexes = {"buff": {str(row["id"]): row for row in catalog.get("buffs", [])},
        "summon": {str(row["id"]): row for row in catalog.get("summons", [])},
        "damage": catalog.get("damage_definitions", {})}
    bosses, all_resources = [], set()
    for enemy in catalog.get("enemies", []):
        if enemy.get("rank") != "Boss":
            continue
        group = enemy["group"]
        actions = [action for action in catalog.get("actions", []) if action.get("group") == group]
        action_keys = {action["key"] for action in actions}
        models = asset_catalog.get("enemies", {})
        model_key = str(enemy["id"])
        model = models.get(model_key, {})
        states = presentation.get("enemies", {}).get(str(enemy["id"]), {}).get("states", {})
        action_rows = []
        missing_actions = []
        for action in actions:
            values = enabled_action_values(action)
            direct = {name for _, value in values for name, _ in visual_references(value)}
            result = trace(values, indexes)
            resolver = coverage.get("resources", {})
            source_verification = resolver.source_bundle_matches(action.get("apk_source", {})) if isinstance(resolver, ApkResources) else None
            result.update({"key": action["key"], "direct_visuals": sorted(direct),
                "dependent_visuals": sorted(set(result["resources"]) - direct),
                "animation_mappings": animation_mappings(action, model, states),
                "action_source_bundle_matches_apk": source_verification})
            action_rows.append(result)
            all_resources.update(result["resources"])
            for row in action.get("events", []):
                if row.get("enabled", True) and row.get("type") == "EET_Interrupt" and row.get("target"):
                    target = group + "/" + row["target"]
                    if target not in action_keys:
                        missing_actions.append({"from": action["key"], "target": target,
                            "requested_by_ai": row["target"] in enemy.get("ai_action_ids", [])})
        ai_buff_ids = set()
        for item in walk(catalog.get("ai_graphs", {}).get(enemy.get("ai", ""), {})):
            for field in ("BuffId", "CheckBuffId"):
                value = item.get(field)
                if isinstance(value, dict) and isinstance(value.get("_value"), str) and value["_value"]:
                    ai_buff_ids.add(value["_value"])
        state = trace([], indexes, {"buff": ai_buff_ids | set(EX_BUFFS)})
        all_resources.update(state["resources"])
        model_path = model.get("path", "") if isinstance(model, dict) else model
        source_prefab = enemy.get("prefab", "")
        resolver = coverage.get("resources", {})
        source_prefab_present = resource_key(source_prefab) in resolver.assets if source_prefab and isinstance(resolver, ApkResources) else None
        bosses.append({"id": enemy["id"], "name": enemy.get("name", ""), "group": group,
            "source_prefab": source_prefab, "source_prefab_present_in_manifest": source_prefab_present,
            "model_catalog_entry_present": model_key in models, "model_path": model_path,
            "model_file_exists": bool(model_path.startswith("res://") and (project / model_path[6:]).is_file()),
            "controller_state_mapping_present": str(enemy["id"]) in presentation.get("enemies", {}),
            "controller_apk_matches_effect_apk": presentation.get("apk_sha256") in hashes,
            "actor_prefab_embedded_effects": "not_audited",
            "action_count": len(actions), "missing_action_targets": missing_actions,
            "animation_mapping_status_counts": dict(sorted(Counter(mapping["status"] for action in action_rows for mapping in action["animation_mappings"]).items())),
            "ai_and_shared_ex": state, "actions": action_rows})
    details = {name: resource_details(name, coverage, media, library, project) for name in sorted(all_resources)}
    for boss in bosses:
        names = set(boss["ai_and_shared_ex"]["resources"])
        for action in boss["actions"]:
            names.update(action["resources"])
        boss["resource_status_counts"] = dict(sorted(Counter(details[name]["status"] for name in names).items()))
        boss["full_quality_scheduled_emitter_budget_exceeded"] = sorted(name for name in names if details[name].get("full_quality", {}).get("emitter_limit_exceeded"))
        boss["full_quality_particle_limit_candidates"] = sorted(name for name in names if details[name].get("full_quality", {}).get("particle_limit_exceeded_without_emitter_cap"))
        boss["reduced_quality_scheduled_emitter_budget_exceeded"] = sorted(name for name in names if details[name].get("reduced_quality", {}).get("emitter_limit_exceeded"))
        boss["missing_local_files"] = {name: details[name]["missing_local_files"] for name in sorted(names) if details[name].get("missing_local_files")}
    return {"schema": 1, "apk_sha256": next(iter(hashes), ""),
        "controller_catalog_apk_sha256": presentation.get("apk_sha256", ""), "bosses": bosses, "resources": details,
        "limitations": [
            "Static potential references are not proof of runtime reachability, visibility, timing or APK parity.",
            "Action bundle hashes are checked, but action, state and summon JSON contents are not re-extracted or compared in this audit.",
            "Actor prefab presence is an exact normalized manifest-address lookup for the imported prefab name, not a search of bundle-internal objects or alternate names.",
            "Dependency closure includes condition and clear-only references; shared EX roots are conservatively included for every Boss.",
            "Actor prefab embedded effects, animation events, preloaded-only assets and fields outside VISUAL_FIELDS are not audited.",
            "Unclassified references may be actors or audio and must not be treated as missing effects.",
            "Controller state mappings have a separately reported APK hash and may come from another build.",
            "Animation matches use imported metadata only, not the loaded Godot AnimationPlayer or live playback.",
            "Budget counts include enabled material-bearing layers and up to 10 burst cycles for designated Boss prefabs (six otherwise), but not layer suppression, reduced-quality sampling or effect-specific runtime conditions; particle totals ignore the competing emitter cap.",
            "A full-quality effect whose emitting layers fit the budgets is allocated at least one emitter per layer by the current scheduler; repeated burst cycles can still be truncated. This is not a visibility test.",
            "Descriptors and local files existing do not establish that all source shaders, particle modules or mesh bindings render equivalently.",
        ]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="Write the detailed JSON report here")
    parser.add_argument("--apk", type=Path, default=ROOT.parent / "1061664.apk", help="APK used for exact manifest and source-bundle verification")
    args = parser.parse_args()
    media = load(ROOT / "assets/combat_presentation/catalog.json")
    follower_path = ROOT / "assets/spirit_followers/catalog.json"
    followers = load(follower_path) if follower_path.exists() else {}
    with args.apk.open("rb") as stream:
        actual = hashlib.file_digest(stream, "sha256").hexdigest()
    if followers and followers.get("apk_sha256") != actual:
        raise ValueError("Follower catalog belongs to a different APK")
    with zipfile.ZipFile(args.apk) as archive:
        names = [name for name in archive.namelist() if name.startswith("assets/yoo/DefaultPackage/DefaultPackage_") and name.endswith(".bytes")]
        if len(names) != 1:
            raise ValueError("Expected exactly one APK DefaultPackage manifest")
        payload = archive.read(names[0])
        assets, bundles = manifest_records(payload)
        coverage = {"apk_sha256": actual, "resources": ApkResources(archive, assets, bundles, media, followers)}
        result = audit(load(ROOT / "assets/data/combat.json"), coverage, media,
            load(ROOT / "assets/combat_presentation/materials.json"), load(ROOT / "assets/catalog.json"),
            load(ROOT / "assets/data/monster_presentation.json"))
        result["manifest"] = {"member": names[0], "sha256": hashlib.sha256(payload).hexdigest()}
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"apk_sha256": result["apk_sha256"], "bosses": [
        {key: boss[key] for key in ("id", "name", "action_count", "source_prefab_present_in_manifest", "model_catalog_entry_present", "model_file_exists", "animation_mapping_status_counts", "resource_status_counts", "full_quality_scheduled_emitter_budget_exceeded", "full_quality_particle_limit_candidates", "reduced_quality_scheduled_emitter_budget_exceeded")}
        for boss in result["bosses"]], "output": str(args.output) if args.output else None}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
