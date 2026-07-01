//
//  ShelfDataManager.swift
//  YetAnotherEBookReader
//
//  Created by Peter on 2022/11/30.
//

import Foundation
import Combine
import RealmSwift
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

    let addToShelfSubject = PassthroughSubject<CalibreBookRealm, Never>()

    var cancellables: Set<AnyCancellable> = []

    let dispatchQueue = DispatchQueue(label: "shelf-queue")

    @Published var isInitialLoadComplete = false
    private var initialCategories = Set<String>()
    private var completedInitialCategories = Set<String>()
    private var realmScanComplete = false
    private var isInitialLoadCompleteFlag = false

    var realmOnQueue: Realm!

    init(unifiedSearchService: UnifiedSearchService, container: AppContainerProtocol) {
        self.unifiedSearchService = unifiedSearchService
        self.container = container

        dispatchQueue.sync {
            guard let realmConf = self.container.realmConf,
                  let realmOnQueue = try? Realm(configuration: realmConf, queue: dispatchQueue) else {
                return
            }
            self.realmOnQueue = realmOnQueue

            // Synchronously scan initial books and construct categories
            let initialBooks = realmOnQueue.objects(CalibreBookRealm.self).filter("inShelf == true")
            var initialKeys = Set<String>()
            for book in initialBooks {
                for author in [book.authorFirst, book.authorSecond, book.authorThird].compactMap({ $0 }) {
                    initialKeys.insert("Author: \(author)")
                }
            }
            self.initialCategories = initialKeys
            self.realmScanComplete = true

            if initialKeys.isEmpty {
                self.isInitialLoadCompleteFlag = true
                DispatchQueue.main.async {
                    self.isInitialLoadComplete = true
                }
            }

            initialBooks.forEach {
                self.addToShelf(book: $0)
            }

            // Observe subsequent updates only
            realmOnQueue.objects(CalibreBookRealm.self)
                .changesetPublisher(keyPaths: ["inShelf"])
                .subscribe(on: dispatchQueue)
                .sink { changes in
                    switch changes {
                    case .initial:
                        // Ignored since we manually populated above
                        break
                    case .update(let results, deletions: _, insertions: _, modifications: let modifications):
                        modifications
                            .map { results[$0] }
                            .forEach {
                                if $0.inShelf {
                                    self.addToShelfSubject.send($0)
                                } else {
                                    self.removeFromShelf(book: $0)
                                }
                            }
                        break
                    case .error(_):
                        break
                    }
                }
                .store(in: &cancellables)

            addToShelfSubject.receive(on: dispatchQueue)
                .sink { book in
                    self.addToShelf(book: book)
                }.store(in: &cancellables)
        }
    }

    /**
     run on dispatchQueue
     */
    func addToShelf(book: CalibreBookRealm) {
        dispatchPrecondition(condition: .onQueue(dispatchQueue))
        guard let inShelfId = book.primaryKey
        else {
            return
        }

        for categoryName in [book.authorFirst, book.authorSecond, book.authorThird] {
            guard let categoryName = categoryName
            else {
                return
            }

            let category = CategoryObject(type: .Author, category: categoryName)
            if let index = categories.firstIndex(of: category) {
                categories[index].inShelfBookIds.insert(inShelfId)
                return
            }

            category.inShelfBookIds.insert(inShelfId)
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
    }

    private func checkInitialLoadCompletion() {
        dispatchPrecondition(condition: .onQueue(dispatchQueue))
        guard realmScanComplete else { return }
        guard !isInitialLoadCompleteFlag else { return }

        let remaining = initialCategories.subtracting(completedInitialCategories)
        if remaining.isEmpty {
            isInitialLoadCompleteFlag = true
            DispatchQueue.main.async {
                self.isInitialLoadComplete = true
            }
        }
    }

    func removeFromShelf(book: CalibreBookRealm) {
        dispatchPrecondition(condition: .onQueue(dispatchQueue))
        guard let inShelfId = book.primaryKey
        else {
            return
        }

        for categoryName in [book.authorFirst, book.authorSecond, book.authorThird] {
            guard let categoryName = categoryName
            else {
                return
            }

            guard let index = categories.firstIndex(of: CategoryObject(type: .Author, category: categoryName))
            else {
                return
            }

            let category = categories[index]
            category.inShelfBookIds.remove(inShelfId)

            guard category.inShelfBookIds.isEmpty
            else {
                return
            }

            category.cancellables.removeAll()
            category.unifiedSearchResult = nil

            let sectionName = "\(category.type.rawValue): \(category.category)"
            DispatchQueue.main.async {
                if self.discoverShelfItems.removeValue(forKey: sectionName) != nil {
                    self.notifyDiscoverShelfChanged()
                }
            }

            categories.remove(at: index)
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

    func refresh() {
        dispatchQueue.async {
            self.categories.forEach { category in
                let key = SearchCriteriaMergedKey(
                    libraryIds: [],
                    criteria: SearchCriteria(
                        searchString: "",
                        sortCriteria: .init(),
                        filterCriteriaCategory: ["Authors" : Set([category.category])]
                    )
                )
                Task {
                    await self.unifiedSearchService.resetSearch(for: key, force: true)
                }
            }
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
                    let positions: [BookDeviceReadingPosition] = readingPositionRepository.getPositions(forBookId: book.bookPrefId)
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
