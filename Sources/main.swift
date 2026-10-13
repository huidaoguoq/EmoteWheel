import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var model: AppModel!
    var overlay: OverlayController!
    var keyboard: KeyboardController!
    var settingsWindow: NSWindow!
    var statusItem: NSStatusItem!
    let preview = CommandLine.arguments.contains("--preview") || CommandLine.arguments.contains("--capture")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        model = AppModel(preview: preview)
        overlay = OverlayController(model: model)
        keyboard = KeyboardController(model: model, overlay: overlay)
        model.onPreview = { [weak self] in self?.keyboard.cancel(); self?.overlay.show(preview: true) }
        model.onRequestInputMonitoring = { [weak self] in self?.keyboard.requestInputMonitoring() }
        model.onRequestAccessibility = { [weak self] in self?.keyboard.requestAccessibility() }
        model.onRefreshPermissions = { [weak self] in self?.keyboard.refreshPermission() }
        model.onCancelInteraction = { [weak self] in self?.keyboard.cancel() }
        buildMenu()
        let root = SettingsView(model: model).preferredColorScheme(.dark)
        settingsWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 790),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        settingsWindow.title = "Emote Wheel · 桌面表情轮盘"
        settingsWindow.titlebarAppearsTransparent = true
        settingsWindow.backgroundColor = NSColor(srgbRed: 0.035, green: 0.065, blue: 0.09, alpha: 1)
        settingsWindow.minSize = NSSize(width: 1040, height: 760)
        settingsWindow.contentView = NSHostingView(rootView: root)
        settingsWindow.isReleasedWhenClosed = false
        settingsWindow.delegate = self
        settingsWindow.center()
        showSettings()
        keyboard.start(global: !preview)
        if CommandLine.arguments.contains("--capture") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.capture() }
        }
    }

    func buildMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem(); mainMenu.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        let quit = NSMenuItem(title: "退出 Emote Wheel", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.addItem(quit)
        NSApp.mainMenu = mainMenu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "face.smiling", accessibilityDescription: "表情轮盘")
        let menu = NSMenu()
        let settings = NSMenuItem(title: "打开表情轮盘设置…", action: #selector(showSettings), keyEquivalent: "")
        settings.target = self; menu.addItem(settings)
        let pause = NSMenuItem(title: "暂停 / 启用快捷键", action: #selector(toggleEnabled), keyEquivalent: "")
        pause.target = self; menu.addItem(pause)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 Emote Wheel", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc func showSettings() {
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func toggleEnabled() {
        model.config.enabled.toggle()
        model.status = model.config.enabled ? "快捷键已启用" : "快捷键已暂停"
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSettings(); return true }
    func windowWillClose(_ notification: Notification) { keyboard.cancel(); model.isRecordingKey = false }

    // Developer-only visual capture; preview never modifies user settings or asks for permissions.
    private func capture() {
        guard let index = CommandLine.arguments.firstIndex(of: "--capture"), CommandLine.arguments.count > index + 1 else { return }
        let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1])
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let view = settingsWindow.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("settings.png"))
            }
            let view = WheelView(model: model, frame: NSRect(x: 0, y: 0, width: 420, height: 420))
            view.selected = 1
            let panel = OverlayPanel(size: 420); panel.contentView = view
            if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("wheel.png"))
            }
            if let image = model.image(for: model.config.slots[0]),
               let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 480, pixelsHigh: 480,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
               let context = NSGraphicsContext(bitmapImageRep: bitmap) {
                let effect = EmoteEffectView(image: image, frame: NSRect(x: 0, y: 0, width: 240, height: 240))
                context.cgContext.clear(CGRect(x: 0, y: 0, width: 480, height: 480))
                context.cgContext.scaleBy(x: 2, y: 2)
                effect.layer?.render(in: context.cgContext)
                try bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("effect.png"))
            }
            print("Captured native views at \(directory.path)")
        } catch { fputs("Capture failed: \(error)\n", stderr) }
        NSApp.terminate(nil)
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.setActivationPolicy(.regular)
application.delegate = delegate
application.run()
