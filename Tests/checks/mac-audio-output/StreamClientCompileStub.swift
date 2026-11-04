// Compile-only seam until the native shared StreamClient target exists. Never instantiated.
import Foundation
import StreamProtocol

final class StreamClient {
    struct Settings { var displayed: StreamSettings? }
    var settings = Settings()
    var soundAcrossMove: Bool?
    var soundMuted = false
    var sound: AudioOutput { fatalError("compile-only") }
    func noteAction() {}
}
