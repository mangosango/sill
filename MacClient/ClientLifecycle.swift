import AppKit

/// Key focus deliberately is not an input: an inactive visible window still shows its picture.
enum ClientVisibility {
    static func pictureVisible(awake: Bool, hidden: Bool, attached: Bool, visible: Bool, minimized: Bool) -> Bool {
        awake && !hidden && attached && visible && !minimized
    }
}

/// Per-session recovery visibility. Sleep suspends reconnects; wake refreshes liveness and browsing.
/// This does not own audio, clipboard activation or native input focus.
final class ClientLifecycle {
    private let window: () -> NSWindow?
    private let changed: (Bool, Bool, Bool) -> Void
    private var sleeping = false
    private var lastVisible: Bool?
    private var lastAwake: Bool?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    var pictureVisible: Bool {
        let own = window()
        return ClientVisibility.pictureVisible(awake: !sleeping, hidden: NSApplication.shared.isHidden,
                                               attached: own != nil, visible: own?.isVisible ?? false,
                                               minimized: own?.isMiniaturized ?? false)
    }

    init(window: @escaping () -> NSWindow?, changed: @escaping (Bool, Bool, Bool) -> Void) {
        self.window = window
        self.changed = changed
        let center = NotificationCenter.default
        for name in [NSApplication.didHideNotification, NSApplication.didUnhideNotification,
                     NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification,
                     NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification] {
            observe(center, name) { [weak self] note in
                guard let self else { return }
                if let other = note.object as? NSWindow, other !== self.window() { return }
                // Closing/ordering notifications can precede the window's updated visibility.
                DispatchQueue.main.async { [weak self] in self?.update(woke: false) }
            }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification) { [weak self] _ in
            self?.sleeping = true
            self?.update(woke: false)
        }
        observe(workspace, NSWorkspace.didWakeNotification) { [weak self] _ in
            self?.sleeping = false
            self?.update(woke: true)
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         action: @escaping (Notification) -> Void) {
        observers.append((center, center.addObserver(forName: name, object: nil, queue: .main, using: action)))
    }

    private func update(woke: Bool) {
        let visible = pictureVisible
        guard woke || lastVisible != visible || lastAwake != !sleeping else { return }
        lastVisible = visible
        lastAwake = !sleeping
        changed(!sleeping, visible, woke)
    }

    deinit {
        for (center, observer) in observers { center.removeObserver(observer) }
    }
}
