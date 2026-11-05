import SwiftUI

/// 메뉴바 팝업이 별도 경고창에 초점을 빼앗겨 닫히지 않도록 같은 화면에서 확인한다.
struct HistoryDeletionConfirmation: View {
    let deletesAll: Bool
    let isBusy: Bool
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(deletesAll ? "모든 풀이 기록을 삭제할까요?" : "이 풀이 기록을 삭제할까요?")
                .font(.headline)
            Text(
                deletesAll
                    ? "검색·날짜·과목 필터와 관계없이 이 Mac의 모든 풀이 기록과 문제 이미지를 삭제합니다. 무료 플랜에서 보이지 않는 이전 기록도 포함되며 되돌릴 수 없습니다. 과목 목록은 유지됩니다."
                    : "이 Mac에 저장된 정답·해설·문제 이미지와 과목 지정이 삭제됩니다. 되돌릴 수 없습니다."
            )
            .font(.caption)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("취소", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(deletesAll ? "모든 기록 삭제" : "기록 삭제", role: .destructive, action: onDelete)
                    .disabled(isBusy)
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
    }
}
