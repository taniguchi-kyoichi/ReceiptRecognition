import CoreImage
import Foundation
import Vision

// MARK: - Protocol

/// 画像からテキストを認識するサービス
protocol OCRService: Sendable {
    /// 画像データからテキストを認識する
    func recognizeText(from imageData: Data) async throws -> OCRResult

    /// CGImageからテキストを認識する
    func recognizeText(from cgImage: CGImage) async throws -> OCRResult
}

// MARK: - Result

/// OCR処理結果
struct OCRResult: Sendable {
    /// 認識されたテキスト
    let text: String
    /// 認識の信頼度（0.0-1.0）
    let confidence: Float?
}

// MARK: - Error

/// OCR処理エラー
enum OCRError: Error, LocalizedError {
    case invalidImage
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            "画像の読み込みに失敗しました"
        case .recognitionFailed(let message):
            "文字認識に失敗しました: \(message)"
        }
    }
}

// MARK: - Implementation

/// Vision frameworkを使用したOCR実装
actor OCRServiceImpl: OCRService {
    private let recognitionLanguages: [String]
    private let ciContext = CIContext()

    init(recognitionLanguages: [String]) {
        self.recognitionLanguages = recognitionLanguages
    }

    func recognizeText(from imageData: Data) async throws -> OCRResult {
        guard let cgImage = createCGImage(from: imageData) else {
            throw OCRError.invalidImage
        }
        return try await recognizeText(from: cgImage)
    }

    func recognizeText(from cgImage: CGImage) async throws -> OCRResult {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: OCRError.recognitionFailed(error.localizedDescription))
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: OCRResult(text: "", confidence: nil))
                    return
                }

                let recognizedStrings = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }

                let fullText = recognizedStrings.joined(separator: "\n")
                let avgConfidence: Float? = observations.isEmpty ? nil : {
                    let confidences = observations.compactMap { $0.topCandidates(1).first?.confidence }
                    return confidences.reduce(0, +) / Float(confidences.count)
                }()

                continuation.resume(returning: OCRResult(
                    text: fullText,
                    confidence: avgConfidence
                ))
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = self.recognitionLanguages
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: OCRError.recognitionFailed(error.localizedDescription))
            }
        }
    }

    // MARK: - Private Methods

    private func createCGImage(from imageData: Data) -> CGImage? {
        guard let ciImage = CIImage(data: imageData) else {
            return nil
        }
        return ciContext.createCGImage(ciImage, from: ciImage.extent)
    }
}
