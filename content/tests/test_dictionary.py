import importlib.util
from collections import defaultdict
import json
from pathlib import Path
import re
import unittest

CONTENT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("dictionary", CONTENT / "scripts/build_dictionary.py")
dictionary = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dictionary)


class ExtractionTests(unittest.TestCase):
    def record(self, **changes):
        # Authentic stdict field values: 각본02, entry 3749, sense 2522.
        record = {"source": "stdict", "raw": "각본02", "unit": "단어", "pos": "명사", "usage": "일반어", "definition": "연극이나 영화를 만들기 위하여 쓴 글.", "categories": ["연기"]}
        record.update(changes)
        return record

    def test_compound_boundaries_do_not_become_spaces(self):
        self.assertEqual(dictionary.spelling("각본-가", "단어", "stdict"), "각본가")
        for raw in ("검인정^교과서", "검인정 교과서", "에이-비(C)", "가a", "가ㄴ"):
            self.assertIsNone(dictionary.spelling(raw, "단어", "stdict"))

    def test_length_has_no_two_or_five_syllable_cap(self):
        self.assertIsNone(dictionary.spelling("것", "단어", "stdict"))
        self.assertEqual(dictionary.spelling("장거리달리기선수", "단어", "stdict"), "장거리달리기선수")

    def test_part_of_speech_and_standardness_belong_to_one_sense(self):
        self.assertIsNone(dictionary.eligibility(self.record()))
        self.assertEqual(dictionary.eligibility(self.record(pos="의존 명사")), "not-noun")
        self.assertEqual(dictionary.eligibility(self.record(usage="북한어")), "usage-not-general")
        self.assertEqual(dictionary.eligibility(self.record(usage="")), "usage-not-general")
        self.assertEqual(dictionary.eligibility(self.record(definition="‘각본’의 방언.")), "nonstandard-or-reference")
        self.assertEqual(dictionary.eligibility(self.record(categories=["인명"])), "possible-name")
        self.assertIsNone(dictionary.eligibility(self.record(definition="잘못된 판단으로 생기는 결과.")))

    def test_definition_selection_uses_only_eligible_safe_senses(self):
        record = self.record(definition="연극이나 영화를 만들기 위하여 쓴 글. 배우의 동작을 적는다.")
        self.assertEqual(dictionary.short_definition(record), "연극이나 영화를 만들기 위하여 쓴 글.")
        self.assertIsNone(dictionary.short_definition(self.record(usage="북한어")))
        self.assertIsNone(dictionary.short_definition(self.record(categories=["책명"])))
        self.assertIsNone(dictionary.short_definition(self.record(definition="사람을 낮잡아 이르는 말.")))
        self.assertEqual(dictionary.short_definition(self.record(definition="&lt;i&gt;연극&lt;/i&gt;에 쓰는 글.\n둘째 문장.")), "연극에 쓰는 글.")
        self.assertIsNone(dictionary.short_definition(self.record(definition="가" * 241 + ".")))

    def test_learner_homograph_grade_wins_within_source(self):
        # Real krdict 가격 entries: 15047 (striking, 고급) and 62450 (price, 초급).
        uncommon = {"source": "krdict", "grade": "고급"}
        common = {"source": "krdict", "grade": "초급"}
        self.assertLess(dictionary.definition_priority(common), dictionary.definition_priority(uncommon))
        self.assertLess(dictionary.definition_priority(uncommon), dictionary.definition_priority({"source": "stdict"}))
        self.assertLess(dictionary.definition_priority({"source": "stdict"}), dictionary.definition_priority({"source": "opendict"}))

    def test_exact_forward_connections(self):
        cases = {"력": {"력", "역"}, "리": {"리", "이"}, "로": {"로", "노"}, "름": {"름", "늠"}, "이": {"이"}, "러": {"러"}, "레": {"레"}, "렁": {"렁"}, "녀": {"녀", "여"}}
        for syllable, expected in cases.items():
            self.assertEqual(dictionary.allowed_starts(syllable), expected)


