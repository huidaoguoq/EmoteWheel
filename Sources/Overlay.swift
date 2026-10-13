import AppKit
import QuartzCore

private let wheelGold = NSColor(srgbRed: 0.78, green: 0.64, blue: 0.37, alpha: 1)
private let wheelCyan = NSColor(srgbRed: 0.35, green: 0.91, blue: 0.85, alpha: 1)

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(size: CGFloat, interactive: Bool = false) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: size, height: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = !interactive
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }
}

final class WheelView: NSView {
    let model: AppModel
    var selected: Int? { didSet { if oldValue != selected { needsDisplay = true } } }
    var isPreview = false
    var onClick: (() -> Void)?
    var onCancel: (() -> Void)?
    init(model: AppModel, frame: NSRect) { self.model = model; super.init(frame: frame) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func rightMouseDown(with event: NSEvent) { onCancel?() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let scale = bounds.width / 420
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let outer: CGFloat = 165 * scale
        let inner: CGFloat = 55 * scale

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.65)
        shadow.shadowBlurRadius = 24 * scale; shadow.set()
        NSColor(srgbRed: 0.025, green: 0.065, blue: 0.10, alpha: 0.97).setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - outer, y: center.y - outer, width: outer * 2, height: outer * 2)).fill()
        NSGraphicsContext.restoreGraphicsState()

        for index in 0..<8 {
            let angle = 90.0 - Double(index) * 45
            let path = NSBezierPath()
            path.appendArc(withCenter: center, radius: outer - 5 * scale,
                           startAngle: angle - 21.8, endAngle: angle + 21.8, clockwise: false)
            path.appendArc(withCenter: center, radius: inner + 3 * scale,
                           startAngle: angle + 21.8, endAngle: angle - 21.8, clockwise: true)
            path.close()
            let active = selected == index
            (active ? NSColor(srgbRed: 0.11, green: 0.28, blue: 0.30, alpha: 1) :
                NSColor(srgbRed: 0.045, green: 0.10, blue: 0.14, alpha: 1)).setFill()
            path.fill()
            (active ? wheelCyan : wheelGold.withAlphaComponent(0.30)).setStroke()
            path.lineWidth = active ? 1.8 * scale : 0.6 * scale
            path.stroke()

            let radians = angle * .pi / 180
            let location = CGPoint(x: center.x + cos(radians) * 112 * scale,
                                   y: center.y + sin(radians) * 112 * scale)
            let imageSize = (active ? 80.0 : 68.0) * scale
            if let image = model.image(for: model.config.slots[index]) {
                NSGraphicsContext.saveGraphicsState()
                if active {
                    let glow = NSShadow(); glow.shadowColor = wheelCyan.withAlphaComponent(0.55)
                    glow.shadowBlurRadius = 15; glow.set()
                }
                image.draw(in: NSRect(x: location.x - imageSize / 2, y: location.y - imageSize / 2,
                                     width: imageSize, height: imageSize), from: .zero, operation: .sourceOver, fraction: 1)
                NSGraphicsContext.restoreGraphicsState()
            }
        }

        for (radius, opacity, width) in [(outer, 0.9, 1.5), (outer + 5 * scale, 0.30, 0.7), (inner, 0.7, 1.0)] {
            wheelGold.withAlphaComponent(opacity).setStroke()
            let ring = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                                  width: radius * 2, height: radius * 2))
            ring.lineWidth = width * scale; ring.stroke()
        }
        NSColor(srgbRed: 0.025, green: 0.06, blue: 0.09, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - inner + 3, y: center.y - inner + 3,
                                  width: inner * 2 - 6, height: inner * 2 - 6)).fill()
        drawText(selected == nil ? "✦" : "↑", at: CGPoint(x: center.x, y: center.y + 3 * scale),
                 font: .systemFont(ofSize: 26 * scale, weight: .light), color: selected == nil ? wheelGold : wheelCyan)
        drawText(selected == nil ? "移回此处取消" : (isPreview ? "点击发送" : "松开发送"),
                 at: CGPoint(x: center.x, y: center.y - 21 * scale),
                 font: .systemFont(ofSize: 10 * scale, weight: .medium), color: .white.withAlphaComponent(0.65))
        let name = selected.flatMap { model.emote(for: model.config.slots[$0])?.name }
        drawText(name ?? (isPreview ? "移动选择 · 点击发送 · Esc 取消" : "\(model.shortcutLabel)  /  移动选择 · 松开发送"),
                 at: CGPoint(x: center.x, y: 12 * scale),
                 font: .systemFont(ofSize: 12 * scale, weight: .medium), color: .white.withAlphaComponent(0.92), shadow: true)
    }

    private func drawText(_ text: String, at point: CGPoint, font: NSFont, color: NSColor, shadow: Bool = false) {
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        if shadow { let s = NSShadow(); s.shadowColor = .black; s.shadowBlurRadius = 5; attrs[.shadow] = s }
        let string = NSAttributedString(string: text, attributes: attrs)
        string.draw(in: NSRect(x: point.x - bounds.width / 2, y: point.y, width: bounds.width, height: font.pointSize * 1.7))
    }
}

