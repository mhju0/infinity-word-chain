import SwiftUI
import UIKit
import WordChainKit

private struct SavedGame: Codable {
    var active: MatchState?
    var history: [MatchState] = []
    var seedPool: SeedPool?
    var theme = Theme.system.rawValue
    var haptics = true
    var welcomed = false
}

private struct ContentHeader: Decodable {
    let version: String
    let connection_version: String
    let output_sha256: [String: String]
}

private struct WordDefinition: Sendable {
    let source: String
    let text: String
}

@MainActor @Observable
final class MatchModel {
    private(set) var view = WordChainViewState()
    private(set) var input = ""
    var loadError = false
    private(set) var unreadableSave = false

    @ObservationIgnored private var dictionary: WordDictionary?
    @ObservationIgnored private var seeds: [String] = []
    @ObservationIgnored private var definitions: [String: WordDefinition] = [:]
    @ObservationIgnored private var definitionVersion = ""
    @ObservationIgnored private var save = SavedGame()
    @ObservationIgnored private var engine: DuelEngine?
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var phaseTask: Task<Void, Never>?
    @ObservationIgnored private var specialMoveTask: Task<Void, Never>?
    @ObservationIgnored private var active = false
    @ObservationIgnored private var keyboardReady = false
    @ObservationIgnored private var promptReady = false
    @ObservationIgnored private var firstMatch = true
    @ObservationIgnored private var loading = false

    @ObservationIgnored private let clockOrigin = ContinuousClock.now

    private var now: TimeInterval { elapsed(at: .now) }

    private func elapsed(at instant: ContinuousClock.Instant) -> TimeInterval {
        let elapsed = clockOrigin.duration(to: instant).components
        return Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
    }
    private var saveURL: URL {
        #if DEBUG
        if let fixture = ProcessInfo.processInfo.environment["WORD_CHAIN_TEST_SAVE"], let id = UUID(uuidString: fixture) {
            return URL.applicationSupportDirectory.appending(path: "InfinityWordChain/test-\(id.uuidString).json")
        }
        #endif
        return URL.applicationSupportDirectory.appending(path: "InfinityWordChain/matches.json")
    }

    var actions: WordChainActions {
        .init(start: start, retryPreparation: prepareOpening, resign: resign, rematch: start, home: home,
              submit: submit, inputReady: inputReady, presentationReady: presentationReady,
              retrySave: retrySave, selectTheme: selectTheme,
              setHaptics: setHaptics, deleteLocalData: deleteLocalData)
    }

