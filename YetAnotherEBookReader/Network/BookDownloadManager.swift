//
//  BookDownloadManager.swift
//  YetAnotherEBookReader
//
//  Created by Gemini on 2026/4/6.
//

import Foundation
import OSLog

public enum DownloadStartError: Error, LocalizedError, Equatable {
    case missingFormatInfo
    case invalidURL
    case missingSavedURL
    case fileAlreadyExists
    case downloadAlreadyActive

    public var errorDescription: String? {
        switch self {
        case .missingFormatInfo:
            return "Book is not available in the requested format on the server."
        case .invalidURL:
            return "The download URL is invalid."
        case .missingSavedURL:
            return "Unable to determine local save location."
        case .fileAlreadyExists:
            return "The book is already downloaded."
        case .downloadAlreadyActive:
            return "A download is already in progress for this book."
        }
    }
}

class BookDownloadManager {
    @MainActor
    var activeDownloads: [URL: BookFormatDownload] = [:]

    private let defaultLog = Logger(subsystem: "io.github.dsreader", category: "BookDownloadManager")
    @MainActor
    private var downloadSnapshotContinuations = [UUID: AsyncStream<[URL: BookFormatDownload]>.Continuation]()
    
    var container: AppContainerProtocol?
    @MainActor
    var sessionConfiguration: URLSessionConfiguration = .default

    init(container: AppContainerProtocol? = nil) {
        self.container = container
    }
    
    @MainActor
    func setup(container: AppContainerProtocol) {
        self.container = container
    }

