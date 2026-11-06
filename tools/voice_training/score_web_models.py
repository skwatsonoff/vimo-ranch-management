"""Scores what each model heard against what was read (counts only).

    python score_web_models.py <lexicon.json> <name>=<heard.jsonl> ...

Prints, per model, the share of words heard right (by sound, so Tamil
letters and Tanglish compare fairly) and of cow names heard right, and
writes scores.json for the app's model list.
"""
from __future__ import annotations

import json
import pathlib
import sys

from learn_lessons import cow_spellings, similar, tokens


def word_accuracy(ref: list[str], hyp: list[str]) -> float:
    n, m = len(ref), len(hyp)
    d = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(n + 1):
        d[i][0] = i
    for j in range(m + 1):
        d[0][j] = j
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            same = similar(ref[i - 1], hyp[j - 1]) >= 0.75
            d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (0 if same else 1))
    return max(0.0, 1 - d[n][m] / max(1, n))


def cow_heard(ref: str, hyp: str, cows: list[dict]) -> bool | None:
    rt, ht = tokens(ref), tokens(hyp)
    for cow in cows:
        for spelling in cow_spellings(cow):
            if any(rt[i : i + len(spelling)] == spelling for i in range(len(rt))):
                joined = " ".join(spelling)
                return any(similar(joined, " ".join(ht[i : i + len(spelling)])) >= 0.75 for i in range(len(ht)))
    return None


def main(lexicon: str, pairs: list[str]) -> None:
    cows = [c for c in json.loads(pathlib.Path(lexicon).read_text(encoding="utf-8")).get("cows", []) if c.get("name")]
    scores = {}
    for pair in pairs:
        name, path = pair.split("=", 1)
        rows = [json.loads(l) for l in pathlib.Path(path).read_text(encoding="utf-8").splitlines() if l.strip()]
        by_lang: dict[str, list[float]] = {}
        cow_hits = []
        for r in rows:
            by_lang.setdefault(r["lang"], []).append(word_accuracy(tokens(r["ref"]), tokens(r["asr"])))
            hit = cow_heard(r["ref"], r["asr"], cows)
            if hit is not None:
                cow_hits.append(hit)
        scores[name] = {
            "recordings": len(rows),
            "words": {k: round(sum(v) / len(v), 3) for k, v in by_lang.items()},
            "cowNames": round(sum(cow_hits) / max(1, len(cow_hits)), 3),
        }
        print(name, json.dumps(scores[name]))
    pathlib.Path("scores.json").write_text(json.dumps(scores, indent=1))


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2:])
