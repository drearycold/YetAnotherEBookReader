import SwiftUI

struct BookFormatList: View {
    let rows: [BookFormatRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if rows.isEmpty { Text("No supported formats available.").foregroundColor(.secondary) }
            ForEach(rows, id: \.format) { row in
                if row.format != rows.first?.format { Divider() }
                row
            }
        }
    }
}
