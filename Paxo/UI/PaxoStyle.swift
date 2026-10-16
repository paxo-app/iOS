import AppKit
import SwiftUI

/// 모든 앱 화면에서 같은 브랜드 색상과 표면 스타일을 사용한다.
enum PaxoStyle {
    static let brand = Color(red: 27 / 255, green: 118 / 255, blue: 1)
    static let cornerRadius: CGFloat = 14
}

extension View {
    func paxoSurface(
        cornerRadius: CGFloat = PaxoStyle.cornerRadius, isOpaque: Bool = false
    ) -> some View {
        background {
            if isOpaque {
                Color(nsColor: .windowBackgroundColor)
            } else {
                PaxoGlassBackground()
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(.primary.opacity(0.1), lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .tint(PaxoStyle.brand)
    }

    func paxoWindowSurface() -> some View {
        paxoSurface(cornerRadius: 0, isOpaque: true)
            .background(PaxoWindowBackground())
            .toolbarBackground(.hidden, for: .windowToolbar)
    }
}

/// 설정 창의 기본 제목 표시줄이 본문과 별개로 배경을 흐리지 않게 한다.
private struct PaxoWindowBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowBackgroundView {
        WindowBackgroundView()
    }

    func updateNSView(_ view: WindowBackgroundView, context: Context) {
        view.applyBackground()
    }
}

private final class WindowBackgroundView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyBackground()
    }

    func applyBackground() {
        guard let window else { return }
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.titlebarAppearsTransparent = true
    }
}

private struct PaxoGlassBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                WindowGlass()
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 창 뒤의 배경을 흐리게 하면서 텍스트 대비를 유지한다.
private struct WindowGlass: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .hudWindow
        view.state = .active
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
    }
}
