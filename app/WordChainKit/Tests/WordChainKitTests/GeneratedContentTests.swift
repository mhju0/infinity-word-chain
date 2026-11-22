import Foundation
import Testing
@testable import WordChainKit

@Test(.enabled(if: ProcessInfo.processInfo.environment["WORD_CHAIN_CONTENT_DIR"] != nil))
func generatedContentUsesCompleteLegalGraph() throws {
    let path = try #require(ProcessInfo.processInfo.environment["WORD_CHAIN_CONTENT_DIR"])
    let directory = URL(fileURLWithPath: path)
    let text = try String(contentsOf: directory.appendingPathComponent("words.tsv"), encoding: .utf8)
    let excluded = try String(contentsOf: directory.appendingPathComponent("excluded.tsv"), encoding: .utf8)
    let seedText = try String(contentsOf: directory.appendingPathComponent("seeds.tsv"), encoding: .utf8)
    let words = try WordDictionary(tsv: text, version: "prototype-nouns-v1",
                                   excludedWords: Set(excluded.split(whereSeparator: \.isNewline).map(String.init)))
    let seeds = seedText.split(whereSeparator: \.isNewline).map(String.init)
    #expect(words.entries.count > 200_000)
    #expect(words.entries.keys.map(\.count).max() == 14)
    var pool = try SeedPool(seeds: seeds, dictionary: words, randomSeed: 1)
    #expect(Set((0..<seeds.count).map { _ in pool.next() }).count == seeds.count)
    var times: [TimeInterval] = []
    var choices: [String] = []
    for seed in seeds.prefix(6) {
        let replies = words.legalReplies(after: seed, used: [seed])
        let familiarReplies = replies.filter { (words.entries[$0]?.familiarity ?? 0) >= 2 }
        let human = try #require(familiarReplies.first)
        for difficulty in Difficulty.allCases {
            var random = SeededRandom(seed: 99)
            var pressure = PressureState()
            let started = ProcessInfo.processInfo.systemUptime
            let choice = try #require(OpponentPolicy.choose(dictionary: words, after: human, used: [seed, human],
                                                             difficulty: difficulty, random: &random, pressure: &pressure))
            times.append(ProcessInfo.processInfo.systemUptime - started)
            #expect(words.rejection(for: choice.word, after: human, used: [seed, human]) == nil)
            let nextReplies = words.legalReplies(after: choice.word, used: [seed, human, choice.word])
            #expect(nextReplies.count == choice.legalReplyCount)
            #expect(nextReplies.filter { (words.entries[$0]?.familiarity ?? 0) >= 2 }.count == choice.familiarReplyCount)
            if difficulty.usesPromptPacing {
                let endings = words.legalReplies(after: human, used: [seed, human]).map { $0.suffix(1) }
                #expect(choice.exploredPositions == Set(endings).count)
            } else {
                #expect(choice.exploredPositions <= (difficulty == .normal ? 1_200 : 24))
            }
            if (difficulty == .adaptive || difficulty.usesPromptPacing), nextReplies.isEmpty {
                #expect(words.legalReplies(after: human, used: [seed, human]).allSatisfy {
                    !words.hasLegalReply(after: $0, used: [seed, human, $0])
                })
            }
            choices.append("\(seed)→\(human)→\(choice.word) [\(difficulty.rawValue), legal \(choice.legalReplyCount), familiar \(choice.familiarReplyCount)]")
        }
    }
    print("Authentic content: \(words.entries.count) words, \(seeds.count) seeds, \(times.count) decisions; desktop debug max \(times.max() ?? 0)s, average \(times.reduce(0, +) / Double(times.count))s")
    print(choices.joined(separator: "\n"))
}
