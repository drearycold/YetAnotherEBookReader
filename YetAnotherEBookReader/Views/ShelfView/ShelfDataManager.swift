//
//  ShelfDataManager.swift
//  YetAnotherEBookReader
//
//  Created by Peter on 2022/11/30.
//

import Foundation
import ShelfView
import RealmSwift

extension ModelData {
    func registerRecentShelfUpdater() {
        self.calibreUpdatedSubject
            .collect(.byTime(RunLoop.main, .seconds(1)))
            .receive(on: DispatchQueue.global(qos: .userInitiated))
            .map { signals -> [(key: String, value: CalibreBook)] in
                self.booksInShelf
                    .sorted {
                        max($0.value.lastModified,
                            $0.value.readPos.getDevices().map{p in Date(timeIntervalSince1970: p.epoch)}.max() ?? $0.value.lastUpdated
                        ) > max(
                            $1.value.lastModified,
                            $1.value.readPos.getDevices().map{p in Date(timeIntervalSince1970: p.epoch)}.max() ?? $1.value.lastUpdated
                        )
                    }
            }
            .map { books -> [BookModel] in
                books
                    .map { (inShelfId, book) -> BookModel in
                        let readerInfo = self.prepareBookReading(book: book)
                        
                        let bookUptoDate = book.formats.allSatisfy {
                            $1.cached == false ||
                            ($1.cached && $1.cacheUptoDate)
                        }
                        let missingFormats = book.formats.filter {
                            $1.selected == true && $1.cached == false
                        }
                        
                        var bookStatus = BookModel.BookStatus.READY
                        if self.calibreServerService.getServerUrlByReachability(server: book.library.server) == nil {
                            bookStatus = .NOCONNECT
                        } else {
                            missingFormats.forEach {
                                guard let format = Format(rawValue: $0.key) else { return }
                                self.bookFormatDownloadSubject.send((book: book, format: format))
                            }
                            
                            if !bookUptoDate {
                                bookStatus = .HASUPDATE
                            }
                            if self.activeDownloads.contains(where: { (url, download) in
                                download.isDownloading && download.book.inShelfId == inShelfId
                            }) {
                                bookStatus = .DOWNLOADING
                            }
                        }
                        if book.library.server.isLocal {
                            bookStatus = .LOCAL
                        }
                        
                        return BookModel(
                            bookCoverSource: book.coverURL?.absoluteString ?? "",
                            bookId: inShelfId,
                            bookTitle: book.title,
                            bookProgress: Int(floor(readerInfo.position.lastProgress)),
                            bookStatus: bookStatus
                        )
                    }
            }
            .receive(on: RunLoop.main)
            .sink(receiveValue: { result in
//                self.books = result.0
//                self.shelfView.reloadBooks(bookModel: result.1)
                self.recentShelfModelSubject.send(result)
            })
            .store(in: &calibreCancellables)
    }
    
