import Foundation
import Testing
@testable import WordChainKit

func makeEngine(_ words: [String] = ["사과", "과자", "자석", "석류", "유리", "리본", "본문"]) throws -> DuelEngine {
    try DuelEngine(dictionary: dictionary(words), seed: words[0], difficulty: .normal, randomSeed: 42)
}

@Test(arguments: [(19.999, true), (20.0, false), (20.001, false)])
func deadlineIsExclusive(example: (Double, Bool)) throws {
    var engine = try makeEngine()
    engine.beginHumanTurn(at: 100)
    #expect(engine.submit("과자", at: 100 + example.0) == (example.1 ? .accepted : .late))
    #expect(engine.state.outcome?.reason == (example.1 ? nil : .timeout))
}

@Test(arguments: [(9.999, true), (10.0, false), (10.001, false)])
func currentDeadlineIsExclusiveAndRefreshesAfterComputerReply(example: (Double, Bool)) throws {
    let words = try dictionary(["사과", "과자", "자석", "석류"])
    var engine = try DuelEngine(dictionary: words, seed: "사과", difficulty: .adaptiveV3, randomSeed: 42)
    #expect(engine.state.opponentVersion == OpponentPolicy.adaptiveV3Version)
    #expect(engine.state.turnDuration == 10)
    #expect(engine.state.remainingTime == 10)
    engine.beginHumanTurn(at: 100)
    engine.checkpoint(at: 105)
    #expect(engine.state.remainingTime == 5)
    #expect(engine.submit("과자", at: 100 + example.0) == (example.1 ? .accepted : .late))
    #expect(engine.state.outcome?.reason == (example.1 ? nil : .timeout))
    if example.1 {
        engine.presentComputerMove()
        #expect(engine.state.phase == .preparing)
        #expect(engine.remainingTime(at: 200) == 10)
    }
    var invalid = engine.state
    invalid.remainingTime = 10.001
    #expect(throws: EngineError.invalidSavedState) { try DuelEngine(dictionary: words, restoring: invalid) }
}

@Test(arguments: [
    ("파력", [], [.finishing, .returning], .finishing),
    ("파력", [WordEntry(word: "역사", familiarity: 0)], [.pressure, .returning], .pressure),
    ("파력", [WordEntry(word: "역사", familiarity: 2)], [.pressure, .returning], .pressure),
    ("파력", [WordEntry(word: "역사", familiarity: 2), WordEntry(word: "력기", familiarity: 3)], [.returning], .returning),
    ("파역", [WordEntry(word: "역사", familiarity: 2)], [.pressure], .pressure)
] as [(String, [WordEntry], Set<SpecialMoveKind>, SpecialMoveKind)])
func specialMovesUseExactHumanEndingAndRemainingLegalReplies(
    example: (word: String, available: [WordEntry], kinds: Set<SpecialMoveKind>, primary: SpecialMoveKind)
) throws {
    let chain = ["사과", "과력", "력파", example.word, "역할"]
    let entries = chain.map { WordEntry(word: $0, familiarity: 3) } + example.available
    let words = try WordDictionary(entries: entries, version: "recognition-fixture", excludedWords: ["역할"])
    var engine = try DuelEngine(dictionary: words, seed: chain[0], difficulty: .adaptiveV3, randomSeed: 42)
    engine.beginHumanTurn(at: 0)
    #expect(engine.submit(chain[1], at: 1) == .accepted)
    #expect(engine.state.pendingComputerWord == chain[2])
    #expect(engine.lastHumanMoveRecognition?.kinds.contains(.returning) != true)
    engine.presentComputerMove()
    engine.beginHumanTurn(at: 3)
    #expect(engine.submit(example.word, at: 4) == .accepted)
    let recognition = try #require(engine.lastHumanMoveRecognition)
    #expect(recognition == HumanMoveRecognition(moveID: 3, kinds: example.kinds, primary: example.primary))
    #expect(engine.state.moves.count == 4)
    #expect(engine.state.outcome?.winner == (example.available.isEmpty ? .human : nil))

    let saved = try JSONDecoder().decode(MatchState.self, from: JSONEncoder().encode(engine.state))
    var restored = try DuelEngine(dictionary: words, restoring: saved)
    #expect(restored.lastHumanMoveRecognition == recognition)
    restored.resume()
    restored.presentComputerMove()
    #expect(restored.lastHumanMoveRecognition == recognition)
    #expect(restored.state.moves.last(where: { $0.actor == .human })?.recognition == recognition)
}

