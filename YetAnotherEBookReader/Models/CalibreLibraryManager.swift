//
//  CalibreLibraryManager.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026/6/13.
//

import Foundation
import Combine
import RealmSwift
import SwiftUI
import OSLog

class CalibreLibraryManager: ObservableObject {
    private let logger = Logger(subsystem: "YetAnotherEBookReader", category: "CalibreLibraryManager")
    
    weak var modelData: ModelData?
    let databaseService: DatabaseService
    
    @Published var calibreLibraries = [String: CalibreLibrary]() {
        didSet {
            modelData?.calibreServerService.updateCalibreLibraries(calibreLibraries)
        }
    }
    @Published var calibreLibraryInfoStaging = [String: CalibreLibraryInfo]()
    @Published var librarySyncStatus = [String: CalibreSyncStatus]()
    var localLibrary: CalibreLibrary?
    
    private var calibreCancellables = Set<AnyCancellable>()
    
    init(modelData: ModelData, databaseService: DatabaseService) {
        self.modelData = modelData
        self.databaseService = databaseService
    }
    
    // MARK: - Migrated Methods
    
    func populateLibraries() {
        guard let realm = databaseService.realm else { return }
        let librariesCached = realm.objects(CalibreLibraryRealm.self)

        librariesCached.forEach { libraryRealm in
            guard let serverUUIDString = libraryRealm.serverUUID,
                  let calibreServer = modelData?.calibreServers[serverUUIDString]
            else {
                return
            }
            let calibreLibrary = CalibreLibrary(
                server: calibreServer,
                key: libraryRealm.key ?? libraryRealm.name!,
                name: libraryRealm.name!,
                autoUpdate: libraryRealm.autoUpdate,
                discoverable: libraryRealm.discoverable,
                hidden: libraryRealm.hidden,
                lastModified: libraryRealm.lastModified,
                customColumnInfos: {
                    guard let data = libraryRealm.customColumnsData else { return [:] }
                    return (try? JSONDecoder().decode([String: CalibreCustomColumnInfo].self, from: data)) ?? [:]
                }()
            )
            
            calibreLibraries[calibreLibrary.id] = calibreLibrary
        }
    }
    
    func populateLocalLibraryBooks() {
        guard let documentDirectoryURL = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            return
        }
        
