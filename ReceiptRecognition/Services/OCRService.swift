//
//  OCRService.swift
//  ReceiptRecognition
//
//  Created by Claude on 2026/01/20.
//

import Foundation
import Vision
import UIKit
import CoreImage

// MARK: - OCR Service

/// iOS標準のOCR機能を使用してテキストを抽出するサービス
actor OCRService {
    // MARK: - Singleton

    static let shared = OCRService()

    private init() {}

    // MARK: - OCR Result

    /// OCR結果（矩形検出情報付き）
    struct OCRResult {
        /// 抽出されたテキスト
        let text: String
        /// 矩形が検出されたかどうか
        let rectangleDetected: Bool
        /// 検出された矩形の信頼度（0-1）
        let confidence: Float?
    }

    // MARK: - Public Methods

    /// 画像から矩形を検出し、その領域内のテキストを抽出
    ///
    /// - Parameter imageData: 解析する画像データ
    /// - Returns: OCR結果（矩形検出情報付き）
    func recognizeTextWithRectangleDetection(from imageData: Data) async throws -> OCRResult {
        guard let image = UIImage(data: imageData), let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }

        // 1. 矩形検出
        let rectangleResult = try await detectRectangle(in: cgImage)

        guard let observation = rectangleResult else {
            // 矩形が検出されなかった場合
            return OCRResult(text: "", rectangleDetected: false, confidence: nil)
        }

        // 2. 検出した矩形で画像を切り出し・透視変換補正
        let correctedImage = perspectiveCorrect(cgImage: cgImage, observation: observation)

        // 3. 補正した画像でOCR実行
        let texts = try await performOCR(on: correctedImage)
        let combinedText = texts.joined(separator: "\n")

        return OCRResult(
            text: combinedText,
            rectangleDetected: true,
            confidence: observation.confidence
        )
    }

    /// 画像データからテキストを抽出し、結合して返す（従来互換）
    ///
    /// - Parameter imageData: 解析する画像データ
    /// - Returns: 改行で結合されたテキスト
    func recognizeTextAsString(from imageData: Data) async throws -> String {
        let result = try await recognizeTextWithRectangleDetection(from: imageData)
        return result.text
    }

    // MARK: - Private Methods

    /// 矩形検出
    private func detectRectangle(in cgImage: CGImage) async throws -> VNRectangleObservation? {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectRectanglesRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: OCRError.rectangleDetectionFailed(error))
                    return
                }

                // 最も信頼度の高い矩形を取得
                let observations = request.results as? [VNRectangleObservation]
                let bestObservation = observations?.max(by: { $0.confidence < $1.confidence })

                continuation.resume(returning: bestObservation)
            }

            // 矩形検出の設定
            request.minimumConfidence = 0.5
            request.maximumObservations = 5
            request.minimumAspectRatio = 0.3  // レシートは縦長なので
            request.maximumAspectRatio = 1.0

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: OCRError.rectangleDetectionFailed(error))
            }
        }
    }

    /// 透視変換補正して矩形領域を切り出し
    private func perspectiveCorrect(cgImage: CGImage, observation: VNRectangleObservation) -> CGImage {
        let ciImage = CIImage(cgImage: cgImage)
        let imageSize = ciImage.extent.size

        // Vision座標系（左下原点、0-1正規化）から画像座標系に変換
        let topLeft = CGPoint(
            x: observation.topLeft.x * imageSize.width,
            y: observation.topLeft.y * imageSize.height
        )
        let topRight = CGPoint(
            x: observation.topRight.x * imageSize.width,
            y: observation.topRight.y * imageSize.height
        )
        let bottomLeft = CGPoint(
            x: observation.bottomLeft.x * imageSize.width,
            y: observation.bottomLeft.y * imageSize.height
        )
        let bottomRight = CGPoint(
            x: observation.bottomRight.x * imageSize.width,
            y: observation.bottomRight.y * imageSize.height
        )

        // 透視変換フィルタを適用
        let perspectiveCorrection = CIFilter(name: "CIPerspectiveCorrection")!
        perspectiveCorrection.setValue(ciImage, forKey: kCIInputImageKey)
        perspectiveCorrection.setValue(CIVector(cgPoint: topLeft), forKey: "inputTopLeft")
        perspectiveCorrection.setValue(CIVector(cgPoint: topRight), forKey: "inputTopRight")
        perspectiveCorrection.setValue(CIVector(cgPoint: bottomLeft), forKey: "inputBottomLeft")
        perspectiveCorrection.setValue(CIVector(cgPoint: bottomRight), forKey: "inputBottomRight")

        guard let outputImage = perspectiveCorrection.outputImage else {
            return cgImage
        }

        let context = CIContext()
        guard let correctedCGImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            return cgImage
        }

        return correctedCGImage
    }

    /// OCR実行
    private func performOCR(on cgImage: CGImage) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: OCRError.recognitionFailed(error))
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let texts = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }

                continuation.resume(returning: texts)
            }

            // 日本語認識を有効化
            request.recognitionLanguages = ["ja-JP", "en-US"]
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: OCRError.recognitionFailed(error))
            }
        }
    }
}

// MARK: - OCR Error

/// OCRエラー
enum OCRError: Error, LocalizedError {
    /// 無効な画像
    case invalidImage

    /// 矩形検出失敗
    case rectangleDetectionFailed(Error)

    /// 認識失敗
    case recognitionFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "無効な画像です"
        case .rectangleDetectionFailed(let error):
            return "矩形検出に失敗しました: \(error.localizedDescription)"
        case .recognitionFailed(let error):
            return "テキスト認識に失敗しました: \(error.localizedDescription)"
        }
    }
}
