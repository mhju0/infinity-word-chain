import Foundation
import Testing
@testable import WordChainKit

@Test(arguments: [Difficulty.adaptiveV2, .adaptiveV3])
func adaptivePromptPacingStartsWithTwoComfortableChoicesThenFindsTheHardBand(difficulty: Difficulty) throws {
    let words = try dictionary(["후가", "가나", "가마", "나무", "나비", "나무늘보", "나팔", "나라", "나사", "나물", "나름", "마루", "마을"])
    var pressure = PressureState()
    pressure.adaptiveV2 = AdaptivePressureV2(level: 5)
    var random = SeededRandom(seed: 8)
    for expectedCount in [8, 8, 2] {
        let choice = try #require(OpponentPolicy.choose(dictionary: words, after: "후가", used: ["후가"], difficulty: difficulty,
                                                        random: &random, pressure: &pressure))
        #expect(choice.familiarReplyCount == expectedCount)
        #expect(!choice.usedRecovery)
    }
}

@Test func adaptiveV2GuardrailReachesOutsideFamiliarCandidatesAndSurvivesDepletion() throws {
    let common = (0..<80).compactMap { UnicodeScalar(0xAC00 + $0) }.map { "가" + String($0) + "나" }
    let usual = common + ["후가", "가끝", "나무", "역사", "력사", "역할"]
    let entries = usual.map { WordEntry(word: $0, familiarity: 3) } + [
        WordEntry(word: "가력", familiarity: 0), WordEntry(word: "나방", familiarity: 0)
    ]
    let words = try WordDictionary(entries: entries, version: "guardrail-fixture", excludedWords: ["역할"])
    var pressure = PressureState()
    pressure.computerTurns = 10
    pressure.adaptiveV2 = AdaptivePressureV2(level: 5)
    var random = SeededRandom(seed: 18)
    let ample = try #require(OpponentPolicy.choose(dictionary: words, after: "후가", used: ["후가"], difficulty: .adaptiveV2,
                                                    random: &random, pressure: &pressure))
    #expect(ample.word == "가력")
    #expect(ample.familiarReplyCount == 2)
    #expect(ample.legalReplyCount == 2)
    #expect(ample.exploredPositions == 3)

    let depleted = try #require(OpponentPolicy.choose(dictionary: words, after: "후가", used: ["후가", "력사", "나무"],
                                                       difficulty: .adaptiveV2, random: &random, pressure: &pressure))
    #expect(depleted.word == "가력")
    #expect(depleted.familiarReplyCount == 1)

    let obscureOnly = try #require(OpponentPolicy.choose(dictionary: words, after: "후가", used: ["후가", "력사", "역사", "나무"],
                                                          difficulty: .adaptiveV2, random: &random, pressure: &pressure))
    #expect(common.contains(obscureOnly.word))
    #expect(obscureOnly.legalReplyCount == 1)
    #expect(obscureOnly.familiarReplyCount == 0)

    let forced = try dictionary(["후가", "가가"])
    let terminal = try #require(OpponentPolicy.choose(dictionary: forced, after: "후가", used: ["후가"], difficulty: .adaptiveV2,
                                                       random: &random, pressure: &pressure))
    #expect(terminal.word == "가가")
    #expect(terminal.legalReplyCount == 0)
    #expect(terminal.familiarReplyCount == 0)
}

@Test func adaptiveV2RecoveryPrefersTheBestReachablePromptWhenFiveAreImpossible() throws {
    let words = try dictionary(["후가", "가나", "가마", "나무", "마루", "마을", "마당", "마음"])
    var pressure = PressureState()
    pressure.computerTurns = 10
    pressure.adaptiveV2 = AdaptivePressureV2(level: 5, recoveryPromptsRemaining: 2)
    var random = SeededRandom(seed: 7)
    let choice = try #require(OpponentPolicy.choose(dictionary: words, after: "후가", used: ["후가"], difficulty: .adaptiveV2,
                                                    random: &random, pressure: &pressure))
    #expect(choice.word == "가마")
    #expect(choice.familiarReplyCount == 4)
    #expect(!choice.usedRecovery)
    #expect(pressure.adaptiveV2?.recoveryPromptsRemaining == 2)
}

@Test(arguments: [6, 8])
func adaptiveV2FavorsRecognizableBotWordsAboveTheReplyFloor(familiarReplyCount: Int) throws {
    let familiarReplies = ["나무", "나비", "나라", "나물", "나사", "나름", "나침반", "나무늘보"]
    let familiar = ["후가", "가나", "마루", "마을", "마음", "다리", "다리미", "다람쥐", "다과", "다음", "다시", "다수", "다운"]
        + familiarReplies.prefix(familiarReplyCount)
    let rare = ["가마", "가다"]
    let entries = familiar.map { WordEntry(word: $0, familiarity: 3) } + rare.map { WordEntry(word: $0, familiarity: 0) }
    let words = try WordDictionary(entries: entries, version: "recognizable-fixture")

    for seed in 0..<30 {
        var pressure = PressureState()
        pressure.adaptiveV2 = AdaptivePressureV2(level: 5)
        var random = SeededRandom(seed: UInt64(seed))
        for _ in 0..<3 {
            let choice = try #require(OpponentPolicy.choose(dictionary: words, after: "후가", used: ["후가"], difficulty: .adaptiveV2,
                                                            random: &random, pressure: &pressure))
            #expect(choice.word == "가나")
            #expect(choice.familiarReplyCount == familiarReplyCount)
        }
        pressure.adaptiveV2 = AdaptivePressureV2(level: 5, recoveryPromptsRemaining: 2)
        let recovery = try #require(OpponentPolicy.choose(dictionary: words, after: "후가", used: ["후가"], difficulty: .adaptiveV2,
                                                           random: &random, pressure: &pressure))
        #expect(recovery.word == "가나")
        #expect(recovery.usedRecovery)
    }
}

