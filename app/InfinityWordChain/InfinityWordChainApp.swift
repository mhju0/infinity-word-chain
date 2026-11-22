import SwiftUI

@main
struct InfinityWordChainApp: App {
    @State private var model = MatchModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WordChainRootView(state: model.view, actions: model.actions, input: Binding(
                get: { model.input }, set: { model.edit($0) }
            ))
            .task { await model.load() }
            .onChange(of: scenePhase, initial: true) { _, phase in
                model.setActive(phase == .active)
            }
            .alert(model.unreadableSave ? "저장 기록을 열 수 없어요" : "게임을 준비하지 못했어요", isPresented: Binding(
                get: { model.loadError }, set: { model.loadError = $0 }
            )) {
                if model.unreadableSave {
                    Button("기록 삭제 후 시작", role: .destructive) { Task { await model.resetUnreadableSave() } }
                }
                Button("다시 시도") { Task { await model.load() } }
                Button("닫기", role: .cancel) {}
            } message: {
                Text(model.unreadableSave
                     ? "기록 삭제 후 시작을 선택하면 이 기기의 게임 기록과 설정이 지워져요."
                     : "단어 자료나 저장 공간을 확인한 뒤 다시 시도해 주세요.")
            }
        }
    }
}
