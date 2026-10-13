import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class AppModel: ObservableObject {
    @Published var config: Configuration { didSet { save() } }
    @Published var catalog: [Emote] = []
    @Published var selectedSlot = 0
    @Published var isRecordingKey = false
    @Published var permissionGranted = false
    @Published var inputMonitoringGranted = false
    @Published var accessibilityGranted = false
    @Published var status = "可在此窗口按住 Y 体验"
    @Published var errorMessage: String?
    @Published var wheelActive = false
    @Published var lastEmoteName = ""
    var onPreview: (() -> Void)?
    var onRequestInputMonitoring: (() -> Void)?
    var onRequestAccessibility: (() -> Void)?
    var onRefreshPermissions: (() -> Void)?
    var onCancelInteraction: (() -> Void)?
    private let imageCache = NSCache<NSString, NSImage>()
    let supportURL: URL
    private let saveEnabled: Bool

    init(preview: Bool = false) {
        saveEnabled = !preview
        imageCache.countLimit = 128
        supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EmoteWheel", isDirectory: true)
        let configURL = supportURL.appendingPathComponent("settings.json")
        if !preview, let data = try? Data(contentsOf: configURL),
           let saved = try? JSONDecoder().decode(Configuration.self, from: data) {
            config = saved
        } else { config = Configuration() }
        if let url = Bundle.main.url(forResource: "emotes", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let bundled = try? JSONDecoder().decode([Emote].self, from: data) {
            catalog = bundled + config.customEmotes
        }
        // Recover only malformed settings; normal settings are used as-is.
        if config.slots.count != 8 { config.slots = Configuration().slots }
        config.wheelScale = min(max(config.wheelScale, 0.8), 1.3)
        config.displayDuration = min(max(config.displayDuration, 1), 5)
        for index in config.slots.indices where image(for: config.slots[index]) == nil {
            config.slots[index] = Configuration().slots[index]
        }
    }

    var shortcutLabel: String {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(config.modifiers))
        return (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "") +
            (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "") + config.keyLabel
    }

    func emote(for id: String) -> Emote? { catalog.first { $0.id == id } }

    func image(for id: String) -> NSImage? {
        if let cached = imageCache.object(forKey: id as NSString) { return cached }
        guard let item = emote(for: id) else { return nil }
        let url = item.id.hasPrefix("custom-")
            ? supportURL.appendingPathComponent(item.filename)
            : Bundle.main.resourceURL?.appendingPathComponent(item.filename)
        guard let url, let image = NSImage(contentsOf: url) else { return nil }
        imageCache.setObject(image, forKey: id as NSString)
        return image
    }

    func assign(_ emote: Emote) {
        config.slots[selectedSlot] = emote.id
        status = "槽位 \(selectedSlot + 1) 已装配「\(emote.name)」"
    }

    func importImage() {
        onCancelInteraction?()
        isRecordingKey = false
        let panel = NSOpenPanel()
        panel.title = "选择一张表情图片"
        panel.prompt = "导入表情"
        panel.allowedContentTypes = [.png, .jpeg, .gif, .tiff, .heic, .webP]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard let source = NSImage(contentsOf: url), source.size.width > 0, source.size.height > 0 else {
                throw NSError(domain: "EmoteWheel", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法读取这张图片，请尝试 PNG 或 JPEG。"])
            }
            // Normalize to a bounded PNG so imports stay small and portable.
            let side = 256
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            context.cgContext.clear(CGRect(x: 0, y: 0, width: side, height: side))
            context.imageInterpolation = .high
            let scale = min(CGFloat(side) / source.size.width, CGFloat(side) / source.size.height)
            let size = NSSize(width: source.size.width * scale, height: source.size.height * scale)
            source.draw(in: NSRect(x: (CGFloat(side) - size.width) / 2, y: (CGFloat(side) - size.height) / 2,
                                  width: size.width, height: size.height))
            NSGraphicsContext.restoreGraphicsState()
            guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
            let id = "custom-" + UUID().uuidString
            let filename = "imports/\(id).png"
            try FileManager.default.createDirectory(at: supportURL.appendingPathComponent("imports"), withIntermediateDirectories: true)
            try png.write(to: supportURL.appendingPathComponent(filename), options: .atomic)
            let emote = Emote(id: id, name: String(url.deletingPathExtension().lastPathComponent.prefix(30)),
                              subtitle: "我的表情", filename: filename)
            catalog.append(emote)
            config.customEmotes.append(emote)
            assign(emote)
        } catch { errorMessage = error.localizedDescription }
    }

    func resetDefaults() {
        let custom = config.customEmotes
        config = Configuration()
        config.customEmotes = custom
        isRecordingKey = false
        status = "已恢复默认按键与轮盘，导入的图片仍在图库中"
    }

    func startRecording() { onCancelInteraction?(); isRecordingKey.toggle() }
    func preview() { isRecordingKey = false; onPreview?() }
    func requestInputMonitoring() { onRequestInputMonitoring?() }
    func requestAccessibility() { onRequestAccessibility?() }
    func refreshPermissions() { onRefreshPermissions?() }

    private func save() {
        guard saveEnabled else { return }
        do {
            try FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(config).write(to: supportURL.appendingPathComponent("settings.json"), options: .atomic)
        } catch { errorMessage = "设置保存失败：\(error.localizedDescription)" }
    }
}
