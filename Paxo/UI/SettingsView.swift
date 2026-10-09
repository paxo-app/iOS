import SwiftUI

/// 앱 설정과 날짜별 풀이 탐색을 하나의 설정 창에서 제공한다.
struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var store: StoreManager
    @State private var recentHistoryLimitText = ""
    @FocusState private var isEditingHistoryLimit: Bool

    var body: some View {
        TabView {
            generalSettings.tabItem { Label("설정", systemImage: "gearshape") }
            HistoryArchiveView().tabItem { Label("풀이 기록", systemImage: "clock.arrow.circlepath") }
        }
        .frame(width: 460, height: 660)
        .paxoSurface(cornerRadius: 0)
        .onAppear { recentHistoryLimitText = String(appState.recentHistoryLimit) }
        .onChange(of: isEditingHistoryLimit) {
            if !isEditingHistoryLimit { saveRecentHistoryLimit() }
        }
        .onChange(of: appState.recentHistoryLimit) {
            recentHistoryLimitText = String(appState.recentHistoryLimit)
        }
    }

    private var generalSettings: some View {
        Form {
            Section("계정") {
                switch appState.authenticationPhase {
                case .signedIn:
                    Label("Apple로 로그인됨", systemImage: "person.crop.circle.badge.checkmark")
                    Button("로그아웃") {
                        appState.signOut()
                    }
                    Button("계정 삭제…", role: .destructive) {
                        showsDeleteConfirmation = true
                    }
                case .failed(let message):
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Button("로그인 다시 준비") {
                        appState.retryAppleSignInPreparation()
                    }
                case .preparing, .signingIn:
                    ProgressView("Apple 로그인을 확인하는 중…")
                case .signedOut:
                    Text("메뉴 막대의 Paxo 메뉴에서 Apple로 로그인해주세요.")
                        .foregroundStyle(.secondary)
                }
                Text("이름과 이메일은 요청하거나 저장하지 않습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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

                    Picker("기다리는 동안", selection: $appState.toastWaitingStyle) {
                        ForEach(ToastWaitingStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    Text(
                        (appState.toastWaitingStyle == .detailed
                            ? "지금 무엇을 하는지 문구로 알려줍니다."
                            : "'푸는 중…'만 보여줍니다.")
                            + " 진행 원은 기다린 시간으로 그린 표시예요. 실제 남은 시간과는 다를 수 있어요."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

            Section("최근 풀이") {
                Toggle("메뉴에 최근 풀이 표시", isOn: $appState.showsRecentHistory)
                Picker("풀이 표시", selection: $appState.historyShowsExplanation) {
                    Text("정답만 표시").tag(false)
                    Text("해설과 함께 표시").tag(true)
                }
                LabeledContent("메뉴에 표시할 풀이 수") {
                    TextField("", text: $recentHistoryLimitText)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                        .focused($isEditingHistoryLimit)
                        .onSubmit { saveRecentHistoryLimit() }
                        .onDisappear { saveRecentHistoryLimit() }
                        .accessibilityLabel("메뉴에 표시할 풀이 수")
                }
                .disabled(!appState.showsRecentHistory)
                Text("메뉴에는 최신 풀이를 설정한 개수만큼 표시합니다. 이전 풀이는 풀이 기록 탭에서 볼 수 있습니다. 정답만 표시해도 저장된 해설은 기록을 열어 볼 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    prompt: Text(DefaultConfig.developmentProxyURL)
                )
                Text("비워두면 Preview 프록시를 사용합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Gemini 직접 호출 (프록시 우회)", isOn: $appState.useDirectGemini)
                SecureField("Gemini API 키 (직접 호출용)", text: $appState.apiKey)
                Text("켜면 프록시 URL을 무시하고 이 키로 Gemini를 직접 호출합니다. 키는 키체인에 저장됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            #endif

            Section("구독") {
                if appState.serverTier == .pro {
                    Label(
                        "Paxo Pro · 오늘 \(appState.remainingToday)회 남음",
                        systemImage: "checkmark.seal.fill"
                    )
                } else {
                    LabeledContent(
                        "무료 사용량",
                        value: "오늘 \(appState.remainingToday)/\(UsagePolicy.dailyFreeLimit)회 남음"
                    )
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

            Section("지원 및 공유") {
                if let feedbackURL {
                    Link(destination: feedbackURL) {
                        Label("의견보내기", systemImage: "envelope")
                    }
                }

                if let appStoreURL = DefaultConfig.appStoreURL {
                    ShareLink(item: appStoreURL) {
                        Label("앱 공유", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button(action: {}) {
                        Label("앱 공유", systemImage: "square.and.arrow.up")
                    }
                    .disabled(true)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .tint(PaxoStyle.brand)
        .alert("Paxo 계정을 삭제할까요?", isPresented: $showsDeleteConfirmation) {
            Button("취소", role: .cancel) {}
            Button("계정 삭제", role: .destructive) {
                appState.deleteAccount()
            }
        } message: {
            Text("Apple 로그인 연결과 서버의 사용량 정보가 삭제되며 되돌릴 수 없습니다. 기기의 풀이 기록은 유지됩니다.")
        }
    }

    @State private var showsDeleteConfirmation = false

    private var feedbackURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "paxo.app.official@gmail.com"
        components.queryItems = [URLQueryItem(name: "subject", value: "Paxo 의견 보내기")]
        return components.url
    }

    private func saveRecentHistoryLimit() {
        if let count = Int(recentHistoryLimitText.trimmingCharacters(in: .whitespacesAndNewlines)) {
            appState.recentHistoryLimit = min(max(count, 1), 100)
        }
        recentHistoryLimitText = String(appState.recentHistoryLimit)
    }
}
