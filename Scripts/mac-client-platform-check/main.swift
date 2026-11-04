import AppKit

var checks = 0
for bits in 0..<32 {
    let awake = bits & 1 != 0
    let hidden = bits & 2 != 0
    let attached = bits & 4 != 0
    let visible = bits & 8 != 0
    let minimized = bits & 16 != 0
    // Only awake, attached, visible and neither hidden nor minimized can show a picture.
    precondition(ClientVisibility.pictureVisible(awake: awake, hidden: hidden, attached: attached,
                                                 visible: visible, minimized: minimized) == (bits == 13))
    checks += 1
}
// Native images only; no view, decoder, pasteboard, preferences or application is started.
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 2,
                              bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false,
                              isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 12, bitsPerPixel: 24)!
bitmap.bitmapData!.initialize(repeating: 127, count: 24)
let image = ClientPlatform.previewImage(bitmap.cgImage!, scale: 2)
precondition(image.size == CGSize(width: 2, height: 1))
let jpeg = ClientPlatform.jpegData(image)!
let decoded = NSBitmapImageRep(data: jpeg)!
precondition(decoded.pixelsWide == 4 && decoded.pixelsHigh == 2)
checks += 2
print("Mac client platform: \(checks) checks passed; no session or UI started.")
