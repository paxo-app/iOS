import AuthenticationServices
import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "text.viewfinder")
                Text("Paxo").font(.headline)
                Spacer()
            }
            .onAppear { appState.refreshFreeRemaining() }

            if appState.authenticationPhase == .signedIn {
                Button {
                    dismiss()
                    appState.beginSolve()
                } label: {
                    Label("화면 캡처로 풀기", systemImage: "camera.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)

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

            if !appState.history.isEmpty {
                Divider()
                Text("최근 풀이")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(Array(appState.history.prefix(5))) { item in
                    Button {
                        dismiss()
                        appState.showFromHistory(item)
                    } label: {
                        HStack {
                            Text(item.answer ?? "…")
                                .lineLimit(1)
                            Spacer()
                            Text(item.date, style: .time)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()
            HStack {
                SettingsLink {
                    Text("설정…")
                }
                .simultaneousGesture(
                    TapGesture().onEnded {
                        NSApp.activate(ignoringOtherApps: true)
                    })
                Spacer()
                Button("종료") {
                    NSApp.terminate(nil)
                }
            }
            .buttonStyle(.plain)
            .font(.callout)
        }
        .padding(12)
        .frame(width: 280)
    }
}
