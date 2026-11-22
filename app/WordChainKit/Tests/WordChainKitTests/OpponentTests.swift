import Foundation
import Testing
@testable import WordChainKit

@Test func randomSequenceAndShuffleAreVersionedDeterministicOperations() {
    var random = SeededRandom(seed: 0)
    #expect(random.next() == 16_294_208_416_658_607_535)
    #expect(random.next() == 7_960_286_522_194_355_700)
    #expect(random.next() == 487_617_019_471_545_679)
    var shuffleRandom = SeededRandom(seed: 0)
    #expect(shuffleRandom.shuffled(Array(0..<6)) == [4, 2, 5, 3, 0, 1])
}

@Test func normalDefendsShortThreatWhileEasyLeavesRealOpportunities() throws {
    let words = try dictionary(["후가", "가나", "가다", "가마", "나끝", "다가", "마끝"])
    var easyChoices: Set<String> = []
    for seed in 0..<40 {
        var easyRandom = SeededRandom(seed: UInt64(seed))
        var normalRandom = easyRandom
        var easyPressure = PressureState()
        var normalPressure = PressureState()
        let easy = try #require(OpponentPolicy.choose(dictionary: words, after: "후가", used: ["후가"], difficulty: .easy,
                                                      random: &easyRandom, pressure: &easyPressure, pacingEnabled: false))
        let normal = try #require(OpponentPolicy.choose(dictionary: words, after: "후가", used: ["후가"], difficulty: .normal,
                                                        random: &normalRandom, pressure: &normalPressure, pacingEnabled: false))
        easyChoices.insert(easy.word)
        #expect(normal.word == "가다")
    }
    #expect(easyChoices.contains("가나") || easyChoices.contains("가마"))
}

@Test func recoveryPrefersFamiliarContinuationsAndAllForcingFallbackStaysLegal() throws {
    let words = try dictionary(["후가", "가나", "가다", "나라", "나무", "나비"])
    var random = SeededRandom(seed: 5)
    var pressure = PressureState()
    pressure.computerTurns = 4
    pressure.demandingTurns = 2
    let recovery = try #require(OpponentPolicy.choose(dictionary: words, after: "후가", used: ["후가"], difficulty: .easy,
                                                      random: &random, pressure: &pressure))
    #expect(recovery.word == "가나")
    #expect(recovery.usedRecovery)
    #expect(recovery.familiarReplyCount == 3)
    #expect(pressure.demandingTurns == 0)
    let forcing = try dictionary(["후가", "가끝"])
    let fallback = try #require(OpponentPolicy.choose(dictionary: forcing, after: "후가", used: ["후가"], difficulty: .easy,
                                                      random: &random, pressure: &pressure))
    #expect(fallback.word == "가끝")
    #expect(!fallback.usedRecovery)
    #expect(fallback.legalReplyCount == 0)
}

@Test func randomAndPacingRoundTripRepeatExactlyAndBudgetsBounded() throws {
    let words = try dictionary(["후가", "가나", "가다", "가마", "나끝", "다가", "마끝"])
    var random = SeededRandom(seed: 13)
    var pressure = PressureState()
    let data = try JSONEncoder().encode(random)
    var restoredRandom = try JSONDecoder().decode(SeededRandom.self, from: data)
    var restoredPressure = pressure
    let first = OpponentPolicy.choose(dictionary: words, after: "후가", used: ["후가"], difficulty: .normal,
                                      random: &random, pressure: &pressure)
    let restored = OpponentPolicy.choose(dictionary: words, after: "후가", used: ["후가"], difficulty: .normal,
                                         random: &restoredRandom, pressure: &restoredPressure)
    #expect(first == restored)
    #expect(random == restoredRandom)
    #expect(pressure == restoredPressure)
    #expect((first?.exploredPositions ?? 0) <= 48 * 25)
}

@Test func seedPoolNoRepeatBeforeExhaustionAndPersistsCursor() throws {
    let words = try dictionary(["가나", "나가", "다라", "라다", "마바", "바마"])
    var pool = try SeedPool(seeds: ["가나", "다라", "마바"], dictionary: words, randomSeed: 7)
    let first = pool.next()
    var recovered = try JSONDecoder().decode(SeedPool.self, from: JSONEncoder().encode(pool))
    let second = pool.next()
    #expect(recovered.next() == second)
    let third = pool.next()
    #expect(Set([first, second, third]).count == 3)
    #expect(pool.next() != third)
}

@Test func corruptSeedCursorCannotReachNext() throws {
    let data = Data(#"{"seeds":["사과"],"position":2,"random":{"state":1}}"#.utf8)
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(SeedPool.self, from: data) }
}

