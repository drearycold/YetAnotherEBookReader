//
//  BookDownloadManager.swift
//  YetAnotherEBookReader
//
//  Created by Gemini on 2026/4/6.
//

import Foundation
import Combine
import OSLog
import RealmSwift

class BookDownloadManager: ObservableObject {
    @Published var activeDownloads: [URL: BookFormatDownload] = [:]
    
    let bookFormatDownloadSubject = PassthroughSubject<(book: CalibreBook, format: Format), Never>()
    let bookDownloadedSubject = PassthroughSubject<CalibreBook, Never>()
    
    private var cancellables = Set<AnyCancellable>()
    private let defaultLog = Logger(subsystem: "io.github.dsreader", category: "BookDownloadManager")
    
    var modelData: ModelData?
    private var realmConf: Realm.Configuration?

    init(modelData: ModelData? = nil, realmConf: Realm.Configuration? = nil) {
        self.modelData = modelData
        self.realmConf = realmConf
        
        registerBookFormatDownloadHandler()
    }
    
    func setup(modelData: ModelData, realmConf: Realm.Configuration?) {
        self.modelData = modelData
        self.realmConf = realmConf
    }

    private func registerBookFormatDownloadHandler() {
        bookFormatDownloadSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] request in
                let _ = self?.startDownload(request.book, format: request.format, overwrite: false)
            }
            .store(in: &cancellables)
    }

    func cancelDownload(_ book: CalibreBook, format: Format) {
        guard let download = activeDownloads.filter({
                    $1.book.id == book.id && $1.format == format
            && ($1.isDownloading || $1.resumeData != nil)
        }).first else {
            return
        }
        
        download.value.downloadTask?.cancel()
        
        if let request = download.value.downloadTask?.originalRequest {
            modelData?.logFinishCalibreActivity(type: "Download Format \(format.rawValue)", request: request, startDatetime: Date(), finishDatetime: Date(), errMsg: "Cancelled")
        }

        activeDownloads[download.key]?.isDownloading = false
        activeDownloads[download.key]?.progress = 0.0
        activeDownloads[download.key]?.resumeData = nil
    }
    
    func pauseDownload(_ book: CalibreBook, format: Format) {
        guard let download = activeDownloads.filter({
                    $1.isDownloading && $1.book.id == book.id && $1.format == format
        }).first else {
            return
        }
        
        download.value.downloadTask?.cancel(byProducingResumeData: { [weak self] resumeData in
            DispatchQueue.main.async {
                self?.activeDownloads[download.key]?.isDownloading = false
                self?.activeDownloads[download.key]?.resumeData = resumeData
            }
        })
        
        if let request = download.value.downloadTask?.originalRequest {
            modelData?.logFinishCalibreActivity(type: "Download Format \(format.rawValue)", request: request, startDatetime: Date(), finishDatetime: Date(), errMsg: "Paused")
        }
    }
    
    func resumeDownload(_ book: CalibreBook, format: Format) -> Bool {
        guard let bookFormatDownloadIndex = activeDownloads.firstIndex (where: {
                $1.book.id == book.id && $1.format == format && $1.resumeData != nil
        }) else {
            return false
        }
        let bookFormatDownload = activeDownloads[bookFormatDownloadIndex].value
        
        guard let resumeData = bookFormatDownload.resumeData else {
            return false
        }
        
        let downloadDelegate = BookFormatDownloadDelegate(download: bookFormatDownload, manager: self)
        
        let downloadConfiguration = URLSessionConfiguration.default
        let downloadSession = URLSession(configuration: downloadConfiguration, delegate: downloadDelegate, delegateQueue: nil)
        let downloadTask = downloadSession.downloadTask(withResumeData: resumeData)
        
        if let credential = bookFormatDownload.credential, let protectionSpace = bookFormatDownload.protectionSpace {
            URLCredentialStorage.shared.setDefaultCredential(credential, for: protectionSpace, task: downloadTask)
        }
        
        activeDownloads[bookFormatDownload.sourceURL]?.isDownloading = true
        activeDownloads[bookFormatDownload.sourceURL]?.resumeData = nil
        activeDownloads[bookFormatDownload.sourceURL]?.downloadTask = downloadTask
        
        if let request = downloadTask.originalRequest {
            modelData?.logFinishCalibreActivity(type: "Download Format \(format.rawValue)", request: request, startDatetime: Date(), finishDatetime: Date(), errMsg: "Resumed")
        }
        
        downloadTask.resume()
        
        return true
    }
    
    func startDownload(_ book: CalibreBook, format: Format, overwrite: Bool = false) -> Bool {
        guard let formatInfo = book.formats[format.rawValue] else {
            return false
        }
        
        guard let url = URL(string: book.library.server.serverUrl)?
                .appendingPathComponent("get", isDirectory: true)
                .appendingPathComponent(format.rawValue, isDirectory: true)
                .appendingPathComponent(book.id.description, isDirectory: true)
                .appendingPathComponent(book.library.key, isDirectory: false)
                else {
            return false
        }

        defaultLog.info("prepare downloadURL: \(url.absoluteString)")
        
        guard let savedURL = getSavedUrl(book: book, format: format) else {
            return false
        }
        
        self.defaultLog.info("savedURL: \(savedURL.absoluteString)")
        
        if FileManager.default.fileExists(atPath: savedURL.path) && !overwrite {
            return false
        }
        
        if activeDownloads[url]?.isDownloading == true && !overwrite {
            return false
        }
        
        var bookFormatDownload = BookFormatDownload(book: book, format: format, startDatetime: Date(), sourceURL: url, savedURL: savedURL, modificationDate: formatInfo.serverMTime)
        
        let downloadDelegate = BookFormatDownloadDelegate(download: bookFormatDownload, manager: self)
        
        let downloadConfiguration = URLSessionConfiguration.default
        let downloadSession = URLSession(configuration: downloadConfiguration, delegate: downloadDelegate, delegateQueue: nil)
        let downloadTask = downloadSession.downloadTask(with: url)
        
        if let request = downloadTask.originalRequest {
            modelData?.logStartCalibreActivity(type: "Download Format \(format.rawValue)", request: request, startDatetime: bookFormatDownload.startDatetime, bookId: book.id, libraryId: book.library.id)
        }

        if book.library.server.username.count > 0 && book.library.server.password.count > 0 {
            var authMethod = NSURLAuthenticationMethodDefault
            if url.scheme == "http" {
                authMethod = NSURLAuthenticationMethodHTTPDigest
            }
            if url.scheme == "https" {
                authMethod = NSURLAuthenticationMethodHTTPBasic
            }
            let protectionSpace = URLProtectionSpace.init(host: url.host!,
                                                          port: url.port ?? 0,
                                                          protocol: url.scheme,
                                                          realm: "calibre",
                                                          authenticationMethod: authMethod)
            if let credentials = URLCredentialStorage.shared.credentials(for: protectionSpace) {
                if let credential = credentials.filter({ $0.key == book.library.server.username }).first?.value {
                    bookFormatDownload.credential = credential
                    bookFormatDownload.protectionSpace = protectionSpace
                    URLCredentialStorage.shared.setDefaultCredential(credential, for: protectionSpace, task: downloadTask)
                }
            }
        }
        
        activeDownloads[url]?.downloadTask?.cancel()
        
        bookFormatDownload.isDownloading = true
        bookFormatDownload.downloadTask = downloadTask
        
        activeDownloads[url] = bookFormatDownload
        
        downloadTask.resume()
        
        defaultLog.info("start downloadURL: \(url.absoluteString)")
        
        return true
    }
    
    func startBatchDownload(books: [CalibreBook], formats: [String]) {
        books.forEach { book in
            let downloadFormats = formats.compactMap { format -> Format? in
                guard let f = Format(rawValue: format),
                      let formatInfo = book.formats[format],
                      formatInfo.serverSize > 0 else { return nil }
                return f
            }
            modelData?.addToShelf(book: book, formats: downloadFormats)
        }
    }
}

