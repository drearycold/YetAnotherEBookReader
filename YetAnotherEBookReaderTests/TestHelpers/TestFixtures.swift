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
}