@Test func specialMovesConsumeTheirOwnWordAndIgnoreTheSeedForReturns() throws {
    let words = try dictionary(["나다", "다다", "다시"])
    var engine = try DuelEngine(dictionary: words, seed: "나다", difficulty: .adaptiveV3, randomSeed: 42)
    engine.beginHumanTurn(at: 0)
    #expect(engine.submit("다", at: 1) == .rejected(.tooShort))
    #expect(engine.lastHumanMoveRecognition == nil)
    #expect(engine.submit("다다", at: 2) == .accepted)
    #expect(engine.lastHumanMoveRecognition == HumanMoveRecognition(moveID: 1, kinds: [.pressure], primary: .pressure))
}

@Test func rejectedInputDoesNotResetClockAndDuplicateSubmitCannotCommitTwice() throws {
    var engine = try makeEngine()
    engine.beginHumanTurn(at: 0)
    #expect(engine.submit("과", at: 5) == .rejected(.tooShort))
    #expect(engine.remainingTime(at: 6) == 14)
    #expect(engine.state.draft == "과")
    #expect(engine.submit("과자", at: 6) == .accepted)
    #expect(engine.submit("과자", at: 6) == .unavailable)
    #expect(engine.state.humanWordCount == 1)
    #expect(engine.state.draft.isEmpty)
}

@Test func computerTerminalCreditsMoveAndSettlesOnlyOnce() throws {
    var engine = try makeEngine(["사과", "과자", "자석"])
    engine.beginHumanTurn(at: 0)
    #expect(engine.submit("과자", at: 1) == .accepted)
    #expect(engine.state.outcome == nil)
    #expect(engine.state.pendingComputerWord == "자석")
    engine.presentComputerMove()
    #expect(engine.state.moves.last?.word == "자석")
    #expect(engine.state.outcome == MatchOutcome(winner: .computer, reason: .noReply))
    let completed = engine.state
    engine.presentComputerMove()
    engine.advanceTime(to: 100)
    engine.resign()
    #expect(engine.state == completed)
}

@Test func obscureReplyIsNotExhaustion() throws {
    let words = try dictionary(["사과", "과자", "자석", "석류"], familiarity: 0)
    var engine = try DuelEngine(dictionary: words, seed: "사과", difficulty: .easy, randomSeed: 4)
    engine.beginHumanTurn(at: 0)
    #expect(engine.submit("과자", at: 1) == .accepted)
    #expect(engine.state.phase == .computer)
    engine.presentComputerMove()
    #expect(engine.state.outcome == nil)
    #expect(engine.state.phase == .preparing)
}

@Test func pauseFreezesTimeAndReadinessStartsSavedAllowance() throws {
    var engine = try makeEngine()
    engine.beginHumanTurn(at: 10)
    engine.updateDraft("과")
    engine.pause(at: 15)
    #expect(engine.state.remainingTime == 15)
    #expect(engine.state.draft == "과")
    engine.advanceTime(to: 100)
    #expect(engine.state.outcome == nil)
    engine.resume()
    #expect(engine.submit("과자", at: 100) == .unavailable)
    engine.beginHumanTurn(at: 100)
    #expect(engine.remainingTime(at: 102) == 13)
    #expect(engine.submit("과자", at: 114.9) == .accepted)
}

@Test func inactiveAtDeadlineTimesOutButTimelySubmissionAlreadyAdvances() throws {
    var late = try makeEngine()
    late.beginHumanTurn(at: 0)
    late.pause(at: 20)
    #expect(late.state.outcome?.reason == .timeout)
    var timely = try makeEngine()
    timely.beginHumanTurn(at: 0)
    #expect(timely.submit("과자", at: 19.9) == .accepted)
    timely.pause(at: 20)
    #expect(timely.state.phase == .computer)
    #expect(timely.state.isPaused)
    #expect(timely.state.outcome == nil)
    timely.presentComputerMove()
    #expect(timely.state.moves.count == 2)
}

