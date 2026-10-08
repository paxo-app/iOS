import AppKit
import SwiftUI

/// 온보딩 창을 재사용해 초기 설정 중 중복 창이 생기지 않게 한다.
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
