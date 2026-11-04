import AppKit
import SwiftUI

// MenuLoader and MenuChoice adapted from Alexander Deutsch’s PR #128 (173843be).
func remoteMenuNote(_ text: String) -> NSMenuItem {
    let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
    item.isEnabled = false
    return item
}

struct RemoteMenus: NSViewRepresentable {
    let client: StreamClient

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.setAccessibilityLabel("Remote Menus")
        context.coordinator.button = button
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        let top = client.menus.top
        guard context.coordinator.top != top || context.coordinator.connected != client.connected
                || context.coordinator.locked != client.macLocked else { return }
        context.coordinator.top = top
        context.coordinator.connected = client.connected
        context.coordinator.locked = client.macLocked
        // Replacing the tree cancels tracking and drops loaders from the previous session/tree.
        button.menu?.cancelTracking()
        let menu = NSMenu(title: "Remote Menus")
        menu.autoenablesItems = false
        menu.addItem(withTitle: "Menus", action: nil, keyEquivalent: "")
        if client.macLocked {
            menu.addItem(remoteMenuNote("Menus unavailable while the Mac is locked."))
        } else if !client.connected || !client.menus.hasMenus {
            menu.addItem(remoteMenuNote("Remote menus unavailable."))
        } else if top.stale {
            menu.addItem(remoteMenuNote(top.note ?? "The app isn’t responding."))
        } else {
            if let note = top.note { menu.addItem(remoteMenuNote(note)) }
            for row in top.menus {
                let item = NSMenuItem(title: row.title, action: nil, keyEquivalent: "")
                item.isEnabled = row.enabled
                if row.enabled, let id = row.id {
                    item.submenu = MenuLoader.menu(for: row, topLevelVersion: top.version, id: id, client: client)
                }
                menu.addItem(item)
            }
        }
        button.menu = menu
        menu.delegate = context.coordinator
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator: NSObject, NSMenuDelegate {
        weak var button: NSPopUpButton?
        private var openObserver: NSObjectProtocol?
        override init() {
            super.init()
            openObserver = NotificationCenter.default.addObserver(forName: Notification.Name("SillViewerOpenRemoteMenus"), object: nil, queue: .main) { [weak self] note in
                guard let button = self?.button, let window = note.object as? NSWindow,
                      button.window === window else { return }
                // Invoked synchronously from a local UI action, never from a network callback.
                button.menu?.popUp(positioning: nil, at: NSPoint(x: button.bounds.maxX, y: button.bounds.minY), in: button)
            }
        }
        deinit { if let openObserver { NotificationCenter.default.removeObserver(openObserver) } }
        var top: MacMenuState.Top?
        var connected = false
        var locked = false
        func menuWillOpen(_ menu: NSMenu) { NSApp.keyWindow?.makeFirstResponder(nil) }
    }
}

/// One menu of the other Mac's, filled in from that Mac each time it opens (uncached, like the iPad's
/// deferred elements): the top level's menus ask by the title they were built with, submenus in the
/// version their row came in.
final class MenuLoader: NSObject, NSMenuDelegate {
    private let row: MacMenuState.Row
    private let topLevelVersion: Int?
    private weak var client: StreamClient?
    /// The open that the answer belongs to: a menu closed and opened again ignores an older answer.
    private var generation = 0

    private init(row: MacMenuState.Row, topLevelVersion: Int?, client: StreamClient) {
        self.row = row
        self.topLevelVersion = topLevelVersion
        self.client = client
    }

    /// A submenu that loads itself; the loader lives as long as the menu (its delegate is weak).
    static func menu(for row: MacMenuState.Row, topLevelVersion: Int?, id: String, client: StreamClient) -> NSMenu {
        let menu = NSMenu(title: row.title)
        menu.autoenablesItems = false
        let loader = MenuLoader(row: row, topLevelVersion: topLevelVersion, client: client)
        menu.delegate = loader
        objc_setAssociatedObject(menu, &loaderKey, loader, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        menu.addItem(remoteMenuNote("Loading…"))
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        generation += 1
        let asked = generation
        menu.removeAllItems()
        menu.addItem(remoteMenuNote("Loading…"))
        guard let client else {
            fill(menu, with: .message(MacMenuState.notConnected))
            return
        }
        let done: (MacMenuState.Content) -> Void = { [weak self, weak menu, weak client] content in
            guard let self, let menu, let client, asked == self.generation, client.connected, !client.macLocked else { return }
            self.fill(menu, with: content, client: client)
        }
        if let version = topLevelVersion, let id = row.id {
            client.fetchTopMenu(id: id, title: row.title, builtVersion: version, completion: done)
        } else {
            client.fetchMenu(row, completion: done)
        }
    }

    func menuDidClose(_ menu: NSMenu) { generation += 1 }

    private func fill(_ menu: NSMenu, with content: MacMenuState.Content, client: StreamClient? = nil) {
        menu.removeAllItems()
        switch content {
        case .message(let text):
            menu.addItem(remoteMenuNote(text))
        case .sections(let sections, _):
            for (i, section) in sections.enumerated() {
                if i > 0 { menu.addItem(.separator()) }
                for row in section { menu.addItem(item(for: row, client: client)) }
            }
            if menu.items.isEmpty { menu.addItem(remoteMenuNote("No items")) }
        }
    }

    private func item(for row: MacMenuState.Row, client: StreamClient?) -> NSMenuItem {
        switch row.kind {
        case .note:
            return remoteMenuNote(row.title)
        case .submenu:
            let item = NSMenuItem(title: row.title, action: nil, keyEquivalent: "")
            item.isEnabled = row.enabled && row.id != nil
            if item.isEnabled, let client, let id = row.id {
                item.submenu = MenuLoader.menu(for: row, topLevelVersion: nil, id: id, client: client)
            }
            return item
        case .item:
            let item = NSMenuItem(title: row.title, action: #selector(MenuChoice.choose(_:)), keyEquivalent: "")
            let choice = MenuChoice(row: row, client: client)
            item.target = choice
            item.representedObject = choice     // the item keeps its target alive
            item.isEnabled = row.enabled
            switch row.mark {
            case .off: item.state = .off
            case .on: item.state = .on
            case .mixed: item.state = .mixed
            }
            if let key = row.key, !key.isEmpty { item.attributedTitle = Self.title(row.title, shortcut: key) }
            return item
        }
    }

    /// "Save" with "⇧⌘S" at the menu's right edge, in the secondary colour: the other Mac's shortcut,
    /// shown, never a key equivalent here.
    private static func title(_ title: String, shortcut: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: 260)]
        let font = NSFont.menuFont(ofSize: 0)
        let text = NSMutableAttributedString(string: title, attributes: [.font: font, .paragraphStyle: paragraph])
        text.append(NSAttributedString(string: "\t" + shortcut,
                                       attributes: [.font: font, .paragraphStyle: paragraph, .foregroundColor: NSColor.secondaryLabelColor]))
        return text
    }
}

private var loaderKey: UInt8 = 0

/// A chosen item: pressed on the other Mac, in the version its row came in.
private final class MenuChoice: NSObject {
    let row: MacMenuState.Row
    weak var client: StreamClient?

    init(row: MacMenuState.Row, client: StreamClient?) {
        self.row = row
        self.client = client
    }

    @objc func choose(_ sender: Any?) {
        guard let client, client.connected, !client.macLocked else { return }
        client.pressMenuItem(row)
    }
}
