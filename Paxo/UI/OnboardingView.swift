import AppKit
import SwiftUI

/// 첫 실행 온보딩: 환영 → 화면 기록 권한 → 시작 안내
struct OnboardingView: View {
    let onFinish: () -> Void

    @EnvironmentObject private var appState: AppState
    @State private var step = 0
    @State private var hasScreenPermission = CGPreflightScreenCaptureAccess()

    private let totalSteps = 3

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: welcome
                case 1: permission
                default: ready
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<totalSteps, id: \.self) { index in
                        Circle()
                            .fill(index == step ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                }
                Spacer()
                if step > 0 {
                    Button("이전") { step -= 1 }
                }
                if step < totalSteps - 1 {
                    Button("다음") { step += 1 }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("시작하기") { onFinish() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(28)
        .frame(width: 440, height: 440)
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            hasScreenPermission = CGPreflightScreenCaptureAccess()
        }
    }

    // MARK: - Step 1: 환영

    private var welcome: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 84, height: 84)
            Text("Paxo에 오신 것을 환영해요")
                .font(.title2.bold())
            VStack(alignment: .leading, spacing: 10) {
                featureRow(icon: "camera.viewfinder",
                           title: "단축키 한 번으로 캡처",
                           detail: "\(appState.hotkey.display) 를 누르면 화면 속 문제를 바로 캡처해요.")
                featureRow(icon: "text.book.closed",
                           title: "정답과 해설을 함께",
                           detail: "AI가 정답과 함께 왜 그런지 풀이 과정을 설명해요.")
                featureRow(icon: "checkmark.circle",
                           title: "빠른 채점 모드",
                           detail: "문제집 셀프 채점엔 정답 먼저, 해설은 필요할 때만.")
            }
            .padding(.top, 4)
        }
    }

    private func featureRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Step 2: 화면 기록 권한

    private var permission: some View {
        VStack(spacing: 14) {
            Image(systemName: hasScreenPermission ? "checkmark.circle.fill" : "rectangle.dashed.badge.record")
                .font(.system(size: 44))
                .foregroundStyle(hasScreenPermission ? Color.green : Color.accentColor)
            Text("화면 기록 권한이 필요해요")
                .font(.title2.bold())
            Text("문제를 캡처하려면 macOS의 화면 기록 권한이 필요해요.\n캡처한 이미지는 풀이에만 사용되고 서버에 저장되지 않아요.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if hasScreenPermission {
                Label("권한이 허용되어 있어요", systemImage: "checkmark.seal.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            } else {
                VStack(spacing: 8) {
                    Button("권한 요청") {
                        CGRequestScreenCaptureAccess()
                        hasScreenPermission = CGPreflightScreenCaptureAccess()
                    }
                    .buttonStyle(.borderedProminent)
                    Button("시스템 설정 열기") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Text("권한을 켠 후에는 Paxo를 다시 실행해야 할 수 있어요.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Step 3: 시작

    private var ready: some View {
        VStack(spacing: 14) {
            Image(systemName: "menubar.arrow.up.rectangle")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("메뉴바에서 만나요")
                .font(.title2.bold())
            VStack(alignment: .leading, spacing: 10) {
                featureRow(icon: "text.viewfinder",
                           title: "Dock에는 보이지 않아요",
                           detail: "Paxo는 화면 위 메뉴바에 상주하는 앱이에요.")
                featureRow(icon: "keyboard",
                           title: "언제든 \(appState.hotkey.display)",
                           detail: "어떤 앱을 쓰고 있어도 단축키로 바로 풀이를 시작해요. 단축키는 설정에서 바꿀 수 있어요.")
                featureRow(icon: "gearshape",
                           title: "설정에서 맞춤 조정",
                           detail: "캡처 방식(영역/전체 화면), 빠른 채점 모드, 과목 프리셋을 바꿀 수 있어요.")
            }
            .padding(.top, 4)
        }
    }
}
