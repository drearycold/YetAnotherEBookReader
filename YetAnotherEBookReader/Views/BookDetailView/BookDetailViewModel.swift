//
//  BookDetailViewModel.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/8/26.
//

import Foundation
import Combine
import SwiftUI

class BookDetailViewModel: ObservableObject {
    @Published var listVM: ReadingPositionListViewModel?
    @Published var previewViewModel = BookPreviewViewModel()
    @Published var calibreBook: CalibreBook?
    private var bookObserverToken: AnyCancellable?
    
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
    
    private weak var modelData: ModelData?
    private var fetchTask: Task<Void, Never>?
    @Published var activeDownloads: [URL: BookFormatDownload] = [:]
    var readerInfo: ReaderInfo? {
        return modelData?.sessionManager.readerInfo
    }

    var deviceName: String {
        return modelData?.deviceName ?? ""
    }

    var updatingMetadataStatus: String {
        return modelData?.updatingMetadataStatus ?? ""
    }
    
    var sharedModelData: ModelData? {
        return modelData
    }
    
    init(modelData: ModelData? = ModelData.shared) {
        self.modelData = modelData
        print("BookDetailViewModel INIT")
    }
    
    deinit {
        fetchTask?.cancel()
    }
    
    func setup(bookId: String) {
        guard let modelData = self.modelData else {
            print("Warning: BookDetailViewModel setup called before modelData was set")
            return
        }
        
        modelData.downloadManager.$activeDownloads.assign(to: &$activeDownloads)
        
        guard let calibreBook = modelData.bookRepository.getBook(id: bookId) else {
            print("Error: CalibreBook not found for primary key \(bookId)")
            return
        }
        self.calibreBook = calibreBook
        
        if self.listVM == nil {
            self.listVM = ReadingPositionListViewModel(
                modelData: modelData, book: calibreBook, positions: modelData.readingPositionRepository.getPositions(forBookId: calibreBook.bookPrefId)
            )
        } else {
            self.listVM?.book = calibreBook
            self.listVM?.positions = modelData.readingPositionRepository.getPositions(forBookId: calibreBook.bookPrefId)
        }
        
        bookObserverToken = modelData.bookRepository.observeBook(id: bookId)
            .sink { [weak self] updatedCalibreBook in
                guard let self = self, let modelData = self.modelData, let updatedCalibreBook = updatedCalibreBook else { return }
                self.calibreBook = updatedCalibreBook
                self.listVM?.book = updatedCalibreBook
                self.listVM?.positions = modelData.readingPositionRepository.getPositions(forBookId: updatedCalibreBook.bookPrefId)
            }
    }
    
    func fetchMetadata(book: CalibreBook) {
        guard let modelData = modelData else { return }
        fetchTask?.cancel()
        fetchTask = Task {
            await modelData.bookManager.getBooksMetadata(
                request: .init(
                    library: book.library,
                    books: [book.id],
                    getAnnotations: true
                )
            )
        }
    }
    
    func refresh(book: CalibreBook) {
        guard let modelData = modelData else { return }
        if modelData.updatingMetadata {
            // TODO cancel logic if needed
        } else {
            if let coverUrl = book.coverURL {
                modelData.kfImageCache.removeImage(forKey: coverUrl.absoluteString)
            }
            fetchMetadata(book: book)
        }
    }
    
    func downloadOrClearCache(book: CalibreBook) {
        guard let modelData = modelData else { return }
        if book.inShelf {
            modelData.bookManager.clearCache(inShelfId: book.inShelfId)
        } else if modelData.downloadManager.activeDownloads.filter({ $1.isDownloading && $1.book.id == book.id }).isEmpty {
            if let downloadFormat = modelData.sessionManager.getPreferredFormat(for: book) {
                modelData.bookManager.addToShelf(book: book, formats: [downloadFormat])
            } else {
                alertItem = AlertItem(id: "Error Download Book", msg: "Sorry, there's no supported book format")
            }
        }
    }

    func readBook(book: CalibreBook) {
        guard let modelData = modelData else { return }
        guard modelData.downloadManager.activeDownloads.filter({ $1.isDownloading && $1.book.id == book.id }).isEmpty else { return }

        if book.inShelf {
            modelData.sessionManager.readerInfo = modelData.sessionManager.prepareBookReading(book: book)
        } else {
            if let downloadFormat = modelData.sessionManager.getPreferredFormat(for: book) {
                modelData.bookManager.addToShelf(book: book, formats: [downloadFormat])
            } else {
                alertItem = AlertItem(id: "Error Download Book", msg: "Sorry, there's no supported book format")
            }
        }
    }

