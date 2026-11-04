import Foundation
import SwiftUI
import StreamProtocol

// Compile-only recording surface: never instantiated, no defaults, clipboard or connections.
@MainActor
final class StreamClient: ObservableObject {
    static let clipboardKey = "fixture.clipboard"
    @Published var soundMuted = false
    @Published var connected = false
    @Published var macLocked = false
    @Published var settings = SettingsLedger()
    @Published var settingsProblem: String?
    @Published var clipboardNote: Note?
    var hostName = "Fixture Mac"
    var connectedAt: Date?
    var remoteRoute: String?
    struct Note { var text: String }
    func setSoundMuted(_ value: Bool) {}
    func clipboardSwitchChanged() {}
    func changeSettings(_ change: HostSettingsChange) {}
}
