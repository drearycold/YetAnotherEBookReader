import SwiftUI

struct BookConnectivitySection: View {
    let libraryName: String
    let serverName: String?
    let bookID: String
    let lastModified: String?
    let refreshState: BookDetailViewModel.RefreshState
    let showFailure: (String) -> Void
    let retry: () -> Void
    let showActivity: () -> Void

    init(book: CalibreBook, refreshState: BookDetailViewModel.RefreshState,
         showFailure: @escaping (String) -> Void, retry: @escaping () -> Void,
         showActivity: @escaping () -> Void) {
        libraryName = book.library.name
        serverName = book.library.server.isLocal ? nil : book.library.server.name
        bookID = book.id.description
        lastModified = book.lastModified.timeIntervalSince1970 != 0 ? book.lastModifiedByLocale : nil
        self.refreshState = refreshState
        self.showFailure = showFailure
        self.retry = retry
        self.showActivity = showActivity
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                switch refreshState {
                case .idle: Label("Details Saved on This Device", systemImage: "arrow.clockwise")
                case .refreshing: Label("Syncing with Server", systemImage: "arrow.clockwise")
                case .synced: Label("In Sync with Server", systemImage: "checkmark.shield")
                case .local: Label("Local File", systemImage: "doc")
                case .unavailable: Label("Unavailable on Server", systemImage: "xmark.shield")
                case .failed(let message):
                    Button { showFailure(message) } label: {
                        Label("Refresh Failed", systemImage: "exclamationmark.shield")
                    }
                    .frame(minHeight: 44)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            if refreshState == .unavailable {
                Text("The server cannot provide this book. Downloaded files remain available to read.")
                    .font(.subheadline).foregroundColor(.secondary)
            }
            if case .failed = refreshState {
                Button("Retry Refresh", action: retry).frame(minHeight: 44)
            }
            BookMetadataValue(title: "Library", value: libraryName)
            if let serverName { BookMetadataValue(title: "Server", value: serverName) }
            BookMetadataValue(title: "Book ID", value: bookID)
            if let lastModified {
                BookMetadataValue(title: "Last Modified", value: lastModified)
            }
            Button(action: showActivity) { Label("Activity Logs", systemImage: "scroll") }
                .frame(minHeight: 44)
        }
    }
}
