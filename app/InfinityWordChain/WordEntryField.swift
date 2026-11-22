import GameController
import SwiftUI
import UIKit

struct WordEntryField: View {
    @Binding var text: String
    let enabled: Bool
    let focus: Bool
    let onSubmit: (ContinuousClock.Instant) -> Void
    let onReady: () -> Void
    @ScaledMetric(relativeTo: .title3) private var entryTextSize = 22.0
    @State private var bridge = EntryBridge()

    var body: some View {
        HStack(spacing: 8) {
            KoreanEntry(bridge: bridge, text: $text, acceptsInput: enabled, focus: focus,
                        onSubmit: onSubmit, onReady: onReady)
                .padding(.horizontal, 14)
                .frame(height: max(56, entryTextSize + 24))
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.line))
            Button("입력") { bridge.submit() }
                .buttonStyle(.primary)
                .fixedSize()
                .disabled(!enabled)
                .opacity(enabled ? 1 : 0.65)
                .accessibilityIdentifier("submit-word")
        }
    }
}

@MainActor
final class EntryBridge: NSObject, UITextFieldDelegate {
    weak var field: UITextField?
    var parent: KoreanEntry?
    var softwareKeyboard = false

    func submit() {
        guard let parent, parent.acceptsInput, let field else { return }
        let submittedAt = ContinuousClock.now
        field.unmarkText()
        parent.text = field.text ?? ""
        parent.onSubmit(submittedAt)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        submit()
        return false
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        parent?.acceptsInput == true
    }

    @objc func changed(_ field: UITextField) {
        if parent?.acceptsInput == true { parent?.text = field.text ?? "" }
    }

    @objc func keyboardShown() {
        softwareKeyboard = true
        reportReady()
    }

    @objc func keyboardHidden() { softwareKeyboard = false }
    @objc func sceneActivated() { focusWhenAttached() }
    @objc func reportReady() {
        guard let field, field.isFirstResponder, let window = field.window, window.isKeyWindow,
              window.windowScene?.activationState == .foregroundActive else { return }
        let guideHeight = window.keyboardLayoutGuide.layoutFrame.height
        guard softwareKeyboard || guideHeight > window.safeAreaInsets.bottom + 1 ||
                GCKeyboard.coalesced != nil else { return }
        parent?.onReady()
    }

    func focusWhenAttached() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let field, field.window != nil else { return }
            if parent?.focus == true, !field.isFirstResponder { field.becomeFirstResponder() }
            reportReady()
        }
    }

    func textFieldDidBeginEditing(_ textField: UITextField) { reportReady() }
}

struct KoreanEntry: UIViewRepresentable {
    let bridge: EntryBridge
    @Binding var text: String
    let acceptsInput: Bool
    let focus: Bool
    let onSubmit: (ContinuousClock.Instant) -> Void
    let onReady: () -> Void

    func makeCoordinator() -> EntryBridge { bridge }

    func makeUIView(context: Context) -> UITextField {
        let field = KoreanWordTextField()
        field.availabilityChanged = { [weak bridge] in bridge?.focusWhenAttached() }
        bridge.field = field
        bridge.parent = self
        bridge.softwareKeyboard = false
        field.delegate = bridge
        field.font = UIFontMetrics(forTextStyle: .title3).scaledFont(
            for: UIFont(name: "Pretendard-SemiBold", size: 22) ?? .systemFont(ofSize: 22, weight: .semibold)
        )
        field.adjustsFontForContentSizeCategory = true
        field.textColor = UIColor(Palette.ink)
        field.tintColor = UIColor(Palette.accent)
        field.attributedPlaceholder = NSAttributedString(string: "단어 입력", attributes: [
            .foregroundColor: UIColor(Palette.muted),
            .font: UIFontMetrics(forTextStyle: .title3).scaledFont(
                for: UIFont(name: "Pretendard-Regular", size: 22) ?? .systemFont(ofSize: 22)
            ),
        ])
        field.accessibilityLabel = "단어 입력"
        field.accessibilityIdentifier = "word-input"
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.inlinePredictionType = .no
        field.returnKeyType = .done
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.addTarget(bridge, action: #selector(EntryBridge.changed(_:)), for: .editingChanged)
        let notifications = NotificationCenter.default
        notifications.addObserver(bridge, selector: #selector(EntryBridge.keyboardShown), name: UIResponder.keyboardDidShowNotification, object: nil)
        notifications.addObserver(bridge, selector: #selector(EntryBridge.keyboardHidden), name: UIResponder.keyboardWillHideNotification, object: nil)
        notifications.addObserver(bridge, selector: #selector(EntryBridge.reportReady), name: .GCKeyboardDidConnect, object: nil)
        notifications.addObserver(bridge, selector: #selector(EntryBridge.sceneActivated), name: UIScene.didActivateNotification, object: nil)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        bridge.parent = self
        if field.markedTextRange == nil, field.text != text { field.text = text }
        bridge.focusWhenAttached()
    }

    static func dismantleUIView(_ field: UITextField, coordinator: EntryBridge) {
        NotificationCenter.default.removeObserver(coordinator)
        (field as? KoreanWordTextField)?.availabilityChanged = nil
        field.delegate = nil
        coordinator.field = nil
        coordinator.parent = nil
    }
}

private final class KoreanWordTextField: UITextField {
    var availabilityChanged: (() -> Void)?

    override var textInputMode: UITextInputMode? {
        UITextInputMode.activeInputModes.first { $0.primaryLanguage?.hasPrefix("ko") == true } ?? super.textInputMode
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        availabilityChanged?()
    }
}
