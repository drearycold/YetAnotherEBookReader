//
//  BookDownloadManagerTests.swift
//  YetAnotherEBookReaderTests
//
//  Created by Antigravity on 2026-06-24.
//

import XCTest
import Combine
import RealmSwift
@testable import YetAnotherEBookReader

final class BookDownloadManagerTests: XCTestCase {
    private var container: AppContainer!
    private var manager: BookDownloadManager!
    private var cancellables: Set<AnyCancellable>!

    override func setUpWithError() throws {
        container = MockAppContainerFactory.makeContainer(testName: "BookDownloadManagerTests")
        AppContainer.shared = container

        manager = BookDownloadManager(container: container, realmConf: container.realmConf)

        let testConfiguration = URLSessionConfiguration.ephemeral
        testConfiguration.protocolClasses = [MockURLProtocol.self]
        manager.sessionConfiguration = testConfiguration

        cancellables = []

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
        cancellables = nil
        MockURLProtocol.requestHandler = nil
    }

    func testStartDownload_addsToActiveDownloads() throws {
        let book = try makeDownloadableBook(id: 999)
        removeSavedFile(for: book, format: .EPUB)

        let result = manager.startDownloadNew(book, format: .EPUB, overwrite: true)

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

        let result = manager.startDownloadNew(book, format: .EPUB)

        XCTAssertEqual(downloadStartError(from: result), .missingFormatInfo)
        XCTAssertTrue(manager.activeDownloads.isEmpty)
    }

    func testStartDownloadRejectsExistingFileWithoutOverwrite() throws {
        let book = try makeDownloadableBook(id: 1001)
        guard let savedURL = getSavedUrl(book: book, format: .EPUB) else {
            return XCTFail("Expected saved URL")
        }
        try Data("existing".utf8).write(to: savedURL)

        let result = manager.startDownloadNew(book, format: .EPUB, overwrite: false)

        XCTAssertEqual(downloadStartError(from: result), .fileAlreadyExists)
        XCTAssertTrue(manager.activeDownloads.isEmpty)
    }

    func testStartDownloadRejectsDuplicateActiveDownload() throws {
        let book = try makeDownloadableBook(id: 1002)
        let download = try makeActiveDownload(book: book, format: .EPUB, isDownloading: true)
        manager.activeDownloads[download.sourceURL] = download

        let result = manager.startDownloadNew(book, format: .EPUB, overwrite: false)

        XCTAssertEqual(downloadStartError(from: result), .downloadAlreadyActive)
        XCTAssertEqual(manager.activeDownloads.count, 1)
        XCTAssertEqual(manager.activeDownloads[download.sourceURL]?.book.id, 1002)
    }

