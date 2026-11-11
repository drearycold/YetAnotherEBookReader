import SwiftUI

@MainActor
final class ReadingPositionHistoryViewModel: ObservableObject, Identifiable {
    let id = UUID()
    let bookIdentity: String
    let library: CalibreLibrary
    let bookId: Int32
    let statistics: ReadingStatisticsModel
    private let context: ReadingHistoryContext
    private let bookRepository: BookRepositoryProtocol
    private let positionRepository: ReadingPositionRepositoryProtocol
    private let activeBook: () -> CalibreBook?
    private let makeList: (CalibreBook) -> ReadingPositionListViewModel
    #if DEBUG
    private let testUpdate: (() -> Void)?
    var hasTestUpdate: Bool { testUpdate != nil }
    func updateTestHistory() { testUpdate?() }
    #endif
    private let deviceName: String

    static let sessionPageSize = 30

    private(set) var listViewModel: ReadingPositionListViewModel?
    @Published var debugReadingPositions = [BookDeviceReadingPosition]()
    @Published private(set) var deviceSections = [ReadingHistoryDeviceSection]()
    @Published private(set) var sessionRows = [ReadingHistorySessionRow]()
    @Published private(set) var hasMoreSessions = false
    @Published private(set) var sessionState = ReadingLoadState.loading
    @Published var alertItem: AlertItem?
    /// The position whose detail is pushed. Rows are buttons rather than NavigationLinks, so a row's
    /// Continue button is its own tap target instead of part of the link.
    @Published private(set) var isDetailActive = false
    /// The destination stays intact while its pop animation finishes.
    @Published private(set) var displayedDetail: ReadingPositionDetailViewModel?

    private let historyRepository: ReadingHistoryRepository
    private var isVisible = false
    private var scope: ReadingHistoryScope?
    private var shelfBookDisplay: BookDisplay?
    private var summaries = [ReadingHistorySessionSummary]()
    private var sessionLimit = sessionPageSize

    private var visibilityTasks = [Task<Void, Never>]()
    private var positionObserver: Task<Void, Never>?
    private var sessionObserver: Task<Void, Never>?
    private var sessionLoad: Task<Void, Never>?
    private var detailLoad: Task<Void, Never>?

    private let percentFormatter = NumberFormatter()
    private let durationFormatter = DateComponentsFormatter()
    private let sessionDateFormatter = DateFormatter()

    init(
        container: AppContainer, book: CalibreBook,
        now: @escaping () -> Date = Date.init, calendar: @escaping () -> Calendar = { .current }
    ) {
        bookIdentity = book.inShelfId
        library = book.library
        bookId = book.id
        context = ReadingHistoryContext(container: container)
        bookRepository = container.bookRepository
        positionRepository = container.readingPositionRepository
        let sessions = container.sessionManager
        activeBook = { sessions.activeReaderPresentation?.book }
        makeList = { ReadingPositionListViewModel(container: container, book: $0, positions: []) }
        deviceName = container.deviceName
        #if DEBUG
        if UITestingReadingHistoryFixture.isEnabled {
            let configuration = container.serverScopedRealmProvider.configuration(for: book.library.server)
            let books = container.bookRepository
            let manager = container.bookManager
            testUpdate = {
                try? UITestingReadingHistoryFixture.update(
                    book: book, configuration: configuration, repository: books, manager: manager
                )
            }
        } else {
            testUpdate = nil
        }
        #endif
        historyRepository = container.readingHistoryRepository
        statistics = ReadingStatisticsModel(repository: container.readingHistoryRepository, now: now, calendar: calendar)

        percentFormatter.numberStyle = .percent
        percentFormatter.minimumFractionDigits = 1

        durationFormatter.unitsStyle = .abbreviated
        durationFormatter.allowedUnits = [.hour, .minute]

        sessionDateFormatter.doesRelativeDateFormatting = true
        sessionDateFormatter.dateStyle = .short
        sessionDateFormatter.timeStyle = .short
    }

    deinit {
        visibilityTasks.forEach { $0.cancel() }
        positionObserver?.cancel()
        sessionObserver?.cancel()
        sessionLoad?.cancel()
        detailLoad?.cancel()
    }

