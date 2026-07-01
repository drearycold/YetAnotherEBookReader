//
//  ShelfDataManager.swift
//  YetAnotherEBookReader
//
//  Created by Peter on 2022/11/30.
//

import Foundation
import Combine
import OSLog

class YabrShelfDataModel: ObservableObject {

    enum CategoryType: String {
        case Last
        case Author
        case Series
        case Tag
    }

    class CategoryObject: ObservableObject, Hashable {

        let type: CategoryType
        let category: String

        var inShelfBookIds: Set<String> = []

        var unifiedSearchResult: UnifiedSearchResult?

        var cancellables: Set<AnyCancellable> = []

        init(type: CategoryType, category: String) {
            self.type = type
            self.category = category
        }

        func hash(into: inout Hasher) {
            into.combine(type)
            into.combine(category)
        }

        static func == (lhs: YabrShelfDataModel.CategoryObject, rhs: YabrShelfDataModel.CategoryObject) -> Bool {
            lhs.type == rhs.type && lhs.category == rhs.category
        }

    }
    private let unifiedSearchService: UnifiedSearchService
    private let container: AppContainerProtocol

    var categories: Set<CategoryObject> = []

    @Published var discoverShelfItems = [String: ShelfSectionItem]()

    var cancellables: Set<AnyCancellable> = []

    let dispatchQueue = DispatchQueue(label: "shelf-queue")

    @Published var isInitialLoadComplete = false
    private var initialCategories = Set<String>()
    private var completedInitialCategories = Set<String>()
    private var shelfSnapshotComplete = false
    private var isInitialLoadCompleteFlag = false