struct BookFormatDownload {
    var isDownloading = false
    var progress: Float = 0
    var resumeData: Data?
    var book: CalibreBook
    var format: Format
    var startDatetime: Date
    
    var sourceURL: URL
    var savedURL: URL
    var modificationDate: Date
    
    var downloadTask: URLSessionDownloadTask?
    var credential: URLCredential?
    var protectionSpace: URLProtectionSpace?
}

struct DownloadError: Error {
    let msg: String
}

class BookFormatDownloadDelegate: CalibreServerTaskDelegate, URLSessionDownloadDelegate {
    private var defaultLog = Logger(subsystem: "io.github.dsreader", category: "BookFormatDownloadDelegate")

    var download: BookFormatDownload
    weak var manager: BookDownloadManager?
    
    var isFileExist = false
    var fileSize = UInt64.zero
    
    init(download: BookFormatDownload, manager: BookDownloadManager) {
        self.download = download
        self.manager = manager
        super.init(download.book.library.server)
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        self.defaultLog.info("fileURL: \(location.absoluteString)")
        
        do {
           //check size
            let fileAttribs = try FileManager.default.attributesOfItem(atPath: location.path)
            guard let fileSize = fileAttribs[.size] as? NSNumber, fileSize.uint64Value > 0 else {
                throw DownloadError(msg: "Empty file")
            }
            
            if FileManager.default.fileExists(atPath: download.savedURL.path) {
                try FileManager.default.removeItem(at: download.savedURL)
            }
            try FileManager.default.moveItem(at: location, to: download.savedURL)
            let attributes = [FileAttributeKey.modificationDate: download.modificationDate]
            try FileManager.default.setAttributes(attributes, ofItemAtPath: download.savedURL.path)
            
            isFileExist = FileManager.default.fileExists(atPath: download.savedURL.path)
            self.fileSize = fileSize.uint64Value
            self.defaultLog.info("isFileExist: \(self.isFileExist)")
            
        } catch {
            print ("file error: \(error)")
        }

    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let response = task.response,
           let httpResponse = response as? HTTPURLResponse,
           (200...299).contains(httpResponse.statusCode),
           isFileExist {
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let manager = self.manager, let modelData = manager.modelData
                       else { return }
                
                modelData.addedCache(book: self.download.book, format: self.download.format)
                manager.activeDownloads[self.download.sourceURL]?.isDownloading = false
                manager.activeDownloads[self.download.sourceURL]?.resumeData = nil
                
                manager.bookDownloadedSubject.send(self.download.book)
                
                guard let request = task.originalRequest else { return }
                modelData.logFinishCalibreActivity(type: "Download Format \(self.download.format.rawValue)", request: request, startDatetime: self.download.startDatetime, finishDatetime: Date(), errMsg: "Finished Size=\(self.fileSize)")
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let manager = self.manager, let modelData = manager.modelData,
                      let request = task.originalRequest
                       else { return }
                
                manager.activeDownloads[self.download.sourceURL]?.isDownloading = false
                manager.activeDownloads[self.download.sourceURL]?.resumeData = nil
                
                modelData.logFinishCalibreActivity(type: "Download Format \(self.download.format.rawValue)", request: request, startDatetime: self.download.startDatetime, finishDatetime: Date(), errMsg: "Failed, error=\(String(describing: error?.localizedDescription))")
            }
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let progress = Float(totalBytesWritten) / Float(totalBytesExpectedToWrite)
        
        guard let manager = manager else { return }
        
        guard progress > (manager.activeDownloads[self.download.sourceURL]?.progress ?? 0.0) + 0.01 else { return }
        
        DispatchQueue.main.async {
            manager.activeDownloads[self.download.sourceURL]?.progress = progress
        }
    }
}
