import SwiftUI

struct WordChainRootView: View {
    let state: WordChainViewState
    let actions: WordChainActions
    @Binding var input: String
    @State private var tab = 0
    @State private var confirmEnd = false

    var body: some View {
        Group {
            switch state.screen {
            case .match:
                MatchView(state: state, actions: actions, input: $input) { confirmEnd = true }
            case .result:
                if let record = state.result {
                    MatchResultView(record: record, bestScore: state.bestScore, isPersonalBest: state.isPersonalBest,
                                    storageError: state.storageError, retry: actions.retrySave,
                                    home: actions.home, rematch: actions.rematch)
                }
            case .home:
                if !state.welcomed {
                    OnboardingView(ready: state.ready, start: actions.start)
                } else {
                    TabView(selection: $tab) {
                        HomeView(state: state, actions: actions)
                            .tabItem { Label("홈", systemImage: "house") }.tag(0)
                        HistoryView(records: state.history)
                            .tabItem { Label("기록", systemImage: "clock.arrow.circlepath") }.tag(1)
                        SettingsView(state: state, actions: actions)
                            .tabItem { Label("설정", systemImage: "gearshape") }.tag(2)
                    }
                    .tint(Palette.accent)
                }
            }
        }
        .font(TextStyle.body)
        .foregroundStyle(Palette.ink)
        .preferredColorScheme(state.theme.colorScheme)
        .alert("이 판을 끝낼까요?", isPresented: $confirmEnd) {
            Button("끝내기", role: .destructive, action: actions.resign)
            Button("취소", role: .cancel) {}
        } message: {
            Text("지금까지 이은 단어가 기록에 남아요.")
        }
        .onChange(of: state.screen) { _, screen in
            if screen != .match { confirmEnd = false }
        }
    }
}

struct HomeView: View {
    let state: WordChainViewState
    let actions: WordChainActions
    @State private var showHelp = false

    var body: some View {
        ScrollView {
            VStack(spacing: Space.block) {
                HStack(alignment: .top) {
                    ScreenHeading(title: "무한끝말잇기")
                    Spacer(minLength: 8)
                    Button("?") { showHelp = true }.buttonStyle(.small).accessibilityLabel("게임 방법")
                }
                .padding(.bottom, 24)
                ConnectionExample()
                VStack(spacing: 10) {
                    KoreanText("몇 단어까지 이을 수 있을까요?", alignment: .center)
                        .font(TextStyle.sheetTitle)
                    KoreanText("컴퓨터와 번갈아 이어 보세요. 내 차례마다 10초예요.", alignment: .center)
                        .font(TextStyle.small).foregroundStyle(Palette.muted)
                }
                .clearsWallpaper()
                if let error = state.storageError {
                    SaveErrorView(message: error, retry: actions.retrySave)
                }
            }
            .padding(.horizontal, Space.side)
            .padding(.vertical, 12)
        }
        .safeAreaInset(edge: .bottom) {
            Button("시작하기", action: actions.start)
                .buttonStyle(.primary)
                .disabled(!state.ready || state.storageError != nil)
                .accessibilityIdentifier("start-match")
                .barBackground()
        }
        .jamoWallpaper()
        .sheet(isPresented: $showHelp) { HelpView() }
    }
}

struct OnboardingView: View {
    let ready: Bool
    let start: () -> Void
    @State private var showHelp = false

    var body: some View {
        ScrollView {
            VStack(spacing: Space.block) {
                ScreenHeading(title: "무한끝말잇기")
                    .padding(.top, 12)
                KoreanText("한 단어씩, 번갈아 이어 가요", alignment: .center)
                    .font(TextStyle.sheetTitle).clearsWallpaper()
                ConnectionExample(animated: true).padding(.vertical, 16)
                VStack(alignment: .leading, spacing: 18) {
                    rule("마지막 글자로 시작해요", detail: "사과 다음에는 과자처럼 이어 주세요.")
                    rule("두 글자 이상의 명사를 써요", detail: "게임 사전에 있는 단어를 사용할 수 있어요.")
                    rule("내 차례는 10초예요", detail: "시작 단어부터 마지막 단어까지 모두 세어요.")
                }
                .card(padding: 20)
            }
            .padding(.horizontal, Space.side)
            .padding(.vertical, 12)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button("시작하기", action: start).buttonStyle(.primary).disabled(!ready).accessibilityIdentifier("onboarding-start")
                Button("게임 방법") { showHelp = true }.buttonStyle(.secondary)
            }
            .barBackground()
        }
        .jamoWallpaper()
        .sheet(isPresented: $showHelp) { HelpView() }
    }

    private func rule(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            KoreanText(title).font(TextStyle.bodyBold)
            KoreanText(detail).font(TextStyle.small).foregroundStyle(Palette.muted)
        }
    }
}

