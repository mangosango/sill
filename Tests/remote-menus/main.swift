import AppKit

final class StreamClient {
    var connected = true
    var macLocked = false
    var menus = MacMenuState()
    var completions: [(MacMenuState.Content) -> Void] = []
    var pressed: [MacMenuState.Row] = []
    func fetchTopMenu(id: String, title: String, builtVersion: Int, completion: @escaping (MacMenuState.Content) -> Void) { completions.append(completion) }
    func fetchMenu(_ row: MacMenuState.Row, completion: @escaping (MacMenuState.Content) -> Void) { completions.append(completion) }
    func pressMenuItem(_ row: MacMenuState.Row) { pressed.append(row) }
}
let client = StreamClient()
let row = MacMenuState.Row(kind: .submenu, id: "1", title: "File", version: 1)
let menu = MenuLoader.menu(for: row, topLevelVersion: 1, id: "1", client: client)
let loader = menu.delegate as! MenuLoader
loader.menuNeedsUpdate(menu)
loader.menuDidClose(menu)
client.completions[0](.message("late"))
assert(menu.items.first?.title == "Loading…")
loader.menuNeedsUpdate(menu)
client.completions[0](.message("older open"))
assert(menu.items.first?.title == "Loading…")
client.completions[1](.message("Timed out"))
assert(menu.items.first?.title == "Timed out")
assert(menu.items.first?.isEnabled == false)
loader.menuNeedsUpdate(menu)
client.connected = false
client.completions[2](.message("departed"))
assert(menu.items.first?.title == "Loading…")
client.connected = true
loader.menuNeedsUpdate(menu)
let leaf = MacMenuState.Row(kind: .item, id: "1.1", title: "Save", key: "⌘S", mark: .on, version: 1)
client.completions[3](.sections([[leaf]], more: 0))
assert(menu.items[0].keyEquivalent.isEmpty)
assert(menu.items[0].state == .on)
// AppKit derives title from attributedTitle; the wire choice must retain the original row.
assert(menu.items[0].title == "Save\t⌘S")
assert(menu.items[0].attributedTitle?.string == "Save\t⌘S")
let item = menu.items[0]
_ = (item.target as? NSObject)?.perform(item.action!, with: item)
assert(client.pressed.first?.title == "Save")
assert(client.pressed.first?.id == "1.1")
loader.menuNeedsUpdate(menu)
client.macLocked = true
client.completions[4](.message("locked"))
assert(menu.items.first?.title == "Loading…")
print("RemoteMenus: 12 asynchronous loader/shortcut assertions passed")
