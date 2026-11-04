import SwiftUI
import StreamProtocol

/// Chooses an existing route without changing the shared client's trust decisions.
struct ViewerConnectView: View {
    @ObservedObject var client: StreamClient
    @State private var forgetID: String?
    @State private var showingPairing = false
    @State private var selection: String?

    private var selectedSavedID: String? {
        client.savedMacs.first { "saved:\($0.macID)" == selection }?.macID
    }

    private func activateSelection() {
        if let id = selectedSavedID {
            if let route = nearby(id) { client.connect(to: route) }
            else { client.connectRemotely(id) }
        } else if let mac = available.first(where: { $0.id == selection }) {
            client.connect(to: mac)
        }
    }

    private func actionTitle(_ mac: FoundMac) -> String {
        if mac.route == .remote { return "Connect Remotely" }
        return mac.door == .pairingRequired ? "Pair…" : "Connect"
    }

    private func nearby(_ id: String) -> FoundMac? {
        client.macs.first { $0.macID == id && $0.route != .remote }
    }

    private var available: [FoundMac] {
        let saved = Set(client.savedMacs.map(\.macID))
        var seen = Set<String>()
        return client.macs.filter { mac in
            guard let id = mac.macID else { return true }
            return !saved.contains(id) && seen.insert(id).inserted
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: $selection) {
                Section("Paired Macs") {
                    if client.savedMacs.isEmpty {
                        Text("No paired Macs yet. Choose Add Mac to pair.").foregroundStyle(.secondary)
                    }
                    ForEach(client.savedMacs, id: \.macID) { mac in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(client.displayName(mac.macID))
                                Text(nearby(mac.macID)?.word ?? (nearby(mac.macID) == nil ? "Not found nearby" : "Nearby"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let route = nearby(mac.macID) {
                                Button("Connect") { client.connect(to: route) }
                                    .accessibilityLabel("Connect to \(client.displayName(mac.macID))")
                            } else {
                                Button("Connect Remotely") { client.connectRemotely(mac.macID) }
                                    .accessibilityLabel("Connect remotely to \(client.displayName(mac.macID))")
                            }
                        }
                        .padding(.vertical, 4)
                        .tag("saved:\(mac.macID)")
                    }
                }
                Section("Available to Pair") {
                    if available.isEmpty {
                        Text(client.searchingNearby ? "Looking on your network and nearby…" : "Looking for Macs on your network…")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(available) { mac in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(mac.name)
                                if let word = mac.word { Text(word).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Button(actionTitle(mac)) {
                                client.connect(to: mac)
                            }.accessibilityLabel("\(actionTitle(mac)) \(mac.name), \(mac.word ?? "available")")
                        }.padding(.vertical, 4)
                            .tag(mac.id)
                    }
                }
            }
            .listStyle(.inset)
            .onKeyPress(.return) {
                guard selection != nil else { return .ignored }
                activateSelection()
                return .handled
            }
            .contextMenu(forSelectionType: String.self) { ids in
                if let id = ids.first, let mac = client.savedMacs.first(where: { "saved:\($0.macID)" == id }) {
                    Button("Forget Mac…") { forgetID = mac.macID }
                }
            } primaryAction: { ids in
                selection = ids.first
                activateSelection()
            }
            if client.showsNearbyHint {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Use the same Wi-Fi network, or turn on Direct Wireless Connection in Sill on the other Mac and search nearby.")
                        .font(.callout).foregroundStyle(.secondary)
                    if client.searchingNearby {
                        Label("Also looking nearby", systemImage: "antenna.radiowaves.left.and.right")
                    } else {
                        Button("Search Nearby") { client.searchNearby() }
                            .help("Look for Macs with Direct Wireless Connection turned on")
                    }
                }.padding([.horizontal, .top])
            }
            // Dial handles are main-thread state, but are not @Published by the shared client.
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                if !client.connected && (client.connection != nil || client.remoteDial != nil || client.reconnect != nil) {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Connecting…")
                        Spacer()
                        Button("Cancel Connection") { client.disconnect() }
                    }.padding([.horizontal, .top])
                }
            }
            Text(client.status)
                .font(.callout).foregroundStyle(.secondary)
                .textSelection(.enabled).accessibilityAddTraits(.updatesFrequently)
                .padding()
        }
        .focusedSceneValue(\.viewerChooserActions, ViewerChooserActions(
            addMac: { showingPairing = true },
            forgetSelected: selectedSavedID.map { id in { forgetID = id } },
            searchNearby: client.showsNearbyHint && !client.searchingNearby ? { client.searchNearby() } : nil
        ))
        .toolbar {
            Button { showingPairing = true } label: { Label("Add Mac…", systemImage: "plus") }
                .help("Pair with another Mac")
            Menu {
                Button("Forget Selected Mac…") { forgetID = selectedSavedID }
                    .disabled(selectedSavedID == nil)
            } label: { Label("Mac Actions", systemImage: "ellipsis.circle") }
        }
        .sheet(isPresented: $showingPairing, onDismiss: cancelPairing) {
            ViewerPairingView(client: client, close: { showingPairing = false })
        }
        .onChange(of: client.homeAsk != nil) { _, asking in
            if asking { showingPairing = true }
        }
        .onChange(of: client.pendingLink != nil) { _, pending in
            if pending { showingPairing = true }
        }
        .onChange(of: client.connected) { _, connected in
            if connected { showingPairing = false }
        }
        .onAppear {
            if client.homeAsk != nil || client.pendingLink != nil { showingPairing = true }
        }
        .confirmationDialog("Forget this paired Mac?", isPresented: Binding(get: { forgetID != nil }, set: { if !$0 { forgetID = nil } })) {
            Button("Forget Mac", role: .destructive) {
                if let id = forgetID { client.forget(id) }
                forgetID = nil
            }
            Button("Cancel", role: .cancel) { forgetID = nil }
        } message: {
            Text("This only removes the saved record on this viewer. Remove this viewer separately in Sill’s Settings on the remote Mac.")
        }
    }

    private func cancelPairing() {
        client.cancelPendingLink()
        client.cancelPairing()
    }
}

