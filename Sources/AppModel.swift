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
    @Published private(set) var availableEmoteIDs: Set<String> = []
    @Published private(set) var isDownloading = false
    @Published private(set) var downloadFailures = 0
    @Published private(set) var downloadStatus = ""
    var onPreview: (() -> Void)?
    var onRequestInputMonitoring: (() -> Void)?
    var onRequestAccessibility: (() -> Void)?
    var onRefreshPermissions: (() -> Void)?
    var onCancelInteraction: (() -> Void)?
    private let imageCache = NSCache<NSString, NSImage>()
    let supportURL: URL
    private let saveEnabled: Bool
    private var downloadTask: Task<Void, Never>?
    private let assetSources: [EmoteDownloadSource]

    init(preview: Bool = false, supportDirectory: URL? = nil) {
        saveEnabled = !preview
        imageCache.countLimit = 128
        supportURL = supportDirectory ?? (preview
            ? FileManager.default.temporaryDirectory.appendingPathComponent("EmoteWheel-Preview-" + UUID().uuidString)
            : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("EmoteWheel", isDirectory: true))
        if let url = Bundle.main.url(forResource: "emotes-sources", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let sources = try? JSONDecoder().decode([EmoteDownloadSource].self, from: data) {
            assetSources = sources
        } else { assetSources = [] }
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
        // Keep selected catalog IDs even when their images have not been downloaded yet.
        for index in config.slots.indices where emote(for: config.slots[index]) == nil {
            config.slots[index] = Configuration().slots[index]
        }
        refreshAvailableEmotes()
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
        let candidates = item.id.hasPrefix("custom-")
            ? [supportURL.appendingPathComponent(item.filename)]
            : [supportURL.appendingPathComponent(item.filename),
               Bundle.main.resourceURL?.appendingPathComponent(item.filename)].compactMap { $0 }
        guard let image = candidates.lazy.compactMap({ NSImage(contentsOf: $0) })
            .first(where: { $0.size.width > 0 && $0.size.height > 0 }) else { return nil }
        imageCache.setObject(image, forKey: id as NSString)
        return image
    }

    func assign(_ emote: Emote) {
        guard image(for: emote.id) != nil else { return }
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
            availableEmoteIDs.insert(id)
            config.customEmotes.append(emote)
            assign(emote)
        } catch { errorMessage = error.localizedDescription }
    }

    var downloadAllowed: Bool { saveEnabled && !assetSources.isEmpty }
    var standardEmoteCount: Int { catalog.filter { !$0.id.hasPrefix("custom-") }.count }
    var readyEmoteCount: Int { availableEmoteIDs.filter { !$0.hasPrefix("custom-") }.count }

    private func refreshAvailableEmotes() {
        availableEmoteIDs = Set(catalog.compactMap { item in
            let cached = supportURL.appendingPathComponent(item.filename)
            let bundled = item.id.hasPrefix("custom-") ? nil : Bundle.main.resourceURL?.appendingPathComponent(item.filename)
            return FileManager.default.fileExists(atPath: cached.path) ||
                (bundled.map { FileManager.default.fileExists(atPath: $0.path) } ?? false) ? item.id : nil
        })
    }

    func downloadAllEmotes() {
        guard downloadAllowed, !isDownloading else { return }
        isDownloading = true
        downloadFailures = 0
        downloadStatus = "正在下载表情，已下载的图片会保留"
        let cacheRoot = supportURL.appendingPathComponent("emotes", isDirectory: true)
        let bundleRoot = Bundle.main.resourceURL?.appendingPathComponent("emotes", isDirectory: true)
        let sources = assetSources
        downloadTask = Task { @MainActor [weak self] in
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 30
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            await withTaskGroup(of: EmoteDownloadResult.self) { group in
                var next = 0
                func addNext() {
                    guard next < sources.count, !Task.isCancelled else { return }
                    let source = sources[next]
                    next += 1
                    group.addTask {
                        await EmoteDownloads.download(source, cacheRoot: cacheRoot, bundleRoot: bundleRoot, session: session)
                    }
                }
                for _ in 0..<5 { addNext() }
                for await result in group {
                    guard let self else { group.cancelAll(); return }
                    if result.ready {
                        self.availableEmoteIDs.insert(result.id)
                    } else if !result.cancelled {
                        self.availableEmoteIDs.remove(result.id)
                        self.downloadFailures += 1
                    }
                    if Task.isCancelled { group.cancelAll() } else { addNext() }
                }
            }
            guard let self else { return }
            self.imageCache.removeAllObjects()
            self.isDownloading = false
            self.downloadStatus = Task.isCancelled ? "下载已取消，继续下载会跳过已完成的表情" :
                (self.downloadFailures == 0 ? "全部表情已就绪，可离线使用" : "部分表情下载失败，点击重试即可继续")
            self.downloadTask = nil
        }
    }

    func cancelDownload() {
        downloadStatus = "正在取消下载…"
        downloadTask?.cancel()
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

private struct EmoteDownloadSource: Decodable, Sendable {
    let id: Int
    let url: URL
}

private struct EmoteDownloadResult: Sendable {
    let id: String
    let ready: Bool
    let cancelled: Bool
}

enum EmoteDownloads {
    // CDN image optimization can change bytes, so validate the decoded PNG rather than a historical hash.
    static func savePNG(_ data: Data, to destination: URL) throws {
        guard data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]),
              let bitmap = NSBitmapImageRep(data: data), bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0 else {
            throw NSError(domain: "EmoteWheel", code: 2, userInfo: [NSLocalizedDescriptionKey: "下载内容不是有效的 PNG 图片"])
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
    }

    fileprivate static func download(_ source: EmoteDownloadSource, cacheRoot: URL, bundleRoot: URL?, session: URLSession) async -> EmoteDownloadResult {
        let id = String(source.id)
        let destination = cacheRoot.appendingPathComponent("\(id).png")
        do {
            try Task.checkCancellation()
            for candidate in [destination, bundleRoot?.appendingPathComponent("\(id).png")].compactMap({ $0 }) {
                if let data = try? Data(contentsOf: candidate),
                   data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]),
                   let bitmap = NSBitmapImageRep(data: data), bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0 {
                    return EmoteDownloadResult(id: id, ready: true, cancelled: false)
                }
            }
            var request = URLRequest(url: source.url)
            request.setValue("EmoteWheel-asset-downloader/1.0", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
                throw URLError(.badServerResponse)
            }
            try savePNG(data, to: destination)
            return EmoteDownloadResult(id: id, ready: true, cancelled: false)
        } catch {
            return EmoteDownloadResult(id: id, ready: false, cancelled: Task.isCancelled || (error as? URLError)?.code == .cancelled)
        }
    }
}
