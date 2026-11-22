import CoreText
import SwiftUI
import UIKit

struct MatchView: View {
    let state: WordChainViewState
    let actions: WordChainActions
    @Binding var input: String
    let end: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pendingAnnouncement: String?

    private var turnLabel: String {
        switch state.phase {
        case .human: "내 차례"
        case .countdown, .preparing: "준비 중"
        case .recovery: "준비 중"
        }
    }

    private var cue: String {
        if state.allowedStarts.count > 1 {
            return "\(state.allowedStarts.joined(separator: " 또는 ")) 중 하나로 시작해 주세요."
        }
        guard let syllable = state.allowedStarts.first else { return "" }
        let final = syllable.unicodeScalars.first.map { (Int($0.value) - 0xAC00) % 28 } ?? 0
        return "\(syllable)\(final == 0 || final == 8 ? "로" : "으로") 시작해 주세요."
    }

    private var urgencySecond: Int? {
        guard state.phase == .human, (1...5).contains(state.remainingSeconds) else { return nil }
        return state.remainingSeconds
    }

    var body: some View {
        Group {
            if state.phase == .recovery {
                recoverySurface
            } else {
                activeSurface
            }
        }
        .plainBackground()
        .task(id: "\(state.phase)-\(state.currentWord)") {
            guard state.phase == .human else { pendingAnnouncement = nil; return }
            let announcement = "\(state.currentWord). \(cue) 내 차례, \(state.remainingSeconds)초."
            if UIAccessibility.isVoiceOverRunning {
                pendingAnnouncement = announcement
                UIAccessibility.post(notification: .announcement, argument: announcement)
            } else {
                actions.presentationReady()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.announcementDidFinishNotification)) { notification in
            guard state.phase == .human,
                  let pendingAnnouncement,
                  notification.userInfo?[UIAccessibility.announcementStringValueUserInfoKey] as? String == pendingAnnouncement else { return }
            self.pendingAnnouncement = nil
            actions.presentationReady()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)) { _ in
            if !UIAccessibility.isVoiceOverRunning, state.phase == .human {
                pendingAnnouncement = nil
                actions.presentationReady()
            }
        }
    }

    private var activeSurface: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    Text(turnLabel)
                        .font(TextStyle.barTitle)
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    if state.phase == .human {
                        Text(String(format: "0:%02d", max(0, state.remainingSeconds)))
                            .font(.pretendard(25, .heavy, relativeTo: .title2))
                            .monospacedDigit()
                            .fixedSize(horizontal: true, vertical: false)
                            .foregroundStyle(urgencySecond != nil ? Palette.hurry : Palette.ink)
                            .accessibilityLabel("남은 시간")
                            .accessibilityValue("\(max(0, state.remainingSeconds))초")
                            .accessibilityIdentifier("turn-timer")
                    }
                    Button("끝내기", action: end)
                        .buttonStyle(.small)
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityIdentifier("end-match")
                }
                HStack(spacing: 10) {
                    Text("연결 \(state.score)")
                        .font(TextStyle.smallBold)
                        .monospacedDigit()
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(Palette.accent)
                        .accessibilityLabel("연결 \(state.score)단어")
                        .accessibilityIdentifier("match-score")
                    ZStack(alignment: .leading) {
                        if let move = state.specialMove {
                            Text(move.label)
                                .font(TextStyle.smallBold)
                                .foregroundStyle(Palette.muted)
                                .lineLimit(1)
                                .accessibilityIdentifier("special-move")
                                .id(move.id)
                                .transition(.opacity)
                        }
                    }
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: state.specialMove?.id)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .padding(.horizontal, Space.side)
            .padding(.vertical, typeSize.isAccessibilitySize ? 6 : 12)

            ScrollView {
                VStack(spacing: Space.block) {
                    if state.phase == .preparing || state.phase == .countdown {
                        preparation
                    } else {
                        VStack(spacing: typeSize.isAccessibilitySize ? 8 : 14) {
                            CurrentWordView(word: state.currentWord)
                            if state.phase == .human, state.allowedStarts.count > 1 {
                                KoreanText("시작 글자 · \(state.allowedStarts.joined(separator: " 또는 "))",
                                           alignment: .center, emphasizedWords: Set(state.allowedStarts))
                                    .font(TextStyle.body).foregroundStyle(Palette.muted)
                                    .accessibilityIdentifier("connection-cue")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                        .padding(.vertical, typeSize.isAccessibilitySize ? 4 : 16)
                        .card()
                    }
                    if let feedback = state.feedback {
                        KoreanText(feedback, alignment: .center)
                            .font(TextStyle.smallBold)
                            .foregroundStyle(state.feedbackIsNeutral ? Palette.muted : Palette.destructiveText)
                            .accessibilityIdentifier("input-feedback")
                    }
                }
                .padding(.horizontal, Space.side)
                .padding(.top, 12)
                .padding(.bottom, Space.block)
            }
            .scrollDismissesKeyboard(.never)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            WordEntryField(text: $input,
                           enabled: state.phase == .human && state.inputEnabled,
                           focus: true,
                           onSubmit: actions.submit,
                           onReady: actions.inputReady)
                .padding(.horizontal, Space.side)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(Palette.background)
        }
        .overlay {
            let edge = RoundedRectangle(cornerRadius: 24)
                .strokeBorder(Palette.hurry, lineWidth: 2)
                .padding(4)
            Group {
                if reduceMotion {
                    edge.opacity(urgencySecond == nil ? 0 : 0.48)
                } else {
                    edge.keyframeAnimator(initialValue: 0.0, trigger: urgencySecond) { content, opacity in
                        content.opacity(opacity)
                    } keyframes: { _ in
                        MoveKeyframe(urgencySecond == nil ? 0.0 : 0.64)
                        CubicKeyframe(urgencySecond == nil ? 0.0 : 0.18, duration: 0.72)
                    }
                }
            }
            .accessibilityIdentifier("turn-urgency")
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
    }

    private var preparation: some View {
        VStack(spacing: 16) {
            if state.phase == .countdown {
                Text(state.countdown)
                    .font(.pretendardFixed(72, .black))
                    .foregroundStyle(Palette.accent)
                    .accessibilityLabel("시작까지 \(state.countdown)")
            } else {
                ProgressView().tint(Palette.accent)
                KoreanText("입력을 준비하고 있어요.", alignment: .center)
                    .font(TextStyle.bodyBold)
            }
            KoreanText("마지막 글자를 이어 주세요", alignment: .center)
                .font(TextStyle.small).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .card()
    }

    private var recoverySurface: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.block) {
                ScreenHeading(title: "키보드를 열지 못했어요")
            }
            .padding(.horizontal, Space.side)
            .padding(.vertical, 24)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button("다시 시도", action: actions.retryPreparation)
                    .buttonStyle(.primary)
                    .accessibilityIdentifier("retry-preparation")
                Button("끝내기", action: end)
                    .buttonStyle(.secondary)
                    .accessibilityIdentifier("end-match")
            }
            .barBackground()
        }
        .accessibilityElement(children: .contain)
    }
}

