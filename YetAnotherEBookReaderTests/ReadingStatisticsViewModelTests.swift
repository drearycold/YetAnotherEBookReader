import XCTest
import Combine
@testable import YetAnotherEBookReader

@MainActor
final class ReadingStatisticsViewModelTests: XCTestCase {
    private var container: AppContainer!
    private var repository: MockReadingHistoryRepository!
    private var book: CalibreBook!
    private let now = Date(timeIntervalSince1970: 1_712_577_600)

    override func setUpWithError() throws {
        container = MockAppContainerFactory.makeContainer(testName: "ReadingStatisticsViewModelTests")
        repository = MockReadingHistoryRepository()
        container.readingHistoryRepository = repository
        book = TestFixtures.makeBook()
        container.booksInShelf = [book.inShelfId: book]
    }

    override func tearDownWithError() throws {
        container = nil
        repository = nil
        book = nil
    }

    func testLoadingFailureRetryEmptyAndSuccessOnlyQueryStatistics() async throws {
        let positions = MockReadingPositionRepository()
        let books = MockBookRepository()
        container.readingPositionRepository = positions
        container.bookRepository = books
        let view = makeView()
        XCTAssertEqual(view.statistics.state, .loading)
        XCTAssertNil(view.statistics.snapshot)
        repository.statisticsRead = { _, _ in throw URLError(.notConnectedToInternet) }
        view.start()
        view.start()
        defer { view.stop() }
        await expect(view.statistics.$state) { $0 == .failed }
        XCTAssertTrue(view.booksHistoryItems.isEmpty)
        XCTAssertEqual(repository.statisticsWindows.count, 1)
        repository.statisticsRead = nil
        view.statistics.refresh()
        await expect(view.statistics.$state) { $0 == .ready }
        XCTAssertFalse(view.statistics.hasReading)

        repository.history = [session()]
        repository.statisticsChanges.send(())
        await expect(view.$booksHistoryItems) { $0.count == 1 }
        XCTAssertEqual(view.statistics.todayMinutes, 1)
        XCTAssertEqual(view.booksHistoryItems.first?.id, book.inShelfId)
        XCTAssertTrue(repository.sessionLimits.isEmpty)
        XCTAssertTrue(repository.detailIDs.isEmpty)
        XCTAssertFalse(positions.getPositionsCalled)
        XCTAssertEqual(positions.positionsBroadcaster.subscriberCount, 0)
        XCTAssertFalse(books.observeBookCalled)
        view.statistics.refresh()
        XCTAssertEqual(view.statistics.state, .loading)
        XCTAssertEqual(view.statistics.presentationState, .ready)
        XCTAssertEqual(view.booksHistoryItems.first?.id, book.inShelfId)
        view.stop()
        view.stop()
        XCTAssertEqual(repository.statisticsChanges.subscriberCount, 0)
    }

    func testScopeChangeRejectsLateStatisticsAndRouteKeepsBookHistoryModel() async throws {
        let view = makeView()
        let entered = expectation(description: "Old statistics suspended")
        let returned = expectation(description: "Old statistics returned")
        var release: CheckedContinuation<ReadingStatistics, Never>?
        repository.statisticsRead = { _, _ in
            let result = await withCheckedContinuation { continuation in
                release = continuation
                entered.fulfill()
            }
            returned.fulfill()
            return result
        }
        view.start()
        defer { view.stop() }
        await fulfillment(of: [entered], timeout: 5)
        let oldWindow = try XCTUnwrap(repository.statisticsWindows.first)
        let obsolete = ReadingStatistics(window: oldWindow, historyByBook: [book.inShelfId: [session()]])
        repository.statisticsRead = nil
        container.booksInShelf = [:]
        await expect(view.statistics.$state) { $0 == .ready }
        XCTAssertFalse(view.statistics.hasReading)
        let continuation = try XCTUnwrap(release)
        continuation.resume(returning: obsolete)
        await fulfillment(of: [returned], timeout: 5)
        XCTAssertFalse(view.statistics.hasReading)
        XCTAssertTrue(view.booksHistoryItems.isEmpty)
        view.showHistory(for: book.inShelfId)
        XCTAssertEqual(view.alertItem?.id, "Book Unavailable")
        XCTAssertNil(view.displayedHistory)

        container.booksInShelf = [book.inShelfId: book]
        repository.history = [session()]
        repository.statisticsChanges.send(())
        await expect(view.$booksHistoryItems) { $0.count == 1 }
        view.showHistory(for: book.inShelfId)
        let history = try XCTUnwrap(view.displayedHistory)
        XCTAssertEqual(history.bookIdentity, book.inShelfId)
        view.stop()
        view.isHistoryActive = false
        view.start()
        view.showHistory(for: book.inShelfId)
        XCTAssertTrue(view.displayedHistory === history)
        XCTAssertTrue(repository.sessionLimits.isEmpty)
    }

    func testTitleChangesUpdateRankingWithoutAnotherStatisticsRead() async throws {
        repository.history = [session()]
        let view = makeView()
        view.start()
        defer { view.stop() }
        await expect(view.$booksHistoryItems) { $0.count == 1 }
        let count = repository.statisticsWindows.count
        var changed = try XCTUnwrap(book)
        changed.title = "Renamed Book"
        container.booksInShelf[changed.inShelfId] = changed
        await expect(view.$booksHistoryItems) { $0.first?.book.title == "Renamed Book" }
        XCTAssertEqual(repository.statisticsWindows.count, count)
    }

    func testDisappearanceRejectsLateResultAndReappearanceReadsCurrentWindow() async throws {
        let view = makeView()
        let entered = expectation(description: "Query suspended")
        let returned = expectation(description: "Query returned")
        var release: CheckedContinuation<ReadingStatistics, Never>?
        repository.statisticsRead = { _, _ in
            let result = await withCheckedContinuation { continuation in
                release = continuation
                entered.fulfill()
            }
            returned.fulfill()
            return result
        }
        view.start()
        await fulfillment(of: [entered], timeout: 5)
        let old = ReadingStatistics(window: try XCTUnwrap(repository.statisticsWindows.first),
                                    historyByBook: [book.inShelfId: [session()]])
        view.stop()
        repository.statisticsRead = nil
        view.start()
        await expect(view.statistics.$state) { $0 == .ready }
        let continuation = try XCTUnwrap(release)
        continuation.resume(returning: old)
        await fulfillment(of: [returned], timeout: 5)
        XCTAssertEqual(view.statistics.todayMinutes, 0)
        view.stop()
    }

    private func makeView() -> ReadingStatisticsViewModel {
        let instant = now
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return ReadingStatisticsViewModel(container: container, now: { instant }, calendar: { calendar })
    }

    private func session() -> BookDeviceReadingPositionHistory {
        BookDeviceReadingPositionHistory(
            id: .init(serverUUID: book.library.server.uuid, objectID: "statistics-session"),
            bookId: book.bookPrefId, startDatetime: now.addingTimeInterval(-60), startPosition: nil,
            endPosition: TestFixtures.makeReadingPosition(epoch: now.timeIntervalSince1970)
        )
    }

    private func expect<P: Publisher>(_ publisher: P, where predicate: @escaping (P.Output) -> Bool) async
    where P.Failure == Never {
        let published = expectation(description: "Expected statistics state")
        let subscription = publisher.first(where: predicate).sink { _ in published.fulfill() }
        await fulfillment(of: [published], timeout: 5)
        subscription.cancel()
    }
}
