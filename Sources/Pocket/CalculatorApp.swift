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
    @Published var shift = false
    @Published var ans: Double = 0
    @Published var degrees: Bool {
        didSet { UserDefaults.standard.set(degrees, forKey: "calc.degrees") }
    }

    init() {
        degrees = UserDefaults.standard.object(forKey: "calc.degrees") as? Bool ?? true
    }

    var result: String? { CalcEngine.display(expression, ans: ans, degrees: degrees) }

    func append(_ token: String) { expression += token }

    func clear() { expression = "" }

    func backspace() {
        for token in ["asin(", "acos(", "atan(", "sin(", "cos(", "tan(", "log(", "ln(", "10^(", "e^(", "Ans", "×10^", "⁻¹", "√(", "∛("] where expression.hasSuffix(token) {
            expression.removeLast(token.count)
            return
        }
        if !expression.isEmpty { expression.removeLast() }
    }

    func commit() {
        guard !expression.isEmpty, let value = CalcEngine.evaluate(expression, ans: ans, degrees: degrees) else { return }
        let text = CalcEngine.format(value)
        history.insert(CalcEntry(expression: expression, result: text), at: 0)
        if history.count > 6 { history.removeLast(history.count - 6) }
        ans = value
        expression = ""
    }

    func copyResult() {
        guard let text = result ?? history.first?.result else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private enum CasioKind { case function, shift, digit, accent }

private struct CasioKey: Hashable {
    let label: String
    let shifted: String?
    let insert: String
    let shiftInsert: String?
    let kind: CasioKind

    init(_ label: String, _ insert: String, shifted: String? = nil, shiftInsert: String? = nil, kind: CasioKind = .function) {
        self.label = label
        self.insert = insert
        self.shifted = shifted
        self.shiftInsert = shiftInsert
        self.kind = kind
    }
}

private enum Casio {
    static let body = [Color(red: 0.20, green: 0.21, blue: 0.23), Color(red: 0.12, green: 0.12, blue: 0.14)]
    static let lcd = [Color(red: 0.80, green: 0.84, blue: 0.72), Color(red: 0.70, green: 0.76, blue: 0.62)]
    static let ink = Color(red: 0.13, green: 0.16, blue: 0.11)
    static let gold = Color(red: 0.93, green: 0.74, blue: 0.30)
    static let label = Color(red: 0.78, green: 0.80, blue: 0.83)

    static let functionRows: [[CasioKey]] = [
        [CasioKey("SHIFT", "", kind: .shift), CasioKey("DRG", "@drg"), CasioKey("x⁻¹", "⁻¹"),
         CasioKey("x²", "²"), CasioKey("x³", "³"), CasioKey("xʸ", "^")],
        [CasioKey("√", "√(", shifted: "∛", shiftInsert: "∛("), CasioKey("log", "log(", shifted: "10ˣ", shiftInsert: "10^("),
         CasioKey("ln", "ln(", shifted: "eˣ", shiftInsert: "e^("), CasioKey("sin", "sin(", shifted: "sin⁻¹", shiftInsert: "asin("),
         CasioKey("cos", "cos(", shifted: "cos⁻¹", shiftInsert: "acos("), CasioKey("tan", "tan(", shifted: "tan⁻¹", shiftInsert: "atan(")],
        [CasioKey("(−)", "−"), CasioKey("(", "("), CasioKey(")", ")"),
         CasioKey("%", "%"), CasioKey("x!", "!"), CasioKey("π", "π", shifted: "e", shiftInsert: "e")],
    ]

    static let numberRows: [[CasioKey]] = [
        [CasioKey("7", "7", kind: .digit), CasioKey("8", "8", kind: .digit), CasioKey("9", "9", kind: .digit),
         CasioKey("DEL", "@del", kind: .accent), CasioKey("AC", "@ac", kind: .accent)],
        [CasioKey("4", "4", kind: .digit), CasioKey("5", "5", kind: .digit), CasioKey("6", "6", kind: .digit),
         CasioKey("×", "×", kind: .digit), CasioKey("÷", "÷", kind: .digit)],
        [CasioKey("1", "1", kind: .digit), CasioKey("2", "2", kind: .digit), CasioKey("3", "3", kind: .digit),
         CasioKey("+", "+", kind: .digit), CasioKey("−", "−", kind: .digit)],
        [CasioKey("0", "0", kind: .digit), CasioKey(".", ".", kind: .digit), CasioKey("×10ˣ", "×10^", kind: .digit),
         CasioKey("Ans", "Ans", kind: .digit), CasioKey("=", "@eq", kind: .digit)],
    ]
}

private struct CasioKeyStyle: ButtonStyle {
    let kind: CasioKind
    let height: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        let fill: [Color] = switch kind {
        case .function, .shift: [Color(red: 0.30, green: 0.31, blue: 0.34), Color(red: 0.22, green: 0.23, blue: 0.25)]
        case .digit: [Color(red: 0.90, green: 0.90, blue: 0.91), Color(red: 0.76, green: 0.77, blue: 0.79)]
        case .accent: [Color(red: 0.93, green: 0.52, blue: 0.24), Color(red: 0.80, green: 0.38, blue: 0.16)]
        }
        let ink: Color = switch kind {
        case .function: .white
        case .shift: Casio.gold
        case .digit: Color(red: 0.12, green: 0.12, blue: 0.14)
        case .accent: .white
        }
        let pressed = configuration.isPressed
        return configuration.label
            .font(.system(size: kind == .digit || kind == .accent ? 15 : 11, weight: .semibold))
            .foregroundStyle(ink)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: kind == .function || kind == .shift ? 7 : 6)
                    .fill(LinearGradient(colors: pressed ? fill.reversed() : fill, startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.55), radius: 0, x: 0, y: pressed ? 0 : 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: kind == .function || kind == .shift ? 7 : 6)
                    .stroke(Color.white.opacity(kind == .digit ? 0.5 : 0.08), lineWidth: 0.5)
            )
            .offset(y: pressed ? 1.5 : 0)
            .contentShape(Rectangle())
    }
}

