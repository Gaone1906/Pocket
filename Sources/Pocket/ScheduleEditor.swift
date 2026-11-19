import AppKit
import SwiftUI

struct ScheduleEditorOverlay: View {
    @ObservedObject var store: ScheduleStore
    let close: () -> Void

    @State private var selected: UUID?
    @State private var adding = false
    @State private var newName = ""
    @State private var renaming: UUID?
    @State private var renameText = ""
    @State private var editing: UUID?
    @FocusState private var nameFocus: ScheduleEditorNameField?

    private var routine: ScheduleRoutine? { selected.flatMap(store.routine) ?? store.routines.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 14)
            Rectangle().fill(Board.line).frame(height: 1)
            if let routine {
                ScrollView(.vertical) {
                    ScheduleEditorGrid(store: store, routine: routine, editing: $editing)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 16)
                }
                .frame(maxHeight: .infinity)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onExitCommand(perform: dismiss)
        .onAppear {
            selected = store.filter.flatMap(store.routine)?.id ?? store.routines.first?.id
            note("schedule editor opened routine=\(routine?.name ?? "none") routines=\(store.routines.count)")
        }
        .onChange(of: store.routines.map(\.id)) { _, ids in
            if let id = selected, !ids.contains(id) { selected = ids.first }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Change the schedule")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Board.ink)
                Spacer()
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Board.muted)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Board.column))
                        .overlay(Circle().stroke(Board.line, lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Close (Esc)")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.routines) { item in
                        pill(item)
                    }
                    addPill
                }
                .padding(3)
            }
        }
    }

    @ViewBuilder
    private func pill(_ item: ScheduleRoutine) -> some View {
        let on = item.id == routine?.id
        if renaming == item.id {
            ScheduleEditorPillField(hue: Board.hue(item.hue), text: $renameText, prompt: "Routine name")
                .focused($nameFocus, equals: .rename)
                .onSubmit(commitRename)
                .onExitCommand { renaming = nil }
                .onChange(of: nameFocus) { _, focus in if focus != .rename, renaming != nil { commitRename() } }
        } else {
            HStack(spacing: 2) {
                Button {
                    withAnimation(Board.glide) { selected = item.id }
                    editing = nil
                } label: {
                    HStack(spacing: 7) {
                        Circle().fill(Board.hue(item.hue)).frame(width: 7, height: 7)
                        Text(item.name)
                            .font(.system(size: 12, weight: on ? .semibold : .medium))
                            .foregroundStyle(on ? Board.ink : Board.muted)
                            .lineLimit(1)
                    }
                    .padding(.leading, 12)
                    .padding(.trailing, on ? 4 : 12)
                    .frame(height: 30)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture(count: 2).onEnded { startRename(item) })
                .help("Double-click to rename")
                if on {
                    Menu {
                        Button("Rename") { startRename(item) }
                        Divider()
                        Button("Delete…", role: .destructive) { confirmDelete(item) }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Board.muted)
                            .frame(width: 22, height: 22)
                            .contentShape(Circle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .padding(.trailing, 6)
                    .help("Rename or delete")
                }
            }
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 15).fill(on ? Board.column : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(on ? Board.hue(item.hue).opacity(0.7) : Board.line, lineWidth: on ? 1.5 : 1))
        }
    }

    @ViewBuilder
    private var addPill: some View {
        if adding {
            ScheduleEditorPillField(hue: Board.faint, text: $newName, prompt: "New routine")
                .focused($nameFocus, equals: .add)
                .onSubmit(commitAdd)
                .onExitCommand { cancelAdd() }
                .onChange(of: nameFocus) { _, focus in if focus != .add, adding { commitAdd() } }
        } else {
            Button {
                newName = ""
                adding = true
                DispatchQueue.main.async { nameFocus = .add }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Board.muted)
                    .frame(width: 30, height: 30)
                    .overlay(Capsule().stroke(Board.line, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Add a routine")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Board.faint)
            Text("Add a routine with + to start planning your week")
                .font(.system(size: 12))
                .foregroundStyle(Board.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func dismiss() {
        note("schedule editor closed routine=\(routine?.name ?? "none")")
        close()
    }

    private func startRename(_ item: ScheduleRoutine) {
        renameText = item.name
        renaming = item.id
        DispatchQueue.main.async { nameFocus = .rename }
    }

    private func commitRename() {
        guard let id = renaming else { return }
        renaming = nil
        store.renameRoutine(id, to: renameText)
    }

    private func commitAdd() {
        guard adding else { return }
        adding = false
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let id = store.addRoutine(name)
        withAnimation(Board.glide) { selected = id }
    }

    private func cancelAdd() {
        newName = ""
        adding = false
    }

    private func confirmDelete(_ item: ScheduleRoutine) {
        let checks = store.book.checks.filter { $0.routine == item.id }.count
        let alert = NSAlert()
        alert.messageText = "Delete “\(item.name)”?"
        alert.informativeText = "Its steps and \(checks) check-off\(checks == 1 ? "" : "s") are removed. A copy of the whole schedule is kept aside in Backups first, so it can be brought back."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else {
            note("schedule routine delete cancelled id=\(item.id) name=\(item.name)")
            return
        }
        editing = nil
        store.deleteRoutine(item.id)
        withAnimation(Board.glide) { selected = store.routines.first?.id }
    }
}

private enum ScheduleEditorNameField: Hashable {
    case add
    case rename
}

private struct ScheduleEditorPillField: View {
    let hue: Color
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(hue).frame(width: 7, height: 7)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Board.ink)
                .frame(width: 130)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 15).fill(Board.column))
        .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(Board.accent.opacity(0.7), lineWidth: 1.5))
    }
}

