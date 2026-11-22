import Foundation

struct AdaptivePressureV2: Codable, Equatable, Sendable {
    static let maximumLevel = 5
    static let recoveryFloor = 5
    private static let recoveryLength = 2

    private enum Evidence: String, Codable, Sendable { case quick, neutral, struggle }

    private(set) var level: Int
    private(set) var recoveryPromptsRemaining: Int
    private(set) var lastFamiliarReplyCount: Int?
    private(set) var hardPromptStreak = 0
    private(set) var hadSubstantiveRejection = false
    private var recent: [Evidence] = []

    init(level: Int = 0, recoveryPromptsRemaining: Int = 0) {
        self.level = level
        self.recoveryPromptsRemaining = recoveryPromptsRemaining
    }

    var isValid: Bool {
        (0...Self.maximumLevel).contains(level) &&
            (0...Self.recoveryLength).contains(recoveryPromptsRemaining) &&
            (lastFamiliarReplyCount ?? 0) >= 0 && (0...1).contains(hardPromptStreak) && recent.count <= 3
    }

    mutating func recordRejection(_ rejection: Rejection) {
        switch rejection {
        case .missingEntry, .excluded, .wrongConnection:
            hadSubstantiveRejection = true
        case .incompleteComposition, .tooShort, .internalSpace, .invalidCharacters, .duplicate:
            break
        }
    }

    mutating func recordAccepted(elapsed: TimeInterval, turnDuration: TimeInterval) {
        defer { hadSubstantiveRejection = false }
        // Only responses to an offered bot prompt can inform its pressure.
        guard recoveryPromptsRemaining == 0, let lastFamiliarReplyCount else { return }
        let comfortable = lastFamiliarReplyCount >= Self.recoveryFloor
        let evidence: Evidence
        if hadSubstantiveRejection || elapsed >= turnDuration * (comfortable ? 0.7 : 0.8) {
            evidence = .struggle
        } else if elapsed <= turnDuration * (comfortable ? 0.45 : 0.5) {
            evidence = .quick
        } else {
            evidence = .neutral
        }
        recent = Array((recent + [evidence]).suffix(3))
        if recent.filter({ $0 == .struggle }).count >= 2 {
            beginRecovery()
        } else if recent.filter({ $0 == .quick }).count >= 2 {
            level = min(level + 1, Self.maximumLevel)
            recent.removeAll()
        }
    }

    mutating func recordDeliveredPrompt(familiarReplyCount: Int) {
        lastFamiliarReplyCount = familiarReplyCount
        if recoveryPromptsRemaining > 0 {
            if familiarReplyCount >= Self.recoveryFloor { recoveryPromptsRemaining -= 1 }
            return
        }

        hardPromptStreak = familiarReplyCount < Self.recoveryFloor ? hardPromptStreak + 1 : 0
        if hardPromptStreak == 2 { beginRecovery() }
    }

    private mutating func beginRecovery() {
        level = max(0, level - 1)
        recoveryPromptsRemaining = Self.recoveryLength
        hardPromptStreak = 0
        recent.removeAll()
    }
}

extension OpponentPolicy {
    private struct Prompt {
        let word: String
        let counts: WordDictionary.ReplyCounts
        let priority: Int
        let score: Int

        func outranks(_ other: Self) -> Bool {
            if priority != other.priority { return priority > other.priority }
            if score != other.score { return score > other.score }
            return word < other.word
        }
    }

    private struct EndingChoices {
        let starts: [String]
        let counts: WordDictionary.ReplyCounts
        var best: Prompt?
        var tiedCount = 1

        mutating func consider(_ prompt: Prompt, random: inout SeededRandom) {
            if let best, prompt.priority == best.priority, prompt.score == best.score {
                tiedCount += 1
                if random.next() % UInt64(tiedCount) == 0 { self.best = prompt }
            } else if best.map(prompt.outranks) ?? true {
                best = prompt
                tiedCount = 1
            }
        }
    }

    static func chooseAdaptiveV2(dictionary: WordDictionary, legal: [String], used: Set<String>,
                                 random: inout SeededRandom, pressure: PressureState, pacingEnabled: Bool) -> ComputerChoice {
        let wantsRecovery = pacingEnabled && (pressure.adaptiveV2?.recoveryPromptsRemaining ?? 0) > 0
        let comfortable = pressure.computerTurns < 2 || wantsRecovery
        let level = comfortable ? 0 : pressure.adaptiveV2?.level ?? 0
        let target = 8 - level
        let usedCounts = dictionary.usedReplyCountsByStart(used)
        var endings: [String: EndingChoices] = [:]
        for word in legal {
            let ending = String(word.suffix(1))
            var choices = endings[ending] ?? {
                let starts = ConnectionRules.allowedStarts(after: ending)
                return EndingChoices(starts: starts, counts: dictionary.availableReplyCounts(starts: starts, usedCounts: usedCounts))
            }()
            let own = dictionary.entries[word]?.familiarity ?? 0
            let familiarWord = own >= familiarThreshold
            var counts = choices.counts
            // A word that starts with one of its own allowed continuations is no longer available.
            if choices.starts.contains(String(word.prefix(1))) {
                counts.legal -= 1
                if familiarWord { counts.familiar -= 1 }
            }

            let priority: Int
            if counts.legal == 0 {
                priority = 0
            } else if comfortable {
                priority = 1 + min(counts.familiar, AdaptivePressureV2.recoveryFloor)
                    + (counts.familiar >= AdaptivePressureV2.recoveryFloor && familiarWord ? 1 : 0)
            } else {
                priority = 1 + min(counts.familiar, 2) + (counts.familiar >= 2 && familiarWord ? 1 : 0)
            }

            let familiarDistance = abs(min(counts.familiar, 8) - target)
            let breadthDistance = abs(min(counts.legal, 24) - target * 3)
            let familiarityBonus = familiarWord && !comfortable ? 36 : 0
            let score = familiarityBonus + own * 3 - familiarDistance * 12 - breadthDistance
            choices.consider(Prompt(word: word, counts: counts, priority: priority, score: score), random: &random)
            endings[ending] = choices
        }

        // One representative per ending keeps common suffixes from crowding the shortlist.
        var finalists: [Prompt] = []
        for choices in endings.values {
            guard let candidate = choices.best else { continue }
            let index = finalists.firstIndex { candidate.outranks($0) } ?? finalists.count
            if index < 5 {
                finalists.insert(candidate, at: index)
                if finalists.count > 5 { finalists.removeLast() }
            }
        }
        let best = finalists[0]
        let pool = finalists.prefix { $0.priority == best.priority && $0.score >= best.score - 10 }
        let selected = pool[weightedIndex(count: pool.count, random: &random)]
        return ComputerChoice(word: selected.word, legalReplyCount: selected.counts.legal,
                              familiarReplyCount: selected.counts.familiar, exploredPositions: endings.count,
                              usedRecovery: wantsRecovery && selected.counts.familiar >= AdaptivePressureV2.recoveryFloor)
    }
}