final class EmoteEffectView: NSView {
    let image: NSImage
    let imageLayer = CALayer()
    init(image: NSImage, frame: NSRect) {
        self.image = image
        super.init(frame: frame)
        wantsLayer = true
        imageLayer.frame = NSRect(x: 30, y: 30, width: 180, height: 180)
        var rect = NSRect(origin: .zero, size: image.size)
        imageLayer.contents = image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        imageLayer.contentsGravity = .resizeAspect
        imageLayer.shadowColor = NSColor.black.cgColor; imageLayer.shadowOpacity = 0.5; imageLayer.shadowRadius = 9
        layer?.addSublayer(imageLayer)
        let pop = CAKeyframeAnimation(keyPath: "transform.scale")
        pop.values = [0.35, 1.15, 0.95, 1]; pop.keyTimes = [0, 0.48, 0.76, 1]; pop.duration = 0.42
        imageLayer.add(pop, forKey: "pop")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class OverlayController {
    let model: AppModel
    private var panel: OverlayPanel?
    private var wheelView: WheelView?
    private var trackingTimer: Timer?
    private var effectPanel: OverlayPanel?
    private var effectTimer: Timer?
    private var center = CGPoint.zero
    private var initialPointer = CGPoint.zero
    private var hasMoved = false
    private var previewDeadline: Date?
    var active: Bool { panel != nil }
    var isPreview: Bool { previewDeadline != nil }

    init(model: AppModel) { self.model = model }

    func show(preview: Bool = false) {
        cancel()
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main else { return }
        let size = min(420 * model.config.wheelScale, min(screen.visibleFrame.width, screen.visibleFrame.height) - 20)
        let target = preview ? CGPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.midY) : pointer
        center = WheelMath.center(pointer: target, screen: screen.visibleFrame, size: size)
        initialPointer = pointer
        hasMoved = false
        let window = OverlayPanel(size: size, interactive: preview)
        window.setFrameOrigin(CGPoint(x: center.x - size / 2, y: center.y - size / 2))
        let view = WheelView(model: model, frame: NSRect(x: 0, y: 0, width: size, height: size))
        view.isPreview = preview
        view.onClick = { [weak self] in self?.commit() }
        view.onCancel = { [weak self] in self?.cancel() }
        window.contentView = view
        panel = window; wheelView = view
        previewDeadline = preview ? Date().addingTimeInterval(15) : nil
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in context.duration = 0.12; window.animator().alphaValue = 1 }
        model.wheelActive = true
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.trackPointer() }
        if let trackingTimer { RunLoop.main.add(trackingTimer, forMode: .common) }
    }

    private func trackPointer() {
        if let deadline = previewDeadline, Date() > deadline { cancel(); return }
        let point = NSEvent.mouseLocation
        if hypot(point.x - initialPointer.x, point.y - initialPointer.y) > 3 { hasMoved = true }
        guard hasMoved, let panel else { return }
        wheelView?.selected = WheelMath.slot(dx: point.x - center.x, dy: point.y - center.y,
                                             deadZone: 55 * panel.frame.width / 420)
    }

    func commit() {
        trackPointer()
        let selected = wheelView?.selected
        let point = center
        cancel()
        guard let selected else { return }
        let id = model.config.slots[selected]
        guard let emote = model.emote(for: id), let image = model.image(for: id) else { return }
        model.lastEmoteName = emote.name
        model.status = "已在桌面展示「\(emote.name)」"
        showEffect(image: image, at: point)
        if model.config.soundEnabled { NSSound(named: "Pop")?.play() }
    }

    func cancel() {
        trackingTimer?.invalidate(); trackingTimer = nil
        panel?.orderOut(nil); panel = nil; wheelView = nil
        previewDeadline = nil
        model.wheelActive = false
    }

    private func showEffect(image: NSImage, at point: CGPoint) {
        effectTimer?.invalidate()
        effectPanel?.orderOut(nil)
        let window = OverlayPanel(size: 240)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main!
        let effectCenter = WheelMath.center(pointer: point, screen: screen.visibleFrame, size: 240)
        window.setFrameOrigin(CGPoint(x: effectCenter.x - 120, y: effectCenter.y - 120))
        window.contentView = EmoteEffectView(image: image, frame: NSRect(x: 0, y: 0, width: 240, height: 240))
        window.orderFrontRegardless()
        effectPanel = window
        effectTimer = Timer.scheduledTimer(withTimeInterval: model.config.displayDuration, repeats: false) { [weak self, weak window] _ in
            guard let window else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                window.animator().alphaValue = 0
                window.animator().setFrameOrigin(CGPoint(x: window.frame.minX, y: window.frame.minY + 18))
            }, completionHandler: { [weak self, weak window] in
                window?.orderOut(nil)
                if self?.effectPanel === window { self?.effectPanel = nil }
            })
        }
    }
}
