//
//  CalibreBrowser.swift
//  YetAnotherEBookReader
//
//  Created by Peter on 2022/11/5.
//

import Foundation
import RealmSwift
import Combine

struct LibrarySearchSort: Hashable {
    var by = SortCriteria.Modified
    var ascending = false
    
    var description: String {
        "\(ascending ? "First" : "Last") \(by.description)"
    }
}

enum SortCriteria: String, CaseIterable, Identifiable {
    var id: String { self.rawValue }
    
    case Title
    case Added
    case Publication
    case Modified
    case SeriesIndex
    
    var sortKeyPath: String {
        switch(self) {
        case .Title:
            return "title"
        case .Added:
            return "timestamp"
        case .Publication:
            return "pubDate"
        case .Modified:
            return "lastModified"
        case .SeriesIndex:
            return "seriesIndex"
        }
    }
    
    var sortQueryParam: String {
        switch(self) {
        case .Title:
            return "sort"
        case .Added:
            return "timestamp"
        case .Publication:
            return "pubdate"
        case .Modified:
            return "last_modified"
        case .SeriesIndex:
            return "series_index"
        }
    }
    
    var description: String {
        switch (self) {
        case .SeriesIndex:
            return "Series Index"
        default:
            return self.rawValue
        }
    }
}

struct SearchCriteria: Hashable, CustomStringConvertible {
    let searchString: String
    let sortCriteria: LibrarySearchSort
    let filterCriteriaCategory: [String: Set<String>]
    let pageSize: Int = 100
    
    var hasEmptyFilter: Bool {
        filterCriteriaCategory.isEmpty
    }
    
    var description: String {
        "\(searchString)^\(sortCriteria)^\(filterCriteriaCategory.count)"
    }
}

struct SearchCriteriaMergedKey: Hashable {
    let libraryIds: Set<String>
    let criteria: SearchCriteria
}

struct LibrarySearchCriteriaResultMerged {
    struct MergedPageOffset {
        var offsets: [Int]
        var beenCutOff: Bool
        var cutOffOffset : Int
        
        mutating func setOffset(index: Int, offset: Int) {
            if index < offsets.endIndex {
                offsets[index] = offset
            } else {
                offsets.append(offset)
            }
        }
    }
    /***
     key: libraryId
     value:
        index: pageNo - 0-based
        element: offset in bookIds
     */
    var mergedPageOffsets: [String: MergedPageOffset]
    
//    @available(*, deprecated, message: "replaced by mergedBooks")
//    var books = [CalibreBook]()
    
    var mergedBooks = [CalibreBook]()
    
    var totalNumber = 0
    var merging = false
    
    init(libraryIds: Set<String>) {
        mergedPageOffsets = libraryIds.reduce(into: [:], { partialResult, libraryId in
            partialResult[libraryId] = .init(offsets: [0], beenCutOff: false, cutOffOffset: 0)
        })
    }
    
    func booksForPage(page: Int, pageSize: Int) -> ArraySlice<CalibreBook> {
        if mergedBooks.count >= (page+1)*pageSize {
            return mergedBooks[page*pageSize..<(page+1)*pageSize]
        } else if mergedBooks.count > (page)*pageSize {
            return mergedBooks.suffix(mergedBooks.count - page * pageSize)
        } else {
            return mergedBooks.suffix(0)
        }
    }
}

struct LibrarySearchKey: Hashable, CustomStringConvertible {
    let libraryId: String
    let criteria: SearchCriteria
    
    var description: String {
        "\(libraryId) || \(criteria)"
    }
}

struct LibrarySearchResult: CustomStringConvertible {
    let library: CalibreLibrary
    var loading = false
    var offlineResult = false
    var error = false
    var totalNumber = 0

    var bookIds = [Int32]()
    
    var description: String {
        "\(bookIds.count)/\(totalNumber)"
    }
}

struct LibrarySearchCache {
    enum CacheType: Comparable, CaseIterable {
        case online
        case onlineCache
        case offline
    }
    struct CacheKey: Hashable {
        let searchKey: LibrarySearchKey
        let type: CacheType
    }
    
    private var cache = [CacheKey: LibrarySearchResult]()
    
    /**
     nil value for type means any available
     */
    func getCache(for library: CalibreLibrary, of criteria: SearchCriteria, by type: CacheType? = nil) -> LibrarySearchResult {
        let searchKey = LibrarySearchKey(libraryId: library.id, criteria: criteria)
        if let type = type {
            let cacheKey = CacheKey(searchKey: searchKey, type: type)
            if let result = cache[cacheKey] {
                return result
            } else {
                return .init(library: library, offlineResult: type == .offline, error: true)
            }
        } else {
            for type in CacheType.allCases {
                if let result = cache[.init(searchKey: searchKey, type: type)] {
                    return result
                }
            }
            return .init(library: library, offlineResult: type == .offline, error: true)
        }
    }
    
    /**
     first non-empty result for each library by preference ( online > onlineCache > offline )
     */
    func getCaches(for libraryIds: Set<String>, of criteria: SearchCriteria, by type: CacheType? = nil) -> [LibrarySearchKey: LibrarySearchResult] {
        self.cache.filter {
            (
                libraryIds.isEmpty
                ||
                libraryIds.contains($0.key.searchKey.libraryId)
            )
            &&
            $0.key.searchKey.criteria == criteria
            &&
            (
                (type == nil && $0.value.bookIds.count > 0)
                ||
                (type == $0.key.type)
            )
        }.sorted { lhs, rhs in
            lhs.key.type < rhs.key.type
        }.reduce(into: [:]) { partialResult, cacheEntry in
            if partialResult[cacheEntry.key.searchKey] == nil {
                partialResult[cacheEntry.key.searchKey] = cacheEntry.value
            }
        }
    }
    
