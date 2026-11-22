import Foundation

public enum Actor: String, Codable, Sendable { case seed, human, computer }
public enum MatchPhase: String, Codable, Sendable { case preparing, human, computer, completed }
public enum OutcomeReason: String, Codable, Sendable { case noReply, timeout, resignation }

public struct MatchOutcome: Codable, Equatable, Sendable {
    public let winner: Actor
    public let reason: OutcomeReason
}

public enum SpecialMoveKind: String, Codable, Sendable {
    case finishing, pressure, returning
}

public struct HumanMoveRecognition: Equatable, Sendable {
    public let moveID: Int
    public let kinds: Set<SpecialMoveKind>
    public let primary: SpecialMoveKind
}

public struct PlayedWord: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let actor: Actor
    public let word: String
    private let specialKinds: [SpecialMoveKind]?

    init(id: Int, actor: Actor, word: String, specialKinds: [SpecialMoveKind]? = nil) {
        self.id = id
        self.actor = actor
        self.word = word
        self.specialKinds = specialKinds
    }

    public var recognition: HumanMoveRecognition? {
        guard actor == .human, let specialKinds, let primary = specialKinds.first else { return nil }
        return HumanMoveRecognition(moveID: id, kinds: Set(specialKinds), primary: primary)
    }
}

public struct MatchState: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let startedAt: Date
    public let dictionaryVersion: String
    public let connectionVersion: String
    public let opponentVersion: String
    public let difficulty: Difficulty
    public var phase: MatchPhase
    public var isPaused: Bool
    public var wasResumed: Bool
    public var moves: [PlayedWord]
    public var remainingTime: TimeInterval
    public var draft: String
    public var pendingComputerWord: String?
    public var random: SeededRandom
    public var pressure: PressureState
    public var outcome: MatchOutcome?
    public var currentWord: String { moves.last?.word ?? "" }
    public var usedWords: Set<String> { Set(moves.map(\.word)) }
    public var humanWordCount: Int { moves.count / 2 }
    public var turnDuration: TimeInterval { difficulty.turnDuration }
    public var allowedStarts: [String] { ConnectionRules.allowedStarts(after: String(currentWord.suffix(1))) }
}

public enum EngineError: Error, Equatable {
    case invalidSeed, terminalSeed, incompatibleVersions, invalidSavedState
}

public enum SubmissionResult: Equatable, Sendable {
    case accepted
    case rejected(Rejection)
    case late
    case unavailable
}

public struct DuelEngine: Sendable {
    /// The original allowance. Use `MatchState.turnDuration` for a particular match.
    public static let turnDuration: TimeInterval = 20
    public let dictionary: WordDictionary
    public private(set) var state: MatchState
    public var lastHumanMoveRecognition: HumanMoveRecognition? { state.moves.last { $0.actor == .human }?.recognition }
    private var activeSince: TimeInterval?
    private var used: Set<String>

    public init(dictionary: WordDictionary, seed: String, difficulty: Difficulty, randomSeed: UInt64,
                id: UUID = UUID(), startedAt: Date = Date()) throws {
        guard dictionary.entries[seed] != nil, !dictionary.excludedWords.contains(seed) else { throw EngineError.invalidSeed }
        guard dictionary.hasLegalReply(after: seed, used: [seed]) else { throw EngineError.terminalSeed }
        self.dictionary = dictionary
        self.used = [seed]
        var pressure = PressureState()
        if difficulty == .adaptive { pressure.adaptive = AdaptivePressure() }
        if difficulty.usesPromptPacing { pressure.adaptiveV2 = AdaptivePressureV2() }
        self.state = MatchState(id: id, startedAt: startedAt, dictionaryVersion: dictionary.version,
                                connectionVersion: ConnectionRules.version, opponentVersion: OpponentPolicy.version(for: difficulty),
                                difficulty: difficulty, phase: .preparing, isPaused: false, wasResumed: false,
                                moves: [PlayedWord(id: 0, actor: .seed, word: seed)], remainingTime: difficulty.turnDuration,
                                draft: "", pendingComputerWord: nil, random: SeededRandom(seed: randomSeed),
                                pressure: pressure, outcome: nil)
    }

