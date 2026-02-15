import SwiftUI
import DesignSystem

/// Edit view for receipt structured data
struct ReceiptEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorPalette) private var colors
    @Environment(\.spacingScale) private var spacing

    let receipt: SavedReceipt
    let original: ReceiptData?
    var onSaved: ((ReceiptData) -> Void)?

    // Editable fields
    @State private var storeName: String = ""
    @State private var date: String = ""
    @State private var time: String = ""
    @State private var totalAmountText: String = ""
    @State private var taxAmountText: String = ""
    @State private var currency: String = "JPY"
    @State private var paymentMethod: String = ""
    @State private var items: [EditableItem] = []

    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                // Store info
                Section("店舗情報") {
                    LabeledContent("店舗名") {
                        TextField("店舗名", text: $storeName)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("日付") {
                        TextField("YYYY-MM-DD", text: $date)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numbersAndPunctuation)
                    }
                    LabeledContent("時刻") {
                        TextField("HH:MM", text: $time)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numbersAndPunctuation)
                    }
                }

                // Amount
                Section("金額") {
                    LabeledContent("合計（税込）") {
                        TextField("0", text: $totalAmountText)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                    }
                    LabeledContent("消費税") {
                        TextField("0", text: $taxAmountText)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                    }
                    Picker("通貨", selection: $currency) {
                        Text("JPY").tag("JPY")
                        Text("USD").tag("USD")
                        Text("EUR").tag("EUR")
                    }
                    LabeledContent("支払方法") {
                        TextField("現金", text: $paymentMethod)
                            .multilineTextAlignment(.trailing)
                    }
                }

                // Items
                Section {
                    ForEach($items) { $item in
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("品名", text: $item.name)
                                .font(.subheadline)
                            HStack {
                                Text("単価")
                                    .font(.caption)
                                    .foregroundStyle(colors.onSurfaceVariant)
                                TextField("0", text: $item.unitPriceText)
                                    .keyboardType(.numberPad)
                                    .frame(width: 80)
                                    .multilineTextAlignment(.trailing)
                                Text("x")
                                    .font(.caption)
                                    .foregroundStyle(colors.onSurfaceVariant)
                                TextField("1", text: $item.quantityText)
                                    .keyboardType(.numberPad)
                                    .frame(width: 40)
                                    .multilineTextAlignment(.trailing)
                                Spacer()
                                Text("小計")
                                    .font(.caption)
                                    .foregroundStyle(colors.onSurfaceVariant)
                                TextField("0", text: $item.subtotalText)
                                    .keyboardType(.numberPad)
                                    .frame(width: 80)
                                    .multilineTextAlignment(.trailing)
                            }
                            .font(.caption)
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { indexSet in
                        items.remove(atOffsets: indexSet)
                    }

                    Button {
                        items.append(EditableItem())
                    } label: {
                        Label("品目を追加", systemImage: "plus.circle")
                    }
                } header: {
                    Text("品目")
                }

                // Error
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(colors.error)
                    }
                }
            }
            .navigationTitle("レシート編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("保存")
                        }
                    }
                    .disabled(storeName.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
        .onAppear {
            populateFields()
        }
    }

    // MARK: - Populate

    private func populateFields() {
        guard let data = original else { return }
        storeName = data.storeName
        date = data.date ?? ""
        time = data.time ?? ""
        totalAmountText = data.totalAmount.map { String($0) } ?? ""
        taxAmountText = data.taxAmount.map { String($0) } ?? ""
        currency = data.currency
        paymentMethod = data.paymentMethod ?? ""
        items = data.items.map { EditableItem(from: $0) }
    }

    // MARK: - Save

    private func save() async {
        isSaving = true
        errorMessage = nil

        let receiptItems = items.compactMap { item -> ReceiptItem? in
            let name = item.name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            return ReceiptItem(
                name: name,
                unitPrice: Int(item.unitPriceText),
                quantity: Int(item.quantityText) ?? 1,
                subtotal: Int(item.subtotalText)
            )
        }

        let updated = ReceiptData(
            storeName: storeName.trimmingCharacters(in: .whitespaces),
            date: date.isEmpty ? nil : date,
            time: time.isEmpty ? nil : time,
            totalAmount: Int(totalAmountText),
            taxAmount: Int(taxAmountText),
            currency: currency,
            paymentMethod: paymentMethod.isEmpty ? nil : paymentMethod,
            items: receiptItems
        )

        do {
            try await ReceiptStore.shared.saveYAML(updated.toYAML(), for: receipt)
            onSaved?(updated)
            dismiss()
        } catch {
            errorMessage = "保存失敗: \(error.localizedDescription)"
        }

        isSaving = false
    }
}

// MARK: - Editable Item

private struct EditableItem: Identifiable {
    let id = UUID()
    var name: String = ""
    var unitPriceText: String = ""
    var quantityText: String = "1"
    var subtotalText: String = ""

    init() {}

    init(from item: ReceiptItem) {
        name = item.name
        unitPriceText = item.unitPrice.map { String($0) } ?? ""
        quantityText = String(item.quantity)
        subtotalText = item.subtotal.map { String($0) } ?? ""
    }
}
