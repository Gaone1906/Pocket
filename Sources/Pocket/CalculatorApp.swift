import AppKit
import SwiftUI

enum CalcEngine {
    static func evaluate(_ text: String, ans: Double = 0, degrees: Bool = true) -> Double? {
        var parser = Parser(chars: Array(text.filter { !$0.isWhitespace }), ans: ans, degrees: degrees)
        guard let value = parser.expression(), parser.atEnd, value.isFinite else { return nil }
        return value
    }

    static func format(_ value: Double) -> String {
        if value == 0 { return "0" }
        return String(format: "%.10g", value)
    }

    static func display(_ text: String, ans: Double = 0, degrees: Bool = true) -> String? {
        evaluate(text, ans: ans, degrees: degrees).map(format)
    }

    struct Parser {
        let chars: [Character]
        let ans: Double
        let degrees: Bool
        var index = 0

        init(chars: [Character], ans: Double, degrees: Bool) {
            self.chars = chars
            self.ans = ans
            self.degrees = degrees
        }

        var atEnd: Bool { index >= chars.count }

        func peek() -> Character? { index < chars.count ? chars[index] : nil }

        func startsOperand(_ c: Character) -> Bool {
            (c.isASCII && (c.isNumber || c.isLetter)) || "(.π√∛".contains(c)
        }

        mutating func expression() -> Double? {
            guard var left = term() else { return nil }
            while let op = peek(), "+-−".contains(op) {
                index += 1
                guard let right = term() else { return nil }
                left = op == "+" ? left + right : left - right
            }
            return left
        }

        mutating func term() -> Double? {
            guard var left = unary() else { return nil }
            while let op = peek() {
                if "*×/÷".contains(op) {
                    index += 1
                    guard let right = unary() else { return nil }
                    if "*×".contains(op) {
                        left *= right
                    } else {
                        if right == 0 { return nil }
                        left /= right
                    }
                } else if startsOperand(op) {
                    guard let right = power() else { return nil }
                    left *= right
                } else {
                    break
                }
            }
            return left
        }

        mutating func unary() -> Double? {
            if let op = peek(), "+-−".contains(op) {
                index += 1
                guard let value = unary() else { return nil }
                return op == "+" ? value : -value
            }
            return power()
        }

        mutating func power() -> Double? {
            guard let base = postfix() else { return nil }
            if peek() == "^" {
                index += 1
                guard let exponent = unary() else { return nil }
                let result = pow(base, exponent)
                return result.isFinite ? result : nil
            }
            return base
        }

        mutating func postfix() -> Double? {
            guard var value = primary() else { return nil }
            while let c = peek() {
                switch c {
                case "%": value /= 100
                case "²": value *= value
                case "³": value = value * value * value
                case "!":
                    guard value >= 0, value <= 170 else { return nil }
                    value = tgamma(value + 1)
                case "⁻":
                    guard index + 1 < chars.count, chars[index + 1] == "¹", value != 0 else { return nil }
                    index += 1
                    value = 1 / value
                default:
                    return value
                }
                index += 1
            }
            return value
        }

        mutating func primary() -> Double? {
            guard let c = peek() else { return nil }
            if c == "(" {
                index += 1
                guard let value = expression() else { return nil }
                if peek() == ")" { index += 1 }
                return value
            }
            if c == "π" {
                index += 1
                return .pi
            }
            if c == "√" || c == "∛" {
                index += 1
                guard let value = postfix() else { return nil }
                if c == "√" { return value < 0 ? nil : value.squareRoot() }
                return cbrt(value)
            }
            if c.isASCII && c.isLetter {
                let start = index
                while let next = peek(), next.isASCII, next.isLetter { index += 1 }
                return named(String(chars[start..<index]).lowercased())
            }
            return number()
        }

