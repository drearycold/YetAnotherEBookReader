//
//  ReadingSessionManager.swift
//  YetAnotherEBookReader
//
//  Created by Gemini on 2026/4/6.
//

import Foundation
import UIKit
import OSLog

enum ReaderPresentationSource: String, Equatable, Codable {
    case shelf
    case bookDetail
    case importResult
    case readingPosition
    case preview
    case compatibility
}

struct ReaderPresentation: Identifiable, Equatable {
    let id: UUID
    let book: CalibreBook
    let readerInfo: ReaderInfo
    let source: ReaderPresentationSource

    init(
        id: UUID = UUID(),
        book: CalibreBook,
        readerInfo: ReaderInfo,
        source: ReaderPresentationSource
    ) {
        self.id = id
        self.book = book
        self.readerInfo = readerInfo
        self.source = source
    }

    var inShelfId: String { book.inShelfId }
    var title: String { book.title }

    func withReaderInfo(_ readerInfo: ReaderInfo) -> ReaderPresentation {
        ReaderPresentation(id: id, book: book, readerInfo: readerInfo, source: source)
    }

    func matches(book: CalibreBook, readerInfo: ReaderInfo) -> Bool {
        self.book.inShelfId == book.inShelfId &&
            self.readerInfo.format == readerInfo.format &&
            self.readerInfo.readerType == readerInfo.readerType
    }

    static func == (lhs: ReaderPresentation, rhs: ReaderPresentation) -> Bool {
        lhs.id == rhs.id
    }
}

struct ReaderPresentationSnapshot: Codable, Equatable {
    let id: UUID
    let bookInShelfId: String
    let format: Format
    let readerType: ReaderType
    let source: ReaderPresentationSource
    let isActive: Bool
    let order: Int
}

protocol ReaderPresentationPersistenceStore {
    func loadReaderPresentationSnapshots() -> [ReaderPresentationSnapshot]
    func saveReaderPresentationSnapshots(_ snapshots: [ReaderPresentationSnapshot])
}

final class UserDefaultsReaderPresentationPersistenceStore: ReaderPresentationPersistenceStore {
    private let userDefaults: UserDefaults
    private let key: String

    init(
        userDefaults: UserDefaults = .standard,
        key: String = Constants.KEY_DEFAULTS_READER_PRESENTATION_SNAPSHOTS
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    func loadReaderPresentationSnapshots() -> [ReaderPresentationSnapshot] {
        guard let data = userDefaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([ReaderPresentationSnapshot].self, from: data)) ?? []
    }

    func saveReaderPresentationSnapshots(_ snapshots: [ReaderPresentationSnapshot]) {
        if snapshots.isEmpty {
            userDefaults.removeObject(forKey: key)
            return
        }
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        userDefaults.set(data, forKey: key)
    }
}

final class InMemoryReaderPresentationPersistenceStore: ReaderPresentationPersistenceStore {
    private(set) var snapshots: [ReaderPresentationSnapshot]

    init(snapshots: [ReaderPresentationSnapshot] = []) {
        self.snapshots = snapshots
    }

    func loadReaderPresentationSnapshots() -> [ReaderPresentationSnapshot] {
        snapshots
    }

    func saveReaderPresentationSnapshots(_ snapshots: [ReaderPresentationSnapshot]) {
        self.snapshots = snapshots
    }
}

class ReadingSessionManager {
    private let stateChangeBroadcaster = ManagerAsyncBroadcaster<Void>()
    private let readingBookInShelfIdBroadcaster = ManagerAsyncBroadcaster<String?>()
    private let readingBookBroadcaster = ManagerAsyncBroadcaster<CalibreBook?>()
    private let readerInfoBroadcaster = ManagerAsyncBroadcaster<ReaderInfo?>()
    private let presentingReaderBroadcaster = ManagerAsyncBroadcaster<Bool>()
    private let readerPresentationsBroadcaster = ManagerAsyncBroadcaster<[ReaderPresentation]>()
    private let activeReaderPresentationBroadcaster = ManagerAsyncBroadcaster<ReaderPresentation?>()
    private let selectedPositionBroadcaster = ManagerAsyncBroadcaster<String>()

