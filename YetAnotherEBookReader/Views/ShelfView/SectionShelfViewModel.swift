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
    private var cancellables = Set<AnyCancellable>()
    
    private var allDisplaySections = [ShelfSectionItem]()
    
    @Published var pickedLibraries = Set<String>()
    @Published var displaySections = [ShelfSectionItem]()
    @Published var libraryFilters = [ShelfLibraryFilterItem]()
    
    @Published var presentingBookDetailId: String? = nil
    @Published var activeAlert: SectionShelfAlert? = nil
    @Published var selectionState = ShelfSelectionState()
    
    init(container: AppContainer) {
        self.container = container
        setupSubscriptions()
        bootstrapShelfDataModelIfNeeded()
    }
    
    private func bootstrapShelfDataModelIfNeeded() {
        guard container.logger != nil else { return }
        
        // Force lazy initialization of shelfDataModel and seed initial items if any
        let initialItems = container.shelfDataModel.discoverShelfItems.values.sorted(by: { $0.title < $1.title })
        if !initialItems.isEmpty {
            self.allDisplaySections = initialItems
            self.applyFiltering()
        }
    }
    
    private func setupSubscriptions() {
        container.discoverShelfItemsSubject
            .sink { [weak self] sections in
                guard let self = self else { return }
                self.allDisplaySections = sections
                self.applyFiltering()
            }
            .store(in: &cancellables)
            
        container.calibreUpdatedSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] signal in
                guard let self = self else { return }
                
                // If database just finished initializing, bootstrap shelfDataModel
                if self.container.logger != nil && self.allDisplaySections.isEmpty {
                    self.bootstrapShelfDataModelIfNeeded()
                }
                
                if case .deleted(let deletedId) = signal {
                    if self.presentingBookDetailId == deletedId {
                        self.presentingBookDetailId = nil
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    func refreshShelf() {
        container.shelfDataModel.refresh()
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
            self.container.downloadManager.bookFormatDownloadSubject.send((book: book, format: format))
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
        let availableLibraryIds = Set(
            allDisplaySections.compactMap { AppContainer.parseShelfSectionId(sectionId: $0.id) }
        )
        pickedLibraries.formIntersection(availableLibraryIds)
        
        let librarySet = Set<CalibreLibrary>(
            allDisplaySections.compactMap { section -> CalibreLibrary? in
                guard let libraryId = AppContainer.parseShelfSectionId(sectionId: section.id) else { return nil }
                return container.libraryManager.calibreLibraries[libraryId]
            }
        )
        let libraryList = librarySet.sorted(by: { $0.name < $1.name })
        
        libraryFilters = libraryList.map { library in
            ShelfLibraryFilterItem(
                id: library.id,
                name: library.name,
                serverName: library.server.name,
                isSelected: pickedLibraries.contains(library.id)
            )
        }
        
        displaySections = allDisplaySections.filter { section in
            guard let libraryId = AppContainer.parseShelfSectionId(sectionId: section.id) else { return false }
            return pickedLibraries.isEmpty || pickedLibraries.contains(libraryId)
        }
    }
}