    func testLegacyBookFormatDownloadSubjectRequestsDownload() throws {
        let book = try makeDownloadableBook(id: 997, filenamePrefix: "legacy")
        removeSavedFile(for: book, format: .EPUB)

        let expectation = expectation(description: "Legacy download subject starts request")
        manager.$activeDownloads
            .dropFirst()
            .sink { downloads in
                if downloads.values.contains(where: { $0.book.id == 997 && $0.format == .EPUB }) {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        manager.bookFormatDownloadSubject.send((book: book, format: .EPUB))

        waitForExpectations(timeout: 1.0)
    }

    func testDownloadSnapshotsYieldInitialAndUpdatedState() async throws {
        let book = try makeDownloadableBook(id: 995, filenamePrefix: "snapshot")
        removeSavedFile(for: book, format: .EPUB)

        var iterator = manager.downloadSnapshots().makeAsyncIterator()
        let initial = await iterator.next()
        XCTAssertEqual(initial?.count, 0)

        let result = manager.startDownloadNew(book, format: .EPUB, overwrite: true)
        guard case .success = result else {
            XCTFail("Expected download start to succeed")
            return
        }

        let updated = await iterator.next()
        XCTAssertEqual(updated?.values.first?.book.id, 995)
        XCTAssertEqual(updated?.values.first?.format, .EPUB)
        XCTAssertEqual(updated?.values.first?.isDownloading, true)
    }

    func testManualBookDownloadedSubjectDoesNotPublishCalibreUpdate() async throws {
        let book = try makeDownloadableBook(id: 996)
        let invertedExpectation = expectation(description: "Manual legacy download subject does not publish calibre update")
        invertedExpectation.isInverted = true

        let task = Task { @MainActor in
            for await signal in container.calibreUpdates() {
                if case .book = signal {
                    invertedExpectation.fulfill()
                    break
                }
            }
        }

        await Task.yield()
        manager.bookDownloadedSubject.send(book)

        await fulfillment(of: [invertedExpectation], timeout: 0.2)
        task.cancel()
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
    }

    func testPauseDownloadDoesNothingWhenNoActiveDownload() throws {
        let book = try makeDownloadableBook(id: 1007)
        let download = try makeActiveDownload(book: book, format: .EPUB, isDownloading: false, resumeData: Data("existing".utf8))
        manager.activeDownloads[download.sourceURL] = download

        manager.pauseDownload(book, format: .EPUB)

        XCTAssertEqual(manager.activeDownloads[download.sourceURL]?.isDownloading, false)
        XCTAssertEqual(manager.activeDownloads[download.sourceURL]?.resumeData, Data("existing".utf8))
    }

    func testResumeDownloadRestartsPausedDownloadAndClearsResumeData() throws {
        let book = try makeDownloadableBook(id: 1008)
        let download = try makeActiveDownload(book: book, format: .EPUB, isDownloading: false, resumeData: validResumeData(for: book, format: .EPUB))
        manager.activeDownloads[download.sourceURL] = download

        let result = manager.resumeDownload(book, format: .EPUB)

        XCTAssertTrue(result)
        XCTAssertEqual(manager.activeDownloads[download.sourceURL]?.isDownloading, true)
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
        let legacyExpectation = expectation(description: "Legacy download completion triggered")
        let calibreUpdateExpectation = expectation(description: "Download completion publishes calibre update")
        var bookDownloaded: CalibreBook?
        var calibreUpdatedBook: CalibreBook?

        manager.bookDownloadedSubject.sink { downloadedBook in
            bookDownloaded = downloadedBook
            legacyExpectation.fulfill()
        }.store(in: &cancellables)

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

        await fulfillment(of: [legacyExpectation, calibreUpdateExpectation], timeout: 2.0)
        calibreUpdateTask.cancel()

        XCTAssertEqual(bookDownloaded?.id, 1013)
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

        let legacyExpectation = expectation(description: "Failed download does not publish legacy success")
        legacyExpectation.isInverted = true
        let calibreUpdateExpectation = expectation(description: "Failed download does not publish calibre update")
        calibreUpdateExpectation.isInverted = true

        manager.bookDownloadedSubject.sink { _ in
            legacyExpectation.fulfill()
        }.store(in: &cancellables)
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
        await fulfillment(of: [legacyExpectation, calibreUpdateExpectation], timeout: 0.2)
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

        let legacyExpectation = expectation(description: "Non-2xx completion does not publish legacy success")
        legacyExpectation.isInverted = true
        manager.bookDownloadedSubject.sink { _ in
            legacyExpectation.fulfill()
        }.store(in: &cancellables)
        let snapshotTask = snapshotExpectation {
            $0[download.sourceURL]?.isDownloading == false &&
            $0[download.sourceURL]?.resumeData == nil
        }

        delegate.urlSession(URLSession.shared, downloadTask: StubDownloadTask(request: URLRequest(url: download.sourceURL)), didFinishDownloadingTo: tempFileURL)
        delegate.urlSession(URLSession.shared, task: StubTask(request: URLRequest(url: download.sourceURL), response: httpResponse(url: download.sourceURL, statusCode: 500)), didCompleteWithError: nil)

        _ = await snapshotTask.value
        await fulfillment(of: [legacyExpectation], timeout: 0.2)
        XCTAssertEqual(manager.activeDownloads[download.sourceURL]?.isDownloading, false)
    }

    func testDownloadCompletionWithEmptyMovedFileDoesNotPublishSuccess() async throws {
        let book = try makeDownloadableBook(id: 1017)
        let tempFileURL = try makeTempFile(name: "temp-empty.epub", contents: Data())
        let download = try makeActiveDownload(book: book, format: .EPUB, isDownloading: true)
        manager.activeDownloads[download.sourceURL] = download
        removeSavedFile(for: book, format: .EPUB)
        let delegate = BookFormatDownloadDelegate(download: download, manager: manager)

        let legacyExpectation = expectation(description: "Empty file completion does not publish legacy success")
        legacyExpectation.isInverted = true
        manager.bookDownloadedSubject.sink { _ in
            legacyExpectation.fulfill()
        }.store(in: &cancellables)
        let snapshotTask = snapshotExpectation {
            $0[download.sourceURL]?.isDownloading == false
        }

        delegate.urlSession(URLSession.shared, downloadTask: StubDownloadTask(request: URLRequest(url: download.sourceURL)), didFinishDownloadingTo: tempFileURL)
        delegate.urlSession(URLSession.shared, task: StubTask(request: URLRequest(url: download.sourceURL), response: httpResponse(url: download.sourceURL, statusCode: 200)), didCompleteWithError: nil)

        _ = await snapshotTask.value
        await fulfillment(of: [legacyExpectation], timeout: 0.2)
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

    private func makeDownloadableBook(
        id: Int32,
        formats: [Format] = [.EPUB],
        filenamePrefix: String = "test"
    ) throws -> CalibreBook {
        let library = try XCTUnwrap(container.libraryManager.calibreLibraries.first?.value)
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
        progress: Float = 0.0,
        resumeData: Data? = nil
    ) throws -> BookFormatDownload {
        let sourceURL = try downloadURL(for: book, format: format)
        let savedURL = try XCTUnwrap(getSavedUrl(book: book, format: format))
        return BookFormatDownload(
            isDownloading: isDownloading,
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

    override var originalRequest: URLRequest? { stubRequest }
    override var response: URLResponse? { stubResponse }

    init(request: URLRequest?, response: URLResponse? = nil, resumeData: Data? = nil) {
        self.stubRequest = request
        self.stubResponse = response
        self.stubResumeData = resumeData
        super.init()
    }

    override func cancel(byProducingResumeData completionHandler: @escaping (Data?) -> Void) {
        completionHandler(stubResumeData)
    }
}
