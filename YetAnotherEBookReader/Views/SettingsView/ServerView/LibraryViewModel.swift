//
//  LibraryViewModel.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026/6/12.
//

import Foundation
import SwiftUI

class LibraryViewModel: ObservableObject {
    let container: AppContainer
    let library: CalibreLibrary
    private let libraryRepository: LibraryRepositoryProtocol
    
    @Published var discoverable: Bool = false
    @Published var autoUpdate: Bool = false
    
    // UI state derived from container.librarySyncStatus
    @Published var isSync = false
    @Published var isUpd = false
    @Published var isError = false
    @Published var msg = "nil"
    @Published var cnt = -1
    @Published var updCount = -1
    @Published var delCount = -1
    @Published var errCount = -1
    
    @Published var failedBookTitles: [Int32: String] = [:]
    @Published var deletedBookTitles: [Int32: String] = [:]
    
    @Published var failedBookIds: [Int32] = []
    @Published var deletedBookIds: [Int32] = []
    
    private var libraryObservationTask: Task<Void, Never>?
    private var syncStatusObservationTask: Task<Void, Never>?
    
    init(container: AppContainer, library: CalibreLibrary, libraryRepository: LibraryRepositoryProtocol? = nil) {
        self.container = container
        self.library = library
        self.libraryRepository = libraryRepository ?? container.libraryRepository
        
        setupBindings()
    }

    deinit {
        libraryObservationTask?.cancel()
        syncStatusObservationTask?.cancel()
    }
    
    private func setupBindings() {
        if let persistedLibrary = libraryRepository.getLibrary(id: library.id) {
            self.discoverable = persistedLibrary.discoverable
            self.autoUpdate = persistedLibrary.autoUpdate
        }

        libraryObservationTask?.cancel()
        libraryObservationTask = Task { @MainActor [weak self, libraryRepository, libraryId = library.id] in
            for await observedLibrary in libraryRepository.observeLibrary(id: libraryId) {
                guard !Task.isCancelled, let observedLibrary else { continue }
                self?.applyObservedFlags(from: observedLibrary)
            }
        }
            
        syncStatusObservationTask?.cancel()
        syncStatusObservationTask = Task { @MainActor [weak self, container] in
            for await statusMap in container.libraryManager.librarySyncStatusSnapshots() {
                guard !Task.isCancelled else { return }
                self?.applySyncStatus(statusMap)
            }
        }
    }

    func setDiscoverable(_ newValue: Bool) {
        guard discoverable != newValue else { return }
        discoverable = newValue
        try? libraryRepository.updateLibraryFlags(
            id: library.id,
            discoverable: newValue,
            autoUpdate: autoUpdate
        )
    }

    func setAutoUpdate(_ newValue: Bool) {
        guard autoUpdate != newValue else { return }
        autoUpdate = newValue
        try? libraryRepository.updateLibraryFlags(
            id: library.id,
            discoverable: discoverable,
            autoUpdate: newValue
        )
    }

    private func applyObservedFlags(from library: CalibreLibrary) {
        discoverable = library.discoverable
        autoUpdate = library.autoUpdate
    }

    private func applySyncStatus(_ statusMap: [String: CalibreSyncStatus]) {
        let status = statusMap[library.id]
        isSync = status?.isSync ?? false
        isUpd = status?.isUpd ?? false
        isError = status?.isError ?? false
        msg = status?.msg ?? "nil"
        cnt = status?.cnt ?? -1
        updCount = status?.upd.count ?? -1
        delCount = status?.del.count ?? -1
        errCount = status?.err.count ?? -1

        failedBookIds = status?.err.map { $0 }.sorted() ?? []
        deletedBookIds = status?.del.map { $0 }.sorted() ?? []

        resolveBookTitles()
    }
    
    private func resolveBookTitles() {
        var tempFailed: [Int32: String] = [:]
        for bookId in failedBookIds {
            if let book = container.bookRepository.getBook(library: library, bookId: bookId) {
                tempFailed[bookId] = book.title
            }
        }
        self.failedBookTitles = tempFailed

        var tempDeleted: [Int32: String] = [:]
        for bookId in deletedBookIds {
            if let book = container.bookRepository.getBook(library: library, bookId: bookId) {
                tempDeleted[bookId] = book.title
            }
        }
        self.deletedBookTitles = tempDeleted
    }

    #if DEBUG
    func resetBooks() {
        container.bookRepository.resetBooks(
            serverUUID: library.server.uuid.uuidString,
            libraryName: library.name
        )
    }
    #endif
}
