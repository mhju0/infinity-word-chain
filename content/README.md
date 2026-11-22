# Prototype dictionary

The generated runtime inputs are `data/words.tsv`, `data/seeds.tsv`,
`data/excluded.tsv` and `data/definitions.tsv`. The generator reads all three original downloaded NIKL
archives; it does not reuse the sibling app's two-syllable accept list.
`data/manifest.json` records source hashes, counts, lengths and output hashes.

This is a development dataset. `release_ready` remains false: source categories
and definition screening cannot prove that every proper-name sense or sensitive
homograph has been reviewed. Do not describe the dataset as a fully reviewed
release dictionary.

## Runtime contract

- UTF-8, LF endings, no header. `words.tsv`: normalized spelling, tab, integer
  familiarity `0...3`. There is no third definition field in this version.
- Spelling is unique and sorted by Unicode code-point order. At least two complete
  Hangul syllables; no product length cap. Use the manifest's maximum length when
  selecting a storage/input safety bound, and recheck it after each revision.
- `seeds.tsv`: one unique, sorted spelling per line. The app shuffles and persists
  its pool position; the data file is not a runtime random sequence.
- `excluded.tsv`: explicitly excluded whole spellings, one per line. An excluded
  spelling is absent from words. Other absent words are not necessarily excluded.
- `definitions.tsv`: word, tab, Korean source short name (`기초`, `표준`,
  `우리말샘`), tab, one clean definition line. It is independent of legality.
  Postmatch lookup can cover rank >=2 words and every seed. A missing row means
  no bundled definition; keep the played word visible and say `뜻풀이가 없어요.`
  Never substitute a different word or treat a missing definition as invalid.
- The same words and exclusions apply to player and computer. Familiarity does
  not restrict legal membership or prove anyone knows a word.

## Extraction and review

A single sense must be a noun, a source word unit, and (in stdict/opendict) carry
`일반어` itself. Dependent nouns, roots and other parts of speech do not qualify.
A clean sense can survive another ineligible sense with the same spelling.
Krdict learner entries provide their own noun/word labels but no `일반어` field;
reference and nonstandard definitions are quarantined rather than followed.

Dictionary homograph-number suffixes are removed. Internal compound-boundary
hyphens are joined only within a source word unit. Entries with `^`, spaces,
Latin, digits inside the spelling or incomplete Hangul are rejected. Optional
spacing phrases are never silently concatenated.

Named-person/place/book categories and explicit name-like definitions are held
per sense. `review/rejected_senses.tsv` records manually inspected named-book,
institution, era and film senses missed by category labels. Its entry and sense
IDs permit another reviewer to check the exact source. This is partial review;
absence of a heuristic match is not evidence that a sense is a common noun.
`서울` remains eligible through its separate common-noun sense.

`review/exclusions.tsv` lists reviewed abusive, slur and sexual spellings, plus
the interjection homographs `와우`, `우와` and `오호`. Each of the three sounds
like an interjection in everyday play, and only obscure noun senses admitted
their spellings. `대박` retains its familiar noun sense.
This is not a complete harmful-language inventory.
Other spellings with flagged usage/sexual definitions are held for review in
`build/sensitive-review.txt`, including homographs with a potentially clean
sense. These holds are unresolved decisions, not automatic permanent bans.
Source usage labels alone do not establish a whole-spelling exclusion.

Familiarity is the larger of the eligible krdict learner grade (초급=3, 중급=2,
고급=1) and the 2002 noun-frequency proxy (>=100=3, >=10=2, >=3=1, otherwise 0).
Historical frequency combines homographs, so a rare qualifying sense can inherit
frequency from a familiar excluded sense. Do not present scores as sense-specific
knowledge. Familiar means rank >=2 only for the initial seed audit and AI tuning.

`review/seed_candidates.txt` is a human-selected ordinary opening pool. A seed
must survive the final filters, rank >=2, have >=8 distinct familiar replies, and
have >=5 replies each allowing >=3 familiar follow-ups after used words are
removed. Connections are the plan's single-forward KKuTu convention, preserving
final consonants. These are graph checks, not playtest results or a promise that
all player choices continue safely. Every legal finishing move remains legal.

## Postmatch definitions

