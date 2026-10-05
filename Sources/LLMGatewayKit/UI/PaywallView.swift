import SwiftUI

public struct PaywallView: View {
    private let config: LLMGatewayKitConfig
    @State private var viewModel: PaywallViewModel

    public init(config: LLMGatewayKitConfig, viewModel: PaywallViewModel) {
        self.config = config
        self._viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.tint)
                    Text("\(config.appDisplayName) Pro")
                        .font(.largeTitle.bold())
                    if !config.companionAppNames.isEmpty {
                        Text("両アプリで有効: \(([config.appDisplayName] + config.companionAppNames).joined(separator: " / "))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(config.paywallFeatures) { feature in
                        HStack(spacing: 12) {
                            Image(systemName: feature.icon)
                                .frame(width: 28)
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(feature.title).font(.headline)
                                if let subtitle = feature.subtitle {
                                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)

                if let price = viewModel.displayPrice, !price.isEmpty {
                    VStack(spacing: 4) {
                        Text(price)
                            .font(.largeTitle.bold())
                        if let period = viewModel.displayBillingPeriod {
                            Text(periodCaption(period))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                }

                VStack(spacing: 12) {
                    Button {
                        Task { await viewModel.purchase() }
                    } label: {
                        Text(purchaseButtonTitle)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy)

                    Button("購入を復元") {
                        Task { await viewModel.restore() }
                    }
                    .disabled(isBusy)

                    if case .failed(let message) = viewModel.purchaseState {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding()
            .navigationTitle("アップグレード")
            .task { await viewModel.loadProducts() }
        }
    }

    private var isBusy: Bool {
        switch viewModel.purchaseState {
        case .purchasing, .verifying:
            return true
        case .idle, .success, .failed:
            return false
        }
    }

    private var purchaseButtonTitle: String {
        switch viewModel.purchaseState {
        case .purchasing:
            return "購入中..."
        case .verifying:
            return "確認中..."
        case .success:
            return "有効化しました"
        case .idle, .failed:
            return viewModel.displayPrice.map { "Pro にアップグレード \($0)" } ?? "Pro にアップグレード"
        }
    }

    /// 金额来自商店；这里只把周期说成日语，与本页其余文案一致。
    private func periodCaption(_ period: PurchaseBillingPeriod) -> String {
        switch (period.unit, period.value) {
        case (.day, 1): return "1日あたり"
        case (.week, 1): return "毎週"
        case (.month, 1): return "毎月"
        case (.year, 1): return "毎年"
        case (.day, let count): return "\(count)日ごと"
        case (.week, let count): return "\(count)週間ごと"
        case (.month, let count): return "\(count)か月ごと"
        case (.year, let count): return "\(count)年ごと"
        }
    }
}
