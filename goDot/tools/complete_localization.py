#!/usr/bin/env python3
"""Collect player copy, resume missing translations, and audit 13 offline catalogs.

Only text values are sent to the selected public translation service. Source
files, resource paths, editor labels, and serialized runtime objects stay local.
"""

from __future__ import annotations

import argparse
import ast
import collections
import html
import json
from pathlib import Path
import re
import subprocess
import time
import unicodedata
from urllib.parse import urlencode

from localization_static import expand_static


ROOT = Path(__file__).resolve().parents[1]
CATALOGS = ROOT / "assets/localization"
LOCALES = ("zh_CN", "zh_TW", "en", "ja", "ko", "id", "th", "vi", "de", "fr", "pt", "es", "ru")
REMOTE_LOCALES = {"zh_TW": "zh-TW", **{locale: locale for locale in LOCALES if not locale.startswith("zh_")}}
HAN = re.compile(r"[\u3400-\u9fff]")
LITERAL = re.compile(r'''\#[^\n]*|"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*' ''', re.VERBOSE)
PRINTF = re.compile(r"%(?:%|(?:\d+\$)?[-+#0]*\d*(?:\.\d+)?[sdifoxXc])")
TOKEN = re.compile(
    PRINTF.pattern +
    r"|[|]|&s\d+&|<[^>]*>|\[[^\]\n]*(?:=|/)[^\]\n]*\]"
    r"|\{[A-Za-z_\d][A-Za-z_\d.:!+-]*\}|\r\n|\n|\r"
    r"|(?:res://|uid://)[^\s\"'<>]+|\b(?:[A-Za-z][A-Za-z\d]*_){1,}[A-Za-z\d_]+\b"
)
NUMBER = r"[-+]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?"
TEMPLATE_TOKEN = re.compile(TOKEN.pattern + "|" + NUMBER)
COPY_FIELDS = {
    "name", "description", "Name", "Description", "Text", "Speaker", "unlock_desc",
    "btn_name", "Label", "OptionText", "OptionSelectFinishText", "ResponseText",
    "UpgradeDescription", "effect_description", "unlcok_desc", "effect_desc", "title",
    "StoryText", "StartGambleText", "EndGambleText", "Gamble_FailureText",
    "Gameble_SuccessText", "resonance_skill_description", "SayContent", "GoodsName",
    "DetailsName", "level_up_description", "Gamble_StoryText", "WinToLeaveText",
    "FailToLeaveText", "EffectString", "Desc", "Title", "UnlockDesc", "UnopenDesc",
    "display_name", "story", "text", "MessageName", "MsgName", "AuthorId",
}
INTERNAL_FILES = {"DamageValues.json", "markers.json", "resource_bindings.json", "manifest.json"}


def read_json(path: Path, default=None):
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else (default or {})


