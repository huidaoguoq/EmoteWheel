import AppKit
import Combine
import ApplicationServices

final class KeyboardController {
    let model: AppModel
    let overlay: OverlayController
    private var eventTap: CFMachPort?
    private var eventSource: CFRunLoopSource?
    private var localMonitor: Any?
    private var permissionTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var configSubscription: AnyCancellable?
    private var held = false
    private var cancellationGeneration = 0
    private let shouldSuppressShortcut: () -> Bool
    private let modifierMask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    init(model: AppModel, overlay: OverlayController,
         shouldSuppressShortcut: @escaping () -> Bool = TextInputFocus.shouldSuppressShortcut) {
        self.model = model; self.overlay = overlay
        self.shouldSuppressShortcut = shouldSuppressShortcut
    }

    func start(global: Bool = true) {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if self.model.isRecordingKey, event.type == .keyDown {
                self.record(event)
                return nil
            }
            if NSApp.modalWindow != nil { self.cancel(); return event }
            if event.type == .rightMouseDown {
                if self.overlay.active { self.cancel(); return nil }
                return event
            }
            if TextInputFocus.isLocalTextInput(NSApp.keyWindow?.firstResponder) { self.cancel(); return event }
            return self.handle(type: event.type, keyCode: event.keyCode,
                flags: event.modifierFlags, isRepeat: event.type == .keyDown && event.isARepeat) ? nil : event
        }
        configSubscription = model.$config.dropFirst().sink { [weak self] _ in self?.cancel() }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
            object: nil, queue: .main) { [weak self] _ in self?.cancel(); self?.model.isRecordingKey = false })
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.screensDidSleepNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil,
                queue: .main) { [weak self] _ in self?.cancel() })
        }
        guard global else { return }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { [weak self] _ in self?.refreshPermission() })
        refreshPermission()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refreshPermission() }
    }

    func requestInputMonitoring() {
        if !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
        }
        model.status = "已打开输入监控设置；修改权限后按系统提示重新打开应用"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
        refreshPermission()
    }

    func requestAccessibility() {
        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        model.status = "已打开辅助功能设置；开启 EmoteWheel 后，返回应用刷新状态"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        refreshPermission()
    }

    func refreshPermission() {
        let permitted = CGPreflightListenEventAccess()
        let trusted = AXIsProcessTrusted()
        model.inputMonitoringGranted = permitted
        model.accessibilityGranted = trusted
        if !permitted || !trusted {
            if eventTap != nil { stopTap(); cancel() }
            model.permissionGranted = false
            return
        }
        if eventTap == nil { installTap() }
        model.permissionGranted = eventTap != nil
    }

    private func installTap() {
        let eventTypes: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .rightMouseDown]
        let mask = eventTypes.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<KeyboardController>.fromOpaque(info).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                controller.cancel()
                if let tap = controller.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            // Active-app events are handled by the local monitor exactly once.
            if !NSApp.isActive, let converted = NSEvent(cgEvent: event) {
                if type == .rightMouseDown { controller.cancel() }
                else {
                    let eventType = converted.type
                    let code = converted.keyCode
                    let flags = converted.modifierFlags
                    let repeated = eventType == .keyDown && converted.isARepeat
                    let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
                    let generation = controller.cancellationGeneration
                    // AX may require IPC; keep it outside the event-tap callback.
                    DispatchQueue.main.async {
                        guard generation == controller.cancellationGeneration else { return }
                        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == frontPID else {
                            controller.cancel(); return
                        }
                        _ = controller.handle(type: eventType, keyCode: code, flags: flags, isRepeat: repeated,
                            isCurrentPress: {
                                generation == controller.cancellationGeneration &&
                                NSWorkspace.shared.frontmostApplication?.processIdentifier == frontPID &&
                                CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(code))
                            })
                    }
                }
            }
            // Passive listening: original keys are never suppressed or rewritten.
            return Unmanaged.passUnretained(event)
        }
        eventTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap,
            options: .listenOnly, eventsOfInterest: mask, callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        if let tap = eventTap {
            eventSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), eventSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            model.status = "全局快捷键已就绪 · 输入文字时自动暂停轮盘"
        } else { model.status = "两项权限已就绪，但快捷键监听未启动；请退出后重新打开应用" }
    }

    private func stopTap() {
        if let source = eventSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap = eventTap { CFMachPortInvalidate(tap) }
        eventTap = nil; eventSource = nil
    }

    @discardableResult
    func handle(type: NSEvent.EventType, keyCode: UInt16, flags: NSEvent.ModifierFlags, isRepeat: Bool,
                isCurrentPress: () -> Bool = { true }) -> Bool {
        if type == .keyDown, keyCode == 53, overlay.active { cancel(); return true }
        if type == .keyUp, keyCode == model.config.keyCode, held {
            if shouldSuppressShortcut() { cancel(); return false }
            held = false; overlay.commit(); return true
        }
        if type == .flagsChanged, held,
           flags.intersection(modifierMask).rawValue != UInt(model.config.modifiers) {
            cancel(); return true
        }
        guard type == .keyDown, model.config.enabled, !model.isRecordingKey,
              keyCode == model.config.keyCode,
              flags.intersection(modifierMask).rawValue == UInt(model.config.modifiers) else { return false }
        if isRepeat { return held }
        if !held {
            guard !shouldSuppressShortcut(), isCurrentPress() else { return false }
            held = true; overlay.show()
        }
        return true
    }

    func cancel() { cancellationGeneration &+= 1; held = false; overlay.cancel() }

    private func record(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        if event.keyCode == 53 { model.isRecordingKey = false; return }
        let special: [UInt16: String] = [122:"F1",120:"F2",99:"F3",118:"F4",96:"F5",97:"F6",98:"F7",100:"F8",101:"F9",109:"F10",103:"F11",111:"F12"]
        let characters = event.charactersIgnoringModifiers?.uppercased() ?? ""
        let label = special[event.keyCode] ?? characters
        guard special[event.keyCode] != nil || (label.count == 1 && label.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) })) else {
            model.status = "请选择字母、数字或 F1–F12，可搭配 ⌃ ⌥ ⇧ ⌘"; return
        }
        var config = model.config
        config.keyCode = event.keyCode
        config.keyLabel = label
        config.modifiers = UInt64(event.modifierFlags.intersection(modifierMask).rawValue)
        model.config = config
        model.isRecordingKey = false
        model.status = "快捷键已改为 \(model.shortcutLabel)"
    }
}
