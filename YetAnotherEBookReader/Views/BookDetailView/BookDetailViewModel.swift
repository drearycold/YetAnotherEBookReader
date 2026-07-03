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
    
    @Published var presentingReadingSheet = false {
        willSet {
            if newValue {
                let binding = Binding<Bool>(
                    get: { [weak self] in self?.presentingReadingSheet ?? false },
                    set: { [weak self] in self?.presentingReadingSheet = $0 }
                )
                pushPresenting(binding)
            }
        }
        didSet { if oldValue { popPresenting() } }
    }
    
    @Published var presentingPreviewSheet = false {
        willSet {
            if newValue {
                let binding = Binding<Bool>(
                    get: { [weak self] in self?.presentingPreviewSheet ?? false },
                    set: { [weak self] in self?.presentingPreviewSheet = $0 }
                )
                pushPresenting(binding)
            }
        }
        didSet { if oldValue { popPresenting() } }
    }
    
    @Published var activityListViewPresenting = false {
        willSet {
            if newValue {
                let binding = Binding<Bool>(
                    get: { [weak self] in self?.activityListViewPresenting ?? false },
                    set: { [weak self] in self?.activityListViewPresenting = $0 }
                )
                pushPresenting(binding)
            }
        }
        didSet { if oldValue { popPresenting() } }
    }

    @Published var readingPositionHistoryViewPresenting = false {
        willSet {
            if newValue {
                let binding = Binding<Bool>(
                    get: { [weak self] in self?.readingPositionHistoryViewPresenting ?? false },
                    set: { [weak self] in self?.readingPositionHistoryViewPresenting = $0 }
                )
                pushPresenting(binding)
            }
        }
        didSet { if oldValue { popPresenting() } }
    }
    
    private weak var container: AppContainer?
    private var fetchTask: Task<Void, Never>?
    private var activeDownloadsTask: Task<Void, Never>?
    @Published var activeDownloads: [URL: BookFormatDownload] = [:]
    var readerInfo: ReaderInfo? {
        return container?.sessionManager.readerInfo
    }

    var deviceName: String {
        return container?.deviceName ?? ""
    }

    var updatingMetadataStatus: String {
        return container?.updatingMetadataStatus ?? ""
    }
    
    var sharedAppContainer: AppContainer? {
        return container
    }
    
    init(container: AppContainer? = AppContainer.shared) {
        self.container = container
        print("BookDetailViewModel INIT")
    }
    
    deinit {
        fetchTask?.cancel()
        activeDownloadsTask?.cancel()
        bookObserverTask?.cancel()
    }
    
    func setup(bookId: String) {
        guard let container = self.container else {
            print("Warning: BookDetailViewModel setup called before container was set")
            return
        }
        
        activeDownloadsTask?.cancel()
        activeDownloadsTask = Task { [weak self, weak container] in
            guard let container else { return }
            for await snapshot in container.downloadManager.downloadSnapshots() {
                await MainActor.run {
                    self?.activeDownloads = snapshot
                }
            }
        }
        
        guard let calibreBook = container.bookRepository.getBook(id: bookId) else {
            print("Error: CalibreBook not found for primary key \(bookId)")
            return
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
        if book.inShelf {
            container.bookManager.clearCache(inShelfId: book.inShelfId)
        } else if container.downloadManager.activeDownloads.filter({ $1.isActive && $1.book.id == book.id }).isEmpty {
            if let downloadFormat = container.sessionManager.getPreferredFormat(for: book) {
                container.bookManager.addToShelf(book: book, formats: [downloadFormat])
            } else {
                alertItem = AlertItem(id: "Error Download Book", msg: "Sorry, there's no supported book format")
            }
        }
    }

    func readBook(book: CalibreBook) {
        guard let container = container else { return }
        guard container.downloadManager.activeDownloads.filter({ $1.isActive && $1.book.id == book.id }).isEmpty else { return }

        if book.inShelf {
            prepareReadingSession(for: book)
        } else {
            if let downloadFormat = container.sessionManager.getPreferredFormat(for: book) {
                container.bookManager.addToShelf(book: book, formats: [downloadFormat])
            } else {
                alertItem = AlertItem(id: "Error Download Book", msg: "Sorry, there's no supported book format")
            }
        }
    }

    func cacheFormat(book: CalibreBook, format: Format) {
        guard let container = container else { return }
        if book.inShelf {
            switch container.downloadManager.startDownload(book, format: format, overwrite: true) {
            case .success:
                break
            case .failure(let error):
                alertItem = AlertItem(id: "Error Download Book", msg: error.localizedDescription)
            }
        } else {
            container.bookManager.addToShelf(book: book, formats: [format])
        }
    }

    func pauseDownload(book: CalibreBook, format: Format) {
        container?.downloadManager.pauseDownload(book, format: format)
    }

    func resumeDownload(book: CalibreBook, format: Format) {
        container?.downloadManager.resumeDownload(book, format: format)
    }

    func cancelDownload(book: CalibreBook, format: Format) {
        container?.downloadManager.cancelDownload(book, format: format)
    }

    func clearFormat(book: CalibreBook, format: Format) {
        container?.bookManager.clearCache(book: book, format: format)
    }

    private func applyBookUpdate(_ book: CalibreBook, container: AppContainer) {
        calibreBook = book
        listVM?.book = book
        listVM?.positions = container.readingPositionRepository.getPositions(for: book)
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
        guard let container = container else { return false }
        guard let reader = container.sessionManager.formatReaderMap[format]?.first else { return false }
        guard let bookFileUrl = getSavedUrl(book: book, format: format) else {
            alertItem = AlertItem(id: "Cannot locate book file", msg: "Please re-download \(format.rawValue)")
            return false
        }

        let readPosition = container.readingPositionRepository.createInitial(deviceName: container.deviceName, reader: reader)

        container.sessionManager.prepareBookReading(
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
    
    func handlePreviewDismiss(book: CalibreBook) {
        prepareReadingSession(for: book)
    }

    private func prepareReadingSession(for book: CalibreBook) {
        container?.bookManager.readingBook = book
    }

    func convert(bookRealm: CalibreBookRealm) -> CalibreBook? {
        return container?.bookManager.convert(bookRealm: bookRealm)
    }

    var updatingMetadata: Bool {
        return container?.updatingMetadata ?? false
    }

    func pushPresenting(_ binding: Binding<Bool>) {
        container?.presentingStack.append(binding)
    }

    func popPresenting() {
        _ = container?.presentingStack.popLast()
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
        
        if let readDateGR = book.readDateGRByLocale {
            return .goodreadsReadDate(readDateGR)
        } else if let readProgressGR = book.readProgressGRDescription {
            return .goodreadsProgress(readProgressGR)
        } else if let position = repository.getPosition(for: book, policy: .latestForDevice(deviceName))
                    ?? repository.getPosition(for: book, policy: .latest) {
            return .localProgress(percent: position.lastProgress, device: position.id)
        } else {
            return nil
        }
    }
    
    func hasReadingHistory(for book: CalibreBook) -> Bool {
        guard let repository = container?.readingPositionRepository else { return false }
        return !repository.getPositions(for: book).isEmpty
    }
    
    func isFormatDownloading(bookId: Int32, format: Format) -> Bool {
        return activeDownloads.values.contains { download in
            download.book.id == bookId && download.format == format && download.isActive
        }
    }
    
    func getActiveDownload(bookId: Int32, format: Format) -> BookFormatDownload? {
        return activeDownloads.values.first { download in
            download.book.id == bookId && download.format == format && download.isActive
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