private struct SolarPanel: View {
    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<4, id: \.self) { _ in
                LinearGradient(colors: [Color(red: 0.30, green: 0.21, blue: 0.17), Color(red: 0.17, green: 0.11, blue: 0.09)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .padding(2)
        .background(Color.black.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .frame(width: 92, height: 24)
    }
}

struct CalcView: View {
    @ObservedObject var model: CalcModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("POCKET").font(.system(size: 15, weight: .heavy)).italic().tracking(2).foregroundStyle(Casio.label)
                    Text("SCIENTIFIC CALCULATOR").font(.system(size: 7, weight: .semibold)).tracking(1.2).foregroundStyle(Casio.label.opacity(0.6))
                }
                Spacer()
                SolarPanel()
            }
            .padding(.top, 30)
            display.padding(.top, 12)
            VStack(spacing: 4) {
                ForEach(Casio.functionRows, id: \.self) { row in
                    HStack(spacing: 7) {
                        ForEach(row, id: \.self) { key in
                            VStack(spacing: 2) {
                                Text(key.shifted ?? " ")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(Casio.gold.opacity(model.shift ? 1 : 0.75))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                keyButton(key, height: 24)
                            }
                        }
                    }
                }
            }
            .padding(.top, 12)
            VStack(spacing: 9) {
                ForEach(Casio.numberRows, id: \.self) { row in
                    HStack(spacing: 9) {
                        ForEach(row, id: \.self) { key in keyButton(key, height: 34) }
                    }
                }
            }
            .padding(.top, 14)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
        .frame(width: 340, height: 498)
        .background(
            ZStack {
                LinearGradient(colors: Casio.body, startPoint: .top, endPoint: .bottom)
                RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.06), lineWidth: 1).padding(5)
            }
        )
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .onAppear { focused = true }
        .onChange(of: model.focusTick) { _, _ in focused = true }
    }

    private var display: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text("S").opacity(model.shift ? 1 : 0)
                Text(model.degrees ? "D" : "R")
                Spacer()
                Button { model.copyResult() } label: { Image(systemName: "doc.on.doc").font(.system(size: 9)) }
                    .buttonStyle(.plain)
                    .help("Copy the answer")
            }
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(Casio.ink.opacity(0.8))
            TextField("", text: $model.expression, prompt: Text(model.history.first.map { $0.expression } ?? "").foregroundColor(Casio.ink.opacity(0.35)))
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .foregroundStyle(Casio.ink)
                .focused($focused)
                .onSubmit { model.commit() }
            Text(shownResult)
                .font(.system(size: 30, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(Casio.ink.opacity(resultIsLive ? 1 : 0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(colors: Casio.lcd, startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
        )
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(0.75)))
    }

    private var resultIsLive: Bool { !model.expression.isEmpty }

    private var shownResult: String {
        if model.expression.isEmpty { return model.history.first?.result ?? "0" }
        return model.result ?? "Math ERROR"
    }

    private func keyButton(_ key: CasioKey, height: CGFloat) -> some View {
        Button {
            press(key)
        } label: {
            Text(key.label)
        }
        .buttonStyle(CasioKeyStyle(kind: key.kind, height: height))
        .help(key.shifted.map { "SHIFT: \($0)" } ?? "")
    }

    private func press(_ key: CasioKey) {
        defer { focused = true }
        if key.kind == .shift {
            model.shift.toggle()
            return
        }
        let token = model.shift ? (key.shiftInsert ?? key.insert) : key.insert
        model.shift = false
        switch token {
        case "@ac": model.clear()
        case "@del": model.backspace()
        case "@eq": model.commit()
        case "@drg": model.degrees.toggle()
        default:
            if model.expression.isEmpty, !model.history.isEmpty, "+−×÷^²³!%⁻".contains(token.first ?? " ") {
                model.append("Ans")
            }
            model.append(token)
        }
    }
}

final class CalculatorApp: PocketApp {
    private let model = CalcModel()

    override var defaultSize: NSSize { NSSize(width: 340, height: 498) }
    override var resizable: Bool { false }

    override func makeContent() -> NSView {
        let hosting = NSHostingView(rootView: CalcView(model: model))
        hosting.appearance = NSAppearance(named: .darkAqua)
        return hosting
    }

    override func didShow() {
        model.focusTick += 1
    }
}
