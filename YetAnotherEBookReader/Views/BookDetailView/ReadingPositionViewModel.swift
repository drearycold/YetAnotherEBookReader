//
//  ReadingPositionViewModel.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/8/25.
//

import Foundation
import SwiftUI

#if canImport(SwiftUICharts)
import SwiftUICharts
#endif

@MainActor
final class ReadingPositionListViewModel {
    var book: CalibreBook
    var positions: [BookDeviceReadingPosition]

    private let sessionManager: ReadingSessionManager
    private let openReader: (CalibreBook, ReaderInfo, UUID?) -> Void

    init(container: AppContainer, book: CalibreBook, positions: [BookDeviceReadingPosition]) {
        self.book = book
        self.positions = positions
        sessionManager = container.sessionManager
        openReader = { book, info, workspaceID in
            container.openReader(book: book, readerInfo: info, source: .readingPosition, targetWorkspaceID: workspaceID)
        }
    }

    func format(for reader: ReaderType) -> Format {
        sessionManager.formatOfReader(readerName: reader.rawValue) ?? reader.format
    }

    func readers(for format: Format) -> [ReaderType] {
        sessionManager.formatReaderMap[format] ?? []
    }

    func positionsByLatestStyle(deviceId: String) -> [BookDeviceReadingPosition] {
        let devicePositions = positions.filter({ $0.id == deviceId })
        guard let latest = devicePositions.first else { return [] }

        return devicePositions.filter { $0.structuralStyle == latest.structuralStyle && $0.positionTrackingStyle == latest.positionTrackingStyle }
    }

    func positionsDeviceKeys() -> [String] {
        return positions.reduce(into: [String: Double]()) { partialResult, position in
            if (partialResult[position.id] ?? -1.0) < position.epoch {
                partialResult[position.id] = position.epoch
            }
        }.sorted(by: { $0.value > $1.value }).map { $0.key }
    }

    /// The reader and format a position reopens with: the override when given, otherwise the reader
    /// that saved it.
    private func readerAndFormat(
        for position: BookDeviceReadingPosition,
        format: Format?,
        readerType: ReaderType?
    ) -> (ReaderType, Format)? {
        guard let reader = readerType ?? ReaderType(rawValue: position.readerName),
              reader != .UNSUPPORTED else {
            return nil
        }
        return (reader, format ?? self.format(for: reader))
    }

    func canContinueReading(at position: BookDeviceReadingPosition, format: Format? = nil, readerType: ReaderType? = nil) -> Bool {
        guard let (_, format) = readerAndFormat(for: position, format: format, readerType: readerType) else { return false }
        return book.formats[format.rawValue]?.cached == true
    }

    /// Opens a reader at `position` in the workspace `targetWorkspaceID`, or returns why it can't.
    @discardableResult
    func continueReading(
        at position: BookDeviceReadingPosition,
        format: Format? = nil,
        readerType: ReaderType? = nil,
        targetWorkspaceID: UUID?
    ) -> AlertItem? {
        guard let (reader, format) = readerAndFormat(for: position, format: format, readerType: readerType) else {
            return AlertItem(id: "Unsupported Reader", msg: "No reader can open \(position.readerName)")
        }
        guard let formatInfo = book.formats[format.rawValue],
              formatInfo.cached else {
            return AlertItem(id: "Selected Format Not Cached", msg: "Please download \(format.rawValue) first")
        }
        guard let bookFileUrl = getSavedUrl(book: book, format: format),
              FileManager.default.fileExists(atPath: bookFileUrl.path) else {
            return AlertItem(id: "Cannot Locate Book File", msg: book.library.server.isLocal
                ? "Please import the original file again." : "Please download \(format.rawValue) again.")
        }

        let readerInfo = sessionManager.prepareBookReading(
            url: bookFileUrl,
            format: format,
            readerType: reader,
            position: position
        )
        openReader(book, readerInfo, targetWorkspaceID)
        return nil
    }
}

@MainActor
final class ReadingPositionDetailViewModel: ObservableObject, Identifiable {
    let id = UUID()
    let position: BookDeviceReadingPosition
    let selectedFormat: Format
    let availableReaders: [ReaderType]

    @Published var selectedFormatReader: ReaderType
    @Published var alertItem: AlertItem?

    private let listModel: ReadingPositionListViewModel
    let percentFormatter = NumberFormatter()
    let dateFormatter = DateFormatter()

    init(listModel: ReadingPositionListViewModel, position: BookDeviceReadingPosition) {
        self.listModel = listModel
        self.position = position
        let reader = ReaderType(rawValue: position.readerName) ?? .UNSUPPORTED
        selectedFormatReader = reader
        selectedFormat = listModel.format(for: reader)
        availableReaders = listModel.readers(for: selectedFormat)

        percentFormatter.numberStyle = .percent
        percentFormatter.minimumFractionDigits = 1
        dateFormatter.doesRelativeDateFormatting = true
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium
        dateFormatter.timeZone = .current
    }

