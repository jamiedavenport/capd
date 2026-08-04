import Foundation
import GRDB

/// Namespace for CapdKit-wide constants.
public enum CapdKit {
    /// The version reported by every Capd surface.
    public static let version = "0.0.5"

    /// Reverse-DNS identifier for `os_log` subsystems and the app bundle.
    public static let bundleIdentifier = "dev.jxd.capd"
}
