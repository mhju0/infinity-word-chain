import Foundation

public enum SeedPoolError: Error, Equatable { case empty, invalidSeed(String) }

public struct SeedPool: Codable, Equatable, Sendable {
    public private(set) var seeds: [String]
    public private(set) var position: Int
    public private(set) var random: SeededRandom

    private enum CodingKeys: String, CodingKey { case seeds, position, random }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seeds = try container.decode([String].self, forKey: .seeds)
        position = try container.decode(Int.self, forKey: .position)
        random = try container.decode(SeededRandom.self, forKey: .random)
        guard !seeds.isEmpty, Set(seeds).count == seeds.count, (0...seeds.count).contains(position),
              seeds.allSatisfy(ConnectionRules.isHangulWord) else {
            throw DecodingError.dataCorruptedError(forKey: .position, in: container, debugDescription: "Invalid seed pool checkpoint")
        }
    }

    public init(seeds: [String], dictionary: WordDictionary, randomSeed: UInt64) throws {
        guard !seeds.isEmpty else { throw SeedPoolError.empty }
        var seen: Set<String> = []
        for seed in seeds {
            guard seen.insert(seed).inserted, dictionary.entries[seed] != nil,
                  !dictionary.excludedWords.contains(seed),
                  dictionary.hasLegalReply(after: seed, used: [seed]) else {
                throw SeedPoolError.invalidSeed(seed)
            }
        }
        var random = SeededRandom(seed: randomSeed)
        self.seeds = random.shuffled(seeds)
        self.position = 0
        self.random = random
    }

    public mutating func next() -> String {
        if position == seeds.count {
            let previous = seeds.last
            seeds = random.shuffled(seeds)
            if seeds.count > 1, seeds.first == previous { seeds.swapAt(0, 1) }
            position = 0
        }
        defer { position += 1 }
        return seeds[position]
    }
}
