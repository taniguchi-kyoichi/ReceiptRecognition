//
//  ReceiptScannerView.swift
//  ReceiptRecognition
//
//  Created by Claude on 2026/01/20.
//

import SwiftUI
import AVFoundation
import Vision

// MARK: - Receipt Scanner View

/// リアルタイムレシートスキャナービュー
struct ReceiptScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var scanner = ReceiptScannerViewModel()

    var body: some View {
        ZStack {
            // カメラプレビュー
            CameraPreviewView(session: scanner.captureSession)
                .ignoresSafeArea()

            // 矩形オーバーレイ
            if let rect = scanner.detectedRectangle {
                RectangleOverlayView(normalizedRect: rect, stability: scanner.stability)
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
                    .padding(.bottom, 50)
            }
        }
        .onAppear {
            scanner.startScanning()
        }
        .onDisappear {
            scanner.stopScanning()
        }
        .fullScreenCover(item: $scanner.capturedData) { data in
            ReceiptAnalysisView(capturedImage: data.image, imageData: data.imageData)
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

/// 検出された矩形のオーバーレイ
struct RectangleOverlayView: View {
    let normalizedRect: VNRectangleObservation
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
                let corners = getCorners(in: geometry.size)
                ForEach(0..<4, id: \.self) { index in
                    Circle()
                        .trim(from: 0, to: stability)
                        .stroke(Color.green, lineWidth: 3)
                        .frame(width: 20, height: 20)
                        .position(corners[index])
                }
            }
        }
    }

    private func createPath(in size: CGSize) -> Path {
        Path { path in
            // Vision座標系（左下原点）からSwiftUI座標系（左上原点）に変換
            let topLeft = CGPoint(
                x: normalizedRect.topLeft.x * size.width,
                y: (1 - normalizedRect.topLeft.y) * size.height
            )
            let topRight = CGPoint(
                x: normalizedRect.topRight.x * size.width,
                y: (1 - normalizedRect.topRight.y) * size.height
            )
            let bottomRight = CGPoint(
                x: normalizedRect.bottomRight.x * size.width,
                y: (1 - normalizedRect.bottomRight.y) * size.height
            )
            let bottomLeft = CGPoint(
                x: normalizedRect.bottomLeft.x * size.width,
                y: (1 - normalizedRect.bottomLeft.y) * size.height
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
            CGPoint(x: normalizedRect.topLeft.x * size.width, y: (1 - normalizedRect.topLeft.y) * size.height),
            CGPoint(x: normalizedRect.topRight.x * size.width, y: (1 - normalizedRect.topRight.y) * size.height),
            CGPoint(x: normalizedRect.bottomRight.x * size.width, y: (1 - normalizedRect.bottomRight.y) * size.height),
            CGPoint(x: normalizedRect.bottomLeft.x * size.width, y: (1 - normalizedRect.bottomLeft.y) * size.height)
        ]
    }
}

#Preview {
    ReceiptScannerView()
}
