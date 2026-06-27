//
//  ReadingSessionManager.swift
//  YetAnotherEBookReader
//
//  Created by Gemini on 2026/4/6.
//

import Foundation
import Combine
import SwiftUI
import RealmSwift
import OSLog

class ReadingSessionManager: ObservableObject {
    @Published var defaultFormat = Format.PDF
    var formatReaderMap = [Format: [ReaderType]]()
    var formatList = [Format]()
    
    private let logger = Logger(subsystem: "YetAnotherEBookReader", category: "ReadingSessionManager")
    @Published var presentingEBookReaderFromShelf = false
    
    @Published var readingBookInShelfId: String? = nil {
        didSet {
            guard let readingBookInShelfId = readingBookInShelfId else {
                readingBook = nil
                return
            }
            if readingBook?.inShelfId != readingBookInShelfId {
                readingBook = container?.bookManager.booksInShelf[readingBookInShelfId] ?? container?.bookManager.getBook(for: readingBookInShelfId)
            }
        }
    }
    
    @available(*, deprecated)
    @Published var readingBook: CalibreBook? = nil {
        didSet {
            guard let readingBook = readingBook else {
                self.selectedPosition = ""
                return
            }
            
            readerInfo = prepareBookReading(book: readingBook)
            self.selectedPosition = readerInfo?.position.id ?? container?.deviceName ?? ""
        }
    }
    
    @Published var readerInfo: ReaderInfo? = nil
    @Published var selectedPosition = ""
    
    weak var container: AppContainerProtocol?
    private var cancellables = Set<AnyCancellable>()

    init(container: AppContainerProtocol? = nil) {
        self.container = container
        
        switch UIDevice.current.userInterfaceIdiom {
            case .phone:
                defaultFormat = Format.EPUB
            case .pad:
                defaultFormat = Format.PDF
            default:
                defaultFormat = Format.EPUB
        }
        
        formatReaderMap[Format.EPUB] = [ReaderType.YabrEPUB, ReaderType.ReadiumEPUB]
        formatReaderMap[Format.PDF] = [ReaderType.YabrPDF, ReaderType.ReadiumPDF]
        formatReaderMap[Format.CBZ] = [ReaderType.ReadiumCBZ]
    }
    
    func setup(container: AppContainerProtocol) {
        self.container = container
    }
    
    func onBookReaderClosed(book: CalibreBook, lastPosition: BookDeviceReadingPosition) async {
        await handleBookReaderClosed(book: book, lastPosition: lastPosition)
    }
    
    func prepareBookReading(book: CalibreBook) -> ReaderInfo {
        let positions = container?.readingPositionRepository.getPositions(forBookId: book.bookPrefId)
        return prepareBookReading(book: book, withLoadedPositions: positions)
    }
    
    func prepareBookReading(book: CalibreBook, withLoadedPositions positions: [BookDeviceReadingPosition]?) -> ReaderInfo {
        guard let container = container else {
            return ReaderInfo(deviceName: "", url: URL(fileURLWithPath: "/invalid"), missing: true, format: .UNKNOWN, readerType: .UNSUPPORTED, position: .init(readerName: ReaderType.UNSUPPORTED.id))
        }
        
        let loadedPositions = positions ?? container.readingPositionRepository.getPositions(forBookId: book.bookPrefId)
        
        var candidatePositions = [BookDeviceReadingPosition]()

        // preference: device
        if let position = ReadingPositionSelectionPolicy.latestForDevice(container.deviceName).select(from: loadedPositions) {
            candidatePositions.append(position)
        }
        // preference: latest
        if let position = ReadingPositionSelectionPolicy.latest.select(from: loadedPositions) {
            candidatePositions.append(position)
        }
        // fallback: preferred format initial position
        if let format = self.getPreferredFormat(for: book) {
            candidatePositions.append(
                container.readingPositionRepository.createInitial(
                    deviceName: container.deviceName,
                    reader: self.getPreferredReader(for: format)
                )
            )
        }
        
        let formatReaderPairArray: [(Format, ReaderType, BookDeviceReadingPosition)] = candidatePositions.compactMap { position in
            guard let reader = ReaderType(rawValue: position.readerName), reader != .UNSUPPORTED else { return nil }
            let format = reader.format
            
            return (format, reader, position)
        }
        
        let formatReaderPair = formatReaderPairArray.first ?? (Format.UNKNOWN, ReaderType.UNSUPPORTED, BookDeviceReadingPosition.init(readerName: ReaderType.UNSUPPORTED.id))
        let savedURL = getSavedUrl(book: book, format: formatReaderPair.0) ?? URL(fileURLWithPath: "/invalid")
        let urlMissing = !FileManager.default.fileExists(atPath: savedURL.path)
        
        return ReaderInfo(deviceName: container.deviceName, url: savedURL, missing: urlMissing, format: formatReaderPair.0, readerType: formatReaderPair.1, position: formatReaderPair.2)
    }
    
