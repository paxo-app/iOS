import AppKit
import SwiftUI

/// 결과와 홈을 같은 패널에서 보여주고 화면 전환에 맞게 창 크기를 관리한다.
@MainActor
final class ResultPanelController {
    private var panel: ResultPanel?
    private var userMoved = false
    private let navigation = ResultPanelNavigation()
    private var resultHeight: CGFloat?

    func show(appState: AppState, on screen: NSScreen? = nil) {
        navigation.showsHome = false
        if let resultHeight {
            panel?.minSize = NSSize(width: 360, height: 300)
            resizeHeight(to: resultHeight)
            self.resultHeight = nil
        }
        if panel == nil {
            let newPanel = ResultPanel(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 420),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            newPanel.title = "Paxo"
            newPanel.level = .floating
            newPanel.titlebarAppearsTransparent = false
            newPanel.isOpaque = false
            newPanel.backgroundColor = .clear
            newPanel.minSize = NSSize(width: 360, height: 300)
            newPanel.isReleasedWhenClosed = false
            newPanel.hidesOnDeactivate = false
            newPanel.becomesKeyOnlyIfNeeded = true
            newPanel.onUserMove = { [weak self] in self?.userMoved = true }
            let hosting = NSHostingView(
                rootView: ResultPanelContentView(
                    navigation: navigation,
                    onHomeSizeChange: { [weak self] size in self?.resizeHome(to: size) },
                    onResultAppear: { [weak self] in
                        guard let self, !self.navigation.showsHome else { return }
                        self.panel?.minSize = NSSize(width: 360, height: 300)
                    }
                )
                .environmentObject(appState)
            )
            hosting.sizingOptions = []
            newPanel.contentView = hosting
            panel = newPanel
        }
        if !userMoved {
            position(using: appState.panelPosition, on: screen)
        }
        if let panel, panel.isMiniaturized {
            panel.deminiaturize(nil)
        }
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
        userMoved = false  // 다음 표시 때는 설정 위치에서 다시 시작
    }

    private func resizeHome(to size: CGSize) {
        guard navigation.showsHome, let panel, size.height > 0 else { return }
        if resultHeight == nil {
            resultHeight = panel.frame.height
        }
        panel.minSize = NSSize(width: 360, height: 0)
        let titlebarHeight = panel.frame.height - panel.contentRect(forFrameRect: panel.frame).height
        resizeHeight(to: ceil(size.height) + titlebarHeight)
    }

    /// 토글을 눌러도 제목 표시줄은 제자리에 두고 창 아래쪽만 늘린다.
    private func resizeHeight(to height: CGFloat) {
        guard let panel else { return }
        var frame = panel.frame
        let top = frame.maxY
        let visibleFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        frame.size.height = min(height, visibleFrame?.height ?? height)
        frame.origin.y = top - frame.height
        if let visibleFrame {
            frame.origin.y = min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - frame.height)
        }
        guard abs(panel.frame.height - frame.height) > 0.5 else { return }
        panel.moveProgrammatically {
            panel.setFrame(frame, display: true)
        }
    }

    private func position(using panelPosition: PanelPosition, on screen: NSScreen?) {
        guard let panel, let target = screen ?? NSScreen.main else { return }
        panel.moveProgrammatically {
            panel.setFrameOrigin(panelPosition.origin(for: panel.frame.size, on: target))
        }
    }
}

@MainActor
private final class ResultPanelNavigation: ObservableObject {
    @Published var showsHome = false
}

private struct ResultPanelContentView: View {
    @ObservedObject var navigation: ResultPanelNavigation
    let onHomeSizeChange: (CGSize) -> Void
    let onResultAppear: () -> Void

    var body: some View {
        Group {
            if navigation.showsHome {
                ScrollView {
                    MenuContentView(keepsResultPanelVisible: true)
                        .padding(.vertical, 8)
                        .fixedSize(horizontal: false, vertical: true)
                        .background {
                            GeometryReader { geometry in
                                Color.clear
                                    .onAppear { onHomeSizeChange(geometry.size) }
                                    .onChange(of: geometry.size) { onHomeSizeChange(geometry.size) }
                            }
                        }
                }
            } else {
                ResultView(onBack: { navigation.showsHome = true }, backTitle: "이전 · 홈")
                    .onAppear {
                        DispatchQueue.main.async(execute: onResultAppear)
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .paxoSurface(cornerRadius: 0)
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
