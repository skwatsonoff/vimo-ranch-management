"""More text for the language model and the understanding model: dairy
sentences built from the ranch's own cow names and the owner's learned
words (the lexicon the app exports), in Tamil, Tanglish and English.

    python make_synthetic_text.py lexicon.json out.txt
"""
from __future__ import annotations

import itertools
import json
import sys

TA_NUMBERS = ["ஒன்று", "ரெண்டு", "மூணு", "நாலு", "அஞ்சு", "ஆறு", "ஏழு", "எட்டு", "பத்து", "ரெண்டரை", "ஒன்றரை", "அரை"]
LATIN_NUMBERS = ["onnu", "rendu", "moonu", "naalu", "anju", "aaru", "ezhu", "ettu", "pathu", "rendara", "onnara", "arai"]
EN_NUMBERS = ["one", "two", "three", "four", "five", "six", "seven", "eight", "ten", "two and a half", "one and a half", "half"]

TA_TEMPLATES = [
    "{cow} {n} லிட்டர்",
    "இன்று காலை {cow} {n} லிட்டர் பால் கொடுத்தது",
    "நேற்று மாலை {cow} மாடு {n} லிட்டர்",
    "{cow} மாட்டுக்கு ஊசி போட்டேன்",
    "{cow} சினை உறுதி ஆனது",
    "{cow} மாடு காய்ச்சல் அடிக்கிறது",
]
LATIN_TEMPLATES = [
    "{cow} ku {n} litre add pannu",
    "{cow} maadu {n} lit kuduthuchu",
    "nethu kaalaila {cow} {n} litre",
]
EN_TEMPLATES = [
    "add {n} litres for {cow}",
    "{cow} gave {n} litres of milk this evening",
    "how much milk did {cow} give this month",
]
GENERAL = [
    "கயிறு 150 ரூபாய் செலவு", "தவுடு 2 மூட்டை பயன்படுத்தினேன்", "வைக்கோல் 20 கட்டு வாங்கினேன்",
    "இன்று எவ்வளவு பால்", "5 இல்லை 6 லிட்டர்", "கடைசி பதிவை நீக்கு", "பால் கறந்து முடிச்சிட்டேன்",
    "petrol ku 200 rupaai selavu", "thavudu anju kilo potten", "innaiku ethana litre paal",
    "hey vimo", "ஹே விமோ", "mudinchu", "finish",
]


def sentences(lexicon: dict) -> list[str]:
    cows = lexicon.get("cows") or [{"name": "Lakshmi", "tamil": "லட்சுமி"}]
    out: list[str] = []
    for cow, (ta_n, lat_n, en_n) in itertools.product(cows, zip(TA_NUMBERS, LATIN_NUMBERS, EN_NUMBERS)):
        name = cow.get("name", "")
        tamil = cow.get("tamil") or name
        for t in TA_TEMPLATES:
            out.append(t.format(cow=tamil, n=ta_n))
        for t in LATIN_TEMPLATES:
            out.append(t.format(cow=name.lower(), n=lat_n))
        for t in EN_TEMPLATES:
            out.append(t.format(cow=name, n=en_n))
    out.extend(GENERAL)
    for row in lexicon.get("learned", []):
        if row.get("meant"):
            out.append(row["meant"])
    seen: set[str] = set()
    return [s for s in out if not (s in seen or seen.add(s))]


if __name__ == "__main__":
    lex = json.load(open(sys.argv[1], encoding="utf-8")) if len(sys.argv) > 1 else {}
    lines = sentences(lex)
    with open(sys.argv[2] if len(sys.argv) > 2 else "synthetic.txt", "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print(f"{len(lines)} sentences")
