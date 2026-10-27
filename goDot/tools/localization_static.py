#!/usr/bin/env python3
"""Expand display-only localization markup before translating natural copy."""

from __future__ import annotations

from functools import lru_cache
import json
from pathlib import Path
import re


TERMS_PATH = Path(__file__).resolve().parents[1] / "assets/data/DisplayTerms.json"
SPECINFO = re.compile(r"<#specinfo=[\"']?([^>\"']+)[\"']?>")
INLINE_LOCALIZATION = re.compile(r"<#LocalizationId=[\"']?([^>\"']+)[\"']?>(.*?)</LocalizationId>", re.DOTALL)
LOCALIZATION = re.compile(r"<#LocalizationId=[\"']?([^>\"']+)[\"']?>")
BREAK = re.compile(r"<br\s*/?>", re.IGNORECASE)
TAG = re.compile(r"<[^>]*>")


@lru_cache(maxsize=1)
def display_terms():
    return json.loads(TERMS_PATH.read_text(encoding="utf-8"))


@lru_cache(maxsize=None)
def transformation(source):
    if "<" not in source:
        return {}
    terms = display_terms()
    static_tokens = []
    visual_tokens = []

    def specinfo(match):
        value = terms.get("specinfo", {}).get(match.group(1))
        if not isinstance(value, str) or not value:
            return match.group()
        static_tokens.append(match.group())
        return value

    def inline(match):
        value = match.group(2)
        if not value:
            value = terms.get("localization", {}).get(match.group(1))
        if not isinstance(value, str) or not value:
            return match.group()
        static_tokens.append(match.group())
        return value

    def localization(match):
        value = terms.get("localization", {}).get(match.group(1))
        if not isinstance(value, str) or not value:
            return match.group()
        static_tokens.append(match.group())
        return value

    text = INLINE_LOCALIZATION.sub(inline, source)
    text = LOCALIZATION.sub(localization, text)
    text = SPECINFO.sub(specinfo, text)

    def line_break(match):
        visual_tokens.append(match.group())
        return "\n"

    text = BREAK.sub(line_break, text)

    def visual(match):
        token = match.group()
        if token.startswith("<#") or token == "</LocalizationId>":
            return token
        visual_tokens.append(token)
        return ""

    text = TAG.sub(visual, text)
    if text == source:
        return {}
    return {
        "plain": text,
        "static_tokens": static_tokens,
        "visual_tokens": visual_tokens,
        "dynamic_tokens": TAG.findall(text),
    }


def expand_static(source):
    return transformation(source).get("plain", source)
