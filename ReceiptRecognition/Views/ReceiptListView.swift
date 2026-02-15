import SwiftUI
import DesignSystem

/// A receipt with its pre-loaded display info for the list
private struct ReceiptListItem: Identifiable {
    let receipt: SavedReceipt
    let receiptData: ReceiptData?
    let displayDate: Date       // レシート記載日 or 撮影日
    let storeName: String       // 店舗名 or OCR 先頭行

    var id: String { receipt.id }
}

/// List of saved receipts grouped by month, sorted by receipt date
struct ReceiptListView: View {
    @Environment(\.colorPalette) private var colors
    @Environment(\.spacingScale) private var spacing

    @State private var items: [ReceiptListItem] = []
    @State private var isLoading = true
    @State private var receiptToDelete: SavedReceipt?
    @State private var showDeleteAlert = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView("読み込み中...")
            } else if items.isEmpty {
                ContentUnavailableView(
                    "レシートがありません",
                    systemImage: "receipt",
                    description: Text("撮影したレシートがここに表示されます")
                )
            } else {
                List {
                    ForEach(groupedByMonth, id: \.key) { month, sectionItems in
                        Section {
                            ForEach(sectionItems) { item in
                                NavigationLink(destination: ReceiptDetailView(receipt: item.receipt)) {
                                    receiptRow(item)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        receiptToDelete = item.receipt
                                        showDeleteAlert = true
                                    } label: {
                                        Label("削除", systemImage: "trash")
                                    }
                                }
                            }
                        } header: {
                            Text(month)
                        }
                    }
                }
            }
        }
        .navigationTitle("保存済みレシート")
        .task {
            await loadReceipts()
        }
        .alert("レシートを削除", isPresented: $showDeleteAlert, presenting: receiptToDelete) { receipt in
            Button("削除", role: .destructive) {
                Task {
                    try? await ReceiptStore.shared.delete(receipt)
                    await loadReceipts()
                }
            }
            Button("キャンセル", role: .cancel) {
                receiptToDelete = nil
            }
        } message: { receipt in
            let dateText = receipt.metadata.capturedAt.formatted(date: .abbreviated, time: .shortened)
            Text("\(dateText) のレシートを削除しますか？この操作は取り消せません。")
        }
    }

    // MARK: - Grouping

    private var groupedByMonth: [(key: String, value: [ReceiptListItem])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"

        let grouped = Dictionary(grouping: items) { item in
            formatter.string(from: item.displayDate)
        }

        return grouped
            .sorted { $0.key > $1.key }
            .map { (key: $0.key, value: $0.value.sorted { $0.displayDate > $1.displayDate }) }
    }

    // MARK: - Row

    private func receiptRow(_ item: ReceiptListItem) -> some View {
        HStack(spacing: spacing.md) {
            // Thumbnail
            if let imageData = try? Data(contentsOf: item.receipt.imageURL),
               let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(colors.surfaceVariant)
                    .frame(width: 50, height: 50)
                    .overlay {
                        Image(systemName: "receipt")
                            .foregroundStyle(colors.onSurfaceVariant)
                    }
            }

            // Store name + date
            VStack(alignment: .leading, spacing: 4) {
                Text(item.storeName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(item.displayDate.formatted(.dateTime.month().day().weekday(.abbreviated)))
                    .font(.caption)
                    .foregroundStyle(colors.onSurfaceVariant)
            }

            Spacer()

            // Total amount
            if let data = item.receiptData, let total = data.totalAmount {
                Text(formatCurrency(total, code: data.currency))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(colors.primary)
            }
        }
    }

    // MARK: - Data Loading

    private func loadReceipts() async {
        do {
            let receipts = try await ReceiptStore.shared.loadAll()
            items = receipts.map { receipt in
                let data = loadReceiptData(for: receipt)
                let displayDate = resolveDate(data: data, capturedAt: receipt.metadata.capturedAt)
                let storeName = data?.storeName ?? fallbackStoreName(for: receipt)

                return ReceiptListItem(
                    receipt: receipt,
                    receiptData: data,
                    displayDate: displayDate,
                    storeName: storeName
                )
            }
        } catch {
            items = []
        }
        isLoading = false
    }

    private func loadReceiptData(for receipt: SavedReceipt) -> ReceiptData? {
        guard let yaml = try? String(contentsOf: receipt.receiptYAMLURL, encoding: .utf8) else {
            return nil
        }
        return ReceiptData.fromYAML(yaml)
    }

    private func resolveDate(data: ReceiptData?, capturedAt: Date) -> Date {
        guard let dateStr = data?.date else { return capturedAt }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateStr) ?? capturedAt
    }

    private func fallbackStoreName(for receipt: SavedReceipt) -> String {
        guard let text = try? String(contentsOf: receipt.ocrTextURL, encoding: .utf8),
              let firstLine = text.split(separator: "\n").first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            return "不明な店舗"
        }
        return String(firstLine).trimmingCharacters(in: .whitespaces)
    }

    private func formatCurrency(_ amount: Int, code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "¥\(amount)"
    }
}
