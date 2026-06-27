//
//  MockRepositories.swift
//  YetAnotherEBookReaderTests
//
//  Created by Antigravity on 2026-06-23.
//

import Foundation
import Combine
@testable import YetAnotherEBookReader

class MockServerRepository: ServerRepositoryProtocol {
    var getAllServersCalled = false
    var getAllServersReturn: [CalibreServer] = []
    
    var saveServerCalled = false
    var saveServerParam: CalibreServer?
    var saveServerError: Error?
    
    var deleteServerCalled = false
    var deleteServerIdParam: String?
    var deleteServerError: Error?
    
    var getDSReaderHelperCalled = false
    var getDSReaderHelperServerIdParam: String?
    var getDSReaderHelperReturn: CalibreServerDSReaderHelper?
    
    var saveDSReaderHelperCalled = false
    var saveDSReaderHelperParam: CalibreServerDSReaderHelper?
    var saveDSReaderHelperServerIdParam: String?
    var saveDSReaderHelperError: Error?
    
    func getAllServers() -> [CalibreServer] {
        getAllServersCalled = true
        return getAllServersReturn
    }
    
    func saveServer(_ server: CalibreServer) throws {
        saveServerCalled = true
        saveServerParam = server
        if let error = saveServerError {
            throw error
        }
    }
    
    func deleteServer(id: String) throws {
        deleteServerCalled = true
        deleteServerIdParam = id
        if let error = deleteServerError {
            throw error
        }
    }
    
    func getDSReaderHelper(for serverId: String) -> CalibreServerDSReaderHelper? {
        getDSReaderHelperCalled = true
        getDSReaderHelperServerIdParam = serverId
        return getDSReaderHelperReturn
    }
    
    func saveDSReaderHelper(_ helper: CalibreServerDSReaderHelper, for serverId: String) throws {
        saveDSReaderHelperCalled = true
        saveDSReaderHelperParam = helper
        saveDSReaderHelperServerIdParam = serverId
        if let error = saveDSReaderHelperError {
            throw error
        }
    }
}

class MockLibraryRepository: LibraryRepositoryProtocol {
    var getAllLibrariesCalled = false
    var getAllLibrariesReturn: [CalibreLibrary] = []
    
    var saveLibraryCalled = false
    var saveLibraryParam: CalibreLibrary?
    var saveLibraryError: Error?
    
    var deleteLibraryCalled = false
    var deleteLibraryServerUUIDParam: String?
    var deleteLibraryNameParam: String?
    var deleteLibraryError: Error?
    
    var countBooksCalled = false
    var countBooksParam: CalibreLibrary?
    var countBooksReturn: Int = 0

    var getLibraryCalled = false
    var getLibraryIdParam: String?
    var getLibraryReturn: CalibreLibrary?

    var observeLibraryCalled = false
    var observeLibraryIdParam: String?
    var observeLibrarySubject = PassthroughSubject<CalibreLibrary?, Never>()

    var updateLibraryFlagsCalled = false
    var updateLibraryFlagsIdParam: String?
    var updateLibraryFlagsDiscoverableParam: Bool?
    var updateLibraryFlagsAutoUpdateParam: Bool?
    var updateLibraryFlagsError: Error?
    
    func getAllLibraries() -> [CalibreLibrary] {
        getAllLibrariesCalled = true
        return getAllLibrariesReturn
    }
    
    func saveLibrary(_ library: CalibreLibrary) throws {
        saveLibraryCalled = true
        saveLibraryParam = library
        if let error = saveLibraryError {
            throw error
        }
    }
    
    func deleteLibrary(serverUUID: String, name: String) throws {
        deleteLibraryCalled = true
        deleteLibraryServerUUIDParam = serverUUID
        deleteLibraryNameParam = name
        if let error = deleteLibraryError {
            throw error
        }
    }
    
    func countBooks(for library: CalibreLibrary) -> Int {
        countBooksCalled = true
        countBooksParam = library
        return countBooksReturn
    }

    func getLibrary(id: String) -> CalibreLibrary? {
        getLibraryCalled = true
        getLibraryIdParam = id
        return getLibraryReturn
    }

