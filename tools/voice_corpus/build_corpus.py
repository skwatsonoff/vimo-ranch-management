"""Builds assets/voice/voice_corpus.json: sentences VIMO must understand,
each with its expected intent and slots. Hand-written sentences in Tamil
script, Tanglish and English, multiplied over a few cow names and amounts.

Run from the repository root:  python3 tools/voice_corpus/build_corpus.py
The Flutter test test/voice_corpus_test.dart checks the pass rate.
"""
import json
import pathlib

COWS = ["Lakshmi", "Kaveri", "Gowri", "Rani", "Ponni", "Sivappi"]
TAMIL = {"Lakshmi": "லட்சுமி", "Kaveri": "காவேரி", "Gowri": "கௌரி", "Rani": "ராணி",
         "Ponni": "பொன்னி", "Sivappi": "சிவப்பி"}
DATIVE = {"Lakshmi": "லட்சுமிக்கு", "Kaveri": "காவேரிக்கு", "Gowri": "கௌரிக்கு",
          "Rani": "ராணிக்கு", "Ponni": "பொன்னிக்கு", "Sivappi": "சிவப்பிக்கு"}

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


# --- ranch work beyond milk -----------------------------------------------------------
for cow in COWS:
    t, d, low = TAMIL[cow], DATIVE[cow], cow.lower()
    add(f"{d} ஊசி போட்டேன்", "vaccination", {"cow": cow})
    add(f"{low} maaduku oosi pottom", "vaccination", {"cow": cow}, "ta-Latn")
    add(f"vaccinated {cow} yesterday", "vaccination", {"cow": cow}, "en")
    add(f"{d} கோமாரி தடுப்பூசி போட்டேன்", "vaccination", {"cow": cow, "vaccine": "fmd"})
    add(f"{t} சினை உறுதி ஆனது", "pregnancy_confirmed", {"cow": cow})
    add(f"{low} sinaiya irukku urudhi", "pregnancy_confirmed", {"cow": cow}, "ta-Latn")
    add(f"{d} செயற்கை கருவூட்டல் செய்தோம்", "insemination", {"cow": cow})
    add(f"{low}ku karuvootal pannen", "insemination", {"cow": cow}, "ta-Latn")
    add(f"{t} பெண் கன்று ஈன்றது", "calf_birth", {"cow": cow, "gender": "female"})
    add(f"{cow} gave birth to a male calf today", "calf_birth", {"cow": cow, "gender": "male"}, "en")
    add(f"{low} kanru pottuchu", "calf_birth", {"cow": cow}, "ta-Latn")
    add(f"{t} மாடு காய்ச்சல் அடிக்கிறது", "symptom", {"cow": cow})
    add(f"{low} maadu nondukuthu", "symptom", {"cow": cow}, "ta-Latn")
    add(f"{cow} is coughing today", "symptom", {"cow": cow}, "en")
    add(f"{t} மாட்டுக்கு மடிவீக்கம் என்று டாக்டர் சொன்னார்", "diagnosis", {"cow": cow, "disease": "mastitis"})
    add(f"doctor said {cow} has bloat", "diagnosis", {"cow": cow, "disease": "bloat"}, "en")
    add(f"இன்று {d} டாக்டர் வந்தார் 500 ரூபாய்", "vet_visit", {"cow": cow, "fee": 500})
    add(f"doctor checked {cow} paid 300 rupees", "vet_visit", {"cow": cow, "fee": 300}, "en")
    add(f"{low} maaduva 30000 rupaaiku vitten", "sell_cow", {"cow": cow, "amount": 30000}, "ta-Latn")
    add(f"இன்று {t} மாட்டை 25000 ரூபாய்க்கு விற்றேன்", "sell_cow", {"cow": cow, "amount": 25000})
    add(f"இன்று {t} எவ்வளவு பால் கொடுத்தது", "query", {"metric": "milk", "cow": cow})

for name, lang in [("luna", "ta-Latn"), ("komathi", "ta-Latn")]:
    add(f"{name} nu pudhu maadu vaangunom", "add_cow", {"name": name}, lang)
    add(f"{name} nu oru pudhu maadu vaanginen 40000 rupaai", "add_cow", {"name": name, "amount": 40000}, lang)
