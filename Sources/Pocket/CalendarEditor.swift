import SwiftUI

struct CalendarEditorCard: View {
    @ObservedObject var store: CalendarStore
    let isNew: Bool
    let close: () -> Void

    @State private var event: CalendarEvent
    @State private var lastDay: Date
    @State private var limited: Bool
    @State private var armedDelete = false
    @FocusState private var titleFocused: Bool

    init(store: CalendarStore, draft: CalendarDraft, close: @escaping () -> Void) {
        self.store = store
        self.isNew = draft.isNew
        self.close = close
        let event = draft.event
        _event = State(initialValue: event)
        let last = event.allDay ? CalendarDays.day(event.end.addingTimeInterval(-1)) : CalendarDays.day(event.end)
        _lastDay = State(initialValue: max(CalendarDays.day(event.start), last))
        _limited = State(initialValue: event.until != nil)
    }

    private var tint: Color { Board.hue(event.hue) }

    private var problem: String? {
        if event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Give the event a name." }
        if event.allDay {
            if lastDay < CalendarDays.day(event.start) { return "The last day can't be before the first." }
        } else if event.end < event.start {
            return "The end must be after the start."
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Circle().fill(tint).frame(width: 12, height: 12)
                TextField("New event", text: $event.title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Board.ink)
                    .focused($titleFocused)
                    .onSubmit(save)
            }
            CalendarHairline()
            VStack(alignment: .leading, spacing: 12) {
                row("All day") {
                    Toggle("", isOn: allDayBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .tint(tint)
                }
                if event.allDay {
                    row("Starts") {
                        DatePicker("", selection: dayBinding, displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.field)
                            .fixedSize()
                    }
                    row("Ends") {
                        DatePicker("", selection: $lastDay, in: CalendarDays.day(event.start)..., displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.field)
                            .fixedSize()
                    }
                } else {
                    row("Starts") {
                        DatePicker("", selection: startBinding, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .datePickerStyle(.field)
                            .fixedSize()
                    }
                    row("Ends") {
                        HStack(spacing: 8) {
                            DatePicker("", selection: $event.end, in: event.start..., displayedComponents: [.date, .hourAndMinute])
                                .labelsHidden()
                                .datePickerStyle(.field)
                                .fixedSize()
                            ForEach([30, 60, 90], id: \.self) { minutes in
                                chip(minutes == 90 ? "1½ h" : minutes == 60 ? "1 h" : "30 m", on: Int(event.length / 60) == minutes) {
                                    event.end = event.start.addingTimeInterval(Double(minutes) * 60)
                                }
                            }
                        }
                    }
                }
                row("Repeat") {
                    menu(event.repeats.label) {
                        ForEach(CalendarRepeat.allCases) { option in
                            Button(option.label) { event.repeats = option }
                        }
                    }
                }
                if event.repeats != .never {
                    row("Until") {
                        HStack(spacing: 8) {
                            Toggle("", isOn: limitedBinding)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .tint(tint)
                            if limited {
                                DatePicker("", selection: untilBinding, in: CalendarDays.day(event.start)..., displayedComponents: .date)
                                    .labelsHidden()
                                    .datePickerStyle(.field)
                                    .fixedSize()
                            } else {
                                Text("Forever")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Board.muted)
                            }
                        }
                    }
                }
                row("Alert") {
                    menu(CalendarAlertChoice.label(event.alert, allDay: event.allDay)) {
                        ForEach(event.allDay ? CalendarAlertChoice.allDay : CalendarAlertChoice.timed, id: \.self) { minutes in
                            Button(CalendarAlertChoice.label(minutes, allDay: event.allDay)) { event.alert = minutes }
                        }
                    }
                }
                row("Colour") {
                    HStack(spacing: 7) {
                        ForEach(0..<Board.hueCount, id: \.self) { index in
                            Button {
                                event.hue = index
                            } label: {
                                Circle()
                                    .fill(Board.hue(index))
                                    .frame(width: 18, height: 18)
                                    .overlay(Circle().stroke(Board.ink.opacity(event.hue == index ? 0.75 : 0), lineWidth: 1.5).padding(-3))
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.leading, 3)
                }
            }
            CalendarHairline()
            VStack(spacing: 8) {
                field("Location", text: $event.location, symbol: "mappin.and.ellipse")
                field("Notes", text: $event.notes, symbol: "text.alignleft", lines: 4)
            }
            HStack(spacing: 10) {
                if !isNew {
                    Button {
                        if armedDelete { remove() } else { withAnimation(.smooth(duration: 0.15)) { armedDelete = true } }
                    } label: {
                        Label(armedDelete ? "Delete for good?" : "Delete", systemImage: "trash")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.red.opacity(armedDelete ? 0.9 : 0.65))
                    }
                    .buttonStyle(.plain)
                    .help(event.repeats == .never ? "Delete this event" : "Delete every repeat of this event")
                }
                if let problem, !isNew || !event.title.isEmpty {
                    Text(problem)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.red.opacity(0.8))
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Button("Cancel", action: close)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Board.muted)
                    .keyboardShortcut(.cancelAction)
                Button(action: save) {
                    Text(isNew ? "Add event" : "Save")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Board.theme.isDark ? Color.black.opacity(0.85) : Color.white)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(Capsule().fill(Board.accentStyle))
                        .opacity(problem == nil ? 1 : 0.45)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .disabled(problem != nil)
            }
        }
        .padding(22)
        .frame(width: 470)
        .background(RoundedRectangle(cornerRadius: 18).fill(Board.theme.panel))
        .boardEdge(18)
        .shadow(color: Board.shadow, radius: 30, y: 12)
        .onAppear { if isNew { titleFocused = true } }
    }

