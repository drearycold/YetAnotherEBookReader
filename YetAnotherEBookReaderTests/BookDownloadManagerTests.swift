//
//  BookDownloadManagerTests.swift
//  YetAnotherEBookReaderTests
//
//  Created by Antigravity on 2026-06-24.
//

import XCTest
import RealmSwift
@testable import YetAnotherEBookReader

@MainActor
final class BookDownloadManagerTests: XCTestCase {
    private var container: AppContainer!
    private var manager: BookDownloadManager!

    override func setUpWithError() throws {
        container = MockAppContainerFactory.makeContainer(testName: "BookDownloadManagerTests")
        AppContainer.shared = container

        manager = BookDownloadManager(container: container)

        let testConfiguration = URLSessionConfiguration.ephemeral
        testConfiguration.protocolClasses = [MockURLProtocol.self]
        manager.sessionConfiguration = testConfiguration

        MockURLProtocol.requestHandler = { request in
            let responseURL = request.url ?? URL(string: "http://localhost/mock-download")!
            let response = HTTPURLResponse(url: responseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("MockDownloadData".utf8))
        }
    }

    override func tearDownWithError() throws {
        if let library = container?.calibreLibraries.first?.value {
            for id in 900...1020 {
                var book = CalibreBook(id: Int32(id), library: library)
                book.formats[Format.EPUB.rawValue] = Self.formatInfo(filename: "cleanup-\(id).epub")
                book.formats[Format.PDF.rawValue] = Self.formatInfo(filename: "cleanup-\(id).pdf")
                book.formats[Format.CBZ.rawValue] = Self.formatInfo(filename: "cleanup-\(id).cbz")
                removeSavedFile(for: book, format: .EPUB)
                removeSavedFile(for: book, format: .PDF)
                removeSavedFile(for: book, format: .CBZ)
            }
        }

        AppContainer.shared = nil
        manager = nil
        container = nil
        MockURLProtocol.requestHandler = nil
    }

    func testStartDownload_addsToActiveDownloads() throws {
        let book = try makeDownloadableBook(id: 999)
        removeSavedFile(for: book, format: .EPUB)

        let result = manager.startDownload(book, format: .EPUB, overwrite: true)

        switch result {
        case .success:
            XCTAssertEqual(manager.activeDownloads.count, 1)
            let download = manager.activeDownloads.values.first
            XCTAssertEqual(download?.book.id, 999)
            XCTAssertEqual(download?.format, .EPUB)
            XCTAssertTrue(download?.isDownloading ?? false)
        case .failure(let error):
            XCTFail("Failed to start download: \(error.localizedDescription)")
        }
    }

    @MainActor
    func testImmediateCancellationLogsOneTerminalActivityWithTheDownloadID() async throws {
        let book = try makeDownloadableBook(id: 998, filenamePrefix: "activity-cancel")
        _ = try manager.requestDownload(book: book, format: .EPUB, overwrite: true).get()
        let download = try XCTUnwrap(manager.activeDownloads.values.first)
        manager.cancelDownload(book, format: .EPUB)
        XCTAssertEqual(manager.activeDownloads[download.sourceURL]?.completion, .cancelled)

        let logger = try XCTUnwrap(container.logger)
        await manager.waitForActivitySubmissions()
        let persisted = await logger.flush()
        XCTAssertTrue(persisted)
        let entries = container.activityLogRepository.fetchEntries(
            libraryId: book.library.id, bookId: book.id, since: download.startDatetime
        )
        XCTAssertEqual(entries.map(\.id), [ActivityID(rawValue: download.id.uuidString)])
        XCTAssertEqual(entries.first?.kind, .download)
        XCTAssertEqual(entries.first?.state, .finished(.cancelled))
    }

