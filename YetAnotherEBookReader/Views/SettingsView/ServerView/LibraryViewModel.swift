//
//  LibraryViewModel.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026/6/12.
//

import Foundation
import Combine
import RealmSwift

class LibraryViewModel: ObservableObject {
    let modelData: ModelData
    let library: CalibreLibrary
    
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
    private var libraryRealmToken: NotificationToken?
    
    init(modelData: ModelData, library: CalibreLibrary) {
        self.modelData = modelData
        self.library = library
        
        setupBindings()
    }
    
    deinit {
        libraryRealmToken?.invalidate()
    }
    
    private func setupBindings() {
        // Fetch initially
        if let realm = try? Realm(configuration: modelData.realmConf),
           let realmLib = realm.object(ofType: CalibreLibraryRealm.self, forPrimaryKey: library.id) {
            self.discoverable = realmLib.discoverable
            self.autoUpdate = realmLib.autoUpdate
            
            // Observe changes to the Realm object
            libraryRealmToken = realmLib.observe { [weak self] change in
                guard let self = self else { return }
                switch change {
                case .change(let object, let properties):
                    for property in properties {
                        if property.name == "discoverable", let val = property.newValue as? Bool {
                            DispatchQueue.main.async { self.discoverable = val }
                        }
                        if property.name == "autoUpdate", let val = property.newValue as? Bool {
                            DispatchQueue.main.async { self.autoUpdate = val }
                        }
                    }
                case .error(let error):
                    print("Error observing CalibreLibraryRealm: \(error)")
                case .deleted:
                    break
                }
            }
        }
        
        // Listen to UI changes and save to Realm
        $discoverable
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] newValue in
                guard let self = self else { return }
                self.updateRealmField { $0.discoverable = newValue }
            }
            .store(in: &cancellables)
            
        $autoUpdate
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] newValue in
                guard let self = self else { return }
                self.updateRealmField { $0.autoUpdate = newValue }
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
    
    private func updateRealmField(writeBlock: @escaping (CalibreLibraryRealm) -> Void) {
        guard let realm = try? Realm(configuration: modelData.realmConf) else { return }
        if let realmLib = realm.object(ofType: CalibreLibraryRealm.self, forPrimaryKey: library.id) {
            try? realm.write {
                writeBlock(realmLib)
            }
        }
    }
    
    private func resolveBookTitles() {
        let serverUUID = library.server.uuid.uuidString
        let libraryName = library.name
        
        var tempFailed: [Int32: String] = [:]
        for bookId in failedBookIds {
            let primaryKey = CalibreBookRealm.PrimaryKey(serverUUID: serverUUID, libraryName: libraryName, id: bookId.description)
            if let obj = modelData.getBookRealm(forPrimaryKey: primaryKey) {
                tempFailed[bookId] = obj.title
            }
        }
        self.failedBookTitles = tempFailed
        
        var tempDeleted: [Int32: String] = [:]
        for bookId in deletedBookIds {
            let primaryKey = CalibreBookRealm.PrimaryKey(serverUUID: serverUUID, libraryName: libraryName, id: bookId.description)
            if let obj = modelData.getBookRealm(forPrimaryKey: primaryKey) {
                tempDeleted[bookId] = obj.title
            }
        }
        self.deletedBookTitles = tempDeleted
    }
    
    #if DEBUG
    func resetBooks() {
        guard let realm = try? Realm(configuration: modelData.realmConf) else { return }
        try? realm.write {
            realm.objects(CalibreBookRealm.self).forEach {
                $0.lastModified = .init(timeIntervalSince1970: 0)
                $0.lastSynced = .init(timeIntervalSince1970: 0)
                $0.title = "__RESET__"
            }
        }
    }
    #endif
}