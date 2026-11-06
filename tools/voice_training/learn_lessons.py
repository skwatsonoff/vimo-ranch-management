"""Lessons from the owner's own recordings, for VIMO's understanding.

Each Train VIMO recording has the sentence the owner read (the transcript)
and the voice. A speech recogniser writes down what it hears; where a cow's
name comes out differently ("Shomperi" heard as "strawberry", "Maina" as
"Miner"), that spelling becomes one more name for the cow, so VIMO
understands it the next time. The lessons are written to Firestore
(voice_training_lessons/<owner>) and the phone reads them before listening.

    python learn_lessons.py <lexicon.json> <asr.jsonl> <lessons.json>

Pure functions (tested in tests/test_learn_lessons.py) plus a small main.
"""
from __future__ import annotations

import collections
import difflib
import json
import pathlib
import re
import sys

# Words that are never a cow's name, however a recogniser spells them:
# numbers, units, sessions, small words of the prompts, in English,
# Tanglish and Tamil.
STOP = set(
    """
    a an and the for of to per in on at is it did do does give gave given this that month today yesterday
    how much milk add added remove last entry litre litres liter liters ltr l half one two three four five six
    seven eight nine ten eleven twelve fifteen twenty morning evening night cow cows
    ku kku ukku la le litre-u paal pal maadu maatuku mattuku kuduthuchu kuduthathu pannu panni sollu
    onnu rendu moonu naalu anju aaru ezhu ettu ombodhu pathu pannendu onnara rendara arai kaal mukkaal
    innaiku inniku nethu kaalai kalai maalai malai noondukuthu nondukuthu
    லிட்டர் பால் மாடு மாட்டுக்கு இன்று இன்னைக்கு நேற்று நேத்து காலை மாலை கொடுத்தது கொடுத்துச்சு
    ஒன்று ஒன்னு இரண்டு ரெண்டு மூன்று மூணு நான்கு நாலு ஐந்து அஞ்சு ஆறு ஏழு எட்டு ஒன்பது பத்து
    பன்னிரண்டு ஒன்றரை ரெண்டரை அரை கால் முக்கால் ஹே விமோ ஊசி போட்டேன் சினை உறுதி ஆனது
    """.split()
)
# Everyday English words a recogniser writes for a name; never a cow alone.
COMMON = set("my mile miles mine tom tim kala call cold mail male man may many money more".split())
_PUNCT = re.compile(r"[^\w஀-௿\s]+", re.UNICODE)


_VOWELS = dict(zip("அஆஇஈஉஊஎஏஐஒஓஔ", "a aa i ii u uu e ee ai o oo au".split()))
_SIGNS = dict(zip("ாிீுூெேைொோௌ", "aa i ii u uu e ee ai o oo au".split()))
_CONS = dict(zip("கஙசஞடணதநபமயரலவழளறனஜஷஸஹ", "k ng s nj d n th n p m y r l v zh l r n j sh s h".split()))


def roman(word: str) -> str:
    """Tamil letters written in Latin letters, roughly as they sound."""
    out, i = [], 0
    while i < len(word):
        ch = word[i]
        if ch in _CONS:
            nxt = word[i + 1] if i + 1 < len(word) else ""
            if nxt == "்":
                out.append(_CONS[ch]); i += 2; continue
            if nxt in _SIGNS:
                out.append(_CONS[ch] + _SIGNS[nxt]); i += 2; continue
            out.append(_CONS[ch] + "a"); i += 1; continue
        out.append(_VOWELS.get(ch, ch if ch.isascii() else ""))
        i += 1
    return "".join(out)


def sound(word: str) -> str:
    """A rough sound key, the same for Tamil letters and Tanglish."""
    w = roman(word.lower())
    for a, b in (("zh", "l"), ("th", "t"), ("dh", "d"), ("ch", "s"), ("sh", "s"), ("w", "v"),
                 ("ph", "p"), ("ck", "k"), ("c", "k"), ("q", "k"), ("x", "ks"), ("z", "s"), ("h", "")):
        w = w.replace(a, b)
    w = re.sub(r"(.)\1+", r"\1", w)
    return w


def similar(a: str, b: str) -> float:
    if a == b:
        return 1.0
    sa, sb = sound(a), sound(b)
    if not sa or not sb:
        return 0.0
    return difflib.SequenceMatcher(None, sa, sb).ratio()


def align(ref: list[str], asr: list[str]) -> list[tuple[int | None, int | None]]:
    """Word-by-word alignment by sound (works across Tamil and Latin
    letters): pairs of (ref index, asr index), None for a gap."""
    n, m = len(ref), len(asr)
    gap = -0.45
    score = [[0.0] * (m + 1) for _ in range(n + 1)]
    for i in range(1, n + 1):
        score[i][0] = i * gap
    for j in range(1, m + 1):
        score[0][j] = j * gap
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            match = score[i - 1][j - 1] + (similar(ref[i - 1], asr[j - 1]) * 2 - 1)
            score[i][j] = max(match, score[i - 1][j] + gap, score[i][j - 1] + gap)
    pairs, i, j = [], n, m
    while i > 0 or j > 0:
        if i > 0 and j > 0 and abs(score[i][j] - (score[i - 1][j - 1] + similar(ref[i - 1], asr[j - 1]) * 2 - 1)) < 1e-9:
            pairs.append((i - 1, j - 1)); i -= 1; j -= 1
        elif i > 0 and abs(score[i][j] - (score[i - 1][j] + gap)) < 1e-9:
            pairs.append((i - 1, None)); i -= 1
        else:
            pairs.append((None, j - 1)); j -= 1
    return pairs[::-1]