    func start() {
        guard !isVisible else { return }
        isVisible = true

        let changes = context.changes()
        visibilityTasks = [Task { [weak self] in
            for await _ in changes {
                guard !Task.isCancelled else { return }
                self?.shelfChanged()
            }
        }]
        let shelfBook = context.shelf[bookIdentity]
        shelfBookDisplay = shelfBook.map(BookDisplay.init)
        let active = activeBook()
        updateBook(bookRepository.getBook(library: library, bookId: bookId)
                   ?? shelfBook ?? (active?.inShelfId == bookIdentity ? active : nil))
        let books = bookRepository.observeBook(id: bookIdentity)
        visibilityTasks.append(Task { [weak self] in
            for await book in books {
                guard !Task.isCancelled, let self else { return }
                let active = self.activeBook()
                let fallback = self.context.shelf[self.bookIdentity]
                    ?? (active?.inShelfId == self.bookIdentity ? active : nil)
                self.updateBook(book ?? fallback)
            }
        })
        updateHistoryScope()
    }

    func stop() {
        isVisible = false
        visibilityTasks.forEach { $0.cancel() }
        visibilityTasks.removeAll()
        positionObserver?.cancel()
        positionObserver = nil
        statistics.stop()
        sessionObserver?.cancel()
        sessionObserver = nil
        sessionLoad?.cancel()
        detailLoad?.cancel()
        if sessionState == .loading { sessionState = .ready }
    }

    func clockDidChange() {
        guard isVisible else { return }
        let window = makeWindow()
        updateSessionRows(window: window)
        statistics.refresh()
    }

    func loadMoreSessions() {
        guard isVisible, hasMoreSessions, !isLoadingSessions else { return }
        sessionLimit += Self.sessionPageSize
        refreshSessionPage()
    }

    var isLoadingSessions: Bool { sessionState == .loading }

    func retrySessions() {
        guard isVisible else { return }
        refreshSessionPage()
    }

    private func currentScope() -> ReadingHistoryScope {
        context.scope(bookID: bookIdentity)
    }

    private func shelfChanged() {
        let book = context.shelf[bookIdentity]
        let display = book.map(BookDisplay.init)
        if display != shelfBookDisplay {
            shelfBookDisplay = display
            if let book { updateBook(book) }
        }
        updateHistoryScope()
    }

    private func updateHistoryScope() {
        guard isVisible else { return }
        let next = currentScope()
        statistics.start(scope: next)
        guard next != scope || sessionObserver == nil else { return }
        let changed = next != scope
        scope = next
        if changed {
            detailLoad?.cancel()
            summaries = []
            sessionRows = []
            hasMoreSessions = false
        }
        observeSessions()
    }

    private func makeWindow() -> ReadingStatisticsWindow { statistics.window() }

    private func observeSessions() {
        guard let scope else { return }
        sessionObserver?.cancel()
        sessionLoad?.cancel()
        sessionState = .loading
        let changes = historyRepository.changes(in: scope, for: .sessions)
        sessionObserver = Task { [weak self] in
            for await _ in changes {
                guard !Task.isCancelled else { return }
                self?.refreshSessionPage()
            }
        }
    }

    private func refreshSessionPage() {
        guard let scope else { return }
        sessionLoad?.cancel()
        sessionState = .loading
        let limit = sessionLimit
        let repository = historyRepository
        sessionLoad = Task { [weak self] in
            do {
                let page = try await repository.sessions(in: scope, limit: limit)
                guard !Task.isCancelled, let self else { return }
                self.summaries = page.rows
                self.hasMoreSessions = page.hasMore
                self.sessionState = .ready
                self.updateSessionRows(window: self.makeWindow())
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.sessionState = .failed
            }
        }
    }

    private func updateBook(_ value: CalibreBook?) {
        guard let book = value, book.inShelfId == bookIdentity else {
            positionObserver?.cancel()
            positionObserver = nil
            listViewModel = nil
            deviceSections = []
            debugReadingPositions = []
            return
        }

        let previous = listViewModel?.book
        if let listViewModel {
            listViewModel.book = book
        } else {
            listViewModel = makeList(book)
        }

        if positionObserver == nil || previous?.bookPrefId != book.bookPrefId {
            positionObserver?.cancel()
            let repository = positionRepository
            listViewModel?.positions = repository.getPositions(for: book)
            deviceSections = makeDeviceSections()
            #if DEBUG
            debugReadingPositions = repository.debugPositions(forBookId: book.bookPrefId, server: book.library.server)
            #endif
            let positions = repository.observePositions(for: book)
            positionObserver = Task { [weak self] in
                for await values in positions {
                    guard !Task.isCancelled, let self else { return }
                    self.listViewModel?.positions = values
                    self.deviceSections = self.makeDeviceSections()
                }
            }
        } else if previous.map(BookDisplay.init) != BookDisplay(book) {
            deviceSections = makeDeviceSections()
        }
    }

    private struct BookDisplay: Equatable {
        let title: String
        let bookKey: String
        let cached: [String: Bool]

