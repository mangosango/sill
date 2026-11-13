import SwiftUI
import AppKit
import Combine
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
    private(set) lazy var menu = ViewerMenuModel(client: client)
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
    @Environment(\.controlActiveState) private var activeState

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

    private var chrome: Bool {
        ViewerChromePolicy.shows(connected: client.connected, controlling: input.controlling,
                                 hover: window.chromeHover, fullScreen: window.fullScreen)
    }

    /// The frame's margins around the picture. The hidden frame and controls wait this far in,
    /// behind the picture, so they grow and slide out from behind it.
    private var frameInset: EdgeInsets {
        let i = ViewerChromePolicy.insets
        return EdgeInsets(top: i.top, leading: i.left, bottom: i.bottom, trailing: i.right)
    }
    /// Where the picture sits: inside the frame in an expanded window, edge to edge otherwise.
    private var inset: EdgeInsets { window.fullScreen || !window.expanded ? EdgeInsets() : frameInset }
    private var radius: CGFloat { window.fullScreen ? 0 : ViewerChromePolicy.pictureRadius }
    /// A window keeps the remote display's shape only for the Desktop; a remote window fits the viewer.
    private var aspect: CGSize? {
        client.connected && client.active == .desktop && client.videoSize != .zero ? client.videoSize : nil
    }

    var body: some View {
        Group {
            if client.connected {
                ZStack(alignment: .top) {
                    // The frame and its controls grow out from behind the picture, as in iPhone Mirroring.
                    if !window.fullScreen {
                        // iPhone Mirroring's material. Glass draws a rim and shadow outside its shape,
                        // which showed around the collapsed frame and was cut off at the window's edge.
                        // Hidden, it matches the picture's corners, so it never looks rounder than the picture.
                        RoundedRectangle(cornerRadius: chrome ? ViewerChromePolicy.frameRadius : ViewerChromePolicy.pictureRadius,
                                         style: .continuous)
                            // Solid while the window is inactive, as the system's window frames are.
                            .fill(activeState == .key ? AnyShapeStyle(.ultraThinMaterial)
                                                      : AnyShapeStyle(Color(nsColor: .windowBackgroundColor)))
                            .overlay { if chrome { ViewerTitlebarDrag() } }
                            .padding(chrome ? EdgeInsets() : frameInset)
                        ViewerChrome(session: session, title: title, fullScreen: false, shown: chrome)
                            .offset(x: chrome ? 0 : frameInset.leading, y: chrome ? 0 : frameInset.top)
                            .opacity(chrome ? 1 : 0)
                            .allowsHitTesting(chrome)
                    }
                    ViewerPicture(client: client, input: input, radius: radius)
                        .overlay {
                            // Released full screen dims the picture under the controls; clicks still take control.
                            Color.black.opacity(window.fullScreen && !input.controlling ? 0.4 : 0)
                                .allowsHitTesting(false)
                                .animation(.easeOut(duration: 0.2), value: input.controlling)
                        }
                        .overlay {
                            if let shade = client.lockShade {
                                VStack(spacing: 8) {
                                    Text(LockedMac.title(mac: client.hostName, shade: shade)).font(.headline)
                                    if let detail = LockedMac.detail(shade: shade, paired: client.settings.host?.sessionPaired) { Text(detail) }
                                }.padding().frame(maxWidth: .infinity, maxHeight: .infinity).background(.background)
                            }
                        }
                        .overlay(alignment: .bottom) {
                            ViewerNotices(client: client, input: input, hasControlled: hasControlled, fullScreen: window.fullScreen)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                        .padding(inset)
                        // The window moves by the same amount in the same pass; animating would shake the picture.
                        .animation(nil, value: window.expanded)
                    if chrome && window.fullScreen {
                        ViewerChrome(session: session, title: title, fullScreen: true, shown: true)
                            .transition(.opacity)
                    }
                }
                .animation(.spring(duration: 0.3, bounce: 0.12), value: chrome)
                // A session window draws under where a title bar would be; the chooser keeps its insets.
                .ignoresSafeArea()
            } else {
                ViewerConnectView(client: client)
            }
        }
        .frame(minWidth: 480, minHeight: 320)
        .background(ViewerWindowReader(state: window, connected: client.connected, chrome: chrome, aspect: aspect, close: session.disconnect, release: input.release))
        .background(alignment: .topTrailing) {
            if client.connected {
                RemoteMenus(client: client).frame(width: 1, height: 1).opacity(0)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .navigationTitle(title)
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

/// The session's controls: in the frame's title bar in a window, a glass capsule over the picture in full screen.
private struct ViewerChrome: View {
    let session: ViewerSession
    @ObservedObject private var menu: ViewerMenuModel
    let title: String
    let fullScreen: Bool
    let shown: Bool

    init(session: ViewerSession, title: String, fullScreen: Bool, shown: Bool) {
        self.session = session
        menu = session.menu
        self.title = title
        self.fullScreen = fullScreen
        self.shown = shown
    }

    var body: some View {
        if fullScreen {
            bar.padding(.horizontal, 18)
                .frame(height: ViewerChromePolicy.fullScreenHeight)
                .viewerGlass(Capsule())
                .padding(.top, ViewerChromePolicy.fullScreenInset)
        } else {
            // Empty space falls through to the frame, which moves the window.
            HStack(spacing: 0) {
                ViewerTrafficLights(shown: shown).frame(width: ViewerChromePolicy.lightsPitch * 2 + 14, height: 14)
                Spacer(minLength: 16)
                bar.foregroundStyle(.secondary)
            }
            .background {
                // Centered as a title bar centers it; never under the lights or the controls.
                Text(title).font(Font(NSFont.titleBarFont(ofSize: 0))).lineLimit(1).truncationMode(.middle)
                    .padding(.horizontal, 150)
                    .allowsHitTesting(false)
            }
            .padding(.leading, ViewerChromePolicy.lightsLeading)
            .padding(.trailing, ViewerChromePolicy.margin + 8)
            .frame(height: ViewerChromePolicy.titlebar)
        }
    }

    private var bar: some View {
        HStack(spacing: 16) {
            if fullScreen {
                Text(title).font(.headline).lineLimit(1).truncationMode(.middle).frame(maxWidth: 360, alignment: .leading)
            }
            ViewerSourceMenu(session: session)
            Button { session.toggleControl() } label: {
                Label("Control Remote Mac", systemImage: "cursorarrow.rays")
            }.help("Control Remote Mac. Control-Option-Command-K releases input.")
                .disabled(menu.snapshot.macLocked)
            Menu { ViewerSessionActions(session: session) } label: { Label("Session Actions", systemImage: "ellipsis.circle") }
                .help("Session Actions")
            if fullScreen {
                Button { session.toggleFullScreen() } label: {
                    Label("Exit Full Screen", systemImage: "arrow.down.right.and.arrow.up.left")
                }.help("Exit Full Screen")
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The system's close, minimize and full screen buttons in the frame of a window without a title bar.
private struct ViewerTrafficLights: NSViewRepresentable {
    let shown: Bool

    final class Lights: NSView {
        private let buttons: [NSButton]
        private var hovering = false
        /// Hidden lights sit behind the picture; they never take its clicks.
        var shown = false {
            didSet {
                guard shown != oldValue else { return }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.25
                    animator().alphaValue = shown ? 1 : 0
                }
            }
        }
        override func hitTest(_ point: NSPoint) -> NSView? { shown ? super.hitTest(point) : nil }

        init() {
            let mask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
            buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
                .compactMap { NSWindow.standardWindowButton($0, for: mask) }
            super.init(frame: .zero)
            alphaValue = 0
            for (index, button) in buttons.enumerated() {
                button.setFrameOrigin(NSPoint(x: CGFloat(index) * ViewerChromePolicy.lightsPitch, y: 0))
                addSubview(button)
            }
        }
        required init?(coder: NSCoder) { fatalError("not used") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let actions = [#selector(NSWindow.performClose(_:)), #selector(NSWindow.performMiniaturize(_:)),
                           #selector(NSWindow.toggleFullScreen(_:))]
            for (button, action) in zip(buttons, actions) {
                button.target = window
                button.action = action
                button.isEnabled = true
            }
        }
        /// The bounds, not `.inVisibleRect`: SwiftUI's hosting can report an empty visible rect,
        /// and then the buttons never learn the pointer is over them.
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
            if let window { hover(bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))) }
        }
        override func mouseEntered(with event: NSEvent) { hover(true) }
        override func mouseExited(with event: NSEvent) { hover(false) }
        private func hover(_ next: Bool) {
            guard next != hovering else { return }
            hovering = next
            // As the title bar does: the buttons redraw their symbols after asking `_mouseInGroup:`.
            let refresh = NSSelectorFromString("mouseEnteredOrExited")
            for button in buttons {
                if button.responds(to: refresh) { button.perform(refresh) }
                button.needsDisplay = true
            }
        }
        /// The buttons ask their superview whether to draw their symbols, as in a title bar.
        @objc func _mouseInGroup(_ button: NSButton) -> Bool { hovering }
    }
    func makeNSView(context: Context) -> Lights { Lights() }
    func updateNSView(_ view: Lights, context: Context) { view.shown = shown }
}

/// The empty frame moves the window, as a title bar does.
private struct ViewerTitlebarDrag: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            guard event.clickCount == 2 else { window?.performDrag(with: event); return }
            switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
            case "Minimize": window?.performMiniaturize(nil)
            case "None": break
            default: window?.performZoom(nil)
            }
        }
    }
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {}
}

/// Status and recovery text on glass at the bottom of the picture, never above the remote menu bar.
private struct ViewerNotices: View {
    @ObservedObject var client: StreamClient
    @ObservedObject var input: ViewerInputState
    let hasControlled: Bool
    let fullScreen: Bool

    var body: some View {
        VStack(spacing: 8) {
            if let recovery = ViewerWindowPolicy.recovery(notice: client.notice?.text, noSource: client.active == .none,
                                                          hasVideo: client.videoSize != .zero, slowLink: client.slowLink) {
                notice(Text(recovery).accessibilityAddTraits(.updatesFrequently))
            }
            if let problem = client.settingsProblem { notice(Text(problem).foregroundStyle(.red)) }
            if let note = client.clipboardNote { notice(Text(note.text)) }
            if !input.controlling, let failure = input.captureFailure {
                notice(VStack(alignment: .leading, spacing: 8) {
                    Text(failure.message).accessibilityLabel("Keyboard capture: \(failure.message)")
                    if failure == .permission || failure == .unavailable {
                        Button("Allow Keyboard Capture…") { MacKeyboardCapture.requestPermission() }
                    }
                })
            } else if !input.controlling, !hasControlled {
                notice(Text(fullScreen
                    ? "Click the picture to control. The pointer, keyboard shortcuts and trackpad gestures go to the remote Mac until Control-Option-Command-K releases input."
                    : "Click the picture to control. Keyboard shortcuts and trackpad gestures go to the remote Mac. Control-Option-Command-K releases input.")
                    .foregroundStyle(.secondary))
            }
        }
        .padding(16)
        .frame(maxWidth: 560)
    }

    private func notice(_ content: some View) -> some View {
        content.font(.callout).textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .viewerGlass(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private extension View {
    /// Liquid Glass from macOS 26; a material before it.
    @ViewBuilder func viewerGlass<S: Shape>(_ shape: S) -> some View {
        if #available(macOS 26, *) { glassEffect(.regular, in: shape) }
        else { background(.regularMaterial, in: shape) }
    }
}

private struct ViewerPicture: NSViewRepresentable {
    let client: StreamClient
    let input: ViewerInputState
    let radius: CGFloat
    @AppStorage("SillViewer.reverseScrolling") private var reverseScrolling = false
    func makeNSView(context: Context) -> ViewerSurface { ViewerSurface(client: client, inputState: input) }
    func updateNSView(_ view: ViewerSurface, context: Context) {
        // SwiftUI's clip does not reach the video layer; round the layer too.
        view.wantsLayer = true
        view.layer?.cornerRadius = radius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = radius > 0
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

/// What the session menus show. The client publishes link statistics every second, and each
/// publish rebuilt every menu and closed any open submenu. This model publishes only when what
/// the menus show changes. Menu views read it as `client` and act through `session.client`.
@MainActor
final class ViewerMenuModel: ObservableObject {
    struct Snapshot: Equatable {
        var connected = false
        var macLocked = false
        var windows: [WindowInfo] = []
        var apps: [AppInfo] = []
        var textScaleSelectable = false
        var textScaleOffersOff = false
        var hostClipboard: Int?
        var soundMuted = false
    }
    @Published private(set) var snapshot = Snapshot()
    private var watch: AnyCancellable?

    init(client: StreamClient) {
        refresh(from: client)
        // objectWillChange comes before the change; read the client after it.
        watch = client.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self, weak client] _ in
            MainActor.assumeIsolated { if let client { self?.refresh(from: client) } }
        }
    }

    private func refresh(from client: StreamClient) {
        let next = Snapshot(connected: client.connected, macLocked: client.macLocked, windows: client.windows,
            apps: client.apps, textScaleSelectable: client.textScaleSelectable,
            textScaleOffersOff: client.textScaleOffersOff, hostClipboard: client.hostClipboard,
            soundMuted: client.soundMuted)
        if next != snapshot { snapshot = next }
    }
}

private struct ViewerControlCommand: View {
    let session: ViewerSession
    @ObservedObject private var input: ViewerInputState
    @ObservedObject private var menu: ViewerMenuModel
    init(session: ViewerSession) { self.session = session; input = session.input; menu = session.menu }
    private var client: ViewerMenuModel.Snapshot { menu.snapshot }
    var body: some View {
        Button(input.controlling ? "Release Input" : "Control Remote Mac") { session.toggleControl() }
            .disabled(!client.connected || client.macLocked)
    }
}

private struct ViewerSourceMenu: View {
    let session: ViewerSession
    @ObservedObject private var menu: ViewerMenuModel
    init(session: ViewerSession) { self.session = session; menu = session.menu }
    private var client: ViewerMenuModel.Snapshot { menu.snapshot }
    var body: some View {
        Menu {
            Button("Desktop") { session.input.release(); session.client.select(.desktop) }
            Menu("Windows") {
                ForEach(client.windows) { window in
                    Button("\(window.appName) — \(window.title)") { session.input.release(); session.client.select(.window(window.id)) }
                }
            }
            Menu("Apps") {
                ForEach(client.apps) { app in
                    Button(app.name) { session.input.release(); session.client.launch(bundleID: app.bundleID) }
                }
            }
        } label: { Label("Source", systemImage: "rectangle.on.rectangle") }
            .help("Source")
            .disabled(!client.connected || client.macLocked)
            .simultaneousGesture(TapGesture().onEnded { session.input.release() })
    }
}

private struct ViewerSessionActions: View {
    let session: ViewerSession
    @ObservedObject private var menu: ViewerMenuModel
    @AppStorage(StreamClient.clipboardKey) private var sharing = true
    init(session: ViewerSession) { self.session = session; menu = session.menu }
    private var client: ViewerMenuModel.Snapshot { menu.snapshot }
    var body: some View {
        Button("Remote Menus") { session.showRemoteMenus() }.disabled(!client.connected || client.macLocked)
        Menu("Aa — Text Size") {
            ForEach(TextScale.detents(offered: client.textScaleOffersOff), id: \.self) { value in
                Button(TextScale.title(at: value)) {
                    session.input.release()
                    session.scale = value
                    if var viewport = session.client.lastViewport {
                        viewport.scale = TextScale.scale(at: value)
                        session.client.sendViewport(viewport)
                    }
                }
            }
        }.disabled(!client.connected || !client.textScaleSelectable || client.macLocked)
        Button("Transfer Local Text to Remote Clipboard") { session.input.release(); session.client.transferLocalClipboard() }
            .disabled(!client.connected || !sharing || client.macLocked || !ClipboardPolicy.hostTakes(client.hostClipboard))
        Toggle("Mute This Viewer", isOn: Binding(get: { client.soundMuted }, set: { session.input.release(); session.client.setSoundMuted($0) }))
        Button("Remote Mac Settings…") { session.showSettings(.remoteMac) }
        Divider()
        Button("Disconnect") { session.disconnect() }
            .keyboardShortcut("d", modifiers: [.command, .shift]).disabled(!client.connected)
    }
}
