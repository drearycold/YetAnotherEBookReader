import SwiftUI

struct BookProgressSection: View {
    let summary: BookDetailViewModel.ReadingProgressSummary?
    let hasHistory: Bool
    let showHistory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                switch summary {
                case .goodreadsReadDate(let date):
                    Label(date, systemImage: "checkmark.circle")
                case .goodreadsProgress(let progress):
                    Label("\(progress)%", systemImage: "hourglass")
                case .localProgress(let percent, let device):
                    VStack(alignment: .leading, spacing: 8) {
                        Label(String(format: "%.1f%%", percent), systemImage: "book.circle")
                        ProgressView(value: min(100, max(0, percent)), total: 100)
                        Text("on \(device)").font(.subheadline).foregroundColor(.secondary)
                    }
                case nil:
                    Text("No Reading History").foregroundColor(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            if hasHistory {
                Button(action: showHistory) { Label("Reading History", systemImage: "clock") }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("book-detail.progress-history")
            }
        }
    }
}