    var defaultFormat = Format.PDF {
        didSet {
            publishStateChange()
        }
    }
    var formatReaderMap = [Format: [ReaderType]]()
    var formatList = [Format]()
    
    private let logger = Logger(subsystem: "YetAnotherEBookReader", category: "ReadingSessionManager")
    private var legacyPresentingEBookReaderFromShelf = false
    private var latestPositionsByPresentationID = [ReaderPresentation.ID: BookDeviceReadingPosition]()
    private let persistenceStore: ReaderPresentationPersistenceStore
    private var suppressPersistence = false
    private var hasAttemptedPersistedRestore = false

    var readerPresentations: [ReaderPresentation] = [] {
        didSet {
            if let activeReaderPresentationID,
               readerPresentations.contains(where: { $0.id == activeReaderPresentationID }) == false {
                self.activeReaderPresentationID = readerPresentations.last?.id
            } else if activeReaderPresentationID == nil {
                self.activeReaderPresentationID = readerPresentations.last?.id
            }
            readerPresentationsBroadcaster.send(readerPresentations)
            activeReaderPresentationBroadcaster.send(activeReaderPresentation)
            presentingReaderBroadcaster.send(presentingEBookReaderFromShelf)
            persistReaderPresentationSnapshots()
            publishStateChange()
        }
    }

    var activeReaderPresentationID: ReaderPresentation.ID? {
        didSet {
            activeReaderPresentationBroadcaster.send(activeReaderPresentation)
            presentingReaderBroadcaster.send(presentingEBookReaderFromShelf)
            persistReaderPresentationSnapshots()
            publishStateChange()
        }
    }

    var activeReaderPresentation: ReaderPresentation? {
        guard let activeReaderPresentationID else { return nil }
        return readerPresentations.first { $0.id == activeReaderPresentationID }
    }

    func readerPresentation(id: ReaderPresentation.ID) -> ReaderPresentation? {
        readerPresentations.first { $0.id == id }
    }

    func readerPresentationForMount(id: ReaderPresentation.ID) -> ReaderPresentation? {
        guard let presentation = readerPresentation(id: id) else { return nil }
        return presentation.withReaderInfo(readerInfoForMounting(presentation: presentation))
    }

    func readerInfoForMounting(presentation: ReaderPresentation) -> ReaderInfo {
        let latestPosition = latestPositionForMounting(presentation: presentation) ?? presentation.readerInfo.position
        return ReaderInfo(
            deviceName: presentation.readerInfo.deviceName,
            url: presentation.readerInfo.url,
            missing: presentation.readerInfo.missing,
            format: presentation.readerInfo.format,
            readerType: presentation.readerInfo.readerType,
            position: latestPosition
        )
    }

    var presentingEBookReaderFromShelf: Bool {
        get { legacyPresentingEBookReaderFromShelf || activeReaderPresentation != nil }
        set {
            legacyPresentingEBookReaderFromShelf = newValue
            if newValue,
               activeReaderPresentation == nil,
               let legacyReadingBook,
               let legacyReaderInfo {
                _ = openReader(book: legacyReadingBook, readerInfo: legacyReaderInfo, source: .compatibility)
            } else if newValue == false {
                readerPresentations.removeAll()
            }
            presentingReaderBroadcaster.send(presentingEBookReaderFromShelf)
            publishStateChange()
        }
    }
    