        let tmpServer = CalibreServer(uuid: CalibreServer.LocalServerUUID, name: "Document Folder", baseUrl: ".", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        guard let modelData = self.modelData else { return }
        
        modelData.documentServer = modelData.calibreServers[tmpServer.id]
        if modelData.documentServer == nil || modelData.documentServer?.name != tmpServer.name {
            modelData.calibreServers[tmpServer.id] = tmpServer
            modelData.documentServer = modelData.calibreServers[tmpServer.id]
            do {
                try modelData.serverManager.updateServerRealm(server: modelData.documentServer!)
            } catch {
                logger.error("Failed to update server realm for document folder: \(error.localizedDescription)")
            }
        }
        
        let localLibraryURL = documentDirectoryURL.appendingPathComponent("Local Library", isDirectory: true)
        
        if FileManager.default.fileExists(atPath: localLibraryURL.path) == false {
            do {
                try FileManager.default.createDirectory(atPath: localLibraryURL.path, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print(error)
            }
        }
        
        let tmpLibrary = CalibreLibrary(
            server: modelData.documentServer!,
            key: localLibraryURL.lastPathComponent,
            name: localLibraryURL.lastPathComponent)
        localLibrary = calibreLibraries[tmpLibrary.id]
        if localLibrary == nil {
            calibreLibraries[tmpLibrary.id] = tmpLibrary
            localLibrary = calibreLibraries[tmpLibrary.id]
            do {
                try updateLibraryRealm(library: localLibrary!, realm: databaseService.realm)
            } catch {
                logger.error("Failed to update local library realm: \(error.localizedDescription)")
            }
        }
        
        guard let dirEnum = FileManager.default.enumerator(atPath: localLibraryURL.path) else {
            return
        }
        
        dirEnum.forEach {
            guard let fileName = $0 as? String else {
                return
            }
            if fileName.hasSuffix(".db") { return }
            if fileName.hasSuffix(".db.lock") { return }
            if fileName.hasSuffix(".db.note") { return }
            if fileName.hasSuffix(".db.management") { return }
            if fileName.hasSuffix(".cv") { return }
            if fileName.hasSuffix(".mx") { return }

            print("populateLocalLibraryBooks \(fileName)")
            let fileURL = modelData.documentServer!.localBaseUrl!.appendingPathComponent(localLibrary!.key, isDirectory: true).appendingPathComponent(fileName, isDirectory: false)

            modelData.loadLocalLibraryBookMetadata(fileURL: fileURL, in: localLibrary!, on: modelData.documentServer!)
        }
        
        let removedBooks: [CalibreBook] = modelData.booksInShelf.values.compactMap { (book: CalibreBook) -> CalibreBook? in
            guard book.library.server.isLocal else { return nil }
            let existingFormats: [String] = book.formats.compactMap {
                guard let format = Format(rawValue: $0.key),
                      let bookFileUrl = getSavedUrl(book: book, format: format) else { return nil }
                
                var isDirectory : ObjCBool = false
                guard FileManager.default.fileExists(atPath: bookFileUrl.path, isDirectory: &isDirectory) else {
                    return nil
                }
                guard isDirectory.boolValue == false else {
                    return nil
                }
                
                return $0.key
            }

            guard existingFormats.isEmpty else {
                return nil
            }
            
            return book
        }
        
        removedBooks.forEach {
            modelData.removeFromShelf(inShelfId: $0.inShelfId)
            print("populateLocalLibraryBooks removeFromShelf \($0)")
        }
    }
    
    func updateLibraryRealm(library: CalibreLibrary, realm: Realm) throws {
        let libraryRealm = CalibreLibraryRealm()
        libraryRealm.key = library.key
        libraryRealm.name = library.name
        libraryRealm.serverUUID = library.server.uuid.uuidString
        
        libraryRealm.customColumnsData = try? JSONEncoder().encode(library.customColumnInfos)
        
        libraryRealm.autoUpdate = library.autoUpdate
        libraryRealm.discoverable = library.discoverable
        libraryRealm.hidden = library.hidden
        libraryRealm.lastModified = library.lastModified
        
        try realm.write {
            realm.add(libraryRealm, update: .all)
        }
    }
    
    func hideLibrary(libraryId: String) {
        calibreLibraries[libraryId]?.hidden = true
        calibreLibraries[libraryId]?.autoUpdate = false
        if let library = calibreLibraries[libraryId] {
            try? updateLibraryRealm(library: library, realm: databaseService.realm)
        }
    }
    
    func restoreLibrary(libraryId: String) {
        calibreLibraries[libraryId]?.hidden = false
        calibreLibraries[libraryId]?.lastModified = Date(timeIntervalSince1970: 0)
        if let library = calibreLibraries[libraryId] {
            try? updateLibraryRealm(library: library, realm: databaseService.realm)
        }
    }
    
    func queryLibraryBookRealmCount(library: CalibreLibrary, realm: Realm) -> Int {
        return realm.objects(CalibreBookRealm.self).filter(
            NSPredicate(format: "serverUUID = %@ AND libraryName = %@",
                        library.server.uuid.uuidString,
                        library.name
            )
        ).count
    }
    
    func updateServerLibraryInfo(serverInfo: CalibreServerInfo) {
        guard let server = modelData?.calibreServers[serverInfo.server.id] else { return }
        
        serverInfo.libraryMap.forEach { key, name in
            let newLibrary = CalibreLibrary(server: serverInfo.server, key: key, name: name)
            let libraryId = newLibrary.id
            
            if calibreLibraries[libraryId] != nil {
                calibreLibraries[libraryId]!.key = newLibrary.key
            } else {
                let library = CalibreLibrary(server: server, key: newLibrary.key, name: newLibrary.name)
                calibreLibraries[libraryId] = library
            }
            do {
                try updateLibraryRealm(library: calibreLibraries[libraryId]!, realm: databaseService.realm)
            } catch {
                logger.error("Failed to update library realm in updateServerLibraryInfo: \(error.localizedDescription)")
            }
        }
    }
    
    @discardableResult
    @MainActor
    func probeLibrary(request: CalibreProbeLibraryRequest) async -> CalibreLibraryProbeTask {
        guard let calibreServerService = modelData?.calibreServerService else {
            fatalError("calibreServerService not found")
        }
        let task = await calibreServerService.probeLibrary(library: request.library)
        
        if let probeResult = task.probeResult {
            self.calibreLibraryInfoStaging[task.library.id] = .init(library: task.library, totalNumber: probeResult.total_num, errorMessage: "Success")
        } else {
            self.calibreLibraryInfoStaging[task.library.id] = .init(library: task.library, totalNumber: 0, errorMessage: "Failed")
        }
        
        return task
    }
    
    @MainActor
    func removeLibrary(library: CalibreLibrary) async {
        guard let modelData = self.modelData else { return }
        if librarySyncStatus[library.id] != nil {
            librarySyncStatus[library.id]?.isSync = true
        } else {
            librarySyncStatus[library.id] = .init(library: library, isSync: true)
        }
        
        //remove cached book files
        let libraryBooksInShelf = modelData.booksInShelf.filter {
            $0.value.library.id == library.id
        }
        libraryBooksInShelf.forEach {
            modelData.clearCache(inShelfId: $0.key)
            modelData.removeFromShelf(inShelfId: $0.key)     //just in case
        }
        
        let serverUUIDString = library.server.uuid.uuidString
        let libraryName = library.name
        let realmConf = modelData.realmConf!
        
        await Task.detached(priority: .background) {
            guard let realm = try? Realm(configuration: realmConf)
            else { return }
            
            //remove library info
            let predicate = NSPredicate(format: "serverUUID = %@ AND libraryName = %@", serverUUIDString, libraryName)
            while true {
                let booksToDelete = realm.objects(CalibreBookRealm.self).filter(predicate).prefix(256).map { $0 }
                if booksToDelete.isEmpty { break }
                
                try? realm.write {
                    realm.delete(booksToDelete)
                }
            }
        }.value
        
        self.librarySyncStatus[library.id]?.isSync = false
    }
    
    func registerProbeLibraryLastModifiedCancellable() {
        let dateFormatter = ISO8601DateFormatter()
        let dateFormatter2 = ISO8601DateFormatter()
        dateFormatter2.formatOptions.formUnion(.withFractionalSeconds)
        
        let queue = DispatchQueue(label: "probe-library", qos: .userInitiated)
        guard let modelData = self.modelData else { return }
        modelData.probeLibraryLastModifiedSubject.receive(on: queue)
            .flatMap { [weak self] request -> AnyPublisher<CalibreSyncLibraryResult, Never> in
                guard let self = self, let calibreServerService = self.modelData?.calibreServerService else {
                    return Empty().eraseToAnyPublisher()
                }
                return calibreServerService.syncLibraryPublisher(
                    resultPrev: .init(request: request, result: [:]),
                    order: "",
                    filter: "",
                    limit: 1
                )
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] result in
                guard let self = self,
                      var library = self.calibreLibraries[result.request.library.id],
                      let lastModifiedStr = result.list.data.last_modified.first?.value.v,
                      let lastModified = dateFormatter.date(from: lastModifiedStr) ?? dateFormatter2.date(from: lastModifiedStr)
                else {
                    return
                }
                
                if lastModified > library.lastModified {
                    library.lastModified = lastModified
                    self.calibreLibraries[result.request.library.id] = library
                    try! self.updateLibraryRealm(library: library, realm: self.databaseService.realm)
                }
                
                self.modelData?.calibreUpdatedSubject.send(.library(library))
            }
            .store(in: &calibreCancellables)
    }
    
