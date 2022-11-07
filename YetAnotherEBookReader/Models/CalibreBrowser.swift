//
//  CalibreBrowser.swift
//  YetAnotherEBookReader
//
//  Created by Peter on 2022/11/5.
//

import Foundation
import RealmSwift
import Combine

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
    
    func mergeBookLists(results: inout [String : LibrarySearchResult], page: Int = 0, limit: Int = 100) -> [String] {
        guard let realm = try? Realm(configuration: realmConf),
              let realmSearch = searchLibraryResultsRealmLocalThread
        else { return [] }
        
        var merged = [String]()
        
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
            }
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
            
            return realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: primaryKey)
            ?? realmSearch.object(ofType: CalibreBookRealm.self, forPrimaryKey: primaryKey)
        }
        heads.sort { lhs, rhs in
            lhs.lastModified < rhs.lastModified
        }
        
        let mergeLength = limit + (page - startPage) * limit
        while merged.count < mergeLength, let head = heads.popLast() {
            merged.append(head.primaryKey!)
            
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
            else { continue }
            
            heads.append(next)
            heads.sort { lhs, rhs in
                lhs.lastModified < rhs.lastModified
            }
            
            if merged.count % limit == 0 {
                let currentPage = (merged.count / limit) + startPage
                headIndex.forEach {
                    results[$0.key]?.pageOffset[currentPage] = $0.value
                }
            }
            
        }
        
        if merged.count % limit == 0 {
            return merged.suffix(limit)
        } else {
            return merged.suffix(merged.count % limit)
        }
    }
    
    
}

