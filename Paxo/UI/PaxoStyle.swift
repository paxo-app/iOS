import AppKit
import SwiftUI

/// 모든 앱 화면에서 같은 브랜드 색상과 표면 스타일을 사용한다.
enum PaxoStyle {
    static let brand = Color(red: 27 / 255, green: 118 / 255, blue: 1)
    static let cornerRadius: CGFloat = 14
}

extension View {
    /// 잠깐 떴다 사라지는 화면(메뉴바 팝오버, 토스트)에만 쓴다. 머물러 읽는 창은 `paxoWindowSurface()`를 쓴다.
    func paxoGlassSurface(cornerRadius: CGFloat = PaxoStyle.cornerRadius) -> some View {
        paxoSurface(cornerRadius: cornerRadius) { PaxoGlassBackground() }
    }

    /// 창 루트에 한 번만 붙인다. 안에 들어가는 화면은 배경을 따로 깔지 않아야 어느 창에서든 그 창의 배경을 따른다.
    func paxoWindowSurface() -> some View {
        paxoSurface(cornerRadius: 0) { Color(nsColor: .windowBackgroundColor) }
            .background(PaxoWindowBackground())
            .toolbarBackground(.hidden, for: .windowToolbar)
    }

    private func paxoSurface<Fill: View>(
        cornerRadius: CGFloat, @ViewBuilder fill: () -> Fill
    ) -> some View {
        background { fill() }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.primary.opacity(0.1), lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .tint(PaxoStyle.brand)
    }
}

/// 제목 표시줄이 본문과 다른 배경으로 그려지지 않도록 창 자체를 불투명하게 맞춘다.
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
