import ApplicationServices
import CapdKit

/// Reports whether keyboard focus, anywhere on screen, sits in a secure text field —
/// browsers mark password inputs `AXSecureTextField` without raising the system
/// secure-input flag.
///
/// Best-effort, not a guarantee: only a positive subrole match refuses. No focused
/// element, a missing Accessibility grant, or any other failure allows the capture.
struct AXReader: SecureInputProbe {
    func isSecureInputActive() -> Bool {
        focusedSubrole() == kAXSecureTextFieldSubrole
    }

    private func focusedSubrole() -> String? {
        var focused: CFTypeRef?
        let systemWide = AXUIElementCreateSystemWide()
        guard
            AXUIElementCopyAttributeValue(
                systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
            let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }

        var subrole: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                focused as! AXUIElement, kAXSubroleAttribute as CFString, &subrole) == .success
        else { return nil }
        return subrole as? String
    }
}
