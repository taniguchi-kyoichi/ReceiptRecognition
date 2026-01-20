//
//  OCRService.swift
//  ReceiptRecognition
//
//  Created by Claude on 2026/01/20.
//

import Foundation
import Vision
import UIKit

// MARK: - OCR Service

/// iOS標準のOCR機能を使用してテキストを抽出するサービス
actor OCRService {
    // MARK: - Singleton

    static let shared = OCRService()

    private init() {}

    // MARK: - Public Methods

    /// 画像からテキストを抽出
    ///
    /// - Parameter image: 解析する画像
    /// - Returns: 抽出されたテキストの配列
    func recognizeText(from image: UIImage) async throws -> [String] {
        guard let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
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

    /// 画像からテキストを抽出し、結合して返す
    ///
    /// - Parameter image: 解析する画像
    /// - Returns: 改行で結合されたテキスト
    func recognizeTextAsString(from image: UIImage) async throws -> String {
        let texts = try await recognizeText(from: image)
        return texts.joined(separator: "\n")
    }

    /// 画像データからテキストを抽出
    ///
    /// - Parameter imageData: 解析する画像データ
    /// - Returns: 抽出されたテキストの配列
    func recognizeText(from imageData: Data) async throws -> [String] {
        guard let image = UIImage(data: imageData) else {
            throw OCRError.invalidImage
        }
        return try await recognizeText(from: image)
    }

    /// 画像データからテキストを抽出し、結合して返す
    ///
    /// - Parameter imageData: 解析する画像データ
    /// - Returns: 改行で結合されたテキスト
    func recognizeTextAsString(from imageData: Data) async throws -> String {
        let texts = try await recognizeText(from: imageData)
        return texts.joined(separator: "\n")
    }
}

// MARK: - OCR Error

/// OCRエラー
enum OCRError: Error, LocalizedError {
    /// 無効な画像
    case invalidImage

    /// 認識失敗
    case recognitionFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "無効な画像です"
        case .recognitionFailed(let error):
            return "テキスト認識に失敗しました: \(error.localizedDescription)"
        }
    }
}
