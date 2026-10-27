#!/usr/bin/env python3
"""Check effective locale catalogs without loading a translation model.

Run from any directory with Python 3.10 or newer. The JSON report records
strict failures and source drift; the exit status is nonzero if either exists.
This checks structural correctness, not native linguistic quality.
"""

from __future__ import annotations

import argparse
from collections import Counter
import json
from pathlib import Path

import complete_localization as catalog
from localization_static import expand_static
from translate_localization_offline import unexpected_script_characters, values_match


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--locale", action="append", choices=catalog.LOCALES)
    parser.add_argument("--report", type=Path, default=catalog.CATALOGS / "quality_report.json")
    parser.add_argument("--subset", type=Path, help="Write sources needing translation repair")
    args = parser.parse_args()
    sources = catalog.collect_sources()
    recorded = catalog.read_json(catalog.CATALOGS / "sources.json")
    drift = {
        "added": sorted(sources.keys() - recorded.keys()),
        "removed": sorted(recorded.keys() - sources.keys()),
        "changed_paths": sorted(source for source in sources.keys() & recorded.keys()
                                if sources[source] != recorded[source]),
    }
    report = {
        "version": 1,
        "source_count": len(sources),
        "recorded_source_count": len(recorded),
        "source_drift": drift,
        "checks": ["nonempty", "placeholders_and_markup", "printf_order", "numeric_values",
                   "percent_symbols", "residual_han", "unexpected_script", "replacement_characters",
                   "unexpected_control_characters", "reviewed_supplemental_sync"],
        "locales": {},
    }
    repair_sources = set()
    unsynced_locales = []
    overrides = catalog.load_overrides()
    for locale in args.locale or catalog.LOCALES:
        original, supplemental = catalog.load_catalogs(locale)
        messages = {**original, **supplemental}
        for source, targets in overrides.items():
            if locale in targets:
                messages[source] = targets[locale]
        reviewed = catalog.read_json(catalog.CATALOGS / "reviewed" / (locale + ".json"))
        unsynced = {source: {"reviewed": target, "supplemental": supplemental.get(source, "")}
                    for source, target in reviewed.items() if target != supplemental.get(source)}
        if unsynced:
            unsynced_locales.append(locale)
        failures = {}
        for source in sources:
            target = source if locale == "zh_CN" else messages.get(source, "")
            error = catalog.validate(source, target, locale)
            if not error and not values_match(expand_static(source), target):
                error = "numeric_or_percent_mismatch"
            if not error and locale not in ("zh_CN", "zh_TW", "ja") and catalog.HAN.search(catalog.TOKEN.sub("", target)):
                error = "residual_han"
            if not error and unexpected_script_characters(target, locale):
                error = "unexpected_script"
            if error:
                failures[source] = {"error": error, "target": target}
        repair_sources.update(failures)
        reasons = dict(sorted(Counter(value["error"] for value in failures.values()).items()))
        summary = {"translated": len(sources) - len(failures), "issues": len(failures),
                   "reviewed_sync_issues": len(unsynced), "reasons": reasons}
        report["locales"][locale] = {**summary, "failures": failures, "reviewed_unsynced": unsynced}
        print(json.dumps({"locale": locale, **summary}, ensure_ascii=False))
    catalog.write_json(args.report, report)
    if args.subset:
        catalog.write_json(args.subset, {source: sources[source] for source in sorted(repair_sources)})
    print(json.dumps({"source_count": len(sources), "source_drift": {key: len(value) for key, value in drift.items()},
                      "report": str(args.report)}, ensure_ascii=False))
    return 1 if repair_sources or unsynced_locales or any(drift.values()) else 0


if __name__ == "__main__":
    raise SystemExit(main())
