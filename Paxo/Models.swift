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

    /// 주어진 크기의 창을 이 위치에 놓기 위한 원점(AppKit 좌하단 원점 기준)
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

/// 결과를 어떻게 보여줄지
enum ResultDisplayMode: String, CaseIterable, Codable, Identifiable {
    case panel  // 정답 + 해설 패널 (기본)
    case toast  // 정답만 잠깐 떴다 사라지는 토스트

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
