import AVFoundation
import SwiftUI

// MARK: - Captured Data

/// キャプチャされた画像データ
struct CapturedData: Identifiable {
    let id = UUID()
    let image: UIImage
    let imageData: Data
}

// MARK: - Receipt Scanner ViewModel

@Observable
@MainActor
final class ReceiptScannerViewModel {
    // MARK: - Observable Properties

    var smoothedCorners: RectangleCorners?
    var stability: Double = 0.0
    var statusMessage = "レシートをかざしてください"
    var capturedData: CapturedData?
    var isFlashOn = false

    // MARK: - Private State

    private var cameraService: (any ReceiptCameraService)?
    /// for-await ループ。View の生存期間中ずっと走り続ける
    private var scanningTask: Task<Void, Never>?
    /// キャプチャ中フラグ（ループは continue でスキップ）
    private var isCapturing = false

    // MARK: - Lifecycle

    /// カメラ起動 + 検出ループ開始（onAppear から呼ぶ）
    func startScanning(cameraService: any ReceiptCameraService) {
        self.cameraService = cameraService
        isCapturing = false
        capturedData = nil
        smoothedCorners = nil
        stability = 0.0
        statusMessage = "レシートをかざしてください"

        let camera = cameraService
        Task {
            await camera.resetDetectionState()
            await camera.startRunning()
        }

        // 検出ループは一度だけ作成（View のライフサイクル中ずっと走る）
        guard scanningTask == nil else { return }
        scanningTask = Task { [weak self] in
            for await result in await camera.detectionResults {
                guard !Task.isCancelled else { break }
                guard let self else { break }

                // キャプチャ中・レビュー中はフレームをスキップ（ループは止めない）
                guard !isCapturing else { continue }

                handleDetectionResult(result)
            }
        }
    }

    /// カメラ停止 + 検出ループ破棄（onDisappear から呼ぶ）
    func stopScanning() {
        scanningTask?.cancel()
        scanningTask = nil
        let camera = cameraService
        Task {
            await camera?.stopRunning()
        }
    }

    /// 撮り直し時のリセット（fullScreenCover の onDisappear から呼ぶ）
    func resetForNextScan() {
        capturedData = nil
        isCapturing = false
        smoothedCorners = nil
        stability = 0.0
        statusMessage = "レシートをかざしてください"

        // 検出状態リセット + カメラ再開（ループは走り続けているので自然に再開）
        let camera = cameraService
        Task {
            guard let camera else { return }
            await camera.resetDetectionState()
            await camera.startRunning()
        }
    }

    // MARK: - Manual Capture

    /// シャッターボタンによる手動キャプチャ
    func manualCapture() {
        guard !isCapturing else { return }

        // 矩形が検出されていなければエラーを表示して撮影しない
        guard smoothedCorners != nil else {
            showTemporaryError("レシートが検出できません\n位置を調整してください")
            return
        }

        performCapture()
    }

    // MARK: - Flash

    func toggleFlash() {
        let camera = cameraService
        Task {
            if let camera {
                isFlashOn = await camera.toggleFlash()
            }
        }
    }

    // MARK: - Private Methods

    /// エラーメッセージを一時的に表示し、検出状態に応じて自動復帰する
    private func showTemporaryError(_ message: String) {
        statusMessage = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            // 2秒後、まだ同じエラーメッセージなら検出状態に応じて復帰
            guard statusMessage == message else { return }
            if smoothedCorners != nil {
                statusMessage = "レシートを検出しました"
            } else {
                statusMessage = "レシートをかざしてください"
            }
        }
    }

    private func handleDetectionResult(_ result: FrameDetectionResult) {
        smoothedCorners = result.smoothedCorners
        stability = result.stability

        // ステータスメッセージ更新
        if result.smoothedCorners != nil {
            if result.shouldAutoCapture {
                statusMessage = "キャプチャ中..."
            } else if result.stability > 0 {
                statusMessage = "そのまま固定してください..."
            } else {
                statusMessage = "レシートを検出しました"
            }
        } else {
            statusMessage = "レシートをかざしてください"
        }

        // 自動キャプチャ
        if result.shouldAutoCapture {
            performCapture()
        }
    }

    private func performCapture() {
        guard !isCapturing else { return }
        isCapturing = true
        statusMessage = "キャプチャ中..."

        Task { [weak self] in
            guard let self, let cameraService else { return }
            do {
                let data = try await cameraService.captureFrame()
                await cameraService.stopRunning()

                if let image = UIImage(data: data) {
                    capturedData = CapturedData(image: image, imageData: data)
                }
            } catch {
                statusMessage = "キャプチャに失敗しました"
                isCapturing = false
            }
        }
    }
}