@Test func checkpointRestoresPausedWithoutRerollOrWallClockDependence() throws {
    var engine = try makeEngine()
    engine.beginHumanTurn(at: 1_000)
    engine.checkpoint(at: 1_007)
    engine.updateDraft("과")
    let saved = try JSONDecoder().decode(MatchState.self, from: JSONEncoder().encode(engine.state))
    var restored = try DuelEngine(dictionary: engine.dictionary, restoring: saved)
    #expect(restored.state.isPaused)
    #expect(restored.state.wasResumed)
    #expect(restored.state.remainingTime == 13)
    restored.resume()
    restored.beginHumanTurn(at: 5)
    #expect(restored.remainingTime(at: 7) == 11)
    #expect(restored.submit("과자", at: 8) == .accepted)
    let pending = restored.state
    let recovered = try DuelEngine(dictionary: restored.dictionary, restoring: pending)
    #expect(recovered.state.pendingComputerWord == pending.pendingComputerWord)
    #expect(recovered.state.random == pending.random)
    #expect(recovered.state.pressure == pending.pressure)
}

@Test func versionMismatchAndCorruptChainRejected() throws {
    let engine = try makeEngine()
    let newer = try WordDictionary(entries: Array(engine.dictionary.entries.values), version: "new")
    #expect(throws: EngineError.incompatibleVersions) { try DuelEngine(dictionary: newer, restoring: engine.state) }
    var corrupt = engine.state
    corrupt.moves.append(PlayedWord(id: 1, actor: .human, word: "사과"))
    #expect(throws: EngineError.invalidSavedState) { try DuelEngine(dictionary: engine.dictionary, restoring: corrupt) }
}

@Test func pausePreparingAndComputerNeverSpendsHumanTime() throws {
    var engine = try makeEngine()
    engine.pause(at: 1)
    engine.beginHumanTurn(at: 10)
    #expect(engine.state.phase == .preparing)
    engine.resume()
    engine.beginHumanTurn(at: 100)
    _ = engine.submit("과자", at: 101)
    engine.presentComputerMove()
    #expect(engine.state.phase == .preparing)
    #expect(engine.remainingTime(at: 100_000) == 20)
    engine.beginHumanTurn(at: 100_000)
    #expect(engine.remainingTime(at: 100_002) == 18)
}

@Test func adaptiveRunCountsEveryAcceptedWordIncludingTheFinisherAndCapsPressure() throws {
    let chain = adaptiveChain(turns: 22)
    var engine = try adaptiveEngine(chain)
    var slow = engine
    for turn in 0..<22 {
        let start = TimeInterval(turn * 60)
        let previousLevel = try #require(engine.state.pressure.adaptive?.level)
        engine.beginHumanTurn(at: start)
        slow.beginHumanTurn(at: start)
        #expect(engine.remainingTime(at: start) == 20)
        #expect(slow.remainingTime(at: start) == 20)
        #expect(engine.submit(chain[turn * 2 + 1], at: start + 2) == .accepted)
        #expect(slow.submit(chain[turn * 2 + 1], at: start + 16) == .accepted)
        let newLevel = try #require(engine.state.pressure.adaptive?.level)
        #expect((0...1).contains(newLevel - previousLevel))
        #expect(slow.state.pressure.adaptive?.level == 0)
        #expect(engine.state.humanWordCount == turn + 1)
        if turn < 21 {
            engine.presentComputerMove()
            slow.presentComputerMove()
            #expect(engine.state.phase == .preparing)
        }
    }
    #expect(engine.state.pressure.adaptive?.level == 8)
    #expect(engine.state.phase == .completed)
    #expect(engine.state.outcome == MatchOutcome(winner: .human, reason: .noReply))
    #expect(engine.state.moves.map(\.word) == chain)
}