    func observeLibrary(id: String) -> AnyPublisher<CalibreLibrary?, Never> {
        observeLibraryCalled = true
        observeLibraryIdParam = id
        return observeLibrarySubject.prepend(getLibraryReturn).eraseToAnyPublisher()
    }

    func updateLibraryFlags(id: String, discoverable: Bool, autoUpdate: Bool) throws {
        updateLibraryFlagsCalled = true
        updateLibraryFlagsIdParam = id
        updateLibraryFlagsDiscoverableParam = discoverable
        updateLibraryFlagsAutoUpdateParam = autoUpdate
        if let error = updateLibraryFlagsError {
            throw error
        }
    }
}

class MockBookRepository: BookRepositoryProtocol {
    var getBookCalled = false
    var getBookIdParam: String?
    var getBookReturn: CalibreBook?
    
    var saveBookCalled = false
    var saveBookParam: CalibreBook?
    
    var deleteBookCalled = false
    var deleteBookIdParam: String?
    
    var getAllBooksInShelfCalled = false
    var getAllBooksInShelfReturn: [CalibreBook] = []
    
    var bookExistsCalled = false
    var bookExistsIdParam: String?
    var bookExistsReturn: Bool = false
    
    var bulkUpdateBooksCalled = false
    var bulkUpdateBooksParam: [[String: Any]]?
    
    var findDeletedBookIdsCalled = false
    var findDeletedBookIdsServerUUIDParam: String?
    var findDeletedBookIdsLibraryNameParam: String?
    var findDeletedBookIdsActiveIdsParam: [String: Any]?
    var findDeletedBookIdsReturn: [Int32] = []
    
    var countAndNeedUpdateBooksCalled = false
    var countAndNeedUpdateBooksServerUUIDParam: String?
    var countAndNeedUpdateBooksLibraryNameParam: String?
    var countAndNeedUpdateBooksReturn: (count: Int, needUpdateIds: [Int32]) = (0, [])
    
    var getBookRealmCalled = false
    var getBookRealmIdParam: String?
    var getBookRealmReturn: CalibreBookRealm?

    var observeBookCalled = false
    var observeBookIdParam: String?
    var observeBookSubject = PassthroughSubject<CalibreBook?, Never>()

    #if DEBUG
    var resetBooksCalled = false
    var resetBooksServerUUIDParam: String?
    var resetBooksLibraryNameParam: String?
    #endif
    
    func getBook(id: String) -> CalibreBook? {
        getBookCalled = true
        getBookIdParam = id
        return getBookReturn
    }
    
    func saveBook(_ book: CalibreBook) {
        saveBookCalled = true
        saveBookParam = book
    }

    func observeBook(id: String) -> AnyPublisher<CalibreBook?, Never> {
        observeBookCalled = true
        observeBookIdParam = id
        return observeBookSubject.prepend(getBookReturn).eraseToAnyPublisher()
    }
    
    func deleteBook(id: String) {
        deleteBookCalled = true
        deleteBookIdParam = id
    }
    
    func getAllBooksInShelf() -> [CalibreBook] {
        getAllBooksInShelfCalled = true
        return getAllBooksInShelfReturn
    }
    
    func bookExists(id: String) -> Bool {
        bookExistsCalled = true
        bookExistsIdParam = id
        return bookExistsReturn
    }
    
    func bulkUpdateBooks(records: [[String : Any]]) {
        bulkUpdateBooksCalled = true
        bulkUpdateBooksParam = records
    }
    
    func findDeletedBookIds(serverUUID: String, libraryName: String, activeIds: [String : Any]) -> [Int32] {
        findDeletedBookIdsCalled = true
        findDeletedBookIdsServerUUIDParam = serverUUID
        findDeletedBookIdsLibraryNameParam = libraryName
        findDeletedBookIdsActiveIdsParam = activeIds
        return findDeletedBookIdsReturn
    }
    
    func countAndNeedUpdateBooks(serverUUID: String, libraryName: String) -> (count: Int, needUpdateIds: [Int32]) {
        countAndNeedUpdateBooksCalled = true
        countAndNeedUpdateBooksServerUUIDParam = serverUUID
        countAndNeedUpdateBooksLibraryNameParam = libraryName
        return countAndNeedUpdateBooksReturn
    }
    