    var isSelectedFormatCached: Bool {
        listModel.canContinueReading(at: position, format: selectedFormat, readerType: selectedFormatReader)
    }

    func readSelectedFormat(targetWorkspaceID: UUID?) {
        alertItem = listModel.continueReading(
            at: position,
            format: selectedFormat,
            readerType: selectedFormatReader,
            targetWorkspaceID: targetWorkspaceID
        )
    }
}

struct BookHistoryItem: Identifiable {
    var id: String { inShelfId }
    let inShelfId: String
    let book: CalibreBook
    let minutesText: String
}

/// One saved position in a device section of Reading History.
struct ReadingHistoryPositionRow: Identifiable {
    let id: String
    let position: BookDeviceReadingPosition
    /// The chapter, or the book of a bundle (`structuralStyle != 0`).
    let title: String
    /// The chapter, when `title` is the book of a bundle.
    let detail: String?
    let percentText: String
    let relativeTimeText: String
    let readerName: String
    let canContinue: Bool
}

struct ReadingHistoryDeviceSection: Identifiable {
    var id: String { deviceName }
    let deviceName: String
    let isThisDevice: Bool
    let rows: [ReadingHistoryPositionRow]
}

/// One reading session on this device, from its start to its last saved position.
struct ReadingHistorySessionRow: Identifiable {
    let id: ReadingHistorySessionID
    let chapter: String
    let durationText: String
    let dateText: String
}

@MainActor
final class ReadingPositionHistoryViewModel: ObservableObject, Identifiable {
    let id = UUID()
    private let container: AppContainer
    let library: CalibreLibrary?
    let bookId: Int32?

    static let limitDays = 7
    static let sessionPageSize = 30
    static let statisticsTitle = "Today and Previous \(limitDays) Days"

    /// Minutes read per day, oldest first; the last entry is today.
    @Published var readingStatistics = [Double]()
    private(set) var chartDayLabels = [String]()
    @Published var maxMinutes = 0
    @Published var avgMinutes = 0
    private(set) var listViewModel: ReadingPositionListViewModel?
    @Published var booksHistoryItems = [BookHistoryItem]()
    @Published var debugReadingPositions = [BookDeviceReadingPosition]()
    @Published private(set) var deviceSections = [ReadingHistoryDeviceSection]()
    @Published private(set) var sessionRows = [ReadingHistorySessionRow]()
    @Published private(set) var hasMoreSessions = false
    @Published private(set) var isLoadingSessions = false
    @Published var alertItem: AlertItem?
    /// The position whose detail is pushed. Rows are buttons rather than NavigationLinks, so a row's
    /// Continue button is its own tap target instead of part of the link.
    @Published private(set) var isDetailActive = false
    /// The destination stays intact while its pop animation finishes.
    @Published private(set) var displayedDetail: ReadingPositionDetailViewModel?

    #if canImport(SwiftUICharts)
    @Published var barChartData: BarChartData?
    #endif
    
    private let historyRepository: ReadingHistoryRepository
    private let now: () -> Date
    private let calendar: () -> Calendar
    private var isVisible = false
    private var scope: ReadingHistoryScope?
    private var observedStatisticsWindow: ReadingStatisticsWindow?
    private var shelfBookDisplay: BookDisplay?
    private var latestStatistics: ReadingStatistics?
    private var summaries = [ReadingHistorySessionSummary]()
    private var sessionLimit = sessionPageSize

    private var visibilityTasks = [Task<Void, Never>]()
    private var positionObserver: Task<Void, Never>?
    private var statisticsObserver: Task<Void, Never>?
    private var sessionObserver: Task<Void, Never>?
    private var statisticsLoad: Task<Void, Never>?
    private var sessionLoad: Task<Void, Never>?
    private var detailLoad: Task<Void, Never>?

    let minutesFormatter = NumberFormatter()
    private let percentFormatter = NumberFormatter()
    private let durationFormatter = DateComponentsFormatter()
    private let sessionDateFormatter = DateFormatter()

    init(
        container: AppContainer, library: CalibreLibrary?, bookId: Int32?,
        now: @escaping () -> Date = Date.init, calendar: @escaping () -> Calendar = { .current }
    ) {
        self.container = container
        self.library = library
        self.bookId = bookId
        self.historyRepository = container.readingHistoryRepository
        self.now = now
        self.calendar = calendar

        minutesFormatter.maximumFractionDigits = 1
        minutesFormatter.minimumFractionDigits = 1

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
        statisticsObserver?.cancel()
        sessionObserver?.cancel()
        statisticsLoad?.cancel()
        sessionLoad?.cancel()
        detailLoad?.cancel()
    }