struct CurrentWordView: View {
    let word: String
    @ScaledMetric(relativeTo: .largeTitle) private var size = 58.0

    var body: some View {
        ViewThatFits(in: .horizontal) {
            wordLabel
            ScrollViewReader { proxy in
                VStack(spacing: 4) {
                    ScrollView(.horizontal) {
                        HStack(spacing: 0) {
                            Color.clear.frame(width: 0, height: 0).id("word-start")
                            wordLabel
                            Color.clear.frame(width: 0, height: 0).id("word-end")
                        }
                    }
                    HStack(spacing: 12) {
                        Button("첫 글자") { proxy.scrollTo("word-start", anchor: .leading) }.buttonStyle(.small)
                        Button("끝 글자") { proxy.scrollTo("word-end", anchor: .trailing) }.buttonStyle(.small)
                    }
                }
                .task(id: word) { proxy.scrollTo("word-end", anchor: .trailing) }
            }
        }
    }

    private var wordLabel: some View {
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            Text(String(word.dropLast())).foregroundStyle(Palette.ink)
            if let syllable = word.last {
                FinalSyllableView(word: word, syllable: String(syllable), size: size)
            }
        }
        .font(.pretendardFixed(size, .heavy))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel(word)
        .accessibilityIdentifier("current-word")
    }
}

private struct FinalSyllableView: View {
    let word: String
    let syllable: String
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animationTrigger = 0

    private struct Motion {
        var pulse = 1.0
        var sweep = 1.0
    }

    var body: some View {
        if reduceMotion {
            letter(Motion())
        } else {
            KeyframeAnimator(initialValue: Motion(), trigger: animationTrigger) { motion in
                letter(motion)
            } keyframes: { _ in
                KeyframeTrack(\.pulse) {
                    MoveKeyframe(1.0)
                    CubicKeyframe(1.10, duration: 0.065)
                    CubicKeyframe(1.0, duration: 0.125)
                }
                KeyframeTrack(\.sweep) {
                    MoveKeyframe(0.25)
                    CubicKeyframe(1.0, duration: 0.19)
                }
            }
            .task(id: word) { animationTrigger += 1 }
        }
    }

    private func letter(_ motion: Motion) -> some View {
        let font = CTFontCreateWithName(Font.pretendardName(.heavy) as CFString, size, nil)
        let attributed = NSAttributedString(string: syllable, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let advance = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let thickness = max(2, size * 0.042)
        let underlineCenter = max(0, -ink.minY) + size * 0.06 + thickness / 2
        let baseline = Alignment(horizontal: .center, vertical: .lastTextBaseline)

        return Text(syllable)
            .foregroundStyle(Palette.accent)
            .scaleEffect(motion.pulse, anchor: .bottom)
            .overlay(alignment: baseline) {
                Capsule()
                    .fill(Palette.accent)
                    .frame(width: ink.width, height: thickness)
                    .scaleEffect(x: motion.sweep, y: 1)
                    .offset(x: ink.midX - advance / 2)
                    .alignmentGuide(.lastTextBaseline) { $0[VerticalAlignment.center] - underlineCenter }
            }
    }
}
