import Foundation
import CoreGraphics

@main
struct CoreTests {
    static func main() throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message); checks += 1
        }
        check(WheelMath.slot(dx: 0, dy: 0, deadZone: 55) == nil, "center must cancel")
        check(WheelMath.slot(dx: 0, dy: 55, deadZone: 55) == nil, "dead-zone boundary must cancel")
        for index in 0..<8 {
            let angle = Double(index) * .pi / 4
            check(WheelMath.slot(dx: sin(angle) * 120, dy: cos(angle) * 120, deadZone: 55) == index,
                  "clockwise slot mapping \(index)")
        }
        check(WheelMath.slot(dx: -1, dy: 100, deadZone: 55) == 0, "angle wrap near north")
        check(WheelMath.slot(dx: 1, dy: 100, deadZone: 55) == 0, "angle wrap near north")
        let screen = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        let size: CGFloat = 420
        for point in [CGPoint(x: -1920, y: -200), CGPoint(x: 0, y: 880), CGPoint(x: -100, y: -100)] {
            let center = WheelMath.center(pointer: point, screen: screen, size: size)
            check(screen.contains(CGRect(x: center.x-size/2, y: center.y-size/2, width: size, height: size)),
                  "wheel must fit on secondary screen with negative coordinates")
        }
        var config = Configuration()
        config.keyCode = 0; config.keyLabel = "A"; config.modifiers = 524288
        config.slots[2] = "custom-example"; config.wheelScale = 1.3; config.displayDuration = 5
        config.customEmotes = [Emote(id: "custom-example", name: "我的表情", subtitle: "我的表情", filename: "imports/example.png")]
        let restored = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(config))
        check(restored.slots[2] == "custom-example", "custom slot persistence")
        check(restored.keyCode == 0 && restored.modifiers == 524288, "modified shortcut persistence")
        check(restored.wheelScale == 1.3 && restored.displayDuration == 5, "slider persistence")
        check(restored.customEmotes.first?.name == "我的表情", "Unicode import metadata persistence")
        print("PASS: \(checks) core checks")
    }
}
