import AppKit
import SwiftUI

@MainActor
final class ResultPanelController {
    private var panel: ResultPanel?
    private var userMoved = false

    func show(appState: AppState, on screen: NSScreen? = nil) {
        if panel == nil {
            let newPanel = ResultPanel(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 420),
                styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            newPanel.title = "Paxo"
            newPanel.level = .floating
            newPanel.titlebarAppearsTransparent = true
            newPanel.isReleasedWhenClosed = false
            newPanel.hidesOnDeactivate = false
            newPanel.becomesKeyOnlyIfNeeded = true
            newPanel.onUserMove = { [weak self] in self?.userMoved = true }
            newPanel.contentView = NSHostingView(
                rootView: ResultView().environmentObject(appState)
            )
            panel = newPanel
        }
        if !userMoved {
            position(using: appState.panelPosition, on: screen)
        }
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
        userMoved = false  // 다음 표시 때는 설정 위치에서 다시 시작
    }

    private func position(using panelPosition: PanelPosition, on screen: NSScreen?) {
        guard let panel, let target = screen ?? NSScreen.main else { return }
        panel.moveProgrammatically {
            panel.setFrameOrigin(panelPosition.origin(for: panel.frame.size, on: target))
        }
    }
}

final class ResultPanel: NSPanel, NSWindowDelegate {
    var onUserMove: (() -> Void)?
    private var suppressMoveCallback = false

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        delegate = self
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }

    /// 코드로 옮길 때 onUserMove가 잘못 발동하지 않게 감싼다
    func moveProgrammatically(_ block: () -> Void) {
        suppressMoveCallback = true
        block()
        suppressMoveCallback = false
    }

    func windowDidMove(_ notification: Notification) {
        guard !suppressMoveCallback else { return }
        onUserMove?()
    }
}
