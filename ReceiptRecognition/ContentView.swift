import SwiftUI
import DesignSystem

struct ContentView: View {
    @Environment(\.colorPalette) private var colors
    @Environment(\.spacingScale) private var spacing

    @State private var showScanner = false
    @State private var receiptCount = 0
    @State private var storageBackend: StorageBackend = .local

    var body: some View {
        NavigationStack {
            VStack(spacing: spacing.xl) {
                Spacer()

                // Icon
                Image(systemName: "receipt")
                    .font(.system(size: 64))
                    .foregroundStyle(colors.primary)

                // Receipt count
                Text("\(receiptCount)枚のレシートを保存済み")
                    .foregroundStyle(colors.onSurfaceVariant)

                // Storage status
                HStack(spacing: 6) {
                    Image(systemName: storageBackend == .iCloud ? "icloud.fill" : "internaldrive.fill")
                        .font(.caption)
                    Text(storageBackend.rawValue)
                        .font(.caption)
                }
                .foregroundStyle(colors.onSurfaceVariant.opacity(0.7))

                // Scan button
                Button {
                    showScanner = true
                } label: {
                    Label("レシートを撮影", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.primary)
                .padding(.horizontal, spacing.xl)

                // List link
                NavigationLink {
                    ReceiptListView()
                } label: {
                    Label("保存済みレシート", systemImage: "list.bullet.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.secondary)
                .padding(.horizontal, spacing.xl)

                Spacer()
            }
            .navigationTitle("レシート認識")
            .fullScreenCover(isPresented: $showScanner) {
                ReceiptScannerView()
            }
            .task {
                receiptCount = (try? await ReceiptStore.shared.count()) ?? 0
                storageBackend = await ReceiptStore.shared.currentBackend
            }
            .onAppear {
                Task {
                    receiptCount = (try? await ReceiptStore.shared.count()) ?? 0
                    storageBackend = await ReceiptStore.shared.currentBackend
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .theme(ThemeProvider())
}
