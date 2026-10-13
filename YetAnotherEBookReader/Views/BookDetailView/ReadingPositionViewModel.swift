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

class ReadingPositionListViewModel: ObservableObject {
    @Published var container: AppContainer
    @Published var book: CalibreBook

    @Published var positions: [BookDeviceReadingPosition]

    let percentFormatter = NumberFormatter()
    let dateFormatter = DateFormatter()

    var modified = false

    init(container: AppContainer, book: CalibreBook, positions: [BookDeviceReadingPosition]) {
        self.container = container
        self.book = book
        self.positions = container.readingPositionRepository.getPositions(for: book)

        percentFormatter.numberStyle = .percent
        percentFormatter.minimumFractionDigits = 1
        dateFormatter.doesRelativeDateFormatting = true
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium
        dateFormatter.timeZone = .current
    }

    func positionsByLatestStyle() -> [BookDeviceReadingPosition] {
        guard let latest = positions.first else { return [] }

        return positions.filter { $0.structuralStyle == latest.structuralStyle && $0.positionTrackingStyle == latest.positionTrackingStyle }
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

    func removePosition(_ deviceName: String) {
        container.readingPositionRepository.removePosition(deviceName: deviceName, for: book)
        modified = true
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
        let format = format ?? container.sessionManager.formatOfReader(readerName: reader.rawValue) ?? reader.format
        return (reader, format)
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
        guard let bookFileUrl = getSavedUrl(book: book, format: format) else {
            return AlertItem(id: "Cannot locate book file", msg: "Please re-download \(format.rawValue)")
        }

        let readerInfo = container.sessionManager.prepareBookReading(
            url: bookFileUrl,
            format: format,
            readerType: reader,
            position: position
        )
        container.openReader(
            book: book,
            readerInfo: readerInfo,
            source: .readingPosition,
            targetWorkspaceID: targetWorkspaceID
        )
        return nil
    }
}

class ReadingPositionDetailViewModel: ObservableObject, AlertDelegate {
    @Published var container: AppContainer
    @Published var listModel: ReadingPositionListViewModel
    @Published var position: BookDeviceReadingPosition
    var targetWorkspaceID: UUID?

    @Published var selectedFormat = Format.UNKNOWN
    @Published var selectedFormatReader = ReaderType.UNSUPPORTED
    @Published var startPage = ""
    @Published var alertItem: AlertItem?

    let percentFormatter = NumberFormatter()
    let dateFormatter = DateFormatter()

    init(
        container: AppContainer,
        listModel: ReadingPositionListViewModel,
        position: BookDeviceReadingPosition,
        targetWorkspaceID: UUID? = nil
    ) {
        self.container = container
        self.listModel = listModel
        self.position = position
        self.targetWorkspaceID = targetWorkspaceID

        if let format = container.sessionManager.formatOfReader(readerName: position.readerName) {
            self.selectedFormat = format
        }
        if let reader = ReaderType(rawValue: position.readerName) {
            self.selectedFormatReader = reader
        }

        startPage = position.lastReadPage.description

        percentFormatter.numberStyle = .percent
        percentFormatter.minimumFractionDigits = 1

        dateFormatter.doesRelativeDateFormatting = true
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium
        dateFormatter.timeZone = .current
    }

    func alert(alertItem: AlertItem) {
        self.alertItem = alertItem
    }

    var availableReaders: [ReaderType] {
        return container.sessionManager.formatReaderMap[selectedFormat] ?? []
    }

    var isSelectedFormatCached: Bool {
        return listModel.book.formats[selectedFormat.rawValue]?.cached == true
    }

    func readSelectedFormat() {
        alertItem = listModel.continueReading(
            at: position,
            format: selectedFormat,
            readerType: selectedFormatReader,
            targetWorkspaceID: targetWorkspaceID
        )
    }

    func updatePosition() {
        container.sessionManager.updateCurrentPosition(alertDelegate: self)

        let book = listModel.book
        listModel.positions = container.readingPositionRepository.getPositions(for: book)
        if let position = container.readingPositionRepository.getPosition(for: book, policy: .latestForDevice(self.position.id)) {
            self.position = position
        }
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
    let id: String
    let chapter: String
    let durationText: String
    let dateText: String
    let endPosition: BookDeviceReadingPosition
}

class ReadingPositionHistoryViewModel: ObservableObject {
    @Published var container: AppContainer
    let library: CalibreLibrary?
    let bookId: Int32?

    static let limitDays = 7

    /// Minutes read per day, oldest first; the last entry is today.
    @Published var readingStatistics = [Double]()
    @Published var maxMinutes = 0
    @Published var avgMinutes = 0
    @Published var listViewModel: ReadingPositionListViewModel? = nil
    @Published var localActivities = [BookDeviceReadingPositionHistory]()
    @Published var booksHistoryItems = [BookHistoryItem]()
    @Published var debugReadingPositions = [BookDeviceReadingPosition]()
    @Published private(set) var deviceSections = [ReadingHistoryDeviceSection]()
    @Published private(set) var sessionRows = [ReadingHistorySessionRow]()
    @Published var alertItem: AlertItem?
    /// The position whose detail is pushed. Rows are buttons rather than NavigationLinks, so a row's
    /// Continue button is its own tap target instead of part of the link.
    @Published var detailPosition: BookDeviceReadingPosition? = nil {
        didSet {
            if let detailPosition {
                displayedDetailPosition = detailPosition
            }
        }
    }
    /// The pushed detail's position. Kept after it is dismissed, so the page doesn't go blank while
    /// it slides out.
    @Published private(set) var displayedDetailPosition: BookDeviceReadingPosition? = nil