    func testPauseAndResumeRecordOneAttemptAndRejectPausedTaskCompletion() async throws {
        let book = try makeDownloadableBook(id: 998, filenamePrefix: "activity-pause")
        removeSavedFile(for: book, format: .EPUB)
        let first = try beginControlledAttempt(book, status: 200)
        defer { try? FileManager.default.removeItem(at: first.savedURL) }
        manager.pauseDownload(book, format: .EPUB)

        let oldDelegate = BookFormatDownloadDelegate(download: first, manager: manager)
        try stage(first, delegate: oldDelegate)
        oldDelegate.urlSession(URLSession.shared, task: try XCTUnwrap(first.downloadTask), didCompleteWithError: nil)
        let paused = try await activity(for: first)
        XCTAssertEqual(paused.state, .inProgress(.paused))
        XCTAssertNil(paused.finishDatetime)
        XCTAssertEqual(paused.progressChanges.map(\.revision), [1])
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.savedURL.path))

        XCTAssertTrue(manager.resumeDownload(book, format: .EPUB))
        let resumed = try replaceWithStub(at: first.sourceURL, status: 200)
        XCTAssertEqual(resumed.id, first.id)
        let delegate = BookFormatDownloadDelegate(download: resumed, manager: manager)
        try stage(resumed, delegate: delegate)
        let resumedTask = try XCTUnwrap(resumed.downloadTask)
        delegate.urlSession(URLSession.shared, task: resumedTask, didCompleteWithError: nil)
        try await waitForCompletion(resumed)
        delegate.urlSession(URLSession.shared, task: resumedTask, didCompleteWithError: URLError(.timedOut))
        let finished = try await activity(for: resumed)
        XCTAssertEqual(finished.state, .finished(.succeeded))
        XCTAssertEqual(finished.result.httpStatusCode, 200)
        XCTAssertEqual(finished.downloadFormat, "EPUB")
        XCTAssertEqual(finished.progressChanges.map(\.progress), [.paused, .running])
        XCTAssertEqual(finished.progressChanges.map(\.revision), [1, 2])
        XCTAssertGreaterThanOrEqual(finished.progressChanges[1].date, finished.progressChanges[0].date)
        XCTAssertEqual(manager.activeDownloads[first.sourceURL]?.completion, .succeeded)
        XCTAssertEqual(try Data(contentsOf: resumed.savedURL), Data("ebook".utf8))
    }

    func testRetryAtAnotherAddressAndOtherFormatsKeepSeparateActivities() async throws {
        let book = try makeDownloadableBook(id: 998, formats: [.EPUB, .PDF], filenamePrefix: "activity-retry")
        let first = try beginControlledAttempt(book, status: 500)
        let oldDelegate = BookFormatDownloadDelegate(download: first, manager: manager)
        oldDelegate.urlSession(URLSession.shared, task: try XCTUnwrap(first.downloadTask), didCompleteWithError: nil)
        try await waitForCompletion(first)
        let failed = try await activity(for: first)
        XCTAssertEqual(failed.state, .finished(.failed))
        XCTAssertEqual(failed.result.httpStatusCode, 500)

        var movedLibrary = book.library
        movedLibrary.server.baseUrl = "http://127.0.0.1:49999"
        let moved = try makeDownloadableBook(id: book.id, formats: [.EPUB, .PDF], library: movedLibrary)
        XCTAssertEqual(moved.inShelfId, book.inShelfId)
        let retry = try beginControlledAttempt(moved, status: 200)
        XCTAssertNotEqual(first.id, retry.id)
        XCTAssertNotEqual(first.sourceURL, retry.sourceURL)
        let pdf = try beginControlledAttempt(moved, format: .PDF, status: 200)
        let otherLibrary = CalibreLibrary(server: book.library.server, key: "other-log-library", name: "Other Log Library")
        let otherBook = try makeDownloadableBook(id: book.id, library: otherLibrary)
        let other = try beginControlledAttempt(otherBook, status: 200)

        try stage(first, delegate: oldDelegate)
        oldDelegate.urlSession(URLSession.shared, task: try XCTUnwrap(first.downloadTask), didCompleteWithError: nil)
        manager.cancelDownload(moved, format: .EPUB)
        let cancelledRetry = try await activity(for: retry)
        XCTAssertEqual(cancelledRetry.state, .finished(.cancelled))
        let firstAfterRetry = try await activity(for: first)
        let pdfActivity = try await activity(for: pdf)
        let otherActivity = try await activity(for: other)
        XCTAssertEqual(firstAfterRetry, failed)
        XCTAssertEqual(pdfActivity.downloadFormat, "PDF")
        XCTAssertEqual(otherActivity.libraryId, otherLibrary.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.savedURL.path))
        let scoped = container.activityLogRepository.fetchEntries(
            libraryId: book.library.id, bookId: book.id, since: first.startDatetime
        )
        XCTAssertEqual(Set(scoped.map(\.id)), [first.activityID, retry.activityID, pdf.activityID])
        manager.cancelDownload(moved, format: .PDF)
        manager.cancelDownload(otherBook, format: .EPUB)
    }

    func testDownloadFailureActivityMatchesSnapshotForHTTPAndFileErrors() async throws {
        for (index, code) in ([401, 403, 500, 200, 200, 200, nil] as [Int?]).enumerated() {
            let book = try makeDownloadableBook(id: 990 + Int32(index), filenamePrefix: "activity-failure")
            removeSavedFile(for: book, format: .EPUB)
            let download = try beginControlledAttempt(book, status: code)
            defer { try? FileManager.default.removeItem(at: download.savedURL) }
            let fileManager = FailingDownloadFileManager()
            if index == 4 {
                // A failed attribute write must leave the previously cached file intact.
                try Data("old cached file".utf8).write(to: download.savedURL)
                fileManager.failAttributes = true
            }
            if index == 5 { fileManager.failedDestination = download.savedURL }
            let delegate = BookFormatDownloadDelegate(download: download, manager: manager, fileManager: fileManager)
            try stage(download, delegate: delegate, contents: index == 3 ? Data() : Data("ebook".utf8))
            let error = code == nil ? URLError(.notConnectedToInternet,
                userInfo: [NSURLErrorFailingURLStringErrorKey: "https://example.invalid/private-token"]) : nil
            delegate.urlSession(URLSession.shared, task: try XCTUnwrap(download.downloadTask), didCompleteWithError: error)
            try await waitForCompletion(download)

            let logged = try await activity(for: download)
            guard case .failed(let message) = manager.activeDownloads[download.sourceURL]?.completion else {
                return XCTFail("Expected a failed download for fixture \(index)")
            }
            XCTAssertEqual(logged.result.detail, message)
            XCTAssertEqual(logged.state, .finished(.failed))
            XCTAssertEqual(logged.result.httpStatusCode, code)
            let expected: ActivityLogErrorCategory = code == nil ? .transport : index < 2 ? .authentication : index == 2 ? .http : .file
            XCTAssertEqual(logged.result.errorCategory, expected)
            XCTAssertFalse(message.contains("private-token"))
            if index == 4 {
                XCTAssertEqual(try Data(contentsOf: download.savedURL), Data("old cached file".utf8))
            }
        }
    }

    func testProgressAndSuccessFromSupersededAddressDoNotMutateEitherAttempt() async throws {
        let book = try makeDownloadableBook(id: 997, filenamePrefix: "superseded")
        removeSavedFile(for: book, format: .EPUB)
        let old = try beginControlledAttempt(book, status: 200)
        var library = book.library
        library.server.baseUrl = "http://127.0.0.1:49998"
        let moved = try makeDownloadableBook(id: book.id, library: library)
        let next = try beginControlledAttempt(moved, status: 200)
        XCTAssertEqual(manager.activeDownloads[old.sourceURL]?.completion, .cancelled)

        let delegate = BookFormatDownloadDelegate(download: old, manager: manager)
        let oldTask = try XCTUnwrap(old.downloadTask)
        delegate.urlSession(URLSession.shared, downloadTask: oldTask, didWriteData: 50,
                            totalBytesWritten: 50, totalBytesExpectedToWrite: 100)
        try stage(old, delegate: delegate)
        delegate.urlSession(URLSession.shared, task: oldTask, didCompleteWithError: nil)
        let oldActivity = try await activity(for: old)
        XCTAssertEqual(oldActivity.state, .finished(.cancelled))
        XCTAssertEqual(manager.activeDownloads[old.sourceURL]?.progress, 0)
        XCTAssertEqual(manager.activeDownloads[next.sourceURL]?.progress, 0)
        XCTAssertTrue(manager.activeDownloads[next.sourceURL]?.isDownloading == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.savedURL.path))
        manager.cancelDownload(moved, format: .EPUB)
    }

    private func beginControlledAttempt(_ book: CalibreBook, format: Format = .EPUB, status: Int?) throws -> BookFormatDownload {
        _ = try manager.requestDownload(book: book, format: format, overwrite: true).get()
        return try replaceWithStub(at: downloadURL(for: book, format: format), status: status)
    }

    private func replaceWithStub(at url: URL, status: Int?) throws -> BookFormatDownload {
        var download = try XCTUnwrap(manager.activeDownloads[url])
        let original = download.downloadTask
        let response = status.map { httpResponse(url: url, statusCode: $0) }
        download.downloadTask = StubDownloadTask(request: URLRequest(url: url), response: response)
        manager.activeDownloads[url] = download
        original?.cancel()
        return download
    }

    private func stage(_ download: BookFormatDownload, delegate: BookFormatDownloadDelegate,
                       contents: Data = Data("ebook".utf8)) throws {
        let url = try makeTempFile(name: UUID().uuidString, contents: contents)
        defer { try? FileManager.default.removeItem(at: url) }
        delegate.urlSession(URLSession.shared, downloadTask: try XCTUnwrap(download.downloadTask),
                            didFinishDownloadingTo: url)
    }

    private func waitForCompletion(_ download: BookFormatDownload) async throws {
        let deadline = Date().addingTimeInterval(5)
        while manager.activeDownloads[download.sourceURL]?.completion == nil, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertNotNil(manager.activeDownloads[download.sourceURL]?.completion)
    }

    private func activity(for download: BookFormatDownload) async throws -> ActivityLogSnapshot {
        let logger = try XCTUnwrap(container.logger)
        await manager.waitForActivitySubmissions()
        _ = await logger.flush()
        let entries = container.activityLogRepository.fetchEntries(
            libraryId: download.book.library.id, bookId: download.book.id, since: .distantPast
        ).filter { $0.id == download.activityID }
        XCTAssertEqual(entries.count, 1)
        return try XCTUnwrap(entries.first)
    }

    func testRequestDownload_addsToActiveDownloads() throws {
        let book = try makeDownloadableBook(id: 998, filenamePrefix: "request")
        removeSavedFile(for: book, format: .EPUB)

        let result = manager.requestDownload(book: book, format: .EPUB, overwrite: true)

        switch result {
        case .success:
            XCTAssertEqual(manager.activeDownloads.count, 1)
            XCTAssertEqual(manager.activeDownloads.values.first?.book.id, 998)
        case .failure(let error):
            XCTFail("Failed to request download: \(error.localizedDescription)")
        }
    }

    func testStartDownloadRejectsMissingFormat() throws {
        let library = try XCTUnwrap(container.libraryManager.calibreLibraries.first?.value)
        let book = CalibreBook(id: 1010, library: library)

        let result = manager.startDownload(book, format: .EPUB)

        XCTAssertEqual(downloadStartError(from: result), .missingFormatInfo)
        XCTAssertTrue(manager.activeDownloads.isEmpty)
    }

    func testStartDownloadRejectsExistingFileWithoutOverwrite() throws {
        let book = try makeDownloadableBook(id: 1001)
        guard let savedURL = getSavedUrl(book: book, format: .EPUB) else {
            return XCTFail("Expected saved URL")
        }
        try Data("existing".utf8).write(to: savedURL)

        let result = manager.startDownload(book, format: .EPUB, overwrite: false)

        XCTAssertEqual(downloadStartError(from: result), .fileAlreadyExists)
        XCTAssertTrue(manager.activeDownloads.isEmpty)
    }

    func testStartDownloadRejectsDuplicateActiveDownload() throws {
        let book = try makeDownloadableBook(id: 1002)
        let download = try makeActiveDownload(book: book, format: .EPUB, isDownloading: true)
        manager.activeDownloads[download.sourceURL] = download

        let result = manager.startDownload(book, format: .EPUB, overwrite: false)

        XCTAssertEqual(downloadStartError(from: result), .downloadAlreadyActive)
        XCTAssertEqual(manager.activeDownloads.count, 1)
        XCTAssertEqual(manager.activeDownloads[download.sourceURL]?.book.id, 1002)
    }

    func testDownloadSnapshotsYieldInitialAndUpdatedState() async throws {
        let book = try makeDownloadableBook(id: 995, filenamePrefix: "snapshot")
        removeSavedFile(for: book, format: .EPUB)

        var iterator = manager.downloadSnapshots().makeAsyncIterator()
        let initial = await iterator.next()
        XCTAssertEqual(initial?.count, 0)

        let result = manager.startDownload(book, format: .EPUB, overwrite: true)
        guard case .success = result else {
            XCTFail("Expected download start to succeed")
            return
        }

        let updated = await iterator.next()
        XCTAssertEqual(updated?.values.first?.book.id, 995)
        XCTAssertEqual(updated?.values.first?.format, .EPUB)
        XCTAssertEqual(updated?.values.first?.isDownloading, true)
    }

    func testCancelDownloadClearsActiveStateAndResumeData() async throws {
        let book = try makeDownloadableBook(id: 1003)
        let download = try makeActiveDownload(book: book, format: .EPUB, isDownloading: true, resumeData: Data("resume".utf8))
        manager.activeDownloads[download.sourceURL] = download

        let snapshotTask = snapshotExpectation { snapshots in
            snapshots[download.sourceURL]?.isDownloading == false &&
            snapshots[download.sourceURL]?.progress == 0.0 &&
            snapshots[download.sourceURL]?.resumeData == nil
        }

        manager.cancelDownload(book, format: .EPUB)

        let snapshot = await snapshotTask.value
        XCTAssertEqual(snapshot?[download.sourceURL]?.book.id, 1003)
    }

    func testCancelDownloadDoesNothingForUnmatchedBookOrFormat() throws {
        let book = try makeDownloadableBook(id: 1004)
        let otherBook = try makeDownloadableBook(id: 1005)
        let download = try makeActiveDownload(book: book, format: .EPUB, isDownloading: true, progress: 0.4, resumeData: Data("resume".utf8))
        manager.activeDownloads[download.sourceURL] = download

        manager.cancelDownload(otherBook, format: .EPUB)
        manager.cancelDownload(book, format: .PDF)

        let active = manager.activeDownloads[download.sourceURL]
        XCTAssertEqual(active?.isDownloading, true)
        XCTAssertEqual(active?.progress, 0.4)
        XCTAssertEqual(active?.resumeData, Data("resume".utf8))
    }

    func testPauseDownloadStoresResumeDataAndStopsDownloading() async throws {
        let book = try makeDownloadableBook(id: 1006)
        let resumeData = Data("pause-resume-data".utf8)
        var download = try makeActiveDownload(book: book, format: .EPUB, isDownloading: true)
        download.downloadTask = StubDownloadTask(request: URLRequest(url: download.sourceURL), resumeData: resumeData)
        manager.activeDownloads[download.sourceURL] = download

        let snapshotTask = snapshotExpectation { snapshots in
            snapshots[download.sourceURL]?.isDownloading == false &&
            snapshots[download.sourceURL]?.resumeData == resumeData
        }

        manager.pauseDownload(book, format: .EPUB)

        let snapshot = await snapshotTask.value
        XCTAssertEqual(snapshot?[download.sourceURL]?.resumeData, resumeData)
        XCTAssertEqual(snapshot?[download.sourceURL]?.isPausing, false)
        XCTAssertEqual(snapshot?[download.sourceURL]?.isPaused, true)
    }

    func testPauseDownloadImmediatelyPublishesPausedActiveState() async throws {
        let book = try makeDownloadableBook(id: 1006, filenamePrefix: "pause-immediate")
        let downloadTask = StubDownloadTask(
            request: URLRequest(url: try downloadURL(for: book, format: .EPUB)),
            resumeData: Data("delayed-resume".utf8),
            completesPauseImmediately: false
        )
        var download = try makeActiveDownload(book: book, format: .EPUB, isDownloading: true)
        download.downloadTask = downloadTask
        manager.activeDownloads[download.sourceURL] = download

        let snapshotTask = snapshotExpectation { snapshots in
            snapshots[download.sourceURL]?.isDownloading == false &&
            snapshots[download.sourceURL]?.isPausing == true &&
            snapshots[download.sourceURL]?.isPaused == true &&
            snapshots[download.sourceURL]?.isActive == true
        }

        manager.pauseDownload(book, format: .EPUB)

        let snapshot = await snapshotTask.value
        XCTAssertNil(snapshot?[download.sourceURL]?.resumeData)

        downloadTask.completePause()
    }

    func testLatePauseDataCannotReactivateCancelledDownload() async throws {
        let book = try makeDownloadableBook(id: 1006, filenamePrefix: "pause-then-cancel")
        let task = StubDownloadTask(request: URLRequest(url: try downloadURL(for: book, format: .EPUB)),
            resumeData: Data("late-resume".utf8), completesPauseImmediately: false)
        var download = try makeActiveDownload(book: book, format: .EPUB, isDownloading: true)
        download.downloadTask = task
        manager.activeDownloads[download.sourceURL] = download
        manager.pauseDownload(book, format: .EPUB)
        manager.cancelDownload(book, format: .EPUB)
        task.completePause()
        await Task.yield()
        await Task.yield()
        XCTAssertEqual(manager.activeDownloads[download.sourceURL]?.completion, .cancelled)
        XCTAssertEqual(manager.activeDownloads[download.sourceURL]?.isActive, false)
        XCTAssertNil(manager.activeDownloads[download.sourceURL]?.resumeData)
    }

    func testPauseDownloadDoesNothingWhenNoActiveDownload() throws {
        let book = try makeDownloadableBook(id: 1007)
        let download = try makeActiveDownload(book: book, format: .EPUB, isDownloading: false, resumeData: Data("existing".utf8))
        manager.activeDownloads[download.sourceURL] = download

        manager.pauseDownload(book, format: .EPUB)

        XCTAssertEqual(manager.activeDownloads[download.sourceURL]?.isDownloading, false)
        XCTAssertEqual(manager.activeDownloads[download.sourceURL]?.resumeData, Data("existing".utf8))
    }

    func testPauseDownloadWithNilResumeDataKeepsPausedActiveState() async throws {
        let book = try makeDownloadableBook(id: 1007, filenamePrefix: "pause-nil")
        var download = try makeActiveDownload(book: book, format: .EPUB, isDownloading: true)
        download.downloadTask = StubDownloadTask(request: URLRequest(url: download.sourceURL), resumeData: nil)
        manager.activeDownloads[download.sourceURL] = download

        let snapshotTask = snapshotExpectation { snapshots in
            snapshots[download.sourceURL]?.isDownloading == false &&
            snapshots[download.sourceURL]?.isPausing == false &&
            snapshots[download.sourceURL]?.isPaused == true &&
            snapshots[download.sourceURL]?.resumeData == nil &&
            snapshots[download.sourceURL]?.isActive == true
        }

        manager.pauseDownload(book, format: .EPUB)

        let snapshot = await snapshotTask.value
        XCTAssertEqual(snapshot?[download.sourceURL]?.book.id, 1007)
    }

    func testResumeDownloadRestartsPausedDownloadAndClearsResumeData() throws {
        let book = try makeDownloadableBook(id: 1008)
        let download = try makeActiveDownload(book: book, format: .EPUB, isDownloading: false, isPaused: true, resumeData: validResumeData(for: book, format: .EPUB))
        manager.activeDownloads[download.sourceURL] = download

        let result = manager.resumeDownload(book, format: .EPUB)

        XCTAssertTrue(result)
        XCTAssertEqual(manager.activeDownloads[download.sourceURL]?.isDownloading, true)
        XCTAssertEqual(manager.activeDownloads[download.sourceURL]?.isPaused, false)
        XCTAssertEqual(manager.activeDownloads[download.sourceURL]?.isPausing, false)
        XCTAssertNil(manager.activeDownloads[download.sourceURL]?.resumeData)
        XCTAssertNotNil(manager.activeDownloads[download.sourceURL]?.downloadTask)
    }

    func testResumeDownloadRestartsPausedDownloadWithoutResumeDataFromSourceURL() throws {
        let book = try makeDownloadableBook(id: 1008, filenamePrefix: "resume-source")
        let download = try makeActiveDownload(book: book, format: .EPUB, isDownloading: false, isPaused: true, resumeData: nil)
        manager.activeDownloads[download.sourceURL] = download

        let result = manager.resumeDownload(book, format: .EPUB)

        XCTAssertTrue(result)
        XCTAssertEqual(manager.activeDownloads[download.sourceURL]?.isDownloading, true)
        XCTAssertEqual(manager.activeDownloads[download.sourceURL]?.isPaused, false)
        XCTAssertEqual(manager.activeDownloads[download.sourceURL]?.isPausing, false)
        XCTAssertNil(manager.activeDownloads[download.sourceURL]?.resumeData)
        XCTAssertNotNil(manager.activeDownloads[download.sourceURL]?.downloadTask)
    }

    func testResumeDownloadReturnsFalseWhenNoResumeData() throws {
        let book = try makeDownloadableBook(id: 1009)
        let download = try makeActiveDownload(book: book, format: .EPUB, isDownloading: false, resumeData: nil)
        manager.activeDownloads[download.sourceURL] = download

        let result = manager.resumeDownload(book, format: .EPUB)

        XCTAssertFalse(result)
        XCTAssertEqual(manager.activeDownloads[download.sourceURL]?.isDownloading, false)
    }

    func testDownloadProgress_publishesUpdates() async throws {
        let book = try makeDownloadableBook(id: 1011)
        let download = try makeActiveDownload(book: book, format: .EPUB, isDownloading: true, progress: 0.0)
        manager.activeDownloads[download.sourceURL] = download
        let delegate = BookFormatDownloadDelegate(download: download, manager: manager)

        let snapshotTask = snapshotExpectation {
            $0[download.sourceURL]?.progress == 0.5
        }

        let mockTask = URLSession(configuration: .default).downloadTask(with: download.sourceURL)
        delegate.urlSession(URLSession.shared, downloadTask: mockTask, didWriteData: 100, totalBytesWritten: 500, totalBytesExpectedToWrite: 1000)

        let snapshot = await snapshotTask.value
        XCTAssertEqual(snapshot?[download.sourceURL]?.progress, 0.5)
    }

    func testProgressCallbackFromBackgroundQueueUpdatesMainActorState() async throws {
        let book = try makeDownloadableBook(id: 1012)
        let download = try makeActiveDownload(book: book, format: .EPUB, isDownloading: true, progress: 0.0)
        manager.activeDownloads[download.sourceURL] = download
        let delegate = BookFormatDownloadDelegate(download: download, manager: manager)

        let snapshotTask = snapshotExpectation {
            $0[download.sourceURL]?.progress == 0.75
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let mockTask = URLSession(configuration: .default).downloadTask(with: download.sourceURL)
            delegate.urlSession(URLSession.shared, downloadTask: mockTask, didWriteData: 100, totalBytesWritten: 750, totalBytesExpectedToWrite: 1000)
        }

        let snapshot = await snapshotTask.value
        XCTAssertEqual(snapshot?[download.sourceURL]?.progress, 0.75)
    }

    func testDownloadCompletion_updatesState() async throws {
        let book = try makeDownloadableBook(id: 1013)
        let tempFileURL = try makeTempFile(name: "temp-success.epub", contents: Data("EPUB CONTENT".utf8))
        let download = try makeActiveDownload(book: book, format: .EPUB, isDownloading: true, progress: 0.0)
        manager.activeDownloads[download.sourceURL] = download
        removeSavedFile(for: book, format: .EPUB)

        let delegate = BookFormatDownloadDelegate(download: download, manager: manager)
        let calibreUpdateExpectation = expectation(description: "Download completion publishes calibre update")
        var calibreUpdatedBook: CalibreBook?

        let calibreUpdateTask = Task { @MainActor in
            for await signal in container.calibreUpdates() {
                if case .book(let book) = signal {
                    calibreUpdatedBook = book
                    calibreUpdateExpectation.fulfill()
                    break
                }
            }
        }
        await Task.yield()

        delegate.urlSession(URLSession.shared, downloadTask: StubDownloadTask(request: URLRequest(url: download.sourceURL)), didFinishDownloadingTo: tempFileURL)
        delegate.urlSession(URLSession.shared, task: StubTask(request: URLRequest(url: download.sourceURL), response: httpResponse(url: download.sourceURL, statusCode: 200)), didCompleteWithError: nil)

        await fulfillment(of: [calibreUpdateExpectation], timeout: 2.0)
        calibreUpdateTask.cancel()

        XCTAssertEqual(calibreUpdatedBook?.id, 1013)
        XCTAssertEqual(manager.activeDownloads[download.sourceURL]?.isDownloading, false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: download.savedURL.path))
    }

    func testCompletionCallbackFromBackgroundQueuePublishesSnapshotAndBookUpdate() async throws {
        let book = try makeDownloadableBook(id: 1014)
        let tempFileURL = try makeTempFile(name: "temp-background-success.epub", contents: Data("EPUB CONTENT".utf8))
        let download = try makeActiveDownload(book: book, format: .EPUB, isDownloading: true, progress: 0.0)
        manager.activeDownloads[download.sourceURL] = download
        removeSavedFile(for: book, format: .EPUB)

        let delegate = BookFormatDownloadDelegate(download: download, manager: manager)
        let calibreUpdateExpectation = expectation(description: "Background completion publishes calibre update")
        let snapshotTask = snapshotExpectation {
            $0[download.sourceURL]?.isDownloading == false &&
            $0[download.sourceURL]?.resumeData == nil
        }
        let calibreUpdateTask = Task { @MainActor in
            for await signal in container.calibreUpdates() {
                if case .book(let updatedBook) = signal, updatedBook.id == book.id {
                    calibreUpdateExpectation.fulfill()
                    break
                }
            }
        }
        await Task.yield()

        DispatchQueue.global(qos: .userInitiated).async {
            delegate.urlSession(URLSession.shared, downloadTask: StubDownloadTask(request: URLRequest(url: download.sourceURL)), didFinishDownloadingTo: tempFileURL)
            delegate.urlSession(URLSession.shared, task: StubTask(request: URLRequest(url: download.sourceURL), response: httpResponse(url: download.sourceURL, statusCode: 200)), didCompleteWithError: nil)
        }

        let snapshot = await snapshotTask.value
        await fulfillment(of: [calibreUpdateExpectation], timeout: 2.0)
        calibreUpdateTask.cancel()

        XCTAssertEqual(snapshot?[download.sourceURL]?.isDownloading, false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: download.savedURL.path))
    }

    func testDownloadFailureClearsDownloadingAndResumeDataWithoutPublishingSuccess() async throws {
        let book = try makeDownloadableBook(id: 1015)
        let download = try makeActiveDownload(book: book, format: .EPUB, isDownloading: true, resumeData: Data("resume".utf8))
        manager.activeDownloads[download.sourceURL] = download
        let delegate = BookFormatDownloadDelegate(download: download, manager: manager)

        let calibreUpdateExpectation = expectation(description: "Failed download does not publish calibre update")
        calibreUpdateExpectation.isInverted = true

        let calibreUpdateTask = Task { @MainActor in
            for await signal in container.calibreUpdates() {
                if case .book = signal {
                    calibreUpdateExpectation.fulfill()
                    break
                }
            }
        }
        await Task.yield()

        let snapshotTask = snapshotExpectation {
            $0[download.sourceURL]?.isDownloading == false &&
            $0[download.sourceURL]?.resumeData == nil
        }

        delegate.urlSession(
            URLSession.shared,
            task: StubTask(request: URLRequest(url: download.sourceURL), response: nil),
            didCompleteWithError: NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        )

        let snapshot = await snapshotTask.value
        await fulfillment(of: [calibreUpdateExpectation], timeout: 0.2)
        calibreUpdateTask.cancel()

        XCTAssertEqual(snapshot?[download.sourceURL]?.isDownloading, false)
        XCTAssertNil(snapshot?[download.sourceURL]?.resumeData)
    }

    func testDownloadCompletionWithNon2xxResponseDoesNotMarkCacheOrPublishDownloadedBook() async throws {
        let book = try makeDownloadableBook(id: 1016)
        let tempFileURL = try makeTempFile(name: "temp-non2xx.epub", contents: Data("EPUB CONTENT".utf8))
        let download = try makeActiveDownload(book: book, format: .EPUB, isDownloading: true)
        manager.activeDownloads[download.sourceURL] = download
        let delegate = BookFormatDownloadDelegate(download: download, manager: manager)

        let calibreUpdateExpectation = expectation(description: "Non-2xx completion does not publish calibre update")
        calibreUpdateExpectation.isInverted = true
        let calibreUpdateTask = Task { @MainActor in
            for await signal in container.calibreUpdates() {
                if case .book = signal {
                    calibreUpdateExpectation.fulfill()
                    break
                }
            }
        }
        await Task.yield()
        let snapshotTask = snapshotExpectation {
            $0[download.sourceURL]?.isDownloading == false &&
            $0[download.sourceURL]?.resumeData == nil
        }

        delegate.urlSession(URLSession.shared, downloadTask: StubDownloadTask(request: URLRequest(url: download.sourceURL)), didFinishDownloadingTo: tempFileURL)
        delegate.urlSession(URLSession.shared, task: StubTask(request: URLRequest(url: download.sourceURL), response: httpResponse(url: download.sourceURL, statusCode: 500)), didCompleteWithError: nil)

        _ = await snapshotTask.value
        await fulfillment(of: [calibreUpdateExpectation], timeout: 0.2)
        calibreUpdateTask.cancel()
        XCTAssertEqual(manager.activeDownloads[download.sourceURL]?.isDownloading, false)
    }

    func testDownloadCompletionWithEmptyMovedFileDoesNotPublishSuccess() async throws {
        let book = try makeDownloadableBook(id: 1017)
        let tempFileURL = try makeTempFile(name: "temp-empty.epub", contents: Data())
        let download = try makeActiveDownload(book: book, format: .EPUB, isDownloading: true)
        manager.activeDownloads[download.sourceURL] = download
        removeSavedFile(for: book, format: .EPUB)
        let delegate = BookFormatDownloadDelegate(download: download, manager: manager)

        let calibreUpdateExpectation = expectation(description: "Empty file completion does not publish calibre update")
        calibreUpdateExpectation.isInverted = true
        let calibreUpdateTask = Task { @MainActor in
            for await signal in container.calibreUpdates() {
                if case .book = signal {
                    calibreUpdateExpectation.fulfill()
                    break
                }
            }
        }
        await Task.yield()
        let snapshotTask = snapshotExpectation {
            $0[download.sourceURL]?.isDownloading == false
        }

        delegate.urlSession(URLSession.shared, downloadTask: StubDownloadTask(request: URLRequest(url: download.sourceURL)), didFinishDownloadingTo: tempFileURL)
        delegate.urlSession(URLSession.shared, task: StubTask(request: URLRequest(url: download.sourceURL), response: httpResponse(url: download.sourceURL, statusCode: 200)), didCompleteWithError: nil)

        _ = await snapshotTask.value
        await fulfillment(of: [calibreUpdateExpectation], timeout: 0.2)
        calibreUpdateTask.cancel()
        XCTAssertFalse(FileManager.default.fileExists(atPath: download.savedURL.path))
    }

    func testMultipleDownloadsTrackIndependentBooksAndFormats() throws {
        let firstBook = try makeDownloadableBook(id: 1018, formats: [.EPUB, .PDF])
        let secondBook = try makeDownloadableBook(id: 1019, formats: [.CBZ])
        let epubDownload = try makeActiveDownload(book: firstBook, format: .EPUB, isDownloading: true, progress: 0.1)
        let pdfDownload = try makeActiveDownload(book: firstBook, format: .PDF, isDownloading: true, progress: 0.2)
        let cbzDownload = try makeActiveDownload(book: secondBook, format: .CBZ, isDownloading: true, progress: 0.3)

        manager.activeDownloads[epubDownload.sourceURL] = epubDownload
        manager.activeDownloads[pdfDownload.sourceURL] = pdfDownload
        manager.activeDownloads[cbzDownload.sourceURL] = cbzDownload

        XCTAssertEqual(manager.activeDownloads.count, 3)
        XCTAssertEqual(manager.activeDownloads[epubDownload.sourceURL]?.format, .EPUB)
        XCTAssertEqual(manager.activeDownloads[pdfDownload.sourceURL]?.format, .PDF)
        XCTAssertEqual(manager.activeDownloads[cbzDownload.sourceURL]?.book.id, 1019)
    }

    func testCancelOneOfMultipleDownloadsDoesNotMutateOthers() throws {
        let firstBook = try makeDownloadableBook(id: 1018, formats: [.EPUB, .PDF])
        let secondBook = try makeDownloadableBook(id: 1019, formats: [.CBZ])
        let epubDownload = try makeActiveDownload(book: firstBook, format: .EPUB, isDownloading: true, progress: 0.1)
        let pdfDownload = try makeActiveDownload(book: firstBook, format: .PDF, isDownloading: true, progress: 0.2)
        let cbzDownload = try makeActiveDownload(book: secondBook, format: .CBZ, isDownloading: true, progress: 0.3)
        manager.activeDownloads[epubDownload.sourceURL] = epubDownload
        manager.activeDownloads[pdfDownload.sourceURL] = pdfDownload
        manager.activeDownloads[cbzDownload.sourceURL] = cbzDownload

        manager.cancelDownload(firstBook, format: .PDF)

        XCTAssertEqual(manager.activeDownloads[epubDownload.sourceURL]?.isDownloading, true)
        XCTAssertEqual(manager.activeDownloads[epubDownload.sourceURL]?.progress, 0.1)
        XCTAssertEqual(manager.activeDownloads[pdfDownload.sourceURL]?.isDownloading, false)
        XCTAssertEqual(manager.activeDownloads[pdfDownload.sourceURL]?.progress, 0.0)
        XCTAssertEqual(manager.activeDownloads[cbzDownload.sourceURL]?.isDownloading, true)
        XCTAssertEqual(manager.activeDownloads[cbzDownload.sourceURL]?.progress, 0.3)
    }

    func testProgressForOneDownloadDoesNotAffectOtherActiveDownloads() async throws {
        let firstBook = try makeDownloadableBook(id: 1018, formats: [.EPUB])
        let secondBook = try makeDownloadableBook(id: 1019, formats: [.CBZ])
        let firstDownload = try makeActiveDownload(book: firstBook, format: .EPUB, isDownloading: true, progress: 0.1)
        let secondDownload = try makeActiveDownload(book: secondBook, format: .CBZ, isDownloading: true, progress: 0.3)
        manager.activeDownloads[firstDownload.sourceURL] = firstDownload
        manager.activeDownloads[secondDownload.sourceURL] = secondDownload
        let delegate = BookFormatDownloadDelegate(download: firstDownload, manager: manager)

        let snapshotTask = snapshotExpectation {
            $0[firstDownload.sourceURL]?.progress == 0.6 &&
            $0[secondDownload.sourceURL]?.progress == 0.3
        }

        delegate.urlSession(
            URLSession.shared,
            downloadTask: StubDownloadTask(request: URLRequest(url: firstDownload.sourceURL)),
            didWriteData: 100,
            totalBytesWritten: 600,
            totalBytesExpectedToWrite: 1000
        )

        let snapshot = await snapshotTask.value
        XCTAssertEqual(snapshot?[firstDownload.sourceURL]?.progress, 0.6)
        XCTAssertEqual(snapshot?[secondDownload.sourceURL]?.progress, 0.3)
    }

    func testIsFormatDownloaded_checksLocalFile() throws {
        let book = try makeDownloadableBook(id: 1020)
        guard let savedURL = getSavedUrl(book: book, format: .EPUB) else {
            return XCTFail("Failed to resolve saved URL")
        }

        try? FileManager.default.removeItem(at: savedURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: savedURL.path))

        try Data("EPUB CONTENT".utf8).write(to: savedURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedURL.path))
    }

    func testAutomaticDownloadDoesNotRestartFailedOrCancelledAttempts() throws {
        let book = try makeDownloadableBook(id: 1020)
        for outcome in [BookFormatDownload.Completion.failed("HTTP 503"), .cancelled] {
            var download = try makeActiveDownload(book: book, format: .EPUB, isDownloading: false)
            download.completion = outcome
            manager.activeDownloads[download.sourceURL] = download
            manager.requestAutomaticDownload(book: book, format: .EPUB)
            XCTAssertEqual(manager.activeDownloads[download.sourceURL]?.id, download.id)
            XCTAssertEqual(manager.activeDownloads[download.sourceURL]?.completion, outcome)
            XCTAssertNil(manager.activeDownloads[download.sourceURL]?.downloadTask)
        }
    }

    func testAutomaticDownloadDoesNotResumePausedAttemptButAllowsAnotherFormat() throws {
        let book = try makeDownloadableBook(id: 1020, formats: [.EPUB, .PDF])
        let paused = try makeActiveDownload(book: book, format: .EPUB, isDownloading: false, isPaused: true)
        manager.activeDownloads[paused.sourceURL] = paused
        manager.requestAutomaticDownload(book: book, format: .EPUB)
        XCTAssertEqual(manager.activeDownloads[paused.sourceURL]?.id, paused.id)
        XCTAssertTrue(manager.activeDownloads[paused.sourceURL]?.isPaused == true)
        manager.requestAutomaticDownload(book: book, format: .PDF)
        XCTAssertTrue(manager.activeDownloads.values.contains { $0.format == .PDF && $0.isActive })
        manager.cancelDownload(book, format: .PDF)
    }

    func testExplicitDownloadCanRetryAfterSuppressedAutomaticRequest() throws {
        let book = try makeDownloadableBook(id: 1020)
        removeSavedFile(for: book, format: .EPUB)
        var failed = try makeActiveDownload(book: book, format: .EPUB, isDownloading: false)
        failed.completion = .failed("HTTP 503")
        manager.activeDownloads[failed.sourceURL] = failed
        manager.requestAutomaticDownload(book: book, format: .EPUB)
        XCTAssertEqual(manager.activeDownloads[failed.sourceURL]?.id, failed.id)
        XCTAssertNil(downloadStartError(from: manager.startDownload(book, format: .EPUB, overwrite: true)))
        XCTAssertNotEqual(manager.activeDownloads[failed.sourceURL]?.id, failed.id)
        manager.cancelDownload(book, format: .EPUB)
    }

    func testBatchDownloadRestartsTerminalAttemptsForSelectedFormats() throws {
        let book = try makeRemoteBatchBook(reachable: true)
        for outcome in [BookFormatDownload.Completion.succeeded, .failed("HTTP 503"), .cancelled] {
            var previous = try makeActiveDownload(book: book, format: .EPUB, isDownloading: false)
            previous.completion = outcome
            manager.activeDownloads[previous.sourceURL] = previous

            manager.startBatchDownload(books: [book], formats: ["EPUB"])

            let attempt = try XCTUnwrap(manager.activeDownloads[previous.sourceURL])
            XCTAssertNotEqual(attempt.id, previous.id, "A batch download should retry \(outcome)")
            XCTAssertTrue(attempt.isDownloading)
            XCTAssertEqual(container.bookRepository.getBook(id: book.inShelfId)?.formats["EPUB"]?.selected, true)
            XCTAssertFalse(manager.activeDownloads.values.contains { $0.format == .PDF })
            manager.startBatchDownload(books: [book], formats: ["EPUB"])
            XCTAssertEqual(manager.activeDownloads[previous.sourceURL]?.id, attempt.id)
            manager.cancelDownload(book, format: .EPUB)
        }
    }

    func testOfflineBatchRetryWaitsForShelfToResumeAtReconnect() throws {
        let book = try makeRemoteBatchBook(reachable: false)
        var previous = try makeActiveDownload(book: book, format: .EPUB, isDownloading: false)
        previous.completion = .failed("Offline")
        manager.activeDownloads[previous.sourceURL] = previous

        manager.startBatchDownload(books: [book], formats: ["EPUB"])

        XCTAssertNil(manager.activeDownloads[previous.sourceURL])
        let queued = try XCTUnwrap(container.bookRepository.getBook(id: book.inShelfId))
        XCTAssertEqual(queued.formats["EPUB"]?.selected, true)
        container.calibreServerInfoStaging[book.library.server.id]?.reachable = true
        manager.requestAutomaticDownload(book: queued, format: .EPUB)
        XCTAssertEqual(manager.activeDownloads[previous.sourceURL]?.isDownloading, true)
        manager.cancelDownload(book, format: .EPUB)
    }

    func testSuccessfulDownloadAtomicallyReplacesExistingCache() async throws {
        let book = try makeDownloadableBook(id: 1020)
        let download = try makeActiveDownload(book: book, format: .EPUB, isDownloading: true)
        manager.activeDownloads[download.sourceURL] = download
        try Data("Original EPUB".utf8).write(to: download.savedURL)
        let temporary = try makeTempFile(name: "bd3-replacement", contents: Data("Updated EPUB".utf8))
        defer { try? FileManager.default.removeItem(at: temporary) }
        let delegate = BookFormatDownloadDelegate(download: download, manager: manager)
        let snapshot = snapshotExpectation { $0[download.sourceURL]?.completion == .succeeded }
        delegate.urlSession(URLSession.shared, downloadTask: StubDownloadTask(request: URLRequest(url: download.sourceURL)), didFinishDownloadingTo: temporary)
        XCTAssertEqual(try Data(contentsOf: download.savedURL), Data("Original EPUB".utf8))
        delegate.urlSession(URLSession.shared, task: StubTask(request: URLRequest(url: download.sourceURL),
            response: httpResponse(url: download.sourceURL, statusCode: 200)), didCompleteWithError: nil)
        _ = await snapshot.value
        XCTAssertEqual(try Data(contentsOf: download.savedURL), Data("Updated EPUB".utf8))
    }

    func testFailedDownloadCannotReplaceExistingCachedFile() async throws {
        let book = try makeDownloadableBook(id: 1020)
        let download = try makeActiveDownload(book: book, format: .EPUB, isDownloading: true)
        manager.activeDownloads[download.sourceURL] = download
        try Data("Original EPUB".utf8).write(to: download.savedURL)
        let temporary = try makeTempFile(name: "bd3-http-error", contents: Data("HTTP Error".utf8))
        defer { try? FileManager.default.removeItem(at: temporary) }
        let delegate = BookFormatDownloadDelegate(download: download, manager: manager)
        delegate.urlSession(URLSession.shared, downloadTask: StubDownloadTask(request: URLRequest(url: download.sourceURL)), didFinishDownloadingTo: temporary)
        delegate.urlSession(URLSession.shared, task: StubTask(request: URLRequest(url: download.sourceURL),
            response: httpResponse(url: download.sourceURL, statusCode: 503)), didCompleteWithError: nil)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(try Data(contentsOf: download.savedURL), Data("Original EPUB".utf8))
    }

    func testCancelledDownloadCannotRecreateClearedFileFromLateFileCallback() async throws {
        let book = try makeDownloadableBook(id: 1020)
        let download = try makeActiveDownload(book: book, format: .EPUB, isDownloading: true)
        manager.activeDownloads[download.sourceURL] = download
        manager.cancelDownload(book, format: .EPUB)
        removeSavedFile(for: book, format: .EPUB)
        let temporary = try makeTempFile(name: "bd3-cancelled-late", contents: Data("Late EPUB".utf8))
        defer { try? FileManager.default.removeItem(at: temporary) }
        let delegate = BookFormatDownloadDelegate(download: download, manager: manager)
        delegate.urlSession(URLSession.shared, downloadTask: StubDownloadTask(request: URLRequest(url: download.sourceURL)), didFinishDownloadingTo: temporary)
        delegate.urlSession(URLSession.shared, task: StubTask(request: URLRequest(url: download.sourceURL),
            response: httpResponse(url: download.sourceURL, statusCode: 200)), didCompleteWithError: nil)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertFalse(FileManager.default.fileExists(atPath: download.savedURL.path))
        XCTAssertEqual(manager.activeDownloads[download.sourceURL]?.completion, .cancelled)
    }

    private func makeRemoteBatchBook(reachable: Bool) throws -> CalibreBook {
        let library = TestFixtures.makeLibrary(key: UUID().uuidString)
        let server = library.server
        container.calibreLibraries[library.id] = library
        let request = CalibreProbeServerRequest(server: server, isPublic: false,
            updateLibrary: false, autoUpdateOnly: false)
        container.calibreServerInfoStaging[server.id] = CalibreServerInfo(
            server: server, isPublic: false, url: try XCTUnwrap(URL(string: server.baseUrl)),
            reachable: reachable, probing: false, errorMsg: "",
            defaultLibrary: library.id, libraryMap: [library.id: library.name], request: request)
        let book = try makeDownloadableBook(id: 1020, formats: [.EPUB, .PDF], library: library)
        let url = try XCTUnwrap(getSavedUrl(book: book, format: .EPUB))
        addTeardownBlock { [container] in
            container?.bookRepository.deleteBook(id: book.inShelfId)
            try? FileManager.default.removeItem(at: url)
        }
        return book
    }

    private func makeDownloadableBook(
        id: Int32,
        formats: [Format] = [.EPUB],
        filenamePrefix: String = "test",
        library: CalibreLibrary? = nil
    ) throws -> CalibreBook {
        let library = try library ?? XCTUnwrap(container.libraryManager.calibreLibraries.first?.value)
        var book = CalibreBook(id: id, library: library)
        book.title = "Download Test \(id)"
        for format in formats {
            book.formats[format.rawValue] = Self.formatInfo(filename: "\(filenamePrefix)-\(id).\(format.ext)")
        }
        return book
    }

    private func makeActiveDownload(
        book: CalibreBook,
        format: Format,
        isDownloading: Bool,
        isPaused: Bool = false,
        isPausing: Bool = false,
        progress: Float = 0.0,
        resumeData: Data? = nil
    ) throws -> BookFormatDownload {
        let sourceURL = try downloadURL(for: book, format: format)
        let savedURL = try XCTUnwrap(getSavedUrl(book: book, format: format))
        return BookFormatDownload(
            isDownloading: isDownloading,
            isPaused: isPaused,
            isPausing: isPausing,
            progress: progress,
            resumeData: resumeData,
            book: book,
            format: format,
            startDatetime: Date(),
            sourceURL: sourceURL,
            savedURL: savedURL,
            modificationDate: book.formats[format.rawValue]?.serverMTime ?? Date()
        )
    }

    private func downloadURL(for book: CalibreBook, format: Format) throws -> URL {
        try XCTUnwrap(URL(string: book.library.server.serverUrl)?
            .appendingPathComponent("get", isDirectory: true)
            .appendingPathComponent(format.rawValue, isDirectory: true)
            .appendingPathComponent(book.id.description, isDirectory: true)
            .appendingPathComponent(book.library.key, isDirectory: false))
    }

    private func removeSavedFile(for book: CalibreBook, format: Format) {
        guard let savedURL = getSavedUrl(book: book, format: format) else { return }
        try? FileManager.default.removeItem(at: savedURL)
    }

    private func makeTempFile(name: String, contents: Data) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
        try contents.write(to: url)
        return url
    }

    private func snapshotExpectation(
        matching predicate: @escaping ([URL: BookFormatDownload]) -> Bool
    ) -> Task<[URL: BookFormatDownload]?, Never> {
        Task {
            for await snapshot in manager.downloadSnapshots() {
                if predicate(snapshot) {
                    return snapshot
                }
            }
            return nil
        }
    }

    private func validResumeData(for book: CalibreBook, format: Format) throws -> Data {
        let url = try downloadURL(for: book, format: format)
        let resumeInfo: [String: Any] = [
            "NSURLSessionResumeInfoVersion": 2,
            "NSURLSessionResumeBytesReceived": 1,
            "NSURLSessionResumeCurrentRequest": try NSKeyedArchiver.archivedData(withRootObject: URLRequest(url: url), requiringSecureCoding: true),
            "NSURLSessionResumeOriginalRequest": try NSKeyedArchiver.archivedData(withRootObject: URLRequest(url: url), requiringSecureCoding: true),
            "NSURLSessionResumeInfoTempFileName": "resume-\(book.id)-\(format.rawValue)"
        ]
        return try PropertyListSerialization.data(fromPropertyList: resumeInfo, format: .binary, options: 0)
    }

    private static func formatInfo(filename: String) -> FormatInfo {
        FormatInfo(
            selected: nil,
            filename: filename,
            serverSize: 1000,
            serverMTime: Date(),
            cached: false,
            cacheSize: 0,
            cacheMTime: Date(),
            manifest: nil
        )
    }

    private func downloadStartError(from result: Result<Void, DownloadStartError>) -> DownloadStartError? {
        if case .failure(let error) = result {
            return error
        }
        return nil
    }
}