    func getBookRealm(id: String) -> CalibreBookRealm? {
        getBookRealmCalled = true
        getBookRealmIdParam = id
        return getBookRealmReturn
    }

    #if DEBUG
    func resetBooks(serverUUID: String, libraryName: String) {
        resetBooksCalled = true
        resetBooksServerUUIDParam = serverUUID
        resetBooksLibraryNameParam = libraryName
    }
    #endif
}

class MockReadingPositionRepository: ReadingPositionRepositoryProtocol, @unchecked Sendable {
    var getPositionCalled = false
    var getPositionBookIdParam: String?
    var getPositionPolicyParam: ReadingPositionSelectionPolicy?
    var getPositionReturn: BookDeviceReadingPosition?
    
    var getPositionsCalled = false
    var getPositionsBookIdParam: String?
    var getPositionsReturn: [BookDeviceReadingPosition] = []
    
    var savePositionCalled = false
    var savePositionParam: BookDeviceReadingPosition?
    var savePositionBookIdParam: String?
    
    var removePositionDeviceCalled = false
    var removePositionDeviceNameParam: String?
    var removePositionBookIdParam: String?
    
    var removePositionObjCalled = false
    var removePositionObjParam: BookDeviceReadingPosition?
    var removePositionObjBookIdParam: String?
    
    var createInitialCalled = false
    var createInitialDeviceNameParam: String?
    var createInitialReaderParam: ReaderType?
    var createInitialReturn: BookDeviceReadingPosition?
    
    var sessionsCalled = false
    var sessionsBookIdParam: String?
    var sessionsStartDateAfterParam: Date?
    var sessionsReturn: [BookDeviceReadingPositionHistory] = []
    
    var sessionStartCalled = false
    var sessionStartReadPositionParam: BookDeviceReadingPosition?
    var sessionStartBookIdParam: String?
    var sessionStartReturn: Date?
    
    var sessionEndCalled = false
    var sessionEndReadPositionParam: BookDeviceReadingPosition?
    var sessionEndBookIdParam: String?
    
    var syncPositionsCalled = false
    var syncPositionsEntriesParam: [CalibreBookLastReadPositionEntry]?
    var syncPositionsBookIdParam: String?
    var syncPositionsReturn: [CalibreBookLastReadPositionEntry] = []

    var debugPositionsCalled = false
    var debugPositionsBookIdParam: String?
    var debugPositionsReturn: [BookDeviceReadingPosition] = []

    var historyBookCalled = false
    var historyBookLibraryParam: CalibreLibrary?
    var historyBookIdParam: Int32?
    var historyBookReturn: CalibreBook?
    
    func getPosition(forBookId bookId: String, policy: ReadingPositionSelectionPolicy) -> BookDeviceReadingPosition? {
        getPositionCalled = true
        getPositionBookIdParam = bookId
        getPositionPolicyParam = policy
        return getPositionReturn
    }
    
    func getPositions(forBookId bookId: String) -> [BookDeviceReadingPosition] {
        getPositionsCalled = true
        getPositionsBookIdParam = bookId
        return getPositionsReturn
    }

    func debugPositions(forBookId bookId: String) -> [BookDeviceReadingPosition] {
        debugPositionsCalled = true
        debugPositionsBookIdParam = bookId
        return debugPositionsReturn
    }

    func historyBook(for library: CalibreLibrary, bookId: Int32) -> CalibreBook? {
        historyBookCalled = true
        historyBookLibraryParam = library
        historyBookIdParam = bookId
        return historyBookReturn
    }
    
    func savePosition(_ position: BookDeviceReadingPosition, forBookId bookId: String) {
        savePositionCalled = true
        savePositionParam = position
        savePositionBookIdParam = bookId
    }
    
    func removePosition(deviceName: String, forBookId bookId: String) {
        removePositionDeviceCalled = true
        removePositionDeviceNameParam = deviceName
        removePositionBookIdParam = bookId
    }
    
    func removePosition(position: BookDeviceReadingPosition, forBookId bookId: String) {
        removePositionObjCalled = true
        removePositionObjParam = position
        removePositionObjBookIdParam = bookId
    }
    
