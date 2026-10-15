import AppKit
import SwiftUI

/// 모든 앱 화면에서 같은 브랜드 색상과 불투명 배경을 사용한다.
enum PaxoStyle {
    static let brand = Color(red: 27 / 255, green: 118 / 255, blue: 1)
    static let cornerRadius: CGFloat = 14
}

extension View {
    func paxoSurface(cornerRadius: CGFloat = PaxoStyle.cornerRadius) -> some View {
        background(Color(nsColor: .windowBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.primary.opacity(0.1), lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .tint(PaxoStyle.brand)
    }

    func paxoWindowSurface() -> some View {
        paxoSurface(cornerRadius: 0)
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
