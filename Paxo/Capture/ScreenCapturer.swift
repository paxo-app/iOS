import AppKit
import ScreenCaptureKit

final class ScreenCapturer {

    typealias Capture = (data: Data, screen: NSScreen)

    @MainActor
    func captureInteractive(mode: CaptureMode) async throws -> Capture? {
        guard ensurePermission() else {
            throw CaptureError.noPermission
        }
        switch mode {
        case .region:
            guard let selection = await SelectionOverlay.selectRegion() else {
                return nil
            }
            // 오버레이 윈도우가 화면에서 사라질 시간을 준다.
            try? await Task.sleep(nanoseconds: 150_000_000)
            let data = try await capture(rect: selection.rect, on: selection.screen)
            return (data, selection.screen)
        case .fullScreen:
            // 마우스 커서가 있는 화면 전체를 즉시 캡처
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
                ?? NSScreen.main
            guard let screen else { throw CaptureError.displayNotFound }
            let data = try await capture(rect: screen.frame, on: screen)
            return (data, screen)
        }
    }

    private func ensurePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        CGRequestScreenCaptureAccess()
        return false
    }

    private func capture(rect: CGRect, on screen: NSScreen) async throws -> Data {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        guard
            let screenNumber = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber,
            let display = content.displays.first(where: { $0.displayID == screenNumber.uint32Value })
        else {
            throw CaptureError.displayNotFound
        }

        // 우리 앱 윈도우(결과 패널 등)는 캡처에서 제외
        let ownWindows = content.windows.filter {
            $0.owningApplication?.processID == getpid()
        }
        let filter = SCContentFilter(display: display, excludingWindows: ownWindows)

        // 전역 좌표(좌하단 원점) → 디스플레이 로컬 좌표(좌상단 원점)
        let screenFrame = screen.frame
        let localRect = CGRect(
            x: rect.minX - screenFrame.minX,
            y: screenFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )

        let scale = screen.backingScaleFactor
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = localRect
        configuration.width = Int(rect.width * scale)
        configuration.height = Int(rect.height * scale)
        configuration.showsCursor = false
        configuration.captureResolution = .best

        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        return try encodeForUpload(cgImage)
    }

    /// 2000px 상한 — 인식 품질은 유지하면서 전송량·토큰 비용·지연을 줄인다.
    private func encodeForUpload(_ cgImage: CGImage) throws -> Data {
        let maxDimension: CGFloat = 2000
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let scale = min(1, maxDimension / max(width, height))

        var finalImage = cgImage
        if scale < 1,
           let context = CGContext(
               data: nil,
               width: Int(width * scale),
               height: Int(height * scale),
               bitsPerComponent: 8,
               bytesPerRow: 0,
               space: CGColorSpaceCreateDeviceRGB(),
               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
           ) {
            context.interpolationQuality = .high
            context.draw(
                cgImage,
                in: CGRect(x: 0, y: 0, width: width * scale, height: height * scale)
            )
            finalImage = context.makeImage() ?? cgImage
        }

        let bitmap = NSBitmapImageRep(cgImage: finalImage)
        guard let jpeg = bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: 0.82]
        ) else {
            throw CaptureError.encodingFailed
        }
        return jpeg
    }
}

enum CaptureError: LocalizedError {
    case noPermission
    case displayNotFound
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .noPermission:
            return "화면 기록 권한이 필요합니다. 시스템 설정 → 개인정보 보호 및 보안 → 화면 및 시스템 오디오 녹음에서 Paxo를 허용한 뒤 다시 시도해주세요."
        case .displayNotFound:
            return "캡처할 디스플레이를 찾지 못했습니다."
        case .encodingFailed:
            return "캡처 이미지 인코딩에 실패했습니다."
        }
    }
}
