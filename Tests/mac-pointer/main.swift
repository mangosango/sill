import AppKit
import StreamProtocol
let rect = CGRect(x: 20, y: 40, width: 200, height: 100)
assert(MacPointerGeometry.point(CGPoint(x: 120, y: 65), in: rect, clamp: false) == CGPoint(x: 0.5, y: 0.25))
assert(MacPointerGeometry.point(.zero, in: rect, clamp: false) == nil)
assert(MacPointerGeometry.point(CGPoint(x: 300, y: -10), in: rect, clamp: true) == CGPoint(x: 1, y: 0))
assert(MacPointerGeometry.point(.zero, in: .zero, clamp: true) == nil)
assert(MacPointerGeometry.phases([.began, .ended], momentum: false) == [.began, .ended])
assert(MacPointerGeometry.phases(.changed, momentum: true).isEmpty)
assert(MacPointerGeometry.phases(.cancelled, momentum: true) == [.momentumEnded])
for mask in 0..<16 {
    assert(MacPointerGeometry.acceptsInput(keyWindow: mask & 1 != 0, firstResponder: mask & 2 != 0, connected: mask & 4 != 0, paused: mask & 8 != 0) == (mask == 7))
}
print("Mac pointer: 23 assertions passed")