Only eligible, unflagged noun senses for admitted familiar words (rank >=2) and
seeds can supply a definition. Selection prefers 한국어기초사전, then
표준국어대사전, then 우리말샘. Within a source, the highest learner grade wins;
source order breaks ties. This avoids choosing 가격's 고급 striking sense over
its 초급 price sense, or 의사's 고급 historical sense over its 초급 doctor sense.
It does not establish that one meaning represents every play of a homograph.

The selected display text preserves the first complete source sentence. HTML
entities and tags are removed and whitespace is collapsed; no paraphrase,
translation or mid-sentence truncation is generated. A first sentence longer
than 240 characters is skipped in favor of another qualifying sense. The current
snapshot covers all 10,780 targets, with no missing definitions and a longest
text of 91 characters. The general missing-row behavior still applies to rank
0/1 words and future data revisions.

`build/definition-sources.jsonl` preserves each selected source, entry/sense ID,
full original definition, display text and eligibility metadata. Source labels,
name checks and sensitive-language checks are applied again to each selected
sense; the global review limitations still apply. The runtime file contains no
examples, quotations from third-party example sentences or media.

## Reproduce and verify

Use Python 3.11 or newer. The bundled dataset is enough to run the app and
validate the shipped data. Regenerating it requires the original source files
listed in [the manifest](data/manifest.json). Put them in a local directory and
pass that directory as read-only input with `--raw-dir`.

```sh
python3 content/scripts/build_dictionary.py --raw-dir /path/to/source-files
python3 -m unittest discover -s content/tests -v
```

A lightweight definition-only rebuild reads the existing audit without opening
source archives or changing the word/seed/exclusion resources:

```sh
python3 content/scripts/build_dictionary.py --definitions-only
```

It requires the audit and verifies the three existing resource hashes against
the manifest before reading it. A full build also generates definitions.

Original filenames are in `FILES` in the script. `raw/freq_words_utf8.tsv` from the
same download collection supplies the historical proxy. No downloads are made by
the build. Keep the source archives; their hashes identify this exact snapshot.
Ignored `content/build/` retains noun senses, IDs, origins, categories, source
members, definitions and rejection reasons in `senses.jsonl.gz`, plus seed graph
evidence and unresolved sensitive spellings. That 58 MB audit file is not an app
resource and is intentionally not tracked. Rebuilding recreates it.

The tests check actual generated output hashes, complete Hangul, sorted unique
spellings, full-length entries, exclusion separation, common-noun homographs,
known named-book rejection, exact connection examples and every seed's distinct
unused follow-ups. Definition checks cover source priority, learner-homograph
grades, unsafe/ineligible-sense rejection, exact familiar/seed coverage, clean
single-line text and selected-source evidence. No simulator, native app or
real-player test is run here.

## Source attribution and redistribution

Dictionary text source: 국립국어원, 한국어기초사전 (2026-10-19 snapshot),
표준국어대사전 (2026-10-12 snapshot), 우리말샘 (2026-10-04 snapshot).
This project's changes are extraction, filtering, normalization, deduplication,
familiarity ranking, seed selection and first-sentence definition extraction.
No examples or media are bundled.

The [한국어기초사전 policy](https://krdict.korean.go.kr/kor/kboardPolicy/copyRightTermsInfo),
[표준국어대사전 policy](https://kdict.korean.go.kr/info/copyright) and
[우리말샘 policy](https://opendict.korean.go.kr/service/copyrightPolicy) state
CC BY-SA 2.0 KR with attribution and share-alike conditions.
[CC BY-SA 2.0 KR terms](https://creativecommons.org/licenses/by-sa/2.0/kr/)
apply to the source-derived data.

Historical frequency source: 국립국어원, 현대 국어 사용 빈도 조사 (2002),
UTF-8 conversion of 단어_빈도색인.txt. The official
[NIKL 2002 report record](https://www.korean.go.kr/front/reportData/reportDataView.do?mn_id=207&report_seq=303)
and the downloaded text archive's
[original record](https://www.korean.go.kr/front/etcData/etcDataView.do?etc_seq=61&mn_id=96)
both display 공공누리 제1유형 (출처표시).

The beta's dictionary attribution screen links the terms and exports the runtime
dataset with `DictionaryCredits.txt`. The manifest retains `release_ready: false`
pending the public-release proper-name review, sensitive-homograph decisions and
playability review.
