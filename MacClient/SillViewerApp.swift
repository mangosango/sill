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
                    Button("Disconnect") { client.disconnect() }
                        .keyboardShortcut("d", modifiers: [.command, .shift])
                } else {
                    ViewerConnectView(client: client)
                }
                Text("Avoid viewing this Mac itself or having two Macs view each other: the picture can repeat inside itself. Native stream input and richer stream controls are not available in this checkpoint.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding()
            .frame(minWidth: 640, minHeight: 400)
            .onDisappear { client.disconnect() }
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
    func makeNSView(context: Context) -> HEVCDisplayView { client.displayView }
    func updateNSView(_ view: HEVCDisplayView, context: Context) {}
}
