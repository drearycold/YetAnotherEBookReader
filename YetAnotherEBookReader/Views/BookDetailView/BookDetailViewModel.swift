//
//  BookDetailViewModel.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/8/26.
//

import Foundation
import SwiftUI

@MainActor
class BookDetailViewModel: ObservableObject {
    @Published private(set) var previewViewModel: BookPreviewViewModel?
    enum PageState: Equatable { case loading, content, unavailable }
    enum RefreshState: Equatable {
        case idle, refreshing, synced, local, unavailable, failed(String)
    }
    @Published private(set) var pageState: PageState = .loading
    @Published private(set) var refreshState: RefreshState = .idle
    @Published private(set) var calibreBook: CalibreBook?
    @Published private(set) var hasReadableFile = false
    @Published private(set) var formatStates: [BookFormatState] = []
    @Published var clearingFormat: Format?
    @Published private(set) var readingProgressSummary: ReadingProgressSummary?
    @Published private(set) var hasHistory = false
    private var helperConfiguration: CalibreDSReaderHelperConfiguration?
    private var positionObserverTask: Task<Void, Never>?
    private var observationID = UUID()
    private var refreshID: UUID?
    private let bookRepository: BookRepositoryProtocol
    private let readingPositionRepository: ReadingPositionRepositoryProtocol
    private let refreshMetadata: (CalibreBooksMetadataRequest) async -> [Int32: BookMetadataRefreshResult]
    private let fileExists: (URL) -> Bool
    private var bookObserverTask: Task<Void, Never>?
    
    @Published var alertItem: AlertItem?
    
    
    @Published private(set) var activityViewModel: ActivityListViewModel?
    private var activityDismissTask: Task<Void, Never>?

    /// Drives the push of Reading History. It is pushed, not a sheet, so a reader opened from it
    /// shows above it in the workspace overlay.
    @Published var isReadingPositionHistoryActive = false
    @Published private(set) var readingHistoryViewModel: ReadingPositionHistoryViewModel?
    
    private weak var container: AppContainer?
    var targetWorkspaceID: UUID?
    private var loadedBookId: String?
    /// Set when Reading History is pushed, so the detail's next appearance (the pop back) doesn't
    /// reload; any other appearance, such as a tab switch back, refreshes as before.
    private var isReturningFromHistory = false
    private var fetchTask: Task<Void, Never>?
    private var activeDownloadsTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private struct PendingReading {
        let bookID: String
        let format: Format
        let downloadID: UUID
        let workspaceID: UUID?
    }
    @Published private var pendingReading: PendingReading?
    @Published var activeDownloads: [URL: BookFormatDownload] = [:]
    var deviceName: String {
        return container?.deviceName ?? ""
    }

