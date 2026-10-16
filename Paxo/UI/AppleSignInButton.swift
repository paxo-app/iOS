import AuthenticationServices
import SwiftUI

/// 로그인 위치가 달라도 동일한 인증 준비 상태와 요청을 사용한다.
struct AppleSignInButton: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        SignInWithAppleButton(
            .continue,
            onRequest: appState.configureAppleSignIn,
            onCompletion: appState.handleAppleSignIn
        )
        .signInWithAppleButtonStyle(.black)
        .frame(height: 36)
        .disabled(!appState.isAppleSignInReady)
    }
}
