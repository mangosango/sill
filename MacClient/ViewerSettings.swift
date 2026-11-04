import AppKit
import SwiftUI
import StreamProtocol

enum ViewerSettingsPane: String, CaseIterable {
    case general, sharing, remoteMac

    var title: String {
        switch self {
        case .general: return "General"
        case .sharing: return "Sharing"
        case .remoteMac: return "Remote Mac"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .sharing: return "doc.on.clipboard"
        case .remoteMac: return "desktopcomputer"
        }
    }
}

/// Viewer-owned window; deliberately independent of the host's Settings implementation.
@MainActor
final class ViewerSettingsWindowController: NSWindowController, NSWindowDelegate {
    private let tabs: ViewerSettingsTabs
    private let releaseInput: () -> Void
    private static let paneKey = "SillViewer.settingsPane"

    init(client: StreamClient, releaseInput: @escaping () -> Void) {
        self.releaseInput = releaseInput
        tabs = ViewerSettingsTabs(client: client, releaseInput: releaseInput)
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .preference
        super.init(window: window)
        window.delegate = self
        window.center()
        tabs.onSelect = { [weak self] in
            guard let self else { return }
            self.window?.title = self.tabs.current.title
            if self.window?.isVisible == true {
                UserDefaults.standard.set(self.tabs.current.rawValue, forKey: Self.paneKey)
            }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not from a nib") }

    func show(pane: ViewerSettingsPane? = nil) {
        releaseInput()
        let saved = UserDefaults.standard.string(forKey: Self.paneKey).flatMap(ViewerSettingsPane.init(rawValue:))
        tabs.select(pane ?? saved ?? .general)
        guard let window else { return }
        window.title = tabs.current.title
        UserDefaults.standard.set(tabs.current.rawValue, forKey: Self.paneKey)
        fit()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.toolbar?.displayMode = .iconAndLabel
        window.toolbar?.allowsUserCustomization = false
        window.toolbar?.isVisible = true
    }

    func windowDidChangeScreen(_ notification: Notification) { fit() }
    @objc private func screensChanged() { fit() }

    private func fit() {
        guard let window, let area = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        let chrome = window.frame.height - window.contentRect(forFrameRect: window.frame).height
        // The grouped Form scrolls inside a fixed viewport, rather than growing beyond the screen.
        window.setContentSize(NSSize(width: min(560, area.width), height: min(520, max(1, area.height - chrome))))
        var origin = window.frame.origin
        origin.x = max(area.minX, min(origin.x, area.maxX - window.frame.width))
        origin.y = max(area.minY, min(origin.y, area.maxY - window.frame.height))
        window.setFrameOrigin(origin)
    }
}

@MainActor
private final class ViewerSettingsTabs: NSTabViewController {
    var onSelect: (() -> Void)?

    init(client: StreamClient, releaseInput: @escaping () -> Void) {
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        for pane in ViewerSettingsPane.allCases {
            let host = NSHostingController(rootView: ViewerSettingsForm(client: client, pane: pane, releaseInput: releaseInput))
            host.sizingOptions = []
            host.title = pane.title
            let item = NSTabViewItem(viewController: host)
            item.identifier = pane.rawValue
            item.label = pane.title
            item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)
            addTabViewItem(item)
        }
        preferredContentSize = NSSize(width: 560, height: 520)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not from a nib") }

    var current: ViewerSettingsPane {
        (tabViewItems[max(0, selectedTabViewItemIndex)].identifier as? String)
            .flatMap(ViewerSettingsPane.init(rawValue:)) ?? .general
    }

    func select(_ pane: ViewerSettingsPane) {
        selectedTabViewItemIndex = ViewerSettingsPane.allCases.firstIndex(of: pane) ?? 0
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        onSelect?()
    }
}

@MainActor
private struct ViewerSettingsForm: View {
    @ObservedObject var client: StreamClient
    let pane: ViewerSettingsPane
    let releaseInput: () -> Void
    @AppStorage(StreamClient.clipboardKey) private var sharing = true
    @AppStorage("SillViewer.reverseScrolling") private var reverseScrolling = false

    var body: some View {
        Form {
            switch pane {
            case .general: general
            case .sharing: sharingPane
            case .remoteMac: remoteMac
            }
        }
        .formStyle(.grouped)
    }

    private var general: some View {
        Group {
            Section("Sound on This Mac") {
                Toggle("Mute This Viewer", isOn: Binding(get: { client.soundMuted }, set: {
                    releaseInput(); client.setSoundMuted($0)
                }))
                Text("Only silences this viewer. Send Audio in Remote Mac settings affects every connected device, not the remote Mac’s speakers.")
                    .foregroundStyle(.secondary)
            }
            Section("Scrolling") {
                Toggle("Reverse scrolling direction", isOn: $reverseScrolling)
                Text("Reverse horizontal and vertical scrolling sent by this viewer. Neither Mac’s system scrolling preference is changed.")
                    .foregroundStyle(.secondary)
            }
            Section("Keyboard and Control") {
                Text("Click the remote picture or choose Control Remote Mac in the session toolbar to send input. The first click takes control without clicking anything on the remote Mac.")
                Text("Control–Option–Command–K or moving the pointer outside the remote view releases input. Opening Settings or leaving the stream’s keyboard focus also releases held keys and buttons.")
                Text("Keyboard control requires Accessibility permission on this Mac. While controlling, Command–Tab, Command–Q, Command–Space and app shortcuts go to the remote Mac. Release input before using local shortcuts such as Command–Comma for Settings. Active VoiceOver’s Control–Option and Caps Lock navigation stay local; system trackpad gestures and media keys are not captured.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sharingPane: some View {
        Group {
            Section("Text Clipboard — This Viewer") {
                Toggle("Share Clipboard", isOn: Binding(get: { sharing }, set: {
                    releaseInput(); sharing = $0; client.clipboardSwitchChanged()
                }))
                Text("Receive remote text while sharing is on. Local text is sent only when you choose Transfer Local Text in the session menu. Remote Command–V uses the remote clipboard; it does not transfer local text.")
                    .foregroundStyle(.secondary)
                if let note = client.clipboardNote { Text(note.text).textSelection(.enabled) }
            }
            Section("Privacy on This Mac") {
                Label("A Sill host running on this Mac may forward received clipboard text to its devices.", systemImage: "exclamationmark.triangle")
                Text("Running the host and viewer together for clipboard forwarding is unsupported. Turn Share Clipboard off to prevent viewer clipboard transfers. This setting does not change the host’s clipboard preference.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var canEditRemote: Bool { client.connected && !client.macLocked && client.settings.displayed != nil }

    private var remoteMac: some View {
        Group {
            Section("Remote Mac — \(client.hostName)") {
                Text("These settings change Sill on \(client.hostName) for all connected devices, not just this viewer. Source and stream changes can affect other viewers.")
                    .foregroundStyle(.secondary)
                if !client.connected { Text("Connect to a Mac to change its settings.") }
                else if client.macLocked { Text("Unlock the remote Mac to change its settings.") }
                if let problem = client.settingsProblem {
                    Label(problem, systemImage: "exclamationmark.triangle").textSelection(.enabled)
                }
                if !client.settings.pending.isEmpty {
                    Label("Applying changes on the remote Mac…", systemImage: "clock")
                }
            }
            if let shown = client.settings.displayed {
                Section("Streaming") {
                    Picker("Quality", selection: setting(\.bitrate, fallback: shown.bitrate) { HostSettingsChange(bitrate: $0) }) {
                        ForEach(QualityPreset.allCases) { Text($0.title).tag($0.rawValue) }
                        if QualityPreset(rawValue: shown.bitrate) == nil {
                            Text(QualityPreset.title(forBitrate: shown.bitrate)).tag(shown.bitrate)
                        }
                    }
                    Picker("Resolution", selection: setting(\.captureScale, fallback: shown.captureScale) { HostSettingsChange(captureScale: $0) }) {
                        Text("Standard").tag(1.0); Text("Retina").tag(2.0)
                    }
                    Picker("Frame Rate Limit", selection: setting(\.maxFPS, fallback: shown.maxFPS) { HostSettingsChange(maxFPS: $0) }) {
                        Text("60 fps").tag(60); Text("120 fps").tag(120)
                    }
                    Toggle("Prioritize Encoding Speed", isOn: setting(\.prioritizeSpeed, fallback: shown.prioritizeSpeed) { HostSettingsChange(prioritizeSpeed: $0) })
                    if let away = client.settings.host?.away {
                        if away.thisConnectionAway {
                            Text("Quality and Resolution change this Mac’s saved away settings, not its home defaults. They apply when every connected device is away.")
                                .foregroundStyle(.secondary)
                            if !away.awayRunning {
                                Text("A device at home is connected, so the remote Mac is currently streaming at its home quality.")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Quality and Resolution change this Mac’s home defaults. Its saved away settings stay unchanged.")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("This host does not report separate home and away quality settings.")
                            .foregroundStyle(.secondary)
                    }
                }.disabled(!canEditRemote)
                Section("Display and Connection") {
                    Toggle("Virtual Display", isOn: setting(\.virtualDisplay, fallback: shown.virtualDisplay, allowed: {
                        client.settings.host?.virtualDisplayAvailable == true || client.settings.displayed?.virtualDisplay == true
                    }) { HostSettingsChange(virtualDisplay: $0) })
                        .disabled(client.settings.host?.virtualDisplayAvailable != true && !shown.virtualDisplay)
                    if let wireless = shown.directWireless {
                        Toggle("Direct Wireless Connection", isOn: optionalSetting(\.directWireless, fallback: wireless, allowed: {
                            client.remoteRoute == nil && client.settings.host?.takesDirectWireless == true
                        }) { HostSettingsChange(directWireless: $0) })
                            .disabled(client.remoteRoute != nil || client.settings.host?.takesDirectWireless != true)
                    } else { Text("This Mac does not offer Direct Wireless Connection.").foregroundStyle(.secondary) }
                    if let note = client.settings.host?.virtualDisplayNote { Text(note).textSelection(.enabled) }
                }.disabled(!canEditRemote)
                Section("Sound for All Devices") {
                    if let audio = shown.sendAudio {
                        Toggle("Send Audio to All Devices (Beta)", isOn: optionalSetting(\.sendAudio, fallback: audio) { HostSettingsChange(sendAudio: $0) })
                    } else { Text("Update Sill on the remote Mac for sound.") }
                    Text("To silence only this viewer, use Mute This Viewer in General.").foregroundStyle(.secondary)
                    if let note = client.settings.host?.audioNote { Text(note).textSelection(.enabled) }
                }.disabled(!canEditRemote)
            } else {
                Section { Text("Waiting for host settings. Older Macs may not support them.").foregroundStyle(.secondary) }
            }
        }
    }

    private func setting<Value>(_ key: KeyPath<StreamSettings, Value>, fallback: Value,
                                allowed: @escaping () -> Bool = { true },
                                change: @escaping (Value) -> HostSettingsChange) -> Binding<Value> {
        let session = client.connectedAt
        return Binding(get: { client.settings.displayed?[keyPath: key] ?? fallback }, set: { value in
            releaseInput()
            guard canEditRemote, client.connectedAt == session, allowed() else { return }
            client.changeSettings(change(value))
        })
    }

    private func optionalSetting<Value>(_ key: KeyPath<StreamSettings, Value?>, fallback: Value,
                                        allowed: @escaping () -> Bool = { true },
                                        change: @escaping (Value) -> HostSettingsChange) -> Binding<Value> {
        let session = client.connectedAt
        return Binding(get: { client.settings.displayed?[keyPath: key] ?? fallback }, set: { value in
            releaseInput()
            guard canEditRemote, client.connectedAt == session,
                  client.settings.displayed?[keyPath: key] != nil, allowed() else { return }
            client.changeSettings(change(value))
        })
    }
}
