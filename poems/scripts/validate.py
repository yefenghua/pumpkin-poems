#!/usr/bin/env python3
"""Validate the offline poetry corpus. Python 3 standard library only."""
import argparse
import collections
import json
import re
from pathlib import Path


LANGUAGES = ("zh-Hant", "zh-Hans")


def read(path):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"Duplicate JSON key: {key} in {path}")
            result[key] = value
        return result
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def bilingual(value, label, allow_empty=False):
    require(isinstance(value, dict) and set(value) == set(LANGUAGES), f"{label}: language keys")
    for lang in LANGUAGES:
        require(isinstance(value[lang], str), f"{label}: non-string {lang}")
        require(allow_empty or bool(value[lang].strip()), f"{label}: empty {lang}")
        require("\ufffd" not in value[lang], f"{label}: replacement character")


def expected_core_ids():
    suffixes = {
        1: [f"{i:02}" for i in range(3, 21)],
        2: [f"{i:02}" for i in range(6, 20)],
        3: ["05a", "05b", "08", "09", "10", "11a", "11b", "13", "17", "18", "19"],
        4: ["01", "11", "16a", "16b", "16c", "17a", "17b", "17c", "18a", "18b"],
    }
    return {f"hk-ks{stage}-{suffix}" for stage, values in suffixes.items() for suffix in values}


