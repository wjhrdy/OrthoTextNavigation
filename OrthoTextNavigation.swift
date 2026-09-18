// BTT-Plugin-Name: Ortho Text Navigation
// BTT-Plugin-Identifier: com.whardy.ortho.textnavigation
// BTT-Plugin-Type: Action
// BTT-Plugin-Icon: arrow.uturn.backward
import Cocoa
import ApplicationServices

class OrthoTextNavigation: NSObject, BTTActionPluginInterface {
    weak var delegate: (any BTTActionPluginDelegate)?
    static func configurationFormItems() -> BTTPluginFormItem? {
        let item = BTTPluginFormItem()
        item.formFieldType = BTTFormTypePopupButton
        item.formFieldID = "operation"
        item.formLabel1 = "Wheel operation"
        item.formOptions = ["Right", "Left", "Cancel"]
        item.defaultValue = "Right"
        return item
    }
    static func actionName(withConfiguration config: [AnyHashable: Any]?) -> String? {
        "Ortho: " + (config?["plugin_var_operation"] as? String ?? "Right")
    }
    func executeAction(withConfiguration config: [AnyHashable: Any]?,
                       completionBlock: ((@Sendable (Any?) -> Void)?)) {
        guard let operation = config?["plugin_var_operation"] as? String,
              ["Right", "Left", "Cancel"].contains(operation) else {
            completionBlock?("Missing Ortho operation configuration; no action taken.")
            return
        }
        DispatchQueue.main.async {
            let result = OrthoNavigationState.shared.perform(operation)
            completionBlock?(result)
        }
    }
}