    mutating func resetCache(for library: CalibreLibrary, of criteria: SearchCriteria, by type: CacheType) {
        let cacheKey = CacheKey(searchKey: .init(libraryId: library.id, criteria: criteria), type: type)
        if var cacheVal = cache[cacheKey] {
            cacheVal.loading = false
            cacheVal.error = true
            cacheVal.bookIds.removeAll(keepingCapacity: true)
            cache[cacheKey] = cacheVal
        } else {
            cache[cacheKey] = .init(library: library, offlineResult: type == .offline, error: true)
        }
    }
    
    mutating func startLoading(for library: CalibreLibrary, of criteria: SearchCriteria, by type: CacheType) {
        let cacheKey = CacheKey(searchKey: .init(libraryId: library.id, criteria: criteria), type: type)
        if cache[cacheKey] == nil {
            cache[cacheKey] = .init(library: library, offlineResult: type == .offline, error: true)
        }
        cache[cacheKey]?.loading = true
    }
    
    mutating func finishLoading(for library: CalibreLibrary, of criteria: SearchCriteria, by type: CacheType) {
        let cacheKey = CacheKey(searchKey: .init(libraryId: library.id, criteria: criteria), type: type)
        cache[cacheKey]?.loading = false
    }
    
    mutating func setIsError(for library: CalibreLibrary, of criteria: SearchCriteria, by type: CacheType, to error: Bool) {
        let cacheKey = CacheKey(searchKey: .init(libraryId: library.id, criteria: criteria), type: type)
        if cache[cacheKey] == nil {
            cache[cacheKey] = .init(library: library, offlineResult: type == .offline, error: error)
        } else {
            cache[cacheKey]?.error = error
        }
    }
    
    mutating func setTotalNumber(for library: CalibreLibrary, of criteria: SearchCriteria, by type: CacheType, to totalNumber: Int) {
        let cacheKey = CacheKey(searchKey: .init(libraryId: library.id, criteria: criteria), type: type)
        cache[cacheKey]?.totalNumber = totalNumber
    }
    
    mutating func appendResult(for library: CalibreLibrary, of criteria: SearchCriteria, by type: CacheType, contentsOf: [Int32]) {
        let cacheKey = CacheKey(searchKey: .init(libraryId: library.id, criteria: criteria), type: type)
        cache[cacheKey]?.bookIds.append(contentsOf: contentsOf)
        cache[cacheKey]?.error = false
    }
}

struct LibraryCategoryList {
    let library: CalibreLibrary
    let category: CalibreLibraryCategory
    let reqId: Int
    var offset: Int
    var num: Int
    
    var result: LibraryCategoryListResult?
}

struct LibraryCategoryListResult: Codable {
    struct Item: Codable {
        let name: String
        let average_rating: Double
        let count: Int
        let url: String
        let has_children: Bool
    }
    let category_name: String
    let base_url: String
    let total_num: Int
    let offset: Int
    let num: Int
    let sort: String
    let sort_order: String
    //"subcategories": [],  unknown
    let items: [Item]
}

extension ModelData {
    func getBook(for primaryKey: String) -> CalibreBook? {
        var bookLocal: CalibreBook? = nil
        var bookSearch: CalibreBook? = nil
        if let obj = getBookRealm(forPrimaryKey: primaryKey) {
            bookLocal = convert(bookRealm: obj)
        }
        
        if let obj = searchLibraryResultsRealmMainThread?.object(ofType: CalibreBookRealm.self, forPrimaryKey: primaryKey) {
            bookSearch = convert(bookRealm: obj)
        }
        
        if bookSearch == nil {
            return bookLocal
        }
        if bookLocal == nil {
            return bookSearch
        }
        
        if bookLocal?.lastModified == bookSearch?.lastModified,
           bookLocal?.lastModified == bookLocal?.lastSynced {
            return bookLocal
        }
        
        return bookSearch
    }
    
    var currentLibrarySearchCriteria: SearchCriteria {
        SearchCriteria(
            searchString: self.searchString,
            sortCriteria: self.sortCriteria,
            filterCriteriaCategory: self.filterCriteriaCategory
        )
    }
    
    var currentLibrarySearchResultKey: SearchCriteriaMergedKey {
        .init(
            libraryIds: filterCriteriaLibraries.isEmpty ? self.calibreLibraries.reduce(into: Set<String>(), { partialResult, entry in
                if entry.value.hidden == false,
                   entry.value.server.removed == false {
                    partialResult.insert(entry.key)
                }
            }) : filterCriteriaLibraries,
            criteria: .init(
                searchString: self.searchString,
                sortCriteria: self.sortCriteria,
                filterCriteriaCategory: self.filterCriteriaCategory
            )
        )
    }
    
    var currentLibrarySearchResultMerged: LibrarySearchCriteriaResultMerged? {
        self.searchCriteriaMergedResults[self.currentLibrarySearchResultKey]
    }
    
    var currentSearchLibraryResults: [LibrarySearchKey: LibrarySearchResult] {
        librarySearchCache.getCaches(
            for: self.filterCriteriaLibraries,
            of: self.currentLibrarySearchCriteria
        )
    }
    
    var currentSearchLibraryResultsCannotFurther: Bool {
        guard let currentLibrarySearchResultMerged = currentLibrarySearchResultMerged
        else { return true }
        
        guard let maxPage = self.currentSearchLibraryResults
            .compactMap({ result -> Int? in
                let resultIsError = result.value.error || result.value.loading
                if let libraryMergedPageOffset = currentLibrarySearchResultMerged.mergedPageOffsets[result.key.libraryId] {
                    if resultIsError {
                        return libraryMergedPageOffset.offsets.lastIndex { $0 < result.value.bookIds.count }
                    } else {
                        return libraryMergedPageOffset.offsets.endIndex
                    }
                } else {
                    return 1
                }
            }).max()
        else { return true }
        
        return self.filteredBookListPageNumber + 1 == maxPage
    }
    
