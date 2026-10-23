#!/usr/bin/env python3
"""Build the phase-1 app content bundle.

Merges the corpus in poems/articles with the authored learning content in
content/phase1-learning.json and writes
pumpkin-poems-app/Resources/PoemContent.json.

Quiz questions are generated here (not at runtime) so that question IDs,
option order and wording stay stable across app launches and script switches.

Usage (from the repository root):
    python3 pumpkin-poems-app/scripts/build_content.py
"""

from __future__ import annotations

import json
import random
import sys
from collections import Counter, defaultdict
from pathlib import Path

APP_ROOT = Path(__file__).resolve().parent.parent
REPO_ROOT = APP_ROOT.parent
ARTICLES = REPO_ROOT / "poems" / "articles"
LEARNING = APP_ROOT / "content" / "phase1-learning.json"
OUTPUT = APP_ROOT / "pumpkin-poems-app" / "Resources" / "PoemContent.json"

HANT, HANS = "zh-Hant", "zh-Hans"
TRAILING_PUNCTUATION = "，。？！；：、"


def pair(value: list[str]) -> dict[str, str]:
    if not (isinstance(value, list) and len(value) == 2 and all(isinstance(v, str) and v for v in value)):
        raise ValueError(f"expected [zh-Hant, zh-Hans] pair, got {value!r}")
    return {HANT: value[0], HANS: value[1]}


def fmt(template: tuple[str, str], **values: dict[str, str]) -> dict[str, str]:
    """Fill a (Hant, Hans) template with localized values."""
    return {
        HANT: template[0].format(**{k: v[HANT] for k, v in values.items()}),
        HANS: template[1].format(**{k: v[HANS] for k, v in values.items()}),
    }


def strip_line(text: dict[str, str]) -> dict[str, str]:
    return {k: v.rstrip(TRAILING_PUNCTUATION) for k, v in text.items()}


def is_han(ch: str) -> bool:
    cp = ord(ch)
    return 0x3400 <= cp <= 0x9FFF or 0xF900 <= cp <= 0xFAFF or 0x20000 <= cp <= 0x3134F


def shuffled(items: list, seed: str) -> list[int]:
    order = list(range(len(items)))
    random.Random(seed).shuffle(order)
    return order


def build_char_map(articles: list[dict]) -> dict[str, str]:
    """Hant -> Hans map from aligned corpus lines; most frequent mapping wins."""
    votes: dict[str, Counter] = defaultdict(Counter)
    for article in articles:
        texts = [line["text"] for line in article["lines"]] + [article["title"]]
        for text in texts:
            hant, hans = text[HANT], text[HANS]
            if len(hant) != len(hans):
                continue
            for a, b in zip(hant, hans):
                if a != b and is_han(a) and is_han(b):
                    votes[a][b] += 1
    return {a: counter.most_common(1)[0][0] for a, counter in sorted(votes.items())}


def build_questions(poem: dict, learning: dict, featured: list[dict]) -> list[dict]:
    pid = poem["id"]
    lines = poem["lines"]
    questions = []

    # 1. Comprehension question, authored (first option is the correct one).
    meaning = learning["meaning"]
    options = [pair(o) for o in meaning["options"]]
    order = shuffled(options, f"{pid}-meaning")
    questions.append({
        "id": f"{pid}-q-meaning",
        "kind": "meaning",
        "prompt": pair(meaning["prompt"]),
        "options": [options[i] for i in order],
        "answer": order.index(0),
        "explanation": pair(meaning["explanation"]),
    })

    # 2. Meaning match: pick the line that matches a plain-language explanation.
    target = learning["match_line"]
    options = [strip_line(line["text"]) for line in lines]
    order = shuffled(options, f"{pid}-match")
    explain = lines[target]["explain"]
    questions.append({
        "id": f"{pid}-q-match",
        "kind": "match",
        "prompt": fmt(("哪一句的意思是：「{e}」", "哪一句的意思是：“{e}”"), e=explain),
        "options": [options[i] for i in order],
        "answer": order.index(target),
        "explanation": fmt(("「{l}」的意思是：{e}", "“{l}”的意思是：{e}"), l=options[target], e=explain),
    })

    # 3. Keyword fill-in.
    fill = learning["fill"]
    line = strip_line(lines[fill["line"]]["text"])
    start, end = fill["range"]
    answer = {k: v[start:end] for k, v in line.items()}
    blank = {k: v[:start] + "＿" * (end - start) + v[end:] for k, v in line.items()}
    options = [answer] + [pair(d) for d in fill["distractors"]]
    for opt in options[1:]:
        if opt[HANS] == answer[HANS] or opt[HANT] == answer[HANT]:
            raise ValueError(f"{pid}: distractor {opt} equals the answer")
        if len(opt[HANT]) != end - start:
            raise ValueError(f"{pid}: distractor {opt} length differs from the blank")
    order = shuffled(options, f"{pid}-fill")
    questions.append({
        "id": f"{pid}-q-fill",
        "kind": "fill",
        "prompt": pair(["選出正確的字，補全詩句。", "选出正确的字，补全诗句。"]),
        "context": blank,
        "options": [options[i] for i in order],
        "answer": order.index(0),
        "explanation": pair(fill["explanation"]),
    })

    # 4. Next line: given an upper line, choose its lower line.
    rng = random.Random(f"{pid}-next")
    upper_index = rng.choice([i for i in range(0, len(lines) - 1, 2)])
    upper = strip_line(lines[upper_index]["text"])
    lower = strip_line(lines[upper_index + 1]["text"])
    pool = []
    for other in featured:
        if other["id"] == pid:
            continue
        for i, other_line in enumerate(other["lines"]):
            text = strip_line(other_line["text"])
            if i % 2 == 1 and len(text[HANS]) == len(lower[HANS]) and text[HANS] != lower[HANS]:
                pool.append(text)
    pool.sort(key=lambda t: t[HANS])
    options = [lower] + rng.sample(pool, 3)
    order = shuffled(options, f"{pid}-next-order")
    questions.append({
        "id": f"{pid}-q-next",
        "kind": "next",
        "prompt": fmt(("「{u}」的下一句是？", "“{u}”的下一句是？"), u=upper),
        "options": [options[i] for i in order],
        "answer": order.index(0),
        "explanation": fmt(("《{t}》中，「{u}」的下一句是「{l}」。", "《{t}》中，“{u}”的下一句是“{l}”。"),
                           t=poem["title"], u=upper, l=lower),
    })

    # 5. Line ordering. answerOrder lists option indices in the poem's order.
    options = [strip_line(line["text"]) for line in lines]
    seed = 0
    order = shuffled(options, f"{pid}-order")
    while order == sorted(order):
        seed += 1
        order = shuffled(options, f"{pid}-order-{seed}")
    full_text = {k: "".join(line["text"][k] for line in lines) for k in (HANT, HANS)}
    questions.append({
        "id": f"{pid}-q-order",
        "kind": "order",
        "prompt": pair(["把詩句排成正確的順序。", "把诗句排成正确的顺序。"]),
        "options": [options[i] for i in order],
        "answerOrder": [order.index(i) for i in range(len(options))],
        "explanation": fmt(("正確順序：{t}", "正确顺序：{t}"), t=full_text),
    })
    return questions


