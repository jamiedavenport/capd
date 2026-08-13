import Foundation
import Testing

@testable import CapdApp
@testable import CapdKit

@MainActor
@Suite("Reminder scheduler")
struct ReminderSchedulerTests {
    @Test("An overdue reminder is presented and claimed once")
    func presentsOverdueReminder() async {
        let capture = Capture(
            id: 1,
            kind: .link,
            url: "https://example.com",
            title: "Example",
            createdAt: Date())
        var due: Capture? = capture
        var presented: [Int64] = []
        let scheduler = ReminderScheduler(
            environment: ReminderScheduler.Environment(
                claimNextDue: { _ in
                    defer { due = nil }
                    return due
                },
                nextDate: { nil },
                present: { presented.append($0.id!) },
                sleep: { _ in }))

        scheduler.start()
        await scheduler.settle()

        #expect(presented == [1])
        #expect(due == nil)
    }
}
