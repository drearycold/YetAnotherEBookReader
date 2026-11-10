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
    let endPosition: BookDeviceReadingPosition
}

@MainActor
final class ReadingPositionHistoryViewModel: ObservableObject, Identifiable {
    let id = UUID()
    private let container: AppContainer
    let library: CalibreLibrary?
    let bookId: Int32?

    static let limitDays = 7
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
    @Published var alertItem: AlertItem?
    /// The position whose detail is pushed. Rows are buttons rather than NavigationLinks, so a row's
    /// Continue button is its own tap target instead of part of the link.
    @Published private(set) var isDetailActive = false
    /// The destination stays intact while its pop animation finishes.
    @Published private(set) var displayedDetail: ReadingPositionDetailViewModel?

    #if canImport(SwiftUICharts)
    @Published var barChartData: BarChartData?
    #endif
    
    private var refreshTasks = [Task<Void, Never>]()

    let minutesFormatter = NumberFormatter()
    private let percentFormatter = NumberFormatter()
    private let durationFormatter = DateComponentsFormatter()
    private let sessionDateFormatter = DateFormatter()

    init(container: AppContainer, library: CalibreLibrary?, bookId: Int32?) {
        self.container = container
        self.library = library
        self.bookId = bookId

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
        refreshTasks.forEach { $0.cancel() }
    }
    
    /// Reloads when a reader above this page records a position (it is hidden or deactivated), a
    /// reader closes, or books update (shelf refresh after a reader closes, a finished download).
    /// None of these make the page appear again, so `onAppear` alone leaves it stale.
    func start() {
        guard refreshTasks.isEmpty else { return }
        loadData()
        let readerInfos = container.sessionManager.readerInfoSnapshots()
        let presentations = container.sessionManager.readerPresentationSnapshots()
        let updates = container.calibreUpdates()
        refreshTasks = [
            Task { @MainActor [weak self] in
                for await _ in readerInfos.dropFirst() {
                    guard let self, !Task.isCancelled else { return }
                    self.loadData()
                }
            },
            Task { @MainActor [weak self] in
                for await _ in presentations.dropFirst() {
                    guard let self, !Task.isCancelled else { return }
                    self.loadData()
                }
            },
            Task { @MainActor [weak self] in
                for await _ in updates {
                    guard let self, !Task.isCancelled else { return }
                    self.loadData()
                }
            },
        ]
    }
    
    func stop() {
        refreshTasks.forEach { $0.cancel() }
        refreshTasks.removeAll()
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

    func loadData(now: Date = Date(), calendar: Calendar = .current) {
        let window = ReadingStatisticsWindow(now: now, calendar: calendar, previousDays: Self.limitDays)
        let history = container.sessionManager.listBookDeviceReadingPositionHistory(
            library: library, bookId: bookId, startingIn: window.sessionStartRange
        )
        let statistics = ReadingStatistics(window: window, historyByBook: history)
        readingStatistics = statistics.minutesByDay
        chartDayLabels = window.dayLabels
        maxMinutes = Int(statistics.previousDayMaximum)
        avgMinutes = Int(statistics.previousDayAverage)

        #if canImport(SwiftUICharts)
        barChartData = makeBarChartData()
        #endif

        if let library = library, let bookId = bookId {
            let identity = CalibreBook.identity(library: library, bookId: bookId)
            let sessions = container.sessionManager.listBookDeviceReadingPositionHistory(library: library, bookId: bookId)
            let activeBook = container.sessionManager.activeReaderPresentation?.book
            let book = container.bookRepository.getBook(library: library, bookId: bookId)
                ?? (activeBook?.inShelfId == identity ? activeBook : nil)

            if let book, book.inShelfId == identity {
                let positions = container.readingPositionRepository.getPositions(for: book)
                if let listViewModel {
                    listViewModel.book = book
                    listViewModel.positions = positions
                } else {
                    listViewModel = ReadingPositionListViewModel(container: container, book: book, positions: positions)
                }
            } else {
                listViewModel = nil
            }

            deviceSections = makeDeviceSections()
            sessionDateFormatter.timeZone = calendar.timeZone
            sessionRows = makeSessionRows(sessions[identity] ?? [], now: now)

            #if DEBUG
            let prefix = BookAnnotation.PrefId(library: library, id: bookId)
            self.debugReadingPositions = container.readingPositionRepository.debugPositions(
                forBookId: prefix,
                server: library.server
            )
            #endif
        } else {
            let rankedBooks = statistics.minutesByBook.sorted { first, second in
                first.value == second.value ? first.key < second.key : first.value > second.value
            }
            booksHistoryItems = rankedBooks.compactMap { entry -> BookHistoryItem? in
                guard let book = container.bookManager.booksInShelf[entry.key],
                      let minutesText = minutesFormatter.string(from: NSNumber(value: entry.value)) else {
                    return nil
                }
                return BookHistoryItem(inShelfId: entry.key, book: book, minutesText: minutesText)
            }
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

    private func makeSessionRows(_ sessions: [BookDeviceReadingPositionHistory], now: Date) -> [ReadingHistorySessionRow] {
        sessions.compactMap { session in
            guard let endPosition = session.endPosition,
                  endPosition.epoch.isFinite,
                  session.startDatetime.timeIntervalSince1970.isFinite else { return nil }
            let chapter = endPosition.lastReadChapter.trimmingCharacters(in: .whitespacesAndNewlines)
            let durationText: String
            if let duration = session.elapsedSeconds(through: now) {
                durationText = duration >= 60 ? durationFormatter.string(from: duration) ?? "<1 min" : "<1 min"
            } else {
                durationText = "Duration unavailable"
            }
            return ReadingHistorySessionRow(
                id: session.id,
                chapter: chapter.isEmpty ? "Page \(endPosition.lastReadPage)" : chapter,
                durationText: durationText,
                dateText: sessionDateFormatter.string(from: session.startDatetime),
                endPosition: endPosition
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