private func httpResponse(url: URL, statusCode: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
}

private final class StubTask: URLSessionTask, @unchecked Sendable {
    private let stubRequest: URLRequest?
    private let stubResponse: URLResponse?

    override var originalRequest: URLRequest? { stubRequest }
    override var response: URLResponse? { stubResponse }

    init(request: URLRequest?, response: URLResponse?) {
        self.stubRequest = request
        self.stubResponse = response
        super.init()
    }
}

private final class StubDownloadTask: URLSessionDownloadTask, @unchecked Sendable {
    private let stubRequest: URLRequest?
    private let stubResponse: URLResponse?
    private let stubResumeData: Data?
    private let completesPauseImmediately: Bool
    private var pauseCompletionHandler: ((Data?) -> Void)?

    override var originalRequest: URLRequest? { stubRequest }
    override var response: URLResponse? { stubResponse }
    override func cancel() {}

    init(request: URLRequest?, response: URLResponse? = nil, resumeData: Data? = nil, completesPauseImmediately: Bool = true) {
        self.stubRequest = request
        self.stubResponse = response
        self.stubResumeData = resumeData
        self.completesPauseImmediately = completesPauseImmediately
        super.init()
    }

    override func cancel(byProducingResumeData completionHandler: @escaping (Data?) -> Void) {
        if completesPauseImmediately {
            completionHandler(stubResumeData)
        } else {
            pauseCompletionHandler = completionHandler
        }
    }

    func completePause() {
        pauseCompletionHandler?(stubResumeData)
        pauseCompletionHandler = nil
    }
}


private final class FailingDownloadFileManager: FileManager, @unchecked Sendable {
    var failAttributes = false
    var failedDestination: URL?

    override func setAttributes(_ attributes: [FileAttributeKey: Any], ofItemAtPath path: String) throws {
        if failAttributes { throw CocoaError(.fileWriteNoPermission) }
        try super.setAttributes(attributes, ofItemAtPath: path)
    }

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        if dstURL == failedDestination { throw CocoaError(.fileWriteNoPermission) }
        try super.moveItem(at: srcURL, to: dstURL)
    }
}
