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
    @Published var listVM: ReadingPositionListViewModel?
    @Published var previewViewModel = BookPreviewViewModel()
    @Published var calibreBook: CalibreBook?
    private var bookObserverTask: Task<Void, Never>?
    
    @Published var alertItem: AlertItem?
    
    @Published var presentingPreviewSheet = false
    
    @Published var activityListViewPresenting = false

    /// Drives the push of Reading History. It is pushed, not a sheet, so a reader opened from it
    /// shows above it in the workspace overlay.
    @Published var isReadingPositionHistoryActive = false
    
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

    var updatingMetadataStatus: String {
        return container?.updatingMetadataStatus ?? ""
    }
    
    var sharedAppContainer: AppContainer? {
        return container
    }
    
    init(container: AppContainer? = AppContainer.shared, targetWorkspaceID: UUID? = nil) {
        self.container = container
        self.targetWorkspaceID = targetWorkspaceID
        print("BookDetailViewModel INIT")
    }
    
    deinit {
        fetchTask?.cancel()
        activeDownloadsTask?.cancel()
        bookObserverTask?.cancel()
        dismissTask?.cancel()
    }
    
    /// Loads the book and refreshes its metadata, except when coming back from Reading History,
    /// which would otherwise hit the server on every pop.
    func onAppear(bookId: String, targetWorkspaceID: UUID?) {
        self.targetWorkspaceID = targetWorkspaceID
        let isReturningFromHistory = self.isReturningFromHistory
        self.isReturningFromHistory = false
        guard !(isReturningFromHistory && loadedBookId == bookId) else { return }
        guard setup(bookId: bookId), let calibreBook else { return }
        loadedBookId = bookId
        fetchMetadata(book: calibreBook)
    }

    func onDisappear() {
        pendingReading = nil
    }
    
    @discardableResult
    func setup(bookId: String) -> Bool {
        guard let container = self.container else {
            print("Warning: BookDetailViewModel setup called before container was set")
            return false
        }
        
        if calibreBook?.inShelfId != bookId { pendingReading = nil }
        activeDownloadsTask?.cancel()
        activeDownloadsTask = Task { [weak self, weak container] in
            guard let container else { return }
            for await snapshot in container.downloadManager.downloadSnapshots() {
                guard !Task.isCancelled else { return }
                self?.applyDownloadSnapshot(snapshot)
            }
        }
        dismissTask?.cancel()
        let dismissEvents = container.dismissAllEvents()
        dismissTask = Task { [weak self] in
            for await _ in dismissEvents {
                guard !Task.isCancelled else { return }
                self?.pendingReading = nil
            }
        }
        
        guard let calibreBook = container.bookRepository.getBook(id: bookId) else {
            print("Error: CalibreBook not found for primary key \(bookId)")
            return false
        }
        self.calibreBook = calibreBook
        
        if self.listVM == nil {
            self.listVM = ReadingPositionListViewModel(
                container: container, book: calibreBook, positions: container.readingPositionRepository.getPositions(for: calibreBook)
            )
        } else {
            self.listVM?.book = calibreBook
            self.listVM?.positions = container.readingPositionRepository.getPositions(for: calibreBook)
        }
        
        bookObserverTask?.cancel()
        let bookUpdates = container.bookRepository.observeBook(id: bookId)
        bookObserverTask = Task { [weak self, weak container] in
            guard let container else { return }
            for await updatedCalibreBook in bookUpdates {
                guard !Task.isCancelled, let updatedCalibreBook else { continue }
                await MainActor.run { [weak self, weak container] in
                    guard let self, let container else { return }
                    self.applyBookUpdate(updatedCalibreBook, container: container)
                }
            }
        }
        return true
    }
    
    func fetchMetadata(book: CalibreBook) {
        guard let container = container else { return }
        fetchTask?.cancel()
        fetchTask = Task { [weak self, weak container] in
            guard let self, let container else { return }
            await container.bookManager.getBooksMetadata(
                request: .init(
                    library: book.library,
                    books: [book.id],
                    getAnnotations: true
                )
            )
            guard !Task.isCancelled else { return }
            container.refreshDatabase()
            guard let updatedBook = container.bookRepository.getBook(id: book.inShelfId) else { return }
            self.applyBookUpdate(updatedBook, container: container)
        }
    }
    
    func refresh(book: CalibreBook) {
        guard let container = container else { return }
        if container.updatingMetadata {
            // TODO cancel logic if needed
        } else {
            if let coverUrl = book.coverURL {
                container.coverCache.removeCover(for: coverUrl)
            }
            fetchMetadata(book: book)
        }
    }
    
    func downloadOrClearCache(book: CalibreBook) {
        guard let container = container else { return }
        pendingReading = nil
        if book.inShelf {
            container.bookManager.clearCache(inShelfId: book.inShelfId)
        } else {
            downloadOnly(book: book)
        }
    }

    func readBook(book: CalibreBook) {
        guard let container, pendingReading == nil else { return }
        alertItem = nil

        if let info = cachedReaderInfo(for: book) {
            if !book.inShelf { container.bookManager.addToShelf(book: book, formats: [info.format]) }
            openReader(for: book, info: info, workspaceID: targetWorkspaceID)
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
        if download.isPaused {
            container.downloadManager.resumeDownload(book, format: format)
        }
    }

    func downloadOnly(book: CalibreBook) {
        pendingReading = nil
        guard let format = preferredReadableFormat(for: book) else {
            alertItem = AlertItem(id: "Error Download Book", msg: "Sorry, there's no supported book format")
            return
        }
        if activeDownload(for: book, format: format) == nil { _ = startCaching(book: book, format: format) }
    }

    func cacheFormat(book: CalibreBook, format: Format) {
        pendingReading = nil
        _ = startCaching(book: book, format: format)
    }

    private func startCaching(book: CalibreBook, format: Format) -> Bool {
        guard let container else { return false }
        var book = book
        if !book.inShelf || book.formats[format.rawValue]?.selected != true {
            container.bookManager.addToShelf(book: book, formats: [format])
            book.inShelf = true
            book.formats[format.rawValue]?.selected = true
        }
        switch container.downloadManager.startDownload(book, format: format, overwrite: true) {
        case .success: return true
        case .failure(let error):
            alertItem = AlertItem(id: "Error Download Book", msg: error.localizedDescription)
            return false
        }
    }

    func pauseDownload(book: CalibreBook, format: Format) {
        container?.downloadManager.pauseDownload(book, format: format)
    }

    func resumeDownload(book: CalibreBook, format: Format) {
        container?.downloadManager.resumeDownload(book, format: format)
    }

    func cancelDownload(book: CalibreBook, format: Format) {
        if pendingReading?.bookID == book.inShelfId, pendingReading?.format == format { pendingReading = nil }
        container?.downloadManager.cancelDownload(book, format: format)
    }

    func cancelReadDownload(book: CalibreBook) {
        guard let pendingReading, pendingReading.bookID == book.inShelfId else { return }
        cancelDownload(book: book, format: pendingReading.format)
    }

    func clearFormat(book: CalibreBook, format: Format) {
        pendingReading = nil
        container?.bookManager.clearCache(book: book, format: format)
    }

    func isWaitingToRead(_ book: CalibreBook) -> Bool { pendingReading?.bookID == book.inShelfId }

    func canRead(_ book: CalibreBook) -> Bool { cachedReaderInfo(for: book) != nil }

    func readActionTitle(for book: CalibreBook) -> String {
        isWaitingToRead(book) ? "Downloading…" : (canRead(book) ? "Read" : "Download and Read")
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
            return FileManager.default.fileExists(atPath: url.path)
        }
        guard !readyBook.formats.isEmpty else { return nil }
        let positions = container.readingPositionRepository.getPositions(for: book).filter {
            guard let reader = ReaderType(rawValue: $0.readerName) else { return false }
            return readyBook.formats[reader.format.rawValue] != nil
        }
        let info = container.sessionManager.prepareBookReading(book: readyBook, withLoadedPositions: positions)
        return info.missing ? nil : info
    }

    private func applyDownloadSnapshot(_ snapshot: [URL: BookFormatDownload]) {
        activeDownloads = snapshot
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
            guard let book = container?.bookRepository.getBook(id: pending.bookID),
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
        calibreBook = book
        listVM?.book = book
        listVM?.positions = container.readingPositionRepository.getPositions(for: book)
    }
    
    func showReadingPositionHistory(book: CalibreBook) {
        pendingReading = nil
        prepareReadingPositionHistory(book: book)
        isReturningFromHistory = true
        isReadingPositionHistoryActive = true
    }
    
    func prepareReadingPositionHistory(book: CalibreBook) {
        guard let container = container else { return }
        if listVM == nil {
            listVM = ReadingPositionListViewModel(
                container: container, book: book, positions: container.readingPositionRepository.getPositions(for: book)
            )
        } else {
            listVM?.book = book
            listVM?.positions = container.readingPositionRepository.getPositions(for: book)
        }
    }
    
    func previewAction(book: CalibreBook, format: Format, formatInfo: FormatInfo) -> Bool {
        pendingReading = nil
        guard let container = container else { return false }
        guard let reader = container.sessionManager.formatReaderMap[format]?.first else { return false }
        guard let bookFileUrl = getSavedUrl(book: book, format: format) else {
            alertItem = AlertItem(id: "Cannot locate book file", msg: "Please re-download \(format.rawValue)")
            return false
        }

        let readPosition = container.readingPositionRepository.createInitial(deviceName: container.deviceName, reader: reader)

        _ = container.sessionManager.prepareBookReading(
            url: bookFileUrl,
            format: format,
            readerType: reader,
            position: readPosition
        )
        
        previewViewModel.container = container
        previewViewModel.book = book
        previewViewModel.url = bookFileUrl
        previewViewModel.format = format
        previewViewModel.reader = reader
        previewViewModel.toc = "Initializing"
        
        Task { [weak self] in
            do {
                let data = try await container.calibreServerService.getBookManifest(book: book, format: format)
                await MainActor.run {
                    self?.parseManifestToTOC(json: data)
                }
            } catch {
                // Error handled or left as initializing
            }
        }
        return true
    }
    
    func parseManifestToTOC(json: Data) {
        previewViewModel.toc = "Without TOC"
        
        guard let root = try? JSONSerialization.jsonObject(with: json, options: []) as? NSDictionary else {
            #if DEBUG
            previewViewModel.toc = String(data: json, encoding: .utf8) ?? "String Decoding Failure"
            #endif
            return
        }
        
        guard let tocNode = root["toc"] as? NSDictionary else {
            #if DEBUG
            previewViewModel.toc = String(data: json, encoding: .utf8) ?? "String Decoding Failure"
            #endif
            
            if let jobStatus = root["job_status"] as? String, jobStatus == "waiting" {
                previewViewModel.toc = "Generating TOC, Please try again later"
            }
            return
        }
        
        previewViewModel.toc = parseTOCNode(node: tocNode, level: 0)
    }
    
    /// The preview prepared a session at the book's start; restore the book's own reading position
    /// without opening a reader (closing a preview isn't a request to read).
    func handlePreviewDismiss(book: CalibreBook) {
        _ = container?.sessionManager.prepareBookReading(book: book)
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

    var updatingMetadata: Bool {
        return container?.updatingMetadata ?? false
    }

    func parseTOCNode(node: NSDictionary, level: Int) -> String {
        guard let childrenNode = node["children"] as? NSArray else {
            return ""
        }
        
        let tocString = childrenNode.compactMap { childNode -> String? in
            guard let dict = childNode as? NSDictionary, let title = dict["title"] as? String else {
                return nil
            }
            return title
        }.joined(separator: "\n") + "\n"
        
        return tocString
    }
    
    enum ReadingProgressSummary: Equatable {
        case goodreadsReadDate(String)
        case goodreadsProgress(String)
        case localProgress(percent: Double, device: String)
    }
    
    func getReadingProgressSummary(for book: CalibreBook) -> ReadingProgressSummary? {
        guard let repository = container?.readingPositionRepository else { return nil }
        let goodreadsSync = goodreadsSyncPreferences(for: book.library)
        
        if let readDateGR = book.readDateGRByLocale(pluginGoodreadsSync: goodreadsSync) {
            return .goodreadsReadDate(readDateGR)
        } else if let readProgressGR = book.readProgressGRDescription(pluginGoodreadsSync: goodreadsSync) {
            return .goodreadsProgress(readProgressGR)
        } else if let position = repository.getPosition(for: book, policy: .latestForDevice(deviceName))
                    ?? repository.getPosition(for: book, policy: .latest) {
            return .localProgress(percent: position.lastProgress, device: position.id)
        } else {
            return nil
        }
    }

    func dsReaderHelperConfiguration(for library: CalibreLibrary) -> CalibreDSReaderHelperConfiguration? {
        container?.serverManager.queryServerDSReaderHelper(server: library.server)?.configuration
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
        guard let repository = container?.readingPositionRepository else { return false }
        return !repository.getPositions(for: book).isEmpty
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
    
    func getFormatStatusText(formatInfo: FormatInfo) -> String {
        if formatInfo.cached {
            return formatInfo.cacheUptoDate ? "Up to date" : "Server has update"
        } else {
            return "Not cached"
        }
    }
    
    func getFormatStatusIcon(formatInfo: FormatInfo) -> String {
        return formatInfo.cacheUptoDate ? "hand.thumbsup" : "hand.thumbsdown"
    }
}
