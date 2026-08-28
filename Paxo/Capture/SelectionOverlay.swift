import AppKit

/// 화면 위에 반투명 오버레이를 띄우고 드래그로 영역을 선택하게 한다.
/// 반환 rect는 전역 화면 좌표(AppKit, 좌하단 원점).
@MainActor
enum SelectionOverlay {
    static func selectRegion() async -> (rect: CGRect, screen: NSScreen)? {
        await withCheckedContinuation { continuation in
            SelectionSession.shared.begin { result in
                continuation.resume(returning: result)
            }
        }
    }
}

@MainActor
final class SelectionSession {
    static let shared = SelectionSession()

    private var windows: [SelectionWindow] = []
    private var completion: (((rect: CGRect, screen: NSScreen)?) -> Void)?
    private var finished = false

    func begin(completion: @escaping ((rect: CGRect, screen: NSScreen)?) -> Void) {
        guard windows.isEmpty else {
            completion(nil)
            return
        }
        self.completion = completion
        finished = false

        for screen in NSScreen.screens {
            let window = SelectionWindow(screen: screen, session: self)
            windows.append(window)
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        NSCursor.crosshair.set()
    }

    func finish(rect: CGRect?, screen: NSScreen?) {
        guard !finished else { return }
        finished = true

        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        NSCursor.arrow.set()

        let completion = self.completion
        self.completion = nil

        if let rect, let screen, rect.width > 4, rect.height > 4 {
            completion?((rect, screen))
        } else {
            completion?(nil)
        }
    }
}

private final class SelectionWindow: NSWindow {
    init(screen: NSScreen, session: SelectionSession) {
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false

        let view = SelectionView(screen: screen, session: session)
        contentView = view
        makeFirstResponder(view)
    }

    override var canBecomeKey: Bool { true }
}

private final class SelectionView: NSView {
    private let screen: NSScreen
    private unowned let session: SelectionSession
    private var startPoint: CGPoint?
    private var currentRect: CGRect = .zero

    init(screen: NSScreen, session: SelectionSession) {
        self.screen = screen
        self.session = session
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.25).setFill()
        bounds.fill()

        guard currentRect.width > 0 else {
            drawHint()
            return
        }
        NSColor.clear.setFill()
        currentRect.fill(using: .copy)
        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(rect: currentRect)
        path.lineWidth = 2
        path.stroke()
    }

    /// 드래그 시작 전, 오버레이 딤 위에 직접 안내를 그린다 (플로팅 패널은 딤에 가려지므로)
    private func drawHint() {
        let text = "풀이할 영역을 드래그하세요  ·  Esc 취소" as NSString
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
        ]
        let size = text.size(withAttributes: attrs)
        let padding = NSSize(width: 24, height: 12)
        let boxWidth = size.width + padding.width * 2
        let boxHeight = size.height + padding.height * 2
        let boxRect = NSRect(
            x: bounds.midX - boxWidth / 2,
            y: bounds.maxY - boxHeight - 80,
            width: boxWidth,
            height: boxHeight
        )
        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: boxRect, xRadius: 10, yRadius: 10).fill()
        text.draw(
            at: NSPoint(x: boxRect.midX - size.width / 2, y: boxRect.midY - size.height / 2),
            withAttributes: attrs
        )
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let point = convert(event.locationInWindow, from: nil)
        currentRect = CGRect(
            x: min(start.x, point.x),
            y: min(start.y, point.y),
            width: abs(start.x - point.x),
            height: abs(start.y - point.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { startPoint = nil }
        guard let window, currentRect.width > 4, currentRect.height > 4 else {
            session.finish(rect: nil, screen: nil)
            return
        }
        let globalRect = CGRect(
            x: window.frame.minX + currentRect.minX,
            y: window.frame.minY + currentRect.minY,
            width: currentRect.width,
            height: currentRect.height
        )
        session.finish(rect: globalRect, screen: screen)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            session.finish(rect: nil, screen: nil)
        } else {
            super.keyDown(with: event)
        }
    }
}
