import AppKit
import SwiftUI

@MainActor
final class PaywallWindowController {
    private var window: NSWindow?

    func show(store: StoreManager) {
        if window == nil {
            let newWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 340, height: 460),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            newWindow.title = "Paxo Pro"
            newWindow.titlebarAppearsTransparent = true
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
