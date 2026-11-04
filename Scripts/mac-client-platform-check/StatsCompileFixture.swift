import Foundation

import Combine
import StreamProtocol

// Compile-only interface for DiagnosticsHUD's reporter, not a transport or media implementation.
final class StreamClient {
    struct MedianMax { let median: Int; let max: Int }
    struct LinkStats {
        let fps: Int
        let frameAge: MedianMax?
        let rtt: MedianMax?
        let soundBehindMs: Int?
        let soundLate: Int?
    }
    @Published var linkStats: LinkStats?
    var connected = false
    func send(_ kind: StreamMessageKind, payload: Data) { fatalError("compile fixture only") }
}
