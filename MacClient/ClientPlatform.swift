import AppKit

/// Native image and accessibility operations for the shared session client.
/// NSImage representation follows Alexander Deutsch's PR #128; no UIKit lifecycle or privacy shims.
enum ClientPlatform {
    static func previewImage(_ image: CGImage, scale: CGFloat) -> NSImage {
        NSImage(cgImage: image, size: CGSize(width: CGFloat(image.width) / scale,
                                           height: CGFloat(image.height) / scale))
    }

    static func jpegData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.72])
    }

    static func announce(_ text: String, view: NSView) {
        NSAccessibility.post(element: view, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}