@Test func adaptiveV2RecoverySurvivesPendingSaveAndCountsOnlyDeliveredPrompts() throws {
    let counts = [2, 4, 2, 5, 7, 8]
    let fixture = try pacingFixture(familiarCounts: counts)
    let remainingBeforeDelivery = [0, 0, 2, 2, 1, 0]
    let remainingAfterDelivery = [0, 2, 2, 1, 0, 0]
    var engine = fixture.engine
    #expect(engine.state.opponentVersion == OpponentPolicy.adaptiveV2Version)

    for turn in counts.indices {
        let start = TimeInterval(turn * 60)
        engine.beginHumanTurn(at: start)
        #expect(engine.submit(fixture.chain[turn * 2 + 1], at: start + 11) == .accepted)
        #expect(engine.state.pendingComputerWord == fixture.chain[turn * 2 + 2])
        #expect(engine.state.pressure.adaptiveV2?.recoveryPromptsRemaining == remainingBeforeDelivery[turn])

        let saved = try JSONDecoder().decode(MatchState.self, from: JSONEncoder().encode(engine.state))
        var restored = try DuelEngine(dictionary: engine.dictionary, restoring: saved)
        #expect(restored.state.isPaused)
        #expect(restored.state.pendingComputerWord == engine.state.pendingComputerWord)
        #expect(restored.state.random == engine.state.random)
        #expect(restored.state.pressure == engine.state.pressure)
        restored.presentComputerMove()
        #expect(restored.state.pressure == engine.state.pressure)
        restored.resume()
        restored.presentComputerMove()

        engine.pause(at: start + 10)
        engine.resume()
        engine.presentComputerMove()
        #expect(restored.state == engine.state)
        #expect(restored.state.pressure.adaptiveV2?.lastFamiliarReplyCount == counts[turn])
        #expect(restored.state.pressure.adaptiveV2?.recoveryPromptsRemaining == remainingAfterDelivery[turn])
        engine = restored
    }
    engine.beginHumanTurn(at: 600)
    let finalWord = try #require(fixture.chain.last)
    #expect(engine.submit(finalWord, at: 619.9) == .accepted)
    #expect(engine.state.humanWordCount == counts.count + 1)
    #expect(engine.state.outcome == MatchOutcome(winner: .human, reason: .noReply))
}

@Test(arguments: [(Difficulty.adaptiveV2, 20.0), (Difficulty.adaptiveV3, 10.0)])
func adaptivePromptPacingUsesFreshRecentEvidenceAndDistinguishesSubmissionProblems(example: (Difficulty, TimeInterval)) throws {
    let (difficulty, turnDuration) = example
    let fixture = try pacingFixture(familiarCounts: Array(repeating: 8, count: 12), difficulty: difficulty)
    var engine = fixture.engine
    let timings: [TimeInterval] = [0.1, 0.45, 0.5, 0.45, 0.45, 0.45, 0.7, 0.55, 0.7, 0.55, 0.55, 0.55]
    let levels = [0, 0, 0, 1, 1, 2, 2, 2, 1, 1, 1, 0]
    let recoveryRemaining = [0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1]

    for turn in timings.indices {
        let start = TimeInterval(turn * 60)
        engine.beginHumanTurn(at: start)
        #expect(engine.remainingTime(at: start) == turnDuration)
        if turn == 1 || turn == 3 {
            #expect(engine.submit("ㄱ", at: start + 1) == .rejected(.incompleteComposition))
            #expect(engine.submit(fixture.chain[0], at: start + 2) == .rejected(.duplicate))
            #expect(engine.state.pressure.adaptiveV2?.hadSubstantiveRejection == false)
        }
        if turn == 10 || turn == 11 {
            #expect(engine.submit("대한민국", at: start + 1) == .rejected(.missingEntry))
            #expect(engine.state.pressure.adaptiveV2?.hadSubstantiveRejection == true)
        }
        #expect(engine.submit(fixture.chain[turn * 2 + 1], at: start + timings[turn] * turnDuration) == .accepted)
        engine.presentComputerMove()
        #expect(engine.state.pressure.adaptiveV2?.level == levels[turn])
        #expect(engine.state.pressure.adaptiveV2?.recoveryPromptsRemaining == recoveryRemaining[turn])
        #expect(engine.state.pressure.adaptiveV2?.hadSubstantiveRejection == false)
    }
}

