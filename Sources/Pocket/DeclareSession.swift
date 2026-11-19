import SwiftUI

struct DeclareSessionCard: View {
    let project: PomodoroProject?
    @ObservedObject var store: PomodoroBoardStore
    let close: () -> Void

    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var minutesText = "40"
    @State private var withTime = false
    @State private var from = DeclareSessionCard.rounded(Date().addingTimeInterval(-40 * 60))
    @State private var to = DeclareSessionCard.rounded(Date())
    @FocusState private var minutesFocused: Bool

    private static let presets = [25, 40, 60, 90, 120]
    private static let maxMinutes = 720

    private var calendar: Calendar { Calendar.current }
    private var today: Date { calendar.startOfDay(for: Date()) }
    private var yesterday: Date { calendar.date(byAdding: .day, value: -1, to: today) ?? today }
    private var tint: Color { project.map { AureliusBoard.hue($0.hue) } ?? AureliusBoard.accent }
    private var minutes: Int? { Int(minutesText.trimmingCharacters(in: .whitespaces)) }

    private var start: Date { combine(day, from) }
    private var end: Date { combine(day, to) }

    private var problem: String? {
        if withTime {
            guard end > start else { return "The end time must be after the start." }
            if end > Date() { return "That time hasn't happened yet." }
        }
        guard let minutes, minutes > 0 else { return "Enter how many minutes you worked." }
        if minutes > Self.maxMinutes { return "Keep one session under 12 hours; declare the rest separately." }
        if day > today { return "Pick today or an earlier day." }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Declare a session")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AureliusBoard.ink)
                HStack(spacing: 6) {
                    Circle().fill(tint).frame(width: 7, height: 7)
                    Text(project.map { $0.name.isEmpty ? "Untitled" : $0.name } ?? "Unassigned")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AureliusBoard.muted)
                }
            }

            section("DAY") {
                HStack(spacing: 6) {
                    chip("Today", on: day == today) { day = today }
                    chip("Yesterday", on: day == yesterday) { day = yesterday }
                    Spacer(minLength: 8)
                    DatePicker("", selection: dayBinding, in: ...Date(), displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.field)
                        .fixedSize()
                }
            }

            section("MINUTES") {
                HStack(spacing: 6) {
                    TextField("40", text: $minutesText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                        .foregroundStyle(AureliusBoard.ink)
                        .multilineTextAlignment(.center)
                        .frame(width: 52, height: 28)
                        .background(RoundedRectangle(cornerRadius: 8).fill(AureliusBoard.theme.pill))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(minutesFocused ? tint.opacity(0.7) : AureliusBoard.line, lineWidth: 1))
                        .focused($minutesFocused)
                        .disabled(withTime)
                        .opacity(withTime ? 0.6 : 1)
                    ForEach(Self.presets, id: \.self) { preset in
                        chip("\(preset)", on: minutes == preset) {
                            minutesText = "\(preset)"
                            if withTime { from = to.addingTimeInterval(-Double(preset) * 60) }
                        }
                    }
                }
            }

            section("TIME", optional: true) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: $withTime.animation(.smooth(duration: 0.15))) {
                        Text("I know when I worked")
                            .font(.system(size: 12))
                            .foregroundStyle(AureliusBoard.ink)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(tint)
                    if withTime {
                        HStack(spacing: 8) {
                            DatePicker("", selection: $from, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .datePickerStyle(.field)
                                .fixedSize()
                            Text("to").font(.system(size: 12)).foregroundStyle(AureliusBoard.muted)
                            DatePicker("", selection: $to, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .datePickerStyle(.field)
                                .fixedSize()
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }

            HStack(spacing: 10) {
                Text(problem ?? summary)
                    .font(.system(size: 11))
                    .foregroundStyle(problem == nil ? AureliusBoard.muted : Color.red.opacity(0.8))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Cancel", action: close)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AureliusBoard.muted)
                    .keyboardShortcut(.cancelAction)
                Button(action: commit) {
                    Text("Declare")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AureliusBoard.theme.isDark ? Color.black.opacity(0.85) : Color.white)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(Capsule().fill(AureliusBoard.accentStyle))
                        .opacity(problem == nil ? 1 : 0.45)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .disabled(problem != nil)
            }
        }
        .padding(22)
        .frame(width: 400)
        .background(RoundedRectangle(cornerRadius: 18).fill(AureliusBoard.column))
        .boardEdge(18)
        .shadow(color: AureliusBoard.shadow, radius: 24, y: 10)
        .onChange(of: from) { _, _ in syncMinutes() }
        .onChange(of: to) { _, _ in syncMinutes() }
        .onChange(of: withTime) { _, now in if now { alignTimes() } }
    }

    private var dayBinding: Binding<Date> {
        Binding(get: { day }, set: { day = calendar.startOfDay(for: $0) })
    }

    private var summary: String {
        let units = Board.unitsLabel((Double(minutes ?? 0) / Double(TallyStick.fullMinutes) * 10).rounded() / 10)
        return "Counts as \(units) session\(units == "1" ? "" : "s")"
    }

    private func section<Content: View>(_ title: String, optional: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(AureliusBoard.faint)
                if optional {
                    Text("optional").font(.system(size: 10)).foregroundStyle(AureliusBoard.faint)
                }
            }
            content()
        }
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: on ? .semibold : .medium).monospacedDigit())
                .foregroundStyle(on ? AureliusBoard.ink : AureliusBoard.muted)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Capsule().fill(on ? tint.opacity(0.22) : AureliusBoard.theme.pill))
                .overlay(Capsule().strokeBorder(on ? tint.opacity(0.7) : AureliusBoard.line, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func alignTimes() {
        let length = Double(minutes ?? 40) * 60
        let latest = day == today ? Self.rounded(Date()) : combine(day, to)
        to = latest
        from = latest.addingTimeInterval(-length)
        syncMinutes()
    }

    private func syncMinutes() {
        guard withTime else { return }
        let span = Int(end.timeIntervalSince(start) / 60)
        if span > 0 { minutesText = "\(span)" }
    }

    private func combine(_ day: Date, _ time: Date) -> Date {
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: day) ?? day
    }

    private func commit() {
        guard problem == nil, let minutes else {
            note("pomodoro declare rejected reason=\(problem ?? "minutes") day=\(day.ISO8601Format()) minutes=\(minutesText)")
            return
        }
        let ended: Date
        if withTime {
            ended = end
        } else if day == today {
            ended = Date()
        } else {
            ended = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day) ?? day
        }
        store.declare(minutes: minutes, ended: ended, started: withTime ? start : nil, project: project?.id)
        close()
    }

    private static func rounded(_ date: Date) -> Date {
        let step = 5.0 * 60
        return Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / step).rounded(.down) * step)
    }
}
