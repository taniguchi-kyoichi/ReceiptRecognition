import SwiftUI
import DesignSystem

/// Post-capture confirmation view with save/retake options
struct SaveConfirmView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorPalette) private var colors
    @Environment(\.spacingScale) private var spacing
    @Environment(\.scanningService) private var scanningService
    @Environment(\.extractionService) private var extractionService

    let capturedImage: UIImage
    let imageData: Data
    var onSaved: (() -> Void)?

    @State private var ocrText: String = ""
    @State private var ocrConfidence: Float = 0
    @State private var rectangleDetected = false
    @State private var isProcessingOCR = true
    @State private var isSaving = false
    @State private var saveCompleted = false
    @State private var errorMessage: String?
    @State private var duplicates: [SavedReceipt] = []
    @State private var showDuplicateAlert = false

    // Extraction state
    @State private var extractedData: ReceiptData?
    @State private var isExtracting = false
    @State private var extractionError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: spacing.lg) {
                    // Image preview
                    Image(uiImage: capturedImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(radius: 4)

                    // Processing status
                    if isProcessingOCR {
                        processingBanner(text: "テキスト認識中...")
                    } else if isExtracting {
                        processingBanner(text: "レシート解析中...")
                    }

                    // Extraction result preview
                    if let data = extractedData {
                        extractionPreview(data)
                    }

                    // Extraction error (non-blocking)
                    if let error = extractionError {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(.orange)
                            Text("解析できませんでした: \(error)")
                                .font(.caption)
                                .foregroundStyle(colors.onSurfaceVariant)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Duplicate warning
                    if !duplicates.isEmpty && !saveCompleted {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("同じ日付・同じ店舗のレシートが\(duplicates.count)枚あります")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                ForEach(duplicates) { dup in
                                    Text("\(dup.metadata.capturedAt, style: .time) に保存済み")
                                        .font(.caption)
                                        .foregroundStyle(colors.onSurfaceVariant)
                                }
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // OCR text (collapsible)
                    if !ocrText.isEmpty {
                        DisclosureGroup("OCR抽出テキスト") {
                            Text(ocrText)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 8)
                        }
                        .padding()
                        .background(colors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // Error
                    if let error = errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(colors.error)
                            Text(error)
                                .foregroundStyle(colors.error)
                        }
                        .padding()
                        .background(colors.error.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Success
                    if saveCompleted {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(colors.primary)
                            Text("保存しました")
                                .fontWeight(.semibold)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(colors.primary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Action buttons
                    if saveCompleted {
                        VStack(spacing: spacing.md) {
                            Button {
                                dismiss()
                            } label: {
                                Label("続けて撮影", systemImage: "camera.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.primary)

                            Button {
                                dismiss()
                                onSaved?()
                            } label: {
                                Label("ホームに戻る", systemImage: "house")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.secondary)
                        }
                    } else {
                        VStack(spacing: spacing.md) {
                            Button {
                                if duplicates.isEmpty {
                                    Task { await save() }
                                } else {
                                    showDuplicateAlert = true
                                }
                            } label: {
                                if isSaving {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                } else {
                                    Label("保存", systemImage: "square.and.arrow.down.fill")
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .buttonStyle(.primary)
                            .disabled(isProcessingOCR || isSaving)

                            Button {
                                dismiss()
                            } label: {
                                Label("撮り直し", systemImage: "camera.rotate")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.secondary)
                            .disabled(isSaving)
                        }
                    }
                }
                .padding(spacing.md)
            }
            .navigationTitle("確認")
            .navigationBarTitleDisplayMode(.inline)
            .alert("重複の可能性", isPresented: $showDuplicateAlert) {
                Button("保存する", role: .destructive) {
                    Task { await save() }
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("同じ日付・同じ店舗のレシートが既に\(duplicates.count)枚保存されています。それでも保存しますか？")
            }
        }
        .task {
            await performOCR()
        }
    }

    // MARK: - Subviews

    private func processingBanner(text: String) -> some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(text)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(colors.surfaceVariant)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func extractionPreview(_ data: ReceiptData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(colors.primary)
                Text("解析結果")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            Divider()

            previewRow(label: "店舗", value: data.storeName)

            if let date = data.date {
                previewRow(label: "日付", value: date + (data.time.map { " \($0)" } ?? ""))
            }

            if let total = data.totalAmount {
                let formatted = NumberFormatter.localizedString(from: NSNumber(value: total), number: .decimal)
                previewRow(label: "合計", value: "\(formatted) \(data.currency)")
            }

            if let method = data.paymentMethod {
                previewRow(label: "支払", value: method)
            }

            if !data.items.isEmpty {
                previewRow(label: "品目", value: "\(data.items.count)点")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func previewRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(colors.onSurfaceVariant)
                .frame(width: 40, alignment: .trailing)
            Text(value)
                .font(.subheadline)
        }
    }

    // MARK: - Actions

    private func performOCR() async {
        do {
            let result = try await scanningService.scan(from: imageData)
            ocrText = result.text
            ocrConfidence = result.confidence ?? 0
            rectangleDetected = result.rectangleDetected
            isProcessingOCR = false

            // Check for duplicates after OCR
            duplicates = (try? await ReceiptStore.shared.findDuplicates(ocrText: ocrText)) ?? []

            // Start extraction if service is available
            await performExtraction()
        } catch {
            ocrText = ""
            ocrConfidence = 0
            isProcessingOCR = false
            errorMessage = "OCR失敗: \(error.localizedDescription)"
        }
    }

    private func performExtraction() async {
        guard let service = extractionService, !ocrText.isEmpty else { return }

        isExtracting = true
        do {
            extractedData = try await service.extract(from: ocrText)
        } catch {
            extractionError = error.localizedDescription
        }
        isExtracting = false
    }

    private func save() async {
        isSaving = true
        errorMessage = nil

        do {
            _ = try await ReceiptStore.shared.save(
                imageData: imageData,
                ocrText: ocrText,
                ocrConfidence: ocrConfidence,
                rectangleDetected: rectangleDetected,
                receiptYAML: extractedData?.toYAML()
            )
            saveCompleted = true
        } catch {
            errorMessage = "保存失敗: \(error.localizedDescription)"
        }

        isSaving = false
    }
}
