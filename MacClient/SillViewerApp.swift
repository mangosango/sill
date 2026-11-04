import SwiftUI
import AppKit
import StreamProtocol

@main
struct SillViewerApp: App {
    @StateObject private var client = StreamClient()
    @State private var started = false
    var body: some Scene {
        Window("Sill Viewer", id: "viewer") {
            VStack(alignment: .leading, spacing: 16) {
                Text(client.connected ? client.hostName : "Connect to a Mac").font(.title)
                Text(client.status).textSelection(.enabled).accessibilityAddTraits(.updatesFrequently)
                if client.connected {
                    ViewerPicture(client: client)
                        .overlay {
                            if let shade = client.lockShade {
                                VStack {
                                    Text(LockedMac.title(mac: client.hostName, shade: shade)).font(.headline)
                                    if let detail = LockedMac.detail(shade: shade, paired: client.settings.host?.sessionPaired) { Text(detail) }
                                }.padding().frame(maxWidth: .infinity, maxHeight: .infinity).background(.black)
                            }
                        }
                    ViewerControls(client: client)
                    Button("Disconnect") { releasePicture(); client.disconnect() }
                        .keyboardShortcut("d", modifiers: [.command, .shift])
                } else {
                    ViewerConnectView(client: client)
                }
                Text("Avoid viewing this Mac itself or having two Macs view each other: the picture can repeat inside itself.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding()
            .frame(minWidth: 640, minHeight: 400)
            .onDisappear { releasePicture(); client.disconnect() }
            .onAppear {
                guard !started else { return }
                started = true
                client.startBrowsing()
            }
        }
    }
}

private struct ViewerConnectView: View {
    @ObservedObject var client: StreamClient
    @State private var forgetID: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Available Macs") {
                    VStack(alignment: .leading) {
                        if client.macs.isEmpty { Text("Looking for Macs on your network…").foregroundStyle(.secondary) }
                        ForEach(client.macs) { mac in
                            Button {
                                client.connect(to: mac)
                            } label: {
                                HStack { Text(mac.name); Spacer(); Text(mac.word ?? "Connect") }
                            }
                            .accessibilityLabel("Connect to \(mac.name), \(mac.word ?? "available")")
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                if !client.savedMacs.isEmpty {
                    GroupBox("Saved Macs") {
                        VStack(alignment: .leading) {
                            ForEach(client.savedMacs, id: \.macID) { mac in
                                HStack {
                                    Text(client.displayName(mac.macID))
                                    Spacer()
                                    Button("Connect Remotely") { client.connectRemotely(mac.macID) }
                                        .accessibilityLabel("Connect remotely to \(client.displayName(mac.macID))")
                                    Button("Forget…", role: .destructive) { forgetID = mac.macID }
                                        .accessibilityLabel("Forget \(client.displayName(mac.macID))")
                                }
                            }
                        }
                    }
                }
                ViewerPairingView(client: client)
            }
        }
        .confirmationDialog("Forget this saved Mac?", isPresented: Binding(get: { forgetID != nil }, set: { if !$0 { forgetID = nil } })) {
            Button("Forget Mac", role: .destructive) {
                if let id = forgetID { client.forget(id) }
                forgetID = nil
            }
            Button("Cancel", role: .cancel) { forgetID = nil }
        } message: {
            Text("This only removes the saved record here. Remove this viewer separately in Sill’s Settings on the remote Mac.")
        }
    }
}

private struct ViewerPairingView: View {
    @ObservedObject var client: StreamClient
    @State private var address = ""
    @State private var code = ""
    @State private var linkError: String?
    private var working: Bool {
        if case .working = client.pairing { return true }
        return client.homeAsk?.phase == .asking
    }

