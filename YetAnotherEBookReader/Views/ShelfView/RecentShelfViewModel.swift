//
//  RecentShelfViewModel.swift
//  YetAnotherEBookReader
//
//  Created by opencode on 2026-06-18.
//

import UIKit
import SwiftUI

enum RecentShelfAlert: Identifiable {
    case localLibraryCheck(AlertItem)
    case missingFormat(book: CalibreBook, format: Format)
    case downloadingFormat(book: CalibreBook, format: Format)
    case deleteConfirm(bookIds: Set<String>)
    case fileRemoval(BookFileRemovalResult)
    /// Another device saved a newer position than the one the book would open at.
    case newerPosition(book: CalibreBook, readerInfo: ReaderInfo, position: BookDeviceReadingPosition)
    
    var id: String {
        switch self {
        case .localLibraryCheck(let notice):
            return notice.id
        case .missingFormat(let book, let format):
            return "missing-\(book.id)-\(format.rawValue)"
        case .downloadingFormat(let book, let format):
            return "downloading-\(book.id)-\(format.rawValue)"
        case .deleteConfirm:
            return "deleteConfirm"
        case .fileRemoval:
            return "fileRemoval"
        case .newerPosition(let book, _, let position):
            return "newerPosition-\(book.id)-\(position.id)-\(position.epoch)"
        }
    }
}

/// A screen pushed from the Recent shelf. Pushed rather than presented in a sheet, so a reader opened
/// from it shows above it in the reader workspace overlay.
enum RecentShelfRoute: Equatable {
    case bookDetail(bookId: String)
    case readingHistory(bookId: String)
}

@MainActor @available(macCatalyst 14.0, *)
final class RecentShelfViewModel: ObservableObject {
    let container: AppContainer
    let targetWorkspaceID: UUID?
    private var recentSnapshotTask: Task<Void, Never>?
    private var calibreEventTask: Task<Void, Never>?
    
    @Published private(set) var loadedBooks: [ShelfBookItem]? = nil
    var displayBooks: [ShelfBookItem] {
        loadedBooks ?? []
    }
    @Published var selectionState = ShelfSelectionState()
    
    // Setting either one pushes its screen and replaces the other: the shelf has a single pushed
    // route, driven by one hidden NavigationLink.
    @Published var presentingBookDetailId: String? = nil {
        didSet {
            guard let bookId = presentingBookDetailId else { return }
            presentingHistoryBookId = nil
            displayedRoute = .bookDetail(bookId: bookId)
        }
    }
    @Published var presentingHistoryBookId: String? = nil {
        didSet {
            guard let bookId = presentingHistoryBookId else { return }
            presentingBookDetailId = nil
            let book = readingHistoryBook(bookId: bookId)
            if book == nil || displayedHistory?.bookIdentity != bookId {
                displayedHistory = book.map { ReadingPositionHistoryViewModel(container: container, book: $0) }
            }
            displayedRoute = .readingHistory(bookId: bookId)
        }
    }
    /// The route's destination. Kept after the route is dismissed, so the page doesn't go blank
    /// while it slides out.
    @Published private(set) var displayedHistory: ReadingPositionHistoryViewModel?
    @Published private(set) var displayedRoute: RecentShelfRoute? = nil
    @Published var activeAlert: RecentShelfAlert? = nil
    
    init(container: AppContainer, targetWorkspaceID: UUID? = nil) {
        self.container = container
        self.targetWorkspaceID = targetWorkspaceID
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
                    if self.presentingBookDetailId == deletedId || self.presentingHistoryBookId == deletedId {
                        self.dismissRoute()
                    }
                }
            }
        }
    }
    
    var isRouteActive: Bool {
        presentingBookDetailId != nil || presentingHistoryBookId != nil
    }

    func dismissRoute() {
        presentingBookDetailId = nil
        presentingHistoryBookId = nil
    }

    func readingHistoryBook(bookId: String) -> CalibreBook? {
        container.bookManager.booksInShelf[bookId]
    }

    func refreshShelf() {
        container.bookManager.refreshShelfMetadataV2(serverReachableChanged: false)
        container.serverManager.probeServersReachability(with: [], updateLibrary: true)
    }

    func deleteBooks(bookIds: Set<String>) async {
        var removed = Set<String>()
        for id in bookIds {
            let result = await container.bookManager.clearCache(inShelfId: id)
            if result.succeeded { removed.insert(id) }
            if !result.succeeded || result.cleanupPending { activeAlert = .fileRemoval(result) }
        }
        selectionState.selectedBookIds.subtract(removed)
        if selectionState.selectedBookIds.isEmpty {
            selectionState.isEditing = false
        }
        if !removed.isEmpty { container.publishCalibreUpdate(.shelf) }
    }

    func deleteBook(bookId: String) async {
        let result = await container.bookManager.clearCache(inShelfId: bookId)
        if !result.succeeded || result.cleanupPending { activeAlert = .fileRemoval(result) }
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
        if let notice = container.libraryManager.localFileAccessNotice(for: book) {
            activeAlert = .localLibraryCheck(notice)
            return
        }

        let readerInfo = container.sessionManager.prepareBookReading(book: book)

        if readerInfo.missing {
            if let activeDownload = container.downloadManager.activeDownloads.first(where: {
                $0.value.book == book && $0.value.format == readerInfo.format
            })?.value, activeDownload.isActive {
                activeAlert = .downloadingFormat(book: book, format: readerInfo.format)
            } else {
                activeAlert = .missingFormat(book: book, format: readerInfo.format)
            }
        } else if let newer = container.sessionManager.newerPositionFromOtherDevice(
            than: container.sessionManager.startPosition(for: readerInfo, book: book),
            for: book
        ) {
            // Known locally already, so asking costs no wait. Otherwise the book opens at once and a
            // newer position found by the background fetch is offered in the reader.
            container.sessionManager.markNewerPositionOffered(newer, for: book)
            activeAlert = .newerPosition(book: book, readerInfo: readerInfo, position: newer)
        } else {
            openReader(book: book, readerInfo: readerInfo)
        }
    }

    func openReader(book: CalibreBook, readerInfo: ReaderInfo) {
        if let notice = container.libraryManager.localFileAccessNotice(for: book, format: readerInfo.format) {
            activeAlert = .localLibraryCheck(notice)
            return
        }
        container.openReader(
            book: book,
            readerInfo: readerInfo,
            source: .shelf,
            targetWorkspaceID: targetWorkspaceID
        )
    }

    func openReader(book: CalibreBook, readerInfo: ReaderInfo, at position: BookDeviceReadingPosition) {
        if let notice = container.libraryManager.localFileAccessNotice(for: book, format: readerInfo.format) {
            activeAlert = .localLibraryCheck(notice)
            return
        }
        container.openReader(
            book: book,
            readerInfo: container.sessionManager.prepareBookReading(book: book, at: position, fallback: readerInfo),
            source: .newerPosition,
            targetWorkspaceID: targetWorkspaceID
        )
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
