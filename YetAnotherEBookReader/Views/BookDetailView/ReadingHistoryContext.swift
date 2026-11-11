import Foundation

@MainActor
final class ReadingHistoryContext {
    private let books: CalibreBookManager
    private let libraries: CalibreLibraryManager

    init(container: AppContainer) {
        books = container.bookManager
        libraries = container.libraryManager
    }

    var shelf: [String: CalibreBook] { books.booksInShelf }

    func scope(bookID: String? = nil) -> ReadingHistoryScope {
        ReadingHistoryScope(shelf: shelf, libraries: libraries.calibreLibraries, bookID: bookID)
    }

    func changes() -> AsyncStream<Void> {
        let shelfChanges = books.booksInShelfSnapshots(bufferingPolicy: .bufferingNewest(1))
        let libraryChanges = libraries.librarySnapshots(bufferingPolicy: .bufferingNewest(1))
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let tasks = [
                Task {
                    for await _ in shelfChanges {
                        guard !Task.isCancelled else { return }
                        continuation.yield()
                    }
                },
                Task {
                    for await _ in libraryChanges {
                        guard !Task.isCancelled else { return }
                        continuation.yield()
                    }
                }
            ]
            continuation.onTermination = { _ in tasks.forEach { $0.cancel() } }
        }
    }
}

enum ReadingLoadState: Equatable {
    case loading
    case ready
    case failed
}
