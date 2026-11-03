import SwiftUI

/// 저장 실패는 풀이 오류와 구분해 결과를 계속 읽고 재시도할 수 있게 한다.
struct HistoryStorageNotice: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        if let message = appState.historyError {
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                Button("다시 시도") { appState.retryHistoryStorage() }
                    .disabled(appState.isSolving)
            }
            .accessibilityElement(children: .contain)
        }
    }
}