    func syncLibrary(request: CalibreSyncLibraryRequest) async {
        guard let modelData = self.modelData else { return }
        let calibreServerService = modelData.calibreServerService
        let libraryId = request.library.id
        guard (self.librarySyncStatus[libraryId]?.isSync ?? false) == false else {
            return
        }
        
        guard request.library.hidden == false else {
            return
        }
        
        if var status = self.librarySyncStatus[libraryId] {
            status.isSync = true
            status.isError = false
            status.msg = ""
            status.cnt = nil
            self.librarySyncStatus[libraryId] = status
        } else {
            self.librarySyncStatus[libraryId] = .init(library: request.library, isSync: true)
        }
        
        var result = await calibreServerService.getCustomColumns(request: request)
        result = await calibreServerService.getLibraryCategories(resultPrev: result)
        
        let shouldSyncBooks = request.autoUpdateOnly == false || request.library.autoUpdate
        
        if shouldSyncBooks {
            var filter = ""
            if request.incremental,
               let libraryRealm = databaseService.realm.object(
                ofType: CalibreLibraryRealm.self,
                forPrimaryKey: CalibreLibraryRealm.PrimaryKey(
                    serverUUID: result.request.library.server.uuid.uuidString,
                    libraryName: result.request.library.name)
               ) {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions.formUnion(.withColonSeparatorInTimeZone)
                formatter.timeZone = .current
                let lastModifiedStr = formatter.string(from: libraryRealm.lastModified)
                filter = "last_modified:\">=\(lastModifiedStr)\""
            }
            
            result = await calibreServerService.syncLibrary(resultPrev: result, filter: filter)
            
            self.librarySyncStatus[libraryId]?.isError = result.isError
            
            if result.isError == false {
                let library = result.request.library
                let serverUUID = library.server.uuid.uuidString
                
                await withCheckedContinuation { continuation in
                    ModelData.SaveBooksMetadataRealmQueue.async { [weak self] in
                        guard let self = self, let realmSave = self.modelData?.realmSaveBooksMetadata else {
                            continuation.resume()
                            return
                        }
                        try? self.updateLibraryRealm(library: library, realm: realmSave)
                        continuation.resume()
                    }
                }
                
                result.categories.filter { $0.is_category }.forEach { category in
                    Task {
                        do {
                            _ = try await modelData.librarySearchManager.libraryCategoryService.fetchAndCacheCategory(library: library, category: category)
                        } catch {
                            logger.error("Failed to fetch and cache category \(category.name) for \(library.name): \(error.localizedDescription)")
                        }
                    }
                }
                
                let dateFormatter = ISO8601DateFormatter()
                let dateFormatter2 = ISO8601DateFormatter()
                dateFormatter2.formatOptions.formUnion(.withFractionalSeconds)
                
                var progress = 0
                let total = result.list.book_ids.count
                for chunk in result.list.book_ids.chunks(size: 1024) {
                    let preMsg = "\(progress) / \(total)"
                    let list = chunk.compactMap { id -> [String: Any]? in
                        let idStr = id.description
                        guard let lastModifiedStr = result.list.data.last_modified[idStr]?.v,
                              let lastModified = dateFormatter.date(from: lastModifiedStr) ?? dateFormatter2.date(from: lastModifiedStr) else { return nil }
                        return [
                            "primaryKey": CalibreBookRealm.PrimaryKey(serverUUID: serverUUID, libraryName: library.name, id: idStr),
                            "serverUUID": serverUUID,
                            "libraryName": library.name,
                            "lastModified": lastModified,
                            "idInLib": id
                        ]
                    }
                    progress += chunk.count
                    let postMsg = "\(progress) / \(total)"
                    await saveBookMetadata(metadata: .init(library: library, action: .save(list), preMsg: preMsg, postMsg: postMsg))
                    
                    if let lastMod = list.last?["lastModified"] as? Date {
                        result.lastModified = lastMod
                    }
                }
                
                if result.request.incremental == false {
                    await saveBookMetadata(metadata: .init(library: library, action: .updateDeleted(result.list.data.last_modified), preMsg: "", postMsg: ""))
                }
                
                await saveBookMetadata(metadata: .init(library: library, action: .complete(result.lastModified, result.result["result"] ?? [:]), preMsg: "", postMsg: "Success"))
                
                if modelData.serverManager.isServerReachable(server: library.server) {
                    modelData.calibreUpdatedSubject.send(.server(library.server))
                    modelData.probeLibraryLastModifiedSubject.send(.init(library: library, autoUpdateOnly: false, incremental: false))
                }
            }
        } else {
            let isError = !result.errmsg.isEmpty
            self.librarySyncStatus[libraryId]?.isError = isError
            self.librarySyncStatus[libraryId]?.isSync = false
            
            if !isError {
                let library = result.request.library
                
                result.categories.filter { $0.is_category }.forEach { category in
                    Task {
                        do {
                            _ = try await modelData.librarySearchManager.libraryCategoryService.fetchAndCacheCategory(library: library, category: category)
                        } catch {
                            logger.error("Failed to fetch and cache category \(category.name) for \(library.name): \(error.localizedDescription)")
                        }
                    }
                }
                
                self.librarySyncStatus[libraryId]?.msg = "Success (Categories)"
                
                if modelData.serverManager.isServerReachable(server: library.server) {
                    modelData.calibreUpdatedSubject.send(.server(library.server))
                }
            } else {
                self.librarySyncStatus[libraryId]?.msg = result.errmsg
            }
        }
    }
    