    func mergeBookListsNew(mergeKey: SearchCriteriaMergedKey, mergedResult: LibrarySearchCriteriaResultMerged, page: Int = 0, limit: Int = 100) -> LibrarySearchCriteriaResultMerged {
        guard let realm = try? Realm(configuration: realmConf),
              let realmSearch = searchLibraryResultsRealmQueue
        else { return mergedResult }
        
        let searchResults: [String: LibrarySearchResult] = self.librarySearchCache.getCaches(
            for: mergeKey.libraryIds,
            of: mergeKey.criteria
        ).reduce(into: [:]) { partialResult, entry in
            partialResult[entry.key.libraryId] = entry.value
        }
        
        var startPage = page
        while startPage > 0, mergeKey.libraryIds.allSatisfy({ libraryId in
            guard let mergedPageOffset = mergedResult.mergedPageOffsets[libraryId]
            else { return false }
            
            return mergedPageOffset.offsets.endIndex > startPage
            &&
            (mergedPageOffset.offsets.last ?? 0) > (searchResults[libraryId]?.totalNumber ?? -1)
        }) == false {
            startPage -= 1
        }
        
        var mergedResult = mergedResult
        
        var headIndex = [String: Int]()
        mergeKey.libraryIds.forEach { libraryId in
            guard let mergedPageOffset = mergedResult.mergedPageOffsets[libraryId]
            else { return }
            
            let startPageOffset = mergedPageOffset.offsets[startPage]
            headIndex[libraryId] = startPageOffset
            
            if let searchResult = searchResults[libraryId] {
                mergedResult.mergedPageOffsets[libraryId]?.beenCutOff = startPageOffset >= searchResult.bookIds.endIndex
                mergedResult.mergedPageOffsets[libraryId]?.cutOffOffset = searchResult.bookIds.endIndex
            } else {
                mergedResult.mergedPageOffsets[libraryId]?.beenCutOff = true
                mergedResult.mergedPageOffsets[libraryId]?.cutOffOffset = 0
            }
        }
        
        headIndex.forEach {
            print("LIBRARYINFOVIEW headIndex \($0)")
        }
        
        var heads = mergeKey.libraryIds.compactMap { libraryId -> CalibreBookRealm? in
            guard let headOffset = headIndex[libraryId],
                  let searchResult = searchResults[libraryId],
                  headOffset < searchResult.bookIds.count
            else { return nil}
            
            let primaryKey = CalibreBookRealm.PrimaryKey(
                serverUUID: searchResult.library.server.uuid.uuidString,
                libraryName: searchResult.library.name,
                id: searchResult.bookIds[headOffset].description
            )
            
            let obj = realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: primaryKey)
            ?? realmSearch.object(ofType: CalibreBookRealm.self, forPrimaryKey: primaryKey)
            
            print("LIBRARYINFOVIEW headObj=\(String(describing: obj)) primaryKey=\(primaryKey)")
            
            return obj
        }
        
        print("LIBRARYINFOVIEW heads=\(heads.count)")
        
        // sort in reverse so we can use popLast() (O(1)) to merge
        let sortComparator = MergeSortComparator(criteria: mergeKey.criteria.sortCriteria.by, order: mergeKey.criteria.sortCriteria.ascending ? .reverse : .forward)
        heads.sort(using: sortComparator)
        
        let mergeLength = (page + 1) * limit
        if mergedResult.mergedBooks.count > startPage * limit {
            mergedResult.mergedBooks.removeLast(mergedResult.mergedBooks.count - startPage * limit)
        }
        while mergedResult.mergedBooks.count < mergeLength, let head = heads.popLast() {
            if let book = self.convert(bookRealm: head) {
                mergedResult.mergedBooks.append(book)
            }
            
            let headLibraryId = CalibreLibraryRealm.PrimaryKey(serverUUID: head.serverUUID!, libraryName: head.libraryName!)
            guard let searchResult = searchResults[headLibraryId] else { continue }
            
            headIndex[headLibraryId]? += 1
            
            if mergedResult.mergedBooks.count % limit == 0 {
                let currentPage = mergedResult.mergedBooks.count / limit
                headIndex.forEach {
                    mergedResult.mergedPageOffsets[$0.key]?.setOffset(index: currentPage, offset: $0.value)
                }
            }
            
            guard let headOffset = headIndex[headLibraryId],
                  headOffset < searchResult.bookIds.count else {
                if searchResult.bookIds.count < searchResult.totalNumber {
                    mergedResult.mergedPageOffsets[headLibraryId]?.beenCutOff = true
                    mergedResult.mergedPageOffsets[headLibraryId]?.cutOffOffset = searchResult.bookIds.count
                }
                continue
            }
            
            let primaryKey = CalibreBookRealm.PrimaryKey(
                serverUUID: searchResult.library.server.uuid.uuidString,
                libraryName: searchResult.library.name,
                id: searchResult.bookIds[headOffset].description
            )
            
            guard let next = realmSearch.object(ofType: CalibreBookRealm.self, forPrimaryKey: primaryKey) ?? realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: primaryKey)
            else {
                continue
            }
            
            heads.append(next)
            heads.sort(using: sortComparator)
        }
        
        print("\(#function) merged from \(searchResults.count) libraries")
        
        return mergedResult
    }
}

struct MergeSortComparator: SortComparator {
    let criteria: SortCriteria
    var order: SortOrder
    
