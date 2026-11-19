import AppKit
import SwiftUI

final class CatCalculator: ObservableObject {
    @Published private(set) var current = "0"
    @Published private(set) var accumulator: Double?
    @Published private(set) var operation: String?
    @Published private(set) var memory: Double = 0
    private var fresh = true

    var expression: String {
        if let accumulator, let operation { return "\(CatCalculator.format(accumulator)) \(operation)" }
        return memory != 0 ? "M" : ""
    }

    private var number: Double { Double(current) ?? 0 }

    static func format(_ value: Double) -> String {
        guard value.isFinite else { return "Error" }
        let rounded = (value * 1e10).rounded() / 1e10
        if rounded == rounded.rounded(), abs(rounded) < 1e15 { return String(Int64(rounded)) }
        return String(rounded)
    }

    private func applyPending() -> Double {
        guard let operation, let accumulator else { return number }
        let operand = number
        switch operation {
        case "+": return accumulator + operand
        case "-": return accumulator - operand
        case "*": return accumulator * operand
        default: return operand == 0 ? .nan : accumulator / operand
        }
    }

    func press(_ key: String) {
        switch key {
        case "0", "1", "2", "3", "4", "5", "6", "7", "8", "9":
            current = fresh || current == "0" ? key : current + key
            fresh = false
        case ".":
            if fresh {
                current = "0."
                fresh = false
            } else if !current.contains(".") {
                current += "."
            }
        case "←":
            if !fresh { current = current.count > 1 ? String(current.dropLast()) : "0" }
        case "CE":
            current = "0"
            fresh = true
        case "C":
            current = "0"
            accumulator = nil
            operation = nil
            fresh = true
        case "±":
            current = CatCalculator.format(-number)
        case "√":
            current = CatCalculator.format(number.squareRoot())
            fresh = true
        case "1/x":
            current = CatCalculator.format(1 / number)
            fresh = true
        case "%":
            current = CatCalculator.format(accumulator.map { $0 * number / 100 } ?? number / 100)
            fresh = true
        case "+", "-", "*", "/":
            if !fresh || accumulator == nil { accumulator = applyPending() }
            operation = key
            current = CatCalculator.format(accumulator ?? 0)
            fresh = true
        case "=":
            current = CatCalculator.format(applyPending())
            accumulator = nil
            operation = nil
            fresh = true
        case "MC":
            memory = 0
        case "MR":
            current = CatCalculator.format(memory)
            fresh = true
        case "MS":
            memory = number
        case "M+":
            memory += number
        case "M-":
            memory -= number
        default:
            break
        }
    }

    func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(current, forType: .string)
    }
}

private enum CatStyle {
    static var navy: Color { Board.theme.isDark ? Board.theme.card : Board.accentInk }
    static var headerInk: Color { Board.theme.isDark ? Board.accentInk : .white }
    static var blue: Color { Board.accent }
    static var blueTint: Color { Board.accent.opacity(0.18) }
    static var ink: Color { Board.ink }
    static var muted: Color { Board.muted }
    static var keyBorder: Color { Board.line }
    static var line: Color { Board.line }
    static var surface: Color { Board.theme.embroidery == nil ? Board.backdrop : Color(hex: 0x111113) }
    static var surface2: Color { Board.theme.embroidery == nil ? Board.column : Color(hex: 0x1B1B1E) }
    static let gap: CGFloat = 5
    static let keyHeight: CGFloat = 31
}

private struct CatKey: View {
    let label: String
    let press: (String) -> Void
    var height: CGFloat = CatStyle.keyHeight
    @State private var hovering = false

    var body: some View {
        let equals = label == "="
        Button { press(label) } label: {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(equals ? Color.white : CatStyle.ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(equals ? CatStyle.blue : hovering ? CatStyle.blueTint : CatStyle.surface2)
                )
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(equals ? CatStyle.blue : CatStyle.keyBorder, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(height: height)
        .onHover { hovering = $0 }
    }
}

struct CalcView: View {
    @ObservedObject var calc: CatCalculator
    @ObservedObject var themes = BoardThemeStore.shared
    let close: () -> Void
    @FocusState private var focused: Bool

    private let topRows = [
        ["MC", "MR", "MS", "M+", "M-"],
        ["←", "CE", "C", "±", "√"],
        ["7", "8", "9", "/", "%"],
        ["4", "5", "6", "*", "1/x"],
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Calculator").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: close) { Text("✕").font(.system(size: 15)) }
                    .buttonStyle(.plain)
                    .help("Close calculator")
            }
            .foregroundStyle(CatStyle.headerInk)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(CatStyle.navy)

            VStack(alignment: .trailing, spacing: 0) {
                Text(calc.expression.isEmpty ? " " : calc.expression)
                    .font(.system(size: 11))
                    .foregroundStyle(CatStyle.muted)
                    .frame(minHeight: 16)
                Text(calc.current)
                    .font(.system(size: 20, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(CatStyle.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contextMenu { Button("Copy") { calc.copy() } }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 4).fill(CatStyle.surface2))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(CatStyle.line, lineWidth: 1))
            .padding(10)

            VStack(spacing: CatStyle.gap) {
                ForEach(topRows, id: \.self) { row in
                    HStack(spacing: CatStyle.gap) {
                        ForEach(row, id: \.self) { CatKey(label: $0, press: calc.press) }
                    }
                }
                HStack(spacing: CatStyle.gap) {
                    VStack(spacing: CatStyle.gap) {
                        HStack(spacing: CatStyle.gap) {
                            ForEach(["1", "2", "3", "-"], id: \.self) { CatKey(label: $0, press: calc.press) }
                        }
                        GeometryReader { geo in
                            let unit = (geo.size.width - CatStyle.gap * 3) / 4
                            HStack(spacing: CatStyle.gap) {
                                CatKey(label: "0", press: calc.press).frame(width: unit * 2 + CatStyle.gap)
                                CatKey(label: ".", press: calc.press).frame(width: unit)
                                CatKey(label: "+", press: calc.press).frame(width: unit)
                            }
                        }
                        .frame(height: CatStyle.keyHeight)
                    }
                    CatKey(label: "=", press: calc.press, height: CatStyle.keyHeight * 2 + CatStyle.gap)
                        .frame(width: 48)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .frame(width: 280)
        .frame(maxHeight: .infinity, alignment: .top)
        .id(themes.theme.id)
        .background(CatStyle.surface)
        .ignoresSafeArea()
        .environment(\.colorScheme, themes.theme.colorScheme)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(phases: .down) { press in
            guard let key = key(for: press) else { return .ignored }
            calc.press(key)
            return .handled
        }
        .onAppear { focused = true }
    }

    private func key(for press: KeyPress) -> String? {
        switch press.key {
        case .return: return "="
        case .delete: return "←"
        case .deleteForward: return "CE"
        default: break
        }
        if press.modifiers.contains(.command) {
            if press.characters == "c" { calc.copy() }
            return nil
        }
        switch press.characters {
        case "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "+", "-", "*", "/", "%", "=": return press.characters
        case "x", "X": return "*"
        case ",": return "."
        case "c", "C": return "C"
        case "r", "R": return "1/x"
        case "@": return "√"
        default: return nil
        }
    }
}

final class CalculatorApp: PocketApp {
    private let calc = CatCalculator()

    override var defaultSize: NSSize { NSSize(width: 280, height: 307) }
    override var resizable: Bool { false }

    override func makeContent() -> NSView {
        ThemedHostingView(rootView: CalcView(calc: calc) { [weak self] in self?.hide(reason: "close button") })
    }
}
