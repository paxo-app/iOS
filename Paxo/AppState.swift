import AppKit
import AuthenticationServices
import Combine
import ServiceManagement

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    enum SolvePhase: Equatable {
        case idle
        case checkingAccess
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

    enum AuthenticationPhase: Equatable {
        case preparing
        case signedOut
        case signingIn
        case signedIn
        case failed(String)
    }

    @Published private(set) var authenticationPhase: AuthenticationPhase = .preparing
    @Published private(set) var isAppleSignInReady = false
    @Published private(set) var remainingToday = 0
    @Published private(set) var serverTier: ProxyTier = .free
    @Published private(set) var usageResetAt: Date?

    // MARK: - 설정

    /// 빠른 채점 모드: 정답을 먼저 크게 표시하고, 해설은 "해설 보기"를 눌렀을 때 생성.
    /// 기본값 false = 항상 정답+해설 함께 표시.
    @Published var quickCheckMode: Bool {
        didSet { UserDefaults.standard.set(quickCheckMode, forKey: "quickCheckMode") }
    }
    @Published var showsRecentHistory: Bool {
        didSet { UserDefaults.standard.set(showsRecentHistory, forKey: "showsRecentHistory") }
    }
    @Published var historyShowsExplanation: Bool {
        didSet { UserDefaults.standard.set(historyShowsExplanation, forKey: "historyShowsExplanation") }
    }
    @Published var recentHistoryLimit: Int {
        didSet { UserDefaults.standard.set(recentHistoryLimit, forKey: "recentHistoryLimit") }
    }

    var recentHistory: [SolveResult] {
        Array(history.prefix(min(max(recentHistoryLimit, 1), 100)))
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
    #if DEBUG
    /// 개발 빌드에서만 프록시 계약을 독립적으로 검증한다.
    @Published var proxyURL: String {
        didSet { UserDefaults.standard.set(proxyURL, forKey: "proxyURL") }
    }
    /// 개발용 직접 호출 키. 키체인에만 보관한다.
    @Published var apiKey: String {
        didSet { KeychainHelper.save(key: "gemini-api-key", value: apiKey) }
    }
    @Published var useDirectGemini: Bool {
        didSet { UserDefaults.standard.set(useDirectGemini, forKey: "useDirectGemini") }
    }
    #endif

    /// 구독 상태 관리 (뷰에는 별도 environmentObject로 주입)
    let store = StoreManager()

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
    private let sessionManager = ProxySessionManager()
    /// 메모리 사용을 제한하고 오래된 문제 이미지는 필요할 때 로컬 기록에서 다시 읽는다.
    private var imageCache: [UUID: Data] = [:]
    private var imageCacheOrder: [UUID] = []
    private static let imageCacheLimit = 8
    /// 마지막으로 캡처한 화면 — 결과 패널/토스트를 같은 화면에 띄우기 위함
    private var lastCaptureScreen: NSScreen?
    private var toastDismissTask: Task<Void, Never>?
    private var credentialRevocationTask: Task<Void, Never>?
    private static let appleUserKey = "apple-user-identifier"

    private init() {
        quickCheckMode = UserDefaults.standard.bool(forKey: "quickCheckMode")
        showsRecentHistory = UserDefaults.standard.object(forKey: "showsRecentHistory") as? Bool ?? true
        historyShowsExplanation = UserDefaults.standard.object(forKey: "historyShowsExplanation") as? Bool ?? true
        recentHistoryLimit = min(max(UserDefaults.standard.object(forKey: "recentHistoryLimit") as? Int ?? 5, 1), 100)
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
        #if DEBUG
        proxyURL =
            UserDefaults.standard.string(forKey: "proxyURL") ?? DefaultConfig.developmentProxyURL
        apiKey = KeychainHelper.load(key: "gemini-api-key") ?? ""
        useDirectGemini = UserDefaults.standard.bool(forKey: "useDirectGemini")
        #endif
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    func start() {
        history = historyStore.load()
        #if DEBUG
        sessionManager.developmentProxyURL = proxyURL
        #endif
        store.onEntitlementsChanged = { [weak self] in
            await self?.refreshServerEntitlements()
        }
        store.start()
        hotkeyManager.onHotkey = { [weak self] in
            self?.beginSolve()
        }
        hotkeyManager.register(hotkey)
        credentialRevocationTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: ASAuthorizationAppleIDProvider.credentialRevokedNotification
            ) {
                await self?.handleCredentialRevocation()
            }
        }
        Task { await restoreAuthentication() }

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

    func configureAppleSignIn(_ request: ASAuthorizationAppleIDRequest) {
        guard let nonce = sessionManager.pendingNonce else {
            authenticationPhase = .failed("로그인 준비가 완료되지 않았습니다. 잠시 후 다시 시도해주세요.")
            return
        }
        request.requestedScopes = []
        request.nonce = ProxySessionManager.nonceDigest(nonce)
        authenticationPhase = .signingIn
    }

    func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        Task { await completeAppleSignIn(result) }
    }

    func retryAppleSignInPreparation() {
        Task {
            if KeychainHelper.load(key: Self.appleUserKey)?.isEmpty == false {
                await restoreAuthentication()
            } else {
                await prepareAppleSignIn()
            }
        }
    }

    func signOut() {
        Task {
            await sessionManager.logout()
            KeychainHelper.save(key: Self.appleUserKey, value: "")
            resetAuthentication()
            await prepareAppleSignIn()
        }
    }

    func deleteAccount() {
        Task {
            do {
                try await sessionManager.deleteAccount()
                KeychainHelper.save(key: Self.appleUserKey, value: "")
                resetAuthentication()
                await prepareAppleSignIn()
            } catch {
                authenticationPhase = .failed(errorMessage(from: error))
            }
        }
    }

    func beginSolve() {
        switch phase {
        case .checkingAccess, .capturing, .solvingAnswer, .solvingExplanation:
            return
        default:
            break
        }
        Task { await prepareAndRunSolve() }
    }

    func showPaywall() {
        paywallWindow.show(store: store)
        Task { await store.reloadProductsIfNeeded() }
    }

    /// 메뉴가 열릴 때 서버 정본을 새로 읽어 자정 초기화와 구독 변경을 반영한다.
    func refreshFreeRemaining() {
        Task {
            guard case .signedIn = authenticationPhase else { return }
            if let session = try? await sessionManager.session(forceRefresh: true) {
                apply(session)
            }
        }
    }

    /// 패널 안의 홈에서 기록을 열 때는 현재 창을 닫지 않고 상세 화면으로 전환한다.
    @discardableResult
    func showFromHistory(_ item: SolveResult, presentPanel: Bool = true, dismissPanel: Bool = true) -> Bool {
        guard !isSolving else { return false }
        toastDismissTask?.cancel()
        toast.dismiss()
        if imageCache[item.id] == nil, let image = historyStore.loadImage(for: item), NSImage(data: image) != nil {
            cacheImage(image, for: item.id)
        }
        current = item
        phase = item.explanation == nil ? .answerReady : .done
        if presentPanel {
            resultPanel.show(appState: self, on: Self.screenUnderMouse())
        } else if dismissPanel {
            resultPanel.hide()
        }
        return true
    }

    var isSolving: Bool {
        switch phase {
        case .checkingAccess, .capturing, .solvingAnswer, .solvingExplanation: return true
        default: return false
        }
    }

    func historyImage(for item: SolveResult) -> NSImage? {
        guard let data = imageCache[item.id] ?? historyStore.loadImage(for: item) else { return nil }
        return NSImage(data: data)
    }

    func updateCorrectness(_ correctness: SolveCorrectness) {
        guard let result = current, result.answer != nil else { return }
        current?.correctness = result.correctness == correctness ? nil : correctness
        upsertHistory()
    }

    func requestExplanation() {
        Task { await runExplanation() }
    }

    private func restoreAuthentication() async {
        authenticationPhase = .preparing
        guard let userID = KeychainHelper.load(key: Self.appleUserKey), !userID.isEmpty else {
            sessionManager.clearCredentials()
            await prepareAppleSignIn()
            return
        }
        guard let state = await credentialState(for: userID) else {
            authenticationPhase = .failed(
                "Apple 로그인 상태를 확인하지 못했습니다. 네트워크 상태를 확인하고 다시 시도해주세요."
            )
            return
        }
        guard state == .authorized else {
            sessionManager.clearCredentials()
            KeychainHelper.save(key: Self.appleUserKey, value: "")
            await prepareAppleSignIn()
            return
        }
        do {
            let session = try await sessionManager.session(forceRefresh: true)
            apply(session)
            authenticationPhase = .signedIn
        } catch {
            authenticationPhase = .failed(errorMessage(from: error))
            if let sessionError = error as? ProxySessionError,
                case .signInRequired = sessionError
            {
                sessionManager.clearCredentials()
                KeychainHelper.save(key: Self.appleUserKey, value: "")
                await prepareAppleSignIn(preserveError: true)
            }
        }
    }

    private func prepareAppleSignIn(preserveError: Bool = false) async {
        if !preserveError { authenticationPhase = .preparing }
        isAppleSignInReady = false
        do {
            _ = try await sessionManager.prepareChallenge()
            isAppleSignInReady = true
            if !preserveError { authenticationPhase = .signedOut }
        } catch {
            authenticationPhase = .failed(errorMessage(from: error))
        }
    }

    private func completeAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        do {
            let authorization = try result.get()
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let identityData = credential.identityToken,
                let identityToken = String(data: identityData, encoding: .utf8),
                let codeData = credential.authorizationCode,
                let authorizationCode = String(data: codeData, encoding: .utf8)
            else {
                throw ProxySessionError.appleVerificationFailed
            }
            let session = try await sessionManager.signIn(
                identityToken: identityToken,
                authorizationCode: authorizationCode
            )
            KeychainHelper.save(key: Self.appleUserKey, value: credential.user)
            apply(session)
            authenticationPhase = .signedIn
            isAppleSignInReady = false
        } catch let error as ASAuthorizationError where error.code == .canceled {
            authenticationPhase = .signedOut
            await prepareAppleSignIn()
        } catch {
            authenticationPhase = .failed(errorMessage(from: error))
            await prepareAppleSignIn(preserveError: true)
        }
    }

    private func credentialState(
        for userID: String
    ) async -> ASAuthorizationAppleIDProvider.CredentialState? {
        await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { state, error in
                continuation.resume(returning: error == nil ? state : nil)
            }
        }
    }

    private func handleCredentialRevocation() async {
        await sessionManager.logout()
        KeychainHelper.save(key: Self.appleUserKey, value: "")
        resetAuthentication()
        await prepareAppleSignIn()
    }

    private func refreshServerEntitlements() async {
        guard case .signedIn = authenticationPhase else { return }
        do {
            let session = try await sessionManager.session(forceRefresh: true)
            apply(session)
        } catch {
            authenticationPhase = .failed(errorMessage(from: error))
        }
    }

    private func resetAuthentication() {
        authenticationPhase = .signedOut
        remainingToday = 0
        serverTier = .free
        usageResetAt = nil
    }

    private func apply(_ session: ProxySession) {
        remainingToday = session.remainingToday
        serverTier = session.tier
        usageResetAt = session.resetAt
    }

    private func apply(_ result: GenerationResult) {
        if let remaining = result.remainingToday { remainingToday = remaining }
        if let resetAt = result.resetAt { usageResetAt = resetAt }
        if let tier = result.tier { serverTier = tier }
    }

    private func prepareAndRunSolve() async {
        #if DEBUG
        if useDirectGemini {
            phase = .capturing
            await runSolve()
            return
        }
        #endif
        guard case .signedIn = authenticationPhase else {
            authenticationPhase = .failed("Paxo를 사용하려면 Apple로 로그인해주세요.")
            await prepareAppleSignIn(preserveError: true)
            return
        }
        phase = .checkingAccess
        do {
            let session = try await sessionManager.session(forceRefresh: true)
            apply(session)
            guard session.remainingToday > 0 else {
                phase = .idle
                if session.tier == .free {
                    showPaywall()
                } else {
                    phase = .failedAnswer("Pro의 일일 안전 한도 100회를 모두 사용했습니다. 내일 다시 이용해주세요.")
                    resultPanel.show(appState: self, on: Self.screenUnderMouse())
                }
                return
            }
            phase = .capturing
            await runSolve()
        } catch {
            phase = .idle
            authenticationPhase = .failed(errorMessage(from: error))
            if case ProxySessionError.signInRequired = error {
                await prepareAppleSignIn(preserveError: true)
            }
        }
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

            let generated = try await requestAnswer(
                imageData: capture.data,
                preset: preset,
                solveID: result.id
            )
            apply(generated)
            current?.answer = generated.text
            if let id = current?.id {
                current?.imageFileName = historyStore.saveImage(capture.data, for: id)
            }
            phase = .answerReady
            upsertHistory()

            if resultDisplayMode == .toast {
                toast.show(appState: self, on: lastCaptureScreen)
                scheduleToastDismiss()
            } else if !quickCheckMode {
                await runExplanation()
            }
        } catch GeminiError.freeDailyLimit {
            toast.dismiss()
            remainingToday = 0
            phase = .idle
            showPaywall()
        } catch GeminiError.proDailyLimit {
            toast.dismiss()
            remainingToday = 0
            phase = .failedAnswer("Pro의 일일 안전 한도 100회를 모두 사용했습니다. 내일 다시 이용해주세요.")
            resultPanel.show(appState: self, on: lastCaptureScreen)
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
            let generated = try await requestExplanation(
                imageData: image,
                answer: answer,
                preset: preset,
                solveID: current.id
            )
            apply(generated)
            self.current?.explanation = generated.text
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
            useDirectGemini: useDirectGemini
        )
        #else
        GeminiService(apiKey: "", proxyURL: DefaultConfig.proxyURL, useDirectGemini: false)
        #endif
    }

    private func requestAnswer(
        imageData: Data,
        preset: SubjectPreset,
        solveID: UUID
    ) async throws -> GenerationResult {
        let service = makeService()
        #if DEBUG
        if useDirectGemini {
            return try await service.answer(
                imageData: imageData,
                preset: preset,
                sessionToken: "development-direct-call",
                solveID: solveID
            )
        }
        #endif
        return try await sessionManager.withSessionRetry { session in
            try await service.answer(
                imageData: imageData,
                preset: preset,
                sessionToken: session.sessionToken,
                solveID: solveID
            )
        }
    }

    private func requestExplanation(
        imageData: Data,
        answer: String,
        preset: SubjectPreset,
        solveID: UUID
    ) async throws -> GenerationResult {
        let service = makeService()
        #if DEBUG
        if useDirectGemini {
            return try await service.explain(
                imageData: imageData,
                answer: answer,
                preset: preset,
                sessionToken: "development-direct-call",
                solveID: solveID
            )
        }
        #endif
        return try await sessionManager.withSessionRetry { session in
            try await service.explain(
                imageData: imageData,
                answer: answer,
                preset: preset,
                sessionToken: session.sessionToken,
                solveID: solveID
            )
        }
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
