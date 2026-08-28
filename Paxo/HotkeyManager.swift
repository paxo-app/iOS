import Carbon.HIToolbox
import Foundation

/// 사용자 지정 가능한 전역 단축키 정의
struct HotkeySpec: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var display: String

    static let `default` = HotkeySpec(
        keyCode: UInt32(kVK_ANSI_S),
        carbonModifiers: UInt32(optionKey | cmdKey),
        display: "⌥⌘S"
    )
}

/// 전역 단축키 등록.
/// RegisterEventHotKey는 샌드박스/Mac App Store에서 허용되는 API다.
final class HotkeyManager {
    var onHotkey: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    /// 단축키를 등록한다. 시스템 예약 조합 등으로 실패하면 false 반환.
    @discardableResult
    func register(_ spec: HotkeySpec) -> Bool {
        installHandlerIfNeeded()
        unregister()
        let hotKeyID = EventHotKeyID(signature: 0x5041584F /* 'PAXO' */, id: 1)
        let status = RegisterEventHotKey(
            spec.keyCode,
            spec.carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        if status != noErr {
            hotKeyRef = nil
            return false
        }
        return true
    }

    /// 단축키 녹화 중 등 일시적으로 전역 단축키를 끌 때 사용
    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { manager.onHotkey?() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }

    deinit {
        unregister()
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }
}
