import Carbon.HIToolbox

/// Answers whether typing is currently shielded from observation, meaning a capture
/// could read a password.
public protocol SecureInputProbe: Sendable {
    func isSecureInputActive() -> Bool
}

/// The system-wide flag any process raises while it has secure keyboard entry enabled.
public struct SystemSecureInputProbe: SecureInputProbe {
    public init() {}

    public func isSecureInputActive() -> Bool {
        IsSecureEventInputEnabled()
    }
}

/// Refuses a capture while secure input is active.
///
/// Probes run in order and the first hit wins, so the cheap process-local flag belongs
/// before probes that reach into other processes.
public struct SecureInputGuard: CaptureGuard {
    let probes: [any SecureInputProbe]

    public init(probes: [any SecureInputProbe] = [SystemSecureInputProbe()]) {
        self.probes = probes
    }

    public func check(_ request: CaptureRequest) throws {
        for probe in probes where probe.isSecureInputActive() {
            throw CaptureError.secureInputActive
        }
    }
}
