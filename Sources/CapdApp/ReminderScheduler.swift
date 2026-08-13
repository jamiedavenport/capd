import CapdAppUI
import CapdKit
import Foundation

@MainActor
final class ReminderScheduler {
    struct Environment {
        var claimNextDue: @MainActor (Date) throws -> Capture?
        var nextDate: @MainActor () throws -> Date?
        var present: @MainActor (Capture) -> Void
        var now: @MainActor () -> Date = Date.init
        var sleep: @Sendable (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        }
    }

    private let environment: Environment
    private var task: Task<Void, Never>?

    init(environment: Environment) {
        self.environment = environment
    }

    func start() {
        reload()
    }

    func reload() {
        task?.cancel()
        task = Task { [weak self] in
            await self?.run()
        }
    }

    func settle() async {
        await task?.value
    }

    private func run() async {
        while !Task.isCancelled {
            do {
                if let capture = try environment.claimNextDue(environment.now()) {
                    environment.present(capture)
                    try await environment.sleep(.seconds(7))
                    continue
                }
                guard let date = try environment.nextDate() else { return }
                let delay = max(0, date.timeIntervalSince(environment.now()))
                try await environment.sleep(.seconds(delay))
            } catch is CancellationError {
                return
            } catch {
                try? await environment.sleep(.seconds(30))
            }
        }
    }
}