def build_poem(article: dict, learning: dict, featured: list[dict]) -> dict:
    pid = article["id"]
    authored_lines = learning["lines"]
    if len(authored_lines) != len(article["lines"]):
        raise ValueError(f"{pid}: {len(authored_lines)} authored lines vs {len(article['lines'])} corpus lines")

    lines = []
    for corpus_line, authored in zip(article["lines"], authored_lines):
        text = corpus_line["text"]
        if len(text[HANT]) != len(text[HANS]):
            raise ValueError(f"{corpus_line['id']}: Hant/Hans lengths differ")
        start, end = authored["keyword"]
        keyword = text[HANS][start:end]
        if not (0 <= start < end <= len(text[HANS])) or not all(is_han(c) for c in keyword):
            raise ValueError(f"{corpus_line['id']}: bad keyword range {authored['keyword']}")
        line = {
            "id": corpus_line["id"],
            "text": text,
            "keyword": [start, end],
            "explain": pair(authored["explain"]),
        }
        if "think" in authored:
            line["think"] = pair(authored["think"])
        lines.append(line)

    annotations = []
    for note in article["annotations"]:
        occurrences = {}
        for script in (HANT, HANS):
            spots = [
                {"lineID": o["line_id"], "start": o["start"], "end": o["end"]}
                for o in (note["occurrences"].get(script) or [])
                if o["scope"] == "body"
            ]
            occurrences[script] = spots
        if occurrences[HANT] or occurrences[HANS]:
            annotations.append({
                "id": note["id"],
                "term": note["term"],
                "definition": note["definition"],
                "occurrences": occurrences,
            })

    poem = {
        "id": pid,
        "theme": learning["theme"],
        "scene": learning["scene"],
        "keyStage": article["curriculum"]["key_stages"][0],
        "title": article["title"],
        "dynasty": article["dynasty"],
        "genre": article["genre"],
        "author": {
            "id": article["author_id"],
            "name": article["author"]["name"],
            "bio": article["author"]["biography"]["short"],
        },
        "tagline": pair(learning["tagline"]),
        "understanding": {k: pair(v) for k, v in learning["understanding"].items()},
        "lines": lines,
        "annotations": annotations,
    }
    poem["questions"] = build_questions(poem, learning, featured)
    return poem


def main() -> int:
    learning = json.loads(LEARNING.read_text(encoding="utf-8"))
    articles = [json.loads(p.read_text(encoding="utf-8")) for p in sorted(ARTICLES.glob("*.json"))]
    by_id = {a["id"]: a for a in articles}

    featured_articles = []
    for entry in learning["poems"]:
        if entry["id"] not in by_id:
            raise ValueError(f"unknown poem id {entry['id']}")
        featured_articles.append(by_id[entry["id"]])
    themes = {t["id"] for t in learning["themes"]}
    for entry in learning["poems"]:
        if entry["theme"] not in themes:
            raise ValueError(f"{entry['id']}: unknown theme {entry['theme']}")

    poems = [build_poem(a, entry, featured_articles) for a, entry in zip(featured_articles, learning["poems"])]

    char_map = build_char_map(articles)
    feihualing = [pair(c) for c in learning["feihualing"]]
    for c in feihualing:
        hits = sum(1 for p in poems for line in p["lines"] if c[HANS] in line["text"][HANS])
        if hits < 3:
            raise ValueError(f"飞花令 character {c[HANS]} only appears in {hits} lines")

    bundle = {
        "version": learning["version"],
        "themes": [
            {"id": t["id"], "name": pair(t["name"]), "badge": pair(t["badge"]), "summary": pair(t["summary"])}
            for t in learning["themes"]
        ],
        "feiHuaLing": feihualing,
        "poems": poems,
        "hantToHans": char_map,
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(bundle, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"wrote {OUTPUT.relative_to(REPO_ROOT)}: {len(poems)} poems, "
          f"{sum(len(p['questions']) for p in poems)} questions, {len(char_map)} char mappings")
    return 0


if __name__ == "__main__":
    sys.exit(main())
