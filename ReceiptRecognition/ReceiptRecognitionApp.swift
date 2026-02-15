import SwiftUI
import DesignSystem

@main
struct ReceiptRecognitionApp: App {
    @State private var themeProvider = ThemeProvider()

    private let scanningService: any ReceiptScanningService
    private let cameraService: any ReceiptCameraService
    private let extractionService: (any ReceiptExtractionService)?

    init() {
        let scanning = ReceiptScanningServiceImpl()
        self.scanningService = scanning
        // CameraService は ScanningService の矩形検出サービスを共有
        self.cameraService = ReceiptCameraServiceImpl(
            rectangleDetectionService: scanning.rectangleDetectionService
        )
        // Gemini API キーが設定されていれば抽出サービスを初期化
        if let apiKey = Bundle.main.object(forInfoDictionaryKey: "GeminiAPIKey") as? String,
           !apiKey.isEmpty, !apiKey.contains("$(") {
            self.extractionService = GeminiReceiptExtractionService(apiKey: apiKey)
        } else {
            self.extractionService = nil
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .theme(themeProvider)
                .environment(\.scanningService, scanningService)
                .environment(\.cameraService, cameraService)
                .environment(\.extractionService, extractionService)
        }
    }
}
