import AppKit
import Testing

@testable import Paxo

/// `PanelPosition.origin`은 AppKit 좌하단 원점을 가정한다.
/// 다중 모니터에서 창이 엉뚱한 곳에 뜨는 회귀를 막기 위한 테스트다.
@MainActor
struct PanelPositionTests {
    private let size = CGSize(width: 400, height: 300)
    private let margin: CGFloat = 16

    /// 주 화면이 없는 환경에서는 검증을 건너뛴다 (헤드리스 CI 대비).
    private var screen: NSScreen? { NSScreen.main }

    @Test func 좌측_위치는_왼쪽_여백에_붙는다() throws {
        let screen = try #require(screen)
        let frame = screen.visibleFrame
        for position in [PanelPosition.topLeft, .bottomLeft] {
            let origin = position.origin(for: size, on: screen, margin: margin)
            #expect(origin.x == frame.minX + margin)
        }
    }

    @Test func 우측_위치는_오른쪽_여백에_붙는다() throws {
        let screen = try #require(screen)
        let frame = screen.visibleFrame
        for position in [PanelPosition.topRight, .bottomRight] {
            let origin = position.origin(for: size, on: screen, margin: margin)
            #expect(origin.x == frame.maxX - size.width - margin)
        }
    }

    @Test func 중앙_위치는_가로_중심에_놓인다() throws {
        let screen = try #require(screen)
        let frame = screen.visibleFrame
        for position in [PanelPosition.topCenter, .center, .bottomCenter] {
            let origin = position.origin(for: size, on: screen, margin: margin)
            #expect(origin.x == frame.midX - size.width / 2)
        }
    }

    /// 상단은 y가 크고 하단은 y가 작다 — 좌표계를 뒤집으면 이 테스트가 깨진다.
    @Test func 상단이_하단보다_y가_크다() throws {
        let screen = try #require(screen)
        let top = PanelPosition.topCenter.origin(for: size, on: screen, margin: margin)
        let bottom = PanelPosition.bottomCenter.origin(for: size, on: screen, margin: margin)
        #expect(top.y > bottom.y)
    }

    @Test func 모든_위치가_화면_안에_들어온다() throws {
        let screen = try #require(screen)
        let frame = screen.visibleFrame
        for position in PanelPosition.allCases {
            let origin = position.origin(for: size, on: screen, margin: margin)
            #expect(origin.x >= frame.minX, "\(position) 가 왼쪽으로 벗어남")
            #expect(origin.y >= frame.minY, "\(position) 가 아래로 벗어남")
            #expect(origin.x + size.width <= frame.maxX, "\(position) 가 오른쪽으로 벗어남")
            #expect(origin.y + size.height <= frame.maxY, "\(position) 가 위로 벗어남")
        }
    }

    @Test func 일곱_가지_위치가_모두_정의돼_있다() {
        #expect(PanelPosition.allCases.count == 7)
    }
}
