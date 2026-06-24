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
    let modelData: ModelData
    private var cancellables = Set<AnyCancellable>()
    
    private var allDisplaySections = [ShelfSectionItem]()
    
    @Published var pickedLibraries = Set<String>()
    @Published var displaySections = [ShelfSectionItem]()
    @Published var libraryFilters = [ShelfLibraryFilterItem]()
    
    @Published var presentingBookDetailId: String? = nil
    @Published var activeAlert: SectionShelfAlert? = nil
    @Published var selectionState = ShelfSelectionState()
    
    init(modelData: ModelData) {
        self.modelData = modelData
        setupSubscriptions()
        bootstrapShelfDataModelIfNeeded()
    }
    
    private func bootstrapShelfDataModelIfNeeded() {
        guard modelData.logger != nil else { return }
        
        // Force lazy initialization of shelfDataModel and seed initial items if any
        let initialItems = modelData.shelfDataModel.discoverShelfItems.values.sorted(by: { $0.title < $1.title })
        if !initialItems.isEmpty {
            self.allDisplaySections = initialItems
            self.applyFiltering()
        }
    }
    
    private func setupSubscriptions() {
        modelData.discoverShelfItemsSubject
            .collect(.byTime(RunLoop.main, .seconds(1)))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] displaySectionsArray in
                guard let self = self, let displaySections = displaySectionsArray.last else { return }
                self.allDisplaySections = displaySections
                self.applyFiltering()
            }
            .store(in: &cancellables)
            
        modelData.calibreUpdatedSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] signal in
                guard let self = self else { return }
                
                // If database just finished initializing, bootstrap shelfDataModel
                if self.modelData.logger != nil && self.allDisplaySections.isEmpty {
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
        modelData.shelfDataModel.refresh()
    }
    
    func downloadSelectedBooks(bookIds: Set<String>) {
        bookIds.forEach { bookId in
            guard let book = modelData.bookManager.getBook(for: bookId),
                  let format = modelData.sessionManager.getPreferredFormat(for: book)
            else { return }
            modelData.bookManager.addToShelf(book: book, formats: [format])
        }
    }

    func tapBook(bookId: String) {
        if selectionState.isEditing {
            toggleSelection(bookId: bookId)
            return
        }

        guard modelData.bookManager.bookExists(forPrimaryKey: bookId) else { return }
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
        guard let book = modelData.bookManager.booksInShelf[bookId] else { return }
        book.formats.filter {
            $1.cached && !$1.cacheUptoDate
        }.keys.forEach {
            guard let format = Format(rawValue: $0) else { return }
            self.modelData.downloadManager.bookFormatDownloadSubject.send((book: book, format: format))
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
            allDisplaySections.compactMap { ModelData.parseShelfSectionId(sectionId: $0.id) }
        )
        pickedLibraries.formIntersection(availableLibraryIds)
        
        let librarySet = Set<CalibreLibrary>(
            allDisplaySections.compactMap { section -> CalibreLibrary? in
                guard let libraryId = ModelData.parseShelfSectionId(sectionId: section.id) else { return nil }
                return modelData.libraryManager.calibreLibraries[libraryId]
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
            guard let libraryId = ModelData.parseShelfSectionId(sectionId: section.id) else { return false }
            return pickedLibraries.isEmpty || pickedLibraries.contains(libraryId)
        }
    }
}