add("புதிய மாடு மாதவி வாங்கினேன்", "add_cow", {"name": "மாதவி"})
add("புதிய HF மாடு ராணி சேர்த்தேன்", "add_cow", {"breed": "hf"})
add("added new Jersey cow Karuppi", "add_cow", {"name": "karuppi", "breed": "jersey"}, "en")
add("bought a new cow Bhavani for 50000 rupees", "add_cow", {"amount": 50000}, "en")
add("pudhu jersey maadu vaangunom", "add_cow", {"breed": "jersey"}, "ta-Latn")

for text, slots, lang in [
    ("கயிறு 150 ரூபாய் செலவு", {"amount": 150}, "ta"),
    ("இன்று பெட்ரோல் 300 ரூபாய்", {"amount": 300}, "ta"),
    ("petrol ku 200 rupaai selavu", {"amount": 200}, "ta-Latn"),
    ("kayiru vaanga 120 rs", {"amount": 120}, "ta-Latn"),
    ("current bill 450 rs", {"amount": 450}, "en"),
    ("spent 600 rupees on diesel", {"amount": 600}, "en"),
    ("ஆள் கூலி 500 ரூபாய் கொடுத்தேன்", {"amount": 500}, "ta"),
    ("மருந்து 250 ரூபாய் செலவு", {"amount": 250}, "ta"),
    ("water bill 100 rupees", {"amount": 100}, "en"),
    ("வைக்கோல் கூலி 300 ரூபாய்", {"amount": 300}, "ta"),
    ("nethu marundhu 80 rupaai", {"amount": 80, "date": "yesterday"}, "ta-Latn"),
    ("repair ku 1000 rupaai selavu", {"amount": 1000}, "ta-Latn"),
]:
    add(text, "expense", slots, lang)

for text, intent, slots, lang in [
    ("தவுடு 2 மூட்டை பயன்படுத்தினேன்", "stock_use", {"item": "thavudu", "qty": 2}, "ta"),
    ("மாட்டுக்கு வைக்கோல் 10 கட்டு கொடுத்தேன்", "stock_use", {"item": "vaikol", "qty": 10}, "ta"),
    ("thavudu 5 kg potten", "stock_use", {"item": "thavudu", "qty": 5}, "ta-Latn"),
    ("vaikol 3 kattu kuduthen", "stock_use", {"item": "vaikol", "qty": 3}, "ta-Latn"),
    ("used 4 bags of bran today", "stock_use", {"item": "thavudu", "qty": 4}, "en"),
    ("fed 12 kg of hay", "stock_use", {"item": "vaikol", "qty": 12}, "en"),
    ("தவுடு 20 கிலோ வாங்கினேன்", "stock_in", {"item": "thavudu", "qty": 20}, "ta"),
    ("வைக்கோல் 50 கட்டு வாங்கினோம்", "stock_in", {"item": "vaikol", "qty": 50}, "ta"),
    ("thavudu 16 moottai vaanginen", "stock_in", {"item": "thavudu", "qty": 16}, "ta-Latn"),
    ("bought 25 kg of hay today", "stock_in", {"item": "vaikol", "qty": 25}, "en"),
    ("hay stock came today", "stock_in", {"item": "vaikol"}, "en"),
    ("murugan 500 rupaai kuduthaaru", "payment", {"amount": 500}, "ta-Latn"),
    ("கண்ணன் 200 ரூபாய் பணம் கொடுத்தார்", "payment", {"amount": 200}, "ta"),
    ("received 1000 rupees from Ram", "payment", {"amount": 1000}, "en"),
    ("ravi kitta 300 ruba vaanginen", "payment", {"amount": 300}, "ta-Latn"),
    ("இன்று எவ்வளவு பால்?", "query", {"metric": "milk", "range": "today"}, "ta"),
    ("இந்த மாதம் மொத்தம் எவ்வளவு பால்", "query", {"metric": "milk", "range": "this_month"}, "ta"),
    ("innaiku ethana litre paal", "query", {"metric": "milk", "range": "today"}, "ta-Latn"),
    ("how much milk this month", "query", {"metric": "milk", "range": "this_month"}, "en"),
    ("நேற்று எவ்வளவு பால் விற்றோம்", "query", {"metric": "milk_sold", "range": "yesterday"}, "ta"),
    ("today how much milk sold", "query", {"metric": "milk_sold"}, "en"),
    ("ரவி இதுவரை எவ்வளவு பால் வாங்கினார்", "query", {"metric": "milk_sold", "range": "all"}, "ta"),
    ("தவுடு எவ்வளவு இருக்கு", "query", {"metric": "stock", "item": "thavudu"}, "ta"),
    ("vaikol evlo irukku", "query", {"metric": "stock", "item": "vaikol"}, "ta-Latn"),
    ("how much bran is left", "query", {"metric": "stock", "item": "thavudu"}, "en"),
    ("எத்தனை கன்று இருக்கு", "query", {"metric": "calf_count"}, "ta"),
    ("how many cows do I have", "query", {"metric": "cow_count"}, "en"),
    ("இந்த மாதம் செலவு எவ்வளவு", "query", {"metric": "expense", "range": "this_month"}, "ta"),
    ("profit this week", "query", {"metric": "profit", "range": "this_week"}, "en"),
    ("இந்த மாதம் பால் வரலாறு காட்டு", "history", {"metric": "milk", "range": "this_month"}, "ta"),
    ("inniki paal pathivugal kaattu", "history", {"metric": "milk", "range": "today"}, "ta-Latn"),
    ("show milk records yesterday", "history", {"metric": "milk", "range": "yesterday"}, "en"),
    ("நாளை லட்சுமிக்கு ஊசி போட வேண்டும்", "unknown", {}, "ta"),
    ("remind me to vaccinate Rani tomorrow", "unknown", {}, "en"),
    ("இன்று மழை வருமா", "unknown", {}, "ta"),
    ("hello", "unknown", {}, "en"),
]:
    add(text, intent, slots, lang)


