import Foundation
import IOKit.ps

/// How many enrichments may run at once, decided by power source. Shared so the queue
/// drains and the `cap status` ETA divide by the same number.
public enum DrainPolicy {
    public static let mainsPowerWidth = 3
    public static let batteryWidth = 1

    public static func width(onMainsPower: Bool) -> Int {
        onMainsPower ? mainsPowerWidth : batteryWidth
    }
}

public enum PowerStatus {
    /// launchd carries no power context, so the agent asks IOKit directly.
    public static func isOnMainsPower() -> Bool {
        IOPSGetTimeRemainingEstimate() == kIOPSTimeRemainingUnlimited
    }
}