_SUFFIXES = ("வுக்கு", "யுக்கு", "க்கு", "ுக்கு", "கு", "வை", "யை")


def strip_case(word: str) -> str:
    """"மைனாவுக்கு" -> "மைனா": the cow, without "to/for"."""
    for suffix in _SUFFIXES:
        if word.endswith(suffix) and len(word) > len(suffix) + 2:
            return word[: -len(suffix)]
    return word


def tokens(text: str) -> list[str]:
    """Lower-case words without punctuation; Tamil letters kept whole."""
    return _PUNCT.sub(" ", text.lower()).split()


def cow_spellings(cow: dict) -> list[list[str]]:
    """Every known way to write [cow] (name, Tamil name, aliases) as words."""
    out = []
    for name in [cow.get("name", ""), cow.get("tamil", ""), *cow.get("aliases", [])]:
        t = tokens(str(name))
        if t and t not in out:
            out.append(t)
    return out


def find_span(words: list[str], spelling: list[str]) -> tuple[int, int] | None:
    n = len(spelling)
    for i in range(len(words) - n + 1):
        if words[i : i + n] == spelling:
            return i, i + n
    return None


def heard_for_cow(ref: str, asr: str, cows: list[dict]) -> tuple[str, str] | None:
    """(cow name, what the recogniser wrote for it) for one recording, when
    the transcript names one cow and the recogniser wrote it differently.
    None when no cow is named, it was heard right, or it cannot be lined up."""
    ref_t, asr_t = tokens(ref), tokens(asr)
    found = []
    for cow in cows:
        for spelling in cow_spellings(cow):
            span = find_span(ref_t, spelling)
            if span:
                found.append((cow["name"], span))
                break
    if len(found) != 1 or not asr_t:
        return None
    name, (i, j) = found[0]
    pairs = align(ref_t, asr_t)
    # The recogniser's words lined up with the name, plus any extra words
    # it wrote in between.
    hit = [p for p, (a, b) in enumerate(pairs) if a is not None and i <= a < j]
    first, last = hit[0], hit[-1]
    # Words the recogniser split off the name ("tom berry", "my leg") are
    # gaps next to it.
    while first > 0 and pairs[first - 1][0] is None:
        first -= 1
    while last + 1 < len(pairs) and pairs[last + 1][0] is None:
        last += 1
    heard = [asr_t[b] for _, b in pairs[first : last + 1] if b is not None]
    heard = [strip_case(w) for w in heard]
    neighbours = [w for p, w in enumerate(ref_t) if not i <= p < j]
    heard = [w for w in heard if w not in STOP and not re.search(r"\d", w) and not any(similar(w, n) > .8 for n in neighbours)]
    text = " ".join(heard)
    if not heard or len(heard) > 3 or len(text) > 32:
        return None
    # A short everyday word ("my", "mile") would catch ordinary talk.
    if len(heard) == 1 and (len(sound(text)) < 4 or text in COMMON):
        return None
    if any(heard == s for s in cow_spellings(next(c for c in cows if c["name"] == name))):
        return None  # heard right
    return name, text


def learn(rows: list[dict], cows: list[dict], min_count: int = 1) -> dict:
    """Aliases per cow from transcribed recordings ({ref, asr} rows). A
    spelling that another cow already uses, or that was heard for two
    different cows, is left out: it could only cause mix-ups."""
    seen: dict[str, collections.Counter] = collections.defaultdict(collections.Counter)
    for row in rows:
        got = heard_for_cow(row.get("ref", ""), row.get("asr", ""), cows)
        if got:
            seen[got[0]][got[1]] += 1
    owners: dict[str, set[str]] = collections.defaultdict(set)
    for cow, counter in seen.items():
        for text in counter:
            owners[text].add(cow)
    taken = {" ".join(s) for c in cows for s in cow_spellings(c)}
    aliases = {}
    for cow, counter in sorted(seen.items()):
        keep = [t for t, n in counter.most_common() if n >= min_count and len(owners[t]) == 1 and t not in taken]
        if keep:
            aliases[cow] = keep[:12]
    return {"schema": 1, "aliases": aliases}


def main(lexicon_path: str, asr_path: str, out_path: str) -> None:
    lexicon = json.loads(pathlib.Path(lexicon_path).read_text(encoding="utf-8") or "{}")
    cows = [c for c in lexicon.get("cows", []) if c.get("name")]
    rows = [json.loads(l) for l in pathlib.Path(asr_path).read_text(encoding="utf-8").splitlines() if l.strip()]
    lessons = learn(rows, cows)
    pathlib.Path(out_path).write_text(json.dumps(lessons, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"lessons: {sum(len(v) for v in lessons['aliases'].values())} spellings for {len(lessons['aliases'])} cows")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
