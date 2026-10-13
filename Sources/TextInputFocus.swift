import AppKit
import ApplicationServices

enum TextInputFocus {
    enum Kind { case text, nonText, unknown }

    // Inspect control metadata only. Never read the text the user is typing.
    static func classify(role: String, subrole: String, attributes: [String],
                         selectedTextRangeSettable: Bool = false, valueSettable: Bool = false) -> Kind {
        if ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"].contains(role) ||
            ["AXSecureTextField", "AXSearchField"].contains(subrole) ||
            attributes.contains(where: { ["AXEditableAncestor", "AXHighestEditableAncestor"].contains($0) }) ||
            selectedTextRangeSettable {
            return .text
        }
        if ["AXButton", "AXCheckBox", "AXRadioButton", "AXSwitch", "AXSlider", "AXMenuItem",
            "AXMenu", "AXMenuBar", "AXTabGroup", "AXTable", "AXOutline", "AXList",
            "AXToolbar"].contains(role) {
            return .nonText
        }
        if valueSettable { return .text }
        // Chromium exposes selection markers even on buttons and ordinary pages.
        // A readable selection is not evidence of a text editor.
        if ["AXWebArea", "AXStaticText", "AXLink", "AXHeading", "AXGroup", "AXScrollArea",
            "AXSplitGroup", "AXLayoutArea", "AXImage", "AXRow", "AXCell", "AXColumn"].contains(role) {
            return .nonText
        }
        return .unknown
    }

    // Read lazily so a focused editor is rejected without querying its ancestors.
    static func shouldSuppressFocus(_ next: () -> (role: String, kind: Kind)?) -> Bool {
        var recognizedNonText = false
        for _ in 0..<32 {
            guard let node = next() else { return true }
            if node.kind == .text { return true }
            if node.role == "AXWebArea", node.kind == .nonText { return false }
            if node.role == "AXWindow" || node.role == "AXApplication" { return !recognizedNonText }
            if node.kind == .nonText { recognizedNonText = true }
        }
        return true
    }

    static func isLocalTextInput(_ responder: NSResponder?) -> Bool {
        if let text = responder as? NSTextView { return text.isEditable }
        if let field = responder as? NSTextField { return field.isEditable }
        if let client = responder as? NSTextInputClient {
            return client.hasMarkedText() || client.selectedRange().location != NSNotFound
        }
        return false
    }

    static func shouldSuppressShortcut() -> Bool {
        if NSApp.isActive {
            return NSApp.modalWindow != nil || isLocalTextInput(NSApp.keyWindow?.firstResponder)
        }
        guard AXIsProcessTrusted(), let application = NSWorkspace.shared.frontmostApplication else { return true }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.12
        let app = AXUIElementCreateApplication(application.processIdentifier)
        var current = elementAttribute(app, kAXFocusedUIElementAttribute as String, until: deadline)
        return shouldSuppressFocus {
            guard let element = current else { return nil }
            guard let role = attribute(element, kAXRoleAttribute as String, until: deadline) as? String,
                  ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            if role == "AXWindow" || role == "AXApplication" { return (role, .unknown) }
            var names: CFArray?
            guard prepare(element, until: deadline), AXUIElementCopyAttributeNames(element, &names) == .success,
                  let attributes = names as? [String] else { return nil }
            let subrole = attribute(element, kAXSubroleAttribute as String, until: deadline) as? String ?? ""
            guard let selectionSettable = isSettable(element, "AXSelectedTextRange", attributes: attributes, until: deadline),
                  let valueSettable = isSettable(element, kAXValueAttribute as String, attributes: attributes, until: deadline)
            else { return nil }
            let kind = classify(role: role, subrole: subrole, attributes: attributes,
                                selectedTextRangeSettable: selectionSettable, valueSettable: valueSettable)
            if kind != .text && role != "AXWebArea" {
                current = elementAttribute(element, kAXParentAttribute as String, until: deadline)
            }
            return (role, kind)
        }
    }

    private static func isSettable(_ element: AXUIElement, _ name: String,
                                   attributes: [String], until deadline: TimeInterval) -> Bool? {
        guard attributes.contains(name) else { return false }
        guard prepare(element, until: deadline) else { return nil }
        var settable: DarwinBoolean = false
        let result = AXUIElementIsAttributeSettable(element, name as CFString, &settable)
        if result == .attributeUnsupported { return false }
        return result == .success ? settable.boolValue : nil
    }

    private static func prepare(_ element: AXUIElement, until deadline: TimeInterval) -> Bool {
        let remaining = deadline - ProcessInfo.processInfo.systemUptime
        guard remaining > 0 else { return false }
        AXUIElementSetMessagingTimeout(element, Float(min(remaining, 0.03)))
        return true
    }

    private static func attribute(_ element: AXUIElement, _ name: String, until deadline: TimeInterval) -> CFTypeRef? {
        guard prepare(element, until: deadline) else { return nil }
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }

    private static func elementAttribute(_ element: AXUIElement, _ name: String, until deadline: TimeInterval) -> AXUIElement? {
        guard let value = attribute(element, name, until: deadline), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}
