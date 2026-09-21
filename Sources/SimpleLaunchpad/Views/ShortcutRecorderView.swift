import SwiftUI
import AppKit
import Carbon

// A plain AppKit button rather than a SwiftUI-native control: capturing the
// *next* raw key event (including bare function keys, which SwiftUI has no
// gesture for) needs an `NSEvent` monitor, which only makes sense hung off
// an AppKit responder.
struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.onCapture = { newKeyCode, newModifiers in
            keyCode = newKeyCode
            modifiers = newModifiers
        }
        button.displayKeyCode = keyCode
        button.displayModifiers = modifiers
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.displayKeyCode = keyCode
        button.displayModifiers = modifiers
    }
}

final class ShortcutRecorderButton: NSButton {
    var onCapture: ((UInt32, UInt32) -> Void)?

    var displayKeyCode: UInt32 = 0 {
        didSet { if !isRecording { updateTitle() } }
    }
    var displayModifiers: UInt32 = 0 {
        didSet { if !isRecording { updateTitle() } }
    }

    private var isRecording = false
    private var localMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        target = self
        action = #selector(startRecording)
        updateTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        title = "Press a key…"

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // Esc cancels without changing anything
                self.stopRecording()
            } else {
                let modifiers = Self.carbonModifiers(from: event.modifierFlags)
                self.displayKeyCode = UInt32(event.keyCode)
                self.displayModifiers = modifiers
                self.stopRecording()
                self.onCapture?(UInt32(event.keyCode), modifiers)
            }
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        localMonitor = nil
        updateTitle()
    }

    private func updateTitle() {
        title = Self.description(keyCode: displayKeyCode, modifiers: displayModifiers)
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }

    static func description(keyCode: UInt32, modifiers: UInt32) -> String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        text += keyName(for: keyCode)
        return text
    }

    private static let keyNames: [UInt32: String] = [
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3", UInt32(kVK_F4): "F4",
        UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6", UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8",
        UInt32(kVK_F9): "F9", UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
        UInt32(kVK_Space): "Space", UInt32(kVK_Return): "Return", UInt32(kVK_Tab): "Tab",
        UInt32(kVK_Escape): "Esc", UInt32(kVK_Delete): "Delete"
    ]

    static func keyName(for keyCode: UInt32) -> String {
        if let name = keyNames[keyCode] { return name }
        // Best-effort for plain letter/number keys via the current keyboard
        // layout; falls back to the raw code for anything unmapped.
        if let layoutData = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
           let dataPointer = TISGetInputSourceProperty(layoutData, kTISPropertyUnicodeKeyLayoutData) {
            let data = Unmanaged<CFData>.fromOpaque(dataPointer).takeUnretainedValue() as Data
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            let result = data.withUnsafeBytes { rawBuffer -> OSStatus in
                guard let layoutPtr = rawBuffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                    return OSStatus(paramErr)
                }
                return UCKeyTranslate(
                    layoutPtr, UInt16(keyCode), UInt16(kUCKeyActionDisplay),
                    0, UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysBit),
                    &deadKeyState, chars.count, &length, &chars
                )
            }
            if result == noErr, length > 0 {
                return String(utf16CodeUnits: chars, count: length).uppercased()
            }
        }
        return "Key \(keyCode)"
    }

    deinit {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }
}
