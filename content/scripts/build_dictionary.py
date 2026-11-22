"""Build a full-length prototype noun lexicon from unmodified NIKL downloads."""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import csv
import gzip
import hashlib
import html
import json
from pathlib import Path
import re
import unicodedata
import zipfile

CONTENT = Path(__file__).resolve().parents[1]
FILES = {
    "krdict": "krdict_json_20261019.zip",
    "stdict": "stdict_json_20261012.zip",
    "opendict": "opendict_json_20261004.zip",
}
HANGUL = re.compile(r"[가-힣]{2,}\Z")
NONSTANDARD = re.compile(r"방언|북한어|옛말|비표준어|의 잘못|규범 표기는|표준어는|→")
NAME_CATEGORIES = {"인명", "지명", "책명", "고유명 일반"}
# Extra quarantine only. Absence of a match does not establish non-name status.
NAME_DEFINITION = re.compile(r"특별시|광역시|특별자치|의 수도|의 연호|성\(姓\)의 하나|기원전|고전 소설|주인공|세운 나라|에 있던 나라|라는 이름|의 이름|라는 제목|의 학명|학명은|우리나라 국보|우리나라 보물|감독의 영화|감독이 만든|개봉하였다|공용 연호|\d{3,4}[~∼～]|[가-힣]{2,}(?:도|시|군|면|읍) .{0,30}에 있는")
SENSITIVE = re.compile(r"속되게|낮잡아|비속|욕으로|은어로|얕잡아|속된 말로|욕하는 말로|놀리는 말로|비웃는 말로|비난하는 말로|낮추는 말로|낮춤말로|성교|성행위|성적 흥분|성기의|남자의 성기|여자의 성기|매춘|매음|음란|포르노|정액을|자위행위")
GRADE = {"초급": 3, "중급": 2, "고급": 1}
DEFINITION_SOURCES = {"krdict": "기초", "stdict": "표준", "opendict": "우리말샘"}
SOURCE_PRIORITY = {source: index for index, source in enumerate(DEFINITION_SOURCES)}
REJECTED_SENSES = {
    tuple(line.split("\t")[:3])
    for line in (CONTENT / "review/rejected_senses.tsv").read_text().splitlines()
    if line and not line.startswith("#")
}


def as_list(value):
    return value if isinstance(value, list) else ([] if value is None else [value])


def feats(obj):
    return {f["att"]: f["val"] for f in as_list(obj.get("feat"))} if isinstance(obj, dict) else {}


def spelling(raw, unit, source):
    if unit != ("어휘" if source == "opendict" else "단어"):
        return None
    # ^ denotes optional spacing; only lexical compound-boundary hyphens join.
    if "^" in raw or any(c.isspace() for c in raw):
        return None
    word = unicodedata.normalize("NFC", re.sub(r"\d+$", "", raw).replace("-", ""))
    return word if HANGUL.fullmatch(word) else None


def records(source, archive):
    with zipfile.ZipFile(archive) as zipped:
        for member in sorted(n for n in zipped.namelist() if n.endswith(".json")):
            data = json.loads(zipped.read(member))
            if source == "krdict":
                for entry in data["LexicalResource"]["Lexicon"]["LexicalEntry"]:
                    f = feats(entry)
                    lemma = {}
                    for part in as_list(entry.get("Lemma")):
                        lemma.update(feats(part))
                    raw = lemma.get("writtenForm", "")
                    for sense in as_list(entry.get("Sense")):
                        yield {
                            "source": source, "entry_id": str(entry.get("val", "")),
                            "sense_id": str(sense.get("val", "")), "raw": raw,
                            "unit": f.get("lexicalUnit"), "pos": f.get("partOfSpeech"),
                            "usage": "learner-entry", "definition": feats(sense).get("definition", ""),
                            "categories": [f.get("semanticCategory", "")],
                            "origins": [{"original_language": f.get("origin", "")}],
                            "grade": f.get("vocabularyLevel", ""),
                            "word_type": "", "member": member,
                        }
            else:
                for item in data["channel"]["item"]:
                    wi = item["wordinfo" if source == "opendict" else "word_info"]
                    if source == "opendict":
                        senses = [(item["senseinfo"].get("pos"), item["senseinfo"])]
                    else:
                        senses = [(pos.get("pos"), sense)
                                  for pos in wi.get("pos_info", [])
                                  for pattern in pos.get("comm_pattern_info", [])
                                  for sense in pattern.get("sense_info", [])]
                    for pos, sense in senses:
                        yield {
                            "source": source, "entry_id": str(item["target_code"]),
                            "sense_id": str(sense.get("sense_code", sense.get("sense_no", ""))),
                            "raw": wi.get("word", ""), "unit": wi.get("word_unit"),
                            "pos": pos, "usage": sense.get("type", ""),
                            "definition": sense.get("definition", ""),
                            "categories": [c["cat"] for c in sense.get("cat_info", [])],
                            "origins": wi.get("original_language_info", []),
                            "word_type": wi.get("word_type", ""), "grade": "", "member": member,
                        }
            del data
            print(f"{source}: {member}", flush=True)