@Test func adaptivePressureAndPendingChoiceSurvivePauseAndRestore() throws {
    let chain = adaptiveChain(turns: 5)
    var uninterrupted = try adaptiveEngine(chain)
    for turn in 0..<3 {
        let start = TimeInterval(turn * 60)
        uninterrupted.beginHumanTurn(at: start)
        #expect(uninterrupted.submit(chain[turn * 2 + 1], at: start + 2) == .accepted)
        uninterrupted.presentComputerMove()
    }
    #expect(uninterrupted.state.pressure.adaptive?.level == 3)
    uninterrupted.beginHumanTurn(at: 180)
    #expect(uninterrupted.submit("가", at: 181) == .rejected(.tooShort))
    var paused = uninterrupted
    paused.pause(at: 182)

    let saved = try JSONDecoder().decode(MatchState.self, from: JSONEncoder().encode(paused.state))
    var restored = try DuelEngine(dictionary: paused.dictionary, restoring: saved)
    #expect(restored.state.opponentVersion == OpponentPolicy.adaptiveVersion)
    #expect(restored.state.remainingTime == 18)
    #expect(restored.state.pressure.adaptive?.rejectedAttempts == 1)
    restored.resume()
    restored.beginHumanTurn(at: 1_000)
    #expect(uninterrupted.submit("가", at: 183) == .rejected(.tooShort))
    #expect(restored.submit("가", at: 1_001) == .rejected(.tooShort))
    #expect(uninterrupted.submit(chain[7], at: 184) == .accepted)
    #expect(restored.submit(chain[7], at: 1_002) == .accepted)
    #expect(restored.state.pressure == uninterrupted.state.pressure)
    #expect(restored.state.pressure.adaptive?.level == 2)
    #expect(restored.state.pressure.adaptive?.rejectedAttempts == 0)
    #expect(restored.state.random == uninterrupted.state.random)
    #expect(restored.state.pendingComputerWord == chain[8])

    let pending = try JSONDecoder().decode(MatchState.self, from: JSONEncoder().encode(restored.state))
    var replay = try DuelEngine(dictionary: restored.dictionary, restoring: pending)
    replay.resume()
    replay.presentComputerMove()
    restored.presentComputerMove()
    #expect(replay.state == restored.state)
}

@Test func adaptivePressureIncludesActiveTimeSpentBeforeCheckpoint() throws {
    let chain = adaptiveChain(turns: 4)
    var engine = try adaptiveEngine(chain)
    engine.beginHumanTurn(at: 100)
    #expect(engine.submit(chain[1], at: 102) == .accepted)
    engine.presentComputerMove()
    #expect(engine.state.pressure.adaptive?.level == 1)
    engine.beginHumanTurn(at: 200)
    engine.checkpoint(at: 211)
    engine.pause(at: 212)
    engine.resume()
    engine.beginHumanTurn(at: 900)
    #expect(engine.submit(chain[3], at: 902) == .accepted)
    #expect(engine.state.pressure.adaptive?.level == 0)
}

@Test(arguments: [Difficulty.easy, .normal])
func legacySaveWithoutAdaptivePressureCanResume(difficulty: Difficulty) throws {
    let chain = adaptiveChain(turns: 3)
    let words = try dictionary(chain)
    var engine = try DuelEngine(dictionary: words, seed: chain[0], difficulty: difficulty, randomSeed: 5)
    engine.beginHumanTurn(at: 100)
    #expect(engine.submit(chain[1], at: 102) == .accepted)
    engine.presentComputerMove()
    let data = try JSONEncoder().encode(engine.state)
    #expect(!String(decoding: data, as: UTF8.self).contains("adaptive"))
    let saved = try JSONDecoder().decode(MatchState.self, from: data)
    var restored = try DuelEngine(dictionary: words, restoring: saved)
    #expect(restored.state.opponentVersion == "bounded-pacing-1")
    #expect(restored.state.pressure.adaptive == nil)
    restored.resume()
    restored.beginHumanTurn(at: 110)
    #expect(restored.submit(chain[3], at: 112) == .accepted)
    #expect(restored.state.pendingComputerWord == chain[4])
}

@Test func adaptiveForcedTerminalEndsTheRunWithTheHumanScoreIntact() throws {
    let chain = Array(adaptiveChain(turns: 3).dropLast())
    var engine = try adaptiveEngine(chain)
    for turn in 0..<2 {
        let start = TimeInterval(turn * 60)
        engine.beginHumanTurn(at: start)
        #expect(engine.submit(chain[turn * 2 + 1], at: start + 2) == .accepted)
        engine.presentComputerMove()
    }
    #expect(engine.state.outcome == MatchOutcome(winner: .computer, reason: .noReply))
    #expect(engine.state.humanWordCount == 2)
    let finished = engine.state
    engine.beginHumanTurn(at: 200)
    engine.presentComputerMove()
    #expect(engine.state == finished)
}

private func adaptiveChain(turns: Int) -> [String] {
    let syllables = (0...turns * 2).compactMap { UnicodeScalar(0xAC00 + $0).map(String.init) }
    return zip(syllables, syllables.dropFirst()).map { $0 + $1 }
}

private func adaptiveEngine(_ chain: [String]) throws -> DuelEngine {
    try DuelEngine(dictionary: dictionary(chain), seed: chain[0], difficulty: .adaptive, randomSeed: 5)
}
