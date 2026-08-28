import StoreKit
import SwiftUI

struct PaywallView: View {
    @EnvironmentObject private var store: StoreManager

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 40))
                .foregroundStyle(.tint)

            Text("Paxo Pro")
                .font(.title2.bold())

            if store.isPro {
                Label("Pro 사용 중 — 무제한으로 풀이와 해설을 볼 수 있어요.", systemImage: "checkmark.seal.fill")
                    .font(.callout)
                    .multilineTextAlignment(.center)
            } else {
                Text("무료 풀이는 하루 \(UsageTracker.dailyFreeLimit)회예요.\nPro로 업그레이드하면 풀이와 해설을 무제한으로 볼 수 있어요.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if store.products.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("가격 정보를 불러오는 중…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(spacing: 8) {
                        ForEach(store.products, id: \.id) { product in
                            Button {
                                Task { await store.purchase(product) }
                            } label: {
                                VStack(spacing: 2) {
                                    Text(product.displayName)
                                        .font(.headline)
                                    Text("\(product.displayPrice) \(periodLabel(product))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if hasFreeTrial(product) {
                                        Text("7일 무료 체험 포함")
                                            .font(.caption2)
                                            .foregroundStyle(.tint)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .disabled(store.purchaseInFlight)
                }
            }

            if let error = store.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button("구매 복원") {
                Task { await store.restore() }
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)

            Text("구독은 App Store 계정 설정에서 언제든 관리·해지할 수 있습니다.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

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
        .frame(width: 340)
    }

    private func periodLabel(_ product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else { return "" }
        switch period.unit {
        case .day: return "/ 일"
        case .week: return "/ 주"
        case .month: return "/ 월"
        case .year: return "/ 년"
        @unknown default: return ""
        }
    }

    private func hasFreeTrial(_ product: Product) -> Bool {
        product.subscription?.introductoryOffer?.paymentMode == .freeTrial
    }
}