private struct ScheduleEditorGrid: View {
    @ObservedObject var store: ScheduleStore
    let routine: ScheduleRoutine
    @Binding var editing: UUID?

    private let labelWidth: CGFloat = 58
    private let gap: CGFloat = 8

    var body: some View {
        let today = ScheduleDays.weekday(store.today)
        VStack(alignment: .leading, spacing: gap) {
            HStack(spacing: gap) {
                Color.clear.frame(width: labelWidth, height: 1)
                ForEach(ScheduleDays.weekOrder, id: \.self) { weekday in
                    let isToday = weekday == today
                    Text(ScheduleDays.short(weekday).uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.6)
                        .foregroundStyle(isToday ? Board.accentInkStyle : AnyShapeStyle(Board.muted))
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .background(Capsule().fill(isToday ? Board.accent.opacity(0.14) : Color.clear))
                        .help(isToday ? "\(ScheduleDays.name(weekday)) (today)" : ScheduleDays.name(weekday))
                }
            }
            ForEach(ScheduleSlot.allCases) { slot in
                HStack(alignment: .top, spacing: gap) {
                    VStack(spacing: 6) {
                        Image(systemName: slot.symbol)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Board.muted)
                        Text(slot.label.uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(Board.muted)
                    }
                    .frame(width: labelWidth)
                    .padding(.top, 12)
                    ForEach(ScheduleDays.weekOrder, id: \.self) { weekday in
                        ScheduleEditorCell(store: store, routine: routine, weekday: weekday, slot: slot,
                                           isToday: weekday == today, editing: $editing)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ScheduleEditorCell: View {
    @ObservedObject var store: ScheduleStore
    let routine: ScheduleRoutine
    let weekday: Int
    let slot: ScheduleSlot
    let isToday: Bool
    @Binding var editing: UUID?

    @State private var adding = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        let steps = routine.steps(weekday, slot)
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                ScheduleEditorStepRow(store: store, routine: routine, weekday: weekday, slot: slot, step: step,
                                      index: index, count: steps.count, editing: $editing)
            }
            Spacer(minLength: 0)
            addRow
        }
        .padding(10)
        .frame(minHeight: 96, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Board.column))
        .boardEdge(14, color: isToday ? Board.accent.opacity(0.55) : Board.line)
        .animation(Board.glide, value: steps.map(\.id))
    }

    @ViewBuilder
    private var addRow: some View {
        if adding {
            TextField("New step", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Board.ink)
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(Board.theme.panel))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Board.accent.opacity(0.6), lineWidth: 1))
                .focused($focused)
                .onSubmit(commit)
                .onExitCommand(perform: cancel)
                .onChange(of: focused) { _, on in if !on { finish() } }
        } else {
            Button {
                draft = ""
                adding = true
                DispatchQueue.main.async { focused = true }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus").font(.system(size: 9, weight: .bold))
                    Text("Add").font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Board.faint)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Add a step to \(ScheduleDays.name(weekday)) \(slot.label.lowercased())")
        }
    }

    private func commit() {
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return cancel() }
        store.addStep(routine.id, weekday: weekday, slot: slot, title: title)
        draft = ""
        DispatchQueue.main.async { focused = true }
    }

    private func finish() {
        guard adding else { return }
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { store.addStep(routine.id, weekday: weekday, slot: slot, title: title) }
        cancel()
    }

    private func cancel() {
        draft = ""
        adding = false
    }
}

