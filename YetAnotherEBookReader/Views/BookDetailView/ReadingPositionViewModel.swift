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
        self.positions = container.readingPositionRepository.getPositions(forBookId: book.bookPrefId)
        
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
        container.readingPositionRepository.removePosition(deviceName: deviceName, forBookId: book.bookPrefId)
        modified = true
    }
}

class ReadingPositionDetailViewModel: ObservableObject, AlertDelegate {
    @Published var container: AppContainer
    @Published var listModel: ReadingPositionListViewModel
    @Published var position: BookDeviceReadingPosition
    
    @Published var selectedFormat = Format.UNKNOWN
    @Published var selectedFormatReader = ReaderType.UNSUPPORTED
    @Published var startPage = ""
    @Published var alertItem: AlertItem?
    
    @Published var presentingReadSheet = false {
        willSet {
            if newValue {
                let binding = Binding<Bool>(
                    get: { [weak self] in self?.presentingReadSheet ?? false },
                    set: { [weak self] in self?.presentingReadSheet = $0 }
                )
                container.presentingStack.append(binding)
            }
        }
        didSet {
            if oldValue {
                _ = container.presentingStack.popLast()
            }
        }
    }

    let percentFormatter = NumberFormatter()
    let dateFormatter = DateFormatter()

    init (container: AppContainer, listModel: ReadingPositionListViewModel, position: BookDeviceReadingPosition) {
        self.container = container
        self.listModel = listModel
        self.position = position

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

    var readingBook: CalibreBook? {
        return container.bookManager.readingBook
    }

    var readerInfo: ReaderInfo? {
        return container.sessionManager.readerInfo
    }
    
    var isSelectedFormatCached: Bool {
        return listModel.book.formats[selectedFormat.rawValue]?.cached == true
    }
    
    func readSelectedFormat() {
        let book = listModel.book
        let format = selectedFormat
        guard let formatInfo = book.formats[format.rawValue],
              formatInfo.cached else {
            alertItem = AlertItem(id: "Selected Format Not Cached", msg: "Please download \(format.rawValue) first")
            return
        }

        guard let bookFileUrl = getSavedUrl(book: book, format: format) else {
            alertItem = AlertItem(id: "Cannot locate book file", msg: "Please re-download \(format.rawValue)")
            return
        }

        container.sessionManager.prepareBookReading(
            url: bookFileUrl,
            format: format,
            readerType: selectedFormatReader,
            position: position
        )

        presentingReadSheet = true
    }

    func updatePosition() {
        container.sessionManager.updateCurrentPosition(alertDelegate: self)

        if let book = container.bookManager.readingBook {
            listModel.book = book
            listModel.positions = container.readingPositionRepository.getPositions(forBookId: book.bookPrefId)
            if let position = container.readingPositionRepository.getPosition(forBookId: book.bookPrefId, deviceName: self.position.id) {
                self.position = position
            }
        }
    }
}

struct BookHistoryItem: Identifiable {
    var id: String { inShelfId }
    let inShelfId: String
    let book: CalibreBook
    let minutesText: String
}

class ReadingPositionHistoryViewModel: ObservableObject {
    @Published var container: AppContainer
    let library: CalibreLibrary?
    let bookId: Int32?
    
    @Published var readingStatistics = [Double]()
    @Published var maxMinutes = 0
    @Published var avgMinutes = 0
    @Published var listViewModel: ReadingPositionListViewModel? = nil
    @Published var localActivities = [BookDeviceReadingPositionHistory]()
    @Published var booksHistoryItems = [BookHistoryItem]()
    @Published var debugReadingPositions = [BookDeviceReadingPosition]()
    
    #if canImport(SwiftUICharts)
    @Published var barChartData: BarChartData?
    #endif
    
    let minutesFormatter = NumberFormatter()
    
    init(container: AppContainer = AppContainer.shared ?? AppContainer(mock: true), library: CalibreLibrary?, bookId: Int32?) {
        self.container = container
        self.library = library
        self.bookId = bookId
        
        minutesFormatter.maximumFractionDigits = 1
        minutesFormatter.minimumFractionDigits = 1
    }
    
    func loadData() {
        let limitDays = 7
        let startDate = Calendar.current.startOfDay(for: Date(timeIntervalSinceNow: Double(-86400 * (limitDays))))

        let readingHistoryList = container.sessionManager.listBookDeviceReadingPositionHistory(library: library, bookId: bookId, startDateAfter: startDate)

        readingStatistics = container.sessionManager.getReadingStatistics(list: readingHistoryList.flatMap({ $0.value }), limitDays: limitDays)
        maxMinutes = Int(readingStatistics.dropLast().max() ?? 0)
        avgMinutes = Int(readingStatistics.dropLast().reduce(0.0,+) / Double(readingStatistics.count - 1))

        #if canImport(SwiftUICharts)
        barChartData = .init(
            dataSets: .init(
                dataPoints: readingStatistics.map({
                    .init(value: $0)
                }),
                legendTitle: "Minutes"
            ),
            metadata: .init(
                title: "Weekly Read Time",
                subtitle: "Minutes"
            )
        )
        #endif

        print("\(#function) readingStatistics=\(readingStatistics)")

        if let library = library, let bookId = bookId {
            localActivities = container.sessionManager.listBookDeviceReadingPositionHistory(library: library, bookId: bookId).first?.value ?? []

            if let book = container.readingPositionRepository.historyBook(for: library, bookId: bookId) {
                listViewModel = ReadingPositionListViewModel(container: container, book: book, positions: container.readingPositionRepository.getPositions(forBookId: book.bookPrefId))
            } else if let book = container.bookManager.readingBook {
                listViewModel = ReadingPositionListViewModel(container: container, book: book, positions: container.readingPositionRepository.getPositions(forBookId: book.bookPrefId))
            }

            let prefix = BookAnnotation.PrefId(library: library, id: bookId)
            self.debugReadingPositions = container.readingPositionRepository.debugPositions(forBookId: prefix)
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
}
