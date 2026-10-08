import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?

    func show(appState: AppState, onFinish: @escaping () -> Void) {
        if window == nil {
            let newWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 440),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            newWindow.title = "Paxo 시작하기"
            newWindow.titlebarAppearsTransparent = false
            newWindow.isOpaque = false
            newWindow.backgroundColor = .clear
            newWindow.isReleasedWhenClosed = false
            newWindow.contentView = NSHostingView(
                rootView: OnboardingView(onFinish: { [weak self] in
                    onFinish()
                    self?.window?.orderOut(nil)
                })
                .environmentObject(appState)
            )
            newWindow.center()
            window = newWindow
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
