import SwiftUI

struct BookDetailView: View {
    @Environment(\.readerWorkspaceID) private var readerWorkspaceID
    let bookId: String
    @StateObject private var viewModel: BookDetailViewModel

    init(bookId: String, container: AppContainer) {
        self.bookId = bookId
        self._viewModel = StateObject(wrappedValue: BookDetailViewModel(container: container))
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                if let book = viewModel.calibreBook, book.inShelfId == bookId {
                    content(for: book, width: min(960, max(0, geometry.size.width - 32)))
                        .frame(maxWidth: 960)
                        .padding(16)
                        .frame(maxWidth: .infinity)
                } else if viewModel.pageState == .loading {
                    ProgressView("Loading book details...")
                        .frame(maxWidth: .infinity).padding()
                } else {
                    VStack(spacing: 12) {
                        Text("Book Unavailable").font(.headline)
                        Text("This book is no longer available in this library.")
                        Button("Retry") {
                            viewModel.onAppear(bookId: bookId, targetWorkspaceID: readerWorkspaceID)
                        }
                    }
                    .frame(maxWidth: .infinity).padding()
                    .accessibilityIdentifier("book-detail.unavailable")
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
        }
        .navigationTitle("Book Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { BookDetailToolbar(viewModel: viewModel) }
        .alert(item: $viewModel.alertItem) { item in
            Alert(title: Text(item.id), message: Text(item.msg ?? item.id))
        }
        .sheet(isPresented: $viewModel.presentingPreviewSheet, onDismiss: {
            if let book = viewModel.calibreBook { viewModel.handlePreviewDismiss(book: book) }
        }) {
            BookPreviewView(viewModel: viewModel.previewViewModel)
        }
        .sheet(isPresented: $viewModel.activityListViewPresenting) {
            NavigationView {
                if let book = viewModel.calibreBook, let container = viewModel.sharedAppContainer {
                    ActivityList(viewModel: ActivityListViewModel(container: container, libraryId: book.library.id, bookId: book.id),
                                 presenting: $viewModel.activityListViewPresenting)
                }
            }
        }
        .background(readingHistoryLink)
        .onAppear { viewModel.onAppear(bookId: bookId, targetWorkspaceID: readerWorkspaceID) }
        .onChange(of: bookId) { id in
            viewModel.onAppear(bookId: id, targetWorkspaceID: readerWorkspaceID)
        }
        .onDisappear { viewModel.onDisappear() }
        .accessibilityIdentifier("screen.book-detail")
    }

    private func content(for book: CalibreBook, width: CGFloat) -> some View {
        let countPages = viewModel.countPagesConfiguration(for: book.library)
        return BookDetailContentView(
            book: book,
            overview: BookOverviewView(book: book, availableWidth: width,
                canRead: viewModel.canRead(book), waitingToRead: viewModel.isWaitingToRead(book),
                hasActiveDownload: viewModel.hasActiveDownload(book), readActionTitle: viewModel.readActionTitle(for: book),
                read: { viewModel.readBook(book: book) },
                downloadOnly: { viewModel.downloadOnly(book: book) },
                cancelDownload: { viewModel.cancelReadDownload(book: book) }),
            progress: BookProgressSection(summary: viewModel.getReadingProgressSummary(for: book),
                hasHistory: viewModel.hasReadingHistory(for: book),
                showHistory: { viewModel.showReadingPositionHistory(book: book) }),
            formats: BookFormatList(rows: formatRows(for: book)),
            metadata: BookMetadataSection(book: book, goodreadsRating: viewModel.ratingGRDescription(for: book),
                goodreadsShelves: viewModel.goodreadsShelves(for: book)),
            connectivity: BookConnectivitySection(book: book, refreshState: viewModel.refreshState,
                showFailure: { viewModel.alertItem = AlertItem(id: "Refresh Failed", msg: $0) },
                retry: { viewModel.refresh(book: book) },
                showActivity: { viewModel.activityListViewPresenting = true }),
            countPages: countPages.isEnabled ? BookCountPagesCorner(book: book, countPage: countPages) : nil)
    }

    private func formatRows(for book: CalibreBook) -> [BookFormatRow] {
        book.formats.sorted { $0.key < $1.key }.compactMap { raw, info in
            guard let format = Format(rawValue: raw) else { return nil }
            let download = viewModel.getActiveDownload(book: book, format: format)
            return BookFormatRow(format: format, formatInfo: info, download: download,
                statusText: viewModel.getFormatStatusText(formatInfo: info),
                statusIcon: info.cached ? viewModel.getFormatStatusIcon(formatInfo: info) : "arrow.down.circle",
                cache: { viewModel.cacheFormat(book: book, format: format) },
                clear: { viewModel.clearFormat(book: book, format: format) },
                preview: {
                    if viewModel.previewAction(book: book, format: format, formatInfo: info) {
                        viewModel.presentingPreviewSheet = true
                    }
                },
                pauseOrResume: {
                    if download?.isDownloading == true { viewModel.pauseDownload(book: book, format: format) }
                    else { viewModel.resumeDownload(book: book, format: format) }
                },
                cancel: { viewModel.cancelDownload(book: book, format: format) })
        }
    }

    /// One pushed route serves the progress section and toolbar, preserving the reader workspace.
    private var readingHistoryLink: some View {
        NavigationLink(isActive: $viewModel.isReadingPositionHistoryActive) {
            if let book = viewModel.calibreBook, book.inShelfId == bookId {
                ReadingPositionHistoryView(library: book.library, bookId: book.id)
                    .id(book.inShelfId)
            }
        } label: { EmptyView() }
        .hidden()
    }
}
