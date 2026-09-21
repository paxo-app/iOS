import AppKit
import Combine
import ServiceManagement

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    enum SolvePhase: Equatable {
        case idle
        case capturing
        case solvingAnswer
        case answerReady
        case solvingExplanation
        case done
        case failedAnswer(String)  // 정답 호출 실패 — 사용량 미차감 상태
        case failedExplanation(String)  // 정답은 있음, 해설만 실패 — 사용량 이미 차감됨
    }

    @Published private(set) var phase: SolvePhase = .idle
    @Published private(set) var current: SolveResult?
    @Published private(set) var history: [SolveResult] = []

    // MARK: - 설정

    /// 빠른 채점 모드: 정답을 먼저 크게 표시하고, 해설은 "해설 보기"를 눌렀을 때 생성.
    /// 기본값 false = 항상 정답+해설 함께 표시.
    @Published var quickCheckMode: Bool {
        didSet { UserDefaults.standard.set(quickCheckMode, forKey: "quickCheckMode") }
    }
    @Published var preset: SubjectPreset {
        didSet { UserDefaults.standard.set(preset.rawValue, forKey: "preset") }
    }
    @Published var captureMode: CaptureMode {
        didSet { UserDefaults.standard.set(captureMode.rawValue, forKey: "captureMode") }
    }
    /// 결과 창 위치
    @Published var panelPosition: PanelPosition {
        didSet { UserDefaults.standard.set(panelPosition.rawValue, forKey: "panelPosition") }
    }
    /// 결과 표시 방식 (패널 / 토스트)
    @Published var resultDisplayMode: ResultDisplayMode {
        didSet { UserDefaults.standard.set(resultDisplayMode.rawValue, forKey: "resultDisplayMode") }
    }
    /// 토스트 표시 시간(초)
    @Published var toastDuration: Double {
        didSet { UserDefaults.standard.set(toastDuration, forKey: "toastDuration") }
    }
    /// 전역 단축키 (설정에서 변경 가능)
    @Published var hotkey: HotkeySpec {
        didSet {
            guard !isRevertingHotkey else { return }
            if hotkeyManager.register(hotkey) {
                hotkeyError = nil
                if let data = try? JSONEncoder().encode(hotkey) {
                    UserDefaults.standard.set(data, forKey: "hotkeySpec")
                }
            } else {
                // 시스템 예약 조합 등으로 등록 실패 → 이전 단축키로 되돌리고 재등록
                hotkeyError = "이 조합은 시스템에서 사용 중이라 등록할 수 없어요. 다른 조합을 선택해주세요."
                isRevertingHotkey = true
                hotkey = oldValue
                isRevertingHotkey = false
                hotkeyManager.register(oldValue)
            }
        }
    }
    /// 단축키 등록 실패 안내 (설정에 표시)
    @Published var hotkeyError: String?
    private var isRevertingHotkey = false

    /// 로그인 시 자동 실행 (SMAppService — MAS 허용)
    @Published var launchAtLogin: Bool {
        didSet {
            guard !isSyncingLaunchAtLogin else { return }
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // 실패 시 실제 시스템 상태로 되돌림
                isSyncingLaunchAtLogin = true
                launchAtLogin = (SMAppService.mainApp.status == .enabled)
                isSyncingLaunchAtLogin = false
            }
        }
    }
    private var isSyncingLaunchAtLogin = false
    /// 프록시 서버 URL. 직접 호출이 꺼져 있으면 이 값을 우선 사용한다.
    @Published var proxyURL: String {
        didSet { UserDefaults.standard.set(proxyURL, forKey: "proxyURL") }
    }
    /// 개발용 직접 호출 키. 키체인에만 보관한다.
    @Published var apiKey: String {
        didSet { KeychainHelper.save(key: "gemini-api-key", value: apiKey) }
    }
    #if DEBUG
    /// 프록시 장애와 Gemini API 설정을 독립적으로 확인하기 위한 개발용 선택지.
    @Published var useDirectGemini: Bool {
        didSet { UserDefaults.standard.set(useDirectGemini, forKey: "useDirectGemini") }
    }
    #endif

    /// 프록시의 사용량 집계용 익명 기기 식별자
    let deviceID: String

    /// 구독 상태 관리 (뷰에는 별도 environmentObject로 주입)
    let store = StoreManager()

    /// 오늘 남은 무료 풀이 횟수 (메뉴 표시용)
    @Published private(set) var freeRemaining: Int = UsageTracker.dailyFreeLimit

    var canRequestExplanation: Bool {
        guard let current, current.explanation == nil else { return false }
        return imageCache[current.id] != nil
    }

    private let hotkeyManager = HotkeyManager()
    private let capturer = ScreenCapturer()
    private let resultPanel = ResultPanelController()
    private let toast = ToastController()
    private let paywallWindow = PaywallWindowController()
    private let onboardingWindow = OnboardingWindowController()
    private let historyStore = HistoryStore()
    private let usage = UsageTracker()
    /// 세션 내 캡처 이미지 캐시 (SolveResult.id 키). 해설 재생성용. 디스크 저장 안 함.
    private var imageCache: [UUID: Data] = [:]
    private var imageCacheOrder: [UUID] = []
    private static let imageCacheLimit = 8
    /// 마지막으로 캡처한 화면 — 결과 패널/토스트를 같은 화면에 띄우기 위함
    private var lastCaptureScreen: NSScreen?
    private var toastDismissTask: Task<Void, Never>?

    private init() {
        quickCheckMode = UserDefaults.standard.bool(forKey: "quickCheckMode")
        preset = SubjectPreset(rawValue: UserDefaults.standard.string(forKey: "preset") ?? "") ?? .general
        captureMode = CaptureMode(rawValue: UserDefaults.standard.string(forKey: "captureMode") ?? "") ?? .region
        panelPosition =
            PanelPosition(rawValue: UserDefaults.standard.string(forKey: "panelPosition") ?? "") ?? .topRight
        resultDisplayMode =
            ResultDisplayMode(rawValue: UserDefaults.standard.string(forKey: "resultDisplayMode") ?? "") ?? .panel
        toastDuration = UserDefaults.standard.object(forKey: "toastDuration") as? Double ?? 4.0
        if let data = UserDefaults.standard.data(forKey: "hotkeySpec"),
            let spec = try? JSONDecoder().decode(HotkeySpec.self, from: data)
        {
            hotkey = spec
        } else {
            hotkey = .default
        }
        proxyURL = UserDefaults.standard.string(forKey: "proxyURL") ?? ""
        apiKey = KeychainHelper.load(key: "gemini-api-key") ?? ""
        #if DEBUG
        useDirectGemini = UserDefaults.standard.bool(forKey: "useDirectGemini")
        #endif
        launchAtLogin = (SMAppService.mainApp.status == .enabled)

        if let existing = UserDefaults.standard.string(forKey: "deviceID") {
            deviceID = existing
        } else {
            let fresh = UUID().uuidString
            UserDefaults.standard.set(fresh, forKey: "deviceID")
            deviceID = fresh
        }
    }

    func start() {
        history = historyStore.load()
        freeRemaining = usage.remainingToday()
        store.start()
        hotkeyManager.onHotkey = { [weak self] in
            self?.beginSolve()
        }
        hotkeyManager.register(hotkey)

        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            showOnboarding()
        }
    }

    func showOnboarding() {
        onboardingWindow.show(appState: self) {
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        }
    }

    /// 단축키 녹화 중 전역 단축키 일시 해제/복원
    func suspendHotkey() { hotkeyManager.unregister() }
    func resumeHotkey() { hotkeyManager.register(hotkey) }

    func beginSolve() {
        switch phase {
        case .capturing, .solvingAnswer, .solvingExplanation:
            return
        default:
            break
        }
        // 무료 한도 소진 + 미구독이면 캡처 전에 페이월 표시
        if !store.isPro && usage.remainingToday() == 0 {
            showPaywall()
            return
        }
        phase = .capturing
        Task { await runSolve() }
    }

    func showPaywall() {
        paywallWindow.show(store: store)
    }

    /// 메뉴가 열릴 때 남은 무료 횟수를 다시 계산 (자정 넘김 반영)
    func refreshFreeRemaining() {
        freeRemaining = usage.remainingToday()
    }

    func showFromHistory(_ item: SolveResult) {
        // 기록 다시 보기는 항상 패널로 (해설 확인·재생성 가능).
        // 같은 세션에 캡처 이미지가 캐시에 남아 있으면 "해설 보기"로 재생성 가능.
        toastDismissTask?.cancel()
        toast.dismiss()
        current = item
        phase = item.explanation == nil ? .answerReady : .done
        resultPanel.show(appState: self, on: Self.screenUnderMouse())
    }

    func requestExplanation() {
        Task { await runExplanation() }
    }

    private func runSolve() async {
        toastDismissTask?.cancel()
        do {
            guard let capture = try await capturer.captureInteractive(mode: captureMode) else {
                phase = .idle
                return
            }
            lastCaptureScreen = capture.screen
            let result = SolveResult(preset: preset)
            cacheImage(capture.data, for: result.id)
            current = result
            phase = .solvingAnswer
            presentSolving()

            let answer = try await makeService()
                .answer(imageData: capture.data, preset: preset)
            current?.answer = answer
            phase = .answerReady
            upsertHistory()

            // 해설은 풀이 1회에 포함 — 정답 호출 성공 시에만 무료 사용량 차감
            if !store.isPro {
                usage.recordUse()
                freeRemaining = usage.remainingToday()
            }

            if resultDisplayMode == .toast {
                toast.show(appState: self, on: lastCaptureScreen)
                scheduleToastDismiss()
            } else if !quickCheckMode {
                await runExplanation()
            }
        } catch {
            toast.dismiss()
            phase = .failedAnswer(errorMessage(from: error))
            resultPanel.show(appState: self, on: lastCaptureScreen)
        }
    }

    private func presentSolving() {
        switch resultDisplayMode {
        case .panel:
            toast.dismiss()
            resultPanel.show(appState: self, on: lastCaptureScreen)
        case .toast:
            resultPanel.hide()
            toast.show(appState: self, on: lastCaptureScreen)
        }
    }

    private func scheduleToastDismiss() {
        toastDismissTask?.cancel()
        let seconds = toastDuration
        toastDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.toast.dismiss()
            self?.phase = .idle
        }
    }

    private func runExplanation() async {
        guard let current,
            let image = imageCache[current.id],
            let answer = current.answer,
            current.explanation == nil
        else { return }
        phase = .solvingExplanation
        do {
            let explanation = try await makeService()
                .explain(imageData: image, answer: answer, preset: preset)
            self.current?.explanation = explanation
            phase = .done
            upsertHistory()
        } catch {
            phase = .failedExplanation(errorMessage(from: error))
        }
    }

    private func cacheImage(_ data: Data, for id: UUID) {
        imageCache[id] = data
        imageCacheOrder.append(id)
        while imageCacheOrder.count > Self.imageCacheLimit {
            let old = imageCacheOrder.removeFirst()
            imageCache[old] = nil
        }
    }

    static func screenUnderMouse() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(location) }
    }

    private func makeService() -> GeminiService {
        #if DEBUG
        GeminiService(
            apiKey: apiKey,
            proxyURL: proxyURL,
            deviceID: deviceID,
            useDirectGemini: useDirectGemini
        )
        #else
        GeminiService(apiKey: apiKey, proxyURL: proxyURL, deviceID: deviceID, useDirectGemini: false)
        #endif
    }

    private func upsertHistory() {
        guard let current else { return }
        if let index = history.firstIndex(where: { $0.id == current.id }) {
            history[index] = current
        } else {
            history.insert(current, at: 0)
        }
        if history.count > 100 {
            history = Array(history.prefix(100))
        }
        historyStore.save(history)
    }

    private func errorMessage(from error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