extension CalibreServerService {
    func buildLibrarySearchTask(library: CalibreLibrary, searchCriteria: LibrarySearchCriteria) -> CalibreLibrarySearchTask? {
        guard let serverUrl = getServerUrlByReachability(server: library.server) else {
            return nil
        }
        
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
        guard task.booksListUrl.isHTTP else {
            return Just(task).setFailureType(to: URLError.self).eraseToAnyPublisher()
        }
        
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
    
    func registerLibrarySearchHandler() {
        let fbURL = URL(fileURLWithPath: "/")
        
        modelData.librarySearchCancellable?.cancel()
        modelData.librarySearchCancellable = modelData.librarySearchSubject
            .subscribe(on: DispatchQueue.global(qos: .userInitiated))
            .receive(on: DispatchQueue.main)
            .compactMap { librarySearchKey -> CalibreLibrarySearchTask? in
                guard let library = modelData.calibreLibraries[librarySearchKey.libraryId]
                else { return nil }
                
                let searchKey = LibrarySearchKey(libraryId: library.id, criteria: librarySearchKey.criteria)
                if modelData.searchLibraryResults[searchKey] == nil {
                    modelData.searchLibraryResults[searchKey] = .init(library: library)
                }
                modelData.searchLibraryResults[searchKey]?.loading = true

                modelData.filteredBookListRefreshing = modelData.searchLibraryResults.filter { $0.key.criteria == librarySearchKey.criteria && $0.value.loading }.isEmpty == false
                
                return modelData.calibreServerService.buildLibrarySearchTask(
                    library: library,
                    searchCriteria: librarySearchKey.criteria
                )
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
            .map { task -> CalibreLibrarySearchTask in
                let librarySearchKey = LibrarySearchKey(libraryId: task.library.id, criteria: task.searchCriteria)
                if let searchResult = task.ajaxSearchResult {
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
                    
                    print("\(#function) library=\(task.library.key) \(searchResult.num) \(searchResult.total_num)")
                } else if task.ajaxSearchError {
                    
                }
                
                return task
            }
            .receive(on: DispatchQueue.global(qos: .userInitiated))
            .compactMap { task -> CalibreBooksTask? in
                guard let books = task.ajaxSearchResult?.book_ids.map({ CalibreBook(id: $0, library: task.library) }),
                      books.isEmpty == false
                else { return nil }
                
                return buildBooksMetadataTask(library: task.library, books: books, searchCriteria: task.searchCriteria)
            }
            .flatMap { task -> AnyPublisher<CalibreBooksTask, Never> in
                modelData.calibreServerService.getBooksMetadata(task: task)
                    .replaceError(with: task)
                    .eraseToAnyPublisher()
            }
            .map { task -> CalibreBooksTask in
                let serverUUID = task.library.server.uuid.uuidString
                
                if let booksMetadataEntry = task.booksMetadataEntry,
                   let booksMetadataJSON = task.booksMetadataJSON,
                   let searchLibraryResultsRealm = modelData.searchLibraryResultsRealmLocalThread {
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
            .sink(receiveCompletion: { completion in
                
            }, receiveValue: { task in
                guard let searchCriteria = task.searchCriteria else { return }
                
                let librarySearchKey = LibrarySearchKey(libraryId: task.library.id, criteria: searchCriteria)
                
                guard let searchPreviousResult = modelData.searchLibraryResults[librarySearchKey]
                else { return }
                
                guard modelData.searchLibraryResults[librarySearchKey]?.error == true else { return }
                
                var needRemerge = false
                if searchPreviousResult.pageOffset.isEmpty {
                    needRemerge = true
                }
                else if let minPartialPage = searchPreviousResult.pageOffset.filter ({ $0.value >= searchPreviousResult.errorOffset }).keys.min() {
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
                
                if needRemerge {
                    modelData.filteredBookListMergeSubject.send(.init(libraryId: task.library.id, criteria: searchCriteria))
                }
                
                modelData.searchLibraryResults[librarySearchKey]?.error = false
            })
    }
    
    func registerFilteredBookListMergeHandler() {
        modelData.filteredBookListMergeCancellable?.cancel()
        modelData.filteredBookListMergeCancellable = modelData.filteredBookListMergeSubject
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { completion in
                
            }, receiveValue: { librarySearchKey in
                print("\(#function) librarySearchKey=\(librarySearchKey)")
                
                let searchCriteria = librarySearchKey.criteria
                
                let results = modelData.searchLibraryResults.filter { $0.key.criteria == searchCriteria }
                modelData.calibreLibraries.filter { $0.value.hidden == false }.forEach {
                    if results[.init(libraryId: $0.key, criteria: searchCriteria)] == nil {
                        modelData.librarySearchSubject.send(.init(libraryId: $0.key, criteria: searchCriteria))
                    }
                }
                
                let totalNumber = results.values.map { $0.totalNumber }.reduce(0) { partialResult, totalNumber in
                    return partialResult + totalNumber
                }
                modelData.filteredBookListPageCount = Int((Double(totalNumber) / Double(modelData.filteredBookListPageSize)).rounded(.up))
                
                var mergeResults = results.reduce(into: [:], { partialResult, entry in
                    partialResult[entry.key.libraryId] = entry.value
                })
                
                modelData.filteredBookList = modelData.mergeBookLists(results: &mergeResults, page: modelData.filteredBookListPageNumber, limit: modelData.filteredBookListPageSize)
                
                mergeResults.forEach {
                    let key = LibrarySearchKey(libraryId: $0.key, criteria: searchCriteria)
                    modelData.searchLibraryResults[key]?.pageOffset = $0.value.pageOffset
                    modelData.searchLibraryResults[key]?.error = $0.value.error
                    modelData.searchLibraryResults[key]?.errorOffset = $0.value.errorOffset
                    
                    if librarySearchKey.libraryId == "" || librarySearchKey.libraryId == $0.key {
                        if $0.value.error || ($0.value.pageOffset[modelData.filteredBookListPageNumber+1] ?? 0) + modelData.filteredBookListPageSize >= $0.value.bookIds.count {
                            modelData.librarySearchSubject.send(key)
                        }
                    }
                }
                
                modelData.filteredBookListRefreshing = modelData.searchLibraryResults.filter { $0.key.criteria == searchCriteria && $0.value.loading }.isEmpty == false
            })
    }
}
