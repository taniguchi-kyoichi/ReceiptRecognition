import SwiftUI
import AVFoundation

// MARK: - Receipt Scanner View

/// リアルタイムレシートスキャナービュー
struct ReceiptScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.cameraService) private var cameraService
    @State private var scanner = ReceiptScannerViewModel()

    var body: some View {
        ZStack {
            // カメラプレビュー
            CameraPreviewView(session: cameraService.captureSession)
                .ignoresSafeArea()

            // 矩形オーバーレイ
            if let corners = scanner.smoothedCorners {
                RectangleOverlayView(corners: corners, stability: scanner.stability)
            }

            // UI オーバーレイ
            VStack {
                // ヘッダー
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                    }
                    Spacer()
                }
                .padding()

                Spacer()

                // ステータス表示
                Text(scanner.statusMessage)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.6))
                    .clipShape(Capsule())

                // シャッターボタン
                Button {
                    scanner.manualCapture()
                } label: {
                    Circle()
                        .fill(.white)
                        .frame(width: 72, height: 72)
                        .overlay(
                            Circle()
                                .stroke(.white, lineWidth: 3)
                                .frame(width: 82, height: 82)
                        )
                }
                .disabled(scanner.capturedData != nil)
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            scanner.startScanning(cameraService: cameraService)
        }
        .onDisappear {
            scanner.stopScanning()
        }
        .fullScreenCover(item: $scanner.capturedData) { data in
            SaveConfirmView(capturedImage: data.image, imageData: data.imageData) {
                dismiss()
            }
            .onDisappear {
                scanner.resetForNextScan()
            }
        }
    }
}

// MARK: - Camera Preview View

/// AVCaptureSessionのプレビューを表示するUIViewRepresentable
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = CameraPreviewUIView()
        view.session = session
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

class CameraPreviewUIView: UIView {
    var session: AVCaptureSession? {
        didSet {
            guard let session = session else { return }
            previewLayer.session = session
        }
    }

    private var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.videoGravity = .resizeAspectFill
    }
}

// MARK: - Rectangle Overlay View

/// 検出された矩形のオーバーレイ（RectangleCorners ベース）
struct RectangleOverlayView: View {
    let corners: RectangleCorners
    let stability: Double // 0.0 - 1.0

    var body: some View {
        GeometryReader { geometry in
            let path = createPath(in: geometry.size)

            // 枠線
            path.stroke(
                stability >= 1.0 ? Color.green : Color.yellow,
                lineWidth: stability >= 1.0 ? 4 : 2
            )

            // 安定度インジケーター（角に表示）
            if stability > 0 && stability < 1.0 {
                let cornerPoints = getCorners(in: geometry.size)
                ForEach(0..<4, id: \.self) { index in
                    Circle()
                        .trim(from: 0, to: stability)
                        .stroke(Color.green, lineWidth: 3)
                        .frame(width: 20, height: 20)
                        .position(cornerPoints[index])
                }
            }
        }
    }

    private func createPath(in size: CGSize) -> Path {
        Path { path in
            // Vision座標系（左下原点）からSwiftUI座標系（左上原点）に変換
            let topLeft = CGPoint(
                x: corners.topLeft.x * size.width,
                y: (1 - corners.topLeft.y) * size.height
            )
            let topRight = CGPoint(
                x: corners.topRight.x * size.width,
                y: (1 - corners.topRight.y) * size.height
            )
            let bottomRight = CGPoint(
                x: corners.bottomRight.x * size.width,
                y: (1 - corners.bottomRight.y) * size.height
            )
            let bottomLeft = CGPoint(
                x: corners.bottomLeft.x * size.width,
                y: (1 - corners.bottomLeft.y) * size.height
            )

            path.move(to: topLeft)
            path.addLine(to: topRight)
            path.addLine(to: bottomRight)
            path.addLine(to: bottomLeft)
            path.closeSubpath()
        }
    }

    private func getCorners(in size: CGSize) -> [CGPoint] {
        [
            CGPoint(x: corners.topLeft.x * size.width, y: (1 - corners.topLeft.y) * size.height),
            CGPoint(x: corners.topRight.x * size.width, y: (1 - corners.topRight.y) * size.height),
            CGPoint(x: corners.bottomRight.x * size.width, y: (1 - corners.bottomRight.y) * size.height),
            CGPoint(x: corners.bottomLeft.x * size.width, y: (1 - corners.bottomLeft.y) * size.height)
        ]
    }
}

#Preview {
    ReceiptScannerView()
}