    @MainActor
    func downloadSnapshots() -> AsyncStream<[URL: BookFormatDownload]> {
        AsyncStream { continuation in
            let id = UUID()
            downloadSnapshotContinuations[id] = continuation
            continuation.yield(activeDownloads)
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.downloadSnapshotContinuations.removeValue(forKey: id)
                }
            }
        }
    }

    @MainActor
    fileprivate func publishDownloadSnapshot() {
        let continuations = Array(downloadSnapshotContinuations.values)
        continuations.forEach {
            $0.yield(activeDownloads)
        }
    }

    @discardableResult
    @MainActor
    func requestDownload(book: CalibreBook, format: Format, overwrite: Bool = false) -> Result<Void, DownloadStartError> {
        startDownload(book, format: format, overwrite: overwrite)
    }

    /// Shelf rebuilds may arrive after a failed or cancelled attempt. Only the user starts a
    /// new attempt in this session; rebuilding the shelf must not retry or resume it implicitly.
    @MainActor
    func requestAutomaticDownload(book: CalibreBook, format: Format) {
        guard !activeDownloads.values.contains(where: {
            $0.book.inShelfId == book.inShelfId && $0.format == format
        }) else { return }
        _ = requestDownload(book: book, format: format)
    }

    @MainActor
    func cancelDownload(_ book: CalibreBook, format: Format) {
        guard let download = activeDownloads.filter({
                    $1.book.inShelfId == book.inShelfId && $1.format == format
            && $1.isActive
        }).first else {
            return
        }
        
        download.value.downloadTask?.cancel()
        
        if let request = download.value.downloadTask?.originalRequest {
            container?.logFinishCalibreActivity(type: "Download Format \(format.rawValue)", request: request, startDatetime: download.value.startDatetime, finishDatetime: Date(), errMsg: "Cancelled")
        }

        activeDownloads[download.key]?.isDownloading = false
        activeDownloads[download.key]?.isPausing = false
        activeDownloads[download.key]?.isPaused = false
        activeDownloads[download.key]?.progress = 0.0
        activeDownloads[download.key]?.resumeData = nil
        activeDownloads[download.key]?.completion = .cancelled
        publishDownloadSnapshot()
    }
    
    @MainActor
    func pauseDownload(_ book: CalibreBook, format: Format) {
        guard let download = activeDownloads.filter({
                    $1.isDownloading && $1.book.inShelfId == book.inShelfId && $1.format == format
        }).first else {
            return
        }

        activeDownloads[download.key]?.isDownloading = false
        activeDownloads[download.key]?.isPausing = true
        activeDownloads[download.key]?.isPaused = true
        publishDownloadSnapshot()
        
        download.value.downloadTask?.cancel(byProducingResumeData: { [weak self] resumeData in
            Task { @MainActor in
                guard let self else { return }
                if let currentTask = self.activeDownloads[download.key]?.downloadTask,
                   let pausedTask = download.value.downloadTask,
                   currentTask !== pausedTask {
                    return
                }
                guard self.activeDownloads[download.key]?.completion == nil else { return }
                self.activeDownloads[download.key]?.isDownloading = false
                self.activeDownloads[download.key]?.isPausing = false
                self.activeDownloads[download.key]?.isPaused = true
                self.activeDownloads[download.key]?.resumeData = resumeData
                self.publishDownloadSnapshot()
            }
        })
        
        if let request = download.value.downloadTask?.originalRequest {
            container?.logFinishCalibreActivity(type: "Download Format \(format.rawValue)", request: request, startDatetime: download.value.startDatetime, finishDatetime: Date(), errMsg: "Paused")
        }
    }
    
    @MainActor
    func resumeDownload(_ book: CalibreBook, format: Format) -> Bool {
        guard let bookFormatDownloadIndex = activeDownloads.firstIndex (where: {
                $1.book.inShelfId == book.inShelfId && $1.format == format && ($1.resumeData != nil || $1.isPaused)
        }) else {
            cancelDownload(book, format: format)
            return false
        }
        let bookFormatDownload = activeDownloads[bookFormatDownloadIndex].value

        let downloadDelegate = BookFormatDownloadDelegate(download: bookFormatDownload, manager: self)

        let downloadConfiguration = self.sessionConfiguration
        let downloadSession = URLSession(configuration: downloadConfiguration, delegate: downloadDelegate, delegateQueue: nil)
        let downloadTask: URLSessionDownloadTask
        if let resumeData = bookFormatDownload.resumeData {
            downloadTask = downloadSession.downloadTask(withResumeData: resumeData)
        } else {
            downloadTask = downloadSession.downloadTask(with: bookFormatDownload.sourceURL)
        }

        if let credential = bookFormatDownload.credential, let protectionSpace = bookFormatDownload.protectionSpace {
            URLCredentialStorage.shared.setDefaultCredential(credential, for: protectionSpace, task: downloadTask)
        }

        activeDownloads[bookFormatDownload.sourceURL]?.isDownloading = true
        activeDownloads[bookFormatDownload.sourceURL]?.isPausing = false
        activeDownloads[bookFormatDownload.sourceURL]?.isPaused = false
        activeDownloads[bookFormatDownload.sourceURL]?.resumeData = nil
        activeDownloads[bookFormatDownload.sourceURL]?.downloadTask = downloadTask
        publishDownloadSnapshot()

        if let request = downloadTask.originalRequest {
            container?.logFinishCalibreActivity(type: "Download Format \(format.rawValue)", request: request, startDatetime: bookFormatDownload.startDatetime, finishDatetime: Date(), errMsg: "Resumed")
        }

        downloadTask.resume()

        return true
    }
    
    @MainActor
    func startDownload(_ book: CalibreBook, format: Format, overwrite: Bool = false) -> Result<Void, DownloadStartError> {
        guard let formatInfo = book.formats[format.rawValue] else {
            return .failure(.missingFormatInfo)
        }
        
        guard let url = URL(string: book.library.server.serverUrl)?
                .appendingPathComponent("get", isDirectory: true)
                .appendingPathComponent(format.rawValue, isDirectory: true)
                .appendingPathComponent(book.id.description, isDirectory: true)
                .appendingPathComponent(book.library.key, isDirectory: false)
                else {
            return .failure(.invalidURL)
        }

        defaultLog.info("prepare downloadURL: \(url.absoluteString)")
        
        guard let savedURL = getSavedUrl(book: book, format: format) else {
            return .failure(.missingSavedURL)
        }
        
        self.defaultLog.info("savedURL: \(savedURL.absoluteString)")
        
        if FileManager.default.fileExists(atPath: savedURL.path) && !overwrite {
            return .failure(.fileAlreadyExists)
        }
        
        if activeDownloads[url]?.isActive == true && !overwrite {
            return .failure(.downloadAlreadyActive)
        }
        
        var bookFormatDownload = BookFormatDownload(book: book, format: format, startDatetime: Date(), sourceURL: url, savedURL: savedURL, modificationDate: formatInfo.serverMTime)
        
        let downloadDelegate = BookFormatDownloadDelegate(download: bookFormatDownload, manager: self)
        
        let downloadConfiguration = self.sessionConfiguration
        let downloadSession = URLSession(configuration: downloadConfiguration, delegate: downloadDelegate, delegateQueue: nil)
        let downloadTask = downloadSession.downloadTask(with: url)
        
        if let request = downloadTask.originalRequest {
            container?.logStartCalibreActivity(type: "Download Format \(format.rawValue)", request: request, startDatetime: bookFormatDownload.startDatetime, bookId: book.id, libraryId: book.library.id)
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
        publishDownloadSnapshot()
        
        downloadTask.resume()
        
        defaultLog.info("start downloadURL: \(url.absoluteString)")
        
        return .success(())
    }

    @MainActor
    func startBatchDownload(books: [CalibreBook], formats: [String]) {
        books.forEach { book in
            let downloadFormats = formats.compactMap { format -> Format? in
                guard let f = Format(rawValue: format),
                      let formatInfo = book.formats[format],
                      formatInfo.serverSize > 0 else { return nil }
                return f
            }
            container?.bookManager.addToShelf(book: book, formats: downloadFormats)
        }
    }
}

