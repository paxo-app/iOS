import AppKit
import AuthenticationServices
import Combine
import ImageIO
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
    /// 지금 기다리는 요청이 시작된 시각. 대기 화면이 경과 시간으로 안내 단계를 고른다.
    @Published private(set) var waitingSince: Date?

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
    @Published var resultFontSize: ResultFontSize {
        didSet { UserDefaults.standard.set(resultFontSize.rawValue, forKey: "resultFontSize") }
    }
    /// 토스트 표시 시간(초)
    @Published var toastDuration: Double {
        didSet { UserDefaults.standard.set(toastDuration, forKey: "toastDuration") }
    }
    /// 토스트가 기다리는 동안의 모습 (단계 안내 / 간단히)
    @Published var toastWaitingStyle: ToastWaitingStyle {
        didSet { UserDefaults.standard.set(toastWaitingStyle.rawValue, forKey: "toastWaitingStyle") }
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

    /// 대기 화면에 보여줄 캡처 미리보기. 결과 ID로 찾으므로 기록을 바꾸면 따라 바뀐다.
    var currentThumbnail: NSImage? {
        current.flatMap { thumbnailCache[$0.id] }
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
    private var thumbnailCache: [UUID: NSImage] = [:]
    private var imageCacheOrder: [UUID] = []
    private let requestGate = SolveRequestGate()
    private var activeTask: Task<Void, Never>?
    /// 해설 요청이 날아가 있는 풀이와 그 시작 시각. 서버는 같은 해설을 두 번 만들지 않으므로
    /// 기다리기를 취소한 뒤 "해설 보기"를 누르면 새로 요청하지 않고 이 요청을 이어서 기다린다.
    private var pendingExplanationStarts: [UUID: Date] = [:]
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
        resultFontSize = ResultFontSize.restored(from: UserDefaults.standard.string(forKey: "resultFontSize"))
        toastDuration = UserDefaults.standard.object(forKey: "toastDuration") as? Double ?? 4.0
        toastWaitingStyle = ToastWaitingStyle.restored(from: UserDefaults.standard.string(forKey: "toastWaitingStyle"))
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
        activeTask = Task { await prepareAndRunSolve() }
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
        // 페이드하는 동안 토스트 내용이 방금 연 기록의 답으로 바뀌어 보이지 않게 바로 닫는다
        toast.dismiss(animated: false)
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
        if let current, let startedAt = pendingExplanationStarts[current.id] {
            waitingSince = startedAt
            phase = .solvingExplanation
            return
        }
        // 이미 날아가는 요청이 있으면 연타를 무시한다
        guard !requestGate.isActive else { return }
        let requestID = requestGate.begin()
        activeTask = Task { await runExplanation(requestID: requestID) }
    }

    /// 대기 중인 요청을 취소한다.
    /// 정답 대기 중이면 풀이 자체를 접고 늦게 온 응답은 버린다.
    /// 무료 횟수는 서버가 세므로, 서버가 이미 받은 요청을 끝까지 처리하면 차감될 수 있다.
    /// 해설 대기 중이면 요청은 끊지 않고 기다리기만 멈춘다. 서버는 해설을 끝까지 만들고 다시 만들어주지 않으므로,
    /// 도착한 해설은 그 기록에 남긴다.
    func cancelSolve() {
        switch phase {
        case .solvingAnswer:
            guard requestGate.isActive else { return }
            requestGate.invalidate()
            activeTask?.cancel()
            activeTask = nil
            waitingSince = nil
            phase = .idle
            resultPanel.hide()
            toast.dismiss(animated: false)
        case .solvingExplanation:
            requestGate.invalidate()
            waitingSince = nil
            phase = .answerReady
        default:
            break
        }
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
        // 작은 정답 토스트가 남은 채 넓은 대기 화면으로 바뀌면 잘린다. 대기 토스트는 요청 시작 때 새 크기로 다시 뜬다.
        toast.dismiss(animated: false)
        // 영역을 고르는 동안 기록으로 화면을 바꿀 수 있으므로 소유권은 캡처 전부터 잡는다
        let requestID = requestGate.begin()
        let capture: ScreenCapturer.Capture
        do {
            let captured = try await capturer.captureInteractive(mode: captureMode)
            guard requestGate.isCurrent(requestID) else { return }
            guard let captured else {
                requestGate.finish(requestID)
                phase = .idle
                return
            }
            capture = captured
        } catch {
            guard requestGate.isCurrent(requestID) else { return }
            requestGate.finish(requestID)
            toast.dismiss(animated: false)
            phase = .failedAnswer(errorMessage(from: error))
            resultPanel.show(appState: self, on: lastCaptureScreen)
            return
        }

        lastCaptureScreen = capture.screen
        let result = SolveResult(preset: preset)
        cacheImage(capture.data, for: result.id)
        current = result
        waitingSince = Date()
        phase = .solvingAnswer
        presentSolving()

        do {
            let generated = try await requestAnswer(
                imageData: capture.data,
                preset: result.preset,
                solveID: result.id
            )
            // 남은 횟수는 서버 정본이므로 취소와 상관없이 반영한다
            apply(generated)
            // 취소가 먼저 처리됐으면 응답을 버린다
            guard requestGate.isCurrent(requestID) else { return }
            waitingSince = nil
            current?.answer = generated.text
            current?.answerContext = generated.answerContext
            if let id = current?.id {
                current?.imageFileName = historyStore.saveImage(capture.data, for: id)
            }
            phase = .answerReady
            upsertHistory()

            if resultDisplayMode == .toast {
                requestGate.finish(requestID)
                toast.show(appState: self, on: lastCaptureScreen)
                scheduleToastDismiss()
            } else if !quickCheckMode {
                await runExplanation(requestID: requestID)
            } else {
                requestGate.finish(requestID)
            }
        } catch GeminiError.freeDailyLimit {
            guard requestGate.isCurrent(requestID) else { return }
            requestGate.finish(requestID)
            waitingSince = nil
            toast.dismiss(animated: false)
            remainingToday = 0
            phase = .idle
            showPaywall()
        } catch GeminiError.proDailyLimit {
            guard requestGate.isCurrent(requestID) else { return }
            requestGate.finish(requestID)
            waitingSince = nil
            toast.dismiss(animated: false)
            remainingToday = 0
            phase = .failedAnswer("Pro의 일일 안전 한도 100회를 모두 사용했습니다. 내일 다시 이용해주세요.")
            resultPanel.show(appState: self, on: lastCaptureScreen)
        } catch {
            guard requestGate.isCurrent(requestID) else { return }
            requestGate.finish(requestID)
            waitingSince = nil
            toast.dismiss(animated: false)
            if error is CancellationError {
                phase = .idle
                resultPanel.hide()
                return
            }
            phase = .failedAnswer(errorMessage(from: error))
            resultPanel.show(appState: self, on: lastCaptureScreen)
        }
    }

    private func presentSolving() {
        switch resultDisplayMode {
        case .panel:
            toast.dismiss(animated: false)
            resultPanel.show(appState: self, on: lastCaptureScreen)
        case .toast:
            resultPanel.hide()
            toast.show(appState: self, on: lastCaptureScreen)
        }
    }

    private func scheduleToastDismiss() {
        toastDismissTask?.cancel()
        let seconds = toastDuration
        let resultID = current?.id
        toastDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            // 그 사이 새 풀이가 시작됐으면 오래된 타이머가 새 화면을 지우지 않게 한다
            guard !Task.isCancelled, let self, self.current?.id == resultID else { return }
            self.toast.dismiss()
            self.phase = .idle
        }
    }

    private func runExplanation(requestID: UUID) async {
        // 예약만 되고 실행 전에 취소된 작업이 새 화면을 건드리지 않게 한다
        guard requestGate.isCurrent(requestID), !Task.isCancelled else { return }
        guard let current,
            let image = imageCache[current.id],
            let answer = current.answer,
            current.explanation == nil
        else {
            requestGate.finish(requestID)
            return
        }
        let solveID = current.id
        let startedAt = Date()
        pendingExplanationStarts[solveID] = startedAt
        waitingSince = startedAt
        phase = .solvingExplanation
        do {
            let generated = try await requestExplanation(
                imageData: image,
                answer: answer,
                context: current.answerContext,
                preset: current.preset,
                solveID: solveID
            )
            pendingExplanationStarts[solveID] = nil
            requestGate.finish(requestID)
            apply(generated)
            saveExplanation(generated.text, for: solveID)
        } catch {
            pendingExplanationStarts[solveID] = nil
            requestGate.finish(requestID)
            // 기다리기를 취소했다면 실패를 띄우지 않는다. "해설 보기"로 새로 요청할 수 있다
            guard self.current?.id == solveID, phase == .solvingExplanation else { return }
            waitingSince = nil
            phase = error is CancellationError ? .answerReady : .failedExplanation(errorMessage(from: error))
        }
    }

    /// 해설을 그 풀이 기록에 남긴다. 지금 보고 있는 풀이면 화면에도 바로 보인다.
    private func saveExplanation(_ text: String, for solveID: UUID) {
        guard current?.id == solveID else {
            guard let index = history.firstIndex(where: { $0.id == solveID }) else { return }
            history[index].explanation = text
            historyStore.save(history)
            return
        }
        current?.explanation = text
        if phase == .solvingExplanation {
            waitingSince = nil
        }
        if phase == .solvingExplanation || phase == .answerReady {
            phase = .done
        }
        upsertHistory()
    }

    private func cacheImage(_ data: Data, for id: UUID) {
        imageCache[id] = data
        thumbnailCache[id] = Self.makeThumbnail(from: data)
        imageCacheOrder.append(id)
        while imageCacheOrder.count > Self.imageCacheLimit {
            let old = imageCacheOrder.removeFirst()
            imageCache[old] = nil
            thumbnailCache[old] = nil
        }
    }

    /// 대기 화면용 작은 미리보기. 원본(최대 2000px)을 그대로 쥐면 캐시 8장이 메모리를 크게 먹는다.
    private static func makeThumbnail(from data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 240,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
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
        context: AnswerContext?,
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
                solveID: solveID,
                answerContext: context
            )
        }
        #endif
        return try await sessionManager.withSessionRetry { session in
            try await service.explain(
                imageData: imageData,
                answer: answer,
                preset: preset,
                sessionToken: session.sessionToken,
                solveID: solveID,
                answerContext: context
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
