import AppKit
import StreamProtocol
let rect = CGRect(x: 20, y: 40, width: 200, height: 100)
assert(MacPointerGeometry.point(CGPoint(x: 120, y: 65), in: rect, clamp: false) == CGPoint(x: 0.5, y: 0.25))
assert(MacPointerGeometry.point(.zero, in: rect, clamp: false) == nil)
assert(MacPointerGeometry.point(CGPoint(x: 300, y: -10), in: rect, clamp: true) == CGPoint(x: 1, y: 0))
assert(MacPointerGeometry.point(.zero, in: .zero, clamp: true) == nil)
assert(MacPointerGeometry.phases([.began, .ended], momentum: false) == [.began, .ended])
assert(MacPointerGeometry.moved(CGPoint(x: 0.5, y: 0.5), dx: 24, dy: -13, in: CGSize(width: 240, height: 130)) == CGPoint(x: 0.6, y: 0.4))
assert(MacPointerGeometry.moved(CGPoint(x: 0.9, y: 0.1), dx: 500, dy: -500, in: CGSize(width: 240, height: 130)) == CGPoint(x: 1, y: 0))
assert(MacPointerGeometry.moved(CGPoint(x: 0.3, y: 0.3), dx: 5, dy: 5, in: .zero) == CGPoint(x: 0.3, y: 0.3))
assert(MacPointerGeometry.phases(.changed, momentum: true).isEmpty)
assert(MacPointerGeometry.phases(.cancelled, momentum: true) == [.momentumEnded])
for mask in 0..<16 {
    assert(MacPointerGeometry.acceptsInput(keyWindow: mask & 1 != 0, firstResponder: mask & 2 != 0, connected: mask & 4 != 0, paused: mask & 8 != 0) == (mask == 7))
}
assert(MacViewportRate.wanted(screen: 120, lowPower: false, away: false) == 120)
assert(MacViewportRate.wanted(screen: 120, lowPower: true, away: false) == 60)
assert(MacViewportRate.wanted(screen: 120, lowPower: false, away: true) == 60)
assert(MacViewportRate.wanted(screen: 30, lowPower: true, away: true) == 30)
assert(MacViewportRate.wanted(screen: 0, lowPower: false, away: false) == 30)

print("Mac pointer/viewport: 28 assertions passed")
