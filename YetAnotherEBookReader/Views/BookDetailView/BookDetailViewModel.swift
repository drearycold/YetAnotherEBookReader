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
    
    @Published var alertItem: AlertItem?
    
    private weak var modelData: ModelData?
    var book: CalibreBookRealm?
    private var fetchTask: Task<Void, Never>?
    @Published var activeDownloads: [URL: BookFormatDownload] = [:]
    var readerInfo: ReaderInfo? {
        return modelData?.readerInfo
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
    
    init() {
        print("BookDetailViewModel INIT")
    }
    
    deinit {
        fetchTask?.cancel()
    }
    
    func setup(modelData: ModelData, book: CalibreBookRealm, calibreBook: CalibreBook) {
        
        self.modelData = modelData
        self.book = book
        
        if let downloadManager = self.modelData?.downloadManager {
            downloadManager.$activeDownloads.assign(to: &$activeDownloads)
        }
        
        if self.listVM == nil {
            self.listVM = ReadingPositionListViewModel(
                modelData: modelData, book: calibreBook, positions: calibreBook.readPos.getDevices().sorted(by: { $0.epoch > $1.epoch })
            )
        } else {
            self.listVM?.book = calibreBook
            self.listVM?.positions = calibreBook.readPos.getDevices().sorted(by: { $0.epoch > $1.epoch })
        }
    }
    
    func fetchMetadata(book: CalibreBook) {
        guard let modelData = modelData else { return }
        fetchTask?.cancel()
        fetchTask = Task {
            await modelData.getBooksMetadata(
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
            modelData.clearCache(inShelfId: book.inShelfId)
        } else if modelData.downloadManager.activeDownloads.filter({ $1.isDownloading && $1.book.id == book.id }).isEmpty {
            if let downloadFormat = modelData.getPreferredFormat(for: book) {
                modelData.addToShelf(book: book, formats: [downloadFormat])
            } else {
                alertItem = AlertItem(id: "Error Download Book", msg: "Sorry, there's no supported book format")
            }
        }
    }
    
    func readBook(book: CalibreBook) {
        guard let modelData = modelData else { return }
        guard modelData.downloadManager.activeDownloads.filter({ $1.isDownloading && $1.book.id == book.id }).isEmpty else { return }
        
        if book.inShelf {
            modelData.readerInfo = modelData.prepareBookReading(book: book)
        } else {
            if let downloadFormat = modelData.getPreferredFormat(for: book) {
                modelData.addToShelf(book: book, formats: [downloadFormat])
            } else {
                alertItem = AlertItem(id: "Error Download Book", msg: "Sorry, there's no supported book format")
            }
        }
    }
    
    func cacheFormat(book: CalibreBook, format: Format) {
        guard let modelData = modelData else { return }
        if book.inShelf {
            modelData.startDownloadFormat(book: book, format: format, overwrite: true)
        } else {
            modelData.addToShelf(book: book, formats: [format])
        }
    }
    
    func pauseDownload(book: CalibreBook, format: Format) {
        modelData?.pauseDownloadFormat(book: book, format: format)
    }
    
    func resumeDownload(book: CalibreBook, format: Format) {
        modelData?.resumeDownloadFormat(book: book, format: format)
    }
    
    func cancelDownload(book: CalibreBook, format: Format) {
        modelData?.cancelDownloadFormat(book: book, format: format)
    }
    
    func clearFormat(book: CalibreBook, format: Format) {
        modelData?.clearCache(book: book, format: format)
    }
    
    func prepareReadingPositionHistory(book: CalibreBook) {
        guard let modelData = modelData else { return }
        if listVM == nil {
            listVM = ReadingPositionListViewModel(
                modelData: modelData, book: book, positions: book.readPos.getDevices().sorted(by: { $0.epoch > $1.epoch })
            )
        } else {
            listVM?.book = book
            listVM?.positions = book.readPos.getDevices().sorted(by: { $0.epoch > $1.epoch })
        }
    }
    
    func previewAction(book: CalibreBook, format: Format, formatInfo: FormatInfo) -> Bool {
        guard let modelData = modelData else { return false }
        guard let reader = modelData.formatReaderMap[format]?.first else { return false }
        guard let bookFileUrl = getSavedUrl(book: book, format: format) else {
            alertItem = AlertItem(id: "Cannot locate book file", msg: "Please re-download \(format.rawValue)")
            return false
        }
        
        let readPosition = book.readPos.createInitial(deviceName: modelData.deviceName, reader: reader)
        
        modelData.prepareBookReading(
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
        
        modelData.calibreServerService.getBookManifest(book: book, format: format) { [weak self] data in
            guard let data = data else { return }
            self?.parseManifestToTOC(json: data)
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
        modelData?.readerInfo = modelData?.prepareBookReading(book: book)
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
}
