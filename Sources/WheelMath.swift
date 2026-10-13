import Foundation
import CoreGraphics

enum WheelMath {
    // Coordinates use the macOS convention: positive y points up.
    static func slot(dx: Double, dy: Double, deadZone: Double) -> Int? {
        guard hypot(dx, dy) > deadZone else { return nil }
        let angle = atan2(dx, dy)
        return (Int(floor((angle + .pi / 8) / (.pi / 4))) + 8) % 8
    }

    static func center(pointer: CGPoint, screen: CGRect, size: CGFloat) -> CGPoint {
        let half = size / 2 + 8
        return CGPoint(x: min(max(pointer.x, screen.minX + half), screen.maxX - half),
                       y: min(max(pointer.y, screen.minY + half), screen.maxY - half))
    }
}

struct Emote: Codable, Identifiable {
    var id: String
    var name: String
    var subtitle: String
    var filename: String
    var keywords: [String]? = nil
}

struct Configuration: Codable {
    var enabled = true
    var keyCode: UInt16 = 16
    var keyLabel = "Y"
    var modifiers: UInt64 = 0
    var slots = ["1505", "1459", "3159", "3154", "1506", "1498", "1499", "1030"]
    var wheelScale = 1.0
    var displayDuration = 2.4
    var soundEnabled = false
    var customEmotes: [Emote] = []
}
