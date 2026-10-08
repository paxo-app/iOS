import AuthenticationServices
import SwiftUI

/// 캡처와 기록 확인을 메뉴 안에서 이어가도록 홈 화면을 구성한다.
struct MenuContentView: View {
    var keepsResultPanelVisible = false
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @AppStorage("recentHistoryExpanded") private var historyExpanded = true
    @State private var showsDetail = false

    var body: some View {
        Group {
            if showsDetail {
                ResultView(onBack: { showsDetail = false }, isHistory: true)
                    .frame(width: 360, height: 500)
            } else {
                menuContent
            }
        }
        .onAppear { appState.refreshFreeRemaining() }
    }

    private var menuContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image("PaxoMenuBar")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .foregroundStyle(.primary)
                    .accessibilityHidden(true)
                Text("Paxo").font(.title3.bold())
                Spacer()
            }
            if appState.authenticationPhase == .signedIn {
                Button {
                    dismiss()
                    appState.beginSolve()
                } label: {
                    Label("화면 캡처로 풀기", systemImage: "camera.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CaptureButtonStyle())
                .controlSize(.large)
                .disabled(appState.isSolving)

                Text("전역 단축키 \(appState.hotkey.display)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if appState.serverTier == .pro {
                    Label(
                        "Paxo Pro · 오늘 \(appState.remainingToday)회 남음",
                        systemImage: "checkmark.seal.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    HStack {
                        Text("오늘 무료 풀이 \(appState.remainingToday)회 남음")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Pro 알아보기") {
                            dismiss()
                            appState.showPaywall()
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.tint)
                    }
                }
            } else {
                if appState.authenticationPhase == .preparing
                    || appState.authenticationPhase == .signingIn
                {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Apple 로그인을 준비하는 중…")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                SignInWithAppleButton(
                    .continue,
                    onRequest: appState.configureAppleSignIn,
                    onCompletion: appState.handleAppleSignIn
                )
                .signInWithAppleButtonStyle(.black)
                .frame(height: 36)
                .disabled(!appState.isAppleSignInReady)

                if case .failed(let message) = appState.authenticationPhase {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("다시 준비") {
                        appState.retryAppleSignInPreparation()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.tint)
                }
            }

            if appState.showsRecentHistory {
                Divider()
                Button {
                    historyExpanded.toggle()
                } label: {
                    HStack {
                        Label("최근 풀이", systemImage: historyExpanded ? "chevron.down" : "chevron.right")
                        Spacer()
                        Text("\(appState.recentHistory.count)개").monospacedDigit()
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(historyExpanded ? "펼쳐짐" : "접힘")
                if historyExpanded {
                    HistoryListView(
                        items: appState.recentHistory,
                        showsExplanation: appState.historyShowsExplanation,
                        showsThumbnail: false,
                        isBusy: appState.isSolving
                    ) { item in
                        if appState.showFromHistory(item, presentPanel: false, dismissPanel: !keepsResultPanelVisible) {
                            showsDetail = true
                        }
                    }
                    .frame(
                        height: appState.recentHistory.isEmpty
                            ? 110
                            : min(
                                CGFloat(appState.recentHistory.count) * (appState.historyShowsExplanation ? 108 : 76),
                                270)
                    )
                    if appState.history.count > appState.recentHistory.count {
                        Text("전체 \(appState.history.count)개는 설정의 풀이 기록 탭에서 볼 수 있습니다.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            HStack {
                SettingsLink { Text("설정…") }
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            dismiss()
                            NSApp.activate(ignoringOtherApps: true)
                        }
                    )
                Spacer()
                Button("종료") { NSApp.terminate(nil) }
            }
            .buttonStyle(.plain)
            .font(.callout)
        }
        .padding(16)
        .frame(width: 360)
        .paxoSurface()
    }

}

private struct CaptureButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .padding(.vertical, 8)
            .foregroundStyle(.primary)
            .background(
                .primary.opacity(configuration.isPressed ? 0.2 : isHovered ? 0.16 : 0.1),
                in: Capsule()
            )
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { isHovered = $0 }
    }
}
