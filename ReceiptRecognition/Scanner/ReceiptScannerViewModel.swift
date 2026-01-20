//
//  ReceiptScannerViewModel.swift
//  ReceiptRecognition
//
//  Created by Claude on 2026/01/20.
//

import SwiftUI
import AVFoundation
import Vision
import CoreImage
import Combine

// MARK: - Captured Data

/// キャプチャされた画像データ
struct CapturedData: Identifiable {
    let id = UUID()
    let image: UIImage
    let imageData: Data
}

// MARK: - Receipt Scanner ViewModel

@MainActor
class ReceiptScannerViewModel: NSObject, ObservableObject {
    // MARK: - Published Properties

    @Published var detectedRectangle: VNRectangleObservation?
    @Published var stability: Double = 0.0
    @Published var statusMessage = "レシートをかざしてください"
    @Published var capturedData: CapturedData?

    // MARK: - Camera Properties

    let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let processingQueue = DispatchQueue(label: "com.receiptrecognition.scanner")

    // MARK: - Stability Tracking

    private var lastRectangle: VNRectangleObservation?
    private var stableStartTime: Date?
    private var referenceRectangle: VNRectangleObservation?  // 安定判定の基準となる矩形
    private let stabilityThreshold: TimeInterval = 1.0  // 1秒安定でキャプチャ
    private let positionThreshold: CGFloat = 0.08  // 手ブレ許容範囲（8%）- 基準からの許容ずれ

    // MARK: - State

    private var isScanning = false
    private var hasTriggeredCapture = false

    // MARK: - Initialization

    override init() {
        super.init()
        setupCamera()
    }

    // MARK: - Camera Setup

    private func setupCamera() {
        captureSession.sessionPreset = .high

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            statusMessage = "カメラにアクセスできません"
            return
        }

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        // ビデオの向きを設定
        if let connection = videoOutput.connection(with: .video) {
            connection.videoRotationAngle = 90
        }
    }

    // MARK: - Scanning Control

    func startScanning() {
        guard !isScanning else { return }
        isScanning = true
        hasTriggeredCapture = false

        processingQueue.async { [weak self] in
            self?.captureSession.startRunning()
        }
    }

    func stopScanning() {
        guard isScanning else { return }
        isScanning = false

        processingQueue.async { [weak self] in
            self?.captureSession.stopRunning()
        }
    }

    func resetForNextScan() {
        capturedData = nil
        hasTriggeredCapture = false
        stability = 0.0
        stableStartTime = nil
        lastRectangle = nil
        referenceRectangle = nil
        detectedRectangle = nil
        statusMessage = "レシートをかざしてください"

        // カメラを再開
        startScanning()
    }

    // MARK: - Rectangle Detection

    nonisolated private func detectRectangleAsync(in pixelBuffer: CVPixelBuffer) {
        let request = VNDetectRectanglesRequest { [weak self] request, error in
            guard let self = self else { return }

            if let error = error {
                print("Rectangle detection error: \(error)")
                return
            }

            let observations = request.results as? [VNRectangleObservation]
            let bestObservation = observations?.max(by: { $0.confidence < $1.confidence })

            Task { @MainActor in
                self.handleRectangleDetection(bestObservation, pixelBuffer: pixelBuffer)
            }
        }

        request.minimumConfidence = 0.5
        request.maximumObservations = 5
        request.minimumAspectRatio = 0.3
        request.maximumAspectRatio = 1.0

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([request])
    }

    private func handleRectangleDetection(_ observation: VNRectangleObservation?, pixelBuffer: CVPixelBuffer) {
        guard !hasTriggeredCapture else { return }

        if let observation = observation {
            detectedRectangle = observation

            // 基準矩形がない場合は設定
            if referenceRectangle == nil {
                referenceRectangle = observation
                stableStartTime = Date()
            }

            // 基準矩形からのずれをチェック（手ブレ許容）
            if let reference = referenceRectangle, isWithinTolerance(current: observation, reference: reference) {
                // 許容範囲内 → 安定とみなす
                let elapsed = Date().timeIntervalSince(stableStartTime!)
                stability = min(elapsed / stabilityThreshold, 1.0)

                if elapsed >= stabilityThreshold {
                    // 安定時間達成 → キャプチャ
                    triggerCapture(pixelBuffer: pixelBuffer, rectangle: observation)
                }
            } else {
                // 大きくずれた → 基準をリセット
                referenceRectangle = observation
                stableStartTime = Date()
                stability = 0.0
            }

            lastRectangle = observation
        } else {
            // 矩形なし
            detectedRectangle = nil
            lastRectangle = nil
            referenceRectangle = nil
            stableStartTime = nil
            stability = 0.0
        }
    }

    /// 現在の矩形が基準矩形の許容範囲内かチェック（手ブレ許容）
    private func isWithinTolerance(current: VNRectangleObservation, reference: VNRectangleObservation) -> Bool {
        let corners = [
            (current.topLeft, reference.topLeft),
            (current.topRight, reference.topRight),
            (current.bottomLeft, reference.bottomLeft),
            (current.bottomRight, reference.bottomRight)
        ]

        for (curr, ref) in corners {
            let dx = abs(curr.x - ref.x)
            let dy = abs(curr.y - ref.y)
            // 基準からの距離が許容範囲を超えたらfalse
            if dx > positionThreshold || dy > positionThreshold {
                return false
            }
        }

        return true
    }

    // MARK: - Capture

    private func triggerCapture(pixelBuffer: CVPixelBuffer, rectangle: VNRectangleObservation) {
        guard !hasTriggeredCapture else { return }
        hasTriggeredCapture = true

        // カメラを停止
        stopScanning()

        // 画像を切り出し
        let imageData = extractRectangle(from: pixelBuffer, observation: rectangle)

        if let image = UIImage(data: imageData) {
            capturedData = CapturedData(image: image, imageData: imageData)
        }
    }

    private func extractRectangle(from pixelBuffer: CVPixelBuffer, observation: VNRectangleObservation) -> Data {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let imageSize = ciImage.extent.size

        // 座標変換
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

        // 透視変換
        let perspectiveCorrection = CIFilter(name: "CIPerspectiveCorrection")!
        perspectiveCorrection.setValue(ciImage, forKey: kCIInputImageKey)
        perspectiveCorrection.setValue(CIVector(cgPoint: topLeft), forKey: "inputTopLeft")
        perspectiveCorrection.setValue(CIVector(cgPoint: topRight), forKey: "inputTopRight")
        perspectiveCorrection.setValue(CIVector(cgPoint: bottomLeft), forKey: "inputBottomLeft")
        perspectiveCorrection.setValue(CIVector(cgPoint: bottomRight), forKey: "inputBottomRight")

        let context = CIContext()

        if let outputImage = perspectiveCorrection.outputImage,
           let cgImage = context.createCGImage(outputImage, from: outputImage.extent) {
            let uiImage = UIImage(cgImage: cgImage)
            return uiImage.jpegData(compressionQuality: 0.8) ?? Data()
        }

        // フォールバック: 元画像をそのまま返す
        if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
            let uiImage = UIImage(cgImage: cgImage)
            return uiImage.jpegData(compressionQuality: 0.8) ?? Data()
        }

        return Data()
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension ReceiptScannerViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // 矩形検出を実行（nonisolated）
        detectRectangleAsync(in: pixelBuffer)
    }
}
