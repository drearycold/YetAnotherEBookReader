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
    
    @MainActor private var lastActivitySubmission: Task<Void, Never>?
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

    // MainActor publishes snapshots immediately. Each task waits only for the previous
    // submission to be accepted by the logger, independently of disk I/O.
    @MainActor
    private func submitActivity(_ event: ActivityLogWriteEvent) {
        guard let logger = container?.logger else { return }
        let previous = lastActivitySubmission
        lastActivitySubmission = Task {
            await previous?.value
            await logger.submit(event)
        }
    }

    @MainActor
    func waitForActivitySubmissions() async {
        await lastActivitySubmission?.value
    }

    @MainActor
    private func recordProgress(at url: URL, _ progress: ActivityLogProgress) {
        guard var download = activeDownloads[url], download.completion == nil else { return }
        download.activityRevision += 1
        activeDownloads[url] = download
        submitActivity(.update(id: download.activityID, .progress(progress, revision: download.activityRevision)))
    }

    @MainActor
    fileprivate func completeDownload(at url: URL, completion: BookFormatDownload.Completion, result: ActivityLogResult) {
        guard var download = activeDownloads[url], download.completion == nil else { return }
        download.isDownloading = false
        download.isPausing = false
        download.isPaused = false
        download.resumeData = nil
        download.completion = completion

        var result = result
        let terminal: ActivityLogCompletion
        switch completion {
        case .succeeded:
            terminal = .succeeded
        case .failed(let message):
            terminal = .failed
            result.detail = message
        case .cancelled:
            terminal = .cancelled
            download.progress = 0
        }
        activeDownloads[url] = download
        submitActivity(.update(id: download.activityID, .finish(terminal, at: Date(), result: result)))
    }

    @MainActor
    func cancelDownload(_ book: CalibreBook, format: Format) {
        guard let download = activeDownloads.first(where: {
            $0.value.book.inShelfId == book.inShelfId && $0.value.format == format && $0.value.isActive
        }) else { return }

        cancelAttempt(at: download.key, download: download.value)
        publishDownloadSnapshot()
    }

    @MainActor
    private func cancelAttempt(at url: URL, download: BookFormatDownload) {
        let status = (download.downloadTask?.response as? HTTPURLResponse)?.statusCode
        completeDownload(at: url, completion: .cancelled, result: .init(httpStatusCode: status))
        download.downloadTask?.cancel()
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
        recordProgress(at: download.key, .paused)
        publishDownloadSnapshot()
        
        download.value.downloadTask?.cancel(byProducingResumeData: { [weak self] resumeData in
            Task { @MainActor in
                guard let self, let current = self.activeDownloads[download.key],
                      current.id == download.value.id, current.completion == nil, current.isPausing,
                      current.downloadTask === download.value.downloadTask else { return }
                self.activeDownloads[download.key]?.isDownloading = false
                self.activeDownloads[download.key]?.isPausing = false
                self.activeDownloads[download.key]?.isPaused = true
                self.activeDownloads[download.key]?.resumeData = resumeData
                self.publishDownloadSnapshot()
            }
        })
        
    }

    @MainActor
    func resumeDownload(_ book: CalibreBook, format: Format) -> Bool {
        guard let bookFormatDownloadIndex = activeDownloads.firstIndex (where: {
                $1.book.inShelfId == book.inShelfId && $1.format == format && $1.completion == nil && ($1.resumeData != nil || $1.isPaused)
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
        recordProgress(at: bookFormatDownload.sourceURL, .running)
        publishDownloadSnapshot()

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

        let diagnosticURL = ActivityLogRequestSnapshot.redactedURL(url) ?? ""
        defaultLog.info("prepare downloadURL: \(diagnosticURL)")
        
        guard let savedURL = getSavedUrl(book: book, format: format) else {
            return .failure(.missingSavedURL)
        }
        
        self.defaultLog.info("savedURL: \(savedURL.absoluteString)")
        
        if FileManager.default.fileExists(atPath: savedURL.path) && !overwrite {
            return .failure(.fileAlreadyExists)
        }
        
        if !overwrite && (activeDownloads[url]?.isActive == true || activeDownloads.values.contains(where: {
            $0.book.inShelfId == book.inShelfId && $0.format == format && $0.isActive
        })) {
            return .failure(.downloadAlreadyActive)
        }
        
        var bookFormatDownload = BookFormatDownload(book: book, format: format, startDatetime: Date(), sourceURL: url, savedURL: savedURL, modificationDate: formatInfo.serverMTime)
        
        let downloadDelegate = BookFormatDownloadDelegate(download: bookFormatDownload, manager: self)
        
        let downloadConfiguration = self.sessionConfiguration
        let downloadSession = URLSession(configuration: downloadConfiguration, delegate: downloadDelegate, delegateQueue: nil)
        let downloadTask = downloadSession.downloadTask(with: url)
        
        if let host = url.host, !book.library.server.username.isEmpty, !book.library.server.password.isEmpty {
            var authMethod = NSURLAuthenticationMethodDefault
            if url.scheme == "http" {
                authMethod = NSURLAuthenticationMethodHTTPDigest
            }
            if url.scheme == "https" {
                authMethod = NSURLAuthenticationMethodHTTPBasic
            }
            let protectionSpace = URLProtectionSpace.init(host: host,
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
        
        for (oldURL, oldDownload) in activeDownloads.filter({
            $0.value.isActive && ($0.key == url || ($0.value.book.inShelfId == book.inShelfId && $0.value.format == format))
        }) {
            cancelAttempt(at: oldURL, download: oldDownload)
        }
        
        bookFormatDownload.isDownloading = true
        bookFormatDownload.downloadTask = downloadTask
        
        activeDownloads[url] = bookFormatDownload
        let request = downloadTask.originalRequest ?? URLRequest(url: url)
        submitActivity(.start(.init(
            id: bookFormatDownload.activityID, kind: .download, request: .init(request: request),
            startDatetime: bookFormatDownload.startDatetime, libraryId: book.library.id,
            bookIds: [book.id], downloadFormat: format.rawValue
        )))
        publishDownloadSnapshot()
        
        downloadTask.resume()
        
        defaultLog.info("start downloadURL: \(diagnosticURL)")
        
        return .success(())
    }

    @MainActor
    func startBatchDownload(books: [CalibreBook], formats: [String]) {
        guard let container else { return }
        for requestedBook in books {
            let book = container.bookRepository.getBook(id: requestedBook.inShelfId) ?? requestedBook
            let downloadFormats = formats.compactMap { format -> Format? in
                guard let f = Format(rawValue: format),
                      f != .UNKNOWN,
                      let formatInfo = book.formats[format],
                      formatInfo.serverSize > 0 else { return nil }
                return f
            }
            container.bookManager.addToShelf(book: book, formats: downloadFormats)
            let server = book.library.server
            guard !server.isLocal, !downloadFormats.isEmpty else { continue }
            guard container.calibreServerService.getServerUrlByReachability(server: server) != nil else {
                // The shelf retains the selection until the server is reachable. Retire terminal
                // results for the formats the user just queued so they can download at that point.
                let previousCount = activeDownloads.count
                activeDownloads = activeDownloads.filter { _, download in
                    download.isActive || download.book.inShelfId != book.inShelfId
                        || !downloadFormats.contains(download.format)
                }
                if activeDownloads.count != previousCount { publishDownloadSnapshot() }
                continue
            }
            // A confirmed batch is an explicit download, including retries after a terminal result.
            for format in downloadFormats {
                requestDownload(book: book, format: format)
            }
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
    var activityRevision = 0
    var activityID: ActivityID { ActivityID(rawValue: id.uuidString) }
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

class BookFormatDownloadDelegate: CalibreServerDiagnosticTaskDelegate, URLSessionDownloadDelegate {
    private struct StagedFile {
        let url: URL
        let size: UInt64
    }

    private static let saveFailure = "The downloaded file could not be saved. Please try again."
    private let fileManager: FileManager
    private let started = DispatchTime.now().uptimeNanoseconds
    private let download: BookFormatDownload
    private weak var manager: BookDownloadManager?
    // URLSession delivers file and completion callbacks on its serial delegate queue.
    private var stagedFile: StagedFile?
    private var stagingFailure: String?

    init(download: BookFormatDownload, manager: BookDownloadManager, fileManager: FileManager = .default) {
        self.download = download
        self.manager = manager
        self.fileManager = fileManager
        super.init(download.book.library.server)
    }

    deinit {
        if let stagedFile { try? fileManager.removeItem(at: stagedFile.url) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: location.path)
            guard let size = attributes[.size] as? NSNumber, size.uint64Value > 0 else {
                stagingFailure = "The server returned an empty file."
                return
            }
            // The URLSession temporary file expires at callback return. Commit its private
            // staging file only after checking that this task still owns the download.
            let staging = download.savedURL.deletingLastPathComponent()
                .appendingPathComponent(".\(UUID().uuidString).download")
            try fileManager.moveItem(at: location, to: staging)
            stagedFile = StagedFile(url: staging, size: size.uint64Value)
        } catch {
            stagingFailure = Self.saveFailure
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let response = task.response as? HTTPURLResponse
        let urlError = error as? URLError
        // A challenge can precede a successful login. Use it only when URLSession cancels
        // without a final response, as it does when credentials are rejected.
        let status = response?.statusCode ?? (urlError?.code == .cancelled ? authenticationStatusCode : nil)
        let request = ActivityLogRequestSnapshot(request: task.currentRequest ?? task.originalRequest ?? URLRequest(url: download.sourceURL))
        let responseURL = ActivityLogRequestSnapshot.redactedURL(response?.url)
        let duration = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
        let diagnostic = ActivityLogRequestDiagnostic(
            request: request, responseURL: responseURL == request.endpointURL ? nil : responseURL,
            httpStatusCode: status, duration: duration
        )
        let staged = stagedFile
        let stagingFailure = self.stagingFailure
        stagedFile = nil

        Task { @MainActor [self] in
            defer { if let staged { try? fileManager.removeItem(at: staged.url) } }
            guard let manager, let current = manager.activeDownloads[download.sourceURL],
                  isCurrent(current, for: task) else { return }

            let completion: BookFormatDownload.Completion
            var result = ActivityLogResult(httpStatusCode: status, requests: [diagnostic])
            if let status, !(200...299).contains(status) {
                result.errorCategory = status == 401 || status == 403 ? .authentication : .http
                completion = .failed("Server returned HTTP \(status).")
            } else if error != nil {
                if urlError?.code == .cancelled {
                    completion = .cancelled
                } else {
                    result.errorCategory = .transport
                    let message = urlError.map { URLError($0.code).localizedDescription } ?? "The download failed."
                    completion = .failed(message)
                }
            } else if response == nil {
                result.errorCategory = .transport
                completion = .failed("The server did not return an HTTP response.")
            } else if let staged {
                do {
                    try commit(staged)
                    completion = .succeeded
                    result.detail = "Saved \(staged.size) bytes."
                } catch {
                    result.errorCategory = .file
                    completion = .failed(Self.saveFailure)
                }
            } else {
                result.errorCategory = .file
                completion = .failed(stagingFailure ?? Self.saveFailure)
            }

            if completion == .succeeded, let container = manager.container {
                let book = container.bookRepository.getBook(id: download.book.inShelfId) ?? download.book
                container.bookManager.addedCache(book: book, format: download.format)
                manager.completeDownload(at: download.sourceURL, completion: completion, result: result)
                manager.publishDownloadSnapshot()
                container.publishCalibreUpdate(.book(container.bookRepository.getBook(id: book.inShelfId) ?? book))
            } else {
                manager.completeDownload(at: download.sourceURL, completion: completion, result: result)
                manager.publishDownloadSnapshot()
            }
        }
        if session !== URLSession.shared { session.finishTasksAndInvalidate() }
    }

    private func isCurrent(_ current: BookFormatDownload, for task: URLSessionTask) -> Bool {
        current.id == download.id && current.isDownloading && current.completion == nil
            && (current.downloadTask == nil || current.downloadTask === task)
    }

    private func commit(_ staged: StagedFile) throws {
        // Set the metadata before replacing anything so a failed attribute write leaves
        // the existing cached book intact. Keep the staged metadata during replacement.
        try fileManager.setAttributes([.modificationDate: download.modificationDate], ofItemAtPath: staged.url.path)
        if fileManager.fileExists(atPath: download.savedURL.path) {
            _ = try fileManager.replaceItemAt(download.savedURL, withItemAt: staged.url, options: .usingNewMetadataOnly)
        } else {
            try fileManager.moveItem(at: staged.url, to: download.savedURL)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = min(Float(totalBytesWritten) / Float(totalBytesExpectedToWrite), 1)
        Task { @MainActor [self] in
            guard let manager, let current = manager.activeDownloads[download.sourceURL],
                  isCurrent(current, for: downloadTask), progress > current.progress + 0.01 else { return }
            manager.activeDownloads[download.sourceURL]?.progress = progress
            manager.publishDownloadSnapshot()
        }
    }
}