    public init(dictionary: WordDictionary, restoring saved: MatchState) throws {
        guard saved.dictionaryVersion == dictionary.version, saved.connectionVersion == ConnectionRules.version,
              saved.opponentVersion == OpponentPolicy.version(for: saved.difficulty) else { throw EngineError.incompatibleVersions }
        guard Self.isValid(saved, dictionary: dictionary) else { throw EngineError.invalidSavedState }
        self.dictionary = dictionary
        self.state = saved
        self.used = saved.usedWords
        if saved.phase != .completed {
            self.state.isPaused = true
            self.state.wasResumed = true
        }
    }

    public mutating func updateDraft(_ draft: String) {
        guard state.phase == .human, !state.isPaused else { return }
        state.draft = draft
    }

    public mutating func beginHumanTurn(at now: TimeInterval) {
        guard !state.isPaused, state.phase == .preparing || state.phase == .human, activeSince == nil else { return }
        state.phase = .human
        activeSince = now
    }

    public func remainingTime(at now: TimeInterval) -> TimeInterval {
        guard let activeSince else { return state.remainingTime }
        return max(0, state.remainingTime - max(0, now - activeSince))
    }

    public mutating func submit(_ input: String, at timestamp: TimeInterval) -> SubmissionResult {
        guard state.phase == .human, !state.isPaused, activeSince != nil else { return .unavailable }
        let remaining = remainingTime(at: timestamp)
        guard remaining > 0 else {
            finish(winner: .computer, reason: .timeout)
            return .late
        }
        if let rejection = dictionary.rejection(for: input, after: state.currentWord, used: used) {
            state.draft = input
            state.pressure.adaptive?.recordRejection()
            state.pressure.adaptiveV2?.recordRejection(rejection)
            return .rejected(rejection)
        }
        let computerTurns = state.pressure.computerTurns
        let turnDuration = state.turnDuration
        let elapsed = turnDuration - remaining
        state.pressure.adaptive?.recordAccepted(elapsed: elapsed, computerTurns: computerTurns)
        state.pressure.adaptiveV2?.recordAccepted(elapsed: elapsed, turnDuration: turnDuration)
        append(ConnectionRules.normalized(input), actor: .human)
        state.draft = ""
        activeSince = nil
        if let choice = OpponentPolicy.choose(dictionary: dictionary, after: state.currentWord, used: used,
                                              difficulty: state.difficulty, random: &state.random, pressure: &state.pressure) {
            state.phase = .computer
            state.pendingComputerWord = choice.word
        } else {
            finish(winner: .human, reason: .noReply)
        }
        return .accepted
    }

    public mutating func presentComputerMove() {
        guard state.phase == .computer, !state.isPaused, let word = state.pendingComputerWord else { return }
        append(word, actor: .computer)
        state.pendingComputerWord = nil
        if !dictionary.hasLegalReply(after: word, used: used) {
            finish(winner: .computer, reason: .noReply)
        } else {
            state.phase = .preparing
            state.remainingTime = state.turnDuration
            if state.difficulty.usesPromptPacing {
                let counts = dictionary.availableReplyCounts(starts: state.allowedStarts,
                                                             usedCounts: dictionary.usedReplyCountsByStart(used))
                state.pressure.adaptiveV2?.recordDeliveredPrompt(familiarReplyCount: counts.familiar)
            }
        }
    }

    public mutating func advanceTime(to now: TimeInterval) {
        guard state.phase == .human, !state.isPaused, activeSince != nil else { return }
        if remainingTime(at: now) <= 0 { finish(winner: .computer, reason: .timeout) }
    }

    public mutating func checkpoint(at now: TimeInterval) {
        guard let activeSince else { return }
        state.remainingTime = max(0, state.remainingTime - max(0, now - activeSince))
        self.activeSince = now
        if state.remainingTime == 0 { finish(winner: .computer, reason: .timeout) }
    }

    public mutating func pause(at now: TimeInterval) {
        guard state.phase != .completed else { return }
        checkpoint(at: now)
        guard state.phase != .completed else { return }
        activeSince = nil
        state.isPaused = true
    }

