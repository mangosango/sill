import SwiftUI
import AppKit
import StreamProtocol

@main
struct SillViewerApp: App {
    @StateObject private var session = ViewerSession()

    var body: some Scene {
        Window("Macs", id: "viewer") {
            ViewerWindowContent(session: session)
        }
        .defaultSize(width: 600, height: 460)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            ViewerChooserCommands()
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { session.showSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandMenu("Session") {
                ViewerSourceMenu(session: session)
                ViewerControlCommand(session: session)
                ViewerSessionActions(session: session)
            }
            CommandGroup(after: .toolbar) {
                ViewerFullScreenCommand(session: session)
            }
        }
    }
}

@MainActor
final class ViewerSession: ObservableObject {
    let client = StreamClient()
    let input = ViewerInputState()
    let window = ViewerWindowState()
    @Published var scale = TextScale.off
    private var started = false
    private lazy var settings = ViewerSettingsWindowController(client: client, releaseInput: { [weak self] in self?.input.release() })

    func start() {
        guard !started else { return }
        started = true
        client.startBrowsing()
    }
    func disconnect() { input.release(); client.disconnect() }
    func showSettings(_ pane: ViewerSettingsPane? = nil) { input.release(); settings.show(pane: pane) }
    func toggleControl() {
        if input.controlling { input.release() }
        else if client.connected && !client.macLocked { input.takeControl() }
    }
    func toggleFullScreen() { input.release(); window.window?.toggleFullScreen(nil) }
    func showRemoteMenus() {
        input.release()
        NotificationCenter.default.post(name: .viewerOpenRemoteMenus, object: window.window)
    }
}

private struct ViewerWindowContent: View {
    @ObservedObject var session: ViewerSession
    @ObservedObject private var client: StreamClient
    @ObservedObject private var input: ViewerInputState
    @ObservedObject private var window: ViewerWindowState
    @State private var hasControlled = false

    init(session: ViewerSession) {
        self.session = session
        client = session.client
        input = session.input
        window = session.window
    }
    private var title: String {
        guard client.connected else { return "Macs" }
        let source: String
        switch client.active {
        case .desktop: source = "Desktop"
        case .window(let id): source = client.windows.first(where: { $0.id == id })?.title ?? "Window"
        case .none: source = "Connecting…"
        }
        return "\(client.hostName) — \(source)"
    }

