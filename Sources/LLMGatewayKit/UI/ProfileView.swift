import SwiftUI

public struct ProfileView: View {
    private let config: LLMGatewayKitConfig
    private let authService: AuthService
    private let subscriptionService: SubscriptionService
    private let onRequestUpgrade: () -> Void
    @State private var usage: UsageInfo?
    @State private var errorMessage: String?

    public init(
        config: LLMGatewayKitConfig,
        authService: AuthService,
        subscriptionService: SubscriptionService,
        onRequestUpgrade: @escaping () -> Void
    ) {
        self.config = config
        self.authService = authService
        self.subscriptionService = subscriptionService
        self.onRequestUpgrade = onRequestUpgrade
    }

    public var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    avatar
                    VStack(alignment: .leading, spacing: 4) {
                        Text(authService.currentUser?.displayName ?? authService.currentUser?.email ?? "未ログイン")
                            .font(.headline)
                        Text(authService.currentUser?.tier == "paid" ? "Paid" : "Free")
                            .font(.caption)
                            .foregroundStyle(authService.currentUser?.tier == "paid" ? .green : .secondary)
                    }
                }
                if authService.isLoggedIn {
                    Button("ログアウト") { Task { await authService.logout() } }
                    Button("アカウント削除", role: .destructive) {
                        Task { try? await authService.deleteAccount() }
                    }
                } else {
                    Button("Sign in with Apple") {
                        Task {
                            do { try await authService.authenticateInteractively() }
                            catch { errorMessage = error.localizedDescription }
                        }
                    }
                }
            }

            if authService.isLoggedIn {
                Section("プラン") {
                    HStack {
                        Text(config.appDisplayName)
                        Spacer()
                        Text(authService.currentUser?.tier == "paid" ? "Pro" : "Free")
                            .foregroundStyle(.secondary)
                    }
                    Button("アップグレード", action: onRequestUpgrade)
                }

                Section("Usage") {
                    if let usage {
                        HStack {
                            Text("使用量")
                            Spacer()
                            Text("\(usage.formattedBudgetUsed) / \(usage.formattedBudgetLimit)")
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: min(max(usage.percentage / 100.0, 0), 1))
                    } else {
                        Text("Usage を読み込み中...")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("プロフィール")
        .task(id: authService.isLoggedIn) {
            guard authService.isLoggedIn else { return }
            usage = try? await authService.fetchUsage()
            await subscriptionService.loadProducts()
        }
    }

    @ViewBuilder
    private var avatar: some View {
        ZStack {
            Circle().fill(.secondary.opacity(0.15))
            Text(Self.initial(from: authService.currentUser?.displayName ?? authService.currentUser?.email))
                .font(.headline.bold())
                .foregroundStyle(.secondary)
        }
        .frame(width: 56, height: 56)
        .rainbowAvatarBorder(isActive: authService.currentUser?.tier == "paid", size: 56)
    }

    public static func initial(from text: String?) -> String {
        guard let first = text?.trimmingCharacters(in: .whitespacesAndNewlines).first else {
            return "?"
        }
        return String(first).uppercased()
    }
}
