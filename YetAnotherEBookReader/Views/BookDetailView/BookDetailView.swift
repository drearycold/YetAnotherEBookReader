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
            ScrollViewReader { scroll in
                ScrollView {
                    if let book = viewModel.calibreBook, book.inShelfId == bookId {
                        content(for: book, width: min(960, max(0, geometry.size.width - 32))) {
                            scroll.scrollTo(BookDetailContentView.descriptionID, anchor: .top)
                        }
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
        }
        .navigationTitle("Book Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { BookDetailToolbar(viewModel: viewModel) }
        .alert(item: $viewModel.alertItem) { item in
            Alert(title: Text(item.id), message: Text(item.msg ?? item.id))
        }
        .sheet(item: Binding(get: { viewModel.previewViewModel }, set: { if $0 == nil { viewModel.closePreview() } })) { preview in
            BookPreviewView(viewModel: preview).id(preview.id)
        }
        .sheet(item: Binding(get: { viewModel.activityViewModel }, set: { if $0 == nil { viewModel.closeActivity() } })) { activity in
            NavigationView {
                ActivityList(viewModel: activity, close: viewModel.closeActivity)
            }
            .navigationViewStyle(.stack)
        }
        .confirmationDialog("Clear Downloaded File?", isPresented: Binding(
            get: { viewModel.clearingFormat != nil },
            set: { if !$0 { viewModel.clearingFormat = nil } }), titleVisibility: .visible) {
                if let format = viewModel.clearingFormat, let book = viewModel.calibreBook {
                    Button("Clear \(format.rawValue) Download", role: .destructive) {
                        viewModel.clearFormat(book: book, format: format)
                        viewModel.clearingFormat = nil
                    }
                }
                Button("Cancel", role: .cancel) { viewModel.clearingFormat = nil }
            } message: {
                Text("Removes this downloaded file from this device. You can download it again from the server. Reading history and annotations are kept. Clearing the last downloaded format also removes the book from Recent.")
            }
        .background(readingHistoryLink)
        .onAppear { viewModel.onAppear(bookId: bookId, targetWorkspaceID: readerWorkspaceID) }
        .onChange(of: bookId) { id in
            viewModel.onAppear(bookId: id, targetWorkspaceID: readerWorkspaceID)
        }
        .onDisappear { viewModel.onDisappear() }
        .accessibilityIdentifier("screen.book-detail")
    }

    private func content(for book: CalibreBook, width: CGFloat, scrollToDescription: @escaping () -> Void) -> some View {
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
                showActivity: { viewModel.showActivity(book: book) }),
            countPages: countPages.isEnabled ? BookCountPagesCorner(book: book, countPage: countPages) : nil,
            scrollToDescription: scrollToDescription)
    }

    private func formatRows(for book: CalibreBook) -> [BookFormatRow] {
        viewModel.formatStates.map { state in
            BookFormatRow(state: state,
                cache: { if let format = state.format { viewModel.cacheFormat(book: book, format: format) } },
                clear: { viewModel.clearingFormat = state.format },
                preview: { if let format = state.format, let info = book.formats[state.id] {
                    _ = viewModel.previewAction(book: book, format: format, formatInfo: info)
                } },
                pauseOrResume: { if let format = state.format {
                    if state.download?.isDownloading == true { viewModel.pauseDownload(book: book, format: format) }
                    else { viewModel.resumeDownload(book: book, format: format) }
                } },
                cancel: { if let format = state.format { viewModel.cancelDownload(book: book, format: format) } })
        }
    }

    /// One pushed route serves the progress section and toolbar, preserving the reader workspace.
    private var readingHistoryLink: some View {
        NavigationLink(isActive: $viewModel.isReadingPositionHistoryActive) {
            if let history = viewModel.readingHistoryViewModel {
                ReadingPositionHistoryView(viewModel: history)
                    .id(history.id)
            }
        } label: { EmptyView() }
        .hidden()
    }
}