    func load() async {
        guard dictionary == nil, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                let bundle = Bundle.main
                func resource(_ name: String) throws -> String {
                    guard let url = bundle.url(forResource: name, withExtension: "tsv") else {
                        throw CocoaError(.fileNoSuchFile)
                    }
                    return try String(contentsOf: url, encoding: .utf8)
                }
                guard let manifestURL = bundle.url(forResource: "manifest", withExtension: "json") else {
                    throw CocoaError(.fileNoSuchFile)
                }
                let header = try JSONDecoder().decode(ContentHeader.self, from: Data(contentsOf: manifestURL))
                guard header.connection_version == ConnectionRules.version,
                      let wordsHash = header.output_sha256["words.tsv"],
                      let excludedHash = header.output_sha256["excluded.tsv"],
                      let definitionsHash = header.output_sha256["definitions.tsv"] else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                let version = "\(header.version)-\(wordsHash.prefix(8))-\(excludedHash.prefix(8))"
                let excluded = Set(try resource("excluded").split(whereSeparator: \.isNewline).map(String.init))
                let dictionary = try WordDictionary(tsv: resource("words"), version: version, excludedWords: excluded)
                let seeds = try resource("seeds").split(whereSeparator: \.isNewline).map(String.init)
                var definitions: [String: WordDefinition] = [:]
                for line in try resource("definitions").split(whereSeparator: \.isNewline) {
                    let columns = line.split(separator: "\t", maxSplits: 2)
                    guard columns.count == 3 else { throw CocoaError(.fileReadCorruptFile) }
                    definitions[String(columns[0])] = WordDefinition(source: String(columns[1]), text: String(columns[2]))
                }
                return (dictionary, seeds, definitions, String(definitionsHash.prefix(8)))
            }.value
            do {
                save = try JSONDecoder().decode(SavedGame.self, from: Data(contentsOf: saveURL))
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                save = SavedGame()
            } catch is DecodingError {
                unreadableSave = true
                throw CocoaError(.fileReadCorruptFile)
            }
            dictionary = loaded.0
            seeds = loaded.1
            if let savedSeeds = save.seedPool?.seeds, Set(savedSeeds) != Set(seeds) { save.seedPool = nil }
            definitions = loaded.2
            definitionVersion = loaded.3
            unreadableSave = false
            view.dictionaryVersion = loaded.0.version
            view.dictionaryCount = loaded.0.entries.count
            view.ready = true
            if let state = save.active {
                archive(state)
                _ = persist()
            }
            refresh()
        } catch {
            loadError = true
        }
    }

    func resetUnreadableSave() async {
        guard unreadableSave else { return }
        do {
            try FileManager.default.removeItem(at: saveURL)
            unreadableSave = false
            await load()
        } catch {
            loadError = true
        }
    }

    func setActive(_ value: Bool) {
        active = value
        guard view.screen == .match else { return }
        if !value {
            keyboardReady = false
            if view.phase == .preparing || view.phase == .countdown {
                phaseTask?.cancel()
                view.phase = .preparing
            }
        } else if timer != nil {
            tick()
        } else if view.phase == .preparing {
            prepareOpening()
        } else {
            beginIfReady()
        }
    }

    func edit(_ value: String) {
        guard input != value else { return }
        input = value
        engine?.updateDraft(value)
        view.feedback = nil
    }

    private func start() {
        guard active, let dictionary, view.storageError == nil,
              engine == nil || engine?.state.phase == .completed else { return }
        do {
            var pool = try save.seedPool ?? SeedPool(seeds: seeds, dictionary: dictionary, randomSeed: UInt64.random(in: .min ... .max))
            var seed = pool.next()
            var randomSeed = UInt64.random(in: .min ... .max)
            #if DEBUG
            if let fixture = ProcessInfo.processInfo.environment["WORD_CHAIN_TEST_SEED"] { seed = fixture }
            if let fixture = ProcessInfo.processInfo.environment["WORD_CHAIN_TEST_RANDOM"],
               let fixedSeed = UInt64(fixture) { randomSeed = fixedSeed }
            #endif
            let next = try DuelEngine(dictionary: dictionary, seed: seed, difficulty: .adaptiveV3,
                                      randomSeed: randomSeed)
            save.seedPool = pool
            save.welcomed = true
            engine = next
            input = ""
            view.feedback = nil
            view.result = nil
            keyboardReady = false
            promptReady = false
            view.screen = .match
            commit()
            if view.storageError == nil { prepareOpening() }
        } catch {
            loadError = true
        }
    }

    private func prepareOpening() {
        guard active, view.storageError == nil, view.screen == .match else { return }
        view.phase = .preparing
        phaseTask?.cancel()
        phaseTask = Task {
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            guard active, view.phase == .preparing else { return }
            view.phase = .recovery
        }
    }

    private func inputReady() {
        guard active, view.screen == .match else { return }
        keyboardReady = true
        if view.phase == .preparing {
            phaseTask?.cancel()
            view.phase = .countdown
            let interval = firstMatch ? 1.0 : 0.6
            view.countdown = "3"
            phaseTask = Task {
                for digit in ["3", "2", "1"] {
                    view.countdown = digit
                    do { try await Task.sleep(for: .seconds(interval)) } catch { return }
                }
                firstMatch = false
                showHuman()
            }
        } else {
            beginIfReady()
        }
    }

    private func presentationReady() {
        guard view.screen == .match, view.phase == .human else { return }
        promptReady = true
        beginIfReady()
    }

    private func showHuman() {
        promptReady = false
        view.phase = .human
        view.remainingSeconds = Int(ceil(engine?.state.remainingTime ?? Difficulty.adaptiveV3.turnDuration))
        view.feedback = nil
    }

    private func beginIfReady() {
        guard active, keyboardReady, promptReady, view.phase == .human, timer == nil,
              view.storageError == nil else { return }
        engine?.beginHumanTurn(at: now)
        view.inputEnabled = true
        timer = Task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(75)) } catch { return }
                tick()
            }
        }
    }

    private func tick() {
        let timestamp = now
        guard let remaining = engine?.remainingTime(at: timestamp), view.phase == .human else { return }
        let seconds = Int(ceil(remaining))
        if view.remainingSeconds != seconds { view.remainingSeconds = seconds }
        if remaining <= 0 {
            engine?.advanceTime(to: timestamp)
            commit()
        }
    }

    private func submit(at instant: ContinuousClock.Instant) {
        let timestamp = elapsed(at: instant)
        guard active, view.phase == .human, view.storageError == nil, let result = engine?.submit(input, at: timestamp) else { return }
        switch result {
        case .accepted:
            stopTimer()
            input = ""
            view.feedback = nil
            let recognition = engine?.lastHumanMoveRecognition
            let playerWord = engine?.state.currentWord ?? ""
            if recognition?.primary == .finishing, view.haptics {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
            if engine?.state.phase == .computer { engine?.presentComputerMove() }
            commit()
            if view.screen == .match, engine?.state.phase == .preparing {
                showSpecialMove(recognition, word: playerWord)
                showHuman()
            }
        case .late:
            commit()
        case .unavailable:
            break
        case .rejected(let rejection):
            view.feedbackIsNeutral = rejection == .duplicate
            view.feedback = rejectionText(rejection)
            if view.haptics && !view.feedbackIsNeutral {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
            if UIAccessibility.isVoiceOverRunning, let feedback = view.feedback {
                UIAccessibility.post(notification: .announcement, argument: feedback)
            }
        }
    }

    private func resign() {
        guard active, view.screen == .match, view.storageError == nil else { return }
        engine?.advanceTime(to: now)
        engine?.resign()
        commit()
    }

    private func home() {
        guard view.storageError == nil else { return }
        view.screen = .home
    }

    private func stopTimer() {
        view.inputEnabled = false
        timer?.cancel()
        timer = nil
    }

    private func stopWork() {
        stopTimer()
        phaseTask?.cancel()
        phaseTask = nil
        specialMoveTask?.cancel()
        specialMoveTask = nil
        view.specialMove = nil
    }

    private func showSpecialMove(_ recognition: HumanMoveRecognition?, word: String) {
        specialMoveTask?.cancel()
        guard let recognition else {
            view.specialMove = nil
            return
        }
        view.specialMove = .init(id: recognition.moveID, label: moveLabel(recognition.primary, word: word))
        if view.haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        specialMoveTask = Task {
            do { try await Task.sleep(for: .milliseconds(1100)) } catch { return }
            view.specialMove = nil
        }
    }

    private func archive(_ state: MatchState) {
        if !save.history.contains(where: { $0.id == state.id }) { save.history.insert(state, at: 0) }
        save.active = nil
    }

    private func commit() {
        guard let state = engine?.state else { return }
        if state.phase == .completed {
            stopWork()
            archive(state)
            view.screen = .result
        } else {
            save.active = state
        }
        if !persist(), state.phase != .completed {
            stopWork()
            archive(state)
            view.result = record(state)
            view.isPersonalBest = false
            view.screen = .result
            engine = nil
        }
        refresh(includeHistory: view.screen == .result)
    }

    @discardableResult
    private func persist() -> Bool {
        do {
            try FileManager.default.createDirectory(at: saveURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(save).write(to: saveURL, options: .atomic)
            view.storageError = nil
            return true
        } catch {
            view.storageError = "저장하지 못했어요. 다시 시도해 주세요."
            return false
        }
    }

    private func retrySave() {
        _ = persist()
        refresh()
    }

    private func refresh(includeHistory: Bool = true) {
        view.welcomed = save.welcomed
        view.theme = Theme(rawValue: save.theme) ?? .system
        view.haptics = save.haptics
        if includeHistory {
            view.history = save.history.map(record)
            let currentRun = engine?.state
            let scores = save.history.lazy.filter {
                $0.outcome != nil && $0.humanWordCount > 0 && self.usesCurrentScoringRules($0)
            }
            view.bestScore = scores.map { $0.moves.count }.max()
            if let currentRun, currentRun.outcome != nil {
                view.result = record(currentRun)
                let previousBest = scores.filter { $0.id != currentRun.id }.map { $0.moves.count }.max() ?? 0
                view.isPersonalBest = currentRun.humanWordCount > 0 &&
                    usesCurrentScoringRules(currentRun) && currentRun.moves.count > previousBest
            }
        }
        guard let state = engine?.state else { return }
        view.score = state.moves.count
        view.currentWord = state.currentWord
        view.allowedStarts = state.allowedStarts
    }

    private func selectTheme(_ theme: Theme) { save.theme = theme.rawValue; savePreference() }
    private func setHaptics(_ enabled: Bool) { save.haptics = enabled; savePreference() }

    private func savePreference() {
        _ = persist()
        refresh()
    }

    private func deleteLocalData() {
        let previous = save
        save = SavedGame()
        if persist() {
            stopWork()
            engine = nil
            input = ""
            view = WordChainViewState()
            view.ready = dictionary != nil
            view.dictionaryVersion = dictionary?.version ?? ""
            view.dictionaryCount = dictionary?.entries.count ?? 0
            firstMatch = true
        } else {
            save = previous
            refresh()
        }
    }

    private func record(_ state: MatchState) -> MatchRecordViewState {
        let interrupted = state.outcome == nil
        var endings: [String: Int] = [:]
        let words = state.moves.map { move -> ChainWordViewState in
            if move.actor == .human { endings[String(move.word.suffix(1)), default: 0] += 1 }
            let definition = definitions[move.word]
            let labels = [SpecialMoveKind.finishing, .pressure, .returning]
                .filter { move.recognition?.kinds.contains($0) == true }
                .map { moveLabel($0, word: move.word) }
            return .init(id: "\(move.id)", word: move.word, actor: actorLabel(move.actor),
                         isPlayer: move.actor == .human, moveLabels: labels,
                         definition: definition?.text ?? "", source: definition?.source ?? "")
        }
        let finishingMove: SpecialMoveViewState? = state.moves.last.flatMap { move in
            guard move.recognition?.primary == .finishing else { return nil }
            return .init(id: move.id, label: moveLabel(.finishing, word: move.word))
        }
        var endingCounts: [EndingCountViewState] = endings.compactMap { syllable, count in
            guard count >= 3 else { return nil }
            return EndingCountViewState(syllable: syllable, count: count)
        }
        endingCounts.sort { first, second in
            if first.count == second.count { return first.syllable < second.syllable }
            return first.count > second.count
        }
        return .init(id: state.id.uuidString, date: state.startedAt,
                     reason: interrupted ? "중단된 판" : "",
                     usesCurrentScoringRules: usesCurrentScoringRules(state),
                     version: state.dictionaryVersion, connectionVersion: state.connectionVersion,
                     definitionVersion: definitionVersion, words: words,
                     finishingMove: finishingMove, endingCounts: endingCounts)
    }

    private func usesCurrentScoringRules(_ state: MatchState) -> Bool {
        state.difficulty == .adaptiveV3 &&
            state.dictionaryVersion == dictionary?.version &&
            state.connectionVersion == ConnectionRules.version &&
            state.opponentVersion == OpponentPolicy.adaptiveV3Version
    }

    private func moveLabel(_ kind: SpecialMoveKind, word: String) -> String {
        let name = switch kind {
        case .returning: "되받기"
        case .pressure: "압박"
        case .finishing: "한방"
        }
        return "\(name) · \(word.suffix(1))"
    }

    private func actorLabel(_ actor: WordChainKit.Actor) -> String {
        switch actor {
        case .seed: "시작"
        case .human: "나"
        case .computer: "컴퓨터"
        }
    }

    private func rejectionText(_ rejection: Rejection) -> String {
        switch rejection {
        case .incompleteComposition: "글자를 끝까지 입력해 주세요."
        case .tooShort: "두 글자 이상 입력해 주세요."
        case .internalSpace: "띄어쓰기 없이 단어 하나를 입력해 주세요."
        case .invalidCharacters: "한글로 입력해 주세요."
        case .missingEntry: "게임 사전에 없는 단어예요."
        case .excluded: "이 게임에서는 사용할 수 없는 단어예요."
        case .duplicate: "이미 나온 단어예요."
        case .wrongConnection: "\(view.allowedStarts.joined(separator: " 또는 "))로 시작해 주세요."
        }
    }
}