def eligibility(record):
    if (record["source"], record.get("entry_id"), record.get("sense_id")) in REJECTED_SENSES:
        return "reviewed-name"
    if record["pos"] != "명사":
        return "not-noun"
    if not spelling(record["raw"], record["unit"], record["source"]):
        return "not-single-hangul-word"
    if record["source"] != "krdict" and record["usage"] != "일반어":
        return "usage-not-general"
    definition = record["definition"]
    if not definition.strip() or NONSTANDARD.search(definition):
        return "nonstandard-or-reference"
    if set(record["categories"]) & NAME_CATEGORIES or NAME_DEFINITION.search(definition):
        return "possible-name"
    if record["source"] == "krdict" and "개념 > 지역" in record["categories"]:
        return "possible-name"
    return None


def allowed_starts(syllable):
    value = ord(syllable) - 0xAC00
    initial, vowel = value // 588, (value % 588) // 28
    target = None
    if initial == 5:
        if vowel in (0, 1, 8, 11, 13, 18):
            target = 2
        elif vowel in (2, 6, 7, 12, 17, 20):
            target = 11
    elif initial == 2 and vowel in (6, 12, 17, 20):
        target = 11
    return {syllable} | ({chr(0xAC00 + target * 588 + value % 588)} if target is not None else set())


def load_frequency(path):
    frequency = Counter()
    with path.open(encoding="utf-8") as stream:
        for row in list(csv.reader(stream, delimiter="\t"))[1:]:
            if len(row) >= 5 and row[3] == "명":
                word = re.sub(r"\d+$", "", row[1].strip())
                if HANGUL.fullmatch(word):
                    frequency[word] += int(row[4].replace(",", "").strip() or 0)
    return frequency


def digest(path):
    hasher = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def short_definition(record):
    if record.get("filter") or eligibility(record) or SENSITIVE.search(record["definition"]):
        return None
    text = html.unescape(record["definition"])
    text = re.sub(r"<[^>]*>", "", text)
    text = " ".join(unicodedata.normalize("NFC", text).split())
    if SENSITIVE.search(text) or NONSTANDARD.search(text) or NAME_DEFINITION.search(text):
        return None
    # Keep a complete source sentence, never an ellipsis or a rewritten meaning.
    first = re.split(r"(?<=[.!?])\s+", text, maxsplit=1)[0]
    if not first or len(first) > 240 or any(ord(character) < 32 for character in first):
        return None
    return first


def definition_priority(record):
    return SOURCE_PRIORITY[record["source"]], -GRADE.get(record.get("grade"), 0)


def write_definitions(output, audit):
    manifest_path = output / "manifest.json"
    summary = json.loads(manifest_path.read_text())
    for name in ("words.tsv", "seeds.tsv", "excluded.tsv"):
        if digest(output / name) != summary["output_sha256"][name]:
            raise ValueError(f"{name} changed since the dictionary audit")
    ranks = {word: int(rank) for word, rank in (line.split("\t") for line in (output / "words.tsv").read_text().splitlines())}
    seeds = set((output / "seeds.tsv").read_text().splitlines())
    targets = {word for word, rank in ranks.items() if rank >= 2} | seeds
    selected = {}
    with gzip.open(audit / "senses.jsonl.gz", "rt", encoding="utf-8") as stream:
        for line in stream:
            record = json.loads(line)
            word = record.get("word")
            if word not in targets:
                continue
            text = short_definition(record)
            if not text:
                continue
            # Prefer the more familiar learner homograph; keep source order on ties.
            if word in selected and definition_priority(selected[word]) <= definition_priority(record):
                continue
            selected[word] = {**record, "display_definition": text}
    with (output / "definitions.tsv").open("w", encoding="utf-8", newline="") as stream, (audit / "definition-sources.jsonl").open("w", encoding="utf-8") as evidence:
        for word in sorted(selected):
            record = selected[word]
            stream.write(f"{word}\t{DEFINITION_SOURCES[record['source']]}\t{record['display_definition']}\n")
            evidence.write(json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n")
    missing = sorted(targets - selected.keys())
    summary["definitions"] = {
        "scope": "familiarity >= 2 plus all seeds",
        "count": len(selected), "target_count": len(targets),
        "by_source": dict(sorted(Counter(record["source"] for record in selected.values()).items())),
        "missing_words": missing,
        "maximum_characters": max((len(record["display_definition"]) for record in selected.values()), default=0),
        "selection": "first eligible safe sentence; krdict > stdict > opendict, then highest learner grade; maximum 240 characters",
    }
    summary["output_sha256"]["definitions.tsv"] = digest(output / "definitions.tsv")
    manifest_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary["definitions"], ensure_ascii=False))


