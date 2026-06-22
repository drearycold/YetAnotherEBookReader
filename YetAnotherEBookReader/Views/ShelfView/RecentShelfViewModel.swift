//
//  RecentShelfViewModel.swift
//  YetAnotherEBookReader
//
//  Created by opencode on 2026-06-18.
//

import UIKit
import Combine

enum RecentShelfAlert: Identifiable {
    case missingFormat(book: CalibreBook, format: Format)
    case downloadingFormat(book: CalibreBook, format: Format)
    case deleteConfirm(bookIds: Set<String>)
    
    var id: String {
        switch self {
        case .missingFormat(let book, let format):
            return "missing-\(book.id)-\(format.rawValue)"
        case .downloadingFormat(let book, let format):
            return "downloading-\(book.id)-\(format.rawValue)"
        case .deleteConfirm:
            return "deleteConfirm"
        }
    }
}

@MainActor @available(macCatalyst 14.0, *)
final class RecentShelfViewModel: ObservableObject {
    let modelData: ModelData
    private var cancellables = Set<AnyCancellable>()
    
    @Published var displayBooks = [ShelfBookItem]()
    @Published var selectionState = ShelfSelectionState()
    
    @Published var presentingBookDetailId: String? = nil
    @Published var presentingHistoryBookId: String? = nil
    @Published var activeAlert: RecentShelfAlert? = nil
    
    init(modelData: ModelData) {
        self.modelData = modelData
        setupSubscriptions()
    }
    
    private func setupSubscriptions() {
        modelData.recentShelfItemsSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] displayBooks in
                self?.displayBooks = displayBooks
            }
            .store(in: &cancellables)
            
        modelData.calibreUpdatedSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] signal in
                guard let self = self else { return }
                if case .deleted(let deletedId) = signal {
                    if self.presentingBookDetailId == deletedId {
                        self.presentingBookDetailId = nil
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    func refreshShelf() {
        modelData.refreshShelfMetadataV2(serverReachableChanged: false)
        modelData.probeServersReachability(with: [], updateLibrary: true)
    }
    
    func deleteBooks(bookIds: Set<String>) {
        bookIds.forEach {
            modelData.clearCache(inShelfId: $0)
        }
        selectionState.selectedBookIds.subtract(bookIds)
        if selectionState.selectedBookIds.isEmpty {
            selectionState.isEditing = false
        }
        modelData.calibreUpdatedSubject.send(.shelf)
    }
    
    func deleteBook(bookId: String) {
        modelData.clearCache(inShelfId: bookId)
    }
    
    func prepareReading(bookId: String) -> ReaderInfo? {
        modelData.readingBookInShelfId = bookId
        guard let book = modelData.readingBook else { return nil }
        return modelData.prepareBookReading(book: book)
    }
    
    func tapBook(bookId: String) {
        if selectionState.isEditing {
            toggleSelection(bookId: bookId)
            return
        }
        
        guard let book = modelData.booksInShelf[bookId] else { return }
        
        modelData.readingBookInShelfId = bookId
        let readerInfo = modelData.prepareBookReading(book: book)
        
        if readerInfo.missing {
            if let activeDownload = modelData.downloadManager.activeDownloads.first(where: {
                $0.value.book == book && $0.value.format == readerInfo.format
            })?.value, activeDownload.isDownloading {
                activeAlert = .downloadingFormat(book: book, format: readerInfo.format)
            } else {
                activeAlert = .missingFormat(book: book, format: readerInfo.format)
            }
        } else {
            modelData.readerInfo = readerInfo
            modelData.presentingEBookReaderFromShelf = true
        }
    }
    
    func toggleSelection(bookId: String) {
        if selectionState.selectedBookIds.contains(bookId) {
            selectionState.selectedBookIds.remove(bookId)
        } else {
            selectionState.selectedBookIds.insert(bookId)
        }
    }
    
    func selectAllBooks() {
        selectionState.selectedBookIds = Set(displayBooks.map { $0.id })
    }
    
    func clearSelection() {
        selectionState.selectedBookIds.removeAll()
    }
    
    func deleteSelectedBooks() {
        let targets = selectionState.selectedBookIds
        deleteBooks(bookIds: targets)
        selectionState.selectedBookIds.removeAll()
        selectionState.isEditing = false
    }
    
    func triggerDownload(book: CalibreBook, format: Format) {
        modelData.downloadManager.bookFormatDownloadSubject.send((book: book, format: format))
    }
    
    func refreshBookFormats(bookId: String) {
        guard let book = modelData.booksInShelf[bookId] else { return }
        book.formats.filter {
            $1.cached && !$1.cacheUptoDate
        }.keys.forEach {
            guard let format = Format(rawValue: $0) else { return }
            self.modelData.downloadManager.bookFormatDownloadSubject.send((book: book, format: format))
        }
    }
    
    func goodreadsAction(bookId: String) {
        guard let book = modelData.booksInShelf[bookId] else { return }
        if let id = book.identifiers["goodreads"],
           let url = URL(string: "https://www.goodreads.com/book/show/\(id)") {
            UIApplication.shared.open(url)
        } else if var urlComponents = URLComponents(string: "https://www.goodreads.com/search") {
            urlComponents.queryItems = [URLQueryItem(name: "q", value: book.title + " " + book.authors.joined(separator: " "))]
            if let url = urlComponents.url {
                UIApplication.shared.open(url)
            }
        }
    }
    
    func doubanAction(bookId: String) {
        guard let book = modelData.booksInShelf[bookId] else { return }
        if let id = book.identifiers["douban"],
           let url = URL(string: "https://m.douban.com/book/subject/\(id)/") {
            UIApplication.shared.open(url)
        } else if var urlComponents = URLComponents(string: "https://m.douban.com/search/") {
            urlComponents.queryItems = [
                URLQueryItem(name: "query", value: book.title + " " + book.authors.joined(separator: " ")),
                URLQueryItem(name: "type", value: "book")
            ]
            if let url = urlComponents.url {
                UIApplication.shared.open(url)
            }
        }
    }
}
