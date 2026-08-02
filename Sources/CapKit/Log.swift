import os

/// Shared `os_log` handles, one per category, so the app, agent, and CLI all log under
/// the same subsystem and `log stream --predicate 'subsystem == "dev.jxd.cap"'` sees
/// every process.
public enum Log {
    public static let capture = Logger(subsystem: CapKit.bundleIdentifier, category: "capture")
    public static let pipeline = Logger(subsystem: CapKit.bundleIdentifier, category: "pipeline")
    public static let store = Logger(subsystem: CapKit.bundleIdentifier, category: "store")
}
