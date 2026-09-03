import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 설정 화면의 단축키 녹화 컨트롤.
/// "변경"을 누르면 다음 키 입력을 새 단축키로 저장한다. (Esc 취소)
struct HotkeyRecorderField: View {
    @EnvironmentObject private var appState: AppState
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Text(isRecording ? "키 조합 입력…" : appState.hotkey.display)
                .font(.body.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isRecording ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12))
                )
            if appState.hotkey != .default && !isRecording {
                Button("기본값") {
                    appState.hotkey = .default
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Button(isRecording ? "취소" : "변경") {
                isRecording ? stopRecording() : startRecording()
            }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        guard monitor == nil else { return }
        isRecording = true
        appState.suspendHotkey()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        appState.resumeHotkey()
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == 53 { // Escape
            stopRecording()
            return
        }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        // 일반 타이핑을 가로채지 않도록 ⌘/⌥/⌃ 중 하나는 필수
        guard flags.contains(.command) || flags.contains(.option) || flags.contains(.control) else {
            NSSound.beep()
            return
        }

        var carbon: UInt32 = 0
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }

        let display = Self.symbols(for: flags) + Self.keyName(for: event)
        appState.hotkey = HotkeySpec(
            keyCode: UInt32(event.keyCode),
            carbonModifiers: carbon,
            display: display
        )
        stopRecording()
    }

    private static func symbols(for flags: NSEvent.ModifierFlags) -> String {
        var result = ""
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.shift) { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }
        return result
    }

    private static let specialKeyNames: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥",
        kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    private static func keyName(for event: NSEvent) -> String {
        if let name = specialKeyNames[Int(event.keyCode)] {
            return name
        }
        return event.charactersIgnoringModifiers?.uppercased() ?? "?"
    }
}
