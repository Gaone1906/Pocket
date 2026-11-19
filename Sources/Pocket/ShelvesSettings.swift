import SwiftUI

struct ShelvesSettings: View {
    @ObservedObject var layout = Layout.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            shelf("MENU BAR", layout.bar)
            shelf("DROPDOWN", layout.tray)
        }
        .frame(maxWidth: 560, alignment: .leading)
    }

    private func shelf(_ title: String, _ ids: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsTitle(text: title)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
                ForEach(ids, id: \.self) { id in
                    HStack(spacing: 6) {
                        Image(systemName: spec(id)?.symbol ?? "questionmark.square")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Board.accentInkStyle)
                        Text(spec(id)?.name ?? id)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Board.ink)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Board.column))
                    .boardEdge(10)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Board.column.opacity(0.5)))
            .boardEdge(16)
        }
    }
}
