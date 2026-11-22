import Foundation

public enum Difficulty: String, Codable, CaseIterable, Sendable {
    case easy, normal, adaptive, adaptiveV2, adaptiveV3

    public var turnDuration: TimeInterval { self == .adaptiveV3 ? 10 : DuelEngine.turnDuration }

    var usesPromptPacing: Bool { self == .adaptiveV2 || self == .adaptiveV3 }
}

public struct PressureState: Codable, Equatable, Sendable {
    public var demandingTurns: Int = 0
    public var computerTurns: Int = 0
    var adaptive: AdaptivePressure?
    var adaptiveV2: AdaptivePressureV2?
    public init() {}
}

struct AdaptivePressure: Codable, Equatable, Sendable {
    private static let maximumLevel = 8
    private static let maximumRejections = 3
    private(set) var level = 0
    private(set) var rejectedAttempts = 0

    var isValid: Bool {
        (0...Self.maximumLevel).contains(level) && (0...Self.maximumRejections).contains(rejectedAttempts)
    }

    mutating func recordRejection() {
        rejectedAttempts = min(rejectedAttempts + 1, Self.maximumRejections)
    }

    mutating func recordAccepted(elapsed: TimeInterval, computerTurns: Int) {
        if elapsed >= 14 || rejectedAttempts >= 2 {
            level = max(0, level - 1)
        } else if rejectedAttempts == 0 && (elapsed <= 7 || (computerTurns > 0 && computerTurns.isMultiple(of: 3))) {
            level = min(Self.maximumLevel, level + 1)
        }
        rejectedAttempts = 0
    }
}

public struct SeededRandom: Codable, Equatable, Sendable, RandomNumberGenerator {
    public private(set) var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }

    public mutating func shuffled<Element>(_ values: [Element]) -> [Element] {
        var result = values
        guard result.count > 1 else { return result }
        // Keep the sampling algorithm stable across standard-library updates.
        for index in stride(from: result.count - 1, through: 1, by: -1) {
            result.swapAt(index, Int(next() % UInt64(index + 1)))
        }
        return result
    }
}

public struct ComputerChoice: Equatable, Sendable {
    public let word: String
    public let legalReplyCount: Int
    public let familiarReplyCount: Int
    public let exploredPositions: Int
    public let usedRecovery: Bool
}

public enum OpponentPolicy {
    public static let version = "bounded-pacing-1"
    public static let adaptiveVersion = "adaptive-pacing-1"
    public static let adaptiveV2Version = "adaptive-pacing-2"
    public static let adaptiveV3Version = "adaptive-pacing-3"
    public static let familiarThreshold = 2

    static func version(for difficulty: Difficulty) -> String {
        switch difficulty {
        case .easy, .normal: version
        case .adaptive: adaptiveVersion
        case .adaptiveV2: adaptiveV2Version
        case .adaptiveV3: adaptiveV3Version
        }
    }

    public static func choose(dictionary: WordDictionary, after word: String, used: Set<String>, difficulty: Difficulty,
                              random: inout SeededRandom, pressure: inout PressureState,
                              pacingEnabled: Bool = true) -> ComputerChoice? {
        // Discovery is complete; only strategic evaluation is sampled and bounded.
        let legal = dictionary.legalReplies(after: word, used: used)
        guard !legal.isEmpty else { return nil }
        if difficulty == .adaptive {
            return chooseAdaptive(dictionary: dictionary, legal: legal, used: used, random: &random,
                                  pressure: &pressure, pacingEnabled: pacingEnabled)
        }
        if difficulty.usesPromptPacing {
            let choice = chooseAdaptiveV2(dictionary: dictionary, legal: legal, used: used, random: &random,
                                          pressure: pressure, pacingEnabled: pacingEnabled)
            pressure.computerTurns += 1
            return choice
        }
        let limit = difficulty == .easy ? 24 : 48
        let shuffled = random.shuffled(legal)
        let familiarCandidates = Array(shuffled.filter { (dictionary.entries[$0]?.familiarity ?? 0) >= familiarThreshold }
            .prefix(limit * 3 / 4))
        let preferred = Set(familiarCandidates)
        let candidates = familiarCandidates + shuffled.filter { !preferred.contains($0) }.prefix(limit - familiarCandidates.count)
        let recoveryRequested = pacingEnabled && (pressure.computerTurns == 0 || pressure.demandingTurns >= 2)
        var explored = 0
        var scored: [(word: String, score: Int, replies: Int, familiar: Int)] = []
        for candidate in candidates {
            explored += 1
            let nextUsed = used.union([candidate])
            let replies = dictionary.legalReplies(after: candidate, used: nextUsed)
            let familiar = replies.filter { (dictionary.entries[$0]?.familiarity ?? 0) >= familiarThreshold }.count
            let own = dictionary.entries[candidate]?.familiarity ?? 0
            var score = own * (difficulty == .easy ? 24 : 7)
            score += min(familiar, 8) * (difficulty == .easy ? 9 : 3)
            score -= min(replies.count, 20) * (difficulty == .easy ? 0 : 2)
            if replies.isEmpty { score += difficulty == .normal ? 1_000 : 20 }
            if difficulty == .normal {
                for reply in replies.prefix(24) {
                    explored += 1
                    if !dictionary.hasLegalReply(after: reply, used: nextUsed.union([reply])) {
                        score -= 300
                        break
                    }
                }
            }
            scored.append((candidate, score, replies.count, familiar))
        }
        let recoveryCandidates = scored.filter { $0.familiar >= 3 }
        let useRecovery = recoveryRequested && !recoveryCandidates.isEmpty
        // Normal retains its immediate winning choice even during a recovery preference.
        let hasImmediateWin = difficulty == .normal && scored.contains { $0.replies == 0 }
        if useRecovery && !hasImmediateWin {
            scored = recoveryCandidates.map { ($0.word, $0.score + min($0.familiar, 8) * 15, $0.replies, $0.familiar) }
        }
        scored.sort { $0.score == $1.score ? $0.word < $1.word : $0.score > $1.score }
        let best = scored[0].score
        let pool = Array(scored.filter { $0.score >= best - (difficulty == .easy ? 65 : 20) }
            .prefix(difficulty == .easy ? 12 : 4))
        let selected = pool[weightedIndex(count: pool.count, random: &random)]
        pressure.computerTurns += 1
        pressure.demandingTurns = selected.familiar < 3 ? pressure.demandingTurns + 1 : 0
        return ComputerChoice(word: selected.word, legalReplyCount: selected.replies,
                              familiarReplyCount: selected.familiar, exploredPositions: explored,
                              usedRecovery: useRecovery && !hasImmediateWin)
    }

