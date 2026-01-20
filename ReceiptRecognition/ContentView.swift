//
//  ContentView.swift
//  ReceiptRecognition
//
//  Created by 谷口恭一 on 2026/01/20.
//

import SwiftUI
import DesignSystem

struct ContentView: View {
    @Environment(\.colorPalette) private var colors
    @Environment(\.spacingScale) private var spacing

    @State private var showImagePicker = false
    @State private var capturedImageData: Data?
    @State private var isAnalyzing = false
    @State private var imageResult: AnalysisResult?
    @State private var ocrResult: AnalysisResult?
    @State private var errorMessage: String?
    @State private var showOCRTextSheet = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: spacing.lg) {
                    imagePreviewSection
                    actionButtonsSection

                    if let error = errorMessage {
                        errorSection(error)
                    }

                    if imageResult != nil || ocrResult != nil {
                        resultsSection
                    }
                }
                .padding(spacing.md)
            }
            .navigationTitle("レシート認識")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .imagePicker(
                isPresented: $showImagePicker,
                selectedImageData: $capturedImageData,
                maxSize: 2.mb
            )
            .onChange(of: capturedImageData) { _, newValue in
                if newValue != nil {
                    imageResult = nil
                    ocrResult = nil
                    errorMessage = nil
                }
            }
            .sheet(isPresented: $showOCRTextSheet) {
                ocrTextSheet
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }

    // MARK: - OCR Text Sheet

    private var ocrTextSheet: some View {
        NavigationStack {
            ScrollView {
                Text(ocrResult?.ocrText ?? "OCRテキストがありません")
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("OCR抽出テキスト")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if let text = ocrResult?.ocrText {
                            UIPasteboard.general.string = text
                        }
                    } label: {
                        Label("コピー", systemImage: "doc.on.doc")
                    }
                    .disabled(ocrResult?.ocrText == nil)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") {
                        showOCRTextSheet = false
                    }
                }
            }
        }
    }

    // MARK: - Image Preview Section

    private var imagePreviewSection: some View {
        Group {
            if let imageData = capturedImageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 4)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(colors.surfaceVariant)
                    .frame(height: 200)
                    .overlay {
                        VStack(spacing: spacing.sm) {
                            Image(systemName: "receipt")
                                .font(.system(size: 48))
                            Text("レシートを撮影してください")
                                .font(.headline)
                        }
                        .foregroundStyle(colors.onSurfaceVariant)
                    }
            }
        }
    }

    // MARK: - Action Buttons Section

    private var actionButtonsSection: some View {
        VStack(spacing: spacing.md) {
            Button {
                showImagePicker = true
            } label: {
                Label(
                    capturedImageData == nil ? "レシートを撮影" : "別のレシートを撮影",
                    systemImage: "camera.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.primary)

            if capturedImageData != nil {
                Button {
                    Task {
                        await analyze()
                    }
                } label: {
                    if isAnalyzing {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("解析実行", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.secondary)
                .disabled(isAnalyzing)
            }
        }
    }

    // MARK: - Error Section

    private func errorSection(_ error: String) -> some View {
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

    // MARK: - Results Section

    private var resultsSection: some View {
        VStack(spacing: spacing.lg) {
            if let img = imageResult, let ocr = ocrResult {
                comparisonView(imageResult: img, ocrResult: ocr)
            }
        }
    }

    // MARK: - Comparison View

    private func comparisonView(imageResult: AnalysisResult, ocrResult: AnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: spacing.md) {
            // 判定結果
            HStack {
                resultBadge(title: "画像入力", result: imageResult)
                Spacer()
                resultBadge(title: "OCR+テキスト", result: ocrResult, showOCRButton: true)
            }

            Divider()

            // 日付
            HStack {
                VStack(alignment: .leading) {
                    Text("日付")
                        .font(.caption)
                        .foregroundStyle(colors.onSurfaceVariant)
                    Text(imageResult.date ?? "-")
                        .fontWeight(.semibold)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("日付")
                        .font(.caption)
                        .foregroundStyle(colors.onSurfaceVariant)
                    Text(ocrResult.date ?? "-")
                        .fontWeight(.semibold)
                }
            }

            Divider()

            // トークン数
            HStack {
                VStack(alignment: .leading) {
                    Text("トークン")
                        .font(.caption)
                        .foregroundStyle(colors.onSurfaceVariant)
                    Text("\(imageResult.totalTokens)")
                        .fontWeight(.semibold)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("トークン")
                        .font(.caption)
                        .foregroundStyle(colors.onSurfaceVariant)
                    Text("\(ocrResult.totalTokens)")
                        .fontWeight(.semibold)
                }
            }

            // 処理時間
            HStack {
                VStack(alignment: .leading) {
                    Text("処理時間")
                        .font(.caption)
                        .foregroundStyle(colors.onSurfaceVariant)
                    Text(String(format: "%.2f秒", imageResult.processingTime))
                        .fontWeight(.semibold)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("処理時間")
                        .font(.caption)
                        .foregroundStyle(colors.onSurfaceVariant)
                    if let ocrTime = ocrResult.ocrTime {
                        Text(String(format: "%.2f秒 (OCR: %.2f秒)", ocrResult.processingTime, ocrTime))
                            .fontWeight(.semibold)
                    } else {
                        Text(String(format: "%.2f秒", ocrResult.processingTime))
                            .fontWeight(.semibold)
                    }
                }
            }

            // 判定一致
            let sameResult = imageResult.isReceipt == ocrResult.isReceipt
            HStack {
                Image(systemName: sameResult ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(sameResult ? colors.primary : colors.error)
                Text(sameResult ? "判定一致" : "判定不一致")
            }
        }
        .padding()
        .background(colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 2)
    }

    private func resultBadge(title: String, result: AnalysisResult, showOCRButton: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(colors.onSurfaceVariant)
            Text(result.isReceipt ? "レシート" : "非レシート")
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(result.isReceipt ? colors.primary : colors.error)
                .foregroundStyle(.white)
                .clipShape(Capsule())

            // 矩形未検出の場合は理由を表示
            if let rectangleDetected = result.rectangleDetected, !rectangleDetected {
                Text("矩形未検出")
                    .font(.caption2)
                    .foregroundStyle(colors.error)
            }

            if showOCRButton {
                Button {
                    showOCRTextSheet = true
                } label: {
                    Label("OCRテキスト", systemImage: "doc.text")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .disabled(result.ocrText == nil)
            }
        }
    }

    // MARK: - Actions

    private func analyze() async {
        guard let imageData = capturedImageData else { return }

        isAnalyzing = true
        errorMessage = nil

        do {
            let results = try await ReceiptAnalysisService.shared.analyzeWithBothMethods(imageData)
            imageResult = results.imageResult
            ocrResult = results.ocrResult
        } catch {
            errorMessage = error.localizedDescription
        }

        isAnalyzing = false
    }
}

#Preview {
    ContentView()
        .theme(ThemeProvider())
}
