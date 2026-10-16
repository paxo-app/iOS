import StoreKit
import SwiftUI

/// 구독 상태와 구매 안내를 제공해 사용자가 플랜을 선택할 수 있게 한다.
struct PaywallView: View {
    @EnvironmentObject private var store: StoreManager

    var body: some View {
        VStack(spacing: 16) {
            PaxoAppIcon()
                .frame(width: 64, height: 64)

            Text("Paxo Pro")
                .font(.title2.bold())

            if store.isPro {
                Label(
                    "Pro 사용 중 — 하루 최대 \(UsagePolicy.dailyProLimit)회 풀이할 수 있어요.",
                    systemImage: "checkmark.seal.fill"
                )
                .font(.callout)
                .multilineTextAlignment(.center)
            } else {
                Text(
                    "무료 풀이는 하루 \(UsagePolicy.dailyFreeLimit)회, 기록 열람은 최신 10개까지예요.\nPro는 하루 최대 \(UsagePolicy.dailyProLimit)회와 기록 100개 열람, 과목 관리·과목별 보기를 제공해요."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

                Text("Pro가 끝나도 이전 기록은 이 Mac에 최대 100개까지 보관됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

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
                                    if let freeTrialText = freeTrialText(product) {
                                        Text(freeTrialText)
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

                    if showsIntroOfferNotice {
                        Text("무료 체험은 신규 구독자에게 같은 구독 그룹에서 한 번만 제공됩니다.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
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

            if let serviceURL = URL(string: DefaultConfig.serviceGuideURL) {
                Link("서비스·구독 안내", destination: serviceURL)
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
        .frame(width: 340)
        .paxoSurface(cornerRadius: 0)
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

    private var showsIntroOfferNotice: Bool {
        store.products.contains { store.isEligibleForIntroOffer($0) }
    }

    private func freeTrialText(_ product: Product) -> String? {
        guard store.isEligibleForIntroOffer(product),
            let offer = product.subscription?.introductoryOffer,
            offer.paymentMode == .freeTrial,
            let unit = periodUnitLabel(offer.period.unit)
        else { return nil }
        return "\(offer.period.value)\(unit) 무료 체험 포함"
    }

    private func periodUnitLabel(_ unit: Product.SubscriptionPeriod.Unit) -> String? {
        switch unit {
        case .day: return "일"
        case .week: return "주"
        case .month: return "개월"
        case .year: return "년"
        @unknown default: return nil
        }
    }
}
