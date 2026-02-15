import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Vision

// MARK: - Result

/// レシートスキャン結果
struct ReceiptScanResult: Sendable {
    /// 認識されたテキスト
    let text: String
    /// 認識の信頼度（0.0-1.0）
    let confidence: Float?
    /// 矩形が検出されたか
    let rectangleDetected: Bool
}

// MARK: - Error

/// レシートスキャンエラー
enum ReceiptScanError: Error, LocalizedError {
    case invalidImage
    case scanFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            "画像の読み込みに失敗しました"
        case .scanFailed(let message):
            "レシートの読み取りに失敗しました: \(message)"
        }
    }
}

// MARK: - Protocol

/// レシートスキャンサービス
/// 矩形検出、透視変換補正、OCRを組み合わせてレシートを読み取る
protocol ReceiptScanningService: Sendable {
    /// カメラプレビュー用の矩形検出サービス
    var rectangleDetectionService: RectangleDetectionService { get }

    /// 画像データからレシートを読み取る
    func scan(from imageData: Data) async throws -> ReceiptScanResult
}

// MARK: - Implementation

final class ReceiptScanningServiceImpl: ReceiptScanningService, @unchecked Sendable {
    // MARK: - Receipt-Optimized Configuration

    /// レシート検出に最適化されたドキュメント検出設定
    static let receiptDetectionConfiguration = RectangleDetectionConfiguration(
        stabilityThreshold: 2.0,
        positionThreshold: 0.03,
        minimumStableFrameCount: 8,
        maximumRectangleAreaRatio: 0.85,
        minimumEdgeMargin: 0.02,
        minimumConfidence: 0.5,
        smoothingFactor: 0.3
    )

    /// レシートOCRに使用する言語設定
    private static let ocrRecognitionLanguages = ["ja-JP", "en-US"]

    // MARK: - Services

    let rectangleDetectionService: RectangleDetectionService

    private let ocrService: OCRService
    private let ciContext = CIContext()

    // MARK: - Initialization

    init() {
        rectangleDetectionService = RectangleDetectionServiceImpl(
            configuration: Self.receiptDetectionConfiguration
        )
        ocrService = OCRServiceImpl(
            recognitionLanguages: Self.ocrRecognitionLanguages
        )
    }

    /// 外部から矩形検出サービスを注入するイニシャライザ（共有インスタンス用）
    init(rectangleDetectionService: any RectangleDetectionService) {
        self.rectangleDetectionService = rectangleDetectionService
        ocrService = OCRServiceImpl(
            recognitionLanguages: Self.ocrRecognitionLanguages
        )
    }

    // MARK: - Public Methods

    func scan(from imageData: Data) async throws -> ReceiptScanResult {
        guard let cgImage = createCGImage(from: imageData) else {
            throw ReceiptScanError.invalidImage
        }

        // 1. 矩形検出
        let rectangle = rectangleDetectionService.detect(in: cgImage)

        // 2. 透視変換補正（矩形が検出された場合）
        let imageForOCR: CGImage
        let rectangleDetected: Bool

        if let rectangle {
            imageForOCR = perspectiveCorrect(cgImage: cgImage, observation: rectangle) ?? cgImage
            rectangleDetected = true
        } else {
            // フォールバック: 矩形なしでも生画像でOCR実行
            imageForOCR = cgImage
            rectangleDetected = false
        }

        // 3. OCR実行
        do {
            let ocrResult = try await ocrService.recognizeText(from: imageForOCR)
            return ReceiptScanResult(
                text: ocrResult.text,
                confidence: ocrResult.confidence,
                rectangleDetected: rectangleDetected
            )
        } catch {
            throw ReceiptScanError.scanFailed(error.localizedDescription)
        }
    }

    // MARK: - Private Methods

    /// 透視変換補正を適用して矩形領域を正面から見た画像に変換
    private func perspectiveCorrect(cgImage: CGImage, observation: VNRectangleObservation) -> CGImage? {
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

        // 型安全な透視変換フィルタを適用
        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = ciImage
        filter.topLeft = topLeft
        filter.topRight = topRight
        filter.bottomLeft = bottomLeft
        filter.bottomRight = bottomRight

        guard let outputImage = filter.outputImage else {
            return nil
        }

        return ciContext.createCGImage(outputImage, from: outputImage.extent)
    }

    private func createCGImage(from imageData: Data) -> CGImage? {
        guard let ciImage = CIImage(data: imageData) else {
            return nil
        }
        return ciContext.createCGImage(ciImage, from: ciImage.extent)
    }
}