    func createInitial(deviceName: String, reader: ReaderType) -> BookDeviceReadingPosition {
        createInitialCalled = true
        createInitialDeviceNameParam = deviceName
        createInitialReaderParam = reader
        return createInitialReturn ?? TestFixtures.makeReadingPosition(id: deviceName, readerName: reader.rawValue)
    }
    
    func sessions(forBookId bookId: String, list startDateAfter: Date?) -> [BookDeviceReadingPositionHistory] {
        sessionsCalled = true
        sessionsBookIdParam = bookId
        sessionsStartDateAfterParam = startDateAfter
        return sessionsReturn
    }
    
    func session(start readPosition: BookDeviceReadingPosition, forBookId bookId: String) -> Date? {
        sessionStartCalled = true
        sessionStartReadPositionParam = readPosition
        sessionStartBookIdParam = bookId
        return sessionStartReturn
    }
    
    func session(end readPosition: BookDeviceReadingPosition, forBookId bookId: String) {
        sessionEndCalled = true
        sessionEndReadPositionParam = readPosition
        sessionEndBookIdParam = bookId
    }
    
    func syncPositions(entries lastReadPositions: [CalibreBookLastReadPositionEntry], forBookId bookId: String) -> [CalibreBookLastReadPositionEntry] {
        syncPositionsCalled = true
        syncPositionsEntriesParam = lastReadPositions
        syncPositionsBookIdParam = bookId
        return syncPositionsReturn
    }
}

class MockAnnotationRepository: AnnotationRepositoryProtocol {
    var getBookmarksCalled = false
    var getBookmarksBookIdParam: String?
    var getBookmarksExcludeRemovedParam: Bool?
    var getBookmarksReturn: [BookBookmark] = []
    
    var getBookmarkCalled = false
    var getBookmarkPosParam: String?
    var getBookmarkBookIdParam: String?
    var getBookmarkReturn: BookBookmark?
    
    var saveBookmarkCalled = false
    var saveBookmarkParam: BookBookmark?
    var saveBookmarkReturn: (Int, String?) = (0, nil)
    
    var removeBookmarkCalled = false
    var removeBookmarkPosParam: String?
    var removeBookmarkBookIdParam: String?
    
    var getHighlightsCalled = false
    var getHighlightsBookIdParam: String?
    var getHighlightsExcludeRemovedParam: Bool?
    var getHighlightsReturn: [BookHighlight] = []
    
    var getHighlightCalled = false
    var getHighlightIdParam: String?
    var getHighlightReturn: BookHighlight?
    
    var saveHighlightCalled = false
    var saveHighlightParam: BookHighlight?
    
    var removeHighlightCalled = false
    var removeHighlightIdParam: String?
    
    var updateHighlightNoteCalled = false
    var updateHighlightNoteIdParam: String?
    var updateHighlightNoteTextParam: String?
    
    var syncBookmarksCalled = false
    var syncBookmarksEntriesParam: [CalibreBookAnnotationBookmarkEntry]?
    var syncBookmarksBookIdParam: String?
    var syncBookmarksReturn: Int = 0
    
    var syncHighlightsCalled = false
    var syncHighlightsEntriesParam: [CalibreBookAnnotationHighlightEntry]?
    var syncHighlightsBookIdParam: String?
    var syncHighlightsReturn: Int = 0
    
    func getBookmarks(forBookId bookId: String, excludeRemoved: Bool) -> [BookBookmark] {
        getBookmarksCalled = true
        getBookmarksBookIdParam = bookId
        getBookmarksExcludeRemovedParam = excludeRemoved
        return getBookmarksReturn
    }
    
    func getBookmark(byPos pos: String, bookId: String) -> BookBookmark? {
        getBookmarkCalled = true
        getBookmarkPosParam = pos
        getBookmarkBookIdParam = bookId
        return getBookmarkReturn
    }
    
    func saveBookmark(_ bookmark: BookBookmark) -> (Int, String?) {
        saveBookmarkCalled = true
        saveBookmarkParam = bookmark
        return saveBookmarkReturn
    }
    