    func prepareBookReading(url: URL, format: Format, readerType: ReaderType, position: BookDeviceReadingPosition) {
        let readerInfo = ReaderInfo(
            deviceName: container?.deviceName ?? "",
            url: url,
            missing: false,
            format: format,
            readerType: readerType,
            position: position
        )
        self.readerInfo = readerInfo
    }
    
    func listBookDeviceReadingPositionHistory(library: CalibreLibrary? = nil, bookId: Int32? = nil, startDateAfter: Date? = nil) -> [String: [BookDeviceReadingPositionHistory]] {
        guard let container = container,
              let realmConf = container.realmConf,
              let realm = try? Realm(configuration: realmConf) else { return [:] }
        
        var pred: NSPredicate?
        if let library = library, let bookId = bookId {
            pred = NSPredicate(format: "bookId = %@", "\(library.key) - \(bookId)")
            if let startDateAfter = startDateAfter {
                pred = NSPredicate(format: "bookId = %@ AND startDatetime >= %@", "\(library.key) - \(bookId)", startDateAfter as NSDate)
            }
        } else {
            if let startDateAfter = startDateAfter {
                pred = NSPredicate(
                    format: "startDatetime >= %@",
                    startDateAfter as NSDate
                )
            }
        }
        
        var results = realm.objects(BookDeviceReadingPositionHistoryRealm.self);
        if let predNotNil = pred {
            results = results.filter(predNotNil)
        }
        results = results.sorted(by: [SortDescriptor(keyPath: "startDatetime", ascending: false)])
        
        var historyList: [BookDeviceReadingPositionHistory] = results.filter { $0.endPosition != nil }
            .map { $0.toDomain() }
        
        if let library = library, let bookId = bookId {
            let bookInShelfId = CalibreBook(id: bookId, library: library).inShelfId
            if let book = container.bookManager.booksInShelf[bookInShelfId] {
                historyList.append(contentsOf: container.readingPositionRepository.sessions(forBookId: book.bookPrefId, list: startDateAfter))
            }
        } else {
            container.bookManager.booksInShelf.forEach {
                historyList.append(contentsOf: container.readingPositionRepository.sessions(forBookId: $0.value.bookPrefId, list: startDateAfter))
            }
        }
        
        let idMap = container.bookManager.booksInShelf.reduce(into: [String: String]()) { partialResult, entry in
            partialResult["\(entry.value.library.key) - \(entry.value.id)"] = entry.value.inShelfId
        }
        
        return historyList.sorted(by:{ $0.startDatetime > $1.startDatetime }).removingDuplicates().reduce(into: [:]) { partialResult, history in
            guard let inShelfId = idMap[history.bookId] else { return }
            
            if partialResult[inShelfId] == nil {
                partialResult[inShelfId] = [history]
            } else {
                partialResult[inShelfId]?.append(history)
            }
        }
    }
    
    func handleBookReaderClosed(book: CalibreBook, lastPosition: BookDeviceReadingPosition) async {
        guard let container = container else { return }
        
        container.bookManager.refreshShelfMetadataV2(with: [book.library.server.id], for: [book.inShelfId], serverReachableChanged: true)

        guard let updatedReadingPosition = container.readingPositionRepository.getPositions(forBookId: book.bookPrefId).first else { return }

        if floor(updatedReadingPosition.lastProgress) > lastPosition.lastProgress || updatedReadingPosition.lastProgress < floor(lastPosition.lastProgress),
           let library = container.libraryManager.calibreLibraries[book.library.id],
           let goodreadsId = book.identifiers["goodreads"],
           let (dsreaderHelperServer, dsreaderHelperLibrary, goodreadsSync) = container.bookManager.shouldAutoUpdateGoodreads(library: library),
           dsreaderHelperLibrary.autoUpdateGoodreadsProgress {
            
            let connector = DSReaderHelperConnector(calibreServerService: container.calibreServerService, server: library.server, dsreaderHelperServer: dsreaderHelperServer, goodreadsSync: goodreadsSync)
            
            do {
                try await connector.updateReadingProgress(goodreads_id: goodreadsId, progress: updatedReadingPosition.lastProgress)
            } catch {
                logger.error("Failed to update Goodreads reading progress for book \(book.title): \(error.localizedDescription)")
            }

            if goodreadsSync.isEnabled, goodreadsSync.readingProgressColumnName.count > 1 {
                do {
                    try await container.calibreServerService.updateMetadata(library: library, bookId: book.id, metadata: [
                        [goodreadsSync.readingProgressColumnName, Int(updatedReadingPosition.lastProgress)]
                    ])
                } catch {
                    logger.error("Failed to update custom column metadata for book \(book.title): \(error.localizedDescription)")
                }
            }
        }
    }
    