@Test(arguments: [20.0, 10.0])
func adaptivePromptPacingInterpretsLateRepliesInTheContextOfTheOfferedPrompt(turnDuration: TimeInterval) {
    var pressure = AdaptivePressureV2(level: 4)
    pressure.recordDeliveredPrompt(familiarReplyCount: 4)
    pressure.recordAccepted(elapsed: 0.75 * turnDuration, turnDuration: turnDuration)
    pressure.recordDeliveredPrompt(familiarReplyCount: 8)
    pressure.recordAccepted(elapsed: 0.75 * turnDuration, turnDuration: turnDuration)
    #expect(pressure.level == 4)
    #expect(pressure.recoveryPromptsRemaining == 0)
    pressure.recordDeliveredPrompt(familiarReplyCount: 4)
    pressure.recordAccepted(elapsed: 0.8 * turnDuration, turnDuration: turnDuration)
    #expect(pressure.level == 3)
    #expect(pressure.recoveryPromptsRemaining == 2)
}

@Test func legacyAdaptivePendingSaveRetainsTheOldPressureAndChoice() throws {
    let data = Data(#"""
        {"id":"00000000-0000-0000-0000-000000000001","startedAt":0,"dictionaryVersion":"fixture-1",
         "connectionVersion":"kkutu-forward-v1","opponentVersion":"adaptive-pacing-1","difficulty":"adaptive",
         "phase":"computer","isPaused":false,"wasResumed":false,"moves":[
         {"id":0,"actor":"seed","word":"사과"},{"id":1,"actor":"human","word":"과자"}],
         "remainingTime":20,"draft":"","pendingComputerWord":"자석","random":{"state":42},
         "pressure":{"demandingTurns":1,"computerTurns":1,"adaptive":{"level":1,"rejectedAttempts":0}}}
        """#.utf8)
    let words = try dictionary(["사과", "과자", "자석", "석류", "유리", "리본"])
    let saved = try JSONDecoder().decode(MatchState.self, from: data)
    var restored = try DuelEngine(dictionary: words, restoring: saved)
    #expect(restored.state.opponentVersion == OpponentPolicy.adaptiveVersion)
    #expect(restored.state.pressure.adaptiveV2 == nil)
    #expect(restored.state.pressure == saved.pressure)
    #expect(restored.state.random == saved.random)
    #expect(restored.state.pendingComputerWord == "자석")
    restored.resume()
    restored.presentComputerMove()
    restored.beginHumanTurn(at: 10)
    #expect(restored.submit("석류", at: 12) == .accepted)
    #expect(restored.state.pendingComputerWord == "유리")
    #expect(restored.state.pressure.adaptive?.level == 2)
}

@Test func legacyV2PendingSaveRoundTripsWithoutRecognitionAndRetainsTwentySeconds() throws {
    let data = Data(#"""
        {"id":"00000000-0000-0000-0000-000000000001","startedAt":0,"dictionaryVersion":"fixture-1",
         "connectionVersion":"kkutu-forward-v1","opponentVersion":"adaptive-pacing-2","difficulty":"adaptiveV2",
         "phase":"computer","isPaused":false,"wasResumed":false,"moves":[
         {"id":0,"actor":"seed","word":"사과"},{"id":1,"actor":"human","word":"과자"}],
         "remainingTime":20,"draft":"","pendingComputerWord":"자석","random":{"state":42},
         "pressure":{"demandingTurns":0,"computerTurns":1,"adaptiveV2":{"level":0,"recoveryPromptsRemaining":0,
         "hardPromptStreak":0,"hadSubstantiveRejection":false,"recent":[]}}}
        """#.utf8)
    let words = try dictionary(["사과", "과자", "자석", "석류", "유리", "리본"])
    let saved = try JSONDecoder().decode(MatchState.self, from: data)
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let original = try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: data), options: .sortedKeys)
    #expect(try encoder.encode(saved) == original)
    var restored = try DuelEngine(dictionary: words, restoring: saved)
    #expect(restored.lastHumanMoveRecognition == nil)
    #expect(restored.state.pendingComputerWord == "자석")
    restored.resume()
    restored.presentComputerMove()
    #expect(restored.state.turnDuration == 20)
    #expect(restored.state.remainingTime == 20)
    restored.beginHumanTurn(at: 10)
    #expect(restored.submit("석류", at: 29.9) == .accepted)
    #expect(restored.state.pendingComputerWord == "유리")
}

private func pacingFixture(familiarCounts: [Int], difficulty: Difficulty = .adaptiveV2) throws -> (engine: DuelEngine, chain: [String]) {
    let syllables = (0...(familiarCounts.count + 1) * 2).compactMap { UnicodeScalar(0xAC00 + $0).map(String.init) }
    let chain = zip(syllables, syllables.dropFirst()).map { $0 + $1 }
    let alternatives = familiarCounts.enumerated().flatMap { index, count in
        "한학할함합행햇".prefix(count - 1).map { syllables[3 + index * 2] + String($0) }
    }
    let words = try dictionary(chain + alternatives)
    return (try DuelEngine(dictionary: words, seed: chain[0], difficulty: difficulty, randomSeed: 13), chain)
}
