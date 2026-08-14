import Foundation
import Testing

@testable import CapdAppUI

@Suite("Reminder picker quick actions")
struct ReminderPickerViewTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test(
        "Quick actions preserve the selected time",
        arguments: [
            (ReminderQuickAction.tomorrow, 2026, 8, 15),
            (ReminderQuickAction.nextWeek, 2026, 8, 21),
            (ReminderQuickAction.nextMonth, 2026, 9, 14),
        ])
    func quickAction(
        _ action: ReminderQuickAction,
        expectedYear: Int,
        expectedMonth: Int,
        expectedDay: Int
    ) {
        let referenceDate = calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 14, hour: 16, minute: 20)
        )!
        let selectedDate = calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 20, hour: 9, minute: 45)
        )!

        let result = action.date(
            after: referenceDate,
            preservingTimeFrom: selectedDate,
            calendar: calendar
        )

        #expect(
            calendar.dateComponents([.year, .month, .day, .hour, .minute], from: result)
                == DateComponents(
                    year: expectedYear,
                    month: expectedMonth,
                    day: expectedDay,
                    hour: 9,
                    minute: 45
                ))
    }
}