struct BookFormatDownload {
    enum Completion: Equatable {
        case succeeded
        case failed(String)
        case cancelled
    }

    /// A retry is a new download; pause/resume retains the same identity.
    var id = UUID()
    var completion: Completion?
    var isDownloading = false
    var isPaused = false
    var isPausing = false
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

    var isActive: Bool {
        isDownloading || isPausing || isPaused || resumeData != nil
    }
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
    private var stagedURL: URL?
    
    init(download: BookFormatDownload, manager: BookDownloadManager) {
        self.download = download
        self.manager = manager
        super.init(download.book.library.server)
    }
    
    deinit {
        if let stagedURL { try? FileManager.default.removeItem(at: stagedURL) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: location.path)
            guard let size = attributes[.size] as? NSNumber, size.uint64Value > 0 else {
                throw DownloadError(msg: "Empty file")
            }
            // URLSession removes its temporary file after this callback. Keep a private copy until
            // the main actor validates the HTTP result, download identity and cancellation state.
            let staging = download.savedURL.deletingLastPathComponent()
                .appendingPathComponent(".\(UUID().uuidString).download")
            try FileManager.default.moveItem(at: location, to: staging)
            stagedURL = staging
            fileSize = size.uint64Value
            isFileExist = true
        } catch {
            self.defaultLog.error("file error: \(error.localizedDescription)")
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let response = task.response,
           let httpResponse = response as? HTTPURLResponse,
           (200...299).contains(httpResponse.statusCode),
           error == nil, isFileExist {
            Task { @MainActor [self] in
                defer { discardStagedFile() }
                guard let manager = self.manager, let container = manager.container,
                      let current = manager.activeDownloads[download.sourceURL],
                      current.id == download.id, current.isActive else { return }
                if let currentTask = manager.activeDownloads[self.download.sourceURL]?.downloadTask,
                   currentTask !== task {
                    return
                }
                guard manager.activeDownloads[self.download.sourceURL]?.completion == nil else { return }

                do {
                    if let stagedURL {
                        if FileManager.default.fileExists(atPath: download.savedURL.path) {
                            _ = try FileManager.default.replaceItemAt(download.savedURL, withItemAt: stagedURL)
                        } else {
                            try FileManager.default.moveItem(at: stagedURL, to: download.savedURL)
                        }
                        try FileManager.default.setAttributes([.modificationDate: download.modificationDate], ofItemAtPath: download.savedURL.path)
                    }
                } catch {
                    manager.activeDownloads[download.sourceURL]?.isDownloading = false
                    manager.activeDownloads[download.sourceURL]?.isPausing = false
                    manager.activeDownloads[download.sourceURL]?.isPaused = false
                    manager.activeDownloads[download.sourceURL]?.resumeData = nil
                    manager.activeDownloads[download.sourceURL]?.completion = .failed("The downloaded file could not be saved. Please try again.")
                    manager.publishDownloadSnapshot()
                    return
                }
                let book = container.bookRepository.getBook(id: download.book.inShelfId) ?? download.book
                container.bookManager.addedCache(book: book, format: self.download.format)
                manager.activeDownloads[self.download.sourceURL]?.isDownloading = false
                manager.activeDownloads[self.download.sourceURL]?.isPausing = false
                manager.activeDownloads[self.download.sourceURL]?.isPaused = false
                manager.activeDownloads[self.download.sourceURL]?.resumeData = nil
                manager.activeDownloads[self.download.sourceURL]?.completion = .succeeded
                manager.publishDownloadSnapshot()

                let updatedBook = container.bookRepository.getBook(id: book.inShelfId) ?? book
                container.publishCalibreUpdate(.book(updatedBook))

                guard let request = task.originalRequest else { return }
                let logger = container.logger
                let startDatetime = self.download.startDatetime
                let format = self.download.format
                let fileSize = self.fileSize
                Task {
                    await logger?.logFinishCalibreActivity(type: "Download Format \(format.rawValue)", request: request, startDatetime: startDatetime, finishDatetime: Date(), errMsg: "Finished Size=\(fileSize)")
                }
            }
        } else {
            Task { @MainActor [self] in
                defer { discardStagedFile() }
                guard let manager = self.manager, let container = manager.container,
                      manager.activeDownloads[download.sourceURL]?.id == download.id,
                      let request = task.originalRequest
                       else { return }
                if let currentTask = manager.activeDownloads[self.download.sourceURL]?.downloadTask,
                   currentTask !== task {
                    return
                }
                guard manager.activeDownloads[self.download.sourceURL]?.completion == nil else { return }

                let nsError = error as NSError?
                if manager.activeDownloads[self.download.sourceURL]?.isPaused == true,
                   nsError?.domain == NSURLErrorDomain,
                   nsError?.code == NSURLErrorCancelled {
                    return
                }

                manager.activeDownloads[self.download.sourceURL]?.isDownloading = false
                manager.activeDownloads[self.download.sourceURL]?.isPausing = false
                manager.activeDownloads[self.download.sourceURL]?.isPaused = false
                manager.activeDownloads[self.download.sourceURL]?.resumeData = nil
                let message: String
                if let error {
                    message = error.localizedDescription
                } else if let response = task.response as? HTTPURLResponse,
                          !(200...299).contains(response.statusCode) {
                    message = "Server returned HTTP \(response.statusCode)."
                } else {
                    message = "The downloaded file could not be saved."
                }
                manager.activeDownloads[self.download.sourceURL]?.completion = .failed(message)
                manager.publishDownloadSnapshot()

                let logger = container.logger
                let startDatetime = self.download.startDatetime
                let format = self.download.format
                let errDescription = error?.localizedDescription
                Task {
                    await logger?.logFinishCalibreActivity(type: "Download Format \(format.rawValue)", request: request, startDatetime: startDatetime, finishDatetime: Date(), errMsg: "Failed, error=\(String(describing: errDescription))")
                }
            }
        }
    }
    
    private func discardStagedFile() {
        if let stagedURL { try? FileManager.default.removeItem(at: stagedURL) }
        stagedURL = nil
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let progress = Float(totalBytesWritten) / Float(totalBytesExpectedToWrite)
        
        guard let manager = manager else { return }

        Task { @MainActor in
            if let currentTask = manager.activeDownloads[self.download.sourceURL]?.downloadTask,
               currentTask !== downloadTask {
                return
            }
            guard progress > (manager.activeDownloads[self.download.sourceURL]?.progress ?? 0.0) + 0.01 else { return }
            manager.activeDownloads[self.download.sourceURL]?.progress = progress
            manager.publishDownloadSnapshot()
        }
    }
}