    init(unifiedSearchService: UnifiedSearchService, container: AppContainerProtocol) {
        self.unifiedSearchService = unifiedSearchService
        self.container = container

        container.calibreUpdatedSubject
            .receive(on: RunLoop.main)
            .compactMap { [weak self] signal -> [String: CalibreBook]? in
                self?.booksInShelfSnapshotIfNeeded(for: signal)
            }
            .receive(on: dispatchQueue)
            .sink { [weak self] booksInShelf in
                self?.rebuildShelfCategories(from: booksInShelf)
            }
            .store(in: &cancellables)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard self.container.bookManager.isShelfLoaded else { return }
            let snapshot = self.container.bookManager.booksInShelf
            self.dispatchQueue.async {
                self.rebuildShelfCategories(from: snapshot)
            }
        }
    }

    private func booksInShelfSnapshotIfNeeded(for signal: calibreUpdatedSignal) -> [String: CalibreBook]? {
        switch signal {
        case .shelf, .book, .deleted:
            guard container.bookManager.isShelfLoaded else { return nil }
            return container.bookManager.booksInShelf
        case .library, .server:
            return nil
        }
    }

    deinit {
        cancellables.removeAll()
        categories.forEach { $0.cancellables.removeAll() }
    }

    /**
     run on dispatchQueue
     */
    func addToShelf(book: CalibreBook) {
        dispatchPrecondition(condition: .onQueue(dispatchQueue))

        for categoryName in authorCategories(for: book) {
            addToShelf(inShelfId: book.inShelfId, categoryName: categoryName)
        }
    }

    private func rebuildShelfCategories(from booksInShelf: [String: CalibreBook]) {
        dispatchPrecondition(condition: .onQueue(dispatchQueue))

        var categoryBookIds = [String: Set<String>]()
        for (inShelfId, book) in booksInShelf {
            for categoryName in authorCategories(for: book) {
                categoryBookIds[categoryName, default: []].insert(inShelfId)
            }
        }

        let desiredCategoryNames = Set(categoryBookIds.keys)
        let existingCategories = categories

        for category in existingCategories where !desiredCategoryNames.contains(category.category) {
            removeCategory(category)
        }

        for categoryName in desiredCategoryNames.sorted() {
            guard let inShelfBookIds = categoryBookIds[categoryName] else { continue }
            if let index = categories.firstIndex(of: CategoryObject(type: .Author, category: categoryName)) {
                categories[index].inShelfBookIds = inShelfBookIds
            } else {
                addToShelf(inShelfIds: inShelfBookIds, categoryName: categoryName)
            }
        }

        let initialKeys = Set(desiredCategoryNames.map { "Author: \($0)" })
        initialCategories = initialKeys
        completedInitialCategories.formIntersection(initialKeys)
        shelfSnapshotComplete = true

        if initialKeys.isEmpty {
            markInitialLoadComplete()
        } else {
            checkInitialLoadCompletion()
        }
    }

    private func addToShelf(inShelfId: String, categoryName: String) {
        addToShelf(inShelfIds: [inShelfId], categoryName: categoryName)
    }

    private func addToShelf(inShelfIds: Set<String>, categoryName: String) {
        dispatchPrecondition(condition: .onQueue(dispatchQueue))

        let category = CategoryObject(type: .Author, category: categoryName)
        if let index = categories.firstIndex(of: category) {
            categories[index].inShelfBookIds.formUnion(inShelfIds)
            return
        }

        category.inShelfBookIds.formUnion(inShelfIds)
        categories.insert(category)

        let key = SearchCriteriaMergedKey(
            libraryIds: [],
            criteria: SearchCriteria(
                searchString: "",
                sortCriteria: .init(),
                filterCriteriaCategory: ["Authors" : Set([categoryName])]
            )
        )

        let categoryKey = "Author: \(categoryName)"

        unifiedSearchService.searchUpdatePublisher(for: key)
            .receive(on: dispatchQueue)
            .sink { [weak self, weak category] update in
                guard let self = self, let category = category else { return }
                dispatchPrecondition(condition: .onQueue(self.dispatchQueue))
                category.unifiedSearchResult = update.result

                let discoverShelfSectionItem = self.buildShelfSectionItem(category: category)

                // Track category loading completion
                let searchLibraryIds = self.container.libraryManager.calibreLibraries.filter {
                    !$0.value.hidden && !$0.value.server.removed
                }.keys

                let isDone: Bool = {
                    if searchLibraryIds.isEmpty {
                        return true
                    }
                    if update.statuses.isEmpty {
                        return false
                    }
                    return update.statuses.values.allSatisfy { !$0.loading }
                }()

                if isDone && self.initialCategories.contains(categoryKey) {
                    self.completedInitialCategories.insert(categoryKey)
                    self.checkInitialLoadCompletion()
                }

                DispatchQueue.main.async {
                    if discoverShelfSectionItem.books.count > 1 {
                        if self.discoverShelfItems[discoverShelfSectionItem.id] != discoverShelfSectionItem {
                            self.discoverShelfItems[discoverShelfSectionItem.id] = discoverShelfSectionItem
                            self.notifyDiscoverShelfChanged()
                        }
                    } else {
                        if self.discoverShelfItems.removeValue(forKey: discoverShelfSectionItem.id) != nil {
                            self.notifyDiscoverShelfChanged()
                        }
                    }
                }
            }
            .store(in: &category.cancellables)
    }

    private func checkInitialLoadCompletion() {
        dispatchPrecondition(condition: .onQueue(dispatchQueue))
        guard shelfSnapshotComplete else { return }
        guard !isInitialLoadCompleteFlag else { return }

        let remaining = initialCategories.subtracting(completedInitialCategories)
        if remaining.isEmpty {
            markInitialLoadComplete()
        }
    }

    private func markInitialLoadComplete() {
        dispatchPrecondition(condition: .onQueue(dispatchQueue))
        guard !isInitialLoadCompleteFlag else { return }
        isInitialLoadCompleteFlag = true
        DispatchQueue.main.async {
            self.isInitialLoadComplete = true
        }
    }

    func removeFromShelf(book: CalibreBook) {
        dispatchPrecondition(condition: .onQueue(dispatchQueue))

        for categoryName in authorCategories(for: book) {
            guard let index = categories.firstIndex(of: CategoryObject(type: .Author, category: categoryName))
            else {
                continue
            }

            let category = categories[index]
            category.inShelfBookIds.remove(book.inShelfId)

            guard category.inShelfBookIds.isEmpty
            else {
                continue
            }

            removeCategory(category)
        }
    }

    private func removeCategory(_ category: CategoryObject) {
        dispatchPrecondition(condition: .onQueue(dispatchQueue))
        category.cancellables.removeAll()
        category.unifiedSearchResult = nil

        let sectionName = "\(category.type.rawValue): \(category.category)"
        DispatchQueue.main.async {
            if self.discoverShelfItems.removeValue(forKey: sectionName) != nil {
                self.notifyDiscoverShelfChanged()
            }
        }

        categories.remove(category)
    }

    private func authorCategories(for book: CalibreBook) -> [String] {
        let authors = book.authors.isEmpty ? ["Unknown"] : book.authors
        return Array(authors.prefix(3))
    }

    func seedCategoriesForTesting(_ categories: [CategoryObject]) {
        dispatchQueue.sync {
            self.categories = Set(categories)
        }
    }

    func categoryNamesForTesting() -> Set<String> {
        dispatchQueue.sync {
            Set(categories.map(\.category))
        }
    }

    func buildShelfSectionItem(category: CategoryObject) -> ShelfSectionItem {
        let sectionName = "\(category.type.rawValue): \(category.category)"

        let books: [ShelfBookItem] = category.unifiedSearchResult?.books.map {
            ShelfBookItem(
                id: $0.inShelfId,
                title: $0.title,
                coverURL: $0.coverURL?.absoluteString ?? "",
                progress: 0,
                status: .ready,
                libraryId: $0.library.id
            )
        } ?? []

        return ShelfSectionItem(id: sectionName, title: sectionName, books: books)
    }

    @MainActor
    private func notifyDiscoverShelfChanged() {
        let displaySections = self.discoverShelfItems.values.sorted(by: { $0.title < $1.title })
        self.container.discoverShelfItemsSubject.send(displaySections)
    }

    func refresh() async {
        let keys = await withCheckedContinuation {
            (continuation: CheckedContinuation<[SearchCriteriaMergedKey], Never>) in
            dispatchQueue.async {
                let keys = self.categories
                    .sorted {
                        if $0.type.rawValue == $1.type.rawValue {
                            return $0.category < $1.category
                        }
                        return $0.type.rawValue < $1.type.rawValue
                    }
                    .map { category in
                        SearchCriteriaMergedKey(
                            libraryIds: [],
                            criteria: SearchCriteria(
                                searchString: "",
                                sortCriteria: .init(),
                                filterCriteriaCategory: ["Authors": Set([category.category])]
                            )
                        )
                    }
                continuation.resume(returning: keys)
            }
        }

        for key in keys {
            guard !Task.isCancelled else { return }
            await unifiedSearchService.resetSearchAndWait(for: key, force: true)
        }
    }
}

