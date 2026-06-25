//
//  TestFixtures.swift
//  YetAnotherEBookReaderTests
//
//  Created by Antigravity on 2026-06-23.
//

import Foundation
@testable import YetAnotherEBookReader

enum TestFixtures {
    static func makeServer(
        uuid: UUID = UUID(),
        name: String = "Test Server",
        baseUrl: String = "http://localhost",
        hasPublicUrl: Bool = false,
        publicUrl: String = "",
        hasAuth: Bool = false,
        username: String = "",
        password: String = ""
    ) -> CalibreServer {
        return CalibreServer(
            uuid: uuid,
            name: name,
            baseUrl: baseUrl,
            hasPublicUrl: hasPublicUrl,
            publicUrl: publicUrl,
            hasAuth: hasAuth,
            username: username,
            password: password
        )
    }

    static func makeLibrary(
        server: CalibreServer? = nil,
        key: String = "test_lib",
        name: String = "Test Library"
    ) -> CalibreLibrary {
        let actualServer = server ?? makeServer()
        return CalibreLibrary(
            server: actualServer,
            key: key,
            name: name
        )
    }

    static func makeBook(
        id: Int32 = 1,
        library: CalibreLibrary? = nil
    ) -> CalibreBook {
        let actualLibrary = library ?? makeLibrary()
        return CalibreBook(
            id: id,
            library: actualLibrary
        )
    }

    static func makeReadingPosition(
        id: String = "test-device",
        readerName: String = "YabrEPUB",
        maxPage: Int = 100,
        lastReadPage: Int = 1,
        lastReadChapter: String = "Chapter 1",
        lastChapterProgress: Double = 0.0,
        lastProgress: Double = 0.0,
        furthestReadPage: Int = 1,
        furthestReadChapter: String = "Chapter 1",
        lastPosition: [Int] = [0, 0, 0],
        cfi: String = "/",
        epoch: Double = Date().timeIntervalSince1970
    ) -> BookDeviceReadingPosition {
        return BookDeviceReadingPosition(
            id: id,
            readerName: readerName,
            maxPage: maxPage,
            lastReadPage: lastReadPage,
            lastReadChapter: lastReadChapter,
            lastChapterProgress: lastChapterProgress,
            lastProgress: lastProgress,
            furthestReadPage: furthestReadPage,
            furthestReadChapter: furthestReadChapter,
            lastPosition: lastPosition,
            cfi: cfi,
            epoch: epoch
        )
    }

    static func makeHighlight(
        id: String = UUID().uuidString,
        bookId: String = "1^test_lib@server-uuid",
        readerName: String = "YabrEPUB",
        page: Int = 1,
        startOffset: Int = 0,
        endOffset: Int = 10,
        date: Date = Date(),
        type: Int = 0,
        note: String? = nil,
        tocFamilyTitles: [String] = [],
        content: String = "Highlight content",
        contentPost: String = "",
        contentPre: String = "",
        cfiStart: String? = nil,
        cfiEnd: String? = nil,
        spineName: String? = nil,
        ranges: String? = nil,
        removed: Bool = false
    ) -> BookHighlight {
        return BookHighlight(
            id: id,
            bookId: bookId,
            readerName: readerName,
            page: page,
            startOffset: startOffset,
            endOffset: endOffset,
            date: date,
            type: type,
            note: note,
            tocFamilyTitles: tocFamilyTitles,
            content: content,
            contentPost: contentPost,
            contentPre: contentPre,
            cfiStart: cfiStart,
            cfiEnd: cfiEnd,
            spineName: spineName,
            ranges: ranges,
            removed: removed
        )
    }

    static func makeBookmark(
        id: String = UUID().uuidString,
        bookId: String = "1^test_lib@server-uuid",
        page: Int = 1,
        pos_type: String = "epubcfi",
        pos: String = "/6/4[chap-1]!/4/2/10/1:0",
        title: String = "Bookmark 1",
        date: Date = Date(),
        removed: Bool = false
    ) -> BookBookmark {
        return BookBookmark(
            id: id,
            bookId: bookId,
            page: page,
            pos_type: pos_type,
            pos: pos,
            title: title,
            date: date,
            removed: removed
        )
    }

    /// Populate a AppContainer (already initialized with `AppContainer(mock: true)`)
    /// with a single mock book and a matching reading position. Extracted from
    /// the previous `AppContainer.init(mock:)` body so it can be reused by tests
    /// and previews without keeping ~65 lines of fixture construction inline.
    static func populateAppContainerWithMockBook(_ container: AppContainer) {
        let library = container.libraryManager.calibreLibraries.first!.value

        var book = CalibreBook(id: 1, library: library)
        book.title = "Mock Book Title"

        book.formats[Format.EPUB.rawValue] = .init(
            filename: book.title + ".epub",
            serverSize: 1024000,
            serverMTime: Date(timeIntervalSince1970: 1645495322),
            cached: true,
            cacheSize: 1024000,
            cacheMTime: Date(timeIntervalSince1970: 1645495322),
            manifest: nil
        )
        if let bookSavedUrl = getSavedUrl(book: book, format: Format.EPUB),
           FileManager.default.fileExists(atPath: bookSavedUrl.path) == false {
            FileManager.default.createFile(atPath: bookSavedUrl.path, contents: String("EPUB").data(using: .utf8), attributes: nil)
        }

        var position = BookDeviceReadingPosition(
            id: container.deviceName,
            readerName: ReaderType.YabrEPUB.rawValue,
            maxPage: 99,
            lastReadPage: 1,
            lastReadChapter: "Mock Last Chapter",
            lastChapterProgress: 5,
            lastProgress: 1,
            furthestReadPage: 98,
            furthestReadChapter: "Mock Furthest Chapter",
            lastPosition: [1, 1, 1]
        )
        position.epoch = 1645495322

        container.readingPositionRepository.savePosition(position, forBookId: book.bookPrefId)
        container.bookManager.readingBook = book
        container.bookManager.booksInShelf[book.inShelfId] = book
    }
}
