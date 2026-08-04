import CapdAppUI
import Foundation

struct AmbientContextEnvironment {
    var isSecureInputActive: @MainActor () -> Bool
    var frontmostTarget: @MainActor () -> FrontmostTarget?
    var browserTab: @MainActor (Browser, FrontmostTarget) async -> BrowserTab?
    var isSuppressed: @MainActor (URL) -> Bool
    var insight: @Sendable (ContextObservation) async -> ContextInsight?
    var present: @MainActor (ContextInsight) -> Void
    var now: () -> Date
}

@MainActor
final class AmbientContextMonitor {
    static let pollInterval: Duration = .seconds(1)

    private let environment: AmbientContextEnvironment
    private var policy: ContextReminderPolicy
    private var task: Task<Void, Never>?

    init(
        environment: AmbientContextEnvironment,
        policy: ContextReminderPolicy = ContextReminderPolicy()
    ) {
        self.environment = environment
        self.policy = policy
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.poll()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        policy.suspend()
    }

    func poll() async {
        guard !environment.isSecureInputActive(), let target = environment.frontmostTarget(),
            let bundleID = target.bundleID, let browser = Browser(bundleID: bundleID),
            let tab = await environment.browserTab(browser, target), let url = URL(string: tab.url)
        else {
            policy.suspend()
            return
        }

        let action = policy.observe(
            url, externallySuppressed: environment.isSuppressed(url), now: environment.now())
        guard case .lookUp(let observation) = action,
            let insight = await environment.insight(observation),
            !environment.isSuppressed(observation.url), policy.isCurrent(observation)
        else { return }
        environment.present(insight)
    }
}
