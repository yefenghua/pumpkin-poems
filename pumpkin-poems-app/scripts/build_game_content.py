#!/usr/bin/env python3
"""Build source-attributed five/seven-character game material from the local corpus.
No new poems or text conversions are invented. Lesson content remains separate.
"""
import json
from pathlib import Path
from build_content import build_char_map, is_han, HANT, HANS

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "pumpkin-poems-app"
OUTPUT = APP / "pumpkin-poems-app/Resources/GameContent.json"


def build():
    articles = [json.loads(p.read_text()) for p in sorted((ROOT / "poems/articles").glob("*.json"))]
    featured = {p["id"] for p in json.loads((APP / "pumpkin-poems-app/Resources/PoemContent.json").read_text())["poems"]}
    mapping = build_char_map(articles)
    normalize = lambda text: "".join(mapping.get(c, c) for c in text if is_han(c))
    verses, seen = [], set()
    for article in articles:
        lines = article["lines"]
        for i, line in enumerate(lines):
            text = {s: "".join(c for c in line["text"][s] if is_han(c)) for s in (HANT, HANS)}
            if len(text[HANS]) not in (5, 7) or len(text[HANT]) != len(text[HANS]):
                continue
            # Omit ambiguous script alignments instead of silently changing a source text.
            if normalize(text[HANT]) != normalize(text[HANS]):
                continue
            key = normalize(text[HANS])
            if key in seen:
                continue
            seen.add(key)
            j = i + 1 if i % 2 == 0 else i - 1
            companion = lines[j]["text"] if 0 <= j < len(lines) else None
            verses.append(dict(id=line["id"], poemID=article["id"], title=article["title"],
                               author=article["author"]["name"], text=text, companion=companion,
                               hasLearningPage=article["id"] in featured))
    # Keep well-known authored lessons first for guided games; randomized games shuffle at runtime.
    verses.sort(key=lambda v: (not v["hasLearningPage"], v["poemID"], v["id"]))
    assert len(verses) > 100
    assert len({v["id"] for v in verses}) == len(verses)
    included = {v["poemID"] for v in verses}
    lengths = {pid: sorted({len(v["text"][HANS]) for v in verses if v["poemID"] == pid}) for pid in included}
    poems = [dict(id=a["id"], title=a["title"], author=a["author"]["name"], authorID=a["author_id"],
                  genre=a["genre"], dynasty=a["dynasty"],
                  keyStages=sorted(set((a.get("curriculum") or {}).get("key_stages", []))),
                  lineLengths=lengths[a["id"]], hasLearningPage=a["id"] in featured)
             for a in articles if a["id"] in included]
    poems.sort(key=lambda p: (not p["hasLearningPage"], p["id"]))
    assert len({p["id"] for p in poems}) == len(poems)
    assert all(all(stage in (1, 2, 3, 4) for stage in p["keyStages"]) for p in poems)
    content = dict(version="games-2026-11-14-libraries", verses=verses, poems=poems, hantToHans=mapping)
    OUTPUT.write_text(json.dumps(content, ensure_ascii=False, indent=2) + "\n")
    print(f"Built {len(verses)} game lines from {len({v['poemID'] for v in verses})} poems: "
          f"{sum(len(v['text'][HANS]) == 5 for v in verses)} five-character, "
          f"{sum(len(v['text'][HANS]) == 7 for v in verses)} seven-character.")

if __name__ == "__main__":
    build()
