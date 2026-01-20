//
//  ReceiptAnalysisView.swift
//  ReceiptRecognition
//
//  Created by Claude on 2026/01/20.
//

import SwiftUI
import Combine
import Vision
import DesignSystem

/// 解析画面
struct ReceiptAnalysisView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorPalette) private var colors

    let capturedImage: UIImage
    @StateObject private var viewModel: ReceiptAnalysisViewModel

    init(capturedImage: UIImage, imageData: Data) {
        self.capturedImage = capturedImage
        self._viewModel = StateObject(wrappedValue: ReceiptAnalysisViewModel(imageData: imageData))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // キャプチャした画像
                    Image(uiImage: capturedImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(radius: 4)

                    // 解析状態
                    analysisStatusView

                    // 結果表示
                    if let result = viewModel.result {
                        resultView(result)
                    }
                }
                .padding()
            }
            .navigationTitle("解析結果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await viewModel.analyze()
        }
    }

    // MARK: - Analysis Status View

    @ViewBuilder
    private var analysisStatusView: some View {
        switch viewModel.state {
        case .idle:
            EmptyView()

        case .recognizingText:
            HStack(spacing: 12) {
                ProgressView()
                Text("テキスト認識中...")
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(colors.surfaceVariant)
            .clipShape(RoundedRectangle(cornerRadius: 8))

        case .analyzingWithLLM:
            HStack(spacing: 12) {
                ProgressView()
                Text("AI解析中...")
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(colors.surfaceVariant)
            .clipShape(RoundedRectangle(cornerRadius: 8))

        case .completed:
            EmptyView()

        case .error(let message):
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(colors.error)
                Text(message)
                    .foregroundStyle(colors.error)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(colors.error.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Result View

    private func resultView(_ result: AnalysisResult) -> some View {
        VStack(spacing: 16) {
            // 判定結果
            HStack {
                Image(systemName: result.isReceipt ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(result.isReceipt ? colors.primary : colors.error)

                VStack(alignment: .leading) {
                    Text(result.isReceipt ? "レシート" : "非レシート")
                        .font(.title2)
                        .fontWeight(.bold)

                    if let date = result.date {
                        Text("日付: \(date)")
                            .foregroundStyle(colors.onSurfaceVariant)
                    }
                }

                Spacer()
            }
            .padding()
            .background(colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // 詳細情報
            VStack(alignment: .leading, spacing: 8) {
                detailRow(label: "トークン数", value: "\(result.totalTokens)")

                if let ocrTime = result.ocrTime {
                    detailRow(label: "OCR時間", value: String(format: "%.2f秒", ocrTime))
                }

                detailRow(label: "合計処理時間", value: String(format: "%.2f秒", result.processingTime))
            }
            .padding()
            .background(colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // OCRテキスト表示ボタン
            if let ocrText = result.ocrText, !ocrText.isEmpty {
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
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(colors.onSurfaceVariant)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

// MARK: - ViewModel

@MainActor
class ReceiptAnalysisViewModel: ObservableObject {
    enum State {
        case idle
        case recognizingText
        case analyzingWithLLM
        case completed
        case error(String)
    }

    @Published var state: State = .idle
    @Published var result: AnalysisResult?

    private let imageData: Data

    init(imageData: Data) {
        self.imageData = imageData
    }

    func analyze() async {
        state = .recognizingText

        do {
            let startTime = Date()
            let ocrStartTime = Date()

            // OCR実行
            let ocrText = try await performOCR()
            let ocrTime = Date().timeIntervalSince(ocrStartTime)

            guard !ocrText.isEmpty else {
                result = AnalysisResult(
                    method: .ocrText,
                    isReceipt: false,
                    date: nil,
                    inputTokens: 0,
                    outputTokens: 0,
                    processingTime: Date().timeIntervalSince(startTime),
                    ocrTime: ocrTime,
                    ocrText: nil,
                    rectangleDetected: true
                )
                state = .completed
                return
            }

            // LLM解析
            state = .analyzingWithLLM
            let llmResult = try await ReceiptAnalysisService.shared.analyzeText(ocrText)

            result = AnalysisResult(
                method: .ocrText,
                isReceipt: llmResult.isReceipt,
                date: llmResult.date,
                inputTokens: llmResult.inputTokens,
                outputTokens: llmResult.outputTokens,
                processingTime: Date().timeIntervalSince(startTime),
                ocrTime: ocrTime,
                ocrText: ocrText,
                rectangleDetected: true
            )
            state = .completed

        } catch {
            state = .error(error.localizedDescription)
        }
    }

    private func performOCR() async throws -> String {
        guard let image = UIImage(data: imageData), let cgImage = image.cgImage else {
            return ""
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }

                let texts = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: texts.joined(separator: "\n"))
            }

            request.recognitionLanguages = ["ja-JP", "en-US"]
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
