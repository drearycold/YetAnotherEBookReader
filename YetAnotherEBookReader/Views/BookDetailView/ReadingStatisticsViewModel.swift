import SwiftUI
import Combine

struct BookHistoryItem: Identifiable {
    var id: String { book.inShelfId }
    let book: CalibreBook
    let minutesText: String
}

@MainActor
final class ReadingStatisticsViewModel: ObservableObject {
    let statistics: ReadingStatisticsModel
    @Published private(set) var booksHistoryItems = [BookHistoryItem]()
    @Published var isHistoryActive = false
    @Published private(set) var displayedHistory: ReadingPositionHistoryViewModel?
    @Published var alertItem: AlertItem?

    private let context: ReadingHistoryContext
    private let makeHistory: (CalibreBook) -> ReadingPositionHistoryViewModel
    private let minutesFormatter = NumberFormatter()
    private var contextTask: Task<Void, Never>?
    private var snapshotSubscription: AnyCancellable?
    private var snapshot: ReadingStatistics?

    init(container: AppContainer, now: @escaping () -> Date = Date.init, calendar: @escaping () -> Calendar = { .current }) {
        context = ReadingHistoryContext(container: container)
        statistics = ReadingStatisticsModel(repository: container.readingHistoryRepository, now: now, calendar: calendar)
        makeHistory = { ReadingPositionHistoryViewModel(container: container, book: $0, now: now, calendar: calendar) }
        minutesFormatter.minimumFractionDigits = 1
        minutesFormatter.maximumFractionDigits = 1
        snapshotSubscription = statistics.$snapshot.sink { [weak self] snapshot in
            self?.snapshot = snapshot
            self?.updateBooks()
        }
    }

    deinit { contextTask?.cancel() }

    func start() {
        guard contextTask == nil else { return }
        updateContext()
        let changes = context.changes()
        contextTask = Task { [weak self] in
            for await _ in changes {
                guard !Task.isCancelled else { return }
                self?.updateContext()
            }
        }
    }

    func stop() {
        contextTask?.cancel()
        contextTask = nil
        statistics.stop()
    }

    func clockDidChange() { statistics.refresh() }

    func showHistory(for id: String) {
        guard let book = context.shelf[id] else {
            alertItem = AlertItem(id: "Book Unavailable")
            return
        }
        if displayedHistory?.bookIdentity != id {
            displayedHistory = makeHistory(book)
        }
        isHistoryActive = true
    }

    private func updateContext() {
        statistics.start(scope: context.scope())
        updateBooks()
    }

    private func updateBooks() {
        guard let snapshot else {
            booksHistoryItems = []
            return
        }
        let shelf = context.shelf
        booksHistoryItems = snapshot.rankedBookIDs.compactMap { id in
            guard let book = shelf[id], let minutes = snapshot.minutesByBook[id],
                  let text = minutesFormatter.string(from: NSNumber(value: minutes)) else { return nil }
            return BookHistoryItem(book: book, minutesText: text)
        }
    }
}