    func cacheFormat(book: CalibreBook, format: Format) {
        guard let modelData = modelData else { return }
        if book.inShelf {
            switch modelData.downloadManager.startDownloadNew(book, format: format, overwrite: true) {
            case .success:
                break
            case .failure(let error):
                alertItem = AlertItem(id: "Error Download Book", msg: error.localizedDescription)
            }
        } else {
            modelData.bookManager.addToShelf(book: book, formats: [format])
        }
    }

    func pauseDownload(book: CalibreBook, format: Format) {
        modelData?.downloadManager.pauseDownload(book, format: format)
    }

    func resumeDownload(book: CalibreBook, format: Format) {
        modelData?.downloadManager.resumeDownload(book, format: format)
    }

    func cancelDownload(book: CalibreBook, format: Format) {
        modelData?.downloadManager.cancelDownload(book, format: format)
    }

    func clearFormat(book: CalibreBook, format: Format) {
        modelData?.bookManager.clearCache(book: book, format: format)
    }
    
    func prepareReadingPositionHistory(book: CalibreBook) {
        guard let modelData = modelData else { return }
        if listVM == nil {
            listVM = ReadingPositionListViewModel(
                modelData: modelData, book: book, positions: modelData.readingPositionRepository.getPositions(forBookId: book.bookPrefId)
            )
        } else {
            listVM?.book = book
            listVM?.positions = modelData.readingPositionRepository.getPositions(forBookId: book.bookPrefId)
        }
    }
    
    func previewAction(book: CalibreBook, format: Format, formatInfo: FormatInfo) -> Bool {
        guard let modelData = modelData else { return false }
        guard let reader = modelData.sessionManager.formatReaderMap[format]?.first else { return false }
        guard let bookFileUrl = getSavedUrl(book: book, format: format) else {
            alertItem = AlertItem(id: "Cannot locate book file", msg: "Please re-download \(format.rawValue)")
            return false
        }

        let readPosition = modelData.readingPositionRepository.createInitial(deviceName: modelData.deviceName, reader: reader)

        modelData.sessionManager.prepareBookReading(
            url: bookFileUrl,
            format: format,
            readerType: reader,
            position: readPosition
        )
        
        previewViewModel.modelData = modelData
        previewViewModel.book = book
        previewViewModel.url = bookFileUrl
        previewViewModel.format = format
        previewViewModel.reader = reader
        previewViewModel.toc = "Initializing"
        
        Task { [weak self] in
            do {
                let data = try await modelData.calibreServerService.getBookManifest(book: book, format: format)
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
        modelData?.sessionManager.readerInfo = modelData?.sessionManager.prepareBookReading(book: book)
    }

    func convert(bookRealm: CalibreBookRealm) -> CalibreBook? {
        return modelData?.bookManager.convert(bookRealm: bookRealm)
    }

    var updatingMetadata: Bool {
        return modelData?.updatingMetadata ?? false
    }

    func pushPresenting(_ binding: Binding<Bool>) {
        modelData?.presentingStack.append(binding)
    }

    func popPresenting() {
        _ = modelData?.presentingStack.popLast()
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
        guard let repository = modelData?.readingPositionRepository else { return nil }
        
        if let readDateGR = book.readDateGRByLocale {
            return .goodreadsReadDate(readDateGR)
        } else if let readProgressGR = book.readProgressGRDescription {
            return .goodreadsProgress(readProgressGR)
        } else if let position = repository.getPosition(forBookId: book.bookPrefId, deviceName: deviceName) ?? repository.getPositions(forBookId: book.bookPrefId).first {
            return .localProgress(percent: position.lastProgress, device: position.id)
        } else {
            return nil
        }
    }
    
    func hasReadingHistory(for book: CalibreBook) -> Bool {
        guard let repository = modelData?.readingPositionRepository else { return false }
        return !repository.getPositions(forBookId: book.bookPrefId).isEmpty
    }
    
    func isFormatDownloading(bookId: Int32, format: Format) -> Bool {
        return activeDownloads.values.contains { download in
            download.book.id == bookId && download.format == format && (download.isDownloading || download.resumeData != nil)
        }
    }
    
    func getActiveDownload(bookId: Int32, format: Format) -> BookFormatDownload? {
        return activeDownloads.values.first { download in
            download.book.id == bookId && download.format == format && (download.isDownloading || download.resumeData != nil)
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
