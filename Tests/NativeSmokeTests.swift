import AppKit

@main
struct NativeSmokeTests {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let model = AppModel(preview: true)
        let overlay = OverlayController(model: model)
        var textInputFocused = false
        let keyboard = KeyboardController(model: model, overlay: overlay,
            shouldSuppressShortcut: { textInputFocused })
        keyboard.start(global: false)
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
            checks += 1
        }
        func down(_ key: UInt16 = 16, flags: NSEvent.ModifierFlags = [], repeated: Bool = false) {
            keyboard.handle(type: .keyDown, keyCode: key, flags: flags, isRepeat: repeated)
        }
        func up(_ key: UInt16 = 16) {
            keyboard.handle(type: .keyUp, keyCode: key, flags: [], isRepeat: false)
        }
        check(model.catalog.count == 2400, "complete catalog metadata must load without downloading")
        check(Configuration().slots.allSatisfy { model.image(for: $0) != nil }, "all eight starter images must decode")
        check(!model.downloadAllowed, "preview must disable network downloads")
        model.downloadAllEmotes()
        check(!model.isDownloading, "preview cannot start a background download")
        let temporarySupport = FileManager.default.temporaryDirectory.appendingPathComponent("EmoteWheel-AssetTests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporarySupport) }
        do {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 3, pixelsHigh: 2,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let png = bitmap.representation(using: .png, properties: [:])!
            let cachedURL = temporarySupport.appendingPathComponent("emotes/1505.png")
            try EmoteDownloads.savePNG(png, to: cachedURL)
            check(NSImage(contentsOf: cachedURL)?.size == NSSize(width: 3, height: 2), "downloaded PNG is saved as a readable cache image")
            do {
                try EmoteDownloads.savePNG(Data("not an image".utf8), to: cachedURL)
                check(false, "invalid download must be rejected")
            } catch {
                check((try? Data(contentsOf: cachedURL)) == png, "invalid download must preserve a previously cached image")
            }
            var saved = Configuration()
            saved.slots[0] = "997"
            let custom = Emote(id: "custom-cache-test", name: "Custom", subtitle: "", filename: "imports/custom.png")
            saved.customEmotes = [custom]
            try EmoteDownloads.savePNG(png, to: temporarySupport.appendingPathComponent(custom.filename))
            try JSONEncoder().encode(saved).write(to: temporarySupport.appendingPathComponent("settings.json"))
            let cachedModel = AppModel(supportDirectory: temporarySupport)
            check(cachedModel.config.slots[0] == "997", "saved catalog selections survive missing local images")
            let unavailable = Emote(id: "unavailable-fixture", name: "Missing", subtitle: "", filename: "emotes/missing.png")
            cachedModel.catalog.append(unavailable)
            cachedModel.assign(unavailable)
            check(cachedModel.config.slots[0] == "997", "unavailable image cannot replace an equipped emote")
            check(cachedModel.image(for: "1505")?.size == NSSize(width: 3, height: 2), "persistent cache takes precedence over bundled image")
            check(cachedModel.image(for: custom.id) != nil, "custom imports resolve from the support directory")
            check(cachedModel.availableEmoteIDs.contains("1505") && cachedModel.availableEmoteIDs.contains(custom.id), "cached and custom images are available immediately")
            let restored = AppModel(supportDirectory: temporarySupport)
            check(restored.image(for: "1505")?.size == NSSize(width: 3, height: 2), "cached downloads survive app model recreation")
        } catch {
            check(false, "cache fixture failed: \(error)")
        }
        down(); check(overlay.active, "Y down opens wheel")
        let wheel = app.windows.first { $0 is OverlayPanel && $0.isVisible }
        check(wheel?.level == .screenSaver, "wheel stays above normal windows")
        check(wheel?.ignoresMouseEvents == true, "hold wheel passes pointer events through")
        check(wheel?.collectionBehavior.contains(.fullScreenAuxiliary) == true, "wheel supports fullscreen Spaces")
        down(repeated: true); check(overlay.active, "repeat keeps current wheel")
        up(); check(!overlay.active, "Y up closes wheel")
        check(model.lastEmoteName.isEmpty, "release without moving must not send")
        up(); check(model.lastEmoteName.isEmpty, "duplicate release must not send")
        down(); down(53); check(!overlay.active, "Esc cancels")
        up(); check(model.lastEmoteName.isEmpty, "release after Esc must not send")
        down(0); check(!overlay.active, "wrong key is ignored")
        model.config.enabled = false
        down(); check(!overlay.active, "paused wheel must not open")
        model.config.enabled = true
        down(); model.config.enabled = false
        check(!overlay.active, "disabling during hold cancels")
        model.config.enabled = true
        model.config.keyCode = 0; model.config.keyLabel = "A"
        down(); check(!overlay.active, "old key must stop working")
        down(0); check(overlay.active, "new key works")
        up(0); check(!overlay.active, "new key release closes")
        model.config.modifiers = UInt64(NSEvent.ModifierFlags.option.rawValue)
        down(0); check(!overlay.active, "required modifier is enforced")
        down(0, flags: .option); check(overlay.active, "modified shortcut opens")
        keyboard.handle(type: .flagsChanged, keyCode: 58, flags: [], isRepeat: false)
        check(!overlay.active, "releasing modifier first cancels")
        up(0); check(model.lastEmoteName.isEmpty, "release after modifier cancel must not send")
        overlay.show(preview: true); check(overlay.active && overlay.isPreview, "preview opens without permissions")
        keyboard.cancel(); check(!overlay.active, "preview cancels")
        model.config = Configuration()
        textInputFocused = true
        let consumed = keyboard.handle(type: .keyDown, keyCode: 16, flags: [], isRepeat: false)
        check(!overlay.active && !consumed, "typing y must pass through without opening")
        down(repeated: true); check(!overlay.active, "holding y in an editor must not open")
        textInputFocused = false
        down(repeated: true); check(!overlay.active, "focus change mid-typing must not open from repeat")
        up(); check(model.lastEmoteName.isEmpty, "typing must never send on key up")
        down(); check(overlay.active, "a new press outside an editor works")
        textInputFocused = true
        up(); check(!overlay.active && model.lastEmoteName.isEmpty, "moving focus to text before release cancels")
        model.config.modifiers = UInt64(NSEvent.ModifierFlags.shift.rawValue)
        down(flags: .shift); check(!overlay.active, "typing uppercase Y must also be protected")
        up()
        for role in ["AXTextField", "AXTextArea", "AXComboBox"] {
            check(TextInputFocus.classify(role: role, subrole: "", attributes: []) == .text,
                  "text roles are protected for every input language")
        }
        check(TextInputFocus.classify(role: "AXGroup", subrole: "", attributes: ["AXSelectedTextRange"],
                                      selectedTextRangeSettable: true) == .text,
              "contenteditable text metadata must be protected")
        check(TextInputFocus.classify(role: "AXUnknown", subrole: "", attributes: []) == .unknown,
              "unexposed custom editor must remain unknown")
        check(TextInputFocus.classify(role: "AXWebArea", subrole: "", attributes: ["AXSelectedTextMarkerRange"]) == .nonText,
              "ordinary web content is not an editor just because it supports selection")
        check(TextInputFocus.classify(role: "AXStaticText", subrole: "", attributes: ["AXNumberOfCharacters"]) == .nonText,
              "read-only labels are not editors; ancestors are checked separately")
        check(TextInputFocus.classify(role: "AXTextField", subrole: "AXSecureTextField", attributes: []) == .text,
              "secure inputs must be protected")
        check(TextInputFocus.classify(role: "AXButton", subrole: "", attributes: []) == .nonText,
              "normal buttons allow shortcut")
        let editor = NSTextView()
        editor.isEditable = true
        editor.string = "y"
        check(TextInputFocus.isLocalTextInput(editor), "English editor focus suppresses shortcut")
        editor.setMarkedText("yin", selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        check(editor.hasMarkedText() && TextInputFocus.isLocalTextInput(editor), "Chinese IME composition suppresses shortcut")
        check(!TextInputFocus.isLocalTextInput(NSView()), "non-text native view allows shortcut")
        model.config = Configuration()
        textInputFocused = false
        keyboard.handle(type: .keyDown, keyCode: 16, flags: [], isRepeat: false, isCurrentPress: { false })
        check(!overlay.active, "released or cancelled key during focus lookup must not open late")
        print("PASS: \(checks) native integration checks (no global permission requested)")
    }
}
