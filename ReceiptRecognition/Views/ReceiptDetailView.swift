import SwiftUI
import DesignSystem

/// Detail view for a saved receipt showing structured data and image
struct ReceiptDetailView: View {
    @Environment(\.colorPalette) private var colors
    @Environment(\.spacingScale) private var spacing
    @Environment(\.scanningService) private var scanningService
    @Environment(\.extractionService) private var extractionService

    let receipt: SavedReceipt

    @State private var receiptData: ReceiptData?
    @State private var ocrText: String?
    @State private var image: UIImage?
    @State private var showFullImage = false
    @State private var showEditor = false
    @State private var isReExtracting = false
    @State private var reExtractError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: spacing.lg) {
                // Receipt image (tappable)
                imageSection

                // Structured data or fallback
                if let data = receiptData {
                    structuredDataSection(data)
                } else if ocrText != nil {
                    noStructuredDataBanner
                }

                // Re-extract button
                reExtractSection

                // OCR raw text (collapsible)
                if let text = ocrText, !text.isEmpty {
                    ocrTextSection(text)
                }

                // Metadata
                metadataSection
            }
            .padding(spacing.md)
        }
        .navigationTitle(receiptData?.storeName ?? "レシート詳細")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showEditor = true
                } label: {
                    Image(systemName: "pencil")
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            ReceiptEditView(receipt: receipt, original: receiptData) { updated in
                receiptData = updated
            }
        }
        .fullScreenCover(isPresented: $showFullImage) {
            fullImageView
        }
        .task {
            loadData()
        }
    }

    // MARK: - Image Section

    private var imageSection: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
                    .onTapGesture { showFullImage = true }
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(colors.surfaceVariant)
                    .frame(height: 160)
                    .overlay {
                        Image(systemName: "receipt")
                            .font(.largeTitle)
                            .foregroundStyle(colors.onSurfaceVariant)
                    }
            }
        }
    }

    // MARK: - Structured Data

    private func structuredDataSection(_ data: ReceiptData) -> some View {
        VStack(spacing: spacing.md) {
            // Header card: store + total
            headerCard(data)

            // Items list
            if !data.items.isEmpty {
                itemsCard(data.items, currency: data.currency)
            }

            // Payment info
            paymentCard(data)
        }
    }

    private func headerCard(_ data: ReceiptData) -> some View {
        VStack(spacing: spacing.sm) {
            // Store name
            Text(data.storeName)
                .font(.title2)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Date & time
            if let date = data.date {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.caption)
                        .foregroundStyle(colors.onSurfaceVariant)
                    Text(formatDateDisplay(date))
                        .font(.subheadline)
                    if let time = data.time {
                        Text(time)
                            .font(.subheadline)
                            .foregroundStyle(colors.onSurfaceVariant)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
                .padding(.vertical, 4)

            // Total amount (large)
            if let total = data.totalAmount {
                HStack(alignment: .firstTextBaseline) {
                    Text("合計")
                        .font(.subheadline)
                        .foregroundStyle(colors.onSurfaceVariant)
                    Spacer()
                    Text(formatCurrency(total, code: data.currency))
                        .font(.system(.title, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(colors.primary)
                }

                if let tax = data.taxAmount {
                    HStack {
                        Text("（うち税")
                            .font(.caption)
                            .foregroundStyle(colors.onSurfaceVariant)
                        Text(formatCurrency(tax, code: data.currency))
                            .font(.caption)
                            .foregroundStyle(colors.onSurfaceVariant)
                        Text("）")
                            .font(.caption)
                            .foregroundStyle(colors.onSurfaceVariant)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .padding(spacing.md)
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }

    private func itemsCard(_ items: [ReceiptItem], currency: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack {
                Image(systemName: "cart.fill")
                    .font(.caption)
                    .foregroundStyle(colors.primary)
                Text("品目")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(items.count)点")
                    .font(.caption)
                    .foregroundStyle(colors.onSurfaceVariant)
            }
            .padding(.horizontal, spacing.md)
            .padding(.top, spacing.md)
            .padding(.bottom, spacing.sm)

            Divider()
                .padding(.horizontal, spacing.md)

            // Item rows
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                itemRow(item, currency: currency)

                if index < items.count - 1 {
                    Divider()
                        .padding(.leading, spacing.md)
                }
            }
        }
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }

    private func itemRow(_ item: ReceiptItem, currency: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline)

                if item.quantity > 1, let unitPrice = item.unitPrice {
                    Text("\(formatCurrency(unitPrice, code: currency)) x \(item.quantity)")
                        .font(.caption)
                        .foregroundStyle(colors.onSurfaceVariant)
                }
            }

            Spacer()

            if let subtotal = item.subtotal {
                Text(formatCurrency(subtotal, code: currency))
                    .font(.subheadline)
                    .fontWeight(.medium)
            } else if let unitPrice = item.unitPrice {
                Text(formatCurrency(unitPrice * item.quantity, code: currency))
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
        }
        .padding(.horizontal, spacing.md)
        .padding(.vertical, spacing.sm)
    }

    private func paymentCard(_ data: ReceiptData) -> some View {
        VStack(spacing: spacing.sm) {
            if let method = data.paymentMethod {
                HStack {
                    Image(systemName: "creditcard.fill")
                        .font(.caption)
                        .foregroundStyle(colors.onSurfaceVariant)
                    Text("支払方法")
                        .font(.caption)
                        .foregroundStyle(colors.onSurfaceVariant)
                    Spacer()
                    Text(method)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
        }
        .padding(spacing.md)
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }

    // MARK: - No Structured Data

    private var noStructuredDataBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .foregroundStyle(colors.onSurfaceVariant)
            Text("構造化データなし（OCRテキストのみ）")
                .font(.subheadline)
                .foregroundStyle(colors.onSurfaceVariant)
        }
        .padding(spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surfaceVariant.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - OCR Text

    private func ocrTextSection(_ text: String) -> some View {
        DisclosureGroup("OCRテキスト") {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
                .textSelection(.enabled)
        }
        .padding(spacing.md)
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        VStack(spacing: 6) {
            metaRow(icon: "clock", label: "撮影日時",
                    value: receipt.metadata.capturedAt.formatted(date: .abbreviated, time: .shortened))
            metaRow(icon: "text.viewfinder", label: "OCR精度",
                    value: "\(Int(receipt.metadata.ocrConfidence * 100))%")
            metaRow(icon: "rectangle.dashed", label: "矩形検出",
                    value: receipt.metadata.rectangleDetected ? "あり" : "なし")
        }
        .padding(spacing.md)
        .background(colors.surfaceVariant.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func metaRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(colors.onSurfaceVariant)
                .frame(width: 20)
            Text(label)
                .font(.caption)
                .foregroundStyle(colors.onSurfaceVariant)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }

    // MARK: - Full Image

    private var fullImageView: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            }

            Button {
                showFullImage = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .white.opacity(0.3))
            }
            .padding()
        }
    }

    // MARK: - Re-Extract

    private var reExtractSection: some View {
        VStack(spacing: spacing.sm) {
            if let error = reExtractError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(colors.error)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(colors.error)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                Task { await performReExtract() }
            } label: {
                HStack(spacing: 8) {
                    if isReExtracting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    Text(isReExtracting ? "再解析中..." : "高精度で再解析")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, spacing.sm)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isReExtracting || extractionService == nil)
        }
    }

    private func performReExtract() async {
        guard let extractionService else { return }

        isReExtracting = true
        reExtractError = nil

        do {
            // 1. Load image data and re-run OCR
            guard let imageData = try? Data(contentsOf: receipt.imageURL) else {
                reExtractError = "画像の読み込みに失敗しました"
                isReExtracting = false
                return
            }

            let scanResult = try await scanningService.scan(from: imageData)

            // 2. Re-extract with stronger model (Gemini Pro)
            let newData = try await extractionService.reExtract(from: scanResult.text)

            // 3. Save updated YAML
            let yaml = newData.toYAML()
            try await ReceiptStore.shared.saveYAML(yaml, for: receipt)

            // 4. Update OCR text file
            if let ocrData = scanResult.text.data(using: .utf8) {
                try ocrData.write(to: receipt.ocrTextURL)
            }

            // 5. Update view state
            receiptData = newData
            ocrText = scanResult.text
            image = UIImage(data: imageData)
        } catch {
            reExtractError = "再解析に失敗: \(error.localizedDescription)"
        }

        isReExtracting = false
    }

    // MARK: - Helpers

    private func loadData() {
        // Load image
        if let data = try? Data(contentsOf: receipt.imageURL) {
            image = UIImage(data: data)
        }

        // Load OCR text
        ocrText = try? String(contentsOf: receipt.ocrTextURL, encoding: .utf8)

        // Load structured YAML
        if let yaml = try? String(contentsOf: receipt.receiptYAMLURL, encoding: .utf8) {
            receiptData = ReceiptData.fromYAML(yaml)
        }
    }

    private func formatCurrency(_ amount: Int, code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }

    private func formatDateDisplay(_ dateString: String) -> String {
        let input = DateFormatter()
        input.dateFormat = "yyyy-MM-dd"
        guard let date = input.date(from: dateString) else { return dateString }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
