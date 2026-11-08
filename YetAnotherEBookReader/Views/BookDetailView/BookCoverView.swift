import SwiftUI
import KingfisherSwiftUI

struct BookOverviewView: View {
    @Environment(\.sizeCategory) private var sizeCategory
    let title: String
    let authors: String
    let coverURL: URL?
    let isLocal: Bool
    let availableWidth: CGFloat
    let canRead: Bool
    let waitingToRead: Bool
    let hasActiveDownload: Bool
    let readActionTitle: String
    let read: () -> Void
    let downloadOnly: () -> Void
    let cancelDownload: () -> Void

    init(book: CalibreBook, availableWidth: CGFloat, canRead: Bool, waitingToRead: Bool,
         hasActiveDownload: Bool, readActionTitle: String, read: @escaping () -> Void,
         downloadOnly: @escaping () -> Void, cancelDownload: @escaping () -> Void) {
        title = book.title
        authors = book.authorsDescription
        coverURL = book.coverURL
        isLocal = book.library.server.isLocal
        self.availableWidth = availableWidth
        self.canRead = canRead
        self.waitingToRead = waitingToRead
        self.hasActiveDownload = hasActiveDownload
        self.readActionTitle = readActionTitle
        self.read = read
        self.downloadOnly = downloadOnly
        self.cancelDownload = cancelDownload
    }

    var body: some View {
        Group {
            if availableWidth >= 600 && !sizeCategory.isAccessibilityCategory {
                HStack(alignment: .top, spacing: 28) {
                    cover.frame(width: min(240, availableWidth * 0.32))
                    summary
                }
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    cover.frame(maxWidth: 240).frame(maxWidth: .infinity)
                    summary
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var cover: some View {
        BookCoverView(coverURL: coverURL)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("book-detail.title")
            Text(authors)
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("book-detail.authors")
            Text(availabilityText)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("book-detail.availability")

            Button(action: read) {
                HStack {
                    if waitingToRead { ProgressView() }
                    if sizeCategory.isAccessibilityCategory {
                        Text(readActionTitle)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Label(readActionTitle, systemImage: canRead ? "book" : "tray.and.arrow.down")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(waitingToRead || (isLocal && !canRead))
            .accessibilityLabel(Text(readActionTitle))
            .accessibilityIdentifier("book-detail.read")

            if waitingToRead {
                Button("Cancel Download", action: cancelDownload)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("book-detail.cancel-download")
            } else if !canRead && !isLocal {
                Button("Download Only", action: downloadOnly)
                    .frame(minHeight: 44)
                    .disabled(hasActiveDownload)
                    .accessibilityIdentifier("book-detail.download-only")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var availabilityText: String {
        if waitingToRead { return "The book will open when the download finishes." }
        if canRead { return "Downloaded and ready to read." }
        if hasActiveDownload { return "A download is in progress." }
        if isLocal { return "No readable file is available on this device." }
        return "Download a file to read on this device."
    }
}

struct BookCoverView: View {
    let coverURL: URL?

    var body: some View {
        KFImage(coverURL)
            .placeholder {
                ZStack {
                    Color(uiColor: .tertiarySystemFill)
                    Image(systemName: "book.closed")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                }
            }
            .resizable()
            .scaledToFit()
            .frame(height: 240)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}