    var readingBookInShelfId: String? = nil {
        didSet {
            readingBookInShelfIdBroadcaster.send(readingBookInShelfId)
            publishStateChange()
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
    private var legacyReadingBook: CalibreBook? = nil

    @available(*, deprecated)
    var readingBook: CalibreBook? {
        get { activeReaderPresentation?.book ?? legacyReadingBook }
        set {
            legacyReadingBook = newValue
            if let newValue {
                let preparedInfo = prepareBookReading(book: newValue)
                legacyReaderInfo = preparedInfo
            } else {
                legacyReaderInfo = nil
            }
            readingBookBroadcaster.send(readingBook)
            publishStateChange()
            guard let readingBook = readingBook else {
                self.selectedPosition = ""
                return
            }

            self.selectedPosition = readerInfo?.position.id ?? container?.deviceName ?? ""
        }
    }

    private var legacyReaderInfo: ReaderInfo? = nil

    var readerInfo: ReaderInfo? {
        get { activeReaderPresentation?.readerInfo ?? legacyReaderInfo }
        set {
            legacyReaderInfo = newValue
            readerInfoBroadcaster.send(readerInfo)
            publishStateChange()
        }
    }
    var selectedPosition = "" {
        didSet {
            selectedPositionBroadcaster.send(selectedPosition)
            publishStateChange()
        }
    }
    
    weak var container: AppContainerProtocol?

    init(
        container: AppContainerProtocol? = nil,
        persistenceStore: ReaderPresentationPersistenceStore = UserDefaultsReaderPresentationPersistenceStore()
    ) {
        self.container = container
        self.persistenceStore = persistenceStore
        
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

    func stateChanges() -> AsyncStream<Void> {
        stateChangeBroadcaster.stream()
    }

    func readingBookInShelfIdSnapshots() -> AsyncStream<String?> {
        readingBookInShelfIdBroadcaster.stream(initialValue: readingBookInShelfId)
    }

    func readingBookSnapshots() -> AsyncStream<CalibreBook?> {
        readingBookBroadcaster.stream(initialValue: readingBook)
    }

    func readerInfoSnapshots() -> AsyncStream<ReaderInfo?> {
        readerInfoBroadcaster.stream(initialValue: readerInfo)
    }

    func presentingReaderSnapshots() -> AsyncStream<Bool> {
        presentingReaderBroadcaster.stream(initialValue: presentingEBookReaderFromShelf)
    }

    func readerPresentationSnapshots() -> AsyncStream<[ReaderPresentation]> {
        readerPresentationsBroadcaster.stream(initialValue: readerPresentations)
    }

    func activeReaderPresentationSnapshots() -> AsyncStream<ReaderPresentation?> {
        activeReaderPresentationBroadcaster.stream(initialValue: activeReaderPresentation)
    }

    func selectedPositionSnapshots() -> AsyncStream<String> {
        selectedPositionBroadcaster.stream(initialValue: selectedPosition)
    }

    private func publishStateChange() {
        stateChangeBroadcaster.send(())
    }
    
    func onBookReaderClosed(book: CalibreBook, lastPosition: BookDeviceReadingPosition) async {
        await handleBookReaderClosed(book: book, lastPosition: lastPosition)
    }

    @discardableResult
    func restorePersistedReaderPresentationsIfNeeded() -> [ReaderPresentation] {
        guard hasAttemptedPersistedRestore == false else { return [] }
        hasAttemptedPersistedRestore = true

        guard readerPresentations.isEmpty else {
            persistReaderPresentationSnapshots()
            return []
        }

        let snapshots = persistenceStore.loadReaderPresentationSnapshots()
            .sorted { $0.order < $1.order }
        guard snapshots.isEmpty == false else { return [] }

        let restoredPresentations = snapshots.compactMap { restorePresentation(from: $0) }
        let activeSnapshotID = snapshots.first { $0.isActive }?.id
        let restoredActiveID: ReaderPresentation.ID? = restoredPresentations.contains(where: { $0.id == activeSnapshotID })
            ? activeSnapshotID
            : restoredPresentations.last?.id

        suppressPersistence = true
        readerPresentations = restoredPresentations
        activeReaderPresentationID = restoredActiveID
        suppressPersistence = false

        if let activePresentation = activeReaderPresentation {
            legacyReadingBook = activePresentation.book
            legacyReaderInfo = activePresentation.readerInfo
            selectedPosition = activePresentation.readerInfo.position.id
        }
        legacyPresentingEBookReaderFromShelf = restoredPresentations.isEmpty == false
        readingBookBroadcaster.send(self.readingBook)
        readerInfoBroadcaster.send(self.readerInfo)
        persistReaderPresentationSnapshots()

        return restoredPresentations
    }

    @discardableResult
    func openReader(
        book: CalibreBook,
        readerInfo: ReaderInfo? = nil,
        source: ReaderPresentationSource,
        reuseExisting: Bool = true
    ) -> ReaderPresentation {
        let resolvedReaderInfo = readerInfo ?? prepareBookReading(book: book)
        if reuseExisting,
           let existingPresentation = readerPresentations.first(where: { $0.matches(book: book, readerInfo: resolvedReaderInfo) }) {
            legacyReadingBook = existingPresentation.book
            legacyReaderInfo = existingPresentation.readerInfo
            legacyPresentingEBookReaderFromShelf = true
            activeReaderPresentationID = existingPresentation.id
            readingBookBroadcaster.send(self.readingBook)
            readerInfoBroadcaster.send(self.readerInfo)
            selectedPosition = existingPresentation.readerInfo.position.id
            return existingPresentation
        }

        let presentation = ReaderPresentation(
            book: book,
            readerInfo: resolvedReaderInfo,
            source: source
        )
        legacyReadingBook = book
        legacyReaderInfo = resolvedReaderInfo
        legacyPresentingEBookReaderFromShelf = true
        readerPresentations.append(presentation)
        activeReaderPresentationID = presentation.id
        readingBookBroadcaster.send(self.readingBook)
        readerInfoBroadcaster.send(self.readerInfo)
        selectedPosition = resolvedReaderInfo.position.id
        return presentation
    }

    func closeReader(id: ReaderPresentation.ID) {
        let wasActive = activeReaderPresentationID == id
        readerPresentations.removeAll { $0.id == id }
        latestPositionsByPresentationID.removeValue(forKey: id)
        if wasActive {
            activeReaderPresentationID = readerPresentations.last?.id
        }
        if readerPresentations.isEmpty {
            legacyPresentingEBookReaderFromShelf = false
        }
        readingBookBroadcaster.send(self.readingBook)
        readerInfoBroadcaster.send(self.readerInfo)
    }

    func activateReader(id: ReaderPresentation.ID) {
        guard readerPresentations.contains(where: { $0.id == id }) else { return }
        legacyPresentingEBookReaderFromShelf = true
        activeReaderPresentationID = id
        readingBookBroadcaster.send(self.readingBook)
        readerInfoBroadcaster.send(self.readerInfo)
    }

    func recordReaderPresentationPosition(id: ReaderPresentation.ID?, position: BookDeviceReadingPosition) {
        guard let id,
              let presentation = readerPresentation(id: id),
              position.readerName == presentation.readerInfo.readerType.rawValue else {
            return
        }
        latestPositionsByPresentationID[id] = position
        if activeReaderPresentationID == id {
            legacyReaderInfo = readerInfoForMounting(presentation: presentation)
            readerInfoBroadcaster.send(self.readerInfo)
        }
    }

    private func latestPositionForMounting(presentation: ReaderPresentation) -> BookDeviceReadingPosition? {
        if let recordedPosition = latestPositionsByPresentationID[presentation.id],
           recordedPosition.readerName == presentation.readerInfo.readerType.rawValue {
            return recordedPosition
        }

        return container?.readingPositionRepository
            .getPositions(for: presentation.book)
            .first { position in
                position.id == presentation.readerInfo.deviceName &&
                    position.readerName == presentation.readerInfo.readerType.rawValue
            }
    }

    private func restorePresentation(from snapshot: ReaderPresentationSnapshot) -> ReaderPresentation? {
        guard let container,
              snapshot.readerType != .UNSUPPORTED,
              snapshot.readerType.format == snapshot.format,
              let book = container.bookRepository.getBook(id: snapshot.bookInShelfId),
              book.formats[snapshot.format.rawValue] != nil,
              let savedURL = getSavedUrl(book: book, format: snapshot.format),
              FileManager.default.fileExists(atPath: savedURL.path)
        else { return nil }

        let positions = container.readingPositionRepository.getPositions(for: book)
            .filter { position in
                position.id == container.deviceName &&
                    position.readerName == snapshot.readerType.rawValue
            }
        let position = ReadingPositionSelectionPolicy.latest.select(from: positions)
            ?? container.readingPositionRepository.createInitial(
                deviceName: container.deviceName,
                reader: snapshot.readerType
            )
        let readerInfo = ReaderInfo(
            deviceName: container.deviceName,
            url: savedURL,
            missing: false,
            format: snapshot.format,
            readerType: snapshot.readerType,
            position: position
        )

        return ReaderPresentation(
            id: snapshot.id,
            book: book,
            readerInfo: readerInfo,
            source: snapshot.source
        )
    }

    private func persistReaderPresentationSnapshots() {
        guard suppressPersistence == false else { return }
        persistenceStore.saveReaderPresentationSnapshots(currentReaderPresentationSnapshots())
    }

    private func currentReaderPresentationSnapshots() -> [ReaderPresentationSnapshot] {
        readerPresentations.enumerated().map { index, presentation in
            ReaderPresentationSnapshot(
                id: presentation.id,
                bookInShelfId: presentation.book.inShelfId,
                format: presentation.readerInfo.format,
                readerType: presentation.readerInfo.readerType,
                source: presentation.source,
                isActive: presentation.id == activeReaderPresentationID,
                order: index
            )
        }
    }
    
    func prepareBookReading(book: CalibreBook) -> ReaderInfo {
        let positions = container?.readingPositionRepository.getPositions(for: book)
        return prepareBookReading(book: book, withLoadedPositions: positions)
    }
    
    func prepareBookReading(book: CalibreBook, withLoadedPositions positions: [BookDeviceReadingPosition]?) -> ReaderInfo {
        guard let container = container else {
            return ReaderInfo(deviceName: "", url: URL(fileURLWithPath: "/invalid"), missing: true, format: .UNKNOWN, readerType: .UNSUPPORTED, position: .init(readerName: ReaderType.UNSUPPORTED.id))
        }
        
        let loadedPositions = positions ?? container.readingPositionRepository.getPositions(for: book)
        
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
    
    @discardableResult
    func prepareBookReading(url: URL, format: Format, readerType: ReaderType, position: BookDeviceReadingPosition) -> ReaderInfo {
        let readerInfo = ReaderInfo(
            deviceName: container?.deviceName ?? "",
            url: url,
            missing: false,
            format: format,
            readerType: readerType,
            position: position
        )
        self.readerInfo = readerInfo
        return readerInfo
    }
    
    func listBookDeviceReadingPositionHistory(library: CalibreLibrary? = nil, bookId: Int32? = nil, startDateAfter: Date? = nil) -> [String: [BookDeviceReadingPositionHistory]] {
        guard let container = container else { return [:] }

        var historyList = container.readingPositionRepository.positionHistory(
            library: library,
            bookId: bookId,
            startDateAfter: startDateAfter
        )
        
        if let library = library, let bookId = bookId {
            let bookInShelfId = CalibreBook(id: bookId, library: library).inShelfId
            if let book = container.bookManager.booksInShelf[bookInShelfId] {
                historyList.append(contentsOf: container.readingPositionRepository.sessions(for: book, list: startDateAfter))
            }
        } else {
            container.bookManager.booksInShelf.forEach {
                historyList.append(contentsOf: container.readingPositionRepository.sessions(for: $0.value, list: startDateAfter))
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

        guard let updatedReadingPosition = container.readingPositionRepository.getPositions(for: book).first else { return }

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
              let updatedReadingPosition = container?.readingPositionRepository.getPositions(for: readingBook).first,
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