    private static func chooseAdaptive(dictionary: WordDictionary, legal: [String], used: Set<String>,
                                       random: inout SeededRandom, pressure: inout PressureState,
                                       pacingEnabled: Bool) -> ComputerChoice {
        let sampleLimit = 24
        var familiar: [String] = []
        var rare: [String] = []
        for word in legal {
            if (dictionary.entries[word]?.familiarity ?? 0) >= familiarThreshold {
                familiar.append(word)
            } else {
                rare.append(word)
            }
        }

        var examplesByEnding: [String: [String]] = [:]
        func leavesHumanReply(_ candidate: String) -> Bool {
            let ending = String(candidate.suffix(1))
            let examples = examplesByEnding[ending] ?? dictionary.firstTwoLegalReplies(afterEnding: ending, used: used)
            examplesByEnding[ending] = examples
            // Two examples suffice because the candidate itself is the only newly used word.
            return examples.contains { $0 != candidate }
        }

        func sampleContinuations(from words: [String]) -> [String] {
            let shuffled = random.shuffled(words)
            let sampled = shuffled.prefix(sampleLimit).filter(leavesHumanReply)
            if !sampled.isEmpty { return sampled }
            if let fallback = shuffled.dropFirst(sampleLimit).first(where: leavesHumanReply) { return [fallback] }
            return []
        }

        var candidates = sampleContinuations(from: familiar)
        if candidates.isEmpty { candidates = sampleContinuations(from: rare) }
        guard !candidates.isEmpty else {
            let forced = familiar.isEmpty ? rare : familiar
            let selected = forced[Int(random.next() % UInt64(forced.count))]
            pressure.computerTurns += 1
            pressure.demandingTurns += 1
            return ComputerChoice(word: selected, legalReplyCount: 0, familiarReplyCount: 0,
                                  exploredPositions: 1, usedRecovery: false)
        }

        let wantsRecovery = pacingEnabled && pressure.demandingTurns >= 2
        // Ramp the maximum pressure after the first two computer moves.
        let level = wantsRecovery ? 0 : min(pressure.adaptive?.level ?? 0, max(0, pressure.computerTurns - 1))
        let target = max(1, 8 - level)
        var countsByEnding: [String: (legal: Int, familiar: Int)] = [:]
        var scored: [(word: String, legal: Int, familiar: Int, score: Int)] = []
        for word in candidates {
            let ending = String(word.suffix(1))
            let counts = countsByEnding[ending] ?? dictionary.replyCounts(afterEnding: ending, used: used,
                                                                         familiarThreshold: familiarThreshold)
            countsByEnding[ending] = counts
            let own = dictionary.entries[word]?.familiarity ?? 0
            let consumesReply = ConnectionRules.allowedStarts(after: ending).contains(String(word.prefix(1)))
            let legal = counts.legal - (consumesReply ? 1 : 0)
            let familiar = counts.familiar - (consumesReply && own >= familiarThreshold ? 1 : 0)
            let familiarDistance = abs(min(familiar, 8) - target)
            let breadthDistance = abs(min(legal, 24) - target * 3)
            let score = own * 3 - familiarDistance * 12 - breadthDistance
            scored.append((word, legal, familiar, score))
        }
        scored.sort { $0.score == $1.score ? $0.word < $1.word : $0.score > $1.score }
        let best = scored[0].score
        let pool = scored.prefix { $0.score >= best - 10 }.prefix(5)
        let selected = pool[weightedIndex(count: pool.count, random: &random)]
        pressure.computerTurns += 1
        pressure.demandingTurns = selected.familiar < 3 ? pressure.demandingTurns + 1 : 0
        return ComputerChoice(word: selected.word, legalReplyCount: selected.legal, familiarReplyCount: selected.familiar,
                              exploredPositions: candidates.count, usedRecovery: wantsRecovery && selected.familiar >= 3)
    }

    // Rank-weighted choice keeps variety close to the best score.
    static func weightedIndex(count: Int, random: inout SeededRandom) -> Int {
        let totalWeight = count * (count + 1) / 2
        var ticket = Int(random.next() % UInt64(totalWeight))
        for index in 0..<count {
            let weight = count - index
            if ticket < weight { return index }
            ticket -= weight
        }
        return 0
    }
}
