import SwiftUI

// MARK: - Environment Keys

private struct ScanningServiceKey: EnvironmentKey {
    static let defaultValue: any ReceiptScanningService = ReceiptScanningServiceImpl()
}

private struct CameraServiceKey: EnvironmentKey {
    static let defaultValue: any ReceiptCameraService = ReceiptCameraServiceImpl(
        rectangleDetectionService: RectangleDetectionServiceImpl(
            configuration: ReceiptScanningServiceImpl.receiptDetectionConfiguration
        )
    )
}

private struct ExtractionServiceKey: EnvironmentKey {
    static let defaultValue: (any ReceiptExtractionService)? = nil
}

extension EnvironmentValues {
    var scanningService: any ReceiptScanningService {
        get { self[ScanningServiceKey.self] }
        set { self[ScanningServiceKey.self] = newValue }
    }

    var cameraService: any ReceiptCameraService {
        get { self[CameraServiceKey.self] }
        set { self[CameraServiceKey.self] = newValue }
    }

    var extractionService: (any ReceiptExtractionService)? {
        get { self[ExtractionServiceKey.self] }
        set { self[ExtractionServiceKey.self] = newValue }
    }
}
