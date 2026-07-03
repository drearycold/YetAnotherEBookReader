//
//  MockRepositories.swift
//  YetAnotherEBookReaderTests
//
//  Created by Antigravity on 2026-06-23.
//

import Foundation
@testable import YetAnotherEBookReader

final class TestAsyncStreamBroadcaster<Element> {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]

    var subscriberCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return continuations.count
    }

    func stream() -> AsyncStream<Element> {
        makeStream(initialValue: nil)
    }

    func stream(initialValue: Element) -> AsyncStream<Element> {
        makeStream(initialValue: initialValue)
    }

    private func makeStream(initialValue: Element?) -> AsyncStream<Element> {
        AsyncStream { continuation in
            let id = UUID()
            if let initialValue {
                continuation.yield(initialValue)
            }
            lock.lock()
            continuations[id] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                self?.lock.lock()
                self?.continuations.removeValue(forKey: id)
                self?.lock.unlock()
            }
        }
    }

    func send(_ value: Element) {
        lock.lock()
        let currentContinuations = Array(continuations.values)
        lock.unlock()
        for continuation in currentContinuations {
            continuation.yield(value)
        }
    }
}

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
    private let observeLibraryBroadcaster = TestAsyncStreamBroadcaster<CalibreLibrary?>()
    var observeLibrarySubscriberCount: Int {
        observeLibraryBroadcaster.subscriberCount
    }

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

    func observeLibrary(id: String) -> AsyncStream<CalibreLibrary?> {
        observeLibraryCalled = true
        observeLibraryIdParam = id
        return observeLibraryBroadcaster.stream(initialValue: getLibraryReturn)
    }

    func sendObservedLibrary(_ library: CalibreLibrary?) {
        observeLibraryBroadcaster.send(library)
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
    var primaryKeyBookParam: CalibreBook?
    var primaryKeyLibraryParam: CalibreLibrary?
    var primaryKeyBookIdParam: Int32?

    var getBookCalled = false
    var getBookIdParam: String?
    var getBookLibraryParam: CalibreLibrary?
    var getBookBookIdParam: Int32?
    var getBookReturn: CalibreBook?

    var saveBookCalled = false
    var saveBookParam: CalibreBook?

    var deleteBookCalled = false
    var deleteBookIdParam: String?

    var deleteBooksCalled = false
    var deleteBooksLibraryParam: CalibreLibrary?
    var deleteBooksIdsParam: [Int32]?

    var getAllBooksInShelfCalled = false
    var getAllBooksInShelfReturn: [CalibreBook] = []

    var bookExistsCalled = false
    var bookExistsIdParam: String?
    var bookExistsReturn: Bool = false

    var saveBookSyncRecordsCalled = false
    var saveBookSyncRecordsParam: [BookMetadataSyncRecord]?
    var saveBookSyncRecordsLibraryParam: CalibreLibrary?

    var persistMetadataEntriesCalled = false
    var persistMetadataEntriesLibraryParam: CalibreLibrary?
    var persistMetadataEntriesBookIdsParam: [Int32]?
    var persistMetadataEntriesReturn = BookMetadataPersistenceResult()

    var findDeletedBookIdsCalled = false
    var findDeletedBookIdsLibraryParam: CalibreLibrary?
    var findDeletedBookIdsActiveIdsParam: [String: CalibreCdbCmdListResult.DateValue]?
    var findDeletedBookIdsReturn: [Int32] = []

    var countAndNeedUpdateBooksCalled = false
    var countAndNeedUpdateBooksLibraryParam: CalibreLibrary?
    var countAndNeedUpdateBooksReturn: (count: Int, needUpdateIds: [Int32]) = (0, [])

    var observeBookCalled = false
    var observeBookIdParam: String?
    private let observeBookBroadcaster = TestAsyncStreamBroadcaster<CalibreBook?>()

    #if DEBUG
    var resetBooksCalled = false
    var resetBooksServerUUIDParam: String?
    var resetBooksLibraryNameParam: String?
    #endif

    func primaryKey(for book: CalibreBook) -> String {
        primaryKeyBookParam = book
        return primaryKey(library: book.library, bookId: book.id)
    }

    func primaryKey(library: CalibreLibrary, bookId: Int32) -> String {
        primaryKeyLibraryParam = library
        primaryKeyBookIdParam = bookId
        return "\(bookId)^\(library.name)@\(library.server.uuid.uuidString)"
    }

    func getBook(id: String) -> CalibreBook? {
        getBookCalled = true
        getBookIdParam = id
        return getBookReturn
    }

    func getBook(library: CalibreLibrary, bookId: Int32) -> CalibreBook? {
        getBookCalled = true
        getBookLibraryParam = library
        getBookBookIdParam = bookId
        return getBookReturn
    }

    func saveBook(_ book: CalibreBook) {
        saveBookCalled = true
        saveBookParam = book
    }

    func observeBook(id: String) -> AsyncStream<CalibreBook?> {
        observeBookCalled = true
        observeBookIdParam = id
        return observeBookBroadcaster.stream(initialValue: getBookReturn)
    }

    func sendObservedBook(_ book: CalibreBook?) {
        observeBookBroadcaster.send(book)
    }

    func deleteBook(id: String) {
        deleteBookCalled = true
        deleteBookIdParam = id
    }

    func deleteBooks(library: CalibreLibrary, ids: [Int32]) {
        deleteBooksCalled = true
        deleteBooksLibraryParam = library
        deleteBooksIdsParam = ids
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

    func saveBookSyncRecords(_ records: [BookMetadataSyncRecord], library: CalibreLibrary) {
        saveBookSyncRecordsCalled = true
        saveBookSyncRecordsParam = records
        saveBookSyncRecordsLibraryParam = library
    }

    func persistMetadataEntries(
        library: CalibreLibrary,
        bookIds: [Int32],
        entries: [String: CalibreBookEntry?],
        json: NSDictionary,
        includeAnnotationBooks: Bool
    ) -> BookMetadataPersistenceResult {
        persistMetadataEntriesCalled = true
        persistMetadataEntriesLibraryParam = library
        persistMetadataEntriesBookIdsParam = bookIds
        return persistMetadataEntriesReturn
    }

    func findDeletedBookIds(library: CalibreLibrary, activeIds: [String: CalibreCdbCmdListResult.DateValue]) -> [Int32] {
        findDeletedBookIdsCalled = true
        findDeletedBookIdsLibraryParam = library
        findDeletedBookIdsActiveIdsParam = activeIds
        return findDeletedBookIdsReturn
    }

    func countAndNeedUpdateBooks(library: CalibreLibrary) -> (count: Int, needUpdateIds: [Int32]) {
        countAndNeedUpdateBooksCalled = true
        countAndNeedUpdateBooksLibraryParam = library
        return countAndNeedUpdateBooksReturn
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

    var positionHistoryCalled = false
    var positionHistoryLibraryParam: CalibreLibrary?
    var positionHistoryBookIdParam: Int32?
    var positionHistoryStartDateAfterParam: Date?
    var positionHistoryReturn: [BookDeviceReadingPositionHistory] = []

    var sessionsCalled = false
    var sessionsBookIdParam: String?
    var sessionsStartDateAfterParam: Date?
    var sessionsReturn: [BookDeviceReadingPositionHistory] = []

    var beginSessionCalled = false
    var beginSessionPositionParam: BookDeviceReadingPosition?
    var beginSessionBookIdParam: String?
    var beginSessionReturn: ReadingSessionHandle?

    var endSessionCalled = false
    var endSessionHandleParam: ReadingSessionHandle?
    var endSessionPositionParam: BookDeviceReadingPosition?

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

    func getPosition(forBookId bookId: String, server: CalibreServer?, policy: ReadingPositionSelectionPolicy) -> BookDeviceReadingPosition? {
        getPositionCalled = true
        getPositionBookIdParam = bookId
        getPositionPolicyParam = policy
        return getPositionReturn
    }

    func getPositions(forBookId bookId: String, server: CalibreServer?) -> [BookDeviceReadingPosition] {
        getPositionsCalled = true
        getPositionsBookIdParam = bookId
        return getPositionsReturn
    }

    func debugPositions(forBookId bookId: String, server: CalibreServer?) -> [BookDeviceReadingPosition] {
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

    func savePosition(_ position: BookDeviceReadingPosition, forBookId bookId: String, server: CalibreServer?) {
        savePositionCalled = true
        savePositionParam = position
        savePositionBookIdParam = bookId
    }

    func removePosition(deviceName: String, forBookId bookId: String, server: CalibreServer?) {
        removePositionDeviceCalled = true
        removePositionDeviceNameParam = deviceName
        removePositionBookIdParam = bookId
    }

    func removePosition(position: BookDeviceReadingPosition, forBookId bookId: String, server: CalibreServer?) {
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

    func positionHistory(library: CalibreLibrary?, bookId: Int32?, startDateAfter: Date?) -> [BookDeviceReadingPositionHistory] {
        positionHistoryCalled = true
        positionHistoryLibraryParam = library
        positionHistoryBookIdParam = bookId
        positionHistoryStartDateAfterParam = startDateAfter
        return positionHistoryReturn
    }

    func sessions(forBookId bookId: String, server: CalibreServer?, list startDateAfter: Date?) -> [BookDeviceReadingPositionHistory] {
        sessionsCalled = true
        sessionsBookIdParam = bookId
        sessionsStartDateAfterParam = startDateAfter
        return sessionsReturn
    }

    func beginSession(at position: BookDeviceReadingPosition, forBookId bookId: String, server: CalibreServer?) -> ReadingSessionHandle? {
        beginSessionCalled = true
        beginSessionPositionParam = position
        beginSessionBookIdParam = bookId
        return beginSessionReturn
    }

    func endSession(_ handle: ReadingSessionHandle, at position: BookDeviceReadingPosition, server: CalibreServer?) {
        endSessionCalled = true
        endSessionHandleParam = handle
        endSessionPositionParam = position
    }

    func syncPositions(entries lastReadPositions: [CalibreBookLastReadPositionEntry], forBookId bookId: String, server: CalibreServer?) -> [CalibreBookLastReadPositionEntry] {
        syncPositionsCalled = true
        syncPositionsEntriesParam = lastReadPositions
        syncPositionsBookIdParam = bookId
        return syncPositionsReturn
    }
}

class MockAnnotationRepository: AnnotationRepositoryProtocol, @unchecked Sendable {
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
    private let observeEntriesBroadcaster = TestAsyncStreamBroadcaster<[ActivityLogUIEntry]>()
    var observeEntriesSubscriberCount: Int {
        observeEntriesBroadcaster.subscriberCount
    }

    var writeActivityLogEventsCalled = false
    var writeActivityLogEventsParam: [ActivityLogWriteEvent] = []

    var removeCalibreActivityCalled = false
    var removeCalibreActivityIdParam: String?

    var cleanCalibreActivitiesCalled = false
    var cleanCalibreActivitiesStartDatetimeParam: Date?

    func fetchEntries(libraryId: String?, bookId: Int32?, since: Date) -> [ActivityLogUIEntry] {
        fetchEntriesCalled = true
        fetchEntriesLibraryIdParam = libraryId
        fetchEntriesBookIdParam = bookId
        fetchEntriesSinceParam = since
        return fetchEntriesReturn
    }

    func observeEntries(libraryId: String?, bookId: Int32?, since: Date) -> AsyncStream<[ActivityLogUIEntry]> {
        observeEntriesCalled = true
        observeEntriesLibraryIdParam = libraryId
        observeEntriesBookIdParam = bookId
        observeEntriesSinceParam = since
        return observeEntriesBroadcaster.stream(initialValue: fetchEntriesReturn)
    }

    func sendObservedEntries(_ entries: [ActivityLogUIEntry]) {
        observeEntriesBroadcaster.send(entries)
    }

    func writeActivityLogEvents(_ events: [ActivityLogWriteEvent]) async {
        writeActivityLogEventsCalled = true
        writeActivityLogEventsParam = events
    }

    func removeCalibreActivity(id: String) async {
        removeCalibreActivityCalled = true
        removeCalibreActivityIdParam = id
    }

    func cleanCalibreActivities(startDatetime: Date) async {
        cleanCalibreActivitiesCalled = true
        cleanCalibreActivitiesStartDatetimeParam = startDatetime
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
    private let observeCategorySummariesBroadcaster = TestAsyncStreamBroadcaster<[CategoryCacheSummary]>()

    var observeCategoryCacheUpdatesCalled = false
    var observeCategoryCacheUpdatesCategoryNameParam: String?
    private var observeCategoryCacheUpdatesBroadcasters: [String: TestAsyncStreamBroadcaster<Void>] = [:]

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

    func observeCategorySummaries() -> AsyncStream<[CategoryCacheSummary]> {
        observeCategorySummariesCalled = true
        let initial = (try? fetchCategorySummaries()) ?? []
        return observeCategorySummariesBroadcaster.stream(initialValue: initial)
    }

    func observeCategoryCacheUpdates(categoryName: String) -> AsyncStream<Void> {
        observeCategoryCacheUpdatesCalled = true
        observeCategoryCacheUpdatesCategoryNameParam = categoryName
        let broadcaster = observeCategoryCacheUpdatesBroadcasters[categoryName] ?? {
            let newBroadcaster = TestAsyncStreamBroadcaster<Void>()
            observeCategoryCacheUpdatesBroadcasters[categoryName] = newBroadcaster
            return newBroadcaster
        }()
        return broadcaster.stream()
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
        observeCategorySummariesBroadcaster.send(summaries)
    }

    func sendCategoryCacheUpdate(categoryName: String) {
        observeCategoryCacheUpdatesBroadcasters[categoryName]?.send(())
    }
}
