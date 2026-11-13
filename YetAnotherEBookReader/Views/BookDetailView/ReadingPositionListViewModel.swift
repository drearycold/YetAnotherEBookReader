import Foundation

@MainActor
final class ReadingPositionListViewModel {
    var book: CalibreBook
    var positions: [BookDeviceReadingPosition]
    let bookRepository: BookRepositoryProtocol

    private let sessionManager: ReadingSessionManager
    private let openReader: (CalibreBook, ReaderInfo, UUID?) -> Void
    private let localFileAccessNotice: (CalibreBook) -> AlertItem?

    init(container: AppContainer, book: CalibreBook, positions: [BookDeviceReadingPosition]) {
        self.book = book
        self.positions = positions
        bookRepository = container.bookRepository
        sessionManager = container.sessionManager
        localFileAccessNotice = { container.libraryManager.localFileAccessNotice(for: $0) }
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
        if let latest = bookRepository.getBook(id: book.inShelfId), latest.inShelfId == book.inShelfId {
            book = latest
        }
        if let notice = localFileAccessNotice(book) { return notice }
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