    @MainActor
    func saveBookMetadata(metadata: CalibreSyncLibraryBooksMetadata) async {
        guard let modelData = self.modelData else { return }
        self.librarySyncStatus[metadata.library.id]?.msg = metadata.preMsg
        
        var metadataResult = metadata
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            ModelData.SaveBooksMetadataRealmQueue.async { [weak self] in
                guard let self = self, let realm = self.modelData?.realmSaveBooksMetadata else {
                    continuation.resume()
                    return
                }
                
                switch metadataResult.action {
                case let .save(list):
                    try? realm.write {
                        list.forEach {
                            realm.create(CalibreBookRealm.self, value: $0, update: .modified)
                        }
                    }
                case let .updateDeleted(last_modified):
                    let objects = realm.objects(CalibreBookRealm.self).filter(
                        "serverUUID = %@ AND libraryName = %@", metadataResult.library.server.uuid.uuidString, metadataResult.library.name
                    )
                    metadataResult.bookDeleted = objects
                        .filter {
                            $0.inShelf == false && last_modified[$0.idInLib.description] == nil
                        }
                        .map { $0.idInLib }
                case .complete:
                    if metadataResult.library.autoUpdate {
                        let objects = realm.objects(CalibreBookRealm.self).filter(
                            "serverUUID = %@ AND libraryName = %@", metadataResult.library.server.uuid.uuidString, metadataResult.library.name
                        )
                        metadataResult.bookCount = objects.count
                        
                        let objectsNeedUpdate = objects.filter("lastSynced < lastModified")
                        metadataResult.bookToUpdate = objectsNeedUpdate
                            .sorted(byKeyPath: "lastModified", ascending: false)
                            .map { $0.idInLib }
                    }
                }
                continuation.resume()
            }
        }
        