    func removeBookmark(pos: String, bookId: String) {
        removeBookmarkCalled = true
        removeBookmarkPosParam = pos
        removeBookmarkBookIdParam = bookId
    }
    
    func getHighlights(forBookId bookId: String, excludeRemoved: Bool) -> [BookHighlight] {
        getHighlightsCalled = true
        getHighlightsBookIdParam = bookId
        getHighlightsExcludeRemovedParam = excludeRemoved
        return getHighlightsReturn
    }
    
    func getHighlight(byId id: String) -> BookHighlight? {
        getHighlightCalled = true
        getHighlightIdParam = id
        return getHighlightReturn
    }
    
    func saveHighlight(_ highlight: BookHighlight) {
        saveHighlightCalled = true
        saveHighlightParam = highlight
    }
    
    func removeHighlight(id: String) {
        removeHighlightCalled = true
        removeHighlightIdParam = id
    }
    
    func updateHighlightNote(id: String, note: String?) {
        updateHighlightNoteCalled = true
        updateHighlightNoteIdParam = id
        updateHighlightNoteTextParam = note
    }
    
    func syncBookmarks(entries: [CalibreBookAnnotationBookmarkEntry], forBookId bookId: String) -> Int {
        syncBookmarksCalled = true
        syncBookmarksEntriesParam = entries
        syncBookmarksBookIdParam = bookId
        return syncBookmarksReturn
    }
    
    func syncHighlights(entries: [CalibreBookAnnotationHighlightEntry], forBookId bookId: String) -> Int {
        syncHighlightsCalled = true
        syncHighlightsEntriesParam = entries
        syncHighlightsBookIdParam = bookId
        return syncHighlightsReturn
    }
}

final class MockActivityLogRepository: ActivityLogRepositoryProtocol {
    var fetchEntriesCalled = false
    var fetchEntriesLibraryIdParam: String?
    var fetchEntriesBookIdParam: Int32?
    var fetchEntriesSinceParam: Date?
    var fetchEntriesReturn: [ActivityLogUIEntry] = []

    var observeEntriesCalled = false
    var observeEntriesLibraryIdParam: String?
    var observeEntriesBookIdParam: Int32?
    var observeEntriesSinceParam: Date?
    let observeEntriesSubject = PassthroughSubject<[ActivityLogUIEntry], Never>()

    func fetchEntries(libraryId: String?, bookId: Int32?, since: Date) -> [ActivityLogUIEntry] {
        fetchEntriesCalled = true
        fetchEntriesLibraryIdParam = libraryId
        fetchEntriesBookIdParam = bookId
        fetchEntriesSinceParam = since
        return fetchEntriesReturn
    }

    func observeEntries(libraryId: String?, bookId: Int32?, since: Date) -> AnyPublisher<[ActivityLogUIEntry], Never> {
        observeEntriesCalled = true
        observeEntriesLibraryIdParam = libraryId
        observeEntriesBookIdParam = bookId
        observeEntriesSinceParam = since
        return observeEntriesSubject.prepend(fetchEntriesReturn).eraseToAnyPublisher()
    }
}

final class MockFolioReaderProfileRepository: FolioReaderProfileRepositoryProtocol {
    var ensureDefaultProfileCalled = false
    var ensureDefaultProfileParam: FolioReaderProfileValue?

    var loadProfileCalled = false
    var loadProfileNameParam: String?
    var loadProfileDefaultsParam: FolioReaderProfileValue?
    var loadProfileReturn: FolioReaderProfileValue?

    var saveProfileCalled = false
    var saveProfileParam: FolioReaderProfileValue?
    var saveProfileNameParam: String?

    var listProfilesCalled = false
    var listProfilesFilterParam: String?
    var listProfilesDefaultsParam: FolioReaderProfileValue?
    var listProfilesReturn: [String] = ["Default"]

    var removeProfileCalled = false
    var removeProfileNameParam: String?

    func ensureDefaultProfile(defaults: FolioReaderProfileValue) {
        ensureDefaultProfileCalled = true
        ensureDefaultProfileParam = defaults
    }

