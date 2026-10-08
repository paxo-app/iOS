import AppKit
import SwiftUI

/// 빌드된 AppIcon을 앱 내부 브랜드 이미지의 단일 원본으로 사용한다.
struct PaxoAppIcon: View {
    var body: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .scaledToFit()
            .accessibilityLabel("Paxo")
    }
}
