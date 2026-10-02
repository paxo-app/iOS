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
            WaitingTimeline(since: appState.waitingSince, stage: WaitingStage.answerStage) { stage, elapsed in
                WaitingStageRow(stage: stage, showsCancel: elapsed.map(WaitingStage.allowsCancel) ?? false)
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
        WaitingTimeline(since: appState.waitingSince, stage: WaitingStage.explanationStage) { stage, elapsed in
            VStack(alignment: .leading, spacing: 10) {
                WaitingStageRow(stage: stage, showsCancel: elapsed.map(WaitingStage.allowsCancel) ?? false)
                VStack(alignment: .leading, spacing: 7) {
                    skeletonLine(width: 290)
                    skeletonLine(width: 240)
                    skeletonLine(width: 265)
                }
                .opacity(dimmed ? 0.45 : 1)
            }
        }
        .onAppear { updatePulse() }
        .onChange(of: reduceMotion) { updatePulse() }
    }

    /// 대기 도중 "동작 줄이기"를 켜도 반복 애니메이션이 바로 멈추도록, 애니메이션 없이 값을 되돌린다
    private func updatePulse() {
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) { dimmed = false }
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
            dimmed = true
        }
    }

    private func skeletonLine(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(.quaternary)
            .frame(maxWidth: width, minHeight: 9, maxHeight: 9)
    }
}

/// 토스트용 한 줄 대기 표시. 스피너 대신 기다린 시간으로 채우는 원을 쓴다.
/// 토스트는 뜰 때 한 번만 크기를 재므로, 가장 긴 문구와 취소 자리가 들어가는 고정 폭을 쓴다.
struct ToastWaitingView: View {
    @EnvironmentObject private var appState: AppState
    let style: ToastWaitingStyle

    var body: some View {
        WaitingTimeline(since: appState.waitingSince, stage: WaitingStage.answerStage) { stage, elapsed in
            let showsCancel = elapsed.map(WaitingStage.allowsCancel) ?? false
            switch style {
            case .detailed:
                HStack(spacing: 10) {
                    ProgressRing(since: appState.waitingSince, symbol: stage.symbolName, description: stage.message)
                    Text(stage.message)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    CancelSlot(visible: showsCancel, compact: false)
                }
                .frame(width: 320, alignment: .leading)
            case .simple:
                // 문구가 없으면 오래 걸릴 때 원만 멈춰 보이므로, 이때만 이유를 한 줄 알려준다
                let message = stage == .slow ? stage.message : "푸는 중…"
                HStack(spacing: 10) {
                    ProgressRing(since: appState.waitingSince, symbol: nil, description: message)
                    Text(message)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    CancelSlot(visible: showsCancel, compact: true)
                }
                .frame(width: 250, alignment: .leading)
            }
        }
    }
}

/// 단계 아이콘 · 문구 · 취소 버튼. 취소 자리는 처음부터 잡아 두어 버튼이 생겨도 화면이 튀지 않는다.
struct WaitingStageRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let stage: WaitingStage
    let showsCancel: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: stage.symbolName)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .symbolEffect(.pulse, isActive: !reduceMotion)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 28)
                Text(stage.message)
                    .font(.callout.weight(.medium))
                Spacer(minLength: 8)
                CancelSlot(visible: showsCancel, compact: false)
            }
            if let detail = stage.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: stage)
    }
}

/// 3초 전에는 자리만 차지하고 클릭 · 키보드 · VoiceOver 어느 쪽으로도 실행되지 않는 취소 버튼
private struct CancelSlot: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let visible: Bool
    let compact: Bool

    var body: some View {
        Group {
            if compact {
                Button {
                    appState.cancelSolve()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.secondary.opacity(0.15)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("풀이 취소")
                .accessibilityLabel("풀이 취소")
            } else {
                Button("취소") {
                    appState.cancelSolve()
                }
                .controlSize(.small)
            }
        }
        .opacity(visible ? 1 : 0)
        .disabled(!visible)
        .allowsHitTesting(visible)
        .accessibilityHidden(!visible)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: visible)
    }
}

/// 기다린 시간으로 채우는 원. 실제 진행률이 아니라 추정치라 90%를 넘지 않는다.
/// 원호만 자주(30Hz) 다시 그리고, 가운데 아이콘은 밖에 두어 펄스 효과가 매 프레임 다시 시작되지 않게 한다.
private struct ProgressRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let since: Date?
    let symbol: String?
    let description: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.25), lineWidth: 3)
            if reduceMotion {
                TimelineView(.periodic(from: since ?? .now, by: 1)) { context in
                    arc(at: context.date)
                }
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    arc(at: context.date)
                }
            }
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tint)
                    .symbolEffect(.pulse, isActive: !reduceMotion)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .frame(width: 26, height: 26)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("진행 중")
        .accessibilityValue(description)
    }

    @ViewBuilder
    private func arc(at date: Date) -> some View {
        let fraction = since.map { WaitingProgress.estimatedFraction(elapsed: date.timeIntervalSince($0)) } ?? 0
        if fraction > 0 {
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// 1초마다 경과 시간을 다시 계산해 단계를 넘긴다. 틱 수가 아니라 시작 시각 기준이라 갱신이 밀려도 어긋나지 않는다.
/// 요청이 시작되기 전(영역 선택 중)에는 경과 시간을 넘기지 않아 취소가 열리지 않는다.
private struct WaitingTimeline<Content: View>: View {
    let since: Date?
    let stage: (TimeInterval) -> WaitingStage
    @ViewBuilder let content: (WaitingStage, TimeInterval?) -> Content

    var body: some View {
        TimelineView(.periodic(from: since ?? .now, by: 1)) { context in
            let elapsed = since.map { context.date.timeIntervalSince($0) }
            content(stage(elapsed ?? 0), elapsed)
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
