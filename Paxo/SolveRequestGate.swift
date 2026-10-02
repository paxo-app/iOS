import Foundation

/// 진행 중인 AI 요청의 소유권.
///
/// 취소하거나 기록으로 화면을 바꾼 뒤에 도착한 이전 응답이 화면 · 기록 · 무료 사용량을 바꾸지 못하게 한다.
/// 모든 `await` 직후 `isCurrent`로 확인한다. 정답 확정과 취소는 MainActor에서 먼저 처리된 쪽이 이긴다.
@MainActor
final class SolveRequestGate {
    private var currentID: UUID?

    var isActive: Bool { currentID != nil }

    /// 새 요청을 시작한다. 이전 요청은 이 시점부터 무효다.
    func begin() -> UUID {
        let id = UUID()
        currentID = id
        return id
    }

    func isCurrent(_ id: UUID) -> Bool {
        currentID == id
    }

    /// 요청이 끝났을 때 부른다. 늦게 끝난 이전 작업이 새 요청을 지우지 않도록 ID가 같을 때만 비운다.
    func finish(_ id: UUID) {
        if currentID == id {
            currentID = nil
        }
    }

    /// 사용자가 취소했다. 지금 날아가는 응답은 도착해도 버려진다.
    func invalidate() {
        currentID = nil
    }
}
