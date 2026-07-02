//
//  SectionShelfViewModel.swift
//  YetAnotherEBookReader
//
//  Created by opencode on 2026-06-18.
//

import Foundation
import Combine

enum SectionShelfAlert: Identifiable {
    case downloadConfirm(bookIds: Set<String>)

    var id: String {
        switch self {
        case .downloadConfirm:
            return "downloadConfirm"
        }
    }
}

@MainActor @available(macCatalyst 14.0, *)
final class SectionShelfViewModel: ObservableObject {
    let container: AppContainer
    private var snapshotTask: Task<Void, Never>?
    private var calibreEventTask: Task<Void, Never>?

    private var allDisplaySections = [ShelfSectionItem]()

    @Published var pickedLibraries = Set<String>()
    @Published var displaySections = [ShelfSectionItem]()
    @Published var libraryFilters = [ShelfLibraryFilterItem]()

    @Published var presentingBookDetailId: String? = nil
    @Published var activeAlert: SectionShelfAlert? = nil
    @Published var selectionState = ShelfSelectionState()
    @Published private(set) var isInitialLoadComplete = false
    @Published private(set) var isRefreshing = false

    init(container: AppContainer) {
        self.container = container
        setupSubscriptions()
        bootstrapIfDatabaseReady()
    }

    deinit {
        snapshotTask?.cancel()
        calibreEventTask?.cancel()
    }

    /// Idempotent bootstrap of the lazy `shelfDataModel`. Safe to call from
    /// `init`, from the calibre update task, and from the view's
    /// `.onAppear` to cover the case where the user first lands directly
    /// on the Discover tab and the database-ready signal has not yet
    /// been routed through the event stream.
    func bootstrapIfDatabaseReady() {
        guard container.logger != nil else { return }
        guard snapshotTask == nil else { return }

        let snapshots = container.shelfDataModel.snapshots()
        snapshotTask = Task { [weak self] in
            for await snapshot in snapshots {
                guard !Task.isCancelled else { return }
                self?.applySnapshot(snapshot)
            }
        }
    }

    private func setupSubscriptions() {
        let signals = container.calibreUpdates()
        calibreEventTask = Task { [weak self] in
            for await signal in signals {
                guard !Task.isCancelled else { return }
                guard let self = self else { return }

                // If database just finished initializing, bootstrap shelfDataModel.
                self.bootstrapIfDatabaseReady()

                if case .deleted(let deletedId) = signal {
                    if self.presentingBookDetailId == deletedId {
                        self.presentingBookDetailId = nil
                    }
                }
            }
        }
    }

    private func applySnapshot(_ snapshot: YabrShelfDataModel.DiscoverShelfSnapshot) {
        isInitialLoadComplete = snapshot.isInitialLoadComplete
        allDisplaySections = snapshot.sections
        applyFiltering()
    }

    func refreshShelf() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await container.shelfDataModel.refresh()
    }

    func downloadSelectedBooks(bookIds: Set<String>) {
        bookIds.forEach { bookId in
            guard let book = container.bookManager.getBook(for: bookId),
                  let format = container.sessionManager.getPreferredFormat(for: book)
            else { return }
            container.bookManager.addToShelf(book: book, formats: [format])
        }
    }

    func tapBook(bookId: String) {
        if selectionState.isEditing {
            toggleSelection(bookId: bookId)
            return
        }

        guard container.bookManager.bookExists(forPrimaryKey: bookId) else { return }
        presentingBookDetailId = bookId
    }

    func toggleSelection(bookId: String) {
        if selectionState.selectedBookIds.contains(bookId) {
            selectionState.selectedBookIds.remove(bookId)
        } else {
            selectionState.selectedBookIds.insert(bookId)
        }
    }

    func selectAllBooks() {
        let allIds = displaySections.flatMap { $0.books.map { $0.id } }
        selectionState.selectedBookIds = Set(allIds)
    }

    func clearSelection() {
        selectionState.selectedBookIds.removeAll()
    }

    func downloadSelectedBooks() {
        let targets = selectionState.selectedBookIds
        downloadSelectedBooks(bookIds: targets)
        selectionState.selectedBookIds.removeAll()
        selectionState.isEditing = false
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

    func toggleLibraryFilter(libraryId: String) {
        pickedLibraries.formSymmetricDifference([libraryId])
        applyFiltering()
    }

    func resetLibraryFilters() {
        pickedLibraries.removeAll(keepingCapacity: true)
        applyFiltering()
    }

    private func applyFiltering() {
        // Aggregate the set of libraries actually present in the section
        // book items. Sections are cross-library by category (e.g. "Author: A"),
        // so the libraryId lives on each ShelfBookItem, not on the section id.
        let availableLibraryIds = Set(
            allDisplaySections.flatMap { $0.books.compactMap { $0.libraryId } }
        )
        // Prune picked libraries that no longer exist in the calibre library
        // dictionary, but keep picked libraries that simply have no books in
        // the current section set — those should still hide every section.
        pickedLibraries.formIntersection(Set(container.libraryManager.calibreLibraries.keys))

        let libraryList = container.libraryManager.calibreLibraries
            .values
            .filter { availableLibraryIds.contains($0.id) }
            .sorted(by: { $0.name < $1.name })

        libraryFilters = libraryList.map { library in
            ShelfLibraryFilterItem(
                id: library.id,
                name: library.name,
                serverName: library.server.name,
                isSelected: pickedLibraries.contains(library.id)
            )
        }

        if pickedLibraries.isEmpty {
            displaySections = allDisplaySections
            return
        }

        displaySections = allDisplaySections.compactMap { section in
            let filteredBooks = section.books.filter { book in
                guard let bookLibraryId = book.libraryId else { return false }
                return pickedLibraries.contains(bookLibraryId)
            }
            guard !filteredBooks.isEmpty else { return nil }
            return ShelfSectionItem(id: section.id, title: section.title, books: filteredBooks)
        }
    }
}