    private var allDayBinding: Binding<Bool> {
        Binding(get: { event.allDay }, set: { on in
            withAnimation(.smooth(duration: 0.15)) {
                event.allDay = on
                let calendar = CalendarDays.calendar
                if on {
                    lastDay = max(CalendarDays.day(event.start), CalendarDays.day(event.end))
                    if let alert = event.alert, !CalendarAlertChoice.allDay.contains(alert) { event.alert = 0 }
                } else {
                    let day = CalendarDays.day(event.start)
                    event.start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
                    event.end = event.start.addingTimeInterval(3600)
                    if event.alert != nil { event.alert = CalendarDraft.defaultAlert ?? 10 }
                }
            }
        })
    }

    private var dayBinding: Binding<Date> {
        Binding(get: { event.start }, set: { value in
            let span = CalendarDays.calendar.dateComponents([.day], from: CalendarDays.day(event.start), to: lastDay).day ?? 0
            event.start = CalendarDays.day(value)
            lastDay = CalendarDays.shift(event.start, days: max(0, span))
        })
    }

    private var startBinding: Binding<Date> {
        Binding(get: { event.start }, set: { value in
            let length = event.length
            event.start = value
            event.end = value.addingTimeInterval(length)
        })
    }

    private var limitedBinding: Binding<Bool> {
        Binding(get: { limited }, set: { on in
            limited = on
            event.until = on ? (event.until ?? CalendarDays.calendar.date(byAdding: .month, value: 1, to: CalendarDays.day(event.start))) : nil
        })
    }

    private var untilBinding: Binding<Date> {
        Binding(get: { event.until ?? event.start }, set: { event.until = CalendarDays.day($0) })
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Board.muted)
                .frame(width: 58, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .frame(minHeight: 24)
    }

    private func menu<Items: View>(_ title: String, @ViewBuilder items: () -> Items) -> some View {
        Menu {
            items()
        } label: {
            HStack(spacing: 6) {
                Text(title).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(Board.muted)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Board.ink)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(Board.theme.pill))
            .overlay(Capsule().strokeBorder(Board.line, lineWidth: 1))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: on ? .semibold : .medium))
                .foregroundStyle(on ? Board.ink : Board.muted)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(Capsule().fill(on ? tint.opacity(0.22) : Board.theme.pill))
                .overlay(Capsule().strokeBorder(on ? tint.opacity(0.7) : Board.line, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func field(_ prompt: String, text: Binding<String>, symbol: String, lines: Int = 1) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(Board.faint)
                .frame(width: 14)
                .padding(.top, 2)
            TextField(prompt, text: text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Board.ink)
                .lineLimit(1...lines)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Board.theme.pill))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Board.line, lineWidth: 1))
    }

    private func save() {
        guard problem == nil else {
            note("calendar editor rejected reason=\(problem ?? "") new=\(isNew)")
            return
        }
        var saved = event
        saved.title = saved.title.trimmingCharacters(in: .whitespacesAndNewlines)
        saved.location = saved.location.trimmingCharacters(in: .whitespacesAndNewlines)
        if saved.allDay {
            saved.start = CalendarDays.day(saved.start)
            saved.end = CalendarDays.shift(CalendarDays.day(lastDay), days: 1)
        }
        if !limited || saved.repeats == .never { saved.until = nil }
        if isNew { store.add(saved) } else { store.update(saved) }
        close()
    }

    private func remove() {
        store.delete(event.id)
        close()
    }
}
