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
                readingBook = modelData?.booksInShelf[readingBookInShelfId] ?? modelData?.getBook(for: readingBookInShelfId)
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
            self.selectedPosition = readerInfo?.position.id ?? modelData?.deviceName ?? ""
        }
    }
    
    @Published var readerInfo: ReaderInfo? = nil
    @Published var selectedPosition = ""
    
    weak var modelData: ModelData?
    private var cancellables = Set<AnyCancellable>()
    
    init(modelData: ModelData? = nil) {
        self.modelData = modelData
        
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
    
    func setup(modelData: ModelData) {
        self.modelData = modelData
    }
    
    func onBookReaderClosed(book: CalibreBook, lastPosition: BookDeviceReadingPosition) async {
        await handleBookReaderClosed(book: book, lastPosition: lastPosition)
    }
    
    func prepareBookReading(book: CalibreBook) -> ReaderInfo {
        guard let modelData = modelData else {
            return ReaderInfo(deviceName: "", url: URL(fileURLWithPath: "/invalid"), missing: true, format: .UNKNOWN, readerType: .UNSUPPORTED, position: .init(readerName: ReaderType.UNSUPPORTED.id))
        }
        
        var candidatePositions = [BookDeviceReadingPosition]()

        //preference: device, latest, selected, any
        if let position = book.readPos.getPosition(modelData.deviceName) {
            candidatePositions.append(position)
        }
        if let position = book.readPos.getDevices().first {
            candidatePositions.append(position)
        }
//        candidatePositions.append(contentsOf: book.readPos.getDevices())
        if let format = modelData.getPreferredFormat(for: book) {
            candidatePositions.append(
                book.readPos.createInitial(
                    deviceName: modelData.deviceName,
                    reader: modelData.getPreferredReader(for: format)
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
        
        return ReaderInfo(deviceName: modelData.deviceName, url: savedURL, missing: urlMissing, format: formatReaderPair.0, readerType: formatReaderPair.1, position: formatReaderPair.2)
    }
    
    func prepareBookReading(url: URL, format: Format, readerType: ReaderType, position: BookDeviceReadingPosition) {
        let readerInfo = ReaderInfo(
            deviceName: modelData?.deviceName ?? "",
            url: url,
            missing: false,
            format: format,
            readerType: readerType,
            position: position
        )
        self.readerInfo = readerInfo
    }
    
    func listBookDeviceReadingPositionHistory(library: CalibreLibrary? = nil, bookId: Int32? = nil, startDateAfter: Date? = nil) -> [String: [BookDeviceReadingPositionHistory]] {
        guard let modelData = modelData, let realm = try? Realm(configuration: modelData.realmConf) else { return [:] }
        
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
            .map { BookDeviceReadingPositionHistory(managedObject: $0) }
        
        if let library = library, let bookId = bookId {
            let bookInShelfId = CalibreBook(id: bookId, library: library).inShelfId
            if let book = modelData.booksInShelf[bookInShelfId] {
                historyList.append(contentsOf: book.readPos.sessions(list: startDateAfter))
            }
        } else {
            modelData.booksInShelf.forEach {
                historyList.append(contentsOf: $0.value.readPos.sessions(list: startDateAfter))
            }
        }
        
        let idMap = modelData.booksInShelf.reduce(into: [String: String]()) { partialResult, entry in
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
        guard let modelData = modelData else { return }
        
        modelData.refreshShelfMetadataV2(with: [book.library.server.id], for: [book.inShelfId], serverReachableChanged: true)

        guard let updatedReadingPosition = book.readPos.getDevices().first else { return }

        if floor(updatedReadingPosition.lastProgress) > lastPosition.lastProgress || updatedReadingPosition.lastProgress < floor(lastPosition.lastProgress),
           let library = modelData.calibreLibraries[book.library.id],
           let goodreadsId = book.identifiers["goodreads"],
           let (dsreaderHelperServer, dsreaderHelperLibrary, goodreadsSync) = modelData.shouldAutoUpdateGoodreads(library: library),
           dsreaderHelperLibrary.autoUpdateGoodreadsProgress {
            
            let connector = DSReaderHelperConnector(calibreServerService: modelData.calibreServerService, server: library.server, dsreaderHelperServer: dsreaderHelperServer, goodreadsSync: goodreadsSync)
            
            // These are currently dataTask based with internal resume()
            _ = connector.updateReadingProgress(goodreads_id: goodreadsId, progress: updatedReadingPosition.lastProgress)

            if goodreadsSync.isEnabled, goodreadsSync.readingProgressColumnName.count > 1 {
                modelData.calibreServerService.updateMetadata(library: library, bookId: book.id, metadata: [
                    [goodreadsSync.readingProgressColumnName, Int(updatedReadingPosition.lastProgress)]
                ])
            }
        }
    }
    
    func updateCurrentPosition(alertDelegate: AlertDelegate?) {
        guard let readingBook = self.readingBook,
              let updatedReadingPosition = readingBook.readPos.getDevices().first,
              let readerInfo = self.readerInfo
        else {
            return
        }

        logger.info("pageNumber:  \(updatedReadingPosition.lastPosition[0])")
        logger.info("pageOffsetX: \(updatedReadingPosition.lastPosition[1])")
        logger.info("pageOffsetY: \(updatedReadingPosition.lastPosition[2])")

        modelData?.refreshShelfMetadataV2(with: [readingBook.library.server.id], for: [readingBook.inShelfId], serverReachableChanged: true)

        if floor(updatedReadingPosition.lastProgress) > readerInfo.position.lastProgress || updatedReadingPosition.lastProgress < floor(readerInfo.position.lastProgress),
           let library = modelData?.calibreLibraries[readingBook.library.id],
           let goodreadsId = readingBook.identifiers["goodreads"],
           let (dsreaderHelperServer, dsreaderHelperLibrary, goodreadsSync) = modelData?.shouldAutoUpdateGoodreads(library: library),
           dsreaderHelperLibrary.autoUpdateGoodreadsProgress {
            let connector = DSReaderHelperConnector(calibreServerService: modelData!.calibreServerService, server: library.server, dsreaderHelperServer: dsreaderHelperServer, goodreadsSync: goodreadsSync)
            connector.updateReadingProgress(goodreads_id: goodreadsId, progress: updatedReadingPosition.lastProgress)

            if goodreadsSync.isEnabled, goodreadsSync.readingProgressColumnName.count > 1 {
                modelData?.calibreServerService.updateMetadata(library: library, bookId: readingBook.id, metadata: [
                    [goodreadsSync.readingProgressColumnName, Int(updatedReadingPosition.lastProgress)]
                ])
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
