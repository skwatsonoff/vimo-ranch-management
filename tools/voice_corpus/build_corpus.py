"""Builds assets/voice/voice_corpus.json: sentences VIMO must understand,
each with its expected intent and slots. Hand-written sentences in Tamil
script, Tanglish and English, multiplied over a few cow names and amounts.

Run from the repository root:  python3 tools/voice_corpus/build_corpus.py
The Flutter test test/voice_corpus_test.dart checks the pass rate.
"""
import json
import pathlib

COWS = ["Lakshmi", "Kaveri", "Gowri", "Rani"]
TAMIL = {"Lakshmi": "லட்சுமி", "Kaveri": "காவேரி", "Gowri": "கௌரி", "Rani": "ராணி"}
DATIVE = {"Lakshmi": "லட்சுமிக்கு", "Kaveri": "காவேரிக்கு", "Gowri": "கௌரிக்கு", "Rani": "ராணிக்கு"}

items = []


def add(text, intent, slots=None, lang="ta"):
    items.append({"text": text, "intent": intent, "slots": slots or {}, "lang": lang})


# --- milk entries ---------------------------------------------------------------
for cow in COWS:
    t, d = TAMIL[cow], DATIVE[cow]
    low = cow.lower()
    add(f"{t} 5 லிட்டர்", "milk_record", {"cow": cow, "liters": 5})
    add(f"{d} அஞ்சு லிட்டர் சேர்", "milk_record", {"cow": cow, "liters": 5})
    add(f"இன்று காலை {t} 8 லிட்டர் பால் கொடுத்தது", "milk_record",
        {"cow": cow, "liters": 8, "session": "Morning", "date": "today"})
    add(f"நேற்று மாலை {t} மாடு ரெண்டரை லிட்டர்", "milk_record",
        {"cow": cow, "liters": 2.5, "session": "Evening", "date": "yesterday"})
    add(f"{low} ku anju litre podu", "milk_record", {"cow": cow, "liters": 5}, "ta-Latn")
    add(f"{low} maadu 7 lit kuduthuchu", "milk_record", {"cow": cow, "liters": 7}, "ta-Latn")
    add(f"nethu kaalaila {low} 3.5 lit", "milk_record",
        {"cow": cow, "liters": 3.5, "session": "Morning", "date": "yesterday"}, "ta-Latn")
    add(f"add 6 litres for {cow}", "milk_record", {"cow": cow, "liters": 6}, "en")
    add(f"{cow} gave 4 litres of milk this evening", "milk_record",
        {"cow": cow, "liters": 4, "session": "Evening"}, "en")
    add(f"{cow} pathu litre", "milk_record", {"cow": cow, "liters": 10}, "ta-Latn")

# --- sales, corrections, removals, answers ----------------------------------------------
for text, liters, lang in [
    ("செல்விக்கு 2 லிட்டர் பால் விற்றேன்", 2, "ta"),
    ("ரவி 3 லிட்டர் பால் வாங்கினார்", 3, "ta"),
    ("murugan anna ku 4 litre koduthaen", 4, "ta-Latn"),
    ("selvikku 0.5 L paal kuduthen", 0.5, "ta-Latn"),
    ("sold 5 litres of milk to Kumar", 5, "en"),
    ("I gave Ravi 2 litres", 2, "en"),
]:
    add(text, "sell_milk", {"liters": liters}, lang)
for text, liters, lang in [
    ("5 இல்லை 6 லிட்டர்", 6, "ta"),
    ("9 illa 10 litre", 10, "ta-Latn"),
    ("not 3, 4 litres", 4, "en"),
    ("தவறு, 7 லிட்டர் என்று மாற்று", 7, "ta"),
]:
    add(text, "edit_last", {"liters": liters}, lang)
for text, lang in [("கடைசி பதிவை நீக்கு", "ta"), ("adha azhichidu", "ta-Latn"),
                   ("remove that", "en"), ("cancel", "en")]:
    add(text, "delete_last", {}, lang)
for text, lang in [("பால் கறந்து முடிச்சிட்டேன்", "ta"), ("mudinchu", "ta-Latn"),
                   ("finish", "en"), ("போதும்", "ta")]:
    add(text, "finish", {}, lang)
for text, lang in [("ஆமா", "ta"), ("சரி", "ta"), ("yes", "en"), ("aama", "ta-Latn")]:
    add(text, "yes", {}, lang)
for text, lang in [("வேண்டாம்", "ta"), ("illa", "ta-Latn"), ("no", "en")]:
    add(text, "no", {}, lang)
for text, lang in [("ஹே விமோ", "ta"), ("hey vimo", "en"), ("விமோ", "ta")]:
    add(text, "wake", {}, lang)

out = pathlib.Path(__file__).resolve().parents[2] / "assets" / "voice" / "voice_corpus.json"
out.write_text(json.dumps({"schema": 1, "cows": COWS, "utterances": items},
                          ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
print(f"{len(items)} utterances -> {out}")