        mutating func named(_ name: String) -> Double? {
            switch name {
            case "ans": return ans
            case "e": return M_E
            case "pi": return .pi
            default: break
            }
            guard peek() == "(" else { return nil }
            index += 1
            guard let x = expression() else { return nil }
            if peek() == ")" { index += 1 }
            let toRadians = degrees ? Double.pi / 180 : 1
            let fromRadians = degrees ? 180 / Double.pi : 1
            switch name {
            case "sin": return snap(sin(x * toRadians))
            case "cos": return snap(cos(x * toRadians))
            case "tan":
                guard abs(cos(x * toRadians)) > 1e-12 else { return nil }
                return snap(tan(x * toRadians))
            case "asin": return (-1...1).contains(x) ? asin(x) * fromRadians : nil
            case "acos": return (-1...1).contains(x) ? acos(x) * fromRadians : nil
            case "atan": return atan(x) * fromRadians
            case "log": return x > 0 ? log10(x) : nil
            case "ln": return x > 0 ? log(x) : nil
            case "sqrt": return x < 0 ? nil : x.squareRoot()
            case "cbrt": return cbrt(x)
            case "abs": return abs(x)
            case "exp": return exp(x)
            default: return nil
            }
        }

        func snap(_ value: Double) -> Double { abs(value) < 1e-12 ? 0 : value }

        mutating func number() -> Double? {
            let start = index
            var digits = 0
            var dots = 0
            while let c = peek(), c.isASCII, c.isNumber || c == "." {
                if c == "." { dots += 1 } else { digits += 1 }
                index += 1
            }
            guard digits > 0, dots <= 1 else { return nil }
            return Double(String(chars[start..<index]))
        }
    }
}

struct CalcEntry: Identifiable {
    let id = UUID()
    let expression: String
    let result: String
}

final class CalcModel: ObservableObject {
    @Published var expression = ""
    @Published var history: [CalcEntry] = []
    @Published var focusTick = 0

    var result: String? { CalcEngine.display(expression) }

    func append(_ token: String) { expression += token }

    func clear() { expression = "" }

    func backspace() {
        if !expression.isEmpty { expression.removeLast() }
    }

    func commit() {
        guard let result else { return }
        history.insert(CalcEntry(expression: expression, result: result), at: 0)
        if history.count > 6 { history.removeLast(history.count - 6) }
        expression = result
    }

    func reuse(_ entry: CalcEntry) { expression = entry.result }

    func copyResult() {
        guard let result else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result, forType: .string)
    }
}

struct CalcView: View {
    @ObservedObject var model: CalcModel
    @FocusState private var focused: Bool

    private let rows: [[String]] = [
        ["C", "⌫", "(", ")"],
        ["7", "8", "9", "÷"],
        ["4", "5", "6", "×"],
        ["1", "2", "3", "−"],
        ["0", ".", "%", "+"],
    ]

    var body: some View {
        VStack(spacing: 8) {
            TextField("0", text: $model.expression)
                .textFieldStyle(.plain)
                .font(.system(size: 22, design: .monospaced))
                .focused($focused)
                .onSubmit { model.commit() }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.07)))

            HStack(spacing: 6) {
                Text(model.expression.isEmpty ? "" : (model.result ?? "—"))
                    .font(.system(size: 26, weight: .semibold, design: .monospaced))
                    .foregroundColor(model.result == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Button {
                    model.copyResult()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .disabled(model.result == nil)
                .help("Copy result")
            }
            .frame(height: 32)

            VStack(spacing: 2) {
                ForEach(model.history) { entry in
                    Button {
                        model.reuse(entry)
                        focused = true
                    } label: {
                        Text("\(entry.expression) = \(entry.result)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)

            VStack(spacing: 6) {
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 6) {
                        ForEach(row, id: \.self) { key in
                            keyButton(key)
                        }
                    }
                }
                keyButton("=")
            }
        }
        .padding(.top, 28)
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .frame(width: 320, height: 470)
        .onAppear { focused = true }
        .onChange(of: model.focusTick) { _, _ in focused = true }
    }

    private func keyButton(_ key: String) -> some View {
        let isOperator = "÷×−+=".contains(key)
        return Button {
            switch key {
            case "C": model.clear()
            case "⌫": model.backspace()
            case "=": model.commit()
            default: model.append(key)
            }
            focused = true
        } label: {
            Text(key)
                .font(.system(size: 16, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 32)
                .foregroundColor(key == "=" ? .white : .primary)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(key == "=" ? Color.accentColor : Color.primary.opacity(isOperator ? 0.16 : 0.08))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

final class CalculatorApp: PocketApp {
    private let model = CalcModel()

    override var defaultSize: NSSize { NSSize(width: 320, height: 470) }
    override var resizable: Bool { false }

    override func makeContent() -> NSView {
        NSHostingView(rootView: CalcView(model: model))
    }

    override func didShow() {
        model.focusTick += 1
    }
}
