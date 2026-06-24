//
//  LibraryViewModel.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026/6/12.
//

import Foundation
import Combine

class LibraryViewModel: ObservableObject {
    let modelData: ModelData
    let library: CalibreLibrary
    private let libraryRepository: LibraryRepositoryProtocol
    
    @Published var discoverable: Bool = false
    @Published var autoUpdate: Bool = false
    
    // UI state derived from modelData.librarySyncStatus
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
    
    private var cancellables = Set<AnyCancellable>()
    
    init(modelData: ModelData, library: CalibreLibrary, libraryRepository: LibraryRepositoryProtocol? = nil) {
        self.modelData = modelData
        self.library = library
        self.libraryRepository = libraryRepository ?? modelData.libraryRepository
        
        setupBindings()
    }
    
    private func setupBindings() {
        if let persistedLibrary = libraryRepository.getLibrary(id: library.id) {
            self.discoverable = persistedLibrary.discoverable
            self.autoUpdate = persistedLibrary.autoUpdate
        }

        libraryRepository.observeLibrary(id: library.id)
            .sink { [weak self] observedLibrary in
                guard let self = self, let observedLibrary = observedLibrary else { return }
                self.discoverable = observedLibrary.discoverable
                self.autoUpdate = observedLibrary.autoUpdate
            }
            .store(in: &cancellables)
        
        // Listen to UI changes and save to Realm
        $discoverable
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] newValue in
                guard let self = self else { return }
                try? self.libraryRepository.updateLibraryFlags(
                    id: self.library.id,
                    discoverable: newValue,
                    autoUpdate: self.autoUpdate
                )
            }
            .store(in: &cancellables)
            
        $autoUpdate
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] newValue in
                guard let self = self else { return }
                try? self.libraryRepository.updateLibraryFlags(
                    id: self.library.id,
                    discoverable: self.discoverable,
                    autoUpdate: newValue
                )
            }
            .store(in: &cancellables)
            
        // Observe modelData.librarySyncStatus
        modelData.libraryManager.$librarySyncStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] statusMap in
                guard let self = self else { return }
                let status = statusMap[self.library.id]
                self.isSync = status?.isSync ?? false
                self.isUpd = status?.isUpd ?? false
                self.isError = status?.isError ?? false
                self.msg = status?.msg ?? "nil"
                self.cnt = status?.cnt ?? -1
                self.updCount = status?.upd.count ?? -1
                self.delCount = status?.del.count ?? -1
                self.errCount = status?.err.count ?? -1
                
                self.failedBookIds = status?.err.map { $0 }.sorted() ?? []
                self.deletedBookIds = status?.del.map { $0 }.sorted() ?? []
                
                self.resolveBookTitles()
            }
            .store(in: &cancellables)
    }
    
    private func resolveBookTitles() {
        let serverUUID = library.server.uuid.uuidString
        let libraryName = library.name

        var tempFailed: [Int32: String] = [:]
        for bookId in failedBookIds {
            let primaryKey = CalibreBookRealm.PrimaryKey(serverUUID: serverUUID, libraryName: libraryName, id: bookId.description)
            if let book = modelData.bookManager.getBook(for: primaryKey) {
                tempFailed[bookId] = book.title
            }
        }
        self.failedBookTitles = tempFailed

        var tempDeleted: [Int32: String] = [:]
        for bookId in deletedBookIds {
            let primaryKey = CalibreBookRealm.PrimaryKey(serverUUID: serverUUID, libraryName: libraryName, id: bookId.description)
            if let book = modelData.bookManager.getBook(for: primaryKey) {
                tempDeleted[bookId] = book.title
            }
        }
        self.deletedBookTitles = tempDeleted
    }

    #if DEBUG
    func resetBooks() {
        modelData.bookRepository.resetBooks(
            serverUUID: library.server.uuid.uuidString,
            libraryName: library.name
        )
    }
    #endif
}