def validate(root):
    manifest = read(root / "manifest.json")
    catalog = read(root / "sources/hk-core-catalog.json")
    baseline_rows = read(root / "sources/text-baselines.json")["entries"]
    baselines = {r["article_id"]: r for r in baseline_rows}
    require(len(baselines) == len(baseline_rows), "Duplicate baseline ID")
    authors, articles = {}, {}
    for path in sorted((root / "author").glob("*.json")):
        author = read(path)
        aid = author["id"]
        require(path.stem == aid and aid not in authors, f"Author filename/ID: {path}")
        require(author["schema_version"] == "1.0.0", f"Author schema: {aid}")
        for field in ("name", "catalog_name", "dynasty"):
            bilingual(author[field], f"{aid}.{field}")
        for size in ("short", "full"):
            bilingual(author["biography"][size], f"{aid}.biography.{size}")
        for lang in LANGUAGES:
            require(len(author["biography"]["full"][lang]) >= 120, f"Full biography too short: {aid}")
            require(len(author["biography"]["short"][lang]) < len(author["biography"]["full"][lang]), f"Biography lengths: {aid}")
        require(bool(author["sources"]), f"Author sources absent: {aid}")
        authors[aid] = author

    fingerprints = {}
    all_segment_ids, all_word_ids = set(), set()
    for path in sorted((root / "articles").glob("*.json")):
        a = read(path)
        pid = a["id"]
        require(path.stem == pid and pid not in articles, f"Article filename/ID: {path}")
        require(a["schema_version"] == "1.0.0", f"Article schema: {pid}")
        require(a["category"] in ("core", "extension"), f"Category: {pid}")
        require(a["priority"] == ("P0" if a["category"] == "core" else "P1"), f"Priority: {pid}")
        for field in ("title", "dynasty", "genre", "text"):
            bilingual(a[field], f"{pid}.{field}")
        bilingual(a["preface"], f"{pid}.preface", allow_empty=True)
        for note in a["edition_notes"]:
            bilingual(note, f"{pid}.edition_notes")
        require(a["author_id"] in authors, f"Unknown author: {pid}")
        require(a["author"] == authors[a["author_id"]], f"Stale embedded author: {pid}")
        require((path.parent / a["author_file"]).resolve() == (root / "author" / f"{a['author_id']}.json").resolve(), f"Author path: {pid}")
        require(pid in baselines, f"Missing baseline: {pid}")
        b = baselines[pid]
        for lang in LANGUAGES:
            require(a["text"][lang] == b["accepted_text_" + lang.replace("-", "_")], f"Text changed from verified baseline: {pid}/{lang}")
            require("[" not in a["text"][lang] and "□" not in a["text"][lang], f"Unresolved textual placeholder: {pid}")
        if a["category"] == "core":
            require(a["text"]["zh-Hant"] == b["source_text_zh_Hant"], f"Core text deviates from EDB: {pid}")
            require(a["preface"]["zh-Hant"] == b["preface_zh_Hant"], f"Core preface differs: {pid}")
            require(a["curriculum"]["key_stages"] == [int(pid[5])], f"Stage: {pid}")
        else:
            require(a["curriculum"] is None, f"Extension falsely mapped to curriculum: {pid}")
        require(any(s["kind"] == "text" for s in a["sources"]), f"No text source: {pid}")
        for source in a["sources"]:
            require(source["url"].startswith("https://"), f"Source URL: {pid}")
            bilingual(source["label"], f"{pid}.source.label")
        line_map = {}
        for line in a["lines"]:
            lid = line["id"]
            require(lid not in all_segment_ids, f"Duplicate segment ID: {lid}")
            all_segment_ids.add(lid)
            bilingual(line["text"], lid)
            line_map[lid] = line["text"]
        for lang in LANGUAGES:
            require("".join(line["text"][lang] for line in a["lines"]) == a["text"][lang], f"Missing or duplicated segment: {pid}/{lang}")
        require(len(a["annotations"]) >= 3, f"Too few contextual words: {pid}")
        for word in a["annotations"]:
            wid = word["id"]
            require(wid not in all_word_ids, f"Duplicate annotation ID: {wid}")
            all_word_ids.add(wid)
            bilingual(word["term"], wid)
            bilingual(word["definition"], wid)
            for lang in LANGUAGES:
                require(bool(word["occurrences"][lang]), f"Missing word anchor: {wid}/{lang}")
                for occurrence in word["occurrences"][lang]:
                    scope = occurrence["scope"]
                    require(scope in ("body", "title", "preface"), f"Invalid scope: {wid}")
                    text = line_map[occurrence["line_id"]][lang] if scope == "body" else a[scope][lang]
                    start, end = occurrence["start"], occurrence["end"]
                    require(isinstance(start, int) and isinstance(end, int) and 0 <= start < end <= len(text), f"Offset bounds: {wid}")
                    require(text[start:end] == word["term"][lang], f"Wrong word location: {wid}/{lang}")
        fingerprint = re.sub(r"[^\u3400-\u9fff]", "", a["text"]["zh-Hans"])
        require(fingerprint not in fingerprints, f"Duplicate work: {pid} and {fingerprints.get(fingerprint)}")
        fingerprints[fingerprint] = pid
        articles[pid] = a

    require(set(baselines) == set(articles), "Extra/missing text baselines")
    core = {pid for pid, a in articles.items() if a["category"] == "core"}
    require(core == expected_core_ids(), f"Core coverage: missing {expected_core_ids() - core}, extra {core - expected_core_ids()}")
    require({r["article_id"] for r in catalog["entries"]} == core, "Core catalog mismatch")
    require(len(catalog["entries"]) == catalog["expected_count"] == 53, "Core catalog count")
    require(len(articles) - len(core) > 100, "Extension must contain more than 100 works")
    require({r["id"] for r in manifest["articles"]} == set(articles), "Article manifest mismatch")
    require({r["id"] for r in manifest["authors"]} == set(authors), "Author manifest mismatch")
    require({a["author_id"] for a in articles.values()} == set(authors), "Orphan author record")
    for row in manifest["articles"]:
        require(row["file"] == f"articles/{row['id']}.json", "Manifest article path")
        require(row["title"] == articles[row["id"]]["title"], "Manifest title mismatch")
        require(row["category"] == articles[row["id"]]["category"], "Manifest category mismatch")
    counts = {"articles": len(articles), "core": len(core), "extension": len(articles) - len(core), "authors": len(authors), "annotations": len(all_word_ids)}
    require(counts == manifest["counts"], "Manifest totals")
    stages = dict(collections.Counter(str(a["curriculum"]["key_stages"][0]) for a in articles.values() if a["category"] == "core"))
    require(stages == manifest["core_by_stage"] == {"1": 18, "2": 14, "3": 11, "4": 10}, "Stage totals")
    require(dict(collections.Counter(a["dynasty"]["zh-Hans"] for a in articles.values())) == manifest["by_dynasty"], "Dynasty totals")
    return {"status": "passed", **counts, "segments": len(all_segment_ids), "checks": ["53 EDB core works", "more than 100 extension works", "bilingual field completeness", "source text baselines", "aligned reading segments", "exact word offsets in both scripts", "author references and embedded profiles", "duplicate work detection", "manifest totals"]}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--report", type=Path, help="Optionally save a validation report")
    args = parser.parse_args()
    try:
        report = validate(args.root)
    except (ValueError, KeyError, TypeError, OSError) as error:
        parser.exit(1, f"FAILED: {error}\n")
    output = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.report:
        args.report.write_text(output, encoding="utf-8")
    print(output, end="")