    func start() {
        guard !isVisible else { return }
        isVisible = true

        let shelf = container.bookManager.booksInShelfSnapshots(bufferingPolicy: .bufferingNewest(1))
        let libraries = container.libraryManager.librarySnapshots(bufferingPolicy: .bufferingNewest(1))
        visibilityTasks = [
            Task { [weak self] in
                for await _ in shelf {
                    guard !Task.isCancelled else { return }
                    self?.shelfChanged()
                }
            },
            Task { [weak self] in
                for await _ in libraries {
                    guard !Task.isCancelled else { return }
                    self?.updateHistoryScope()
                }
            }
        ]

        if let identity, let library, let bookId {
            let shelfBook = container.bookManager.booksInShelf[identity]
            shelfBookDisplay = shelfBook.map(BookDisplay.init)
            let active = container.sessionManager.activeReaderPresentation?.book
            updateBook(container.bookRepository.getBook(library: library, bookId: bookId)
                       ?? shelfBook ?? (active?.inShelfId == identity ? active : nil))
            let books = container.bookRepository.observeBook(id: identity)
            visibilityTasks.append(Task { [weak self] in
                for await book in books {
                    guard !Task.isCancelled, let self else { return }
                    let fallback = self.container.bookManager.booksInShelf[identity]
                        ?? self.container.sessionManager.activeReaderPresentation?.book
                    self.updateBook(book ?? fallback)
                }
            })
        }
        updateHistoryScope()
    }

    func stop() {
        isVisible = false
        visibilityTasks.forEach { $0.cancel() }
        visibilityTasks.removeAll()
        positionObserver?.cancel()
        positionObserver = nil
        statisticsObserver?.cancel()
        statisticsObserver = nil
        sessionObserver?.cancel()
        sessionObserver = nil
        statisticsLoad?.cancel()
        sessionLoad?.cancel()
        detailLoad?.cancel()
        isLoadingSessions = false
    }

    func clockDidChange() {
        guard isVisible else { return }
        let window = makeWindow()
        updateSessionRows(window: window)
        refreshStatistics(window: window)
    }

    func loadMoreSessions() {
        guard isVisible, hasMoreSessions, !isLoadingSessions else { return }
        sessionLimit += Self.sessionPageSize
        refreshSessionPage()
    }

    private var identity: String? {
        guard let library, let bookId else { return nil }
        return CalibreBook.identity(library: library, bookId: bookId)
    }

    private func currentScope() -> ReadingHistoryScope {
        ReadingHistoryScope(shelf: container.bookManager.booksInShelf,
                            libraries: container.calibreLibraries, bookID: identity)
    }

    private func shelfChanged() {
        if let identity {
            let book = container.bookManager.booksInShelf[identity]
            let display = book.map(BookDisplay.init)
            if display != shelfBookDisplay {
                shelfBookDisplay = display
                if let book { updateBook(book) }
            }
        } else if booksHistoryItems.contains(where: { item in
            container.bookManager.booksInShelf[item.id]?.title != item.book.title
        }) {
            updateBookTotals()
        }
        updateHistoryScope()
    }

    private func updateHistoryScope() {
        guard isVisible else { return }
        let next = currentScope()
        guard next != scope || statisticsObserver == nil else { return }
        let changed = next != scope
        scope = next
        let window = makeWindow()
        if changed {
            detailLoad?.cancel()
            applyStatistics(ReadingStatistics.Accumulator(window: window).result, window: window)
            summaries = []
            sessionRows = []
            hasMoreSessions = false
        }
        observeStatistics(window: window)
        if isBookMode { observeSessions() }
    }

    private func makeWindow() -> ReadingStatisticsWindow {
        ReadingStatisticsWindow(now: now(), calendar: calendar(), previousDays: Self.limitDays)
    }

    private func observeStatistics(window: ReadingStatisticsWindow) {
        guard let scope else { return }
        statisticsObserver?.cancel()
        statisticsLoad?.cancel()
        observedStatisticsWindow = window
        let changes = historyRepository.changes(in: scope, for: .statistics(since: window.sessionStartRange.lowerBound))
        statisticsObserver = Task { [weak self] in
            for await _ in changes {
                guard !Task.isCancelled, let self else { return }
                self.refreshStatistics(window: self.makeWindow())
            }
        }
    }

