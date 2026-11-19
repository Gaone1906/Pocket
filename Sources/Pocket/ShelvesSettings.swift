import AppKit
import SwiftUI

struct ShelvesSettings: View {
    @ObservedObject var layout = Layout.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Menu bar apps sit in the menu bar; every other shelf is a group in the Pocket dropdown. Drag apps between shelves, drag a shelf by its handle to reorder, or right-click an app to move it.")
                .font(.system(size: 12))
                .foregroundStyle(Board.muted)
                .fixedSize(horizontal: false, vertical: true)
            ShelfList(layout: layout, editing: true) { id in
                AppDelegate.shared.open(id, source: "settings")
            }
        }
        .frame(maxWidth: 560, alignment: .leading)
        .animation(Board.glide, value: layout.shelves)
        .animation(Board.glide, value: layout.bar)
    }
}