    func compare(
        _ lhs: CalibreBookRealm,
        _ rhs: CalibreBookRealm
    ) -> ComparisonResult {
        switch order {
        case .forward:
            switch criteria {
            case .Title:
                return lhs.title.compare(rhs.title)
            case .Added:
                return lhs.timestamp.compare(rhs.timestamp)
            case .Publication:
                return lhs.pubDate.compare(rhs.pubDate)
            case .Modified:
                return lhs.lastModified.compare(rhs.lastModified)
            case .SeriesIndex:
                if lhs.seriesIndex < rhs.seriesIndex {
                    return .orderedAscending
                } else if lhs.seriesIndex > rhs.seriesIndex {
                    return .orderedDescending
                } else {
                    return .orderedSame
                }
            }
        case .reverse:
            switch criteria {
            case .Title:
                return rhs.title.compare(lhs.title)
            case .Added:
                return rhs.timestamp.compare(lhs.timestamp)
            case .Publication:
                return rhs.pubDate.compare(lhs.pubDate)
            case .Modified:
                return rhs.lastModified.compare(lhs.lastModified)
            case .SeriesIndex:
                if rhs.seriesIndex < lhs.seriesIndex {
                    return .orderedAscending
                } else if rhs.seriesIndex > lhs.seriesIndex {
                    return .orderedDescending
                } else {
                    return .orderedSame
                }
            }
        }
    }
}


extension CalibreServerService {
    func buildLibrarySearchTask(library: CalibreLibrary, searchCriteria: SearchCriteria) -> CalibreLibrarySearchTask? {
        guard let serverUrl =
                modelData.librarySyncStatus[library.id]?.isError == true
                ?
                URL(fileURLWithPath: "/realm")
                :
                (
                    getServerUrlByReachability(server: library.server)
                    ??
                    (
                        (library.autoUpdate || library.server.isLocal)
                        ?
                        URL(fileURLWithPath: "/realm")
                        :
                        nil
                    )
                )
        else { return nil }
        
        let searchPrevResult = modelData.librarySearchCache.getCache(
            for: library,
            of: searchCriteria,
            by: serverUrl.isFileURL ? .offline : .online
        )
        
        guard searchPrevResult.loading == false
        else { return nil }
        
        var booksListUrlComponents = URLComponents()
        booksListUrlComponents.path = "ajax/search/\(library.key)"
        
        var booksListUrlQueryItems = [URLQueryItem]()
        
        booksListUrlQueryItems.append(URLQueryItem(name: "sort", value: searchCriteria.sortCriteria.by.sortQueryParam))
        booksListUrlQueryItems.append(URLQueryItem(name: "sort_order", value: searchCriteria.sortCriteria.ascending ? "asc" : "desc"))
        
        let maxMergedOffset = modelData.searchCriteriaMergedResults.compactMap {
            $0.value.mergedPageOffsets[library.id]?.offsets.last
        }.max() ?? 0
        
        let searchedOffset = searchPrevResult.bookIds.count
        let searchNum = maxMergedOffset + searchCriteria.pageSize - searchedOffset
        guard searchNum >= 0 else {
            return nil
        }
        
        booksListUrlQueryItems.append(.init(name: "offset", value: searchedOffset.description))
        booksListUrlQueryItems.append(.init(name: "num", value: searchNum.description))
        
        var queryStrings = [String]()
        if searchCriteria.searchString.isEmpty == false {
            queryStrings.append(searchCriteria.searchString)
        }
        searchCriteria.filterCriteriaCategory.forEach { entry in
            var queryKey = entry.key.lowercased()
            var queryIsRating = entry.key == "Rating"
            
            if let customColumnInfo = library.customColumnInfos.filter({ $0.value.name == entry.key }).first {
                queryKey = "#\(customColumnInfo.key)"
                queryIsRating = customColumnInfo.value.datatype == "rating"
            }
            
            let q = entry.value.map {
                "\(queryKey):" + (queryIsRating ? "\($0.count)" : "\"=\($0)\"")
            }.joined(separator: " OR ")
            if q.isEmpty == false {
                queryStrings.append("( " + q + " )")
            }
        }
        
        booksListUrlQueryItems.append(.init(name: "query", value: queryStrings.joined(separator: " AND ")))
        
        booksListUrlComponents.queryItems = booksListUrlQueryItems
        
        guard let booksListUrl = booksListUrlComponents.url(relativeTo: serverUrl)?.absoluteURL else {
            return nil
        }
        
        return CalibreLibrarySearchTask(
            library: library,
            searchCriteria: searchCriteria,
            booksListUrl: booksListUrl,
            offset: searchedOffset,
            num: searchNum
        )
    }
    
    func searchLibraryBooks(task: CalibreLibrarySearchTask) -> AnyPublisher<CalibreLibrarySearchTask, URLError> {
        if task.booksListUrl.isHTTP {
            return urlSession(server: task.library.server).dataTaskPublisher(for: task.booksListUrl)
                .map { result -> CalibreLibrarySearchTask in
                    var task = task
                    do {
                        task.ajaxSearchResult = try JSONDecoder().decode(CalibreLibraryBooksResult.SearchResult.self, from: result.data)
                    } catch {
                        task.ajaxSearchError = true
                    }
                    return task
                }
                .eraseToAnyPublisher()
        }
        if task.booksListUrl.isFileURL,
           let urlComponents = URLComponents(url: task.booksListUrl, resolvingAgainstBaseURL: false) {    //search offline realm
            var task = task
            
            let libraryPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                    NSPredicate(format: "serverUUID = %@", task.library.server.uuid.uuidString),
                    NSPredicate(format: "libraryName = %@", task.library.name)
                ])
            
            var predicates = [NSPredicate]()
            let searchTerms = task.searchCriteria.searchString
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split { $0.isWhitespace }
                .map { String($0) }
            if searchTerms.isEmpty == false {
                predicates.append(contentsOf:
                    searchTerms.map {
                        NSCompoundPredicate(orPredicateWithSubpredicates: [
                            NSPredicate(format: "title CONTAINS[c] %@", $0),
                            NSPredicate(format: "authorFirst CONTAINS[c] %@", $0),
                            NSPredicate(format: "authorSecond CONTAINS[c] %@", $0)
                        ])
                    }
                )
            }

