import AppKit
import SwiftUI

/// 충전 안내 창을 재사용하고 구매 상태를 같은 저장소에서 관찰하게 한다.
@MainActor
final class PaywallWindowController {
    private var window: NSWindow?

    func show(store: StoreManager) {
        if window == nil {
            let newWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 650),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            newWindow.title = "풀이권 충전"
            newWindow.titlebarAppearsTransparent = false
            newWindow.isOpaque = false
            newWindow.backgroundColor = .clear
            newWindow.isReleasedWhenClosed = false
            newWindow.contentView = NSHostingView(
                rootView: PaywallView().environmentObject(store)
            )
            newWindow.center()
            window = newWindow
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