    func loadProfile(named name: String, defaults: FolioReaderProfileValue) -> FolioReaderProfileValue? {
        loadProfileCalled = true
        loadProfileNameParam = name
        loadProfileDefaultsParam = defaults
        return loadProfileReturn
    }

    func saveProfile(_ profile: FolioReaderProfileValue, named name: String) {
        saveProfileCalled = true
        saveProfileParam = profile
        saveProfileNameParam = name
    }

    func listProfiles(filter: String?, defaults: FolioReaderProfileValue) -> [String] {
        listProfilesCalled = true
        listProfilesFilterParam = filter
        listProfilesDefaultsParam = defaults
        return listProfilesReturn
    }

    func removeProfile(named name: String) {
        removeProfileCalled = true
        removeProfileNameParam = name
    }
}

final class MockCategoryCacheRepository: CategoryCacheRepository, @unchecked Sendable {
    var cache: [String: LibraryCategoryResult] = [:]

    var invalidateCategoryCacheCalled = false
    var invalidateCategoryCacheParams: [(libraryId: String, categoryName: String)] = []

    var observeCategorySummariesCalled = false
    let observeCategorySummariesSubject = PassthroughSubject<[CategoryCacheSummary], Never>()

    var observeCategoryCacheUpdatesCalled = false
    var observeCategoryCacheUpdatesCategoryNameParam: String?
    var observeCategoryCacheUpdatesSubjects: [String: PassthroughSubject<Void, Never>] = [:]

    func fetchLibraryCategoryResult(libraryId: String, categoryName: String) throws -> LibraryCategoryResult? {
        cache["\(libraryId)-\(categoryName)"]
    }

    func saveLibraryCategoryResult(libraryId: String, categoryName: String, result: LibraryCategoryResult) throws {
        cache["\(libraryId)-\(categoryName)"] = result
    }

    func fetchCategorySummaries() throws -> [CategoryCacheSummary] {
        var summariesByName: [String: (itemsCount: Int, totalNumber: Int)] = [:]
        for result in cache.values {
            let name = result.categoryName
            let current = summariesByName[name] ?? (0, 0)
            summariesByName[name] = (
                current.itemsCount + result.items.count,
                current.totalNumber + result.totalNumber
            )
        }
        return summariesByName.map { name, stats in
            CategoryCacheSummary(
                categoryName: name,
                itemsCount: stats.itemsCount,
                totalNumber: stats.totalNumber
            )
        }.sorted { $0.categoryName < $1.categoryName }
    }

    func observeCategorySummaries() -> AnyPublisher<[CategoryCacheSummary], Never> {
        observeCategorySummariesCalled = true
        let initial = (try? fetchCategorySummaries()) ?? []
        return observeCategorySummariesSubject.prepend(initial).eraseToAnyPublisher()
    }

    func observeCategoryCacheUpdates(categoryName: String) -> AnyPublisher<Void, Never> {
        observeCategoryCacheUpdatesCalled = true
        observeCategoryCacheUpdatesCategoryNameParam = categoryName
        let subject = observeCategoryCacheUpdatesSubjects[categoryName] ?? {
            let newSubject = PassthroughSubject<Void, Never>()
            observeCategoryCacheUpdatesSubjects[categoryName] = newSubject
            return newSubject
        }()
        return subject.eraseToAnyPublisher()
    }

    func invalidateCategoryCache(libraryId: String, categoryName: String) throws {
        invalidateCategoryCacheCalled = true
        invalidateCategoryCacheParams.append((libraryId, categoryName))
        if let result = cache["\(libraryId)-\(categoryName)"] {
            let staleResult = LibraryCategoryResult(
                libraryId: result.libraryId,
                categoryName: result.categoryName,
                items: result.items,
                generation: Date(timeIntervalSince1970: 0),
                totalNumber: result.totalNumber
            )
            cache["\(libraryId)-\(categoryName)"] = staleResult
        }
    }

    func sendCategorySummaries(_ summaries: [CategoryCacheSummary]) {
        observeCategorySummariesSubject.send(summaries)
    }

    func sendCategoryCacheUpdate(categoryName: String) {
        observeCategoryCacheUpdatesSubjects[categoryName]?.send(())
    }
}