    var body: some View {
        GroupBox(client.homeAsk.map { "Pair with \($0.name)" } ?? "Add a Mac") {
            VStack(alignment: .leading, spacing: 12) {
                Text("On the remote Mac, open Sill’s pairing window. Enter its 12-digit code, or explicitly paste its pairing link. Mac-to-Mac pairing does not use a camera or automatic USB pairing.")
                if client.homeAsk == nil {
                    TextField("Address (hostname or IP, optionally :port)", text: $address)
                        .textContentType(nil)
                }
                TextField("12-digit pairing code", text: $code)
                    .onSubmit { if !working { pair() } }
                HStack {
                    Button("Pair") { pair() }.disabled(working)
                    PasteButton(payloadType: String.self) { strings in
                        guard let text = strings.first else { return }
                        // Parse before invoking the shared URL path: typed addresses must not bypass confirmation.
                        if case .success(let link) = PairLink.parse(text) {
                            linkError = nil
                            client.pendingLink = link
                        } else {
                            linkError = "That is not a Sill pairing link."
                        }
                    }
                    .disabled(working)
                    .accessibilityLabel("Paste pairing link for confirmation")
                    Button("Cancel Pairing", role: .cancel) {
                        client.cancelPendingLink()
                        client.cancelPairing()
                        code = ""
                        linkError = nil
                    }
                }
                if let error = linkError { Text(error).foregroundStyle(.red) }
                switch client.pairing {
                case .idle: EmptyView()
                case .working(let words): HStack { ProgressView().controlSize(.small); Text(words) }
                case .failed(let problem): Text(problem.text).foregroundStyle(.red).textSelection(.enabled)
                case .paired(let words): Text(words)
                }
                if let link = client.pendingLink {
                    Divider()
                    Text("Pair with \(link.name)?").font(.headline)
                    Text("Continue only if this link came from the Mac you intend to control. No connection is made from the pasted link until you confirm.")
                    HStack {
                        Button("Confirm Pairing") { client.confirmPendingLink() }
                        Button("Discard Link", role: .cancel) { client.cancelPendingLink() }
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func pair() {
        linkError = nil
        if client.homeAsk != nil {
            client.pairHome(code: code)
        } else {
            switch AddressParser.parse(address) {
            case .failure(.pairingLink):
                if case .success(let link) = PairLink.parse(address) {
                    client.pendingLink = link
                } else {
                    linkError = "That is not a Sill pairing link."
                }
            default:
                client.pairTyped(code: code, address: address, overlay: false)
            }
        }
    }
}

private struct ViewerPicture: NSViewRepresentable {
    let client: StreamClient
    func makeNSView(context: Context) -> ViewerSurface { ViewerSurface(client: client) }
    func updateNSView(_ view: ViewerSurface, context: Context) { view.refresh() }
    static func dismantleNSView(_ view: ViewerSurface, coordinator: ()) { view.detach() }
}

// Relinquish input before a control changes the remote source or opens a native menu.
private func releasePicture() { NSApp.keyWindow?.makeFirstResponder(nil) }

private struct ViewerControls: View {
    @ObservedObject var client: StreamClient
    @AppStorage(StreamClient.clipboardKey) private var sharing = true
    @State private var scale = TextScale.off

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Desktop") { releasePicture(); client.select(.desktop) }
                Menu("Windows") {
                    ForEach(client.windows) { window in
                        Button("\(window.appName) — \(window.title)") { releasePicture(); client.select(.window(window.id)) }
                    }
                }.simultaneousGesture(TapGesture().onEnded { releasePicture() })
                Menu("Apps") {
                    ForEach(client.apps) { app in
                        Button(app.name) { releasePicture(); client.launch(bundleID: app.bundleID) }
                    }
                }.simultaneousGesture(TapGesture().onEnded { releasePicture() })
                Picker("Aa", selection: Binding(get: {
                    TextScale.position(of: TextScale.scale(at: scale), offered: client.textScaleOffersOff)
                }, set: { value in
                    releasePicture()
                    scale = value
                    if var viewport = client.lastViewport {
                        viewport.scale = TextScale.scale(at: value)
                        client.sendViewport(viewport)
                    }
                })) {
                    ForEach(TextScale.detents(offered: client.textScaleOffersOff), id: \.self) { value in
                        Text(TextScale.title(at: value)).tag(value)
                    }
                }.disabled(!client.textScaleSelectable || client.macLocked)
                RemoteMenus(client: client).fixedSize()
                Button("Release Input") { releasePicture() }
            }.disabled(client.macLocked)
            DisclosureGroup("Stream Settings") {
                settings
            }.simultaneousGesture(TapGesture().onEnded { releasePicture() })
            if let problem = client.settingsProblem { Text(problem).foregroundStyle(.red).textSelection(.enabled) }
            Toggle("Share Clipboard", isOn: $sharing)
                .onChange(of: sharing) { _ in releasePicture(); client.clipboardSwitchChanged() }
            Text("Warning: a Sill host running on this Mac may forward received clipboard text to its devices. Turn sharing off to prevent viewer clipboard transfers. Remote Command-V uses the remote clipboard; it does not transfer local text.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Transfer Local Text to Remote Clipboard") { releasePicture(); client.transferLocalClipboard() }
                .disabled(!sharing || client.macLocked || !ClipboardPolicy.hostTakes(client.hostClipboard))
            if let note = client.clipboardNote { Text(note.text).textSelection(.enabled) }
            Toggle("Mute This Viewer", isOn: Binding(get: { client.soundMuted }, set: { releasePicture(); client.setSoundMuted($0) }))
        }
    }

    @ViewBuilder private var settings: some View {
        if let shown = client.settings.displayed {
            VStack(alignment: .leading) {
                Picker("Quality", selection: setting(shown.bitrate) { HostSettingsChange(bitrate: $0) }) {
                    ForEach(QualityPreset.allCases) { Text($0.title).tag($0.rawValue) }
                    if QualityPreset(rawValue: shown.bitrate) == nil { Text(QualityPreset.title(forBitrate: shown.bitrate)).tag(shown.bitrate) }
                }
                Picker("Resolution", selection: setting(shown.captureScale) { HostSettingsChange(captureScale: $0) }) {
                    Text("Standard").tag(1.0); Text("Retina").tag(2.0)
                }
                Picker("Frame Rate Limit", selection: setting(shown.maxFPS) { HostSettingsChange(maxFPS: $0) }) {
                    Text("60 fps").tag(60); Text("120 fps").tag(120)
                }
                Toggle("Prioritize Encoding Speed", isOn: setting(shown.prioritizeSpeed) { HostSettingsChange(prioritizeSpeed: $0) })
                Toggle("Virtual Display", isOn: setting(shown.virtualDisplay) { HostSettingsChange(virtualDisplay: $0) })
                    .disabled(client.settings.host?.virtualDisplayAvailable != true && !shown.virtualDisplay)
                if let wireless = shown.directWireless {
                    Toggle("Direct Wireless Connection", isOn: setting(wireless) { HostSettingsChange(directWireless: $0) })
                        .disabled(client.remoteRoute != nil || client.settings.host?.takesDirectWireless != true)
                }
                if let audio = shown.sendAudio {
                    Toggle("Send Audio to All Devices (Beta)", isOn: setting(audio) { HostSettingsChange(sendAudio: $0) })
                } else { Text("Update Sill on the remote Mac for sound.") }
                if let note = client.settings.host?.audioNote { Text(note) }
                if let note = client.settings.host?.virtualDisplayNote { Text(note) }
            }.disabled(client.macLocked)
        } else { Text("Waiting for host settings. Older Macs may not support them.") }
    }

    private func setting<Value>(_ value: Value, change: @escaping (Value) -> HostSettingsChange) -> Binding<Value> {
        Binding(get: { value }, set: { releasePicture(); client.changeSettings(change($0)) })
    }
}