struct ConnectionExample: View {
    var animated = false
    @State private var showLastWord = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { exampleWords(arrow: "arrow.right") }
                    .fixedSize()
                VStack(spacing: 8) { exampleWords(arrow: "arrow.down") }
            }
            .font(.pretendard(34, .heavy, relativeTo: .largeTitle))
            .frame(maxWidth: .infinity, minHeight: 76)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("사과, 과자, 자동차. 사과의 과, 과자의 자에서 이어져요.")
            KoreanText("끝 글자를 이어 주세요", alignment: .center)
                .font(TextStyle.small).foregroundStyle(Palette.muted)
        }
        .clearsWallpaper()
        .task {
            guard animated, !reduceMotion else { showLastWord = true; return }
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.22)) { showLastWord = true }
        }
    }

    @ViewBuilder private func exampleWords(arrow: String) -> some View {
        endingHighlightedWord("사과")
        exampleArrow(arrow)
        endingHighlightedWord("과자")
        exampleArrow(arrow).opacity(showLastWord || !animated || reduceMotion ? 1 : 0)
        Text("자동차").fixedSize().opacity(showLastWord || !animated || reduceMotion ? 1 : 0)
    }

    private func exampleArrow(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(Palette.muted)
    }
}

struct HelpView: View {
    var body: some View {
        SheetFrame(title: "게임 방법") {
            VStack(alignment: .leading, spacing: 18) {
                help("마지막 글자로 이어 주세요", "컴퓨터와 번갈아 단어를 냅니다. 사과 → 과자 → 자동차처럼 이어 주세요.")
                help("사전에 있는 명사만 써요", "두 글자 이상의 한글 명사를 입력해 주세요. 이름, 사투리, 옛말, 띄어쓰기가 있는 말은 사용할 수 없어요.")
                help("같은 단어는 한 번만", "시작 단어도 이미 나온 단어에 포함돼요. 뜻이 달라도 같은 글자라면 다시 쓸 수 없어요.")
                help("내 차례마다 10초", "잘못 입력한 단어는 시간이 남아 있을 때 고칠 수 있어요. 다른 앱으로 이동해도 시작된 차례의 시간은 계속 흘러요.")
            }
            .card(padding: 20)
            VStack(alignment: .leading, spacing: 14) {
                KoreanText("이어 쓸 수 있는 글자").font(TextStyle.sheetTitle)
                KoreanText("화면에 표시된 시작 글자를 확인해 주세요.").foregroundStyle(Palette.muted)
                Text("리 → 리 또는 이\n로 → 로 또는 노\n력 → 력 또는 역\n름 → 름 또는 늠")
                    .font(TextStyle.bodyBold).foregroundStyle(Palette.accent).lineSpacing(6)
                KoreanText("이 → 리, 름 → 음, 렁 → 넝은 이 게임에서 이어지지 않아요.")
                    .font(TextStyle.small).foregroundStyle(Palette.muted)
            }
            .card(padding: 20)
            VStack(alignment: .leading, spacing: 12) {
                help("이은 단어가 기록이 돼요", "시작 단어부터 마지막 단어까지 모두 세어요. 시간이 다 되거나 더 이을 단어가 없으면 이번 기록을 확인할 수 있어요.")
                help("컴퓨터가 난이도를 조절해요", "처음에는 이어 쓰기 쉬운 단어를 골라요. 답하는 흐름에 따라 까다로운 글자와 쉬운 글자가 번갈아 나올 수 있어요.")
                help("도중에 끝낼 수 있어요", "끝내기를 눌러 이 판을 마칠 수 있어요. 확인하는 동안에도 남은 시간은 흘러요.")
            }
            .card(padding: 20)
        }
    }

    private func help(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            KoreanText(title).font(TextStyle.bodyBold)
            KoreanText(detail).font(TextStyle.small).foregroundStyle(Palette.muted)
        }
    }
}