private struct ScheduleEditorStepRow: View {
    @ObservedObject var store: ScheduleStore
    let routine: ScheduleRoutine
    let weekday: Int
    let slot: ScheduleSlot
    let step: ScheduleStep
    let index: Int
    let count: Int
    @Binding var editing: UUID?

    @State private var hovering = false

    private var open: Binding<Bool> {
        Binding(get: { editing == step.id }, set: { shown in
            if shown { editing = step.id } else if editing == step.id { editing = nil }
        })
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(step.title)
                .font(.system(size: 12))
                .foregroundStyle(Board.ink)
                .lineLimit(3)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !step.tip.isEmpty, !hovering {
                Image(systemName: "text.bubble")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Board.faint)
            }
            if hovering {
                Button {
                    editing = nil
                    store.removeStep(routine.id, weekday: weekday, slot: slot, step: step.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Board.muted)
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove step")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 7).fill(hovering || editing == step.id ? Board.line.opacity(0.45) : Color.clear))
        .contentShape(Rectangle())
        .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hovering = inside } }
        .onTapGesture { editing = editing == step.id ? nil : step.id }
        .help(step.tip.isEmpty ? step.title : "\(step.title)\n\n\(step.tip)")
        .popover(isPresented: open, arrowEdge: .trailing) {
            ScheduleStepEditor(store: store, routine: routine.id, weekday: weekday, slot: slot, step: step,
                               index: index, count: count) { editing = nil }
        }
    }
}

private struct ScheduleStepEditor: View {
    @ObservedObject var store: ScheduleStore
    let routine: UUID
    let weekday: Int
    let slot: ScheduleSlot
    let step: ScheduleStep
    let index: Int
    let count: Int
    let done: () -> Void

    @State private var title = ""
    @State private var tip = ""
    @State private var removed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(ScheduleDays.name(weekday).uppercased()) · \(slot.label.uppercased())")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(Board.muted)
            TextField("Step", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Board.ink)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Board.column))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Board.line, lineWidth: 1))
                .onSubmit(finish)
            Text("HOW TO DO IT")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(Board.muted)
                .padding(.top, 4)
            TextEditor(text: $tip)
                .font(.system(size: 12))
                .foregroundStyle(Board.ink)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 120)
                .background(RoundedRectangle(cornerRadius: 8).fill(Board.column))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Board.line, lineWidth: 1))
            HStack(spacing: 6) {
                iconButton("arrow.up", help: "Move up", disabled: index == 0) { move(-1) }
                iconButton("arrow.down", help: "Move down", disabled: index >= count - 1) { move(1) }
                iconButton("trash", help: "Delete step", disabled: false) {
                    removed = true
                    store.removeStep(routine, weekday: weekday, slot: slot, step: step.id)
                    done()
                }
                Spacer()
                Button("Done", action: finish)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.small)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .frame(width: 320)
        .background(Board.theme.panel)
        .environment(\.colorScheme, Board.theme.colorScheme)
        .onAppear {
            title = step.title
            tip = step.tip
        }
        .onDisappear(perform: save)
    }

    private func iconButton(_ symbol: String, help: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(disabled ? Board.faint : Board.muted)
                .frame(width: 28, height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(Board.column))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Board.line, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
    }

    private func move(_ offset: Int) {
        save()
        store.moveStep(routine, weekday: weekday, slot: slot, step: step.id, by: offset)
    }

    private func finish() {
        save()
        done()
    }

    private func save() {
        guard !removed else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        let trimmedTip = tip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTitle != step.title || trimmedTip != step.tip else { return }
        store.updateStep(routine, weekday: weekday, slot: slot, step: step.id, title: trimmedTitle, tip: trimmedTip)
    }
}
