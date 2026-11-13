import Foundation

// The shared client (iOSClient/StreamClient.swift) calls these iOS services as it changes state.
// The Mac viewer has no device auto-lock to hold off and no Picture in Picture, so here each one
// does nothing. The real ones are iOS-only: DeviceIdleTimer in StreamScreen.swift, and
// PictureInPictureHub and PictureInPicture in PictureInPicture.swift.

final class DeviceIdleTimer {
    static let shared = DeviceIdleTimer()
    func update() {}
    func used() {}
}

final class PictureInPictureHub {
    static let shared = PictureInPictureHub()
    func update() {}
    func used(_ client: StreamClient) {}
}

final class PictureInPicture {
    static let supported = false
    init(client: StreamClient) {}
    func end(_ ending: PictureInPicturePolicy.Ending, why: String) {}
}
