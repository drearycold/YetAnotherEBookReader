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

struct LibrarySearchCriteria: Hashable {
    let searchString: String
    let sortCriteria: LibrarySearchSort
    let filterCriteriaCategory: [String: Set<String>]
    let filterCriteriaLibraries: Set<String>
    let pageSize: Int = 100
    
    var hasEmptyFilter: Bool {
        filterCriteriaCategory.isEmpty
        && filterCriteriaLibraries.isEmpty
    }
}

struct LibrarySearchCriteriaResultMerged {
    var books = [CalibreBook]()
    var pageNo = 0
    var pageCount = 0
    var pageSize = 100
    var merging = false
}

struct LibrarySearchKey: Hashable {
    let libraryId: String
    let criteria: LibrarySearchCriteria
}

struct LibrarySearchResult {
    let library: CalibreLibrary
    var loading = false
    var offlineResult = false
    var error = false
    var errorOffset = 0
    var totalNumber = 0
    var pageOffset = [Int: Int]()    //key: browser page no, value: offset in bookIds
    var bookIds = [Int32]()
    
    var description: String {
        "\(bookIds.count)/\(totalNumber)"
    }
}

struct LibrarySearchMergeResult {
    let libraryId: String
    let criteria: LibrarySearchCriteria
    
    var totalNumber = 0
    var mergeResults: [String : LibrarySearchResult] = [:]
    var mergedBooks: [CalibreBook] = []
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
        if let obj = getBookRealm(forPrimaryKey: primaryKey),
           let book = convert(bookRealm: obj) {
            return book
        } else if let obj = searchLibraryResultsRealmMainThread?.object(ofType: CalibreBookRealm.self, forPrimaryKey: primaryKey),
                  let book = convert(bookRealm: obj) {
            return book
        }
        return nil
    }
    
    var currentLibrarySearchCriteria: LibrarySearchCriteria {
        LibrarySearchCriteria(
            searchString: self.searchString,
            sortCriteria: self.sortCriteria,
            filterCriteriaCategory: self.filterCriteriaCategory,
            filterCriteriaLibraries: self.filterCriteriaLibraries
        )
    }
    
    var currentSearchLibraryResults: [LibrarySearchKey: LibrarySearchResult] {
        let searchCriteria = self.currentLibrarySearchCriteria
        return self.searchLibraryResults.filter { $0.key.criteria == searchCriteria }
    }
    
    var currentSearchLibraryResultsCannotFurther: Bool {
        guard let maxPage = self.currentSearchLibraryResults.flatMap({ result -> [Int] in
            result.value.pageOffset.filter {
                (result.value.error || result.value.loading) ? $0.value < result.value.errorOffset : true
            }.keys.map { $0 } }).max()
        else { return true }
        
        return self.filteredBookListPageNumber + 1 == maxPage
    }
    
    func mergeBookLists(results: inout [String : LibrarySearchResult], sortCriteria: LibrarySearchSort, page: Int = 0, limit: Int = 100) -> [CalibreBook] {
        guard let realm = try? Realm(configuration: realmConf),
              let realmSearch = searchLibraryResultsRealmQueue
        else { return [] }
        
        var merged = [CalibreBook]()
        
        var startPage = page
        while startPage > 0 {
            if results.allSatisfy({
                $0.value.pageOffset[startPage] != nil
                || ($0.value.pageOffset.max(by: { $0.key < $1.key })?.value ?? 0) >= $0.value.totalNumber
            }) {
                break
            }
            startPage -= 1
        }
        
        var headIndex = [String: Int]()
        results.forEach {
            if startPage == 0 {
                headIndex[$0.key] = 0
            } else if let offset = $0.value.pageOffset[startPage] {
                headIndex[$0.key] = offset
                
                if offset < $0.value.bookIds.count  {
                    results[$0.key]?.error = false
                }
            }
        }
        
        headIndex.forEach {
            print("LIBRARYINFOVIEW headIndex \($0)")
        }
        
        var heads = results.compactMap { entry -> CalibreBookRealm? in
            guard let headOffset = headIndex[entry.value.library.id],
                  headOffset < entry.value.bookIds.count
            else { return nil }
            let primaryKey = CalibreBookRealm.PrimaryKey(
                serverUUID: entry.value.library.server.uuid.uuidString,
                libraryName: entry.value.library.name,
                id: entry.value.bookIds[headOffset].description
            )
            
            let obj = realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: primaryKey)
            ?? realmSearch.object(ofType: CalibreBookRealm.self, forPrimaryKey: primaryKey)
            
            print("LIBRARYINFOVIEW headObj=\(obj) primaryKey=\(primaryKey)")
            
            return obj
        }
        
        print("LIBRARYINFOVIEW heads=\(heads.count)")
        
        // sort in reverse so we can use popLast() (O(1)) to merge
        let sortComparator = MergeSortComparator(criteria: sortCriteria.by, order: sortCriteria.ascending ? .reverse : .forward)
        heads.sort(using: sortComparator)
        
        let mergeLength = limit + (page - startPage) * limit
        while merged.count < mergeLength, let head = heads.popLast() {
            if let book = self.convert(bookRealm: head) {
                merged.append(book)
            }
            
            let headLibraryId = CalibreLibraryRealm.PrimaryKey(serverUUID: head.serverUUID!, libraryName: head.libraryName!)
            guard let searchResult = results[headLibraryId] else { continue }
            
            headIndex[headLibraryId]? += 1
            
            guard let headOffset = headIndex[headLibraryId],
                  headOffset < searchResult.bookIds.count else {
                if searchResult.bookIds.count < searchResult.totalNumber {
                    results[headLibraryId]?.error = true
                    results[headLibraryId]?.errorOffset = searchResult.bookIds.count
                }
                continue
            }
            
            let primaryKey = CalibreBookRealm.PrimaryKey(
                serverUUID: searchResult.library.server.uuid.uuidString,
                libraryName: searchResult.library.name,
                id: searchResult.bookIds[headOffset].description
            )
            
            guard let next = realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: primaryKey)
            ?? realmSearch.object(ofType: CalibreBookRealm.self, forPrimaryKey: primaryKey)
            else {
                continue
            }
            
            heads.append(next)
            heads.sort(using: sortComparator)
            
            if merged.count % limit == 0 {
                let currentPage = (merged.count / limit) + startPage
                headIndex.forEach {
                    results[$0.key]?.pageOffset[currentPage] = $0.value
                }
            }
            
        }
        
        let resultLength = merged.count - (page - startPage) * limit
        if resultLength > 0 {
            return merged.suffix(resultLength)
        } else {
            return []
        }
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
    func buildLibrarySearchTask(library: CalibreLibrary, searchCriteria: LibrarySearchCriteria) -> CalibreLibrarySearchTask? {
        guard let serverUrl =
                modelData.librarySyncStatus[library.id]?.isError == true
                ? URL(fileURLWithPath: "/realm")
                : (
                    getServerUrlByReachability(server: library.server) ?? (
                        (library.autoUpdate || library.server.isLocal)
                        ? URL(fileURLWithPath: "/realm")
                        : nil
                    )
                )
        else { return nil }
        
        var booksListUrlComponents = URLComponents()
        booksListUrlComponents.path = "ajax/search/\(library.key)"
        
        var booksListUrlQueryItems = [URLQueryItem]()
        
        booksListUrlQueryItems.append(URLQueryItem(name: "sort", value: searchCriteria.sortCriteria.by.sortQueryParam))
        booksListUrlQueryItems.append(URLQueryItem(name: "sort_order", value: searchCriteria.sortCriteria.ascending ? "asc" : "desc"))
        
        if let searchPreviousResult = modelData.searchLibraryResults[.init(libraryId: library.id, criteria: searchCriteria)] {
            booksListUrlQueryItems.append(URLQueryItem(name: "offset", value: searchPreviousResult.bookIds.count.description))
            let maxOffset = searchPreviousResult.pageOffset.values.max() ?? 0
            let num = max(0, maxOffset + searchCriteria.pageSize * 2 - searchPreviousResult.bookIds.count)
            booksListUrlQueryItems.append(.init(name: "num", value: num.description))
        } else {
            booksListUrlQueryItems.append(.init(name: "num", value: (searchCriteria.pageSize * 2).description))
        }
        
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
            booksListUrl: booksListUrl
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
            
//            if task.searchCriteria.filterCriteriaShelved != .none {
//                predicates.append(
//                    NSPredicate(format: "inShelf = %@", modelData.filterCriteriaShelved == .shelvedOnly)
//                )
//            }
            
            if let realm = try? Realm(configuration: modelData.realmConf) {
                let allbooks = realm.objects(CalibreBookRealm.self).filter(libraryPredicate)
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
        
//        return Just(task).setFailureType(to: URLError.self).eraseToAnyPublisher()
    }
    
    func registerLibrarySearchHandler() {
        modelData.librarySearchSubject
            .subscribe(on: DispatchQueue.global(qos: .userInitiated))
            .receive(on: DispatchQueue.main)
            .compactMap { librarySearchKey -> CalibreLibrarySearchTask? in
                guard let library = modelData.calibreLibraries[librarySearchKey.libraryId]
                else {
                    return nil
                }
                
                if modelData.searchLibraryResults[librarySearchKey] == nil {
                    modelData.searchLibraryResults[librarySearchKey] = .init(library: library, error: true)
                }
                
                guard let task = modelData.calibreServerService.buildLibrarySearchTask(
                    library: library,
                    searchCriteria: librarySearchKey.criteria
                ) else {
                    return nil
                }
                
                modelData.searchLibraryResults[librarySearchKey]?.offlineResult = (task.booksListUrl.isFileURL && !task.library.server.isLocal)
                modelData.searchLibraryResults[librarySearchKey]?.loading = true

                modelData.filteredBookListRefreshingSubject.send("")
                
                print("\(#function) searchUrl=\(task.booksListUrl.absoluteString)")
                
                return task
            }
            .receive(on: DispatchQueue.global(qos: .userInitiated))
            .flatMap({ task -> AnyPublisher<CalibreLibrarySearchTask, Never> in
                var errorTask = task
                errorTask.ajaxSearchError = true
                return modelData.calibreServerService.searchLibraryBooks(task: task)
                    .replaceError(with: errorTask)
                    .eraseToAnyPublisher()
            })
            .receive(on: DispatchQueue.main)
            .compactMap { task -> CalibreLibrarySearchTask? in
                guard task.ajaxSearchResult != nil else {
                    let librarySearchKey = LibrarySearchKey(libraryId: task.library.id, criteria: task.searchCriteria)
                    
                    modelData.searchLibraryResults[librarySearchKey]?.loading = false

                    modelData.filteredBookListRefreshingSubject.send("")

                    return nil
                }
                
                return task
            }
            .receive(on: ModelData.SearchLibraryResultsRealmQueue)
            .compactMap { task -> CalibreBooksTask? in
                let serverUUID = task.library.server.uuid.uuidString
                
                guard let realm = modelData.searchLibraryResultsRealmQueue,
                      let books = task.ajaxSearchResult?.book_ids
                    .filter({ realm.object(
                        ofType: CalibreBookRealm.self,
                        forPrimaryKey:
                            CalibreBookRealm.PrimaryKey(
                                serverUUID: serverUUID,
                                libraryName: task.library.name,
                                id: $0.description
                            )) == nil })
                    .map({ CalibreBook(id: $0, library: task.library) })
                else {
                    return nil
                }
                
                return buildBooksMetadataTask(library: task.library, books: books, searchTask: task)
            }
            .receive(on: DispatchQueue.global(qos: .userInitiated))
            .flatMap { task -> AnyPublisher<CalibreBooksTask, Never> in
                modelData.calibreServerService.getBooksMetadata(task: task)
                    .replaceError(with: task)
                    .eraseToAnyPublisher()
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
            .map { task -> CalibreBooksTask in
                guard let searchTask = task.searchTask else { return task }
                
                let librarySearchKey = LibrarySearchKey(libraryId: task.library.id, criteria: searchTask.searchCriteria)
                if let searchResult = searchTask.ajaxSearchResult {
                    if searchResult.total_num > 0,
                       (modelData.searchLibraryResults[librarySearchKey]?.totalNumber ?? 0) == 0 {
                        modelData.searchLibraryResults[librarySearchKey]?.error = true  //trigger list remerge
                        modelData.searchLibraryResults[librarySearchKey]?.errorOffset = 0
                    }
                    modelData.searchLibraryResults[librarySearchKey]?.totalNumber = searchResult.total_num
                    if modelData.searchLibraryResults[librarySearchKey]?.bookIds.count == searchResult.offset {
                        modelData.searchLibraryResults[librarySearchKey]?.bookIds.append(contentsOf: searchResult.book_ids)
                    } else {
                        print("\(#function) library=\(task.library.key) mismatch \(searchResult.num) \(searchResult.total_num) \(searchResult.offset) \(modelData.searchLibraryResults[librarySearchKey]?.bookIds.count ?? 0)")
                    }
                    
                    print("\(#function) finishLoading library=\(task.library.key) \(searchResult.num) \(searchResult.total_num)")
                } else if searchTask.ajaxSearchError {
                    
                }
                
                modelData.searchLibraryResults[librarySearchKey]?.loading = false

                return task
            }
            .sink(receiveCompletion: { completion in
                
            }, receiveValue: { task in
                guard let searchCriteria = task.searchTask?.searchCriteria else { return }
                
                let librarySearchKey = LibrarySearchKey(libraryId: task.library.id, criteria: searchCriteria)
                
                modelData.librarySearchReturnedSubject.send(librarySearchKey)
                
                modelData.filteredBookListRefreshingSubject.send("")

                guard let searchPreviousResult = modelData.searchLibraryResults[librarySearchKey],
                      searchPreviousResult.error
                else { return }
                
                var needRemerge = searchPreviousResult.pageOffset.isEmpty
                if !needRemerge,
                   let minPartialPage = searchPreviousResult.pageOffset.filter ({ $0.value >= searchPreviousResult.errorOffset }).keys.min() {
                    // discard partial offsets
                    for key in modelData.searchLibraryResults.keys {
                        if let pages = modelData.searchLibraryResults[key]?.pageOffset.keys.filter({ $0 >= minPartialPage }) {
                            for page in pages {
                                modelData.searchLibraryResults[key]?.pageOffset.removeValue(forKey: page)
                            }
                        }
                    }
                    needRemerge = true
                }

                print("LIBRARYINFOVIEW library=\(task.library.id) needRemerge=\(needRemerge) \(task.books.count)")
                if needRemerge {
                    modelData.filteredBookListMergeSubject.send(.init(libraryId: task.library.id, criteria: searchCriteria))
                }
                
                modelData.searchLibraryResults[librarySearchKey]?.error = false
            }).store(in: &modelData.calibreCancellables)
    }
    
    func registerFilteredBookListMergeHandler() {
        modelData.filteredBookListMergeSubject
            .receive(on: DispatchQueue.main)
            .map { librarySearchKey -> LibrarySearchKey in
                if modelData.searchCriteriaResults[librarySearchKey.criteria] == nil {
                    modelData.searchCriteriaResults[librarySearchKey.criteria] = .init()
                }
                modelData.searchCriteriaResults[librarySearchKey.criteria]?.merging = true
                return librarySearchKey
            }
            .receive(on: ModelData.SearchLibraryResultsRealmQueue)
            .map { librarySearchKey -> LibrarySearchMergeResult in
                print("\(#function) librarySearchKey=\(librarySearchKey)")
                
                var librarySearchMergeResult = LibrarySearchMergeResult(libraryId: librarySearchKey.libraryId, criteria: librarySearchKey.criteria)
                
                let searchCriteria = librarySearchKey.criteria
                
                let results = modelData.searchLibraryResults.filter {
                    $0.key.criteria == searchCriteria
                    && (searchCriteria.filterCriteriaLibraries.isEmpty || searchCriteria.filterCriteriaLibraries.contains($0.key.libraryId))
                }
                modelData.calibreLibraries.filter {
                    $0.value.hidden == false
                    && (searchCriteria.filterCriteriaLibraries.isEmpty || searchCriteria.filterCriteriaLibraries.contains($0.key))
                    && results[.init(libraryId: $0.key, criteria: searchCriteria)] == nil
                }.forEach {
                    modelData.librarySearchSubject.send(.init(libraryId: $0.key, criteria: searchCriteria))
                }
                
                librarySearchMergeResult.totalNumber = results.values.map { $0.totalNumber }.reduce(0) { partialResult, totalNumber in
                    return partialResult + totalNumber
                }
                
                var mergeResults = results.reduce(into: [:], { partialResult, entry in
                    partialResult[entry.key.libraryId] = entry.value
                })
                
                librarySearchMergeResult.mergedBooks = modelData.mergeBookLists(
                    results: &mergeResults,
                    sortCriteria: librarySearchKey.criteria.sortCriteria,
                    page: modelData.filteredBookListPageNumber,
                    limit: modelData.filteredBookListPageSize
                )
                
                librarySearchMergeResult.mergeResults = mergeResults
                
                return librarySearchMergeResult
            }
            .receive(on: DispatchQueue.main)
            .map { librarySearchMergeResult -> LibrarySearchMergeResult in
                
                modelData.searchCriteriaResults[librarySearchMergeResult.criteria]?.books = librarySearchMergeResult.mergedBooks
                print("LIBRARYINFOVIEW \(#function) library=\(librarySearchMergeResult.libraryId) merged=\(librarySearchMergeResult.mergedBooks.count)")
//                if modelData.currentLibrarySearchCriteria == librarySearchKey.criteria {
//                    modelData.filteredBookList = mergedBooks
//                }
                modelData.searchCriteriaResults[librarySearchMergeResult.criteria]?.merging = false
                
                librarySearchMergeResult.mergeResults.forEach {
                    let key = LibrarySearchKey(libraryId: $0.key, criteria: librarySearchMergeResult.criteria)
                    modelData.searchLibraryResults[key]?.pageOffset = $0.value.pageOffset
                    modelData.searchLibraryResults[key]?.error = $0.value.error
                    modelData.searchLibraryResults[key]?.errorOffset = $0.value.errorOffset
                    
                    if librarySearchMergeResult.libraryId == "" || librarySearchMergeResult.libraryId == $0.key {
                        if $0.value.error || ($0.value.pageOffset[modelData.filteredBookListPageNumber+1] ?? 0) + modelData.filteredBookListPageSize >= $0.value.bookIds.count {
                            modelData.librarySearchSubject.send(key)
                        } else {
                            if librarySearchMergeResult.libraryId.starts(with: "Domestic"),
                               librarySearchMergeResult.mergedBooks.count <= 2 {
                                print("LIBRARYINFOVIEW DISCONTINUE merged=\(librarySearchMergeResult.mergedBooks.count) searchLibraryResults=\(modelData.searchLibraryResults)")
                            }
                        }
                    }
                }
                
                if librarySearchMergeResult.criteria == modelData.currentLibrarySearchCriteria {
                    modelData.filteredBookListPageCount = Int((Double(librarySearchMergeResult.totalNumber) / Double(modelData.filteredBookListPageSize)).rounded(.up))
                }
                
                return librarySearchMergeResult
            }
            .sink(receiveCompletion: { completion in
                
            }, receiveValue: { librarySearchMergeResult in
                modelData.filteredBookListRefreshingSubject.send("")
            }).store(in: &modelData.calibreCancellables)
    }
    
    func registerLibrarySearchResetHandler() {
        modelData.librarySearchResetSubject
            .subscribe(on: DispatchQueue.main)
            .sink(receiveCompletion: { completion in
                
            }, receiveValue: { librarySearchKey in
                if librarySearchKey.libraryId.isEmpty {
                    modelData.searchCriteriaResults.removeValue(forKey: librarySearchKey.criteria)
                } else {
                    modelData.searchLibraryResults.removeValue(forKey: librarySearchKey)
                }
            })
            .store(in: &modelData.calibreCancellables)
    }
    
    func registerLibraryCategoryHandler() {
        modelData.libraryCategorySubject
            .receive(on: DispatchQueue.global())
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
        modelData.libraryCategoryMergeSubject
            .subscribe(on: DispatchQueue.global(qos: .userInitiated))
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
            .subscribe(on: DispatchQueue.main)
            .sink { entry in
                modelData.calibreLibraryCategoryMerged[entry.0] = entry.1
                
                modelData.categoryItemListSubject.send(entry.0)
            }
            .store(in: &modelData.calibreCancellables)
    }
}
