import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var store: StoreManager

    var body: some View {
        Form {
            Section("결과 표시") {
                Picker("표시 방식", selection: $appState.resultDisplayMode) {
                    ForEach(ResultDisplayMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Text(
                    appState.resultDisplayMode == .toast
                        ? "정답만 잠깐 떴다 사라집니다. 해설은 생성하지 않아요."
                        : "정답과 해설을 창으로 보여줍니다."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Picker("표시 위치", selection: $appState.panelPosition) {
                    ForEach(PanelPosition.allCases) { position in
                        Text(position.displayName).tag(position)
                    }
                }

                if appState.resultDisplayMode == .toast {
                    HStack {
                        Text("표시 시간")
                        Spacer()
                        Text("\(appState.toastDuration, specifier: "%.0f")초")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $appState.toastDuration, in: 2...10, step: 1)
                }
            }

            if appState.resultDisplayMode == .panel {
                Section("풀이") {
                    Toggle("빠른 채점 모드", isOn: $appState.quickCheckMode)
                    Text(
                        "문제집을 풀고 스스로 채점할 때를 위한 모드입니다. 정답을 먼저 크게 표시하고, 해설은 '해설 보기'를 눌렀을 때 생성합니다. 끄면 항상 정답과 해설이 함께 표시됩니다."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section("과목") {
                Picker("과목 프리셋", selection: $appState.preset) {
                    ForEach(SubjectPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
            }

            Section("캡처") {
                Picker("캡처 방식", selection: $appState.captureMode) {
                    ForEach(CaptureMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Text("전체 화면을 선택하면 드래그 선택 없이 단축키 즉시 현재 화면 전체를 캡처합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // 개발 빌드 전용 — 릴리즈(App Store) 빌드에서는 보이지 않고 내장 프록시로 동작
            #if DEBUG
            Section("AI 연결 (개발 빌드 전용)") {
                TextField(
                    "프록시 URL",
                    text: $appState.proxyURL,
                    prompt: Text(DefaultConfig.proxyURL)
                )
                Text("비워두면 내장 기본 프록시(DefaultConfig)를 사용합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                SecureField("Gemini API 키 (직접 호출용)", text: $appState.apiKey)
                Text("프록시가 없을 때만 사용하는 개발용 키. 키체인에 저장됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            #endif

            Section("구독") {
                if store.isPro {
                    Label("Paxo Pro 사용 중", systemImage: "checkmark.seal.fill")
                } else {
                    LabeledContent("무료 사용량", value: "하루 \(UsageTracker.dailyFreeLimit)회")
                    Button("Paxo Pro 알아보기…") {
                        appState.showPaywall()
                    }
                }
                Button("구매 복원") {
                    Task { await store.restore() }
                }
                Text("구독은 App Store 계정 설정에서 관리·해지할 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("단축키") {
                LabeledContent("화면 캡처로 풀기") {
                    HotkeyRecorderField()
                }
                if let error = appState.hotkeyError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text("⌃, ⌥, ⌘ 중 하나 이상을 포함한 조합이어야 해요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("기타") {
                Toggle("로그인 시 자동 실행", isOn: $appState.launchAtLogin)
                Button("시작 가이드 다시 보기") {
                    appState.showOnboarding()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 660)
    }
}