@unittest.skipUnless((CONTENT / "data/manifest.json").exists(), "Run generator first")
class GeneratedDataTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rows = [line.split("\t") for line in (CONTENT / "data/words.tsv").read_text().splitlines()]
        cls.words = {row[0]: int(row[1]) for row in cls.rows}
        cls.manifest = json.loads((CONTENT / "data/manifest.json").read_text())

    def test_sorted_unique_and_complete_hangul(self):
        self.assertEqual([row[0] for row in self.rows], sorted(self.words))
        self.assertTrue(all(len(row) == 2 and re.fullmatch(r"[가-힣]{2,}", row[0]) and 0 <= int(row[1]) <= 3 for row in self.rows))
        self.assertEqual(len(self.rows), self.manifest["words"])
        self.assertGreater(sum(len(word) > 5 for word in self.words), 0)
        self.assertEqual(max(map(len, self.words)), self.manifest["maximum_length"])

    def test_hashes_and_exclusions(self):
        for name, expected in self.manifest["output_sha256"].items():
            self.assertEqual(dictionary.digest(CONTENT / "data" / name), expected)
        excluded = set((CONTENT / "data/excluded.tsv").read_text().splitlines())
        self.assertFalse(excluded & self.words.keys())
        self.assertNotIn("씨발", self.words)
        self.assertTrue({"와우", "우와", "오호"} <= excluded)
        self.assertTrue({"대박", "일석이조", "동문서답", "전화위복"} <= self.words.keys())
        self.assertIn("자동차", self.words)
        self.assertIn("아이스크림", self.words)
        self.assertIn("서울", self.words)  # A separate common-noun sense survives.
        self.assertNotIn("대불정여래밀인수증요의제보살만행수능엄경언해", self.words)

    def test_definitions_cover_familiar_words_and_seeds_cleanly(self):
        rows = [line.split("\t") for line in (CONTENT / "data/definitions.tsv").read_text().splitlines()]
        definitions = {word: (source, text) for word, source, text in rows}
        self.assertEqual([row[0] for row in rows], sorted(definitions))
        targets = {word for word, rank in self.words.items() if rank >= 2} | set((CONTENT / "data/seeds.tsv").read_text().splitlines())
        self.assertEqual(set(definitions), targets - set(self.manifest["definitions"]["missing_words"]))
        self.assertEqual(len(rows), self.manifest["definitions"]["count"])
        for word, source, text in rows:
            self.assertIn(source, dictionary.DEFINITION_SOURCES.values())
            self.assertTrue(text and len(text) <= 240)
            self.assertFalse(any(ord(character) < 32 for character in text))
            self.assertIsNone(dictionary.SENSITIVE.search(text), word)
            self.assertNotIn("<", text)
        self.assertEqual(definitions["가격"], ("기초", "물건의 가치를 돈으로 나타낸 것."))
        self.assertEqual(definitions["의사"], ("기초", "일정한 자격을 가지고서 병을 진찰하고 치료하는 일을 직업으로 하는 사람."))
        self.assertNotIn("씨발", definitions)

    @unittest.skipUnless((CONTENT / "build/definition-sources.jsonl").exists(), "Rebuild definitions for selected-sense evidence")
    def test_definitions_match_eligible_source_sense_evidence(self):
        expected = {}
        for line in (CONTENT / "build/definition-sources.jsonl").read_text().splitlines():
            record = json.loads(line)
            self.assertTrue(record["entry_id"] and record["sense_id"])
            self.assertIsNone(dictionary.eligibility(record))
            self.assertIsNone(record["filter"])
            text = dictionary.short_definition(record)
            self.assertEqual(text, record["display_definition"])
            expected[record["word"]] = (dictionary.DEFINITION_SOURCES[record["source"]], text)
        actual = {word: (source, text) for word, source, text in (line.split("\t") for line in (CONTENT / "data/definitions.tsv").read_text().splitlines())}
        self.assertEqual(actual, expected)

    def test_every_seed_has_multiple_familiar_continuations(self):
        seeds = (CONTENT / "data/seeds.tsv").read_text().splitlines()
        self.assertEqual(seeds, sorted(set(seeds)))
        familiar = defaultdict(set)
        for word, rank in self.words.items():
            if rank >= 2:
                familiar[word[0]].add(word)
        def following(word, used):
            return set().union(*(familiar[c] for c in dictionary.allowed_starts(word[-1]))) - used
        for seed in seeds:
            self.assertIn(seed, self.words)
            replies = following(seed, {seed})
            self.assertGreaterEqual(len(replies), 8, seed)
            supported = 0
            for reply in replies:
                after = following(reply, {seed, reply})
                supported += len(after) >= 3
            self.assertGreaterEqual(supported, 5, seed)


if __name__ == "__main__":
    unittest.main()