        let library = metadata.library
        var libraryUpdated: CalibreLibrary? = nil
        
        switch metadataResult.action {
        case let .complete(lastModified, columnInfos):
            if columnInfos.isEmpty == false,
               library.customColumnInfos != columnInfos {
                if libraryUpdated == nil {
                    libraryUpdated = library
                }
                libraryUpdated!.customColumnInfos = columnInfos
            }
            if let lastModified = lastModified,
               library.lastModified != lastModified {
                if libraryUpdated == nil {
                    libraryUpdated = library
                }
                libraryUpdated!.lastModified = lastModified
            }
            
            if let libraryUpdated = libraryUpdated {
                self.calibreLibraries[library.id] = libraryUpdated
                await withCheckedContinuation { continuation in
                    ModelData.SaveBooksMetadataRealmQueue.async { [weak self] in
                        guard let self = self, let realmSave = self.modelData?.realmSaveBooksMetadata else {
                            continuation.resume()
                            return
                        }
                        try? self.updateLibraryRealm(library: libraryUpdated, realm: realmSave)
                        continuation.resume()
                    }
                }
            }
            
            self.librarySyncStatus[library.id]?.isSync = false
            self.librarySyncStatus[library.id]?.cnt = metadataResult.bookCount
            
            let bookToUpdate = metadataResult.bookToUpdate.filter {
                self.librarySyncStatus[library.id]?.upd.contains($0) == false
            }
            self.librarySyncStatus[library.id]?.upd.formUnion(bookToUpdate)
            
            bookToUpdate.chunks(size: 256).forEach { chunk in
                Task {
                    await modelData.getBooksMetadata(request: .init(library: metadata.library, books: chunk, getAnnotations: false))
                }
            }
        case .updateDeleted:
            self.librarySyncStatus[library.id]?.del.formUnion(metadataResult.bookDeleted)
        case let .save(list):
            let bookIds = list.compactMap { $0["idInLib"] as? Int32 }
            bookIds.chunks(size: 256).forEach { chunk in
                Task {
                    await modelData.getBooksMetadata(request: .init(library: library, books: chunk, getAnnotations: false))
                }
            }
        }
        
        self.librarySyncStatus[library.id]?.msg = metadata.postMsg
    }
}
