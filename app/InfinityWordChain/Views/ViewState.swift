import SwiftUI

struct ChainWordViewState: Identifiable, Equatable {
    var id: String
    var word: String
    var actor: String
    var isPlayer: Bool
    var moveLabels: [String]
    var definition: String = ""
    var source: String = ""
}

struct SpecialMoveViewState: Equatable {
    var id: Int
    var label: String
}

struct EndingCountViewState: Identifiable, Equatable {
    var id: String { syllable }
    var syllable: String
    var count: Int
}

struct MatchRecordViewState: Identifiable, Equatable {
    var id: String
    var date: Date
    var reason: String
    var usesCurrentScoringRules: Bool
    var version: String
    var connectionVersion: String
    var definitionVersion: String
    var words: [ChainWordViewState]
    var wordCount: Int { words.count }
    var finishingMove: SpecialMoveViewState?
    var endingCounts: [EndingCountViewState]
}

struct WordChainViewState {
    enum Screen { case home, match, result }
    enum Phase { case preparing, countdown, human, recovery }

    var screen: Screen = .home
    var phase: Phase = .preparing
    var welcomed = false
    var ready = false
    var score = 0
    var bestScore: Int?
    var isPersonalBest = false
    var currentWord = ""
    var allowedStarts: [String] = []
    var inputEnabled = false
    var remainingSeconds = 10
    var countdown = "3"
    var feedback: String?
    var feedbackIsNeutral = false
    var storageError: String?
    var specialMove: SpecialMoveViewState?
    var result: MatchRecordViewState?
    var history: [MatchRecordViewState] = []
    var theme = Theme.system
    var haptics = true
    var dictionaryVersion = ""
    var dictionaryCount = 0
}

struct WordChainActions {
    var start: () -> Void
    var retryPreparation: () -> Void
    var resign: () -> Void
    var rematch: () -> Void
    var home: () -> Void
    var submit: (ContinuousClock.Instant) -> Void
    var inputReady: () -> Void
    var presentationReady: () -> Void
    var retrySave: () -> Void
    var selectTheme: (Theme) -> Void
    var setHaptics: (Bool) -> Void
    var deleteLocalData: () -> Void
}
