import AppKit
import SwiftUI

/// 정답을 기다리는 동안 결과 패널에 보여주는 화면.
/// 무엇을 캡처했는지 먼저 보여주고, 기다린 시간에 맞춰 안내 문구를 바꾼다.
struct AnswerWaitingView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let thumbnail = appState.currentThumbnail {
                CaptureThumbnailCard(image: thumbnail, preset: appState.current?.preset ?? appState.preset)
            }
            WaitingTimeline(since: appState.waitingSince, stage: WaitingStage.answerStage) { stage in
                WaitingStageRow(stage: stage)
            }
        }
    }
}

/// 정답은 이미 보이고 해설만 기다릴 때. 해설이 들어설 자리를 미리 잡아 두어 화면이 튀지 않게 한다.
struct ExplanationWaitingView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        WaitingTimeline(since: appState.waitingSince, stage: WaitingStage.explanationStage) { stage in
            VStack(alignment: .leading, spacing: 10) {
                WaitingStageRow(stage: stage)
                VStack(alignment: .leading, spacing: 7) {
                    skeletonLine(width: 290)
                    skeletonLine(width: 240)
                    skeletonLine(width: 265)
                }
                .opacity(dimmed ? 0.45 : 1)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                dimmed = true
            }
        }
    }

    private func skeletonLine(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(.quaternary)
            .frame(maxWidth: width, minHeight: 9, maxHeight: 9)
    }
}

/// 토스트용 한 줄 대기 표시.
/// 토스트는 뜰 때 한 번만 크기를 재므로, 가장 긴 단계(문구 + 취소 버튼)가 들어가는 고정 폭을 쓴다.
struct ToastWaitingView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        WaitingTimeline(since: appState.waitingSince, stage: WaitingStage.answerStage) { stage in
            WaitingStageRow(stage: stage, compact: true)
        }
        .frame(width: 320, alignment: .leading)
    }
}

/// 단계 아이콘 · 문구 · (오래 걸리면) 취소 버튼
struct WaitingStageRow: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let stage: WaitingStage
    var compact = false

    var body: some View {
        Group {
            if compact {
                HStack(spacing: 10) {
                    icon.font(.title3)
                    Text(stage.message)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if stage.allowsCancel { cancelButton }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        icon.font(.title2)
                        Text(stage.message)
                            .font(.callout.weight(.medium))
                    }
                    if let detail = stage.detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if stage.allowsCancel { cancelButton }
                }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: stage)
    }

    private var icon: some View {
        Image(systemName: stage.symbolName)
            .foregroundStyle(.tint)
            .symbolEffect(.pulse, isActive: !reduceMotion)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 28)
    }

    private var cancelButton: some View {
        Button("취소") {
            appState.cancelSolve()
        }
        .controlSize(.small)
    }
}

/// 1초마다 경과 시간을 다시 계산해 단계를 넘긴다. 틱 수가 아니라 시작 시각 기준이라 갱신이 밀려도 어긋나지 않는다.
private struct WaitingTimeline<Content: View>: View {
    let since: Date?
    let stage: (TimeInterval) -> WaitingStage
    @ViewBuilder let content: (WaitingStage) -> Content

    var body: some View {
        TimelineView(.periodic(from: since ?? .now, by: 1)) { context in
            content(stage(context.date.timeIntervalSince(since ?? context.date)))
        }
    }
}

/// "이 문제를 보고 있어요"를 눈으로 확인시켜 주는 캡처 미리보기
private struct CaptureThumbnailCard: View {
    let image: NSImage
    let preset: SubjectPreset

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 72, maxHeight: 48)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 2) {
                Text("캡처한 문제")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(preset.displayName) · 방금")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 0.5)
        )
    }
}