extension AppContainerProtocol where Self: ObservableObject {
    func registerRecentShelfUpdater() {
        let queue = DispatchQueue(label: "recent-shelf-updater", qos: .userInitiated)
        let box = RecentShelfFirstPublishBox()
        calibreUpdatedSubject
            .receive(on: RunLoop.main)
            .compactMap { [weak self] _ -> ([String: CalibreBook], OSSignpostIntervalState)? in
                guard let self = self else { return nil }
                guard self.bookManager.isShelfLoaded else {
                    return nil
                }
                let snapshot = self.bookManager.booksInShelf
                let state = AppPerformanceSignpost.begin("RecentShelfRebuild")
                return (snapshot, state)
            }
            .receive(on: queue)
            .map { [weak self] (booksInShelf: [String: CalibreBook], state: OSSignpostIntervalState) -> ([ShelfBookItem], OSSignpostIntervalState) in
                guard let self = self else { return ([], state) }
                let readingPositionRepository = self.readingPositionRepository
                var booksWithTS: [(key: String, value: CalibreBook, ts: Date, positions: [BookDeviceReadingPosition])] = []
                for (key, book) in booksInShelf {
                    let positions = readingPositionRepository.getPositions(for: book)
                    let maxEpoch: Date? = positions.map { p in Date(timeIntervalSince1970: p.epoch) }.max()
                    let ts: Date = max(book.lastModified, maxEpoch ?? book.lastUpdated)
                    booksWithTS.append((key, book, ts, positions))
                }

                let sorted = booksWithTS.sorted { lhs, rhs in
                    return lhs.ts > rhs.ts
                }

                let items = sorted.map { entry in
                    self.buildShelfBookItem(entry: entry)
                }
                return (items, state)
            }
            .receive(on: RunLoop.main)
            .sink(receiveValue: { (displayBooks, state) in
                AppPerformanceSignpost.end("RecentShelfRebuild", state)
                if box.isFirstPublish {
                    box.isFirstPublish = false
                    AppPerformanceSignpost.emit("FirstRecentShelfPublish")
                }
                self.recentShelfItemsSubject.send(displayBooks)
            })
            .store(in: &calibreCancellables)
    }
}

extension AppContainerProtocol where Self: ObservableObject {
    private func buildShelfBookItem(entry: (key: String, value: CalibreBook, ts: Date, positions: [BookDeviceReadingPosition])) -> ShelfBookItem {
        let inShelfId = entry.key
        let book = entry.value
        let positions = entry.positions

        let formats: [String: FormatInfo] = book.formats
        let formatArray: [(String, FormatInfo)] = Array(formats)

        var bookUptoDate = true
        for (_, formatInfo) in formatArray {
            if !(formatInfo.cached == false || (formatInfo.cached && formatInfo.cacheUptoDate)) {
                bookUptoDate = false
                break
            }
        }

        var missingFormats: [String: FormatInfo] = [:]
        for (key, formatInfo) in formatArray where formatInfo.selected == true && formatInfo.cached == false {
            missingFormats[key] = formatInfo
        }

        var status = ShelfBookStatus.ready
        if self.calibreServerService.getServerUrlByReachability(server: book.library.server) == nil {
            status = .noConnect
        } else {
            missingFormats.forEach {
                guard let format = Format(rawValue: $0.key) else { return }
                self.downloadManager.bookFormatDownloadSubject.send((book: book, format: format))
            }

            if !bookUptoDate {
                status = .hasUpdate
            }
            if self.downloadManager.activeDownloads.contains(where: { (url, download) in
                download.isDownloading && download.book.inShelfId == inShelfId
            }) {
                status = .downloading
            }
        }
        if book.library.server.isLocal {
            status = .local
        }

        var lastProgress = 0.0
        if let position = ReadingPositionSelectionPolicy.latestForDevice(self.deviceName).select(from: positions) {
            lastProgress = position.lastProgress
        } else if let position = ReadingPositionSelectionPolicy.latest.select(from: positions) {
            lastProgress = position.lastProgress
        }

        return ShelfBookItem(
            id: inShelfId,
            title: book.title,
            coverURL: book.coverURL?.absoluteString ?? "",
            progress: Int(floor(lastProgress)),
            status: status
        )
    }
}

class RecentShelfFirstPublishBox {
    var isFirstPublish = true
}
