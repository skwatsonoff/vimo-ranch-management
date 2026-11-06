import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))

import learn_lessons as L  # noqa: E402

COWS = [
    {"name": "Shomperi", "tamil": "ஷொம்பெரி", "aliases": []},
    {"name": "Maina", "tamil": "மைனா", "aliases": []},
    {"name": "Karupalazhi", "tamil": "கருபலழி", "aliases": []},
    {"name": "Maila", "tamil": "மைலா", "aliases": []},
]


def test_a_misheard_name_becomes_an_alias():
    assert L.heard_for_cow("add six litres for Shomperi", "add 6 liters for strawberry", COWS) == ("Shomperi", "strawberry")


def test_a_name_split_in_two_words_is_kept_whole():
    assert L.heard_for_cow("how much milk did Shomperi give this month", "How much milk did Tom Berry give this month?", COWS) == ("Shomperi", "tom berry")


def test_a_name_heard_right_teaches_nothing():
    assert L.heard_for_cow("add five litres for Maina", "Add 5 liters for Maina.", COWS) is None
    assert L.heard_for_cow("மைனா அஞ்சு லிட்டர்", "மைனா 5 லிட்டர்", COWS) is None


def test_tanglish_lines_up_with_tamil_letters():
    got = L.heard_for_cow("nethu maalai karupalazhi aaru litre kuduthuchu", "நேத்து மாலை, கருப்பழகி, ஆர் லிட்டர் கொடுத்தது", COWS)
    assert got == ("Karupalazhi", "கருப்பழகி")


def test_tamil_case_endings_and_numbers_are_dropped():
    got = L.heard_for_cow("karupalazhi ku moonu litre add pannu", "கரப்பலைக்கு 3 லிட்டர் அடு பண்ணு", COWS)
    assert got == ("Karupalazhi", "கரப்பலை")


def test_everyday_words_never_become_a_cow():
    assert L.heard_for_cow("add five litres for Maila", "add 5 liters for my", COWS) is None
    assert L.heard_for_cow("add five litres for Maina", "add 5 liters for", COWS) is None


def test_a_spelling_heard_for_two_cows_is_left_out():
    rows = [
        {"ref": "add five litres for Maina", "asr": "add 5 liters for miner"},
        {"ref": "add five litres for Maila", "asr": "add 5 liters for miner"},
        {"ref": "add six litres for Shomperi", "asr": "add 6 liters for strawberry"},
    ]
    assert L.learn(rows, COWS)["aliases"] == {"Shomperi": ["strawberry"]}


def test_sound_key_matches_across_scripts():
    assert L.similar("நொண்டுக்குது", "nondukuthu") > 0.8
    assert L.similar("கருப்பழகி", "karupalazhi") > 0.8