struct ViewerChooserActions {
    var addMac: () -> Void
    var forgetSelected: (() -> Void)?
    var searchNearby: (() -> Void)?
}

private struct ViewerChooserActionsKey: FocusedValueKey {
    typealias Value = ViewerChooserActions
}

extension FocusedValues {
    var viewerChooserActions: ViewerChooserActions? {
        get { self[ViewerChooserActionsKey.self] }
        set { self[ViewerChooserActionsKey.self] = newValue }
    }
}

/// Install once with the app scene's .commands { ViewerChooserCommands() }.
struct ViewerChooserCommands: Commands {
    @FocusedValue(\.viewerChooserActions) private var actions

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Add Mac…") { actions?.addMac() }
                .disabled(actions == nil)
            Button("Search Nearby") { actions?.searchNearby?() }
                .disabled(actions?.searchNearby == nil)
            Button("Forget Selected Mac…") { actions?.forgetSelected?() }
                .disabled(actions?.forgetSelected == nil)
        }
    }
}

private struct ViewerPairingView: View {
    @ObservedObject var client: StreamClient
    var close: () -> Void
    @State private var address = ""
    @State private var code = ""
    @State private var linkError: String?
    private var working: Bool {
        if case .working = client.pairing { return true }
        return client.homeAsk?.phase == .asking
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(client.homeAsk.map { "Pair with \($0.name)" } ?? "Add a Mac").font(.title2)
            VStack(alignment: .leading, spacing: 12) {
                Text("Open Sill’s pairing window on the Mac you want to control. Enter its 12-digit code, or paste its pairing link for confirmation.")
                if client.homeAsk == nil {
                    Text("Address").font(.headline)
                    TextField("Hostname or IP, optionally :port", text: $address)
                        .accessibilityLabel("Mac address")
                }
                Text("Pairing Code").font(.headline)
                TextField("12-digit pairing code", text: $code)
                    .accessibilityLabel("12-digit pairing code")
                    .onSubmit { if !working && client.pendingLink == nil { pair() } }
                HStack {
                    Button("Pair") { pair() }.disabled(working || client.pendingLink != nil)
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
                    Button("Cancel", role: .cancel) {
                        client.cancelPendingLink()
                        client.cancelPairing()
                        code = ""
                        linkError = nil
                        close()
                    }
                    .keyboardShortcut(.cancelAction)
                }
                if client.homeAsk?.phase == .asking {
                    HStack { ProgressView().controlSize(.small); Text(client.status) }
                } else {
                    Text(client.status).foregroundStyle(.secondary).textSelection(.enabled)
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
                        Button("Confirm Pairing") { client.confirmPendingLink() }.disabled(working)
                        Button("Discard Link", role: .cancel) { client.cancelPendingLink() }
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
        .frame(width: 480)
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