def write_json(path: Path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def is_copy(value: str) -> bool:
    if not HAN.search(value) or "res://" in value or "uid://" in value:
        return False
    if re.fullmatch(r"[^\s。！？，：；（）【】·、<>]+_[^\s。！？，：；（）【】·、<>]+", value):
        return False
    return True


def collect_sources():
    sources = collections.defaultdict(set)
    for path in sorted((ROOT / "scripts").rglob("*.gd")):
        if path.name == "localization.gd":
            continue
        for match in LITERAL.finditer(path.read_text(encoding="utf-8")):
            literal = match.group()
            if literal.startswith("#"):
                continue
            try:
                value = ast.literal_eval(literal)
            except (SyntaxError, ValueError):
                continue
            if is_copy(value):
                sources[value].add(str(path.relative_to(ROOT)))

    def walk(value, path: Path, key=""):
        if isinstance(value, dict):
            if path.name == "dialogue.json" and "Language" in value and value["Language"] != "cn":
                return
            for child_key, child in value.items():
                walk(child, path, child_key)
        elif isinstance(value, list):
            for child in value:
                walk(child, path, key)
        elif (key in COPY_FIELDS or (path.name == "guides.json" and key in {"category", "body", "head"})) and isinstance(value, str) and is_copy(value):
            sources[value].add(str(path.relative_to(ROOT)))

    for path in sorted((ROOT / "assets/data").glob("*.json")):
        if path.name in INTERNAL_FILES:
            continue
        value = read_json(path)
        if path.name == "DisplayTerms.json":
            for group in ("specinfo", "localization"):
                for term in value.get(group, {}).values():
                    if isinstance(term, str) and is_copy(term):
                        sources[term].add(str(path.relative_to(ROOT)))
        if path.name == "combat.json":
            value = {key: value.get(key, []) for key in ("characters", "enemies")}
        walk(value, path)
    guides = ROOT / "assets/ui/settings/guides.json"
    if guides.exists():
        walk(read_json(guides), guides)
    return {source: sorted(paths) for source, paths in sorted(sources.items())}


def signature(text: str):
    return collections.Counter(TOKEN.findall(text))


def numeric_signature(text: str):
    return collections.Counter(re.findall(NUMBER, TOKEN.sub(" ", text)))


def validate(source: str, target: str, locale: str, *, strict_markup=True):
    if not target.strip():
        return "empty"
    if "\ufffd" in target or "\u2047" in target:
        return "replacement_character"
    if any(unicodedata.category(char) == "Cc" and char not in "\n\r\t" for char in target):
        return "unexpected_control_character"
    source_tokens, target_tokens = signature(source), signature(target)
    if strict_markup:
        candidates = [source]
        plain_source = expand_static(source)
        if plain_source != source:
            candidates.append(plain_source)
        candidates = [candidate for candidate in candidates if signature(candidate) == target_tokens]
        if not candidates:
            return "placeholder_or_markup_mismatch"
        candidates = [candidate for candidate in candidates if numeric_signature(candidate) == numeric_signature(target)]
        if not candidates:
            return "numeric_value_mismatch"
        if not any(PRINTF.findall(candidate) == PRINTF.findall(target) for candidate in candidates):
            return "printf_order_mismatch"
    else:
        source_tokens = collections.Counter({key: count for key, count in source_tokens.items() if key.startswith(("%", "&s"))})
        target_tokens = collections.Counter({key: count for key, count in target_tokens.items() if key.startswith(("%", "&s"))})
        if source_tokens != target_tokens:
            return "placeholder_or_markup_mismatch"
    if locale not in ("zh_CN", "zh_TW", "ja") and target.strip() == source.strip():
        return "untranslated_source"
    return ""


def protect(text: str, *, numbers=False):
    tokens = []

    def replace(match):
        tokens.append(match.group())
        return f"ZXQ{len(tokens) - 1:04d}QXZ"

    return (TEMPLATE_TOKEN if numbers else TOKEN).sub(replace, text), tokens


def numeric_template(text: str):
    """Return a reusable translation template and exact values to restore."""
    return protect(text, numbers=True)


def translation_fragments(text: str, *, numbers=True):
    """Split copy from immutable values for engines that cannot retain markers."""
    pattern = TEMPLATE_TOKEN if numbers else TOKEN
    fragments = []
    cursor = 0
    for match in pattern.finditer(text):
        if match.start() > cursor:
            fragments.append((text[cursor:match.start()], False))
        fragments.append((match.group(), True))
        cursor = match.end()
    if cursor < len(text):
        fragments.append((text[cursor:], False))
    return fragments


def restore(text: str, tokens):
    for index, value in enumerate(tokens):
        marker = f"ZXQ{index:04d}QXZ"
        if text.count(marker) != 1:
            raise ValueError(f"lost or repeated protected token {index}")
        text = text.replace(marker, value)
    if "ZXQ" in text:
        raise ValueError("unexpected protected token")
    return text


def curl(url: str, *, data=None, cookie=None):
    command = ["curl", "--fail", "--location", "--silent", "--show-error", "--max-time", "25"]
    if cookie:
        command += ["--cookie", str(cookie), "--cookie-jar", str(cookie)]
    if data:
        for key, value in data.items():
            command += ["--data-urlencode", f"{key}={value}"]
    result = subprocess.run(command + [url], capture_output=True, text=True, check=False)
    if result.returncode:
        raise RuntimeError(result.stderr.strip())
    return result.stdout


class Translator:
    def __init__(self, provider: str, endpoint: str | None):
        self.provider = provider
        self.endpoint = endpoint
        self.auth = None

    def translate_many(self, sources, locale):
        # Public endpoints have no record IDs; one request per source avoids
        # accepting a reordered multiline response as aligned translations.
        return [self.translate(source, locale) for source in sources]

    def translate(self, text: str, locale: str):
        protected, tokens = protect(text)
        language = REMOTE_LOCALES[locale]
        if self.provider == "opencc":
            if locale != "zh_TW":
                raise ValueError("OpenCC is only used for the Traditional Chinese catalog")
            from opencc import OpenCC
            if not self.auth:
                self.auth = OpenCC("s2twp")
            translated = self.auth.convert(protected)
        elif self.provider == "google":
            url = self.endpoint or "https://translate.googleapis.com/translate_a/single"
            query = urlencode({"client": "gtx", "sl": "zh-CN", "tl": language, "dt": "t", "q": protected})
            value = json.loads(curl(url + "?" + query))
            translated = "".join(str(part[0] or "") for part in value[0])
        elif self.provider == "mymemory":
            url = self.endpoint or "https://api.mymemory.translated.net/get"
            query = urlencode({"q": protected, "langpair": "zh-CN|" + language})
            value = json.loads(curl(url + "?" + query))
            if value.get("responseStatus") != 200 or value.get("quotaFinished"):
                raise RuntimeError(value.get("responseDetails", "translation quota exhausted"))
            translated = html.unescape(value["responseData"]["translatedText"])
        elif self.provider == "lingva":
            from urllib.parse import quote
            url = self.endpoint or "https://lingva.ml/api/v1"
            value = json.loads(curl(f"{url}/zh/{language}/{quote(protected, safe='')}"))
            translated = value["translation"]
        elif self.provider == "bing":
            if not self.auth:
                page = curl("https://cn.bing.com/translator")
                abuse = re.search(r"var params_AbusePreventionHelper = (\[[^;]+\]);", page)
                ig = re.search(r'IG:"([^" ]+)"', page)
                iid = re.search(r'data-iid="([^"]+)"', page)
                if not (abuse and ig and iid):
                    raise RuntimeError("Bing did not issue translation session parameters")
                key, token, _ = json.loads(abuse.group(1))
                self.auth = (key, token, ig.group(1), iid.group(1))
            key, token, ig, iid = self.auth
            language = "zh-Hant" if locale == "zh_TW" else language
            value = json.loads(curl(f"https://cn.bing.com/ttranslatev3?isVertical=1&IG={ig}&IID={iid}.1", data={
                "fromLang": "zh-Hans", "to": language, "text": protected, "token": token, "key": str(key),
            }))
            if not isinstance(value, list):
                raise RuntimeError("Bing declined the anonymous translation request")
            translated = value[0]["translations"][0]["text"]
        else:
            raise ValueError(self.provider)
        result = restore(translated, tokens)
        error = validate(text, result, locale)
        if error:
            raise ValueError(error)
        return result


def load_catalogs(locale):
    original = read_json(CATALOGS / "original" / f"{locale}.json")
    supplemental = read_json(CATALOGS / "supplemental" / f"{locale}.json")
    return original, supplemental


def load_overrides():
    value = read_json(CATALOGS / "overrides.json")
    if "messages" in value and "locales" in value:
        return {source: dict(zip(value["locales"], targets)) for source, targets in value["messages"].items()}
    return value


def audit(sources):
    report = {"source_count": len(sources), "source_characters": sum(map(len, sources)), "locales": {}}
    for locale in LOCALES:
        original, supplemental = load_catalogs(locale)
        merged = {**original, **supplemental}
        overrides = load_overrides()
        for source, translations in overrides.items():
            if locale in translations:
                merged[source] = translations[locale]
        missing, invalid, number_risks = [], {}, {}
        for source in sources:
            if locale == "zh_CN":
                continue
            if source not in merged:
                missing.append(source)
            else:
                strict = source in supplemental or locale in overrides.get(source, {})
                error = validate(source, merged[source], locale, strict_markup=strict)
                if error:
                    invalid[source] = error
                if source in original and not strict:
                    if numeric_signature(source) != numeric_signature(merged[source]):
                        number_risks[source] = merged[source]
        report["locales"][locale] = {
            "translated": len(sources) - len(missing) - len(invalid),
            "missing": missing, "invalid": invalid,
            "original_number_risks": number_risks,
        }
    write_json(CATALOGS / "coverage.json", report)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--translate", action="store_true")
    parser.add_argument("--provider", choices=("google", "bing", "mymemory", "lingva", "opencc"), default="google")
    parser.add_argument("--endpoint")
    parser.add_argument("--locale", action="append", choices=LOCALES)
    parser.add_argument("--limit", type=int, default=0, help="Maximum new translations per locale (0: unlimited)")
    parser.add_argument("--scripts-only", action="store_true")
    parser.add_argument("--delay", type=float, default=0.15)
    parser.add_argument("--max-source-length", type=int, default=0)
    parser.add_argument("--replace-existing", action="store_true", help="Regenerate existing machine/authored entries while preserving manual overrides")
    args = parser.parse_args()
    sources = collect_sources()
    write_json(CATALOGS / "sources.json", sources)
    selected = {source: paths for source, paths in sources.items() if not args.scripts_only or any(path.startswith("scripts/") for path in paths)}
    translator = Translator(args.provider, args.endpoint)
    if args.translate:
        for locale in args.locale or LOCALES:
            original, supplemental = load_catalogs(locale)
            merged = {**original, **supplemental}
            overrides = load_overrides()
            translated = 0
            last_saved = 0
            failures = 0
            pending = [source for source in sorted(selected, key=lambda source: (not any(p.startswith("scripts/") for p in selected[source]), len(source), source))
                       if locale != "zh_CN" and locale not in overrides.get(source, {})
                       and (not args.max_source_length or len(source) <= args.max_source_length)
                       and (args.replace_existing or source not in merged or validate(source, merged[source], locale, strict_markup=source in supplemental))]
            while pending and (not args.limit or translated < args.limit):
                batch = [pending.pop(0)]
                try:
                    results = translator.translate_many(batch, locale)
                except (ValueError, RuntimeError, KeyError, TypeError) as error:
                    print(f"{locale}: stopped: {error}", flush=True)
                    failures += 1
                    if failures >= 3:
                        break
                    continue
                supplemental.update(zip(batch, results))
                translated += len(batch)
                failures = 0
                if translated - last_saved >= 20:
                    write_json(CATALOGS / "supplemental" / f"{locale}.json", supplemental)
                    print(f"{locale}: +{translated}, total supplemental={len(supplemental)}", flush=True)
                    last_saved = translated
                if args.limit and translated >= args.limit:
                    break
                time.sleep(args.delay)
            write_json(CATALOGS / "supplemental" / f"{locale}.json", supplemental)
            print(f"{locale}: saved {len(supplemental)} supplemental translations", flush=True)
    report = audit(sources)
    print(json.dumps({"source_count": len(sources), "locales": {k: {"translated": v["translated"], "missing": len(v["missing"]), "invalid": len(v["invalid"])} for k, v in report["locales"].items()}}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
