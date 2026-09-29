import AppKit

enum SubjectPreset: String, CaseIterable, Codable, Identifiable {
    case general
    case math
    case licenseExam

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .general: return "일반"
        case .math: return "수학"
        case .licenseExam: return "자격시험"
        }
    }

    var promptHint: String {
        switch self {
        case .general:
            return ""
        case .math:
            return "수학 문제입니다. 계산 과정을 반드시 검산한 뒤 답하세요."
        case .licenseExam:
            return "자격시험 문제입니다. 법령·규정 용어를 정확하게 사용하세요."
        }
    }
}

enum CaptureMode: String, CaseIterable, Codable, Identifiable {
    case region
    case fullScreen

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .region: return "영역 선택"
        case .fullScreen: return "전체 화면"
        }
    }
}

/// 결과 창이 화면에서 뜨는 위치
enum PanelPosition: String, CaseIterable, Codable, Identifiable {
    case topLeft, topCenter, topRight
    case center
    case bottomLeft, bottomCenter, bottomRight

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .topLeft: return "좌측 상단"
        case .topCenter: return "중앙 상단"
        case .topRight: return "우측 상단"
        case .center: return "정중앙"
        case .bottomLeft: return "좌측 하단"
        case .bottomCenter: return "중앙 하단"
        case .bottomRight: return "우측 하단"
        }
    }

    /// AppKit 좌하단 원점 기준
    func origin(for size: CGSize, on screen: NSScreen, margin: CGFloat = 16) -> NSPoint {
        let frame = screen.visibleFrame
        let x: CGFloat
        switch self {
        case .topLeft, .bottomLeft:
            x = frame.minX + margin
        case .topCenter, .center, .bottomCenter:
            x = frame.midX - size.width / 2
        case .topRight, .bottomRight:
            x = frame.maxX - size.width - margin
        }
        let y: CGFloat
        switch self {
        case .topLeft, .topCenter, .topRight:
            y = frame.maxY - size.height - margin
        case .center:
            y = frame.midY - size.height / 2
        case .bottomLeft, .bottomCenter, .bottomRight:
            y = frame.minY + margin
        }
        return NSPoint(x: x, y: y)
    }
}

enum ResultDisplayMode: String, CaseIterable, Codable, Identifiable {
    case panel
    case toast

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .panel: return "패널 (정답 + 해설)"
        case .toast: return "토스트 (정답만 잠깐)"
        }
    }
}

struct SolveResult: Identifiable, Codable, Equatable {
    var id = UUID()
    var date = Date()
    var preset: SubjectPreset
    var answer: String?
    var explanation: String?

    init(preset: SubjectPreset) {
        self.preset = preset
    }
}

/// 응답을 기다리는 동안의 안내 단계.
/// 스피너만 돌면 멈춘 것처럼 느껴져서, 기다린 시간에 맞춰 문구를 바꾸고 오래 걸리면 취소를 연다.
enum WaitingStage: CaseIterable, Equatable {
    case reading
    case thinking
    case finishing
    case slow
    case explaining

    /// 이 시간을 넘기면 오래 걸린다고 알린다
    static let slowThreshold: TimeInterval = 15

    /// 취소를 여는 시점. 캡처 직후 실수로 눌러 멀쩡한 요청을 끊는 것만 막는다.
    static let cancelThreshold: TimeInterval = 3

    /// 정답 대기. 시계가 뒤로 가서 음수가 나와도 첫 단계로 본다.
    static func answerStage(elapsed: TimeInterval) -> WaitingStage {
        switch elapsed {
        case ..<3: return .reading
        case ..<8: return .thinking
        case ..<slowThreshold: return .finishing
        default: return .slow
        }
    }

    static func explanationStage(elapsed: TimeInterval) -> WaitingStage {
        elapsed < slowThreshold ? .explaining : .slow
    }

    static func allowsCancel(elapsed: TimeInterval) -> Bool {
        elapsed >= cancelThreshold
    }

    /// 실제 진행률을 모르므로 "곧 끝난다"고 약속하는 문구는 쓰지 않는다
    var message: String {
        switch self {
        case .reading: return "문제를 읽고 있어요"
        case .thinking: return "풀이를 떠올리는 중이에요"
        case .finishing: return "답을 정리하고 있어요"
        case .slow: return "조금 오래 걸리고 있어요"
        case .explaining: return "해설을 정리하고 있어요"
        }
    }

    var detail: String? {
        self == .slow ? "복잡한 문제일수록 시간이 더 걸려요." : nil
    }

    var symbolName: String {
        switch self {
        case .reading: return "eye"
        case .thinking: return "lightbulb"
        case .finishing: return "pencil"
        case .slow: return "hourglass"
        case .explaining: return "book"
        }
    }
}

/// 토스트가 기다리는 동안 보여줄 모습
enum ToastWaitingStyle: String, CaseIterable, Codable, Identifiable {
    case detailed
    case simple

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .detailed: return "단계 안내 (기본)"
        case .simple: return "간단히"
        }
    }

    /// 저장된 값이 없거나 알 수 없으면 개선된 안내를 기본으로 쓴다
    static func restored(from rawValue: String?) -> ToastWaitingStyle {
        rawValue.flatMap(ToastWaitingStyle.init(rawValue:)) ?? .detailed
    }
}

/// 토스트의 원형 진행 표시에 쓰는 추정 진행률.
/// 서버는 답을 한 번에 보내서 실제 진행률을 알 수 없다. 기다린 시간으로 처음엔 빠르게, 점점 느리게 채우고
/// 답이 오기 전에는 가득 차지 않도록 90%에서 멈춘다.
enum WaitingProgress {
    static let ceiling = 0.9
    /// 곡선이 차오르는 속도. 측정 스크립트로 정답 응답 시간을 잰 뒤 조정한다.
    static let timeConstant: TimeInterval = 5

    static func estimatedFraction(elapsed: TimeInterval) -> Double {
        guard elapsed > 0 else { return 0 }
        return ceiling * (1 - exp(-elapsed / timeConstant))
    }
}
