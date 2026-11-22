import XCTest

final class MatchFlowTests: XCTestCase {
    @MainActor
    func testChainScoreResultDefinitionAndRematch() {
        let app = launchMatch(seed: "자동차")
        let submit = app.buttons["submit-word"]
        let score = app.staticTexts["match-score"]
        let current = app.staticTexts["current-word"]
        XCTAssertEqual(current.label, "자동차")
        XCTAssertEqual(score.label, "연결 1단어")
        XCTAssertFalse(app.descendants(matching: .any)["connection-cue"].exists)
        XCTAssertFalse(app.buttons["pause-match"].exists)

        app.textFields["word-input"].typeText("차표")
        submit.tap()
        XCTAssertTrue(waitForLabel("연결 3단어", on: score))
        XCTAssertTrue(waitForEnabled(submit))
        XCTAssertTrue(current.label.hasPrefix("표"))
        let reply = current.label
        endMatch(app)

        let rematch = app.buttons["rematch"]
        XCTAssertTrue(rematch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["result-score"].label, "3단어 연결")
        XCTAssertTrue(app.staticTexts["새 최고 기록"].exists)
        capture("result", app: app)

        app.buttons["show-chain"].tap()
        let openingWord = app.buttons["chain-word-0"]
        for _ in 0..<4 where !openingWord.isHittable { app.swipeUp() }
        XCTAssertTrue(openingWord.isHittable)
        XCTAssertTrue(openingWord.label.contains("자동차"))
        XCTAssertTrue(app.buttons["chain-word-1"].label.contains("차표"))
        XCTAssertTrue(app.buttons["chain-word-2"].label.contains(reply))
        capture("chain", app: app)
        openingWord.tap()
        let definitionTitle = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "단어 뜻")).firstMatch
        XCTAssertTrue(definitionTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "엔진의 힘으로")).firstMatch.exists)
        capture("definition", app: app)
        app.buttons["close-단어 뜻"].tap()
        app.buttons["close-이어 온 단어"].tap()

        rematch.tap()
        XCTAssertTrue(waitForEnabled(submit))
        XCTAssertEqual(current.label, "자동차")
        XCTAssertEqual(score.label, "연결 1단어")
        XCTAssertTrue((1...10).contains(remainingSeconds(in: app)))
        endMatch(app)
        XCTAssertTrue(rematch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["result-score"].label, "1단어 연결")
        XCTAssertFalse(app.staticTexts["새 최고 기록"].exists)

        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["start-match"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts["최고 기록"].exists)
        capture("home-after-personal-best", app: app)
    }

    @MainActor
    func testAlternateStartsKeepInvalidInputUntilTimeout() {
        let app = launchMatch(seed: "다리")
        let input = app.textFields["word-input"]
        let current = app.staticTexts["current-word"]
        let cue = app.descendants(matching: .any)["connection-cue"]
        XCTAssertEqual(current.label, "다리")
        XCTAssertTrue(cue.isHittable)
        XCTAssertTrue(cue.label.contains("리 또는 이"))
        XCTAssertTrue(input.isHittable)
        XCTAssertGreaterThan(input.frame.minY, current.frame.maxY)
        capture("alternate-starts", app: app)

        input.typeText("abc")
        app.buttons["submit-word"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["input-feedback"].waitForExistence(timeout: 3))
        XCTAssertEqual(input.value as? String, "abc")

        let timer = app.staticTexts["turn-timer"]
        let urgent = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            timer.value as? String == "5초"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [urgent], timeout: 10), .completed)
        capture("alternate-starts-five-seconds", app: app)
        XCTAssertTrue(app.buttons["rematch"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["result-score"].label, "1단어 연결")
    }

    @MainActor
    func testBackgroundExpiryAndRelaunchArchivesTheRound() async throws {
        let app = launchMatch(seed: "자동차")
        let submit = app.buttons["submit-word"]
        XCTAssertTrue((1...10).contains(remainingSeconds(in: app)))
        XCUIDevice.shared.press(.home)
        try await Task.sleep(for: .seconds(11))
        app.activate()
        XCTAssertTrue(app.buttons["rematch"].waitForExistence(timeout: 4))
        XCTAssertEqual(app.staticTexts["result-score"].label, "1단어 연결")
        XCTAssertFalse(app.buttons["resume-match"].exists)
        capture("background-timeout", app: app)

        app.buttons["rematch"].tap()
        XCTAssertTrue(waitForEnabled(submit))
        app.textFields["word-input"].typeText("차표")
        submit.tap()
        XCTAssertTrue(waitForLabel("연결 3단어", on: app.staticTexts["match-score"]))
        app.terminate()
        app.launch()
        let start = app.buttons["start-match"]
        XCTAssertTrue(start.waitForExistence(timeout: 20))
        XCTAssertTrue(waitForEnabled(start))
        XCTAssertFalse(app.buttons["resume-match"].exists)
        XCTAssertFalse(app.staticTexts["current-word"].exists)

        let tab = app.tabBars.firstMatch
        tab.buttons["기록"].tap()
        let interrupted = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "중단된 판"))
        XCTAssertTrue(interrupted.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(interrupted.count, 1)
        interrupted.firstMatch.tap()
        let openingWord = app.buttons["chain-word-0"]
        XCTAssertTrue(openingWord.waitForExistence(timeout: 5))
        XCTAssertTrue(openingWord.label.contains("자동차"))
        XCTAssertTrue(app.buttons["chain-word-1"].label.contains("차표"))
        XCTAssertTrue(app.buttons["chain-word-2"].label.contains("컴퓨터"))
        capture("interrupted-history", app: app)
        app.buttons["close-경기 기록"].tap()

        tab.buttons["설정"].tap()
        let sources = app.buttons["사전 출처"]
        for _ in 0..<4 where !sources.isHittable { app.swipeUp() }
        XCTAssertTrue(sources.isHittable)
        sources.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "국립국어원 사전 자료")).firstMatch.waitForExistence(timeout: 5))
        let export = app.buttons["사전 데이터 내보내기"]
        for _ in 0..<4 where !export.isHittable { app.swipeUp() }
        XCTAssertTrue(export.isHittable && export.isEnabled)
        capture("dictionary-source", app: app)

        app.buttons["close-사전 출처"].tap()
        let help = app.buttons["게임 방법"]
        for _ in 0..<4 where !help.isHittable { app.swipeDown() }
        XCTAssertTrue(help.isHittable)
        help.tap()
        let pacing = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "컴퓨터가 난이도를 조절해요")).firstMatch
        for _ in 0..<8 where !pacing.isHittable { app.swipeUp() }
        XCTAssertTrue(pacing.isHittable)
        capture("pacing-help", app: app)
    }

    @MainActor
    func testFinishingMoveCountsThePlayerWord() {
        let app = launchMatch(seed: "딸기")
        app.textFields["word-input"].typeText("기쁨")
        app.buttons["submit-word"].tap()
        XCTAssertTrue(app.buttons["rematch"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["result-score"].label, "2단어 연결")
        let finishing = app.descendants(matching: .any)["finishing-move"]
        XCTAssertTrue(finishing.exists)
        XCTAssertEqual(finishing.label, "한방 · 쁨")
        capture("finishing-move", app: app)
    }

    @MainActor
    func testPressureMoveAppearsOnTheNextTurn() {
        let app = launchMatch(seed: "파트")
        app.textFields["word-input"].typeText("트럭")
        app.buttons["submit-word"].tap()
        let special = app.descendants(matching: .any)["special-move"]
        XCTAssertEqual(special.label, "압박 · 럭")
        capture("pressure-move", app: app)
        XCTAssertEqual(app.staticTexts["match-score"].label, "연결 3단어")
        endMatch(app)
        app.buttons["show-chain"].tap()
        let playerWord = app.buttons["chain-word-1"]
        XCTAssertTrue(playerWord.label.contains("나, 트럭"))
        XCTAssertFalse(playerWord.label.contains("압박"))
        playerWord.tap()
        let recordedMove = app.descendants(matching: .any)["definition-move"]
        XCTAssertTrue(recordedMove.waitForExistence(timeout: 5))
        XCTAssertEqual(recordedMove.label, "압박 · 럭")
    }

    @MainActor
    func testReturningMoveIsRecordedInTheChain() {
        let app = launchMatch(seed: "생명", randomSeed: 2)
        let input = app.textFields["word-input"]
        let submit = app.buttons["submit-word"]
        let current = app.staticTexts["current-word"]
        input.typeText("명태")
        submit.tap()
        XCTAssertTrue(waitForLabel("태도", on: current))
        XCTAssertTrue(waitForEnabled(submit))

        input.typeText("도태")
        submit.tap()
        XCTAssertTrue(waitForLabel("태권도", on: current))
        XCTAssertTrue(waitForEnabled(submit))

        input.typeText("도화양태")
        submit.tap()
        XCTAssertTrue(waitForLabel("연결 7단어", on: app.staticTexts["match-score"]))
        endMatch(app)
        XCTAssertEqual(app.staticTexts["result-score"].label, "7단어 연결")

        app.buttons["show-chain"].tap()
        let repeats = app.descendants(matching: .any)["ending-count-태"]
        XCTAssertTrue(repeats.waitForExistence(timeout: 5))
        XCTAssertEqual(repeats.label, "‘태’로 3번 공격")
        let returningWord = app.buttons["chain-word-3"]
        for _ in 0..<4 where !returningWord.isHittable { app.swipeUp() }
        XCTAssertTrue(returningWord.isHittable)
        XCTAssertTrue(returningWord.label.contains("도태"))
        capture("returning-move-chain", app: app)
        returningWord.tap()
        let recordedMove = app.descendants(matching: .any)["definition-move"]
        XCTAssertTrue(recordedMove.waitForExistence(timeout: 5))
        XCTAssertEqual(recordedMove.label, "되받기 · 태")
    }

    @MainActor
    private func launchMatch(seed: String, randomSeed: UInt64? = nil) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["WORD_CHAIN_TEST_SEED"] = seed
        app.launchEnvironment["WORD_CHAIN_TEST_SAVE"] = UUID().uuidString
        if let randomSeed { app.launchEnvironment["WORD_CHAIN_TEST_RANDOM"] = String(randomSeed) }
        app.launch()
        let start = app.buttons["onboarding-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 20))
        XCTAssertTrue(waitForEnabled(start))
        start.tap()
        let keyboardIntro = app.buttons["Continue"]
        if keyboardIntro.exists { keyboardIntro.tap() }
        XCTAssertTrue(waitForEnabled(app.buttons["submit-word"]))
        return app
    }

    @MainActor
    private func endMatch(_ app: XCUIApplication) {
        app.buttons["end-match"].tap()
        let confirm = app.alerts["이 판을 끝낼까요?"].buttons["끝내기"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
    }

    @MainActor
    private func remainingSeconds(in app: XCUIApplication) -> Int {
        guard let seconds = app.staticTexts["turn-timer"].value as? String else { return 0 }
        return Int(seconds.dropLast()) ?? 0
    }

    @MainActor
    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func waitForEnabled(_ element: XCUIElement) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true"), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 12) == .completed
    }

    @MainActor
    private func waitForLabel(_ label: String, on element: XCUIElement) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND label == %@", label), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 4) == .completed
    }
}