    func updateCurrentPosition(alertDelegate: AlertDelegate?) {
        guard let readingBook = self.readingBook,
              let updatedReadingPosition = container?.readingPositionRepository.getPositions(forBookId: readingBook.bookPrefId).first,
              let readerInfo = self.readerInfo
        else {
            return
        }

        logger.info("pageNumber:  \(updatedReadingPosition.lastPosition[0])")
        logger.info("pageOffsetX: \(updatedReadingPosition.lastPosition[1])")
        logger.info("pageOffsetY: \(updatedReadingPosition.lastPosition[2])")

        container?.bookManager.refreshShelfMetadataV2(with: [readingBook.library.server.id], for: [readingBook.inShelfId], serverReachableChanged: true)

        if floor(updatedReadingPosition.lastProgress) > readerInfo.position.lastProgress || updatedReadingPosition.lastProgress < floor(readerInfo.position.lastProgress),
           let library = container?.libraryManager.calibreLibraries[readingBook.library.id],
           let goodreadsId = readingBook.identifiers["goodreads"],
           let (dsreaderHelperServer, dsreaderHelperLibrary, goodreadsSync) = container?.bookManager.shouldAutoUpdateGoodreads(library: library),
           dsreaderHelperLibrary.autoUpdateGoodreadsProgress {
            let connector = DSReaderHelperConnector(calibreServerService: container!.calibreServerService, server: library.server, dsreaderHelperServer: dsreaderHelperServer, goodreadsSync: goodreadsSync)
            Task {
                do {
                    try await connector.updateReadingProgress(goodreads_id: goodreadsId, progress: updatedReadingPosition.lastProgress)
                } catch {
                    logger.error("Failed to update Goodreads reading progress for book \(readingBook.title): \(error.localizedDescription)")
                }

                if goodreadsSync.isEnabled, goodreadsSync.readingProgressColumnName.count > 1 {
                    do {
                        try await container?.calibreServerService.updateMetadata(library: library, bookId: readingBook.id, metadata: [
                            [goodreadsSync.readingProgressColumnName, Int(updatedReadingPosition.lastProgress)]
                        ])
                    } catch {
                        logger.error("Failed to update custom column metadata for book \(readingBook.title): \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    func defaultReaderForDefaultFormat(book: CalibreBook) -> (Format, ReaderType) {
        if book.formats.contains(where: { $0.key == defaultFormat.rawValue }) {
            return (defaultFormat, formatReaderMap[defaultFormat]!.first!)
        } else {
            return book.formats.keys.compactMap {
                Format(rawValue: $0)
            }
            .reversed()
            .reduce((Format.UNKNOWN, ReaderType.UNSUPPORTED)) {
                ($1, formatReaderMap[$1]!.first!)
            }
        }
    }

    func formatOfReader(readerName: String) -> Format? {
        let formats = formatReaderMap.filter {
            $0.value.contains(where: { reader in reader.rawValue == readerName } )
        }
        return formats.first?.key
    }

    func getPreferredFormat() -> Format {
        return Format(rawValue: UserDefaults.standard.string(forKey: Constants.KEY_DEFAULTS_PREFERRED_FORMAT) ?? "" ) ?? defaultFormat
    }

    func getPreferredFormat(for book: CalibreBook) -> Format? {
        let selectedFormats = book.formats.filter { $0.value.selected == true }
        if selectedFormats.count == 1,
           let firstFormatRaw = selectedFormats.first?.key,
           let firstFormat = Format(rawValue: firstFormatRaw) {
            return firstFormat
        }
        if book.formats[getPreferredFormat().rawValue] != nil {
            return getPreferredFormat()
        } else if let format = book.formats.compactMap({ Format(rawValue: $0.key) }).first {
            return format
        }
        return nil
    }

    func updatePreferredFormat(for format: Format) {
        UserDefaults.standard.setValue(format.rawValue, forKey: Constants.KEY_DEFAULTS_PREFERRED_FORMAT)
    }

    // user preferred -> default -> unsupported
    func getPreferredReader(for format: Format) -> ReaderType {
        return ReaderType(
            rawValue: UserDefaults.standard.string(forKey: "\(Constants.KEY_DEFAULTS_PREFERRED_READER_PREFIX)\(format.rawValue)") ?? ""
        ) ?? formatReaderMap[format]?.first ?? ReaderType.UNSUPPORTED
    }

    func updatePreferredReader(for format: Format, with reader: ReaderType) {
        UserDefaults.standard.setValue(reader.rawValue, forKey: "\(Constants.KEY_DEFAULTS_PREFERRED_READER_PREFIX)\(format.rawValue)")
    }

    func getReadingStatistics(list: [BookDeviceReadingPositionHistory], limitDays: Int) -> [Double] {
        return BookDeviceReadingPositionHistory.getReadingStatistics(list: list, limitDays: limitDays)
    }
}
