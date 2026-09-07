import SwiftUI

/// Numbers measured off the Codenotch reference frame so the whole UI resizes
/// together at the same proportions. Anchor: the provider ring is 44pt across.
enum Design {
    static let scale: CGFloat = 44.0 / 117.0

    static func px(_ pixels: CGFloat) -> CGFloat { pixels * scale }

    private static let capRatio: CGFloat = 0.714

    static func fontSize(capPixels pixels: CGFloat) -> CGFloat {
        px(pixels) / capRatio
    }
}