    #if canImport(SwiftUICharts)
    @Published var barChartData: BarChartData?
    #endif
    
    private var refreshTasks = [Task<Void, Never>]()

    let minutesFormatter = NumberFormatter()
    private let percentFormatter = NumberFormatter()
    private let durationFormatter = DateComponentsFormatter()
    private let sessionDateFormatter = DateFormatter()

    init(container: AppContainer = AppContainer.shared ?? AppContainer(mock: true), library: CalibreLibrary?, bookId: Int32?) {
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
    @MainActor
    func observeChanges() {
        guard refreshTasks.isEmpty else { return }
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

    func loadData() {
        let limitDays = Self.limitDays
        let startDate = Calendar.current.startOfDay(for: Date(timeIntervalSinceNow: Double(-86400 * (limitDays))))

        let readingHistoryList = container.sessionManager.listBookDeviceReadingPositionHistory(library: library, bookId: bookId, startDateAfter: startDate)

        readingStatistics = container.sessionManager.getReadingStatistics(list: readingHistoryList.flatMap({ $0.value }), limitDays: limitDays)
        maxMinutes = Int(readingStatistics.dropLast().max() ?? 0)
        avgMinutes = readingStatistics.count > 1
            ? Int(readingStatistics.dropLast().reduce(0.0,+) / Double(readingStatistics.count - 1))
            : 0

        #if canImport(SwiftUICharts)
        barChartData = makeBarChartData()
        #endif

        if let library = library, let bookId = bookId {
            localActivities = container.sessionManager.listBookDeviceReadingPositionHistory(library: library, bookId: bookId).first?.value ?? []

            if let book = container.bookRepository.getBook(library: library, bookId: bookId) {
                listViewModel = ReadingPositionListViewModel(container: container, book: book, positions: container.readingPositionRepository.getPositions(for: book))
            } else if let book = container.sessionManager.activeReaderPresentation?.book,
                      book.library.id == library.id, book.id == bookId {
                // Only the book this history is about: Continue Reading opens listViewModel's book.
                listViewModel = ReadingPositionListViewModel(container: container, book: book, positions: container.readingPositionRepository.getPositions(for: book))
            } else {
                listViewModel = nil
            }

            deviceSections = makeDeviceSections()
            sessionRows = makeSessionRows()

            let prefix = BookAnnotation.PrefId(library: library, id: bookId)
            self.debugReadingPositions = container.readingPositionRepository.debugPositions(
                forBookId: prefix,
                server: library.server
            )
        } else {
            let computedHistory = readingHistoryList.reduce(into: [String: Double](), { partialResult, entry in
                let inShelfId = entry.key
                entry.value.forEach {
                    guard let endPosition = $0.endPosition else { return }
                    let duration = endPosition.epoch - $0.startDatetime.timeIntervalSince1970
                    if duration > 0 {
                        partialResult[inShelfId] = (partialResult[inShelfId] ?? 0.0) + (duration / 60.0)
                    }
                }
            })

            self.booksHistoryItems = computedHistory.sorted(by: { $0.value > $1.value }).compactMap { entry -> BookHistoryItem? in
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
        detailPosition = position
    }

    func dismissDetail() {
        detailPosition = nil
    }

    func detailViewModel(
        for position: BookDeviceReadingPosition,
        listViewModel: ReadingPositionListViewModel,
        targetWorkspaceID: UUID?
    ) -> ReadingPositionDetailViewModel {
        ReadingPositionDetailViewModel(
            container: container,
            listModel: listViewModel,
            position: position,
            targetWorkspaceID: targetWorkspaceID
        )
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

    private func makeSessionRows() -> [ReadingHistorySessionRow] {
        localActivities.enumerated().compactMap { index, session in
            guard let endPosition = session.endPosition else { return nil }
            let chapter = endPosition.lastReadChapter.trimmingCharacters(in: .whitespacesAndNewlines)
            let duration = endPosition.epoch - session.startDatetime.timeIntervalSince1970
            let durationText = duration >= 60
                ? durationFormatter.string(from: duration) ?? "<1 min"
                : "<1 min"
            return ReadingHistorySessionRow(
                id: "\(index)|\(session.startDatetime.timeIntervalSince1970)|\(endPosition.epoch)",
                chapter: chapter.isEmpty ? "Page \(endPosition.lastReadPage)" : chapter,
                durationText: durationText,
                dateText: sessionDateFormatter.string(from: session.startDatetime),
                endPosition: endPosition
            )
        }
    }

    /// Day names ("Tue", "Thu") for the statistics buckets, oldest first; the last is "Today".
    func chartDayLabels() -> [String] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let symbols = calendar.shortWeekdaySymbols
        return readingStatistics.indices.map { index in
            let daysAgo = readingStatistics.count - 1 - index
            guard daysAgo > 0,
                  let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) else {
                return "Today"
            }
            return symbols[calendar.component(.weekday, from: day) - 1]
        }
    }

    #if canImport(SwiftUICharts)
    private func makeBarChartData() -> BarChartData {
        let labels = chartDayLabels()
        let colour = ColourStyle(colour: .accentColor)
        return BarChartData(
            dataSets: BarDataSet(
                dataPoints: readingStatistics.enumerated().map { index, minutes in
                    BarChartDataPoint(
                        value: minutes,
                        xAxisLabel: labels[index],
                        description: "\(Int(minutes)) min",
                        colour: colour
                    )
                },
                legendTitle: "Minutes"
            ),
            metadata: ChartMetadata(title: "Last \(Self.limitDays) Days", subtitle: "Minutes"),
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
