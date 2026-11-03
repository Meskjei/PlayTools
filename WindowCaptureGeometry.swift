import Foundation
import CoreGraphics

func fittedPhoneWindowSize(available: CGSize) -> CGSize? {
    guard available.width.isFinite, available.height.isFinite, available.width > 0, available.height > 0 else { return nil }
    let scale = min(1, available.width / 390, available.height / 844)
    return CGSize(width: 390 * scale, height: 844 * scale)
}

func fittedPhoneViewportSize(available: CGSize, content: CGSize, logical: CGSize) -> CGSize? {
    let values = [available.width, available.height, content.width, content.height, logical.width, logical.height]
    guard values.allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
    let target = CGSize(width: 390 * content.width / logical.width, height: 844 * content.height / logical.height)
    let fit = min(1, available.width / target.width, available.height / target.height)
    return CGSize(width: target.width * fit, height: target.height * fit)
}

/// ScreenCaptureKit's window image includes the title bar; UIKit's coordinates do not.
func windowContentCrop(frameSize: CGSize, contentRect: CGRect, imageSize: CGSize) -> CGRect? {
    let values = [frameSize.width, frameSize.height, imageSize.width, imageSize.height,
                  contentRect.minX, contentRect.minY, contentRect.width, contentRect.height]
    guard values.allSatisfy({ $0.isFinite }), frameSize.width > 0, frameSize.height > 0,
          imageSize.width > 0, imageSize.height > 0, !contentRect.isEmpty,
          CGRect(origin: .zero, size: frameSize).contains(contentRect) else { return nil }
    let sx = imageSize.width / frameSize.width, sy = imageSize.height / frameSize.height
    let rect = CGRect(x: contentRect.minX * sx, y: (frameSize.height - contentRect.maxY) * sy,
                      width: contentRect.width * sx, height: contentRect.height * sy).integral
    guard CGRect(origin: .zero, size: imageSize).contains(rect) else { return nil }
    return rect
}
