import SwiftUI

struct HistoryView: View {
    let records: [MatchRecordViewState]
    @State private var selected: MatchRecordViewState?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.block) {
                ScreenHeading(title: "기록")
                if records.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        KoreanText("아직 끝낸 판이 없어요.").font(TextStyle.sheetTitle)
                        KoreanText("한 판을 마치면 여기에 남아요.")
                            .font(TextStyle.small).foregroundStyle(Palette.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                } else {
                    LazyVStack(spacing: 14) {
                        ForEach(records) { record in
                            Button { selected = record } label: {
                                RecordSummary(record: record)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .card(padding: 14)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("전체 단어 보기")
                        }
                    }
                }
            }
            .padding(.horizontal, Space.side)
            .padding(.vertical, 12)
        }
        .jamoWallpaper()
        .sheet(item: $selected) { record in
            SheetFrame(title: "경기 기록") {
                RecordSummary(record: record).card()
                ChainList(record: record)
                DisclosureGroup("기록 정보") {
                    ScrollView(.horizontal) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("경기 사전 \(record.version)")
                            Text("연결 규칙 \(record.connectionVersion)")
                        }
                        .font(TextStyle.small)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .font(TextStyle.smallBold)
                .card()
            }
        }
    }
}

struct RecordSummary: View {
    let record: MatchRecordViewState
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    date.fixedSize()
                    Spacer(minLength: 0)
                    count.fixedSize()
                }
                VStack(alignment: .leading, spacing: 6) {
                    date
                    count.frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            if !record.reason.isEmpty {
                KoreanText(record.reason).font(TextStyle.small).foregroundStyle(Palette.muted)
            }
            if !record.usesCurrentScoringRules {
                Text("이전 규칙").font(TextStyle.small).foregroundStyle(Palette.muted)
            }
        }
    }

    private var date: some View {
        Text(record.date.formatted(date: .abbreviated, time: .shortened))
            .font(TextStyle.small).foregroundStyle(Palette.muted)
    }

    private var count: some View {
        Text("\(record.wordCount)단어")
            .font(TextStyle.sheetTitle).foregroundStyle(Palette.accent)
            .monospacedDigit()
            .accessibilityIdentifier("record-count")
    }
}

struct MatchResultView: View {
    let record: MatchRecordViewState
    let bestScore: Int?
    let isPersonalBest: Bool
    let storageError: String?
    let retry: () -> Void
    let home: () -> Void
    let rematch: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showChain = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.block) {
                VStack(spacing: 10) {
                    Text("\(record.wordCount)단어 연결")
                        .font(TextStyle.bigNumber).foregroundStyle(Palette.accent)
                        .lineLimit(1).minimumScaleFactor(0.38)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("result-score")
                    if let move = record.finishingMove {
                        Text(move.label).font(TextStyle.bodyBold).foregroundStyle(Palette.accent)
                            .accessibilityIdentifier("finishing-move")
                    }
                    if isPersonalBest {
                        Text("새 최고 기록").font(TextStyle.smallBold).foregroundStyle(Palette.accent)
                    } else if record.usesCurrentScoringRules, let bestScore {
                        KoreanText("최고 기록 \(bestScore)단어", alignment: .center)
                            .font(TextStyle.small).foregroundStyle(Palette.muted)
                    }
                    if !record.reason.isEmpty {
                        KoreanText(record.reason, alignment: .center).foregroundStyle(Palette.muted)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .clearsWallpaper()
                if let storageError {
                    SaveErrorView(message: storageError, retry: retry)
                }
                Button("이어 온 단어 보기") { showChain = true }
                    .buttonStyle(.secondary)
                    .accessibilityIdentifier("show-chain")
            }
            .padding(.horizontal, Space.side)
            .padding(.top, 24)
            .padding(.bottom, 12)
        }
        .safeAreaInset(edge: .bottom) {
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(spacing: 10) { resultButtons }
                } else {
                    HStack(spacing: 10) { resultButtons }
                }
            }
            .barBackground()
        }
        .jamoWallpaper()
        .sheet(isPresented: $showChain) {
            SheetFrame(title: "이어 온 단어") {
                ChainList(record: record)
            }
        }
    }

    @ViewBuilder private var resultButtons: some View {
        Button("홈", action: home).buttonStyle(.secondary)
            .disabled(storageError != nil).accessibilityIdentifier("result-home")
        Button("다음 판", action: rematch).buttonStyle(.primary)
            .disabled(storageError != nil).accessibilityIdentifier("rematch")
    }
}

