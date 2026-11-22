import Foundation

public enum ConnectionRules {
    public static let version = "kkutu-forward-v1"

    public static func allowedStarts(after syllable: String) -> [String] {
        guard syllable.unicodeScalars.count == 1,
              let scalar = syllable.unicodeScalars.first,
              (0xAC00...0xD7A3).contains(scalar.value) else { return [] }
        let offset = Int(scalar.value) - 0xAC00
        let initial = offset / 588
        let vowel = (offset % 588) / 28
        let target: Int?
        if initial == 5, [0, 1, 8, 11, 13, 18].contains(vowel) {
            target = 2
        } else if initial == 5, [2, 6, 7, 12, 17, 20].contains(vowel) {
            target = 11
        } else if initial == 2, [6, 12, 17, 20].contains(vowel) {
            target = 11
        } else {
            target = nil
        }
        guard let target, let converted = UnicodeScalar(0xAC00 + target * 588 + vowel * 28 + offset % 28) else {
            return [syllable]
        }
        return [syllable, String(converted)]
    }

    public static func normalized(_ input: String) -> String {
        input.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func isHangulWord(_ word: String) -> Bool {
        word.unicodeScalars.count >= 2 && word.unicodeScalars.allSatisfy { (0xAC00...0xD7A3).contains($0.value) }
    }
}

public struct WordEntry: Codable, Equatable, Sendable {
    public let word: String
    public let familiarity: Int
    public let definition: String?

    public init(word: String, familiarity: Int, definition: String? = nil) {
        self.word = word
        self.familiarity = familiarity
        self.definition = definition
    }
}

public enum DictionaryError: Error, Equatable {
    case malformedRow(Int)
    case duplicateWord(String)
}

public enum Rejection: String, Codable, Sendable {
    case incompleteComposition, tooShort, internalSpace, invalidCharacters, missingEntry, excluded, duplicate, wrongConnection
}

public struct WordDictionary: Sendable {
    public let version: String
    public let entries: [String: WordEntry]
    public let excludedWords: Set<String>
    private let byStart: [String: [String]]
    private let countsByStart: [String: ReplyCounts]

    struct ReplyCounts {
        var legal = 0
        var familiar = 0

        mutating func countWord(familiarity: Int) {
            legal += 1
            if familiarity >= OpponentPolicy.familiarThreshold { familiar += 1 }
        }
    }

    public init(entries: [WordEntry], version: String, excludedWords: Set<String> = []) throws {
        var indexed: [String: WordEntry] = [:]
        var starts: [String: [String]] = [:]
        var counts: [String: ReplyCounts] = [:]
        for (index, entry) in entries.enumerated() {
            guard ConnectionRules.isHangulWord(entry.word), (0...3).contains(entry.familiarity) else {
                throw DictionaryError.malformedRow(index + 1)
            }
            guard indexed[entry.word] == nil else { throw DictionaryError.duplicateWord(entry.word) }
            indexed[entry.word] = entry
            let start = String(entry.word.prefix(1))
            starts[start, default: []].append(entry.word)
            if !excludedWords.contains(entry.word) {
                counts[start, default: ReplyCounts()].countWord(familiarity: entry.familiarity)
            }
        }
        self.version = version
        self.entries = indexed
        self.excludedWords = excludedWords
        self.byStart = starts.mapValues { $0.sorted() }
        self.countsByStart = counts
    }

    public init(tsv: String, version: String, excludedWords: Set<String> = []) throws {
        var entries: [WordEntry] = []
        for (index, line) in tsv.split(whereSeparator: \.isNewline).enumerated() {
            let columns = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard columns.count >= 2, let familiarity = Int(columns[1]) else {
                throw DictionaryError.malformedRow(index + 1)
            }
            entries.append(WordEntry(word: String(columns[0]), familiarity: familiarity,
                                     definition: columns.count == 3 && !columns[2].isEmpty ? String(columns[2]) : nil))
        }
        try self.init(entries: entries, version: version, excludedWords: excludedWords)
    }

    public func legalReplies(after word: String, used: Set<String>) -> [String] {
        let starts = ConnectionRules.allowedStarts(after: String(word.suffix(1)))
        return starts.flatMap { byStart[$0] ?? [] }.filter { !used.contains($0) && !excludedWords.contains($0) }
    }

    public func hasLegalReply(after word: String, used: Set<String>) -> Bool {
        for start in ConnectionRules.allowedStarts(after: String(word.suffix(1))) {
            if (byStart[start] ?? []).contains(where: { !used.contains($0) && !excludedWords.contains($0) }) {
                return true
            }
        }
        return false
    }

    func firstTwoLegalReplies(afterEnding ending: String, used: Set<String>) -> [String] {
        var replies: [String] = []
        for start in ConnectionRules.allowedStarts(after: ending) {
            for word in byStart[start] ?? [] where !used.contains(word) && !excludedWords.contains(word) {
                replies.append(word)
                if replies.count == 2 { return replies }
            }
        }
        return replies
    }

    func replyCounts(afterEnding ending: String, used: Set<String>, familiarThreshold: Int) -> (legal: Int, familiar: Int) {
        var legal = 0
        var familiar = 0
        for start in ConnectionRules.allowedStarts(after: ending) {
            for word in byStart[start] ?? [] where !used.contains(word) && !excludedWords.contains(word) {
                legal += 1
                if (entries[word]?.familiarity ?? 0) >= familiarThreshold { familiar += 1 }
            }
        }
        return (legal, familiar)
    }

    func usedReplyCountsByStart(_ used: Set<String>) -> [String: ReplyCounts] {
        var counts: [String: ReplyCounts] = [:]
        for word in used {
            guard let entry = entries[word], !excludedWords.contains(word) else { continue }
            counts[String(word.prefix(1)), default: ReplyCounts()].countWord(familiarity: entry.familiarity)
        }
        return counts
    }

    func availableReplyCounts(starts: [String], usedCounts: [String: ReplyCounts]) -> ReplyCounts {
        var available = ReplyCounts()
        for start in starts {
            guard let total = countsByStart[start] else { continue }
            let used = usedCounts[start] ?? ReplyCounts()
            available.legal += total.legal - used.legal
            available.familiar += total.familiar - used.familiar
        }
        return available
    }

    public func rejection(for input: String, after word: String, used: Set<String>) -> Rejection? {
        let normalized = ConnectionRules.normalized(input)
        if normalized.unicodeScalars.contains(where: { (0x1100...0x11FF).contains($0.value) || (0x3130...0x318F).contains($0.value) }) {
            return .incompleteComposition
        }
        if normalized.contains(where: \.isWhitespace) { return .internalSpace }
        if normalized.unicodeScalars.contains(where: { !(0xAC00...0xD7A3).contains($0.value) }) { return .invalidCharacters }
        if normalized.count < 2 { return .tooShort }
        if excludedWords.contains(normalized) { return .excluded }
        if used.contains(normalized) { return .duplicate }
        if entries[normalized] == nil { return .missingEntry }
        if !ConnectionRules.allowedStarts(after: String(word.suffix(1))).contains(String(normalized.prefix(1))) {
            return .wrongConnection
        }
        return nil
    }
}