            predicates = task.searchCriteria.filterCriteriaCategory.reduce(into: predicates) { partialResult, categoryFilter in
                guard categoryFilter.value.isEmpty == false else { return }
                
                switch categoryFilter.key {
                case "Tags":
                    partialResult.append(
                        NSCompoundPredicate(
                            orPredicateWithSubpredicates:
                                categoryFilter.value.map ({
                                    NSCompoundPredicate(orPredicateWithSubpredicates: [
                                        NSPredicate(format: "tagFirst = %@", $0),
                                        NSPredicate(format: "tagSecond = %@", $0),
                                        NSPredicate(format: "tagThird = %@", $0)
                                    ])
                                    
                                })
                        )
                    )
                case "Authors":
                    partialResult.append(
                        NSCompoundPredicate(
                            orPredicateWithSubpredicates:
                                categoryFilter.value.map ({
                                    NSCompoundPredicate(orPredicateWithSubpredicates: [
                                        NSPredicate(format: "authorFirst = %@", $0),
                                        NSPredicate(format: "authorSecond = %@", $0),
                                        NSPredicate(format: "authorThird = %@", $0)
                                    ])
                                    
                                })
                        )
                    )
                case "Series":
                    partialResult.append(
                        NSCompoundPredicate(
                            orPredicateWithSubpredicates:
                                categoryFilter.value.map ({
                                    NSPredicate(format: "series = %@", $0)
                                })
                        )
                    )
                case "Publisher":
                    partialResult.append(
                        NSCompoundPredicate(
                            orPredicateWithSubpredicates:
                                categoryFilter.value.map ({
                                    NSPredicate(format: "publisher = %@", $0)
                                })
                        )
                    )
                case "Rating":
                    partialResult.append(
                        NSCompoundPredicate(
                            orPredicateWithSubpredicates:
                                categoryFilter.value.map ({
                                    NSPredicate(format: "rating = %@", NSNumber(value: $0.count * 2))
                                })
                        )
                    )
                case "Languages":   //not recorded in realm
                    partialResult.append(NSPredicate(value: false))
                default:    //unrecognized
                    partialResult.append(NSPredicate(value: false))
                }
            }
            
