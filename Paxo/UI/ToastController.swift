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
        // 대기 모습은 띄우는 순간에 고정한다. 대기 중 설정을 바꿔도 이미 잰 토스트 크기와 어긋나지 않게.
        host.rootView = AnyView(
            ToastView(waitingStyle: appState.toastWaitingStyle).environmentObject(appState).fixedSize()
        )

        guard let panel, let screen = screen ?? NSScreen.main else { return }

        host.layoutSubtreeIfNeeded()
        let fitting = host.fittingSize
        let size = CGSize(
            width: min(max(fitting.width, 120), 560),
            height: min(max(fitting.height, 52), 260)
        )
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

    /// 정답을 보여준 뒤에만 페이드로 닫는다. 취소 · 오류처럼 정답 없이 닫을 때 페이드하면
    /// 그 사이 내용이 빈 자리("—")로 바뀌고 창도 그 크기로 줄어 작은 말풍선이 번쩍인다.
    func dismiss(animated: Bool = true) {
        guard let panel, isVisible else { return }
        isVisible = false
        guard animated else {
            panel.orderOut(nil)
            return
        }
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
        newPanel.contentView = host
        panel = newPanel
        hosting = host
        return host
    }
}

private struct ToastView: View {
    @EnvironmentObject private var appState: AppState
    let waitingStyle: ToastWaitingStyle

    var body: some View {
        content
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .paxoSurface(cornerRadius: 16)
    }

    @ViewBuilder
    private var content: some View {
        switch appState.phase {
        case .checkingAccess, .capturing, .solvingAnswer:
            ToastWaitingView(style: waitingStyle)
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
