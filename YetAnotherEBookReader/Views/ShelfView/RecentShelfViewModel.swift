//
//  RecentShelfViewModel.swift
//  YetAnotherEBookReader
//
//  Created by opencode on 2026-06-18.
//

import Foundation
import Combine
import ShelfView

@MainActor @available(macCatalyst 14.0, *)
final class RecentShelfViewModel: ObservableObject {
    private let modelData: ModelData
    private var cancellables = Set<AnyCancellable>()
    
    @Published var books = [BookModel]()
    
    init(modelData: ModelData) {
        self.modelData = modelData
        setupSubscriptions()
    }
    
    private func setupSubscriptions() {
        modelData.recentShelfModelSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] books in
                self?.books = books
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
}
