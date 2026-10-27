#!/usr/bin/env python3
"""Resume local Argos/CTranslate2 translation without packaging model weights.

Install ctranslate2 and sentencepiece in a task environment. Pass an extracted
Argos model directory or .argosmodel archive. Results default to a separate
/tmp directory so an online producer can continue writing supplemental files.
"""

from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import time
import unicodedata
import zipfile

import complete_localization as catalog
from localization_static import expand_static, transformation


NLLB_LANGUAGES = {
    "zh_CN": "zho_Hans", "zh_TW": "zho_Hant", "en": "eng_Latn", "ja": "jpn_Jpan",
    "ko": "kor_Hang", "id": "ind_Latn", "th": "tha_Thai", "vi": "vie_Latn",
    "de": "deu_Latn", "fr": "fra_Latn", "pt": "por_Latn", "es": "spa_Latn", "ru": "rus_Cyrl",
}
EXTRA_IMMUTABLE = re.compile(r"[_“”]|(?<![A-Za-z])[Ll][Vv]\d+|\b[IVX]{2,4}\b|(?<= )I$")
EXTRA_NUMERIC_IMMUTABLE = re.compile(r"[%％‰_“”]|(?<![A-Za-z])[Ll][Vv]\d+|\b[IVX]{2,4}\b|(?<= )I$")
PERCENT_WORDS = {
    "en": r"per\s*cent|percent", "ja": "パーセント", "ko": "퍼센트",
    "id": "persen", "th": "เปอร์เซ็นต์", "vi": r"phần\s*trăm", "de": "Prozent",
    "fr": r"pour\s*cent|pourcent", "pt": r"por\s*cento", "es": r"por\s*ciento",
    "ru": r"процент(?:ов|а)?",
}
LATIN_PUNCTUATION = str.maketrans({
    "。": ".", "，": ",", "；": ";", "：": ":", "！": "!", "？": "?",
    "（": "(", "）": ")", "【": "[", "】": "]", "、": ",",
})
ENGLISH_NUMBER_WORDS = {
    "zero": "0", "one": "1", "first": "1", "once": "1", "two": "2", "double": "2", "twice": "2",
    "triple": "3",
    "three": "3", "third": "3", "four": "4", "fourth": "4", "five": "5", "fifth": "5",
    "six": "6", "sixth": "6", "seven": "7", "seventh": "7", "eight": "8", "eighth": "8",
    "nine": "9", "ninth": "9", "ten": "10", "tenth": "10", "thirty": "30",
}
NUMBER_WORDS = {
    "ja": ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十", "三十", "一万"],
    "ko": ["영", "일", "이", "삼", "사", "오", "육", "칠", "팔", "구", "십", "삼십", "일만"],
    "id": ["nol", "satu", "dua", "tiga", "empat", "lima", "enam", "tujuh", "delapan", "sembilan", "sepuluh", "tiga puluh", "sepuluh ribu"],
    "th": ["ศูนย์", "หนึ่ง", "สอง", "สาม", "สี่", "ห้า", "หก", "เจ็ด", "แปด", "เก้า", "สิบ", "สามสิบ", "หนึ่งหมื่น"],
    "vi": ["không", "một", "hai", "ba", "bốn", "năm", "sáu", "bảy", "tám", "chín", "mười", "ba mươi", "mười nghìn"],
    "de": ["null", "eins", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun", "zehn", "dreißig", "zehntausend"],
    "fr": ["zéro", "un", "deux", "trois", "quatre", "cinq", "six", "sept", "huit", "neuf", "dix", "trente", "dix mille"],
    "pt": ["zero", "um", "dois", "três", "quatro", "cinco", "seis", "sete", "oito", "nove", "dez", "trinta", "dez mil"],
    "es": ["cero", "uno", "dos", "tres", "cuatro", "cinco", "seis", "siete", "ocho", "nueve", "diez", "treinta", "diez mil"],
    "ru": ["ноль", "один", "два", "три", "четыре", "пять", "шесть", "семь", "восемь", "девять", "десять", "тридцать", "десять тысяч"],
}
ALLOWED_SCRIPTS = {
    "ja": ("LATIN", "CJK", "HIRAGANA", "KATAKANA", "IDEOGRAPHIC"),
    "ko": ("LATIN", "HANGUL"),
    "th": ("LATIN", "THAI"),
    "ru": ("LATIN", "CYRILLIC"),
}


def replacement_characters(target):
    return sorted(set(target) & {"\ufffd", "\u2047"})


def unexpected_script_characters(target, locale):
    if locale in ("zh_CN", "zh_TW"):
        return []
    allowed = ALLOWED_SCRIPTS.get(locale, ("LATIN",))
    return sorted({char for char in catalog.TOKEN.sub("", target)
                   if unicodedata.category(char).startswith(("L", "M"))
                   and not unicodedata.name(char, "").startswith(allowed + ("COMBINING", "MODIFIER LETTER"))})


def normalize_written_numbers(source, target, locale):
    """Keep explicitly spelled source numerals spelled in the translated copy."""
    if locale not in NUMBER_WORDS:
        return target
    words = dict(zip([str(value) for value in range(11)] + ["30", "10000"], NUMBER_WORDS[locale]))
    plain_source = catalog.TOKEN.sub(" ", source)
    myriad = len(re.findall(r"\bten[ -]+thousand\b", plain_source, flags=re.I))
    plain_source = re.sub(r"\bten[ -]+thousand\b", " ", plain_source, flags=re.I)
    allowance = Counter(ENGLISH_NUMBER_WORDS[word.lower()] for word in
                        re.findall(r"\b(?:" + "|".join(ENGLISH_NUMBER_WORDS) + r")\b", plain_source, flags=re.I))
    allowance["2"] += len(re.findall(r"\bsecond(?=\s+(?:attack|stage|level|hit|part|tier|floor)\b)",
                                      plain_source, flags=re.I))
    allowance["10000"] += myriad
    extra = catalog.numeric_signature(target) - catalog.numeric_signature(source)
    parts = []
    for value, protected in catalog.translation_fragments(target, numbers=False):
        if not protected:
            if allowance["10000"]:
                value, count = re.subn(r"(?<!\d)10[, .]000(?!\d)", words["10000"], value,
                                       count=allowance["10000"])
                allowance["10000"] -= count

            def replace(match):
                number = match.group()
                if extra[number] > 0 and allowance[number] > 0 and number in words:
                    extra[number] -= 1
                    allowance[number] -= 1
                    if locale == "ko":
                        following = match.string[match.end():]
                        if following.startswith("번째") and number == "1":
                            return "첫 "
                        if re.match(r"(?:개|명|마리|번|발|자루|가지|곳)", following):
                            native = {"1": "한", "2": "두", "3": "세", "4": "네", "5": "다섯",
                                      "6": "여섯", "7": "일곱", "8": "여덟", "9": "아홉", "10": "열", "30": "서른"}
                            if number in native:
                                return native[number] + " "
                    return words[number]
                return number

            value = re.sub(catalog.NUMBER, replace, value)
        parts.append(value)
    return "".join(parts)


def natural_chunks(value):
    limit = 180 if catalog.HAN.search(value) else 600
    if len(value) <= limit:
        return [value]
    sentences = re.split(r"(?<=[。！？；!?;])|(?<=\.)(?!\d)", value)
    result = []
    for sentence in sentences:
        clauses = re.split(r"(?<=[，、])", sentence) if len(sentence) > limit else [sentence]
        for clause in clauses:
            while len(clause) > limit:
                boundary = clause.rfind(" ", 0, limit + 1)
                if boundary < limit // 2:
                    boundary = limit
                result.append(clause[:boundary])
                clause = clause[boundary:]
            if clause:
                result.append(clause)
    return result


def immutable_fragments(source, *, numbers=False):
    result = []
    for value, protected in catalog.translation_fragments(source, numbers=numbers):
        if protected:
            result.append((value, True))
            continue
        cursor = 0
        for match in (EXTRA_NUMERIC_IMMUTABLE if numbers else EXTRA_IMMUTABLE).finditer(value):
            if match.start() > cursor:
                result.extend((chunk, False) for chunk in natural_chunks(value[cursor:match.start()]))
            result.append((match.group(), True))
            cursor = match.end()
        if cursor < len(value):
            result.extend((chunk, False) for chunk in natural_chunks(value[cursor:]))
    return result


def values_match(source, target):
    source = catalog.TOKEN.sub(" ", source)
    target = catalog.TOKEN.sub(" ", target)
    numeric = r"[-+]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?"
    return (Counter(re.findall(numeric, source)) == Counter(re.findall(numeric, target))
            and Counter(char for char in source if char in "%％‰")
            == Counter(char for char in target if char in "%％‰"))


def normalize_notation(source, target, locale):
    parts = catalog.translation_fragments(target, numbers=False)
    percent_word = PERCENT_WORDS.get(locale)
    normalized = []
    for value, protected in parts:
        if not protected:
            if locale not in ("zh_CN", "zh_TW", "ja"):
                value = value.translate(LATIN_PUNCTUATION)
            value = re.sub(r"([+-])\s+(?=\d)", r"\1", value)
            if percent_word:
                value = re.sub(r"(?<=\d)\s*(?:" + percent_word + r")(?!\w)", "%", value, flags=re.I)
        normalized.append([value, protected])
    target = "".join(value for value, _ in normalized)
    source_values = catalog.numeric_signature(source)
    target_values = catalog.numeric_signature(target)
    for value, count in source_values.items():
        if not value.startswith("+") or source_values.get(value[1:]):
            continue
        remaining = count - target_values.get(value, 0)
        pattern = re.compile(r"(?<![\d.+-])" + re.escape(value[1:]) + r"(?![\d.])")
        for part in normalized:
            if part[1] or remaining <= 0:
                continue
            part[0], restored = pattern.subn(value, part[0], count=remaining)
            remaining -= restored
    return normalize_written_numbers(source, "".join(value for value, _ in normalized), locale)


def model_directory(path: Path, cache: Path) -> Path:
    if path.is_dir():
        return path
    if not zipfile.is_zipfile(path):
        raise ValueError("Model must be an extracted Argos directory or a valid archive")
    with path.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    directory = cache / digest[:16]
    marker = directory / ".complete"
    if not marker.exists():
        directory.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(path) as archive:
            for member in archive.namelist():
                if not (directory / member).resolve().is_relative_to(directory.resolve()):
                    raise ValueError("Unsafe model archive path")
            archive.extractall(directory)
        marker.touch()
    return directory


class OfflineTranslator:
    def __init__(self, path: Path, cache: Path, threads: int, batch_size: int,
                 translation_cache: Path, engine: str = "argos",
                 source_language: str = "zh", target_locale: str = "en", beam_size: int = 4):
        import ctranslate2
        import sentencepiece

        root = model_directory(path, cache)
        binaries = sorted(root.rglob("model.bin"))
        if len(binaries) != 1:
            raise ValueError("Expected one CTranslate2 model.bin in the Argos package")
        pieces = sorted(root.rglob("sentencepiece.bpe.model" if engine == "nllb" else "sentencepiece.model"))
        if not pieces:
            pieces = sorted(root.rglob("*.model"))
        if not pieces:
            raise ValueError("The Argos package has no SentencePiece model")
        source = next((item for item in pieces if item.name.startswith("source")), pieces[0])
        target = next((item for item in pieces if item.name.startswith("target")), source)
        self.source = sentencepiece.SentencePieceProcessor(model_file=str(source))
        self.target = sentencepiece.SentencePieceProcessor(model_file=str(target))
        supported = ctranslate2.get_supported_compute_types("cpu")
        compute_type = "int8" if "int8" in supported else "float32"
        self.engine = ctranslate2.Translator(str(binaries[0].parent), device="cpu",
                                            compute_type=compute_type, intra_threads=threads,
                                            inter_threads=1)
        self.batch_size = batch_size
        self.beam_size = beam_size
        self.engine_kind = engine
        self.source_language = "zho_Hans" if source_language == "zh" else "eng_Latn"
        self.target_language = NLLB_LANGUAGES[target_locale]
        self.target_locale = target_locale
        self.cache_path = translation_cache.with_stem(translation_cache.stem + "_context_v4_b" + str(beam_size))
        self.segment_cache = catalog.read_json(self.cache_path)
        overrides = catalog.load_overrides()
        self.source_terms = {}
        for override_source, values in overrides.items():
            alias = override_source.replace("【", "").replace("】", "")
            if re.fullmatch(r"[\u3400-\u9fff]{2,12}", alias) and "en" in values and not catalog.signature(values["en"]):
                self.source_terms[alias] = values["en"]
            if "<" not in override_source and not catalog.signature(override_source) and target_locale in values:
                self.segment_cache[alias] = values[target_locale]
                if source_language == "en" and "en" in values:
                    self.segment_cache[values["en"]] = values[target_locale]
        self.source_term_pattern = re.compile("|".join(re.escape(term) for term in sorted(self.source_terms, key=len, reverse=True)))
        glossary = catalog.read_json(catalog.CATALOGS / "fragments.json")
        if target_locale in glossary.get("locales", []):
            index = glossary["locales"].index(target_locale)
            self.segment_cache.update({source: values[index] for source, values in glossary.get("messages", {}).items()})
            if source_language == "en" and "en" in glossary["locales"]:
                english_index = glossary["locales"].index("en")
                aliases = {}
                for _, values in sorted(glossary.get("messages", {}).items(), key=lambda item: len(item[0])):
                    alias = values[english_index].strip()
                    for variant in (alias, alias.lower(), alias.capitalize(), alias.title()):
                        aliases.setdefault(variant, values[index].strip())
                second = {
                    "ja": "秒", "ko": "초", "id": "detik", "th": "วินาที", "vi": "giây",
                    "de": "Sekunde", "fr": "seconde", "pt": "segundo", "es": "segundo", "ru": "сек.",
                }.get(target_locale)
                if second:
                    for variant in ("second", "Second", "SECOND"):
                        aliases[variant] = second
                        aliases[variant + "."] = second.rstrip(".") + "."
                    plural = {"de": "Sekunden", "fr": "secondes", "pt": "segundos", "es": "segundos"}.get(target_locale, second)
                    for variant in ("seconds", "Seconds", "SECONDS"):
                        aliases[variant] = plural
                        aliases[variant + "."] = plural.rstrip(".") + "."
                self.segment_cache.update(aliases)
        print(json.dumps({"engine": ctranslate2.__version__, "compute_type": compute_type,
                          "model": str(binaries[0].parent), "source_tokenizer": str(source),
                          "target_tokenizer": str(target)}, ensure_ascii=False), flush=True)

    def translate(self, texts):
        if self.engine_kind == "argos" and self.source_language == "zho_Hans" and self.target_locale == "en":
            texts = [self.source_term_pattern.sub(lambda match: " " + self.source_terms[match.group()] + " ", text)
                     for text in texts]
        encoded = [self.source.encode(text, out_type=str) for text in texts]
        if self.engine_kind == "nllb":
            encoded = [[self.source_language] + pieces + ["</s>"] for pieces in encoded]
        buckets = {}
        for index, pieces in enumerate(encoded):
            limit = next((size for size in (64, 128, 256, 512) if size >= len(pieces) * 4 + 16), 1024)
            buckets.setdefault(limit, []).append(index)
        decoded = [""] * len(encoded)
        for limit, indices in buckets.items():
            options = {}
            if self.engine_kind == "nllb":
                options["target_prefix"] = [[self.target_language] for _ in indices]
            results = self.engine.translate_batch([encoded[index] for index in indices], beam_size=self.beam_size,
                                                  max_batch_size=self.batch_size,
                                                  batch_type="examples", max_decoding_length=limit,
                                                  no_repeat_ngram_size=4, **options)
            for index, item in zip(indices, results):
                pieces = item.hypotheses[0]
                if self.engine_kind == "nllb" and pieces and pieces[0] == self.target_language:
                    pieces = pieces[1:]
                decoded[index] = self.target.decode(pieces).replace("\u2581", " ").strip()
        return decoded

    def translate_preserving(self, texts):
        # Keep ordinary values in context. Split them only if the engine changes
        # a number, percent sign, placeholder, or markup token.
        plain = [expand_static(source).replace("【", "").replace("】", "") for source in texts]
        if self.source_language == "eng_Latn":
            plain = [self.source_term_pattern.sub(lambda match: " " + self.source_terms[match.group()] + " ", value)
                     for value in plain]
        translated = [normalize_notation(source, target, self.target_locale)
                      for source, target in zip(plain, self.translate_fragments(plain, numbers=False))]
        retry = [index for index, (source, target) in enumerate(zip(plain, translated))
                 if not values_match(source, target) or catalog.validate(source, target, self.target_locale)
                 or replacement_characters(target)
                 or unexpected_script_characters(target, self.target_locale)]
        if retry:
            repaired = self.translate_fragments([plain[index] for index in retry], numbers=True)
            for index, value in zip(retry, repaired):
                translated[index] = normalize_notation(plain[index], value, self.target_locale)
        if self.target_locale == "en":
            repairs = {
                "暴击率": ["Crystal Chance", "Crisis Chance", "violent assault rate"],
                "暴击伤害": ["Crystal Damage"],
                "冷却": ["Coolown", "Courttown"],
                "斯卡蒂之怒": ["Skadi's Worth"],
                "惩戒光柱": ["Pilar of Retribution"],
            }
            for index, source in enumerate(plain):
                for term, variants in repairs.items():
                    if term in source and term in self.source_terms:
                        for variant in variants:
                            translated[index] = re.sub(re.escape(variant), self.source_terms[term], translated[index], flags=re.I)
        return translated

    def translate_fragments(self, texts, *, numbers):
        fragments = [immutable_fragments(source, numbers=numbers) for source in texts]
        pending = list(dict.fromkeys(
            value.strip()
            for sentence in fragments for value, protected in sentence
            if not protected and re.search(r"[A-Za-z\u3400-\u9fff]", value)
            and value.strip() not in self.segment_cache
        ))
        if pending:
            self.segment_cache.update(zip(pending, self.translate(pending)))
            catalog.write_json(self.cache_path, self.segment_cache)
        translated = []
        for sentence in fragments:
            parts = []
            for value, protected in sentence:
                if protected or not re.search(r"[A-Za-z\u3400-\u9fff]", value):
                    parts.append(value)
                    continue
                prefix = value[:len(value) - len(value.lstrip())]
                suffix = value[len(value.rstrip()):]
                target = self.segment_cache[value.strip()]
                parts.append(prefix + target + suffix)
            translated.append(self.join_fragments(parts))
        return translated

    def join_fragments(self, parts):
        if self.target_locale in ("zh_CN", "zh_TW", "ja"):
            return "".join(parts)
        result = ""
        previous = ""
        for part in parts:
            if part == "_":
                part = " _ "
            if result and part and not result[-1].isspace() and not part[0].isspace():
                previous_symbol = previous.startswith(("<#", "%", "&s", "{"))
                current_symbol = part.startswith(("<#", "%s", "%d", "%i", "&s", "{"))
                number_start = part[0].isdigit() or (len(part) > 1 and part[0] in "+-" and part[1].isdigit())
                if ((result[-1].isalpha() and (number_start or current_symbol))
                        or ((result[-1].isdigit() or previous_symbol or previous in ("%", "％", "‰"))
                            and part[0].isalpha())
                        or (previous.startswith("<#") and current_symbol)
                        or (result[-1] in ".!?;" and part[0].isalpha())):
                    result += " "
            result += part
            previous = part
        return result


def merged_catalog(locale):
    original, supplemental = catalog.load_catalogs(locale)
    result = {**original, **supplemental}
    result.update(catalog.read_json(catalog.CATALOGS / "reviewed" / (locale + ".json")))
    for source, translations in catalog.load_overrides().items():
        if locale in translations:
            result[source] = translations[locale]
    return original, supplemental, result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--engine", choices=("argos", "nllb"), default="argos")
    parser.add_argument("--from-language", choices=("zh", "en"), default="en")
    parser.add_argument("--locale", choices=catalog.LOCALES, required=True)
    parser.add_argument("--sources", type=Path, default=catalog.CATALOGS / "sources.json")
    parser.add_argument("--output-dir", type=Path, default=Path("/tmp/city-localization-mt-output"))
    parser.add_argument("--model-cache", type=Path, default=Path("/tmp/city-localization-mt-models"))
    parser.add_argument("--report-dir", type=Path, default=Path("/tmp/city-localization-mt-output"))
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--threads", type=int, default=6)
    parser.add_argument("--beam-size", type=int, default=4)
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--scripts-only", action="store_true")
    parser.add_argument("--replace-original", action="store_true",
                        help="Translate raw source again instead of trusting original source-only mappings")
    parser.add_argument("--rebuild", action="store_true",
                        help="Rebuild generated catalog entries while preserving manual overrides and translation caches")
    parser.add_argument("--refresh-existing", action="store_true",
                        help="Retranslate selected sources while keeping all other generated entries")
    args = parser.parse_args()
    if args.engine == "argos" and args.from_language == "zh" and args.locale != "en":
        raise SystemExit("Chinese input requires the zh_en package and --locale en")
    if args.from_language == "en" and args.locale in ("zh_CN", "zh_TW", "en"):
        raise SystemExit("English input requires an en_<target> package")
    if args.batch_size < 1 or args.threads < 1 or args.beam_size < 1:
        raise SystemExit("Batch size, thread count, and beam size must be positive")
    sources = catalog.read_json(args.sources)
    provenance_sources = {**catalog.read_json(catalog.CATALOGS / "sources.json"), **sources}
    catalog.write_json(catalog.CATALOGS / "static_sources.json", {
        "version": 1,
        "terms_source": "assets/data/DisplayTerms.json",
        "terms_sha256": hashlib.sha256((catalog.ROOT / "assets/data/DisplayTerms.json").read_bytes()).hexdigest(),
        "messages": {source: value for source in provenance_sources if (value := transformation(source))},
    })
    original, supplemental, existing = merged_catalog(args.locale)
    reviewed = catalog.read_json(catalog.CATALOGS / "reviewed" / (args.locale + ".json"))
    output_path = args.output_dir / (args.locale + ".json")
    output = {} if args.rebuild else catalog.read_json(output_path)
    output.update(reviewed)
    english = merged_catalog("en")[2]
    english.update(catalog.read_json(args.output_dir / "en.json"))
    pending, failures, missing_english, rejected_translations = [], {}, [], {}
    overrides = catalog.load_overrides()
    for source, paths in sorted(sources.items(), key=lambda item: (
            not any(path.startswith("scripts/") for path in item[1]), len(item[0]), item[0])):
        if args.scripts_only and not any(path.startswith("scripts/") for path in paths):
            continue
        current = existing.get(source, output.get(source, ""))
        strict = source in supplemental or source in output
        if args.locale in overrides.get(source, {}) or source in reviewed:
            continue
        if (not (args.rebuild or args.refresh_existing) and current and not (args.replace_original and source in original and source not in supplemental)
                and not catalog.validate(source, current, args.locale, strict_markup=strict)):
            continue
        input_text = source if args.from_language == "zh" else english.get(source, "")
        if not input_text or (args.from_language == "en" and catalog.validate(source, input_text, "en")):
            missing_english.append(source)
            continue
        pending.append((source, input_text))
    if args.limit:
        pending = pending[:args.limit]
    print(json.dumps({"pending": len(pending), "missing_english": len(missing_english),
                      "resumed_output": len(output), "output": str(output_path)},
                     ensure_ascii=False), flush=True)
    engine = OfflineTranslator(args.model, args.model_cache, args.threads, args.batch_size,
                               args.model_cache / "translation_cache" / (args.engine + "_" + args.from_language + "_" + args.locale + ".json"),
                               args.engine, args.from_language, args.locale, args.beam_size)
    started = time.monotonic()
    completed = 0
    for start in range(0, len(pending), args.batch_size):
        batch = pending[start:start + args.batch_size]
        translations = engine.translate_preserving([item[1] for item in batch])
        for (source, _), translated in zip(batch, translations):
            error = catalog.validate(source, translated, args.locale)
            if not error and not values_match(expand_static(source), translated):
                error = "numeric_value_mismatch"
            if not error and args.locale not in ("zh_CN", "zh_TW", "ja") and catalog.HAN.search(catalog.TOKEN.sub("", translated)):
                error = "residual_han"
            if not error and unexpected_script_characters(translated, args.locale):
                error = "unexpected_script"
            if not error and replacement_characters(translated):
                error = "replacement_character"
            if error:
                failures[source] = error
                rejected_translations[source] = translated
                output.pop(source, None)
                continue
            output[source] = translated
            completed += 1
        catalog.write_json(output_path, output)
        if (start + len(batch)) % 256 == 0 or start + len(batch) == len(pending):
            print(json.dumps({"locale": args.locale, "completed": completed, "attempted": start + len(batch),
                              "failed": len(failures), "seconds": round(time.monotonic() - started, 2)},
                             ensure_ascii=False), flush=True)
    report = {"locale": args.locale, "from_language": args.from_language,
              "completed": completed, "attempted": len(pending), "failures": failures,
              "rejected_translations": rejected_translations,
              "missing_english": missing_english,
              "seconds": round(time.monotonic() - started, 2),
              "sentences_per_second": round(completed / max(time.monotonic() - started, 0.001), 3),
              "output": str(output_path)}
    catalog.write_json(args.report_dir / (args.locale + "_report.json"), report)
    print(json.dumps({key: value for key, value in report.items()
                      if key not in ("missing_english", "failures", "rejected_translations")}, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