@MainActor
private final class OrthoNavigationState {
    static let shared = OrthoNavigationState()
    private var element: AXUIElement?
    private var pid: pid_t = 0
    private var original = CFRange(location: 0, length: 0)
    private var expected = CFRange(location: 0, length: 0)
    private var document = ""
    private var anchor = 0
    private var caret = 0
    private var extending = false
    private var pendingDelete = false
    private var inhibitDelete = false
    private var timer: Timer?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var workspaceMonitor: NSObjectProtocol?
    private var lastWarning = Date.distantPast
    private var wordSelectionHalfStep = false
    private var wordSelectionDirection = 0
    private var wordSelectionModifiers: UInt64 = 0

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }
    private func writable(_ element: AXUIElement, _ name: String) -> Bool {
        var result = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, name as CFString, &result) == .success && result.boolValue
    }
    private func focused() -> AXUIElement? {
        guard let value = attribute(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    private func range(_ element: AXUIElement) -> CFRange? {
        guard let raw = attribute(element, kAXSelectedTextRangeAttribute),
              CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let value = raw as! AXValue
        var result = CFRange(location: 0, length: 0)
        guard AXValueGetType(value) == .cfRange, AXValueGetValue(value, .cfRange, &result) else { return nil }
        return result
    }
    private func same(_ a: CFRange, _ b: CFRange) -> Bool {
        a.location == b.location && a.length == b.length
    }
    private func valid(_ r: CFRange, length: Int) -> Bool {
        r.location >= 0 && r.length >= 0 && r.location <= length && r.length <= length - r.location
    }
    private func writeRange(_ r: CFRange, to element: AXUIElement) -> Bool {
        var r = r
        guard let value = AXValueCreate(.cfRange, &r),
              AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success,
              let actual = range(element) else { return false }
        return same(r, actual)
    }
    private func contextMatches() -> Bool {
        guard let element, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let focus = focused(), CFEqual(element, focus),
              let text = attribute(element, kAXValueAttribute) as? String, text == document,
              let current = range(element), same(current, expected) else { return false }
        return true
    }
    private func stopWatching() {
        timer?.invalidate()
        timer = nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let workspaceMonitor { NSWorkspace.shared.notificationCenter.removeObserver(workspaceMonitor) }
        globalMonitor = nil
        localMonitor = nil
        workspaceMonitor = nil
    }
    private func clear(keepInhibition: Bool = false) {
        element = nil
        document = ""
        pendingDelete = false
        extending = false
        wordSelectionHalfStep = false
        wordSelectionDirection = 0
        wordSelectionModifiers = 0
        if !keepInhibition { inhibitDelete = false; stopWatching() }
    }
    private func watch() {
        guard timer == nil else { return }
        let mask: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            DispatchQueue.main.async { self?.interrupted() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            DispatchQueue.main.async { self?.interrupted() }
            return event
        }
        workspaceMonitor = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.interrupted() }
        }
        timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
    private func interrupted() {
        inhibitDelete = CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand)
        clear(keepInhibition: inhibitDelete)
    }
    private func tick() {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        let modifiers = flags.intersection([.maskAlternate, .maskShift, .maskCommand]).rawValue
        if modifiers != wordSelectionModifiers { wordSelectionHalfStep = false }
        let command = flags.contains(.maskCommand)
        if element != nil && !contextMatches() {
            inhibitDelete = command
            clear(keepInhibition: command)
            return
        }
        if !command {
            inhibitDelete = false
            if pendingDelete { commitDeletion(); return }
            if element == nil { clear() }
        }
    }
    private func commitDeletion() {
        pendingDelete = false
        guard contextMatches(), let element, expected.length > 0,
              globalMonitor != nil, localMonitor != nil,
              writable(element, kAXSelectedTextAttribute),
              let selected = attribute(element, kAXSelectedTextAttribute) as? String,
              selected == (document as NSString).substring(with: NSRange(location: expected.location, length: expected.length)) else {
            clear()
            return
        }
        // Write only the verified selection in the original focused element.
        // Never send Backspace, which could delete unrelated text if focus changes.
        let result = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, "" as CFString)
        clear()
        if result != .success { warn("Deletion unavailable in this text field; selection was left in place.") }
    }
    private func begin() -> Bool {
        guard AXIsProcessTrusted(), let focus = focused(),
              let role = attribute(focus, kAXRoleAttribute) as? String,
              [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role),
              (attribute(focus, kAXSubroleAttribute) as? String) != kAXSecureTextFieldSubrole,
              writable(focus, kAXSelectedTextRangeAttribute),
              let text = attribute(focus, kAXValueAttribute) as? String,
              let r = range(focus), valid(r, length: (text as NSString).length) else { return false }
        var process: pid_t = 0
        guard AXUIElementGetPid(focus, &process) == .success,
              process == NSWorkspace.shared.frontmostApplication?.processIdentifier else { return false }
        element = focus
        pid = process
        document = text
        original = r
        expected = r
        anchor = r.location
        caret = r.location + r.length
        extending = false
        watch()
        return true
    }
    private func destination(from position: Int, direction: Int, word: Bool) -> Int {
        let ns = document as NSString
        if !word {
            if direction > 0 {
                guard position < ns.length else { return ns.length }
                return NSMaxRange(ns.rangeOfComposedCharacterSequence(at: position))
            }
            guard position > 0 else { return 0 }
            return ns.rangeOfComposedCharacterSequence(at: position - 1).location
        }
        var target = direction > 0 ? ns.length : 0
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byWords, .substringNotRequired]) {
            _, r, _, stop in
            if direction > 0 {
                if NSMaxRange(r) > position { target = NSMaxRange(r); stop.pointee = true }
            } else if r.location < position {
                target = r.location
            } else {
                stop.pointee = true
            }
        }
        return target
    }
    private func warn(_ message: String) {
        guard Date().timeIntervalSince(lastWarning) > 3 else { return }
        lastWarning = Date()
        NSLog("Ortho Text Navigation: %@", message)
        // Keep warnings in the diagnostic log without an audible alert.
    }
    private func fallback(direction: Int, flags: CGEventFlags) {
        // Preserve basic arrow navigation in unsupported apps, but never emulate Command deletion.
        guard !flags.contains(.maskCommand),
              let app = NSWorkspace.shared.frontmostApplication else {
            warn("Command mode requires an accessible text field.")
            return
        }
        var output: CGEventFlags = []
        if flags.contains(.maskAlternate) { output.insert(.maskAlternate) }
        if flags.contains(.maskShift) { output.insert(.maskShift) }
        let source = CGEventSource(stateID: .privateState)
        let code: CGKeyCode = direction > 0 ? 124 : 123
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else { return }
        down.flags = output
        up.flags = output
        down.postToPid(app.processIdentifier)
        up.postToPid(app.processIdentifier)
        warn("Basic navigation only: cursor restoration is unavailable in this field.")
    }
    func perform(_ operation: String) -> String {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        let command = flags.contains(.maskCommand)
        if !command { inhibitDelete = false }
        if operation == "Cancel" {
            // Disarm before any Accessibility call, even if restoring fails.
            pendingDelete = false
            inhibitDelete = command
            let matching = contextMatches()
            let restored: Bool
            if matching, let element { restored = writeRange(original, to: element) }
            else { restored = false }
            clear(keepInhibition: command)
            if command { watch() }
            return restored ? "Starting cursor/selection restored; deletion cancelled." : "Deletion cancelled; no valid cursor snapshot to restore."
        }
        if element != nil && !contextMatches() { interrupted() }
        if pendingDelete && !command { commitDeletion() }
        let direction = operation == "Right" ? 1 : -1
        let accessible = element != nil || begin()
        let select = command || flags.contains(.maskShift)
        // Half sensitivity for ALL rotation modes, including fallback shortcuts.
        // This replaces the word-selection-only filter rather than stacking with it.
        // Cancellation above remains immediate and bypasses this filter.
        let modifiers = flags.intersection([.maskAlternate, .maskShift, .maskCommand]).rawValue
        if direction != wordSelectionDirection || modifiers != wordSelectionModifiers {
            wordSelectionHalfStep = false
        }
        wordSelectionDirection = direction
        wordSelectionModifiers = modifiers
        if !wordSelectionHalfStep {
            wordSelectionHalfStep = true
            return "Navigation: waiting for the second wheel step."
        }
        wordSelectionHalfStep = false
        if !accessible {
            fallback(direction: direction, flags: flags)
            return "Unsupported text field: basic navigation only, no restoration or deletion."
        }
        guard let element else { return "No text field." }
        if !select && expected.length > 0 && !flags.contains(.maskAlternate) {
            caret = direction > 0 ? expected.location + expected.length : expected.location
            anchor = caret
        } else {
            if select && !extending {
                anchor = direction > 0 ? expected.location : expected.location + expected.length
                caret = direction > 0 ? expected.location + expected.length : expected.location
            } else if !select && expected.length > 0 {
                caret = direction > 0 ? expected.location + expected.length : expected.location
            }
            caret = destination(from: caret, direction: direction, word: flags.contains(.maskAlternate))
            if !select { anchor = caret }
        }
        let next = CFRange(location: min(anchor, caret), length: abs(caret - anchor))
        guard writeRange(next, to: element) else {
            interrupted()
            warn("Selection update failed; deletion disarmed.")
            return "Selection update failed; deletion disarmed."
        }
        expected = next
        extending = select
        if command && !inhibitDelete {
            pendingDelete = globalMonitor != nil && localMonitor != nil && writable(element, kAXSelectedTextAttribute)
            if !pendingDelete { warn("Selection works, but safe deletion is unavailable in this field.") }
        }
        return "Moved cursor/selection; starting position saved."
    }
}