# --- more ways to say milk, numbers in words --------------------------------------------
for cow in COWS:
    t, d, low = TAMIL[cow], DATIVE[cow], cow.lower()
    add(f"{t} முக்கால் லிட்டர்", "milk_record", {"cow": cow, "liters": 0.75})
    add(f"{low} irubathi anju litre", "milk_record", {"cow": cow, "liters": 25}, "ta-Latn")
    add(f"{cow} twelve litres", "milk_record", {"cow": cow, "liters": 12}, "en")
    add(f"மாலை {d} ஒன்றரை லிட்டர் போடு", "milk_record",
        {"cow": cow, "liters": 1.5, "session": "Evening"})
for text, intent, slots, lang in [
    ("ஹே விமோ லட்சுமிக்கு 5 லிட்டர்", "milk_record", {"cow": "Lakshmi", "liters": 5}, "ta"),
    ("hey vimo rani 4 litre", "milk_record", {"cow": "Rani", "liters": 4}, "en"),
    ("vimo kaveri ku moonu litre", "milk_record", {"cow": "Kaveri", "liters": 3}, "ta-Latn"),
    ("பொன்னி 5 லிட்டர் பால் கறந்தேன்", "milk_record", {"cow": "Ponni", "liters": 5}, "ta"),
    ("gowri maadu paththu litre kuduthaa", "milk_record", {"cow": "Gowri", "liters": 10}, "ta-Latn"),
    ("Lakshmi ko paanch litre", "milk_record", {"cow": "Lakshmi", "liters": 5}, "hi-Latn"),
    ("சிவப்பி ஏழு லிட்டர் கொடுத்தாள்", "milk_record", {"cow": "Sivappi", "liters": 7}, "ta"),
    ("ரவிக்கு அரை லிட்டர் பால் விற்பனை", "sell_milk", {"liters": 0.5}, "ta"),
    ("today evening Ravi bought 2 litres milk", "sell_milk", {"liters": 2}, "en"),
    ("selvi akka ku 6 lit koduthaen", "sell_milk", {"liters": 6}, "ta-Latn"),
    ("13 illa 2 litre", "edit_last", {"liters": 2}, "ta-Latn"),
    ("150 இல்லை 250 ரூபாய்", "edit_last", {"amount": 250}, "ta"),
    ("thappu, 2 litre nu maathu", "edit_last", {"liters": 2}, "ta-Latn"),
    ("அதை நீக்கு", "delete_last", {}, "ta"),
    ("ippo potta pathivai azhi", "delete_last", {}, "ta-Latn"),
    ("முடிஞ்சது", "finish", {}, "ta"),
    ("done", "finish", {}, "en"),
    ("ஆமாம்", "yes", {}, "ta"),
    ("ok", "yes", {}, "en"),
    ("இல்லை", "no", {}, "ta"),
]:
    add(text, intent, slots, lang)

out = pathlib.Path(__file__).resolve().parents[2] / "assets" / "voice" / "voice_corpus.json"
out.write_text(json.dumps({"schema": 1, "cows": COWS, "utterances": items},
                          ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
print(f"{len(items)} utterances -> {out}")
