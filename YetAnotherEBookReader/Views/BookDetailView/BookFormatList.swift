import SwiftUI

struct BookFormatList: View {
    let rows: [BookFormatRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if rows.isEmpty { Text("No files available.").foregroundColor(.secondary) }
            ForEach(rows, id: \.state.id) { row in
                if row.state.id != rows.first?.state.id { Divider() }
                row
            }
        }
    }
}