struct ChainList: View {
    let record: MatchRecordViewState
    @State private var selected: ChainWordViewState?
    @State private var chainWidth: CGFloat = 0
    @ScaledMetric(relativeTo: .body) private var minimumCellWidth = 66.0
    private let arrowWidth: CGFloat = 12

    private var columns: Int {
        min(4, max(1, Int((chainWidth + arrowWidth) / (minimumCellWidth + arrowWidth))))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text("내 단어")
                    .foregroundStyle(Palette.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Palette.accent.opacity(0.12), in: .rect(cornerRadius: 7))
                Text("컴퓨터").foregroundStyle(Palette.ink)
            }
            .font(TextStyle.smallBold)
            .clearsWallpaper()
            LazyVStack(spacing: 0) {
                ForEach(Array(stride(from: 0, to: record.words.count, by: columns)), id: \.self) { start in
                    chainRow(start, bend: false)
                    if start + columns < record.words.count {
                        chainRow(start, bend: true)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { chainWidth = $0 }
            .card(padding: 10)
            KoreanText("단어를 눌러 뜻을 확인할 수 있어요.")
                .font(TextStyle.section).foregroundStyle(Palette.muted).clearsWallpaper()
            if !record.endingCounts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(record.endingCounts) { ending in
                        KoreanText("‘\(ending.syllable)’로 \(ending.count)번 공격")
                            .accessibilityIdentifier("ending-count-\(ending.syllable)")
                    }
                }
                .font(TextStyle.smallBold)
                .card()
            }
        }
        .sheet(item: $selected) { move in
            DefinitionView(move: move, version: record.definitionVersion)
        }
    }

    private func chainRow(_ start: Int, bend: Bool) -> some View {
        let reversed = (start / columns) % 2 != 0
        return HStack(spacing: 0) {
            ForEach(0..<columns, id: \.self) { column in
                let index = start + column
                Group {
                    if bend, column == columns - 1 {
                        chainArrow("↓")
                    } else if !bend, record.words.indices.contains(index) {
                        chainWord(record.words[index], index: index)
                    } else {
                        Color.clear.frame(height: bend ? 14 : 44).accessibilityHidden(true)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity)
                if column < columns - 1 {
                    Group {
                        if !bend, record.words.indices.contains(index + 1) {
                            chainArrow(reversed ? "←" : "→")
                        } else {
                            Color.clear.frame(height: 0).accessibilityHidden(true)
                        }
                    }
                    .frame(width: arrowWidth)
                }
            }
        }
        .environment(\.layoutDirection, reversed ? .rightToLeft : .leftToRight)
    }

    private func chainArrow(_ arrow: String) -> some View {
        Text(arrow)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Palette.muted)
            .frame(height: 14)
            .accessibilityHidden(true)
    }

    private func chainWord(_ move: ChainWordViewState, index: Int) -> some View {
        Button { selected = move } label: {
            Text(move.word)
                .font(TextStyle.bodyBold)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 3)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(move.isPlayer ? Palette.accent : index == 0 ? Palette.muted : Palette.ink)
                .background(move.isPlayer ? Palette.accent.opacity(0.12) : .clear, in: .rect(cornerRadius: 7))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityLabel("\(index + 1)번째, \(move.actor), \(move.word)")
        .accessibilityHint("단어 뜻 보기")
        .accessibilityIdentifier("chain-word-\(move.id)")
        .accessibilitySortPriority(Double(record.words.count - index))
    }
}

struct DefinitionView: View {
    let move: ChainWordViewState
    let version: String

    var body: some View {
        SheetFrame(title: "단어 뜻") {
            VStack(alignment: .leading, spacing: 18) {
                ScrollView(.horizontal) {
                    Text(move.word).font(TextStyle.largeTitle).fixedSize()
                }
                .accessibilityLabel(move.word)
                HStack(spacing: 8) {
                    Text("명사").font(TextStyle.smallBold).foregroundStyle(Palette.accent)
                    Text(move.actor).font(TextStyle.small).foregroundStyle(Palette.muted)
                }
                KoreanText(move.definition.isEmpty ? "이 단어의 뜻풀이가 저장되어 있지 않아요." : move.definition)
                    .font(TextStyle.body)
                if !move.moveLabels.isEmpty {
                    KoreanText(move.moveLabels.joined(separator: ", "))
                        .font(TextStyle.small).foregroundStyle(Palette.muted)
                        .accessibilityIdentifier("definition-move")
                }
                if !move.source.isEmpty {
                    KoreanText(move.source).font(TextStyle.small).foregroundStyle(Palette.muted)
                }
                KoreanText("현재 앱의 뜻풀이 \(version)")
                    .font(TextStyle.small).foregroundStyle(Palette.muted)
            }
            .card(padding: 20)
        }
    }
}
