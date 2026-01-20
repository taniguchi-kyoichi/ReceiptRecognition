//
//  ReceiptAnalysisService.swift
//  ReceiptRecognition
//
//  Created by Claude on 2026/01/20.
//

import Foundation
import UIKit
import LLMStructuredOutputs

// MARK: - Receipt Analysis Service

/// レシート解析サービス
///
/// Gemini 3.0 Flashを使用してレシートを解析します。
/// 画像入力とOCR+テキスト入力の2つの方式をサポートします。
actor ReceiptAnalysisService {
    // MARK: - Singleton

    static let shared = ReceiptAnalysisService()

    // MARK: - Properties

    /// 毎回最新のAPIキーでクライアントを取得
    private var client: GeminiClient {
        GeminiClient(apiKey: APIKeyStorage.geminiAPIKey)
    }

    // MARK: - Initializer

    private init() {}

    // MARK: - Public Methods

    /// 画像を直接解析（マルチモーダル方式）
    func analyzeWithImage(_ imageData: Data) async throws -> AnalysisResult {
        let startTime = Date()

        // 画像をリサイズ（最大1024px）
        let resizedData = Self.resizeImage(imageData, maxDimension: 1024)
        let imageContent = ImageContent.base64(resizedData, mediaType: .jpeg)
        let input = LLMInput("レシートか判定し日付を抽出。ボケ・ブレ・不鮮明な画像は非レシート扱い", images: [imageContent])

        let result: GenerationResult<ReceiptAnalysis> = try await client.generateWithUsage(
            input: input,
            model: .flash25Lite
        )

        return AnalysisResult(
            method: .imageInput,
            isReceipt: result.result.isReceipt,
            date: result.result.date,
            inputTokens: result.usage.inputTokens,
            outputTokens: result.usage.outputTokens,
            processingTime: Date().timeIntervalSince(startTime),
            ocrTime: nil,
            ocrText: nil,
            rectangleDetected: nil
        )
    }

    /// OCR + テキスト解析方式
    func analyzeWithOCR(_ imageData: Data) async throws -> AnalysisResult {
        let startTime = Date()

        // OCRでテキスト抽出（矩形検出付き、時間計測）
        let ocrStartTime = Date()
        let ocrResult = try await OCRService.shared.recognizeTextWithRectangleDetection(from: imageData)
        let ocrTime = Date().timeIntervalSince(ocrStartTime)

        // 矩形が検出されなければレシートではないと判定
        guard ocrResult.rectangleDetected else {
            return AnalysisResult(
                method: .ocrText,
                isReceipt: false,
                date: nil,
                inputTokens: 0,
                outputTokens: 0,
                processingTime: Date().timeIntervalSince(startTime),
                ocrTime: ocrTime,
                ocrText: nil,
                rectangleDetected: false
            )
        }

        // テキストが認識できなければレシートではないと判定
        guard !ocrResult.text.isEmpty else {
            return AnalysisResult(
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
        }

        let input = LLMInput("以下がレシートか判定し、日付を抽出:\n\(ocrResult.text)")

        let result: GenerationResult<ReceiptAnalysisFromText> = try await client.generateWithUsage(
            input: input,
            model: .flash25Lite
        )

        return AnalysisResult(
            method: .ocrText,
            isReceipt: result.result.isReceipt,
            date: result.result.date,
            inputTokens: result.usage.inputTokens,
            outputTokens: result.usage.outputTokens,
            processingTime: Date().timeIntervalSince(startTime),
            ocrTime: ocrTime,
            ocrText: ocrResult.text,
            rectangleDetected: true
        )
    }

    /// 両方の方式で解析して比較
    func analyzeWithBothMethods(_ imageData: Data) async throws -> (imageResult: AnalysisResult, ocrResult: AnalysisResult) {
        async let imageResult = analyzeWithImage(imageData)
        async let ocrResult = analyzeWithOCR(imageData)

        return try await (imageResult, ocrResult)
    }
}

// MARK: - Receipt Analysis Error

enum ReceiptAnalysisError: Error, LocalizedError {
    case missingAPIKey

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "GEMINI_API_KEYが設定されていません"
        }
    }
}

// MARK: - Image Resize Helper

extension ReceiptAnalysisService {
    /// 画像を指定の最大サイズにリサイズ
    static func resizeImage(_ data: Data, maxDimension: CGFloat) -> Data {
        guard let image = UIImage(data: data) else { return data }

        let size = image.size
        let scale: CGFloat

        if size.width > size.height {
            scale = size.width > maxDimension ? maxDimension / size.width : 1.0
        } else {
            scale = size.height > maxDimension ? maxDimension / size.height : 1.0
        }

        // リサイズ不要
        if scale >= 1.0 {
            return image.jpegData(compressionQuality: 0.8) ?? data
        }

        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }

        return resized.jpegData(compressionQuality: 0.8) ?? data
    }
}
