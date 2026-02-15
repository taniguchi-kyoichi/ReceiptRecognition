import CoreImage
import Foundation
import os
@preconcurrency import Vision

// MARK: - Frame Detection Result

/// フレーム検出結果
struct FrameDetectionResult: Sendable {
    /// UI表示用のスムージング済み座標
    let smoothedCorners: RectangleCorners?
    /// 矩形の安定度（0.0-1.0）
    let stability: Double
    /// 安定度が閾値を超えたか
    let shouldAutoCapture: Bool
}

// MARK: - Configuration

/// 矩形検出の設定値
struct RectangleDetectionConfiguration: Sendable {
    /// 安定と判定するまでの時間（秒）
    var stabilityThreshold: TimeInterval
    /// 0.0-1.0 の正規化座標
    var positionThreshold: CGFloat
    /// 自動撮影に必要な最小連続安定フレーム数
    var minimumStableFrameCount: Int
    /// これ以上大きい矩形は画面全体とみなして除外
    var maximumRectangleAreaRatio: CGFloat
    /// 0.0-0.5 の正規化座標
    var minimumEdgeMargin: CGFloat
    /// 0.0-1.0
    var minimumConfidence: Float
    /// 0.0 に近いほど滑らか、1.0 で無効
    var smoothingFactor: CGFloat

    init(
        stabilityThreshold: TimeInterval,
        positionThreshold: CGFloat,
        minimumStableFrameCount: Int,
        maximumRectangleAreaRatio: CGFloat,
        minimumEdgeMargin: CGFloat,
        minimumConfidence: Float,
        smoothingFactor: CGFloat
    ) {
        precondition(stabilityThreshold > 0, "stabilityThreshold must be > 0")
        self.stabilityThreshold = stabilityThreshold
        self.positionThreshold = positionThreshold
        self.minimumStableFrameCount = minimumStableFrameCount
        self.maximumRectangleAreaRatio = maximumRectangleAreaRatio
        self.minimumEdgeMargin = minimumEdgeMargin
        self.minimumConfidence = minimumConfidence
        self.smoothingFactor = smoothingFactor
    }
}

// MARK: - RectangleCorners + VNRectangleObservation

private extension RectangleCorners {
    init(_ observation: VNRectangleObservation) {
        self.init(
            topLeft: observation.topLeft,
            topRight: observation.topRight,
            bottomLeft: observation.bottomLeft,
            bottomRight: observation.bottomRight
        )
    }

    /// 指数移動平均によるスムージング
    func smoothed(with observation: VNRectangleObservation, factor alpha: CGFloat) -> RectangleCorners {
        func smooth(_ current: CGPoint, _ previous: CGPoint) -> CGPoint {
            CGPoint(
                x: alpha * current.x + (1 - alpha) * previous.x,
                y: alpha * current.y + (1 - alpha) * previous.y
            )
        }
        return RectangleCorners(
            topLeft: smooth(observation.topLeft, topLeft),
            topRight: smooth(observation.topRight, topRight),
            bottomLeft: smooth(observation.bottomLeft, bottomLeft),
            bottomRight: smooth(observation.bottomRight, bottomRight)
        )
    }
}

// MARK: - Protocol

/// カメラフレームや静止画から矩形を検出するサービス
protocol RectangleDetectionService: AnyObject, Sendable {
    /// カメラフレームを処理し、スムージング・安定度追跡付きの検出結果を返す
    func process(_ pixelBuffer: CVPixelBuffer) -> FrameDetectionResult
    /// 静止画から矩形を単発検出する（状態を持たない）
    func detect(in cgImage: CGImage) -> VNRectangleObservation?
    /// 安定度追跡の内部状態をリセットする
    func reset()
}

// MARK: - Implementation

final class RectangleDetectionServiceImpl: RectangleDetectionService, @unchecked Sendable {
    private let configuration: RectangleDetectionConfiguration

    private struct State {
        /// 前フレームの矩形（安定判定の基準）
        var referenceRectangle: VNRectangleObservation?
        /// 安定状態が始まった時刻
        var stableStartTime: Date?
        /// 連続で安定と判定されたフレーム数
        var consecutiveStableFrameCount: Int = 0
        /// EMA スムージング済みの矩形座標
        var smoothedCorners: RectangleCorners?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    init(configuration: RectangleDetectionConfiguration) {
        self.configuration = configuration
    }

