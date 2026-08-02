import Foundation
import GRDB
import SwiftSoup

// GRDB and SwiftSoup are imported ahead of any use of them: at this stage the point
// is to prove they resolve, link, and compile under Swift 6 language mode. Real use
// arrives with the Store (T1) and the body-extraction pipeline (E1/X1).

/// Namespace for CapKit-wide constants.
///
/// CapKit owns the data model, store, capture pipeline, and search. In v0.1 it is
/// consumed by three thin clients: the menu-bar app, the `cap` CLI, and the
/// enrichment agent.
public enum CapKit {
    /// The version reported by every cap surface (`cap --version`, the menu-bar
    /// item, the agent's startup log).
    public static let version = "0.0.1"

    /// Reverse-DNS identifier used for `os_log` subsystems and, later, the app
    /// bundle identifier and launchd label.
    public static let bundleIdentifier = "dev.jxd.cap"
}
