import Foundation
import GRDB

/// Namespace for CapKit-wide constants.
public enum CapKit {
    /// The version reported by every cap surface.
    public static let version = "0.0.6"

    /// Reverse-DNS identifier for `os_log` subsystems and the app bundle.
    public static let bundleIdentifier = "dev.jxd.cap"
}
