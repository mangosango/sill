import AppKit

/// Main-thread only. Reads happen solely from the explicit transfer action, never on activation.
final class MacClipboard {
    static let provenance = NSPasteboard.PasteboardType("me.saffer.sill.viewer.clipboard")
    private let board: NSPasteboard
    private var owned: (count: Int, token: String)?
    private var expiry: DispatchWorkItem?

    init(board: NSPasteboard) { self.board = board }
    var changeCount: Int { board.changeCount }

    func readForTransfer(maxBytes: Int) -> String? {
        // Do not offer received text back, even after a session reset; a newer local copy is fine.
        guard board.availableType(from: [Self.provenance]) == nil,
              let text = board.string(forType: .string), !text.isEmpty,
              text.utf8.count <= maxBytes else { return nil }
        return text
    }

    func write(_ text: String, lifetime: TimeInterval) {
        expiry?.cancel()
        let token = UUID().uuidString
        board.prepareForNewContents(with: .currentHostOnly)
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setString(token, forType: Self.provenance)
        guard board.writeObjects([item]) else { owned = nil; return }
        owned = (board.changeCount, token)
        let work = DispatchWorkItem { [weak self] in self?.expireOwnedWrite() }
        expiry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + lifetime, execute: work)
    }

    func expireOwnedWrite() {
        expiry?.cancel()
        expiry = nil
        guard let owned else { return }
        self.owned = nil
        // Check the count before reading the marker: never read a newer local copy on a timer.
        guard board.changeCount == owned.count,
              board.string(forType: Self.provenance) == owned.token else { return }
        board.clearContents()
    }

    /// Session end removes only this adapter's still-owned remote copy.
    func reset() { expireOwnedWrite() }
    deinit { expiry?.cancel() }

    static func announce(_ text: String) {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
}