    private func refreshStatistics(window: ReadingStatisticsWindow) {
        guard let scope else { return }
        if observedStatisticsWindow?.calendar != window.calendar
            || observedStatisticsWindow?.sessionStartRange.lowerBound != window.sessionStartRange.lowerBound {
            observeStatistics(window: window)
            return
        }
        statisticsLoad?.cancel()
        let repository = historyRepository
        statisticsLoad = Task { [weak self] in
            do {
                let statistics = try await repository.statistics(in: scope, window: window)
                guard !Task.isCancelled, let self else { return }
                self.applyStatistics(statistics, window: window)
            } catch {
                guard !Task.isCancelled else { return }
                self?.alertItem = AlertItem(id: "Reading Statistics Unavailable")
            }
        }
    }

    private func observeSessions() {
        guard let scope else { return }
        sessionObserver?.cancel()
        sessionLoad?.cancel()
        isLoadingSessions = true
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
        isLoadingSessions = true
        let limit = sessionLimit
        let repository = historyRepository
        sessionLoad = Task { [weak self] in
            do {
                let page = try await repository.sessions(in: scope, limit: limit)
                guard !Task.isCancelled, let self else { return }
                self.summaries = page.rows
                self.hasMoreSessions = page.hasMore
                self.isLoadingSessions = false
                self.updateSessionRows(window: self.makeWindow())
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.isLoadingSessions = false
                self.alertItem = AlertItem(id: "Local Sessions Unavailable")
            }
        }
    }

    private func updateBook(_ value: CalibreBook?) {
        guard let book = value, book.inShelfId == identity else {
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
            listViewModel = ReadingPositionListViewModel(container: container, book: book, positions: [])
        }

        if positionObserver == nil || previous?.bookPrefId != book.bookPrefId {
            positionObserver?.cancel()
            let repository = container.readingPositionRepository
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

    /// A single book's history; otherwise statistics across every book on the shelf.
    var isBookMode: Bool {
        library != nil && bookId != nil
    }

    var navigationTitle: String {
        isBookMode ? "Reading History" : "Reading Statistics"
    }

    var hasRecentReading: Bool {
        readingStatistics.contains { $0 > 0 }
    }

    var todayMinutes: Int {
        Int(readingStatistics.last ?? 0)
    }

    /// Avg and Max cover the \(limitDays) days before today, so they're labelled apart from Today.
    var summaryText: String {
        "Today \(todayMinutes) min · Previous \(Self.limitDays) days: avg \(avgMinutes), max \(maxMinutes) min/day"
    }

    private func applyStatistics(_ statistics: ReadingStatistics, window: ReadingStatisticsWindow) {
        readingStatistics = statistics.minutesByDay
        chartDayLabels = window.dayLabels
        maxMinutes = Int(statistics.previousDayMaximum)
        avgMinutes = Int(statistics.previousDayAverage)

        #if canImport(SwiftUICharts)
        barChartData = makeBarChartData()
        #endif

        if !isBookMode {
            latestStatistics = statistics
            updateBookTotals()
        }
    }

    private func updateBookTotals() {
        guard let latestStatistics else { return }
        let shelf = container.bookManager.booksInShelf
        booksHistoryItems = latestStatistics.rankedBookIDs.compactMap { id in
            guard let book = shelf[id], let minutes = latestStatistics.minutesByBook[id],
                  let text = minutesFormatter.string(from: NSNumber(value: minutes)) else { return nil }
            return BookHistoryItem(inShelfId: id, book: book, minutesText: text)
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
        isDetailActive = false
    }

    func history(for book: CalibreBook) -> ReadingPositionHistoryViewModel {
        ReadingPositionHistoryViewModel(container: container, library: book.library, bookId: book.id)
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
                isThisDevice: deviceName == container.deviceName,
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

    #if canImport(SwiftUICharts)
    private func makeBarChartData() -> BarChartData {
        let colour = ColourStyle(colour: .accentColor)
        return BarChartData(
            dataSets: BarDataSet(
                dataPoints: readingStatistics.enumerated().map { index, minutes in
                    BarChartDataPoint(
                        value: minutes,
                        xAxisLabel: chartDayLabels[index],
                        description: "\(Int(minutes)) min",
                        colour: colour
                    )
                },
                legendTitle: "Minutes"
            ),
            metadata: ChartMetadata(title: Self.statisticsTitle, subtitle: "Minutes"),
            barStyle: BarStyle(barWidth: 0.6, colour: colour),
            chartStyle: BarChartStyle(
                xAxisLabelFont: .caption2,
                xAxisLabelColour: .secondary,
                yAxisGridStyle: GridStyle(numberOfLines: 3, lineColour: Color(.gray).opacity(0.2), dash: [4]),
                yAxisLabelFont: .caption2,
                yAxisLabelColour: .secondary,
                yAxisNumberOfLabels: 3,
                baseline: .zero
            )
        )
    }
    #endif
}