    public mutating func resume() {
        guard state.phase != .completed, state.isPaused else { return }
        state.isPaused = false
        state.wasResumed = true
        // The UI explicitly calls beginHumanTurn only after input/announcement readiness.
    }

    public mutating func resign() {
        guard state.phase != .completed else { return }
        finish(winner: .computer, reason: .resignation)
    }

    private mutating func append(_ word: String, actor: Actor) {
        used.insert(word)
        var specialKinds: [SpecialMoveKind] = []
        if state.difficulty == .adaptiveV3, actor == .human {
            let ending = String(word.suffix(1))
            let counts = dictionary.availableReplyCounts(starts: ConnectionRules.allowedStarts(after: ending),
                                                         usedCounts: dictionary.usedReplyCountsByStart(used))
            if counts.legal == 0 {
                specialKinds.append(.finishing)
            } else if counts.familiar <= 1 {
                specialKinds.append(.pressure)
            }
            if state.moves.last(where: { $0.actor == .human })?.word.suffix(1) == word.suffix(1) {
                specialKinds.append(.returning)
            }
        }
        state.moves.append(PlayedWord(id: state.moves.count, actor: actor, word: word,
                                      specialKinds: specialKinds.isEmpty ? nil : specialKinds))
    }

    private mutating func finish(winner: Actor, reason: OutcomeReason) {
        guard state.outcome == nil else { return }
        state.outcome = MatchOutcome(winner: winner, reason: reason)
        state.phase = .completed
        state.isPaused = false
        state.pendingComputerWord = nil
        activeSince = nil
        if reason == .timeout { state.remainingTime = 0 }
    }

    private static func isValid(_ saved: MatchState, dictionary: WordDictionary) -> Bool {
        guard !saved.moves.isEmpty, saved.moves[0].actor == .seed,
              saved.remainingTime.isFinite, (0...saved.turnDuration).contains(saved.remainingTime),
              saved.moves.count == saved.usedWords.count,
              (saved.phase == .completed) == (saved.outcome != nil),
              (saved.phase == .computer) == (saved.pendingComputerWord != nil) else { return false }
        if saved.difficulty == .adaptive || saved.difficulty.usesPromptPacing {
            guard (0...saved.humanWordCount).contains(saved.pressure.computerTurns),
                  (0...saved.pressure.computerTurns).contains(saved.pressure.demandingTurns) else { return false }
        }
        if saved.difficulty == .adaptive, saved.pressure.adaptive?.isValid != true { return false }
        if saved.difficulty.usesPromptPacing {
            guard saved.pressure.adaptive == nil, saved.pressure.adaptiveV2?.isValid == true else { return false }
        }
        var used: Set<String> = []
        for (index, move) in saved.moves.enumerated() {
            guard move.id == index, dictionary.entries[move.word] != nil,
                  !dictionary.excludedWords.contains(move.word) else { return false }
            if index > 0 {
                guard move.actor == (index % 2 == 1 ? .human : .computer),
                      dictionary.rejection(for: move.word, after: saved.moves[index - 1].word, used: used) == nil else { return false }
            }
            used.insert(move.word)
        }
        if let pending = saved.pendingComputerWord,
           dictionary.rejection(for: pending, after: saved.currentWord, used: used) != nil { return false }
        if saved.phase == .computer, saved.moves.last?.actor != .human { return false }
        if saved.phase == .human || saved.phase == .preparing {
            guard saved.moves.last?.actor != .human,
                  dictionary.hasLegalReply(after: saved.currentWord, used: used) else { return false }
        }
        if let outcome = saved.outcome {
            guard outcome.winner != .seed else { return false }
            switch outcome.reason {
            case .noReply:
                guard saved.moves.count > 1, saved.moves.last?.actor == outcome.winner,
                      !dictionary.hasLegalReply(after: saved.currentWord, used: used) else { return false }
            case .timeout:
                guard outcome.winner == .computer, saved.remainingTime == 0,
                      saved.moves.last?.actor != .human else { return false }
            case .resignation:
                guard outcome.winner == .computer else { return false }
            }
        }
        return true
    }
}
