import Foundation
import CoreGraphics

let frame = CGSize(width: 789, height: 620)
let content = CGRect(x: 0, y: 0, width: 789, height: 592)
precondition(windowContentCrop(frameSize: frame, contentRect: content,
                              imageSize: CGSize(width: 1578, height: 1240)) == CGRect(x: 0, y: 56, width: 1578, height: 1184))
precondition(windowContentCrop(frameSize: frame, contentRect: CGRect(origin: .zero, size: frame),
                              imageSize: frame) == CGRect(origin: .zero, size: frame))
precondition(windowContentCrop(frameSize: frame, contentRect: CGRect(x: -1, y: 0, width: 500, height: 500), imageSize: frame) == nil)
precondition(windowContentCrop(frameSize: .zero, contentRect: content, imageSize: frame) == nil)
precondition(windowContentCrop(frameSize: frame, contentRect: content, imageSize: CGSize(width: CGFloat.nan, height: 1)) == nil)
print("Own-window capture geometry passed")
let fullPhone = fittedPhoneWindowSize(available: CGSize(width: 1440, height: 1000))!
precondition(fullPhone == CGSize(width: 390, height: 844))
let smallDisplay = fittedPhoneWindowSize(available: CGSize(width: 1200, height: 600))!
precondition(smallDisplay.height == 600 && abs(smallDisplay.width / smallDisplay.height - 390.0 / 844) < 0.000001)
let narrowDisplay = fittedPhoneWindowSize(available: CGSize(width: 300, height: 1000))!
precondition(narrowDisplay.width == 300 && narrowDisplay.height <= 1000)
precondition(fittedPhoneWindowSize(available: .zero) == nil)
precondition(fittedPhoneWindowSize(available: CGSize(width: CGFloat.nan, height: 800)) == nil)
print("Phone portrait window sizing passed")
