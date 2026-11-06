import StoreKit
import SwiftUI

/// 충전량과 실제 결제 가격을 함께 보여주고 서버에 적립된 잔액을 안내한다.
struct PaywallView: View {
    @EnvironmentObject private var store: StoreManager

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PaxoAppIcon()
                    .frame(width: 52, height: 52)

                Text("풀이권 충전")
                    .font(.title2.bold())

                Text("필요한 만큼 충전하고, 기간 제한 없이 사용하세요.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if store.isSignedIn {
                    Label("보유 풀이권 \(store.creditBalance.formatted())회", systemImage: "ticket")
                        .font(.headline)
                        .monospacedDigit()
                } else {
                    Text("설정에서 Apple로 로그인한 뒤 충전할 수 있습니다.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                productChoices

                if store.purchaseInFlight {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("결제와 풀이권 적립을 확인하는 중…")
                            .font(.caption)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("매일 무료 \(UsagePolicy.dailyFreeLimit)회를 먼저 사용합니다.", systemImage: "gift")
                    Label("풀이권 1회로 정답과 해설을 제공합니다.", systemImage: "text.bubble")
                    Label("정답 제공에 성공했을 때만 차감합니다.", systemImage: "checkmark.circle")
                    Label("충전한 풀이권은 만료·자동 결제 없이 사용합니다.", systemImage: "ticket")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(UsagePolicy.dailyResetNotice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let error = store.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button("잔액 새로고침") {
                    Task { await store.restore() }
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.tint)
                .disabled(store.purchaseInFlight || !store.isSignedIn)

                Text("풀이권은 로그인한 Paxo 계정에 보관됩니다.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let serviceURL = URL(string: DefaultConfig.serviceGuideURL) {
                    Link("서비스·충전 안내", destination: serviceURL)
                        .font(.caption2)
                }

                HStack(spacing: 12) {
                    if let privacyURL = URL(string: DefaultConfig.privacyPolicyURL) {
                        Link("개인정보 처리방침", destination: privacyURL)
                    }
                    if let termsURL = URL(string: DefaultConfig.termsOfUseURL) {
                        Link("이용약관", destination: termsURL)
                    }
                }
                .font(.caption2)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .frame(width: 420, height: 650)
        .paxoSurface(cornerRadius: 0)
    }

    @ViewBuilder
    private var productChoices: some View {
        if store.productLoadState == .idle || store.productLoadState == .loading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("가격 정보를 불러오는 중…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } else if store.products.isEmpty {
            Button("가격 정보 다시 불러오기") {
                Task { await store.loadProducts() }
            }
            .buttonStyle(.bordered)
        } else {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(store.products, id: \.id) { product in
                    if let count = StoreProducts.creditCount(for: product.id) {
                        Button {
                            Task { await store.purchase(product) }
                        } label: {
                            VStack(spacing: 8) {
                                Text("\(count.formatted())회")
                                    .font(.title3.bold())
                                Text(product.displayPrice)
                                    .font(.headline)
                                Text("충전하기")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("풀이권 \(count)회, \(product.displayPrice), 충전하기")
                    }
                }
            }
            .disabled(store.purchaseInFlight || !store.isSignedIn)
        }
    }
}