    var body: some View {
        Group {
            if client.connected {
                VStack(spacing: 0) {
                    if !input.controlling {
                        VStack(spacing: 6) {
                            HStack {
                                Text(hasControlled ? "Input released" : "View only").font(.headline)
                                Spacer()
                                Button("Control Remote Mac") { session.toggleControl() }.disabled(client.macLocked)
                                if window.fullScreen { Button("Exit Full Screen") { session.toggleFullScreen() } }
                            }
                            if let failure = input.captureFailure {
                                Text(failure.message).font(.callout)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .accessibilityLabel("Keyboard capture: \(failure.message)")
                                if failure == .permission || failure == .unavailable {
                                    Button("Allow Keyboard Capture…") { MacKeyboardCapture.requestPermission() }
                                }
                            }
                            if !hasControlled {
                                Text("Click the picture to control. Keyboard shortcuts go to the remote Mac. Control-Option-Command-K releases input.")
                                    .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }.padding(10).background(.background)
                    }
                    ViewerPicture(client: client, input: input)
                        .overlay {
                            if let shade = client.lockShade {
                                VStack(spacing: 8) {
                                    Text(LockedMac.title(mac: client.hostName, shade: shade)).font(.headline)
                                    if let detail = LockedMac.detail(shade: shade, paired: client.settings.host?.sessionPaired) { Text(detail) }
                                }.padding().frame(maxWidth: .infinity, maxHeight: .infinity).background(.background)
                            }
                        }
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    if let recovery = ViewerWindowPolicy.recovery(notice: client.notice?.text, noSource: client.active == .none,
                                                                  hasVideo: client.videoSize != .zero, slowLink: client.slowLink) {
                        Text(recovery).font(.callout).textSelection(.enabled).accessibilityAddTraits(.updatesFrequently)
                            .padding(8).frame(maxWidth: .infinity, alignment: .leading).background(.background)
                    }
                    if let problem = client.settingsProblem {
                        Text(problem).font(.callout).foregroundStyle(.red).textSelection(.enabled).padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading).background(.background)
                    }
                    if let note = client.clipboardNote {
                        Text(note.text).font(.callout).textSelection(.enabled).padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading).background(.background)
                    }
                }
            } else {
                ViewerConnectView(client: client)
            }
        }
        .frame(minWidth: 480, minHeight: 320)
        .background(ViewerWindowReader(state: window, connected: client.connected, close: session.disconnect, release: input.release))
        .background(alignment: .topTrailing) {
            if client.connected {
                RemoteMenus(client: client).frame(width: 1, height: 1).opacity(0)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .navigationTitle(title)
        .toolbar {
            if client.connected {
                ToolbarItem { ViewerSourceMenu(session: session) }
                ToolbarItem {
                    Button { session.toggleControl() } label: {
                        Label(input.controlling ? "Release Input" : "Control Remote Mac", systemImage: input.controlling ? "hand.raised" : "cursorarrow")
                    }.help(input.controlling ? "Release Input (Control-Option-Command-K), or move the pointer outside the remote view" : "Control Remote Mac")
                        .disabled(client.macLocked)
                }
                ToolbarItem {
                    Menu { ViewerSessionActions(session: session) } label: { Label("Session Actions", systemImage: "ellipsis.circle") }
                }
            }
        }
        .onAppear { session.start() }
        .onChange(of: client.connected) { _, _ in input.release(); hasControlled = false }
        .onChange(of: input.controlling) { _, controlling in if controlling { hasControlled = true } }
        .onExitCommand {
            guard !input.controlling, window.fullScreen, window.window?.attachedSheet == nil,
                  NSApp.modalWindow == nil else { return }
            session.toggleFullScreen()
        }
    }
}

private struct ViewerPicture: NSViewRepresentable {
    let client: StreamClient
    let input: ViewerInputState
    @AppStorage("SillViewer.reverseScrolling") private var reverseScrolling = false
    func makeNSView(context: Context) -> ViewerSurface { ViewerSurface(client: client, inputState: input) }
    func updateNSView(_ view: ViewerSurface, context: Context) {
        view.input.reverseScrolling = reverseScrolling
        view.refresh()
    }
    static func dismantleNSView(_ view: ViewerSurface, coordinator: ()) { view.detach() }
}

private struct ViewerFullScreenCommand: View {
    let session: ViewerSession
    @ObservedObject private var window: ViewerWindowState
    init(session: ViewerSession) { self.session = session; window = session.window }
    var body: some View {
        Button(window.fullScreen ? "Exit Full Screen" : "Enter Full Screen") { session.toggleFullScreen() }
            .keyboardShortcut("f", modifiers: [.control, .command])
    }
}

private struct ViewerControlCommand: View {
    let session: ViewerSession
    @ObservedObject private var input: ViewerInputState
    @ObservedObject private var client: StreamClient
    init(session: ViewerSession) { self.session = session; input = session.input; client = session.client }
    var body: some View {
        Button(input.controlling ? "Release Input" : "Control Remote Mac") { session.toggleControl() }
            .disabled(!client.connected || client.macLocked)
    }
}

private struct ViewerSourceMenu: View {
    @ObservedObject var session: ViewerSession
    @ObservedObject private var client: StreamClient
    init(session: ViewerSession) { self.session = session; client = session.client }
    var body: some View {
        Menu("Source") {
            Button("Desktop") { session.input.release(); client.select(.desktop) }
            Menu("Windows") {
                ForEach(client.windows) { window in
                    Button("\(window.appName) — \(window.title)") { session.input.release(); client.select(.window(window.id)) }
                }
            }
            Menu("Apps") {
                ForEach(client.apps) { app in
                    Button(app.name) { session.input.release(); client.launch(bundleID: app.bundleID) }
                }
            }
        }.disabled(!client.connected || client.macLocked)
            .simultaneousGesture(TapGesture().onEnded { session.input.release() })
    }
}

private struct ViewerSessionActions: View {
    @ObservedObject var session: ViewerSession
    @ObservedObject private var client: StreamClient
    @AppStorage(StreamClient.clipboardKey) private var sharing = true
    init(session: ViewerSession) { self.session = session; client = session.client }
    var body: some View {
        Button("Remote Menus") { session.showRemoteMenus() }.disabled(!client.connected || client.macLocked)
        Menu("Aa — Text Size") {
            ForEach(TextScale.detents(offered: client.textScaleOffersOff), id: \.self) { value in
                Button(TextScale.title(at: value)) {
                    session.input.release()
                    session.scale = value
                    if var viewport = client.lastViewport {
                        viewport.scale = TextScale.scale(at: value)
                        client.sendViewport(viewport)
                    }
                }
            }
        }.disabled(!client.connected || !client.textScaleSelectable || client.macLocked)
        Button("Transfer Local Text to Remote Clipboard") { session.input.release(); client.transferLocalClipboard() }
            .disabled(!client.connected || !sharing || client.macLocked || !ClipboardPolicy.hostTakes(client.hostClipboard))
        Toggle("Mute This Viewer", isOn: Binding(get: { client.soundMuted }, set: { session.input.release(); client.setSoundMuted($0) }))
        Button("Remote Mac Settings…") { session.showSettings(.remoteMac) }
        Divider()
        Button("Disconnect") { session.disconnect() }
            .keyboardShortcut("d", modifiers: [.command, .shift]).disabled(!client.connected)
    }
}
