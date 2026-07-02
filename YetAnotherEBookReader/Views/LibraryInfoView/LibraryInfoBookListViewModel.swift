//
//  LibraryInfoBookListViewModel.swift
//  YetAnotherEBookReader
//

import SwiftUI
import Combine
import OSLog

@MainActor
class LibraryInfoBookListViewModel: ObservableObject {
    @Published var selectedBookIds = Set<String>()
    @Published var downloadBookList = [CalibreBook]()
    @Published private(set) var activeDownloads: [URL: BookFormatDownload] = [:]
    
    @Published var searchString = ""
    
    @Published var batchDownloadSheetPresenting = false
    @Published var booksListInfoPresenting = false
    @Published var searchHistoryPresenting = false
    private var activeDownloadsTask: Task<Void, Never>?

    deinit {
        activeDownloadsTask?.cancel()
    }

    func bindDownloadSnapshots(container: AppContainer) {
        activeDownloadsTask?.cancel()
        activeDownloadsTask = Task { [weak self, weak container] in
            guard let container else { return }
            for await snapshot in container.downloadManager.downloadSnapshots() {
                guard !Task.isCancelled else { return }
                self?.activeDownloads = snapshot
            }
        }
    }

    func activeDownload(for book: CalibreBook) -> BookFormatDownload? {
        activeDownloads.values.first { download in
            download.book.id == book.id && download.isActive
        }
    }
    
    func syncDraftFromCriteria(_ criteriaSearchString: String) {
        self.searchString = criteriaSearchString
    }
    
    func submitSearch(libraryInfoViewModel: LibraryInfoView.ViewModel, searchViewModel: UnifiedSearchViewModel) {
        libraryInfoViewModel.searchStringChanged(searchString: searchString, searchViewModel: searchViewModel)
    }
    
    func clearSearch(libraryInfoViewModel: LibraryInfoView.ViewModel, searchViewModel: UnifiedSearchViewModel) {
        libraryInfoViewModel.searchStringChanged(searchString: "", searchViewModel: searchViewModel)
        searchString = ""
    }
    
    func prepareBatchDownload(books: [CalibreBook]) {
        downloadBookList.removeAll(keepingCapacity: true)
        downloadBookList = books
        batchDownloadSheetPresenting = true
    }
    
    func buildSections(
        books: [CalibreBook],
        sectionedBy: LibraryInfoView.GroupKey?
    ) -> [LibraryInfoBookSection] {
        guard !books.isEmpty else { return [] }
        
        if let sectionedBy = sectionedBy {
            if let groupString = sectionedBy.groupString {
                let grouped = Dictionary(grouping: Array(books.enumerated()), by: { groupString($0.element) })
                let sortedKeys = grouped.keys.compactMap { $0 }.sorted()
                return sortedKeys.map { key in
                    LibraryInfoBookSection(
                        id: key,
                        title: key,
                        items: (grouped[key] ?? []).map { index, book in
                            LibraryInfoBookSection.Item(id: String(book.id), index: index, book: book)
                        }
                    )
                }
            } else if let groupRating = sectionedBy.groupRating {
                let grouped = Dictionary(grouping: Array(books.enumerated()), by: { groupRating($0.element) })
                let sortedKeys = grouped.keys.sorted(by: >)
                return sortedKeys.map { key in
                    LibraryInfoBookSection(
                        id: String(key),
                        title: CalibreBookRealm.RatingDescription(key),
                        items: (grouped[key] ?? []).map { index, book in
                            LibraryInfoBookSection.Item(id: String(book.id), index: index, book: book)
                        }
                    )
                }
            }
        }
        
        return [
            LibraryInfoBookSection(
                id: "all",
                title: "",
                items: books.enumerated().map { index, book in
                    LibraryInfoBookSection.Item(id: String(book.id), index: index, book: book)
                }
            )
        ]
    }
    
    func filterableAuthors(for book: CalibreBook, filterCriteriaCategory: [String: Set<String>]) -> [String] {
        book.authors.filter { filterCriteriaCategory["Authors"]?.contains($0) != true }
    }
    
    func filterableTags(for book: CalibreBook, filterCriteriaCategory: [String: Set<String>]) -> [String] {
        book.tags.filter { filterCriteriaCategory["Tags"]?.contains($0) != true }
    }
    
    func shouldShowSeriesFilter(for book: CalibreBook, filterCriteriaCategory: [String: Set<String>]) -> Bool {
        !book.series.isEmpty && filterCriteriaCategory["Series"]?.contains(book.series) != true
    }
    
    func downloadOrAddToShelfAction(book: CalibreBook, format: Format, container: AppContainer) {
        if book.inShelf {
            if case .failure(let error) = container.downloadManager.startDownload(book, format: format, overwrite: true) {
                Logger(subsystem: "YetAnotherEBookReader", category: "LibraryInfoBookListViewModel").error("Failed to start download: \(error.localizedDescription)")
            }
        } else {
            container.bookManager.addToShelf(book: book, formats: [format])
        }
    }
    
    func updateFilterCategoryAction(
        key: String,
        value: String,
        libraryInfoViewModel: LibraryInfoView.ViewModel,
        searchViewModel: UnifiedSearchViewModel
    ) {
        libraryInfoViewModel.updateFilterCategory(key: key, value: value, searchViewModel: searchViewModel)
    }
    
    func updateFilterSeriesAction(
        series: String,
        libraryInfoViewModel: LibraryInfoView.ViewModel,
        searchViewModel: UnifiedSearchViewModel
    ) {
        libraryInfoViewModel.sortCriteria.by = .SeriesIndex
        libraryInfoViewModel.sortCriteria.ascending = true
        libraryInfoViewModel.updateFilterCategory(key: "Series", value: series, searchViewModel: searchViewModel)
    }
}

struct LibraryInfoBookSection: Identifiable {
    let id: String
    let title: String
    let items: [Item]
    
    struct Item: Identifiable {
        let id: String
        let index: Int
        let book: CalibreBook
    }
}
