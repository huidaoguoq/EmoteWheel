import Foundation

@main
struct TextInputFocusTests {
    static func main() {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
            checks += 1
        }
        typealias Node = (role: String, kind: TextInputFocus.Kind)
        func node(_ role: String, attributes: [String] = [],
                  selectionEditable: Bool = false, valueEditable: Bool = false) -> Node {
            (role, TextInputFocus.classify(role: role, subrole: "", attributes: attributes,
                  selectedTextRangeSettable: selectionEditable, valueSettable: valueEditable))
        }
        func suppressed(_ path: [Node]) -> Bool {
            var index = 0
            return TextInputFocus.shouldSuppressFocus {
                guard index < path.count else { return nil }
                defer { index += 1 }
                return path[index]
            }
        }
        // All Chromium web nodes expose this attribute, including buttons.
        let webAttributes = ["AXRole", "AXParent", "AXValue", "AXSelectedTextMarkerRange"]
        let page = node("AXWebArea", attributes: webAttributes)
        let window = node("AXWindow")
        check(!suppressed([page]), "ordinary browser page allows Y")
        check(!suppressed([node("AXButton", attributes: webAttributes), page]),
              "browser and Electron buttons are not classified as typing")
        check(!suppressed([node("AXGroup", attributes: webAttributes), page]),
              "ordinary webpage container allows Y")
        check(!suppressed([node("AXStaticText", attributes: webAttributes +
              ["AXSelectedTextRange", "AXNumberOfCharacters", "AXInsertionPointLineNumber"]), page]),
              "selectable read-only text allows Y")
        for role in ["AXGroup", "AXScrollArea", "AXOutline", "AXList", "AXTable", "AXImage"] {
            check(!suppressed([node(role), window]), "native non-editing \(role) allows Y")
        }
        for role in ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"] {
            check(suppressed([node(role, attributes: webAttributes), page]),
                  "\(role) protects Chinese and English typing")
        }
        check(suppressed([node("AXGroup", attributes: webAttributes + ["AXEditableAncestor"]), page]),
              "editable descendant metadata protects custom rich-text controls")
        check(suppressed([node("AXGroup", attributes: ["AXSelectedTextRange"], selectionEditable: true), page]),
              "writable text selection protects a generic editor")
        check(suppressed([node("AXWebArea", attributes: webAttributes, valueEditable: true)]),
              "editable document root is protected before the web boundary")
        check(suppressed([node("AXWebArea", selectionEditable: true)]),
              "document editing protects Y when exposed via writable selection")
        check(suppressed([node("AXStaticText"), node("AXGroup"), node("AXTextArea"), page]),
              "non-editing child inside a rich-text editor is still protected")
        check(suppressed([node("AXButton"), node("AXGroup", valueEditable: true), window]),
              "native editing ancestor takes priority over a button child")
        check(!suppressed([node("AXButton")] + Array(repeating: node("AXGroup"), count: 8) + [page]),
              "normal deeply nested UI is not rejected after six ancestors")
        check(suppressed([node("AXUnknown"), window]), "unrecognized native control remains conservative")
        check(suppressed([]), "failed focus query suppresses Y")
        check(suppressed([node("AXGroup")]), "incomplete ancestor query suppresses Y")
        check(suppressed(Array(repeating: node("AXGroup"), count: 40)), "cyclic or unbounded focus tree is bounded")
        check(node("AXSlider", valueEditable: true).kind == .nonText,
              "adjustable slider values are not text editing")
        print("PASS: \(checks) shared focus regression checks")
    }
}
