import SwiftUI

enum ReminderQuickAction: CaseIterable, Identifiable {
    case tomorrow
    case nextWeek
    case nextMonth

    var id: Self { self }

    var title: String {
        switch self {
        case .tomorrow: "Tomorrow"
        case .nextWeek: "Next Week"
        case .nextMonth: "Next Month"
        }
    }

    func date(
        after referenceDate: Date,
        preservingTimeFrom selectedDate: Date,
        calendar: Calendar = .current
    ) -> Date {
        let offset: (component: Calendar.Component, value: Int) =
            switch self {
            case .tomorrow: (.day, 1)
            case .nextWeek: (.weekOfYear, 1)
            case .nextMonth: (.month, 1)
            }
        guard
            let targetDate = calendar.date(
                byAdding: offset.component,
                value: offset.value,
                to: referenceDate
            )
        else { return selectedDate }
        let time = calendar.dateComponents([.hour, .minute, .second], from: selectedDate)
        return calendar.date(
            bySettingHour: time.hour ?? 0,
            minute: time.minute ?? 0,
            second: time.second ?? 0,
            of: targetDate
        ) ?? targetDate
    }
}

/// A compact, Mac-native reminder editor. Keeping it independent from `SearchModel`
/// makes every visual state available in the preview canvas.
struct ReminderPickerView: View {
    let captureTitle: String
    @Binding var date: Date
    let minimumDate: Date
    let error: String?
    let cancel: () -> Void
    let schedule: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            hairline
            editor
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bell")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text("Remind me")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(captureTitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 16)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var editor: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)

            VStack(spacing: 18) {
                VStack(spacing: 5) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(Theme.accent)

                    Text("Choose a reminder time")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.text)

                    Text(
                        date.formatted(.dateTime.weekday(.wide).month(.wide).day().hour().minute())
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                }

                pickerFields
                quickActions

                if let error {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.warning)
                }
            }
            .frame(width: 390)

            Spacer(minLength: 20)

            HStack(spacing: 10) {
                Spacer()
                Button("Cancel", action: cancel)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                Button("Set Reminder", action: schedule)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pickerFields: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                fieldLabel("Date", systemImage: "calendar")
                Spacer()
                DatePicker(
                    "Date",
                    selection: $date,
                    in: minimumDate...,
                    displayedComponents: .date
                )
                .datePickerStyle(.field)
                .labelsHidden()
                .fixedSize()
            }
            .padding(.horizontal, 14)
            .frame(height: 45)

            hairline
                .padding(.leading, 40)

            HStack(spacing: 10) {
                fieldLabel("Time", systemImage: "clock")
                Spacer()
                DatePicker(
                    "Time",
                    selection: $date,
                    in: minimumDate...,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.field)
                .labelsHidden()
                .fixedSize()
            }
            .padding(.horizontal, 14)
            .frame(height: 45)
        }
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1))
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick select")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)

            HStack(spacing: 8) {
                ForEach(ReminderQuickAction.allCases) { action in
                    Button {
                        date = action.date(
                            after: minimumDate,
                            preservingTimeFrom: date
                        )
                    } label: {
                        Text(action.title)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fieldLabel(_ title: String, systemImage: String) -> some View {
        Label {
            Text(title)
                .font(.system(size: 12, weight: .medium))
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 16)
        }
        .foregroundStyle(Theme.text)
    }

    private var hairline: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: 1)
    }
}

private struct ReminderPickerPreview: View {
    @State private var date = Calendar.current.date(
        from: DateComponents(year: 2026, month: 8, day: 14, hour: 9))!
    var error: String?

    var body: some View {
        ReminderPickerView(
            captureTitle: "How to design interfaces that feel inevitable",
            date: $date,
            minimumDate: Calendar.current.date(
                from: DateComponents(year: 2026, month: 8, day: 13))!,
            error: error,
            cancel: {},
            schedule: {}
        )
        .frame(width: 640, height: 470)
        .background(Theme.background, in: PanelStyle.shape)
        .overlay(PanelStyle.shape.strokeBorder(Theme.border, lineWidth: 1))
        .preferredColorScheme(.dark)
    }
}

#Preview("Reminder") {
    ReminderPickerPreview()
}

#Preview("Reminder error") {
    ReminderPickerPreview(error: "Choose a time in the future.")
}