            if let realm = try? Realm(configuration: modelData.realmConf) {
                let allbooks = realm.objects(CalibreBookRealm.self)
                    .filter(libraryPredicate)
                    .sorted(byKeyPath: task.searchCriteria.sortCriteria.by.sortKeyPath, ascending: task.searchCriteria.sortCriteria.ascending)
                let filteredBooks = allbooks.filter(NSCompoundPredicate(andPredicateWithSubpredicates: predicates))
                
                let offset = Int(urlComponents.queryItems?.first(where: { $0.name == "offset" })?.value ?? "0") ?? 0
                let num = Int(urlComponents.queryItems?.first(where: { $0.name == "num" })?.value ?? "100") ?? 100
                
                if offset <= filteredBooks.count {
                    let bookIds : [Int32] = filteredBooks[offset..<min(offset+num, filteredBooks.endIndex)]
                        .map {
                            $0.id
                        }
                    
                    task.ajaxSearchResult = .init(total_num: filteredBooks.count, sort_order: task.searchCriteria.sortCriteria.ascending ? "asc" : "desc", num_books_without_search: allbooks.count, offset: offset, num: bookIds.count, sort: task.searchCriteria.sortCriteria.by.sortQueryParam, base_url: "", library_id: task.library.key, book_ids: bookIds, vl: "")
                    
                    return Just(task).setFailureType(to: URLError.self).eraseToAnyPublisher()
                }
            }
        }
        
        return Fail(error: URLError(.badURL)).eraseToAnyPublisher()
    }
    
    func registerLibrarySearchHandler() {
        let queue = DispatchQueue(label: "library-search", qos: .userInitiated)
        modelData.librarySearchRequestSubject.receive(on: DispatchQueue.main)
            .map({ task -> CalibreLibrarySearchTask in
                let librarySearchKey = LibrarySearchKey(libraryId: task.library.id, criteria: task.searchCriteria)
                
                let prevResult = modelData.librarySearchCache.getCache(
                    for: task.library,
                    of: task.searchCriteria,
                    by: task.booksListUrl.isFileURL ? .offline : .online
                )
                
                print("\(#function) id=\(task.id) librarySearchKey=\(librarySearchKey) fire num=\(task.num) offset=\(task.offset) prevCount=\(prevResult.bookIds.count) prevOffline=\(prevResult.offlineResult) offline=\(task.booksListUrl.isFileURL && !task.library.server.isLocal) prevLoading=\(prevResult.loading)")
                
                if librarySearchKey.libraryId == "Calibre-Default@0FB2EFE0-6C43-4E05-A86E-815E5B21D989", librarySearchKey.criteria == .init(searchString: "", sortCriteria: .init(), filterCriteriaCategory: [:]) {
                    print()
                }
                
                modelData.librarySearchCache.startLoading(
                    for: task.library,
                    of: task.searchCriteria,
                    by: task.booksListUrl.isFileURL ? .offline : .online
                )
                
                modelData.filteredBookListRefreshingSubject.send("")
                
                print("\(#function) id=\(task.id) searchUrl=\(task.booksListUrl.absoluteString)")
                
                return task
            })
            .receive(on: queue)
            .flatMap({ task -> AnyPublisher<CalibreLibrarySearchTask, Never> in
                var errorTask = task
                errorTask.ajaxSearchError = true
                
                if task.num > 0 {
                    return modelData.calibreServerService.searchLibraryBooks(task: task)
                        .replaceError(with: errorTask)
                        .eraseToAnyPublisher()
                } else {
                    return Just(errorTask).setFailureType(to: Never.self).eraseToAnyPublisher()
                }
            })
            .receive(on: ModelData.SearchLibraryResultsRealmQueue)
            .flatMap { searchTask -> AnyPublisher<CalibreBooksTask, Never> in
                let serverUUID = searchTask.library.server.uuid.uuidString
                
                if let realm = modelData.searchLibraryResultsRealmQueue,
                      let books = searchTask.ajaxSearchResult?.book_ids
                    .filter({ realm.object(
                        ofType: CalibreBookRealm.self,
                        forPrimaryKey:
                            CalibreBookRealm.PrimaryKey(
                                serverUUID: serverUUID,
                                libraryName: searchTask.library.name,
                                id: $0.description
                            )) == nil })
                    .map({ CalibreBook(id: $0, library: searchTask.library) }),
                   books.isEmpty == false,
                   let metaTask = buildBooksMetadataTask(library: searchTask.library, books: books, searchTask: searchTask) {
                    return modelData.calibreServerService.getBooksMetadata(task: metaTask)
                        .replaceError(with: metaTask)
                        .eraseToAnyPublisher()
                } else {
                    let dummyURL = URL(fileURLWithPath: "/realm")
                    let metaTask = buildBooksMetadataTask(library: searchTask.library, books: [], searchTask: searchTask) ??
                    CalibreBooksTask(request: .init(library: searchTask.library, books: [], getAnnotations: false), metadataUrl: dummyURL, lastReadPositionUrl: dummyURL, annotationsUrl: dummyURL, searchTask: searchTask)
                    return Just(metaTask)
                        .setFailureType(to: Never.self)
                        .eraseToAnyPublisher()
                }
            }
            .receive(on: ModelData.SearchLibraryResultsRealmQueue)
            .map { task -> CalibreBooksTask in
                let serverUUID = task.library.server.uuid.uuidString
                
                if let booksMetadataEntry = task.booksMetadataEntry,
                   let booksMetadataJSON = task.booksMetadataJSON,
                   let searchLibraryResultsRealm = modelData.searchLibraryResultsRealmQueue {
                    let realmBooks = booksMetadataEntry.compactMap { metadataEntry -> CalibreBookRealm? in
                        guard let entry = metadataEntry.value,
                              let bookId = Int32(metadataEntry.key)
                        else { return nil }
                        
                        let obj = CalibreBookRealm()
                        obj.serverUUID = serverUUID
                        obj.libraryName = task.library.name
                        obj.id = bookId
                        
                        modelData.calibreServerService.handleLibraryBookOne(library: task.library, bookRealm: obj, entry: entry, root: booksMetadataJSON)
                        
                        return obj
                    }
                    
                    try? searchLibraryResultsRealm.write{
                        searchLibraryResultsRealm.add(realmBooks, update: .modified)
                    }
                }
                
                return task
            }
            .receive(on: DispatchQueue.main)
            .sink { task in
                guard let searchTask = task.searchTask else { return }
                
                let librarySearchKey = LibrarySearchKey(libraryId: task.library.id, criteria: searchTask.searchCriteria)
                let prevResult = modelData.librarySearchCache.getCache(for: searchTask.library, of: searchTask.searchCriteria, by: searchTask.booksListUrl.isFileURL ? .offline : .online)
                
                if let searchResult = searchTask.ajaxSearchResult {
                    if searchResult.total_num > 0,
                        prevResult.totalNumber == 0 {
                        //trigger list remerge
                        modelData.librarySearchCache.setIsError(
                            for: searchTask.library,
                            of: searchTask.searchCriteria,
                            by: searchTask.booksListUrl.isFileURL ? .offline : .online,
                            to: true
                        )
                    }
                    modelData.librarySearchCache.setTotalNumber(
                        for: searchTask.library,
                        of: searchTask.searchCriteria,
                        by: searchTask.booksListUrl.isFileURL ? .offline : .online,
                        to: searchResult.total_num
                    )
                    
                    print("\(#function) id=\(searchTask.id) librarySearchKey=\(librarySearchKey) result num=\(searchResult.num) tn=\(searchResult.total_num) offset=\(searchResult.offset) prevCount=\(prevResult.bookIds.count) offline=\(searchTask.booksListUrl.isFileURL && !searchTask.library.server.isLocal)")
                    
                    guard prevResult.bookIds.count == searchResult.offset,
                          Set(prevResult.bookIds).union(Set(searchResult.book_ids)).count == prevResult.bookIds.count + searchResult.book_ids.count
                    else {
                        //duplication, reset search result
                        print("\(#function) duplicate id=\(searchTask.id) librarySearchKey=\(librarySearchKey) mismatch_or_duplicate num=\(searchResult.num) tn=\(searchResult.total_num) offset=\(searchResult.offset) prevCount=\(prevResult.bookIds.count)")
                        
                        modelData.librarySearchCache.resetCache(
                            for: searchTask.library,
                            of: searchTask.searchCriteria,
                            by: searchTask.booksListUrl.isFileURL ? .offline : .online
                        )
                        
                        if let newTask = modelData.calibreServerService.buildLibrarySearchTask(library: searchTask.library, searchCriteria: searchTask.searchCriteria) {
                            modelData.librarySearchRequestSubject.send(newTask)
                        }
                        
                        return
                    }
                        
                    modelData.librarySearchCache.appendResult(
                        for: searchTask.library,
                        of: searchTask.searchCriteria,
                        by: searchTask.booksListUrl.isFileURL ? .offline : .online,
                        contentsOf: searchResult.book_ids
                    )
                    
                    print("\(#function) finishLoading id=\(searchTask.id) library=\(task.library.key) \(searchResult.num) \(searchResult.total_num)")
                    
                    modelData.librarySearchResultSubject.send(searchTask)
                } else if searchTask.ajaxSearchError {
                    print("\(#function) ajaxSearchError id=\(searchTask.id) library=\(task.library.key)")
                    
                    modelData.librarySearchCache.setIsError(
                        for: searchTask.library,
                        of: searchTask.searchCriteria,
                        by: searchTask.booksListUrl.isFileURL ? .offline : .online,
                        to: searchTask.num > 0
                    )
                    
                    modelData.librarySearchCache.finishLoading(
                        for: searchTask.library,
                        of: searchTask.searchCriteria,
                        by: searchTask.booksListUrl.isFileURL ? .offline : .online
                    )
                }
            }.store(in: &modelData.calibreCancellables)
        
        modelData.librarySearchResultSubject.collect(.byTime(RunLoop.main, .seconds(2)))
            .sink { tasks in
                tasks.reduce(into: Set<SearchCriteriaMergedKey>()) { partialResult, task in
                    let librarySearchKey = LibrarySearchKey(libraryId: task.library.id, criteria: task.searchCriteria)
                    let searchResult = modelData.librarySearchCache.getCache(
                        for: task.library,
                        of: task.searchCriteria,
                        by: task.booksListUrl.isFileURL ? .offline : .online
                    )
                    partialResult.formUnion(
                        self.modelData.searchCriteriaMergedResults.filter {
                            guard let mergedPageOffset = $0.value.mergedPageOffsets[librarySearchKey.libraryId]
                            else { return false }
                            
                            return mergedPageOffset.beenCutOff == true
                            &&
                            mergedPageOffset.cutOffOffset < searchResult.bookIds.count
                        }.keys
                    )
                    
                    modelData.librarySearchCache.finishLoading(
                        for: task.library,
                        of: task.searchCriteria,
                        by: task.booksListUrl.isFileURL ? .offline : .online
                    )
                }.forEach {
                    //prevent animation gap in LibraryInfoView
                    modelData.searchCriteriaMergedResults[$0]?.merging = true
                    
                    modelData.filteredBookListMergeSubject.send($0)
                }
                
                modelData.filteredBookListRefreshingSubject.send("")
            }.store(in: &modelData.calibreCancellables)
    }
    
    func registerFilteredBookListMergeHandler() {
        modelData.filteredBookListMergeSubject.receive(on: DispatchQueue.main)
            .map { searchCriteriaResultKey -> SearchCriteriaMergedKey in
                if modelData.searchCriteriaMergedResults[searchCriteriaResultKey] == nil {
                    modelData.searchCriteriaMergedResults[searchCriteriaResultKey] = .init(libraryIds: searchCriteriaResultKey.libraryIds)
                    
                }
                modelData.searchCriteriaMergedResults[searchCriteriaResultKey]?.merging = true
                
                modelData.filteredBookListRefreshingSubject.send("")
                
                return searchCriteriaResultKey
            }
            .receive(on: ModelData.SearchLibraryResultsRealmQueue)
            .map { searchCriteriaMergedKey -> (SearchCriteriaMergedKey, LibrarySearchCriteriaResultMerged) in
                print("\(#function) librarySearchKey=\(searchCriteriaMergedKey)")
                
                var mergedResult = modelData.searchCriteriaMergedResults[searchCriteriaMergedKey]!
                
                let searchResults = modelData.librarySearchCache.getCaches(
                    for: searchCriteriaMergedKey.libraryIds,
                    of: searchCriteriaMergedKey.criteria
                )
                
                mergedResult.totalNumber = searchResults.values.map { $0.totalNumber }
                    .reduce(0, +)

                mergedResult = modelData.mergeBookListsNew(
                    mergeKey: searchCriteriaMergedKey,
                    mergedResult: mergedResult,
                    page: modelData.filteredBookListPageNumber,
                    limit: modelData.filteredBookListPageSize
                )
                
                return (searchCriteriaMergedKey, mergedResult)
            }
            .receive(on: DispatchQueue.main)
            .map { searchCriteriaMergedKey, mergedResult -> LibrarySearchCriteriaResultMerged in
                
                modelData.searchCriteriaMergedResults[searchCriteriaMergedKey] = mergedResult
                print("\(#function) library=\(searchCriteriaMergedKey) merged=\(mergedResult.mergedBooks.count)")
                
                modelData.searchCriteriaMergedResults[searchCriteriaMergedKey]?.merging = false
                
                mergedResult.mergedPageOffsets.forEach { mergedPageOffset in
                    guard let library = modelData.calibreLibraries[mergedPageOffset.key]
                    else { return }
                    
                    let searchResult = modelData.librarySearchCache.getCache(
                        for: library,
                        of: searchCriteriaMergedKey.criteria
                    )
                    
                    guard searchCriteriaMergedKey.libraryIds.isEmpty || searchCriteriaMergedKey.libraryIds.contains(mergedPageOffset.key)
                    else { return }
                        
                    if searchResult.error == false,
                       searchResult.totalNumber == searchResult.bookIds.count {
                        //reached full list
                        return
                    }
                    
                    if mergedPageOffset.value.beenCutOff
                        ||
                        (
                            (
                                (mergedPageOffset.value.offsets.last ?? 0)
                                +
                                modelData.filteredBookListPageSize
                            )
                            >=
                            searchResult.bookIds.count
                        ) {
                        if let library = modelData.calibreLibraries[mergedPageOffset.key],
                           let task = modelData.calibreServerService.buildLibrarySearchTask(library: library, searchCriteria: searchCriteriaMergedKey.criteria) {
                            modelData.librarySearchRequestSubject.send(task)
                        }
                    }
                }
                
                if searchCriteriaMergedKey == modelData.currentLibrarySearchResultKey {
                    modelData.filteredBookListPageCount = Int((Double(mergedResult.totalNumber) / Double(modelData.filteredBookListPageSize)).rounded(.up))
                }
                
                return mergedResult
            }
            .sink(receiveValue: { librarySearchMergeResult in
                modelData.filteredBookListRefreshingSubject.send("")
            })
            .store(in: &modelData.calibreCancellables)
    }
    
    
    func registerLibrarySearchResetHandler() {
        modelData.librarySearchResetSubject.subscribe(on: DispatchQueue.main)
            .sink(receiveCompletion: { completion in
                
            }, receiveValue: { librarySearchKey in
                if librarySearchKey.libraryId.isEmpty {
                    let keysToRemove = modelData.searchCriteriaMergedResults.filter {
                        $0.key.criteria == librarySearchKey.criteria
                    }.map { $0.key }
                    keysToRemove.forEach {
                        modelData.searchCriteriaMergedResults.removeValue(forKey: $0)
                    }
                } else {
                    if let library = modelData.calibreLibraries[librarySearchKey.libraryId] {
                        modelData.librarySearchCache.resetCache(for: library, of: librarySearchKey.criteria, by: .online)
                    }
                }
            })
            .store(in: &modelData.calibreCancellables)
    }
    
    func registerLibraryCategoryHandler() {
        let queue = DispatchQueue.init(label: "library-category", qos: .userInitiated)
        modelData.libraryCategorySubject
            .receive(on: queue)
            .flatMap { request -> AnyPublisher<LibraryCategoryList, Never> in
                let just = Just(request).setFailureType(to: Never.self).eraseToAnyPublisher()
                guard let serverUrl = getServerUrlByReachability(server: request.library.server)
                else { return just }
                
                var urlComponents = URLComponents(string: request.category.url)
                urlComponents?.queryItems = [
                    URLQueryItem(name: "num", value: request.num.description),
                    URLQueryItem(name: "offset", value: request.offset.description)
                ]
                guard let url = urlComponents?.url(relativeTo: serverUrl)
                else { return just }
                
                return urlSession(server: request.library.server).dataTaskPublisher(for: url)
                    .map {
                        $0.data
                    }
                    .decode(type: LibraryCategoryListResult.self, decoder: JSONDecoder())
                    .map { result -> LibraryCategoryList in
                        var request = request
                        request.result = result
                        return request
                    }
                    .replaceError(with: request)
                    .eraseToAnyPublisher()
            }
            .receive(on: DispatchQueue.main)
            .sink { completion in
                
            } receiveValue: { value in
                guard let result = value.result
                else { return }
                
                print("\(#function) category=\(value.category) reqId=\(value.reqId) totalNum=\(result.total_num) num=\(result.num) offset=\(result.offset)")

                let key = CalibreLibraryCategoryKey(libraryId: value.library.id, categoryName: value.category.name)
                if modelData.calibreLibraryCategories[key] == nil {
                    modelData.calibreLibraryCategories[key] = .init(reqId: 0, totalNumber: 0, items: [])
                }
                if (modelData.calibreLibraryCategories[key]?.reqId ?? 0) < value.reqId,
                   (modelData.calibreLibraryCategories[key]?.totalNumber ?? 0) != result.total_num {
                    modelData.calibreLibraryCategories[key]?.reqId = value.reqId
                    modelData.calibreLibraryCategories[key]?.totalNumber = result.total_num
                    modelData.calibreLibraryCategories[key]?.items.removeAll(keepingCapacity: true)
                    modelData.calibreLibraryCategories[key]?.items.reserveCapacity(result.total_num)
                }
                guard modelData.calibreLibraryCategories[key]?.reqId == value.reqId
                else { return }
                
                if result.offset + result.items.count < result.total_num {
                    modelData.libraryCategorySubject.send(
                        .init(
                            library: value.library,
                            category: value.category,
                            reqId: value.reqId,
                            offset: result.offset + result.items.count,
                            num: 1000
                        )
                    )
                }
                
                guard result.items.isEmpty == false
                else { return }
                
                if (modelData.calibreLibraryCategories[key]?.items.count ?? 0) < (result.offset + result.items.count) {
                    let dummyItem = LibraryCategoryListResult.Item(name: "", average_rating: 0, count: 0, url: "", has_children: false)
                    modelData.calibreLibraryCategories[key]?.items.append(
                        contentsOf:
                            Array(
                                repeating: dummyItem,
                                count: (result.offset + result.items.count) - (modelData.calibreLibraryCategories[key]?.items.count ?? 0)
                            )
                    )
                }
                
                modelData.calibreLibraryCategories[key]?.items.replaceSubrange(result.offset..<(result.offset+result.items.count), with: result.items)
                
                if modelData.calibreLibraryCategories[key]?.items.count == result.total_num {
                    modelData.libraryCategoryMergeSubject.send(key.categoryName)
                }
            }.store(in: &modelData.calibreCancellables)

    }
    
    func registerLibraryCategoryMergeHandler() {
        let queue = DispatchQueue(label: "library-category-merge", qos: .userInitiated)
        modelData.libraryCategoryMergeSubject
            .receive(on: queue)
            .map { categoryName -> (String, [String]) in
                (
                    categoryName,
                    modelData.calibreLibraryCategories
                        .filter {
                            $0.key.categoryName == categoryName && $0.value.items.count == $0.value.totalNumber
                        }
                        .reduce(into: Set<String>()) { partialResult, category in
                            partialResult.formUnion(category.value.items.map { $0.name })
                        }
                        .sorted()
                 )
            }
            .receive(on: DispatchQueue.main)
            .sink { entry in
                modelData.calibreLibraryCategoryMerged[entry.0] = entry.1
                
                modelData.categoryItemListSubject.send(entry.0)
            }
            .store(in: &modelData.calibreCancellables)
    }
}