    init(container: AppContainer, targetWorkspaceID: UUID? = nil,
         bookRepository: BookRepositoryProtocol? = nil,
         readingPositionRepository: ReadingPositionRepositoryProtocol? = nil,
         refreshMetadata: ((CalibreBooksMetadataRequest) async -> [Int32: BookMetadataRefreshResult])? = nil,
         fileExists: @escaping (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) {
        self.container = container
        self.targetWorkspaceID = targetWorkspaceID
        self.bookRepository = bookRepository ?? container.bookRepository
        self.readingPositionRepository = readingPositionRepository ?? container.readingPositionRepository
        self.refreshMetadata = refreshMetadata ?? { [bookManager = container.bookManager] request in
            await bookManager.getBooksMetadata(request: request)
        }
        self.fileExists = fileExists
    }

    deinit {
        fetchTask?.cancel()
        activeDownloadsTask?.cancel()
        bookObserverTask?.cancel()
        positionObserverTask?.cancel()
        dismissTask?.cancel()
        activityDismissTask?.cancel()
    }

    /// Returning from History reattaches local observations without another network refresh.
    func onAppear(bookId: String, targetWorkspaceID: UUID?) {
        self.targetWorkspaceID = targetWorkspaceID
        let fromHistory = isReturningFromHistory && loadedBookId == bookId
        isReturningFromHistory = false
        guard setup(bookId: bookId), let book = calibreBook else { return }
        if !fromHistory { fetchMetadata(book: book) }
    }

    func onDisappear() {
        previewViewModel?.cancel()
        pendingReading = nil
        cancelRefresh()
        stopObserving()
    }

    private func stopObserving() {
        observationID = UUID()
        bookObserverTask?.cancel()
        bookObserverTask = nil
        positionObserverTask?.cancel()
        positionObserverTask = nil
        activeDownloadsTask?.cancel()
        activeDownloadsTask = nil
        dismissTask?.cancel()
        dismissTask = nil
    }

    @discardableResult
    func setup(bookId: String) -> Bool {
        let sameBook = loadedBookId == bookId
        stopObserving()
        cancelRefresh()
        loadedBookId = bookId
        pendingReading = nil
        if !sameBook {
            clearContent()
            refreshState = .idle
            alertItem = nil
            isReadingPositionHistoryActive = false
            readingHistoryViewModel = nil
            isReturningFromHistory = false
            closePreview()
            clearingFormat = nil
        }
        guard let container else {
            clearContent()
            return false
        }
        let id = observationID
        if let book = bookRepository.getBook(id: bookId), book.inShelfId == bookId {
            applyBookUpdate(book, container: container)
            observePositions(for: book, observationID: id)
        } else {
            clearContent()
        }

        // Register streams before scheduling consumers, so immediate changes aren't missed.
        let bookUpdates = bookRepository.observeBook(id: bookId)
        bookObserverTask = Task { [weak self, weak container] in
            for await book in bookUpdates {
                guard !Task.isCancelled, let self, let container,
                      self.observationID == id, self.loadedBookId == bookId else { return }
                guard let book else {
                    self.cancelRefresh()
                    self.clearContent()
                    continue
                }
                guard book.inShelfId == bookId else { continue }
                self.applyBookUpdate(book, container: container)
                if self.positionObserverTask == nil { self.observePositions(for: book, observationID: id) }
            }
        }
        let downloadSnapshots = container.downloadManager.downloadSnapshots()
        activeDownloads = container.downloadManager.activeDownloads
        activeDownloadsTask = Task { [weak self] in
            for await snapshot in downloadSnapshots {
                guard !Task.isCancelled, self?.observationID == id else { return }
                self?.applyDownloadSnapshot(snapshot)
            }
        }
        let dismissEvents = container.dismissAllEvents()
        dismissTask = Task { [weak self] in
            for await _ in dismissEvents {
                guard !Task.isCancelled, self?.observationID == id else { return }
                self?.pendingReading = nil
                self?.closePreview()
            }
        }
        return calibreBook != nil
    }

    private func clearContent() {
        calibreBook = nil
        pageState = .unavailable
        closeActivity()
        refreshState = .idle
        helperConfiguration = nil
        readingProgressSummary = nil
        hasHistory = false
        hasReadableFile = false
        formatStates = []
        clearingFormat = nil
        closePreview()
        pendingReading = nil
        positionObserverTask?.cancel()
        positionObserverTask = nil
    }

    private func observePositions(for book: CalibreBook, observationID: UUID) {
        let updates = readingPositionRepository.observePositions(for: book)
        positionObserverTask = Task { [weak self] in
            for await positions in updates {
                guard !Task.isCancelled, let self, self.observationID == observationID,
                      let currentBook = self.calibreBook, currentBook.inShelfId == book.inShelfId else { return }
                self.applyPositions(positions, book: currentBook)
            }
        }
    }

    func cancelRefresh() {
        refreshID = nil
        fetchTask?.cancel()
        fetchTask = nil
        if refreshState == .refreshing { refreshState = .idle }
    }

    func fetchMetadata(book: CalibreBook) {
        guard loadedBookId == book.inShelfId, calibreBook != nil else { return }
        cancelRefresh()
        if book.library.server.isLocal {
            refreshState = .local
            return
        }
        let requestID = UUID()
        refreshID = requestID
        refreshState = .refreshing
        let refresh = refreshMetadata
        fetchTask = Task { [weak self] in
            let results = await refresh(.init(library: book.library, books: [book.id], getAnnotations: true))
            guard !Task.isCancelled, let self, self.refreshID == requestID,
                  self.loadedBookId == book.inShelfId else { return }
            self.refreshID = nil
            self.fetchTask = nil
            guard let updatedBook = self.bookRepository.getBook(id: book.inShelfId),
                  updatedBook.inShelfId == book.inShelfId,
                  let container = self.container else {
                self.clearContent()
                self.refreshState = .idle
                return
            }
            self.applyBookUpdate(updatedBook, container: container)
            switch results[book.id] ?? .failed("The server did not return this book's details.") {
            case .updated: self.refreshState = .synced
            case .unavailable: self.refreshState = .unavailable
            case .failed(let message): self.refreshState = .failed(message)
            case .cancelled: self.refreshState = .idle
            }
            self.updateFormatStates()
        }
    }

    func refresh(book: CalibreBook) {
        guard loadedBookId == book.inShelfId else { return }
        if let coverURL = book.coverURL { container?.coverCache.removeCover(for: coverURL) }
        fetchMetadata(book: book)
    }

    func readBook(book: CalibreBook) {
        guard let container, pendingReading == nil,
              loadedBookId == nil || loadedBookId == book.inShelfId else { return }
        alertItem = nil

        if let info = cachedReaderInfo(for: book) {
            if !book.inShelf { container.bookManager.addToShelf(book: book, formats: [info.format]) }
            openReader(for: book, info: info, workspaceID: targetWorkspaceID)
            return
        }
        guard !book.library.server.isLocal else {
            alertItem = AlertItem(id: "Cannot locate book file", msg: "Please import the original file again.")
            return
        }
        guard let format = preferredReadableFormat(for: book) else {
            alertItem = AlertItem(id: "Error Download Book", msg: "Sorry, there's no supported book format")
            return
        }
        if activeDownload(for: book, format: format) == nil {
            guard startCaching(book: book, format: format) else { return }
        }
        guard let download = activeDownload(for: book, format: format) else { return }
        pendingReading = PendingReading(bookID: book.inShelfId, format: format,
            downloadID: download.id, workspaceID: targetWorkspaceID)
        if download.isPaused && !download.isPausing {
            container.downloadManager.resumeDownload(book, format: format)
        }
    }

    func downloadOnly(book: CalibreBook) {
        pendingReading = nil
        guard !book.library.server.isLocal else {
            alertItem = AlertItem(id: "Cannot locate book file", msg: "Please import the original file again.")
            return
        }
        guard let format = preferredReadableFormat(for: book) else {
            alertItem = AlertItem(id: "Error Download Book", msg: "Sorry, there's no supported book format")
            return
        }
        if let download = activeDownload(for: book, format: format) {
            if download.isPaused && !download.isPausing { resumeDownload(book: book, format: format) }
        } else { _ = startCaching(book: book, format: format) }
    }

    func cacheFormat(book: CalibreBook, format: Format) {
        pendingReading = nil
        _ = startCaching(book: book, format: format)
    }

    private func startCaching(book: CalibreBook, format: Format) -> Bool {
        guard let container, !book.library.server.isLocal, format != .UNKNOWN,
              book.formats[format.rawValue] != nil,
              activeDownload(for: book, format: format) == nil else { return false }
        var currentBook = bookRepository.getBook(id: book.inShelfId) ?? book
        if currentBook.formats[format.rawValue] == nil { currentBook = book }
        var book = currentBook
        if !book.inShelf || book.formats[format.rawValue]?.selected != true {
            container.bookManager.addToShelf(book: book, formats: [format])
            book.inShelf = true
            book.formats[format.rawValue]?.selected = true
        }
        switch container.downloadManager.startDownload(book, format: format, overwrite: true) {
        case .success:
            activeDownloads = container.downloadManager.activeDownloads
            updateReadableFile()
            return true
        case .failure(let error):
            alertItem = AlertItem(id: "Error Download Book", msg: error.localizedDescription)
            return false
        }
    }

    func pauseDownload(book: CalibreBook, format: Format) {
        container?.downloadManager.pauseDownload(book, format: format)
        synchronizeDownloads()
    }

    func resumeDownload(book: CalibreBook, format: Format) {
        container?.downloadManager.resumeDownload(book, format: format)
        synchronizeDownloads()
    }

    func cancelDownload(book: CalibreBook, format: Format) {
        if pendingReading?.bookID == book.inShelfId, pendingReading?.format == format { pendingReading = nil }
        container?.downloadManager.cancelDownload(book, format: format)
        synchronizeDownloads()
    }

    private func synchronizeDownloads() {
        activeDownloads = container?.downloadManager.activeDownloads ?? [:]
        updateReadableFile()
    }

    func cancelReadDownload(book: CalibreBook) {
        guard let pendingReading, pendingReading.bookID == book.inShelfId else { return }
        cancelDownload(book: book, format: pendingReading.format)
    }

    func clearFormat(book: CalibreBook, format: Format) {
        pendingReading = nil
        guard !book.library.server.isLocal, let container else { return }
        container.downloadManager.cancelDownload(book, format: format)
        // Reconcile with the latest metadata before the manager persists the cache change.
        let current = bookRepository.getBook(id: book.inShelfId) ?? book
        container.bookManager.clearCache(book: current, format: format)
        if let current = bookRepository.getBook(id: book.inShelfId), loadedBookId == book.inShelfId {
            applyBookUpdate(current, container: container)
        }
    }

    func isWaitingToRead(_ book: CalibreBook) -> Bool { pendingReading?.bookID == book.inShelfId }

    func canRead(_ book: CalibreBook) -> Bool { calibreBook?.inShelfId == book.inShelfId && hasReadableFile }

    func readActionTitle(for book: CalibreBook) -> String {
        if let pending = pendingReading, pending.bookID == book.inShelfId {
            return getActiveDownload(book: book, format: pending.format)?.isPaused == true ? "Paused" : "Downloading…"
        }
        return canRead(book) ? "Read" : (book.library.server.isLocal ? "File Missing" : "Download and Read")
    }

    func hasActiveDownload(_ book: CalibreBook) -> Bool {
        activeDownloads.values.contains { $0.book.inShelfId == book.inShelfId && $0.isActive }
    }

    private func activeDownload(for book: CalibreBook, format: Format) -> BookFormatDownload? {
        container?.downloadManager.activeDownloads.values.first {
            $0.book.inShelfId == book.inShelfId && $0.format == format && $0.isActive
        }
    }

    private func preferredReadableFormat(for book: CalibreBook) -> Format? {
        guard let container else { return nil }
        var readableBook = book
        readableBook.formats = book.formats.filter {
            guard let format = Format(rawValue: $0.key) else { return false }
            return container.sessionManager.getPreferredReader(for: format) != .UNSUPPORTED
        }
        return container.sessionManager.getPreferredFormat(for: readableBook)
    }

    /// Keep the session manager's device/latest-position policy, considering only ready files.
    private func cachedReaderInfo(for book: CalibreBook, format: Format? = nil) -> ReaderInfo? {
        guard let container else { return nil }
        var readyBook = book
        readyBook.formats = book.formats.filter { raw, info in
            guard let candidate = Format(rawValue: raw), format == nil || format == candidate,
                  info.cached, container.sessionManager.getPreferredReader(for: candidate) != .UNSUPPORTED,
                  let url = getSavedUrl(book: book, format: candidate) else { return false }
            return fileExists(url)
        }
        guard !readyBook.formats.isEmpty else { return nil }
        let positions = readingPositionRepository.getPositions(for: book).filter {
            guard let reader = ReaderType(rawValue: $0.readerName) else { return false }
            return readyBook.formats[reader.format.rawValue] != nil
        }
        let info = container.sessionManager.prepareBookReading(book: readyBook, withLoadedPositions: positions)
        return info.missing ? nil : info
    }

    private func applyDownloadSnapshot(_ snapshot: [URL: BookFormatDownload]) {
        activeDownloads = snapshot
        updateReadableFile()
        guard let pending = pendingReading else { return }
        guard container?.downloadManager.activeDownloads.values.contains(where: { $0.id == pending.downloadID }) == true else {
            pendingReading = nil
            return
        }
        guard let download = snapshot.values.first(where: { $0.id == pending.downloadID }) else { return }
        guard let completion = download.completion else { return }
        // Consume before opening: duplicate callbacks and subsequent metadata updates cannot reopen.
        pendingReading = nil
        switch completion {
        case .succeeded:
            guard let book = bookRepository.getBook(id: pending.bookID),
                  calibreBook?.inShelfId == pending.bookID,
                  let info = cachedReaderInfo(for: book, format: pending.format) else {
                alertItem = AlertItem(id: "Cannot locate book file", msg: "Please download the book again.")
                return
            }
            openReader(for: book, info: info, workspaceID: pending.workspaceID)
        case .failed(let message):
            alertItem = AlertItem(id: "Error Download Book", msg: message)
        case .cancelled: break
        }
    }

    private func applyBookUpdate(_ book: CalibreBook, container: AppContainer) {
        guard book.inShelfId == loadedBookId else { return }
        calibreBook = book
        pageState = .content
        helperConfiguration = container.serverManager.queryServerDSReaderHelper(server: book.library.server)?.configuration
        applyPositions(readingPositionRepository.getPositions(for: book), book: book)
        updateReadableFile()
    }
    
    func showReadingPositionHistory(book: CalibreBook) {
        guard let container, book.inShelfId == loadedBookId else { return }
        pendingReading = nil
        cancelRefresh()
        readingHistoryViewModel = ReadingPositionHistoryViewModel(container: container, book: book)
        isReturningFromHistory = true
        isReadingPositionHistoryActive = true
    }

    func showActivity(book: CalibreBook) {
        guard let container, book.inShelfId == loadedBookId, activityViewModel == nil else { return }
        let activity = ActivityListViewModel(repository: container.activityLogRepository,
                                             libraryId: book.library.id, bookId: book.id)
        let events = container.dismissAllEvents()
        activityViewModel = activity
        // The sheet owns its dismissal subscription even if Book Detail disappears underneath it.
        activityDismissTask = Task { [weak self] in
            for await _ in events {
                guard !Task.isCancelled, self?.activityViewModel?.id == activity.id else { return }
                self?.closeActivity()
                return
            }
        }
    }

    func closeActivity() {
        activityDismissTask?.cancel()
        activityDismissTask = nil
        activityViewModel?.stop()
        activityViewModel = nil
    }

    func previewAction(book: CalibreBook, format: Format, formatInfo: FormatInfo) -> Bool {
        pendingReading = nil
        cancelRefresh()
        closePreview()
        guard let container, let reader = ReaderType.readers(for: format).first else { return false }
        guard formatInfo.cached, let url = getSavedUrl(book: book, format: format), fileExists(url) else {
            updateReadableFile()
            alertItem = AlertItem(id: "Cannot locate book file", msg: book.library.server.isLocal
                ? "Please import the original file again." : "Please download \(format.rawValue) again.")
            return false
        }
        let info = ReaderInfo(deviceName: container.deviceName, url: url, missing: false, format: format,
            readerType: reader, position: readingPositionRepository.createInitial(deviceName: container.deviceName, reader: reader))
        let preview = BookPreviewViewModel(container: container, book: book, readerInfo: info)
        previewViewModel = preview
        preview.start()
        return true
    }

    func closePreview() {
        previewViewModel?.cancel()
        previewViewModel = nil
    }

    private func openReader(for book: CalibreBook, info: ReaderInfo, workspaceID: UUID?) {
        guard let container else { return }
        container.openReader(
            book: book,
            readerInfo: info,
            source: .bookDetail,
            targetWorkspaceID: workspaceID
        )
    }

    var updatingMetadata: Bool { refreshState == .refreshing }

    enum ReadingProgressSummary: Equatable {
        case goodreadsReadDate(String)
        case goodreadsProgress(String)
        case localProgress(percent: Double, device: String)
    }

    private func updateReadableFile() {
        updateFormatStates()
        guard let book = calibreBook, let container else { hasReadableFile = false; return }
        hasReadableFile = book.formats.contains { raw, info in
            guard info.cached, let format = Format(rawValue: raw),
                  container.sessionManager.getPreferredReader(for: format) != .UNSUPPORTED,
                  let url = getSavedUrl(book: book, format: format) else { return false }
            return fileExists(url)
        }
    }

    private func applyPositions(_ positions: [BookDeviceReadingPosition], book: CalibreBook) {
        hasHistory = !positions.isEmpty
        let goodreadsSync = goodreadsSyncPreferences(for: book.library)
        if let date = book.readDateGRByLocale(pluginGoodreadsSync: goodreadsSync) {
            readingProgressSummary = .goodreadsReadDate(date)
        } else if let progress = book.readProgressGRDescription(pluginGoodreadsSync: goodreadsSync) {
            readingProgressSummary = .goodreadsProgress(progress)
        } else if let position = ReadingPositionSelectionPolicy.latestForDevice(deviceName).select(from: positions)
                    ?? ReadingPositionSelectionPolicy.latest.select(from: positions) {
            readingProgressSummary = .localProgress(percent: position.lastProgress, device: position.id)
        } else {
            readingProgressSummary = nil
        }
    }

    func getReadingProgressSummary(for book: CalibreBook) -> ReadingProgressSummary? {
        calibreBook?.inShelfId == book.inShelfId ? readingProgressSummary : nil
    }

    func dsReaderHelperConfiguration(for library: CalibreLibrary) -> CalibreDSReaderHelperConfiguration? {
        calibreBook?.library.id == library.id ? helperConfiguration : nil
    }

    func goodreadsSyncPreferences(for library: CalibreLibrary) -> CalibreGoodreadsSyncPrefs.PluginPrefs {
        library.pluginGoodreadsSyncPreferences(configuration: dsReaderHelperConfiguration(for: library))
    }

    func countPagesConfiguration(for library: CalibreLibrary) -> CalibreCountPagesPrefs.LibraryConfig {
        library.pluginCountPagesConfiguration(configuration: dsReaderHelperConfiguration(for: library))
    }

    func ratingGRDescription(for book: CalibreBook) -> String? {
        book.ratingGRDescription(pluginGoodreadsSync: goodreadsSyncPreferences(for: book.library))
    }

    func goodreadsShelves(for book: CalibreBook) -> [String]? {
        let goodreadsSync = goodreadsSyncPreferences(for: book.library)
        guard goodreadsSync.isEnabled,
              goodreadsSync.tagsColumnName.count > 0,
              let shelves = book.userMetadatas[goodreadsSync.tagsColumnName.trimmingCharacters(in: CharacterSet(["#"]))] as? [String],
              shelves.count > 0 else {
            return nil
        }
        return shelves
    }
    
    func hasReadingHistory(for book: CalibreBook) -> Bool {
        calibreBook?.inShelfId == book.inShelfId && hasHistory
    }
    
    private func updateFormatStates() {
        guard let book = calibreBook else { formatStates = []; return }
        formatStates = book.formats.sorted { $0.key < $1.key }.map { raw, info in
            let format = Format(rawValue: raw).flatMap { ReaderType.readers(for: $0).isEmpty ? nil : $0 }
            let available = info.cached && (format.flatMap { getSavedUrl(book: book, format: $0) }.map(fileExists) ?? false)
            let download = format.flatMap { format in
                activeDownloads.values.lazy
                    .filter { $0.book.inShelfId == book.inShelfId && $0.format == format }
                    .max { first, second in
                        if first.isActive != second.isActive { return second.isActive }
                        return first.startDatetime < second.startDatetime
                    }
            }
            let text: String
            let icon: String
            if format == nil { text = "This format is not supported."; icon = "doc.badge.ellipsis" }
            else if book.library.server.isLocal {
                text = available ? "Imported Original File" : "File missing. Import the original file again."
                icon = available ? "doc" : "exclamationmark.triangle"
            } else if case .failed = download?.completion {
                text = available ? "Download failed. Previous download is available." : "Download failed. Try again."
                icon = "exclamationmark.triangle"
            } else if info.cached && !available {
                text = "File missing. Download again."; icon = "exclamationmark.triangle"
            } else if available {
                text = remoteFreshnessUnknown ? "Downloaded" : (info.cacheUptoDate ? "Downloaded · Up to Date" : "Downloaded · Server Has Update")
                icon = "checkmark.circle"
            } else { text = "Not Downloaded"; icon = "arrow.down.circle" }
            return BookFormatState(id: raw, format: format, size: available ? info.cacheSize : info.serverSize,
                isLocal: book.library.server.isLocal, fileAvailable: available, wasCached: info.cached,
                download: download, statusText: text, statusIcon: icon)
        }
    }

    func isFormatDownloading(book: CalibreBook, format: Format) -> Bool {
        return activeDownloads.values.contains { download in
            download.book.inShelfId == book.inShelfId && download.format == format && download.isActive
        }
    }
    
    func getActiveDownload(book: CalibreBook, format: Format) -> BookFormatDownload? {
        return activeDownloads.values.first { download in
            download.book.inShelfId == book.inShelfId && download.format == format && download.isActive
        }
    }
    
    private var remoteFreshnessUnknown: Bool {
        switch refreshState {
        case .failed, .unavailable: return true
        default: return false
        }
    }

}
