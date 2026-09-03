import AppKit
import SwiftUI

@MainActor
final class ToastController {
    private var panel: NSPanel?
    private var hosting: NSHostingView<AnyView>?
    private var isVisible = false

    func show(appState: AppState, on screen: NSScreen? = nil) {
        let host = ensurePanel(appState: appState)
        host.rootView = AnyView(
            ToastView().environmentObject(appState).fixedSize()
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

    func dismiss() {
        guard let panel, isVisible else { return }
        isVisible = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self, weak panel] in
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

    var body: some View {
        content
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
            )
    }

    @ViewBuilder
    private var content: some View {
        switch appState.phase {
        case .capturing, .solvingAnswer:
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
