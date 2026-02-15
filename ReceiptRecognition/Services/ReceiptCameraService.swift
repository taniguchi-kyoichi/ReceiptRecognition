@preconcurrency import AVFoundation
import CoreImage
import Foundation
import UIKit

// MARK: - Protocol

protocol ReceiptCameraService: Sendable {
    /// カメラプレビュー用のセッション
    nonisolated var captureSession: AVCaptureSession { get }

    var detectionResults: AsyncStream<FrameDetectionResult> { get async }

    func startRunning() async

    func stopRunning() async

    /// 矩形検出の内部状態（安定度追跡）をリセットする
    func resetDetectionState() async

    func toggleFlash() async -> Bool

    /// シャッター音なしでビデオフレームをキャプチャする
    func captureFrame() async throws -> Data
}

// MARK: - Implementation

actor ReceiptCameraServiceImpl: NSObject, ReceiptCameraService {
    // MARK: - Constants

    private enum Config {
        /// レシート最小幅 (mm)
        static let minimumReceiptWidth: Float = 100
        /// プレビュー占有率
        static let previewFillPercentage: Float = 0.8
        /// JPEG圧縮品質（0.0-1.0）
        static let jpegCompressionQuality: CGFloat = 0.9
    }

    // MARK: - Properties

    nonisolated let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoOutputQueue = DispatchQueue(label: "receipt.camera.videoOutput")

    nonisolated let rectangleDetectionService: any RectangleDetectionService

    private var isSessionConfigured = false
    private var isFlashOn = false

    // MARK: - Frame Capture

    /// videoOutputQueue からのみ書き込み、captureFrame() からのみ読み取り
    nonisolated(unsafe) private var latestPixelBuffer: CVPixelBuffer?
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - AsyncStream

    private let detectionStream: AsyncStream<FrameDetectionResult>
    /// Continuation は Sendable なので nonisolated でアクセス可能
    nonisolated let detectionContinuation: AsyncStream<FrameDetectionResult>.Continuation

    // MARK: - Initialization

    init(rectangleDetectionService: any RectangleDetectionService) {
        self.rectangleDetectionService = rectangleDetectionService

        (detectionStream, detectionContinuation) = AsyncStream.makeStream(
            of: FrameDetectionResult.self
        )

        super.init()
    }

    // MARK: - Public Interface

    var detectionResults: AsyncStream<FrameDetectionResult> {
        detectionStream
    }

    // MARK: - Session Control

    func startRunning() {
        if !isSessionConfigured {
            setupCameraSession()
        }

        configureForScanning()

        captureSession.startRunning()
    }

    func stopRunning() {
        captureSession.stopRunning()
    }

    func resetDetectionState() {
        rectangleDetectionService.reset()
    }

    func toggleFlash() -> Bool {
        isFlashOn.toggle()

        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch else {
            return isFlashOn
        }

        do {
            try device.lockForConfiguration()
            device.torchMode = isFlashOn ? .on : .off
            device.unlockForConfiguration()
        } catch {
            // トーチ設定失敗は無視
        }

        return isFlashOn
    }

    /// videoZoomFactorが適用済みのフレームをキャプチャするため、プレビューと同じ領域になる
    func captureFrame() async throws -> Data {
        guard let pixelBuffer = latestPixelBuffer else {
            throw ReceiptCameraError.imageDataNotAvailable
        }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            throw ReceiptCameraError.imageDataNotAvailable
        }

        let uiImage = UIImage(cgImage: cgImage)
        guard let jpegData = uiImage.jpegData(compressionQuality: Config.jpegCompressionQuality) else {
            throw ReceiptCameraError.imageDataNotAvailable
        }

        return jpegData
    }

    // MARK: - Private Methods

    private func setupCameraSession() {
        captureSession.beginConfiguration()

        // 4K キャプチャ（フォールバック: 1080p）
        if captureSession.canSetSessionPreset(.hd4K3840x2160) {
            captureSession.sessionPreset = .hd4K3840x2160
        } else {
            captureSession.sessionPreset = .hd1920x1080
        }

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            captureSession.commitConfiguration()
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
        } catch {
            captureSession.commitConfiguration()
            return
        }

        // ビデオ出力の設定（矩形検出 + フレームキャプチャ用）
        videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        if let connection = videoOutput.connection(with: .video) {
            if #available(iOS 17.0, *) {
                connection.videoRotationAngle = 90
            } else {
                connection.videoOrientation = .portrait
            }
        }

        captureSession.commitConfiguration()
        isSessionConfigured = true
    }

    private func configureForScanning() {
        guard let input = captureSession.inputs.first as? AVCaptureDeviceInput else {
            return
        }

        let device = input.device

        do {
            try device.lockForConfiguration()

            device.videoZoomFactor = 1.0

            if device.isAutoFocusRangeRestrictionSupported {
                device.autoFocusRangeRestriction = .near
            }

            // 最小フォーカス距離に基づくズーム調整（WWDC21推奨方式）
            let minimumSubjectDistance = calculateMinimumSubjectDistance(
                fieldOfView: device.activeFormat.videoFieldOfView
            )

            let deviceMinimumFocusDistance = Float(device.minimumFocusDistance)
            if minimumSubjectDistance < deviceMinimumFocusDistance, deviceMinimumFocusDistance > 0 {
                let zoomFactor = deviceMinimumFocusDistance / minimumSubjectDistance
                let clampedZoomFactor = min(CGFloat(zoomFactor), device.maxAvailableVideoZoomFactor)
                device.videoZoomFactor = clampedZoomFactor
            }

            device.unlockForConfiguration()
        } catch {
            // フォーカス設定失敗は無視してスキャン続行
        }
    }

    /// 被写体がプレビューに収まるために必要な最小距離を計算（WWDC21方式）
    private func calculateMinimumSubjectDistance(fieldOfView: Float) -> Float {
        let radians = fieldOfView / 2.0 * .pi / 180.0
        let filledSize = Config.minimumReceiptWidth / Config.previewFillPercentage
        return filledSize / tan(radians)
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension ReceiptCameraServiceImpl: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from _: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        // videoOutputQueue 上で Vision 処理を実行（重い処理はバックグラウンドで完結）
        let frameResult = rectangleDetectionService.process(pixelBuffer)

        // nonisolated(unsafe) プロパティに直接アクセス（videoOutputQueue はシリアル）
        latestPixelBuffer = pixelBuffer
        detectionContinuation.yield(frameResult)
    }
}

// MARK: - Error

enum ReceiptCameraError: Error, LocalizedError {
    case imageDataNotAvailable

    var errorDescription: String? {
        switch self {
        case .imageDataNotAvailable:
            "画像データを取得できませんでした"
        }
    }
}