struct SettingsView: View {
    let state: WordChainViewState
    let actions: WordChainActions
    @State private var showHelp = false
    @State private var showSources = false
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.block) {
                ScreenHeading(title: "설정")
                VStack(alignment: .leading, spacing: 18) {
                    Text("화면").font(TextStyle.section).foregroundStyle(Palette.muted)
                    Picker("테마", selection: Binding(get: { state.theme }, set: { actions.selectTheme($0) })) {
                        ForEach(Theme.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Divider().overlay(Palette.line)
                    Toggle("게임 진동", isOn: Binding(get: { state.haptics }, set: { actions.setHaptics($0) })).tint(Palette.fill)
                }
                .card()
                VStack(spacing: 0) {
                    settingsButton("게임 방법") { showHelp = true }
                    Divider().overlay(Palette.line)
                    settingsButton("사전 출처") { showSources = true }
                }
                .card(padding: 0)
                VStack(alignment: .leading, spacing: 12) {
                    Button { confirmDelete = true } label: {
                        Text("내 기록 삭제")
                            .foregroundStyle(Palette.destructiveText)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    KoreanText("게임 기록과 설정은 이 기기에 저장돼요. 기기 백업에는 포함될 수 있어요.")
                        .font(TextStyle.small).foregroundStyle(Palette.muted)
                }
                .card()
                if let error = state.storageError {
                    SaveErrorView(message: error, retry: actions.retrySave)
                }
                Text("버전 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                    .font(TextStyle.small).foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity).clearsWallpaper()
            }
            .padding(.horizontal, Space.side)
            .padding(.vertical, 12)
        }
        .jamoWallpaper()
        .sheet(isPresented: $showHelp) { HelpView() }
        .sheet(isPresented: $showSources) {
            SheetFrame(title: "사전 출처") {
                VStack(alignment: .leading, spacing: 14) {
                    KoreanText("국립국어원 사전 자료").font(TextStyle.sheetTitle)
                    KoreanText("한국어기초사전 · 표준국어대사전 · 우리말샘").font(TextStyle.bodyBold)
                    KoreanText("게임 규칙에 맞는 명사를 골라 기기에 담았습니다. 모든 사전 표제어가 게임에서 인정되는 것은 아니에요.")
                        .font(TextStyle.small).foregroundStyle(Palette.muted)
                    Text("게임 사전 \(state.dictionaryVersion)").font(TextStyle.small)
                    Text("\(state.dictionaryCount.formatted())개 단어").font(TextStyle.small)
                    KoreanText("뜻풀이는 각 단어에 표시된 사전의 자료입니다.").font(TextStyle.small).foregroundStyle(Palette.muted)
                    KoreanText("게임에 맞게 표제어를 골라 표기를 정리하고 일부 뜻풀이를 발췌했어요.")
                        .font(TextStyle.small).foregroundStyle(Palette.muted)
                    Link("사전 데이터 이용 조건 · CC BY-SA 2.0 KR",
                         destination: URL(string: "https://creativecommons.org/licenses/by-sa/2.0/kr/")!)
                        .font(TextStyle.smallBold)
                    Link("국립국어연구원 현대 국어 사용 빈도 조사 · 공공누리 제1유형",
                         destination: URL(string: "https://www.korean.go.kr/front/etcData/etcDataView.do?etc_seq=61&mn_id=96")!)
                        .font(TextStyle.small)
                    ShareLink(items: dictionaryFiles) {
                        Label("사전 데이터 내보내기", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.secondary)
                    .disabled(dictionaryFiles.count != 6)
                }
                .card()
            }
        }
        .alert("내 기록을 모두 지울까요?", isPresented: $confirmDelete) {
            Button("모두 삭제", role: .destructive, action: actions.deleteLocalData)
            Button("취소", role: .cancel) {}
        } message: {
            Text("이 기기의 게임 기록과 설정을 지워요. 되돌릴 수 없어요. 이미 만든 기기 백업은 지워지지 않아요.")
        }
    }

    private var dictionaryFiles: [URL] {
        ["DictionaryCredits.txt", "manifest.json", "words.tsv", "seeds.tsv", "excluded.tsv", "definitions.tsv"]
            .compactMap { Bundle.main.url(forResource: $0, withExtension: nil) }
    }

    private func settingsButton(_ title: String, icon: String = "chevron.right", action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                KoreanText(title)
                Spacer(minLength: 8)
                Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 56)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

struct SaveErrorView: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            KoreanText("저장하지 못했어요").font(TextStyle.bodyBold)
            KoreanText(message).font(TextStyle.small).foregroundStyle(Palette.muted)
            Button("저장 다시 시도", action: retry).buttonStyle(.secondary)
        }
        .card()
        .accessibilityElement(children: .contain)
    }
}
