import Foundation

/// 矩形の4角の座標（Vision 正規化座標系 0.0-1.0）
struct RectangleCorners: Sendable {
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomLeft: CGPoint
    let bottomRight: CGPoint
}
