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
    private var modelData: ModelData!
    private var manager: BookDownloadManager!
    private var cancellables: Set<AnyCancellable>!
    private var originalModelDataShared: ModelData?
    
    override func setUpWithError() throws {
        originalModelDataShared = ModelData.shared
        modelData = ModelData(mock: true)
        ModelData.shared = modelData
        
        manager = BookDownloadManager(modelData: modelData, realmConf: modelData.realmConf)
        
        let testConfiguration = URLSessionConfiguration.ephemeral
        testConfiguration.protocolClasses = [MockURLProtocol.self]
        manager.sessionConfiguration = testConfiguration
        
        cancellables = []
        
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("MockDownloadData".utf8))
        }
    }
    
    override func tearDownWithError() throws {
        // Clean up any downloaded books from Document Directory
        if let library = modelData?.calibreLibraries.first?.value {
            let mockBook = CalibreBook(id: 999, library: library)
            if let savedUrl = getSavedUrl(book: mockBook, format: .EPUB) {
                try? FileManager.default.removeItem(at: savedUrl)
            }
        }
        
        ModelData.shared = originalModelDataShared
        manager = nil
        modelData = nil
        cancellables = nil
        MockURLProtocol.requestHandler = nil
    }
    
    func testStartDownload_addsToActiveDownloads() throws {
        let library = try XCTUnwrap(modelData.libraryManager.calibreLibraries.first?.value)
        var book = CalibreBook(id: 999, library: library)
        book.title = "Start Download Test"
        book.formats[Format.EPUB.rawValue] = FormatInfo(selected: nil, filename: "test.epub", serverSize: 1000, serverMTime: Date(), cached: false, cacheSize: 0, cacheMTime: Date(), manifest: nil)
        
        // Ensure file does not exist
        if let savedUrl = getSavedUrl(book: book, format: .EPUB) {
            try? FileManager.default.removeItem(at: savedUrl)
        }
        
        let result = manager.startDownloadNew(book, format: .EPUB, overwrite: true)
        
        switch result {
        case .success:
            XCTAssertEqual(manager.activeDownloads.count, 1)
            let download = manager.activeDownloads.values.first
            XCTAssertNotNil(download)
            XCTAssertEqual(download?.book.id, 999)
            XCTAssertEqual(download?.format, .EPUB)
            XCTAssertTrue(download?.isDownloading ?? false)
        case .failure(let error):
            XCTFail("Failed to start download: \(error.localizedDescription)")
        }
    }
    
    func testCancelDownload_removesFromActive() throws {
        let library = try XCTUnwrap(modelData.libraryManager.calibreLibraries.first?.value)
        var book = CalibreBook(id: 999, library: library)
        book.formats[Format.EPUB.rawValue] = FormatInfo(selected: nil, filename: "test.epub", serverSize: 1000, serverMTime: Date(), cached: false, cacheSize: 0, cacheMTime: Date(), manifest: nil)
        
        _ = manager.startDownloadNew(book, format: .EPUB, overwrite: true)
        XCTAssertEqual(manager.activeDownloads.values.filter({ $0.isDownloading }).count, 1)
        
        manager.cancelDownload(book, format: .EPUB)
        
        let active = manager.activeDownloads.values.first
        XCTAssertEqual(active?.isDownloading, false)
        XCTAssertEqual(active?.progress, 0.0)
    }
    
    func testDownloadProgress_publishesUpdates() throws {
        let library = try XCTUnwrap(modelData.libraryManager.calibreLibraries.first?.value)
        let book = CalibreBook(id: 999, library: library)
        let url = URL(string: "http://localhost/download")!
        let savedUrl = URL(fileURLWithPath: "/tmp/mock_saved_file")
        
        let download = BookFormatDownload(
            isDownloading: true,
            progress: 0.0,
            book: book,
            format: .EPUB,
            startDatetime: Date(),
            sourceURL: url,
            savedURL: savedUrl,
            modificationDate: Date()
        )
        
        manager.activeDownloads[url] = download
        let delegate = BookFormatDownloadDelegate(download: download, manager: manager)
        
        let expectation = self.expectation(description: "Progress updated on main queue")
        
        // Trigger progress callback
        let mockTask = URLSession(configuration: .default).downloadTask(with: url)
        delegate.urlSession(URLSession.shared, downloadTask: mockTask, didWriteData: 100, totalBytesWritten: 500, totalBytesExpectedToWrite: 1000)
        
        // Check progress asynchronously because delegate updates on DispatchQueue.main
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let updatedDownload = self.manager.activeDownloads[url]
            XCTAssertEqual(updatedDownload?.progress, 0.5)
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0)
    }
    
    func testDownloadCompletion_updatesState() throws {
        let library = try XCTUnwrap(modelData.libraryManager.calibreLibraries.first?.value)
        var book = CalibreBook(id: 999, library: library)
        book.formats[Format.EPUB.rawValue] = FormatInfo(selected: nil, filename: "test.epub", serverSize: 1000, serverMTime: Date(), cached: false, cacheSize: 0, cacheMTime: Date(), manifest: nil)
        
        let url = URL(string: "http://localhost/download")!
        let tempFileUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("temp_test_file.epub")
        try Data("EPUB CONTENT".utf8).write(to: tempFileUrl)
        
        guard let savedUrl = getSavedUrl(book: book, format: .EPUB) else {
            XCTFail("Failed to resolve saved URL")
            return
        }
        try? FileManager.default.removeItem(at: savedUrl)
        
        let download = BookFormatDownload(
            isDownloading: true,
            progress: 0.0,
            book: book,
            format: .EPUB,
            startDatetime: Date(),
            sourceURL: url,
            savedURL: savedUrl,
            modificationDate: Date()
        )
        manager.activeDownloads[url] = download
        
        let delegate = BookFormatDownloadDelegate(download: download, manager: manager)
        
        let expectation = self.expectation(description: "Download completion triggered")
        var bookDownloaded: CalibreBook?
        
        manager.bookDownloadedSubject.sink { downloadedBook in
            bookDownloaded = downloadedBook
            expectation.fulfill()
        }.store(in: &cancellables)
        
        // 1. Simulate file finished downloading
        delegate.urlSession(URLSession.shared, downloadTask: URLSession.shared.downloadTask(with: url), didFinishDownloadingTo: tempFileUrl)
        
        // 2. Simulate task completion with 200 HTTP response
        let httpResponse = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        
        class StubTask: URLSessionTask {
            private let stubResponse: URLResponse?
            override var response: URLResponse? { stubResponse }
            init(response: URLResponse?) {
                self.stubResponse = response
                super.init()
            }
        }
        let stubTask = StubTask(response: httpResponse)
        delegate.urlSession(URLSession.shared, task: stubTask, didCompleteWithError: nil)
        
        waitForExpectations(timeout: 2.0)
        
        XCTAssertEqual(bookDownloaded?.id, 999)
        let updatedDownload = manager.activeDownloads[url]
        XCTAssertEqual(updatedDownload?.isDownloading, false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedUrl.path))
    }
    
    func testDownloadFailure_setsErrorState() throws {
        let library = try XCTUnwrap(modelData.libraryManager.calibreLibraries.first?.value)
        var book = CalibreBook(id: 999, library: library)
        book.formats[Format.EPUB.rawValue] = FormatInfo(selected: nil, filename: "test.epub", serverSize: 1000, serverMTime: Date(), cached: false, cacheSize: 0, cacheMTime: Date(), manifest: nil)
        
        let url = URL(string: "http://localhost/download")!
        let savedUrl = URL(fileURLWithPath: "/tmp/non_existent_path")
        
        let download = BookFormatDownload(
            isDownloading: true,
            progress: 0.0,
            book: book,
            format: .EPUB,
            startDatetime: Date(),
            sourceURL: url,
            savedURL: savedUrl,
            modificationDate: Date()
        )
        manager.activeDownloads[url] = download
        
        let delegate = BookFormatDownloadDelegate(download: download, manager: manager)
        
        let mockTask = URLSession.shared.downloadTask(with: url)
        
        let expectation = self.expectation(description: "Failure processed on main queue")
        
        delegate.urlSession(URLSession.shared, task: mockTask, didCompleteWithError: NSError(domain: "NSURLErrorDomain", code: -1009, userInfo: nil))
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let updated = self.manager.activeDownloads[url]
            XCTAssertEqual(updated?.isDownloading, false)
            XCTAssertNil(updated?.resumeData)
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 1.0)
    }
    
    func testIsFormatDownloaded_checksLocalFile() throws {
        let library = try XCTUnwrap(modelData.libraryManager.calibreLibraries.first?.value)
        var book = CalibreBook(id: 999, library: library)
        book.formats[Format.EPUB.rawValue] = FormatInfo(selected: nil, filename: "test.epub", serverSize: 1000, serverMTime: Date(), cached: false, cacheSize: 0, cacheMTime: Date(), manifest: nil)
        
        guard let savedUrl = getSavedUrl(book: book, format: .EPUB) else {
            XCTFail("Failed to resolve saved URL")
            return
        }
        
        try? FileManager.default.removeItem(at: savedUrl)
        XCTAssertFalse(FileManager.default.fileExists(atPath: savedUrl.path))
        
        // Write mock file
        try Data("EPUB CONTENT".utf8).write(to: savedUrl)
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedUrl.path))
    }
}