    func process(_ pixelBuffer: CVPixelBuffer) -> FrameDetectionResult {
        let observation = performDocumentDetection(
            handler: VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        )

        return state.withLock { state in
            guard let observation else {
                state = State()
                return FrameDetectionResult(
                    smoothedCorners: nil,
                    stability: 0,
                    shouldAutoCapture: false
                )
            }

            if let existing = state.smoothedCorners {
                state.smoothedCorners = existing.smoothed(with: observation, factor: configuration.smoothingFactor)
            } else {
                state.smoothedCorners = RectangleCorners(observation)
            }

            var stability: Double = 0
            var shouldAutoCapture = false

            if let reference = state.referenceRectangle {
                let isStable = isRectangleStable(observation, reference: reference)

                if isStable {
                    state.consecutiveStableFrameCount += 1

                    // 連続安定フレーム数が閾値を超えたら時間計測を開始
                    if state.consecutiveStableFrameCount >= configuration.minimumStableFrameCount {
                        if state.stableStartTime == nil {
                            state.stableStartTime = Date()
                        }

                        let stableDuration = Date().timeIntervalSince(state.stableStartTime!)
                        stability = min(stableDuration / configuration.stabilityThreshold, 1.0)

                        if stableDuration >= configuration.stabilityThreshold {
                            shouldAutoCapture = true
                        }
                    }
                } else {
                    state.stableStartTime = nil
                    state.consecutiveStableFrameCount = 0
                    stability = 0
                }
            }

            state.referenceRectangle = observation

            return FrameDetectionResult(
                smoothedCorners: state.smoothedCorners,
                stability: stability,
                shouldAutoCapture: shouldAutoCapture
            )
        }
    }

    func reset() {
        state.withLock { $0 = State() }
    }

    func detect(in cgImage: CGImage) -> VNRectangleObservation? {
        performDocumentDetection(
            handler: VNImageRequestHandler(cgImage: cgImage, options: [:])
        )
    }

    // MARK: - Private Methods

    private func performDocumentDetection(handler: VNImageRequestHandler) -> VNRectangleObservation? {
        var detectedObservation: VNRectangleObservation?

        let request = VNDetectDocumentSegmentationRequest { request, _ in
            detectedObservation = request.results?.first as? VNRectangleObservation
        }

        try? handler.perform([request])

        guard let observation = detectedObservation,
              isValidRectangle(observation) else {
            return nil
        }

        return observation
    }

    private func isRectangleStable(
        _ current: VNRectangleObservation,
        reference: VNRectangleObservation
    ) -> Bool {
        let corners = [
            (current.topLeft, reference.topLeft),
            (current.topRight, reference.topRight),
            (current.bottomLeft, reference.bottomLeft),
            (current.bottomRight, reference.bottomRight)
        ]

        for (currentCorner, referenceCorner) in corners {
            let dx = abs(currentCorner.x - referenceCorner.x)
            let dy = abs(currentCorner.y - referenceCorner.y)
            if dx > configuration.positionThreshold || dy > configuration.positionThreshold {
                return false
            }
        }

        return true
    }

    private func isValidRectangle(_ observation: VNRectangleObservation) -> Bool {
        if observation.confidence < configuration.minimumConfidence {
            return false
        }

        let area = calculateRectangleArea(observation)
        if area > configuration.maximumRectangleAreaRatio {
            return false
        }

        let margin = configuration.minimumEdgeMargin
        let corners = [
            observation.topLeft,
            observation.topRight,
            observation.bottomLeft,
            observation.bottomRight
        ]

        for corner in corners {
            if corner.x < margin || corner.x > (1.0 - margin) ||
                corner.y < margin || corner.y > (1.0 - margin) {
                return false
            }
        }

        return true
    }

    /// ショーレースの公式で面積を計算（正規化座標系 0.0-1.0）
    private func calculateRectangleArea(_ observation: VNRectangleObservation) -> CGFloat {
        let corners = [
            observation.bottomLeft,
            observation.bottomRight,
            observation.topRight,
            observation.topLeft
        ]

        var area: CGFloat = 0
        for i in 0..<4 {
            let j = (i + 1) % 4
            area += corners[i].x * corners[j].y
            area -= corners[j].x * corners[i].y
        }

        return abs(area) / 2.0
    }
}