def build(raw_dir, output):
    output.mkdir(parents=True, exist_ok=True)
    audit = CONTENT / "build"
    audit.mkdir(exist_ok=True)
    exclusions = {line.split("\t")[0] for line in (CONTENT / "review/exclusions.tsv").read_text().splitlines() if line and not line.startswith("#")}
    words = {}
    sensitive = set()
    counts = Counter()
    sources = {}
    with gzip.open(audit / "senses.jsonl.gz", "wt", encoding="utf-8") as provenance:
        for source, filename in FILES.items():
            path = raw_dir / filename
            sources[source] = {"file": filename, "sha256": digest(path)}
            for record in records(source, path):
                counts[f"{source}:senses"] += 1
                reason = eligibility(record)
                counts[f"{source}:{reason or 'candidate'}"] += 1
                # Preserve noun evidence including rejected senses for diagnosis.
                if record["pos"] != "명사":
                    continue
                word = spelling(record["raw"], record["unit"], source)
                record["word"] = word
                record["filter"] = reason
                provenance.write(json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n")
                if word and SENSITIVE.search(record["definition"]):
                    sensitive.add(word)
                if reason:
                    continue
                rank = GRADE.get(record["grade"], 0)
                old = words.setdefault(word, {"grade": 0, "sources": set(), "sense_count": 0})
                old["grade"] = max(old["grade"], rank)
                old["sources"].add(source)
                old["sense_count"] += 1
    frequency = load_frequency(raw_dir / "freq_words_utf8.tsv")
    held = sorted((sensitive - exclusions) & words.keys())
    (audit / "sensitive-review.txt").write_text("\n".join(held) + "\n", encoding="utf-8")
    for word in sensitive | exclusions:
        words.pop(word, None)
    ranks = {}
    for word, row in words.items():
        count = frequency[word]
        ranks[word] = max(row["grade"], 3 if count >= 100 else 2 if count >= 10 else 1 if count >= 3 else 0)
    with (output / "words.tsv").open("w", encoding="utf-8", newline="") as stream:
        for word in sorted(words):
            stream.write(f"{word}\t{ranks[word]}\n")
    (output / "excluded.tsv").write_text("\n".join(sorted(exclusions)) + "\n", encoding="utf-8")
    starts = defaultdict(set)
    familiar = defaultdict(set)
    for word in words:
        starts[word[0]].add(word)
        if ranks[word] >= 2:
            familiar[word[0]].add(word)
    def replies(word, used):
        return set().union(*(familiar[c] for c in allowed_starts(word[-1]))) - used
    seeds, seed_evidence = [], []
    for seed in (CONTENT / "review/seed_candidates.txt").read_text().splitlines():
        if seed not in words or ranks[seed] < 2:
            continue
        first = replies(seed, {seed})
        supported = [word for word in first if len(replies(word, {seed, word})) >= 3]
        if len(first) >= 8 and len(supported) >= 5:
            seeds.append(seed)
            seed_evidence.append({"word": seed, "familiar_replies": len(first), "replies_with_three_familiar_followups": len(supported), "examples": sorted(supported)[:12]})
    if len(seeds) < 20:
        raise ValueError(f"Only {len(seeds)} opening seeds pass")
    (output / "seeds.tsv").write_text("\n".join(sorted(set(seeds))) + "\n", encoding="utf-8")
    (audit / "seed-evidence.json").write_text(json.dumps(seed_evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    summary = {
        "version": "prototype-nouns-v1", "connection_version": "kkutu-forward-v1",
        "release_ready": False,
        "release_gaps": ["Complete proper-name and sensitive-homograph human review remains open", "Familiarity and seed follow-ups are proxies, not observed playability"],
        "sources": sources, "frequency_sha256": digest(raw_dir / "freq_words_utf8.tsv"),
        "counts": dict(sorted(counts.items())), "words": len(words), "seeds": len(seeds),
        "familiarity": dict(sorted(Counter(ranks.values()).items())),
        "lengths": dict(sorted(Counter(map(len, words)).items())),
        "maximum_length": max(map(len, words)),
        "longest_words": sorted(words, key=lambda word: (-len(word), word))[:10],
        "sensitive_spellings_held": len(held),
        "exclusion_spellings": len(exclusions),
        "output_sha256": {name: digest(output / name) for name in ("words.tsv", "seeds.tsv", "excluded.tsv")},
    }
    (output / "manifest.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    write_definitions(output, audit)
    print(json.dumps({key: summary[key] for key in ("words", "seeds", "maximum_length", "sensitive_spellings_held")}, ensure_ascii=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--raw-dir", type=Path)
    parser.add_argument("--definitions-only", action="store_true", help="Reuse the existing audited senses without rereading archives")
    parser.add_argument("--output", type=Path, default=CONTENT / "data")
    args = parser.parse_args()
    if args.definitions_only:
        write_definitions(args.output, CONTENT / "build")
    elif args.raw_dir:
        build(args.raw_dir, args.output)
    else:
        parser.error("--raw-dir is required unless --definitions-only is selected")
