import Foundation
import Testing
@testable import WordChainKit

func dictionary(_ words: [String], familiarity: Int = 3, excluded: Set<String> = []) throws -> WordDictionary {
    try WordDictionary(entries: words.map { WordEntry(word: $0, familiarity: familiarity) }, version: "fixture-1", excludedWords: excluded)
}

@Test(arguments: [
    ("락", ["락", "낙"]), ("랭", ["랭", "냉"]), ("록", ["록", "녹"]),
    ("뢰", ["뢰", "뇌"]), ("룽", ["룽", "눙"]), ("름", ["름", "늠"]),
    ("량", ["량", "양"]), ("력", ["력", "역"]), ("례", ["례", "예"]),
    ("료", ["료", "요"]), ("류", ["류", "유"]), ("리", ["리", "이"]),
    ("녀", ["녀", "여"]), ("뇨", ["뇨", "요"]), ("뉴", ["뉴", "유"]), ("니", ["니", "이"]),
    ("렁", ["렁"]), ("레", ["레"]), ("러", ["러"]), ("이", ["이"]), ("나", ["나"]),
    ("륭", ["륭", "융"]), ("륜", ["륜", "윤"])
])
func exactConnections(example: (String, [String])) {
    #expect(ConnectionRules.allowedStarts(after: example.0) == example.1)
}

@Test func forwardConversionIsSingleAndDictionaryBound() throws {
    let words = try dictionary(["고름", "늠름", "음악", "표구렁", "넝쿨", "오이", "리본"])
    #expect(words.rejection(for: "음악", after: "고름", used: ["고름"]) == .wrongConnection)
    #expect(words.rejection(for: "늠름", after: "고름", used: ["고름"]) == nil)
    #expect(words.rejection(for: "넝쿨", after: "표구렁", used: ["표구렁"]) == .wrongConnection)
    #expect(words.rejection(for: "리본", after: "오이", used: ["오이"]) == .wrongConnection)
}

@Test func normalizationAndFullLengthAdmission() throws {
    let longWord = "과학기술정보통신부문"
    let words = try dictionary(["사과", "과자", longWord, "과즙"], excluded: ["과즙"])
    #expect(words.rejection(for: "  과자\n", after: "사과", used: ["사과"]) == nil)
    #expect(words.rejection(for: "과자".decomposedStringWithCanonicalMapping, after: "사과", used: ["사과"]) == nil)
    #expect(words.rejection(for: longWord, after: "사과", used: ["사과"]) == nil)
    #expect(words.rejection(for: "과 자", after: "사과", used: []) == .internalSpace)
    #expect(words.rejection(for: "ㄱ", after: "사과", used: []) == .incompleteComposition)
    #expect(words.rejection(for: "과", after: "사과", used: []) == .tooShort)
    #expect(words.rejection(for: "과!", after: "사과", used: []) == .invalidCharacters)
    #expect(words.rejection(for: "과일", after: "사과", used: []) == .missingEntry)
    #expect(words.rejection(for: "과즙", after: "사과", used: []) == .excluded)
    #expect(words.rejection(for: "사과", after: "사과", used: ["사과"]) == .duplicate)
}

@Test func graphExhaustionRemovesUsedSpellingAndUnfamiliarStillCounts() throws {
    let words = try dictionary(["가나", "나가"], familiarity: 0)
    #expect(words.legalReplies(after: "나가", used: ["나가"]) == ["가나"])
    #expect(words.hasLegalReply(after: "나가", used: ["나가"]))
    #expect(words.legalReplies(after: "나가", used: ["가나", "나가"]).isEmpty)
    #expect(!words.hasLegalReply(after: "나가", used: ["가나", "나가"]))
    var engine = try DuelEngine(dictionary: words, seed: "가나", difficulty: .easy, randomSeed: 1)
    engine.beginHumanTurn(at: 0)
    #expect(engine.submit("나가", at: 1) == .accepted)
    #expect(engine.state.outcome?.winner == .human)
    #expect(engine.state.humanWordCount == 1)
    #expect(engine.state.moves.last?.word == "나가")
}

@Test func tsvContractAndMalformedRows() throws {
    let words = try WordDictionary(tsv: "사과\t3\t사과나무의 열매\n과자\t2\t\n", version: "content-1")
    #expect(words.entries["사과"]?.definition == "사과나무의 열매")
    #expect(words.entries["과자"]?.definition == nil)
    #expect(throws: DictionaryError.self) { try WordDictionary(tsv: "사과\t4", version: "bad") }
    #expect(throws: DictionaryError.duplicateWord("사과")) {
        try WordDictionary(tsv: "사과\t3\n사과\t2", version: "bad")
    }
}