        init(_ book: CalibreBook) {
            title = book.title
            bookKey = book.bookPrefId
            cached = book.formats.mapValues(\.cached)
        }
    }

    /// Opens the reader at the row's position in the workspace the history is shown in.
    func continueReading(_ row: ReadingHistoryPositionRow, targetWorkspaceID: UUID?) {
        continueReading(at: row.position, targetWorkspaceID: targetWorkspaceID)
    }

    func continueReading(at position: BookDeviceReadingPosition, targetWorkspaceID: UUID?) {
        guard let listViewModel else {
            alertItem = AlertItem(id: "Book Not Found", msg: "This book is no longer in the library")
            return
        }
        alertItem = listViewModel.continueReading(at: position, targetWorkspaceID: targetWorkspaceID)
    }

    func showDetail(for position: BookDeviceReadingPosition) {
        detailLoad?.cancel()
        presentDetail(for: position)
    }

    func showDetail(for session: ReadingHistorySessionRow) {
        guard isVisible else { return }
        detailLoad?.cancel()
        let scope = currentScope()
        let repository = historyRepository
        detailLoad = Task { [weak self] in
            do {
                let position = try await repository.endPosition(for: session.id, in: scope)
                guard !Task.isCancelled, let self else { return }
                guard let position, self.currentScope() == scope else {
                    self.alertItem = AlertItem(id: "Session Unavailable", msg: "This reading session is no longer available.")
                    return
                }
                self.presentDetail(for: position)
            } catch {
                guard !Task.isCancelled else { return }
                self?.alertItem = AlertItem(id: "Session Unavailable")
            }
        }
    }

    private func presentDetail(for position: BookDeviceReadingPosition) {
        guard let listViewModel else {
            alertItem = AlertItem(id: "Book Not Found", msg: "This book is no longer in the library")
            return
        }
        displayedDetail = ReadingPositionDetailViewModel(listModel: listViewModel, position: position)
        isDetailActive = true
    }

    func dismissDetail() {
        detailLoad?.cancel()
        isDetailActive = false
    }

    private func percentText(_ progress: Double) -> String {
        percentFormatter.string(from: NSNumber(value: progress / 100)) ?? ""
    }

    private func makeDeviceSections() -> [ReadingHistoryDeviceSection] {
        guard let listViewModel else { return [] }
        return listViewModel.positionsDeviceKeys().map { deviceName in
            let rows = listViewModel.positionsByLatestStyle(deviceId: deviceName).enumerated().map { index, position in
                makePositionRow(position, index: index, listViewModel: listViewModel)
            }
            return ReadingHistoryDeviceSection(
                deviceName: deviceName,
                isThisDevice: deviceName == self.deviceName,
                rows: rows
            )
        }
    }

    private func makePositionRow(
        _ position: BookDeviceReadingPosition,
        index: Int,
        listViewModel: ReadingPositionListViewModel
    ) -> ReadingHistoryPositionRow {
        let chapter = position.lastReadChapter.trimmingCharacters(in: .whitespacesAndNewlines)
        let chapterTitle = chapter.isEmpty ? "Page \(position.lastReadPage)" : chapter
        let isBundle = position.structuralStyle != 0 && position.lastReadBook.isEmpty == false

        return ReadingHistoryPositionRow(
            id: "\(index)|\(position.id)|\(position.readerName)|\(position.epoch)",
            position: position,
            title: isBundle ? position.lastReadBook : chapterTitle,
            detail: isBundle ? "\(chapterTitle) (\(percentText(position.lastChapterProgress)))" : nil,
            percentText: percentText(position.lastProgress),
            relativeTimeText: position.epochByLocaleRelative,
            readerName: position.readerName,
            canContinue: listViewModel.canContinueReading(at: position)
        )
    }

    private func updateSessionRows(window: ReadingStatisticsWindow) {
        sessionDateFormatter.timeZone = window.calendar.timeZone
        sessionRows = summaries.map { session in
            let chapter = session.chapter.trimmingCharacters(in: .whitespacesAndNewlines)
            let durationText: String
            if let duration = session.timing.elapsedSeconds(through: window.now) {
                durationText = duration >= 60 ? durationFormatter.string(from: duration) ?? "<1 min" : "<1 min"
            } else {
                durationText = "Duration unavailable"
            }
            return ReadingHistorySessionRow(
                id: session.id,
                chapter: chapter.isEmpty ? "Page \(session.page)" : chapter,
                durationText: durationText,
                dateText: sessionDateFormatter.string(from: session.timing.startDatetime)
            )
        }
    }

}