@Test func easySamplesFamiliarWordsEvenAmongManyObscureCandidates() throws {
    let obscure = (1...80).compactMap { UnicodeScalar(0xAC00 + $0) }.map { WordEntry(word: "가" + String($0), familiarity: 0) }
    let words = try WordDictionary(entries: obscure + [WordEntry(word: "가나", familiarity: 3)], version: "sample-fixture")
    for seed in 0..<20 {
        var random = SeededRandom(seed: UInt64(seed))
        var pressure = PressureState()
        let choice = try #require(OpponentPolicy.choose(dictionary: words, after: "후가", used: ["후가"], difficulty: .easy,
                                                        random: &random, pressure: &pressure, pacingEnabled: false))
        #expect(choice.word == "가나")
    }
    let fallback = try dictionary(["후가", "가나", "나가"], familiarity: 0)
    var random = SeededRandom(seed: 1)
    var pressure = PressureState()
    #expect(OpponentPolicy.choose(dictionary: fallback, after: "후가", used: ["후가"], difficulty: .easy,
                                  random: &random, pressure: &pressure)?.word == "가나")
}

@Test func adaptiveOpeningAndRecoveryPreferMoreFamiliarHumanReplies() throws {
    let words = try dictionary(["후가", "가나", "가다", "나다", "나이", "나라", "나무", "나비", "나사", "나치", "나팔", "다리", "다마"])
    var warmedUp = PressureState()
    warmedUp.adaptive = AdaptivePressure()
    warmedUp.computerTurns = 10
    for _ in 0..<8 { warmedUp.adaptive?.recordAccepted(elapsed: 2, computerTurns: 10) }

    var opening = warmedUp
    opening.computerTurns = 1
    var recovery = warmedUp
    recovery.demandingTurns = 2
    var random = SeededRandom(seed: 42)
    #expect(OpponentPolicy.choose(dictionary: words, after: "후가", used: ["후가"], difficulty: .adaptive,
                                  random: &random, pressure: &opening)?.word == "가나")
    let demanding = OpponentPolicy.choose(dictionary: words, after: "후가", used: ["후가"], difficulty: .adaptive,
                                           random: &random, pressure: &warmedUp)
    #expect(demanding?.word == "가다")
    #expect(demanding?.familiarReplyCount == 2)
    let recovered = OpponentPolicy.choose(dictionary: words, after: "후가", used: ["후가"], difficulty: .adaptive,
                                           random: &random, pressure: &recovery)
    #expect(recovered?.word == "가나")
    #expect(recovered?.familiarReplyCount == 8)
    #expect(recovered?.usedRecovery == true)
    #expect(recovery.demandingTurns == 0)
}

@Test func adaptiveFindsFamiliarNonterminalOutsideTheSample() throws {
    let terminal = (1...80).compactMap { UnicodeScalar(0xAC00 + $0) }.map { "가" + String($0) }
    let entries = (terminal + ["후가", "가나", "나무", "다리"]).map { WordEntry(word: $0, familiarity: 3) }
    let words = try WordDictionary(entries: entries + [WordEntry(word: "가다", familiarity: 0)], version: "fallback-fixture")
    let used: Set<String> = ["후가"]
    let familiar = words.legalReplies(after: "후가", used: used).filter { $0 != "가다" }
    let seed = try #require((0..<20).first { seed in
        var random = SeededRandom(seed: UInt64(seed))
        return !random.shuffled(familiar).prefix(24).contains("가나")
    })
    var random = SeededRandom(seed: UInt64(seed))
    var pressure = PressureState()
    let choice = try #require(OpponentPolicy.choose(dictionary: words, after: "후가", used: used, difficulty: .adaptive,
                                                    random: &random, pressure: &pressure))
    #expect(choice.word == "가나")
    #expect(choice.legalReplyCount == 1)
    #expect(choice.exploredPositions <= 24)
}

@Test func adaptiveUsesRareContinuationBeforeAForcedDeadEndAndRespectsExclusions() throws {
    let entries = [WordEntry(word: "후가", familiarity: 3), WordEntry(word: "가나", familiarity: 3),
                   WordEntry(word: "가력", familiarity: 0), WordEntry(word: "역사", familiarity: 3),
                   WordEntry(word: "나무", familiarity: 3), WordEntry(word: "력사", familiarity: 3)]
    let words = try WordDictionary(entries: entries, version: "rare-fixture", excludedWords: ["나무", "력사"])
    var random = SeededRandom(seed: 1)
    var pressure = PressureState()
    let continuation = OpponentPolicy.choose(dictionary: words, after: "후가", used: ["후가"], difficulty: .adaptive,
                                              random: &random, pressure: &pressure)
    #expect(continuation?.word == "가력")
    #expect(continuation?.legalReplyCount == 1)
    let terminal = OpponentPolicy.choose(dictionary: words, after: "후가", used: ["후가", "역사"], difficulty: .adaptive,
                                          random: &random, pressure: &pressure)
    #expect(terminal?.word == "가나")
    #expect(terminal?.legalReplyCount == 0)

    let selfLoop = try dictionary(["후가", "가가"])
    let selfLoopChoice = OpponentPolicy.choose(dictionary: selfLoop, after: "후가", used: ["후가"], difficulty: .adaptive,
                                                random: &random, pressure: &pressure)
    #expect(selfLoopChoice?.word == "가가")
    #expect(selfLoopChoice?.legalReplyCount == 0)
}
