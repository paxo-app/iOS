import AppKit
import SwiftUI

/// 토스트를 하나의 패널로 재사용해 결과 갱신 중 중복 알림을 막는다.
@MainActor
final class ToastController {
    private var panel: NSPanel?
    private var hosting: NSHostingView<AnyView>?
    private var isVisible = false

    func show(appState: AppState, on screen: NSScreen? = nil) {
        let host = ensurePanel(appState: appState)
        let content = AnyView(ToastView().environmentObject(appState))
        host.rootView = content

        guard let panel, let screen = screen ?? NSScreen.main else { return }

        let size = Self.size(of: content)
        panel.setContentSize(size)
        panel.setFrameOrigin(appState.panelPosition.origin(for: size, on: screen, margin: 28))

        if isVisible {
            panel.orderFrontRegardless()
        } else {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                panel.animator().alphaValue = 1
            }
            isVisible = true
        }
    }

    func dismiss() {
        guard let panel, isVisible else { return }
        isVisible = false
        NSAnimationContext.runAnimationGroup(
            { ctx in
                ctx.duration = 0.3
                panel.animator().alphaValue = 0
            },
            completionHandler: { [weak self, weak panel] in
                // 페이드 중 show()가 다시 호출돼 isVisible=true가 됐으면 이 낡은 완료는 무시.
                guard let self, !self.isVisible else { return }
                panel?.orderOut(nil)
            })
    }

    private func ensurePanel(appState: AppState) -> NSHostingView<AnyView> {
        if let hosting { return hosting }
        let newPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.level = .floating
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = true
        newPanel.isReleasedWhenClosed = false
        newPanel.hidesOnDeactivate = false
        newPanel.becomesKeyOnlyIfNeeded = true
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let host = NSHostingView(rootView: AnyView(EmptyView()))
        // 창 크기는 show()만 정한다. 호스팅 뷰가 내용에 맞춰 창을 다시 줄이면
        // 왼쪽 아래 모서리만 고정된 채 줄어서 설정한 위치에서 어긋난다.
        host.sizingOptions = []
        newPanel.contentView = host
        panel = newPanel
        hosting = host
        return host
    }

    /// 표시용 호스팅 뷰는 크기를 재지 않으므로 따로 만든 뷰로 잰다.
    private static func size(of content: AnyView) -> CGSize {
        let ideal = NSHostingView(rootView: content.fixedSize()).fittingSize
        let width = min(max(ideal.width, 120), 560)
        var height = ideal.height
        if ideal.width > width {
            // 최대 폭을 넘는 정답은 줄바꿈되므로 그 폭에서 높이를 다시 잰다.
            let wrapped = content.frame(width: width).fixedSize(horizontal: false, vertical: true)
            height = NSHostingView(rootView: wrapped).fittingSize.height
        }
        return CGSize(width: width, height: min(max(height, 52), 260))
    }
}

private struct ToastView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        content
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            // 말풍선이 정해진 창 크기를 채워야 창 위치와 말풍선 위치가 같다.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .paxoSurface(cornerRadius: 16)
    }

    @ViewBuilder
    private var content: some View {
        switch appState.phase {
        case .checkingAccess, .capturing, .solvingAnswer:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("푸는 중…")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        default:
            if let answer = appState.current?.answer {
                Text(answer)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
            } else {
                Text("—").font(.title2)
            }
        }
    }
}
