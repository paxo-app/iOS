import Foundation
import Testing

@testable import Paxo

/// 히스토리는 JSON으로 디스크에 남는다. 필드 이름이나 타입이 바뀌면
/// 기존 사용자의 기록이 조용히 사라진다.
struct CodableRoundTripTests {
    @Test func solveResult가_왕복해도_동일하다() throws {
        var original = SolveResult(preset: .math)
        original.answer = "③"
        original.explanation = "**핵심 개념**\n- 첫째\n- 둘째"

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SolveResult.self, from: data)

        #expect(decoded == original)
        #expect(decoded.id == original.id)
        #expect(decoded.answer == "③")
    }

    /// 정답만 있고 해설이 없는 상태는 정상적인 중간 상태다 (빠른 채점·토스트 모드).
    @Test func 해설이_없는_기록도_왕복한다() throws {
        var original = SolveResult(preset: .licenseExam)
        original.answer = "가나다"

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SolveResult.self, from: data)

        #expect(decoded == original)
        #expect(decoded.explanation == nil)
    }

    @Test func 기록_배열이_왕복한다() throws {
        let items = SubjectPreset.allCases.map { SolveResult(preset: $0) }
        let data = try JSONEncoder().encode(items)
        let decoded = try JSONDecoder().decode([SolveResult].self, from: data)
        #expect(decoded == items)
    }

    @Test func hotkeySpec이_왕복해도_동일하다() throws {
        let original = HotkeySpec.default
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotkeySpec.self, from: data)

        #expect(decoded == original)
        #expect(decoded.display == "⌥⌘S")
    }

    /// rawValue가 바뀌면 저장된 설정을 못 읽는다.
    @Test func 설정_열거형의_rawValue가_고정돼_있다() {
        #expect(SubjectPreset.general.rawValue == "general")
        #expect(CaptureMode.region.rawValue == "region")
        #expect(ResultDisplayMode.panel.rawValue == "panel")
        #expect(PanelPosition.topRight.rawValue == "topRight")
    }
}