    func registerDiscoverShelfUpdater() {
        calibreUpdatedSubject
            .collect(.byTime(RunLoop.main, .seconds(1)))
            .receive(on: ModelData.SearchLibraryResultsRealmQueue)
            .sink { signals in
                let signalSet = Set<calibreUpdatedSignal>(signals)
                self.booksInShelf.values.filter({ book in
                    book.library.server.isLocal == false &&
                    (
                        signalSet.contains(.shelf) ||
                        signalSet.contains(.deleted(book.inShelfId)) ||
                        signalSet.contains(.book(book)) ||
                        signalSet.contains(.library(book.library)) ||
                        signalSet.contains(.server(book.library.server))
                    )
                }).reduce(into: Set<LibrarySearchKey>()) { libraryKeys, book in
                    if let author = book.authors.first {
                        libraryKeys.insert(.init(
                            libraryId: book.library.id,
                            criteria: .init(
                                searchString: "",
                                sortCriteria: .init(by: .Title, ascending: true),
                                filterCriteriaCategory: ["Authors": Set<String>([author])],
                                filterCriteriaFormat: [],
                                filterCriteriaIdentifier: [],
                                filterCriteriaLibraries: [])))
                    }
                    book.tags.forEach { tag in
                        libraryKeys.insert(.init(
                            libraryId: book.library.id,
                            criteria: .init(
                                searchString: "",
                                sortCriteria: .init(by: .Modified, ascending: false),
                                filterCriteriaCategory: ["Tags": Set<String>([tag])],
                                filterCriteriaFormat: [],
                                filterCriteriaIdentifier: [],
                                filterCriteriaLibraries: [])))
                    }
                    if book.series.isEmpty == false {
                        libraryKeys.insert(.init(
                            libraryId: book.library.id,
                            criteria: .init(
                                searchString: "",
                                sortCriteria: .init(by: .SeriesIndex, ascending: true),
                                filterCriteriaCategory: ["Series": Set<String>([book.series])],
                                filterCriteriaFormat: [],
                                filterCriteriaIdentifier: [],
                                filterCriteriaLibraries: [])))
                    }
                }.forEach {
                    self.librarySearchSubject.send($0)
                }
            }
            .store(in: &calibreCancellables)
        
        librarySearchReturnedSubject
            .receive(on: ModelData.SearchLibraryResultsRealmQueue)
            .map { librarySearchKey -> ShelfModelSection in
                let emptyShelf = ShelfModelSection(sectionName: "", sectionId: "", sectionShelf: [])
                guard librarySearchKey.criteria.filterCriteriaCategory.count == 1,
                      let categoryFilter = librarySearchKey.criteria.filterCriteriaCategory.first,
                      categoryFilter.value.count == 1,
                      let categoryFilterValue = categoryFilter.value.first,
                      let library = self.calibreLibraries[librarySearchKey.libraryId],
                      library.hidden == false,
                      library.discoverable == true,
                      let result = self.searchLibraryResults[librarySearchKey],
                      let realm = try? Realm(configuration: self.realmConf)
                else { return emptyShelf }
                
                switch categoryFilter.key {
                case "Tags":
                    guard self.booksInShelf.first(where: { $0.value.tags.firstIndex(of: categoryFilterValue) != nil }) != nil
                    else { return emptyShelf }
                case "Authors":
                    guard self.booksInShelf.first(where: { $0.value.authors.firstIndex(of: categoryFilterValue) != nil }) != nil
                    else { return emptyShelf }
                case "Series":
                    guard self.booksInShelf.first(where: { $0.value.series == categoryFilterValue }) != nil
                    else { return emptyShelf }
                default:    //unrecognized
                    return emptyShelf
                }
                
                let sectionId = "\(librarySearchKey)"
                
                let serverUUID = library.server.uuid.uuidString
                
                let sectionShelf = result.bookIds.compactMap { bookId -> ShelfModel? in
                    let primaryKey = CalibreBookRealm.PrimaryKey(serverUUID: serverUUID, libraryName: library.name, id: bookId.description)
                    guard let bookRealm = realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: primaryKey) ?? self.searchLibraryResultsRealmQueue?.object(ofType: CalibreBookRealm.self, forPrimaryKey: primaryKey),
                          bookRealm.inShelf == false
                    else { return nil }
                    
                    let book = self.convert(library: library, bookRealm: bookRealm)
                    
                    return ShelfModel(
                        bookCoverSource: book.coverURL?.absoluteString ?? ".",
                        bookId: book.inShelfId,
                        bookTitle: book.title,
                        bookProgress: Int(
                            book.readPos.getDevices().max { lhs, rhs in
                                lhs.lastProgress < rhs.lastProgress
                            }?.lastProgress ?? 0.0),
                        bookStatus: .READY,
                        sectionId: sectionId
                    )
                }
                
                let sectionName = "\(categoryFilter.key): \(categoryFilterValue) in \(library.name)"
                
                return ShelfModelSection(sectionName: sectionName, sectionId: sectionId, sectionShelf: sectionShelf)
            }
            .receive(on: DispatchQueue.main)
            .sink { shelfModelSection in
                defer {
                    self.discoverShelfModelSubject.send(self.bookModelSection)
                }
                self.bookModelSection.removeAll { shelfModelSection.sectionId == $0.sectionId }
                
                guard shelfModelSection.sectionShelf.count > 1 else { return }
                
                self.bookModelSection.append(shelfModelSection)
                
                self.bookModelSection.sort { $0.sectionName < $1.sectionName }
            }
            .store(in: &calibreCancellables)
    }
}
