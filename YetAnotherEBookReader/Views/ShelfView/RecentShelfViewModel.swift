//
//  RecentShelfViewModel.swift
//  YetAnotherEBookReader
//
//  Created by opencode on 2026-06-18.
//

import UIKit
import SwiftUI

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
    let container: AppContainer
    private var recentSnapshotTask: Task<Void, Never>?
    private var calibreEventTask: Task<Void, Never>?
    
    @Published private(set) var loadedBooks: [ShelfBookItem]? = nil
    var displayBooks: [ShelfBookItem] {
        loadedBooks ?? []
    }
    @Published var selectionState = ShelfSelectionState()
    
    @Published var presentingBookDetailId: String? = nil
    @Published var presentingHistoryBookId: String? = nil
    @Published var activeAlert: RecentShelfAlert? = nil
    
    init(container: AppContainer) {
        self.container = container
        setupTasks()
    }

    deinit {
        recentSnapshotTask?.cancel()
        calibreEventTask?.cancel()
    }
    
    private func setupTasks() {
        let snapshots = container.shelfDataModel.recentSnapshots()
        recentSnapshotTask = Task { [weak self] in
            for await snapshot in snapshots {
                guard !Task.isCancelled else { return }
                self?.loadedBooks = snapshot.books
            }
        }

        let signals = container.calibreUpdates()
        calibreEventTask = Task { [weak self] in
            for await signal in signals {
                guard !Task.isCancelled else { return }
                guard let self = self else { return }
                if case .deleted(let deletedId) = signal {
                    if self.presentingBookDetailId == deletedId {
                        self.presentingBookDetailId = nil
                    }
                }
            }
        }
    }
    
    func refreshShelf() {
        container.bookManager.refreshShelfMetadataV2(serverReachableChanged: false)
        container.serverManager.probeServersReachability(with: [], updateLibrary: true)
    }

    func deleteBooks(bookIds: Set<String>) {
        bookIds.forEach {
            container.bookManager.clearCache(inShelfId: $0)
        }
        selectionState.selectedBookIds.subtract(bookIds)
        if selectionState.selectedBookIds.isEmpty {
            selectionState.isEditing = false
        }
        container.publishCalibreUpdate(.shelf)
    }

    func deleteBook(bookId: String) {
        container.bookManager.clearCache(inShelfId: bookId)
    }

    func prepareReading(bookId: String) -> ReaderInfo? {
        guard let book = container.bookManager.booksInShelf[bookId] ?? container.bookManager.getBook(for: bookId) else { return nil }
        return container.sessionManager.prepareBookReading(book: book)
    }

    func tapBook(bookId: String) {
        if selectionState.isEditing {
            toggleSelection(bookId: bookId)
            return
        }

        guard let book = container.bookManager.booksInShelf[bookId] else { return }

        let readerInfo = container.sessionManager.prepareBookReading(book: book)

        if readerInfo.missing {
            if let activeDownload = container.downloadManager.activeDownloads.first(where: {
                $0.value.book == book && $0.value.format == readerInfo.format
            })?.value, activeDownload.isActive {
                activeAlert = .downloadingFormat(book: book, format: readerInfo.format)
            } else {
                activeAlert = .missingFormat(book: book, format: readerInfo.format)
            }
        } else {
            container.sessionManager.openReader(book: book, readerInfo: readerInfo, source: .shelf)
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
        container.downloadManager.requestDownload(book: book, format: format)
    }
    
    func refreshBookFormats(bookId: String) {
        guard let book = container.bookManager.booksInShelf[bookId] else { return }
        book.formats.filter {
            $1.cached && !$1.cacheUptoDate
        }.keys.forEach {
            guard let format = Format(rawValue: $0) else { return }
            self.container.downloadManager.requestDownload(book: book, format: format)
        }
    }

    func goodreadsAction(bookId: String) {
        guard let book = container.bookManager.booksInShelf[bookId] else { return }
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
        guard let book = container.bookManager.booksInShelf[bookId] else { return }
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
