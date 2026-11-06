"""Word error rate: how many words the model got wrong, out of all words.

0.0 is perfect, 0.25 means one word in four is wrong. Used to decide
whether a new model is better than the one before (it must be, to be
offered on the phone).

    python evaluate_wer.py refs.txt hyps.txt
"""
from __future__ import annotations

import sys

from common import normalise_text


def edit_distance(a: list[str], b: list[str]) -> int:
    prev = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        cur = [i] + [0] * len(b)
        for j, y in enumerate(b, 1):
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x != y))
        prev = cur
    return prev[-1]


def wer(references: list[str], hypotheses: list[str]) -> float:
    if len(references) != len(hypotheses):
        raise ValueError("references and hypotheses differ in length")
    errors = words = 0
    for ref, hyp in zip(references, hypotheses):
        r = normalise_text(ref).split()
        h = normalise_text(hyp).split()
        errors += edit_distance(r, h)
        words += len(r)
    return errors / words if words else 0.0


if __name__ == "__main__":
    refs = open(sys.argv[1], encoding="utf-8").read().splitlines()
    hyps = open(sys.argv[2], encoding="utf-8").read().splitlines()
    print(f"{wer(refs, hyps):.4f}")
