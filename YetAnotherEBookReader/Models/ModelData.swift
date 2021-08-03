//
//  ModelData.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/1/25.
//

import Foundation
import Combine
import RealmSwift
import SwiftUI
import OSLog
import Kingfisher
import R2Shared
import R2Streamer
import CryptoSwift

#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

final class ModelData: ObservableObject {
    @Published var deviceName = UIDevice.current.name
    
    @Published var calibreServers = [String: CalibreServer]()
    @Published var currentCalibreServerId = "" {
        didSet {
            guard oldValue != currentCalibreServerId else { return }
            
            UserDefaults.standard.set(currentCalibreServerId, forKey: Constants.KEY_DEFAULTS_SELECTED_SERVER_ID)
            
            currentBookId = 0
            filteredBookList.removeAll()
            calibreServerLibraryBooks.removeAll()
            
            guard let server = calibreServers[currentCalibreServerId] else { return }
            
            let tmpLastLibrary = CalibreLibrary(server: server, key: server.lastLibrary, name: server.lastLibrary)
            if let library = calibreLibraries[tmpLastLibrary.id] {
                currentCalibreLibraryId = library.id
                return
            }
            
            let tmpDefaultLibrary = CalibreLibrary(server: server, key: server.defaultLibrary, name: server.defaultLibrary)
            
            if let library = calibreLibraries[tmpDefaultLibrary.id] {
                currentCalibreLibraryId = library.id
                return
            }
            
            let serverLibraryIDs = calibreLibraries.compactMap {
                guard $0.value.server.id == server.id else { return nil }
                return $0.key
            } as [String]
            currentCalibreLibraryId = serverLibraryIDs.first ?? "Empty Server"
            
        }
    }
    var currentCalibreServer: CalibreServer? {
        calibreServers[currentCalibreServerId]
    }
    
    @Published var calibreLibraries = [String: CalibreLibrary]()
    @Published var currentCalibreLibraryId = "" {
        didSet {
            guard oldValue != currentCalibreLibraryId else { return }
            
            guard let library = calibreLibraries[currentCalibreLibraryId] else { return }
            guard var server = calibreServers[currentCalibreServerId] else { return }
            
            server.lastLibrary = library.name
            do {
                try updateServerRealm(server: server)
            } catch {
                
            }
            
            UserDefaults.standard.set(currentCalibreLibraryId, forKey: Constants.KEY_DEFAULTS_SELECTED_LIBRARY_ID)
            
            calibreServerLibraryUpdating = true
            currentBookId = 0
            filteredBookList.removeAll()
            calibreServerLibraryBooks.removeAll()
            DispatchQueue(label: "data").async { [self] in
                let realm = try! Realm(configuration: realmConf)
                populateServerLibraryBooks(realm: realm)
                updateFilteredBookList()
                
                DispatchQueue.main.sync {
                    calibreServerLibraryUpdating = false
                    //currentBookId = self.filteredBookList.first ?? 0
                }
            }
        }
    }
    var currentCalibreLibrary: CalibreLibrary? {
        calibreLibraries[currentCalibreLibraryId]
    }
    var currentCalibreServerLibraries: [CalibreLibrary] {
        calibreLibraries.values.filter { $0.server.id == currentCalibreServerId }
    }
    
    @Published var calibreServerUpdating = false
    @Published var calibreServerUpdatingStatus: String? = nil
    
    @Published var calibreServerLibraryUpdating = false
    @Published var calibreServerLibraryUpdatingProgress = 0
    @Published var calibreServerLibraryUpdatingTotal = 0
    
    @Published var calibreServerLibraryBooks = [Int32: CalibreBook]()
    
    @Published var activeTab = 0
    var documentServer: CalibreServer?
    var localLibrary: CalibreLibrary?
    
    //for LibraryInfoView
    @Published var defaultFormat = Format.PDF
    var formatReaderMap = [Format: [ReaderType]]()
    
    @Published var searchString = "" {
        didSet {
            if searchString != oldValue {
                updateFilteredBookList()
            }
        }
    }
    @Published var filterCriteriaRating = Set<String>() {
        didSet {
            if filterCriteriaRating != oldValue {
                updateFilteredBookList()
            }
        }
    }
    
    @Published var filterCriteriaFormat = Set<String>() {
        didSet {
            if filterCriteriaFormat != oldValue {
                updateFilteredBookList()
            }
        }
    }
    @Published var filterCriteriaIdentifier = Set<String>() {
        didSet {
            if filterCriteriaIdentifier != oldValue {
                updateFilteredBookList()
            }
        }
    }
    @Published var filterCriteriaShelved = FilterCriteriaShelved.none {
        didSet {
            if filterCriteriaShelved != oldValue {
                updateFilteredBookList()
            }
        }
    }
    @Published var filterCriteriaSeries = Set<String>() {
        didSet {
            if filterCriteriaSeries != oldValue {
                updateFilteredBookList()
            }
        }
    }
    
    @Published var filteredBookList = [Int32]()
    
    @Published var booksInShelf = [String: CalibreBook]()
    
    var currentBookId: Int32 = -1 {
        didSet {
            self.selectedBookId = currentBookId
        }
    }

    @Published var selectedBookId: Int32? = nil {
        didSet {
            guard let selectedBookId = selectedBookId else { return }
            self.readingBook = self.calibreServerLibraryBooks[selectedBookId]
        }
    }
    
    @Published var selectedPosition = ""
    @Published var updatedReadingPosition = BookDeviceReadingPosition(id: UIDevice().name, readerName: "")
    
    var readingBookInShelfId: String? = nil {
        didSet {
            guard let readingBookInShelfId = readingBookInShelfId else {
                readingBook = nil
                return
            }
            guard readingBook?.inShelfId != readingBookInShelfId else { return }
            readingBook = booksInShelf[readingBookInShelfId]
            readerInfo = prepareBookReading(book: readingBook!)
        }
    }
    @Published var readingBook: CalibreBook? = nil {
        didSet {
            guard readingBook != nil else { return }
            
            if let position = getDeviceReadingPosition() {
                self.selectedPosition = position.id
            } else if let position = getLatestReadingPosition() {
                self.selectedPosition = position.id
            } else {
                self.selectedPosition = getInitialReadingPosition().id
            }
        }
    }
    
    @Published var readerInfo: ReaderInfo? = nil
    
    @Published var presentingEBookReaderFromShelf = false
    
    let readingBookReloadCover = PassthroughSubject<(), Never>()
    
    @Published var loadLibraryResult = "Waiting"
    
    var updatingMetadataTask: URLSessionDataTask?
    @Published var updatingMetadata = false {
        didSet {
            if updatingMetadata {
                updatingMetadataSucceed = false
                updatingMetadataStatus = "Updating"
            }
        }
    }
    @Published var updatingMetadataStatus = "" {
        didSet {
            if updatingMetadataStatus == "Success" || updatingMetadataStatus == "Deleted" {
                updatingMetadataSucceed = true
            }
        }
    }
    @Published var updatingMetadataSucceed = false
    
    private var defaultLog = Logger()
    
    private var realm: Realm!
    private var realmConf = Realm.Configuration(
        
        schemaVersion: 17,
        migrationBlock: { migration, oldSchemaVersion in
                if oldSchemaVersion < 9 {
                    // if you added a new property or removed a property you don't
                    // have to do anything because Realm automatically detects that
                    
                }
            }
    )
    
    let kfImageCache = ImageCache.default
    var authResponsor = AuthResponsor()
    
    init() {
        #if canImport(GoogleMobileAds)
        GADMobileAds.sharedInstance().start(completionHandler: nil)
        #endif
        
        if let applicationSupportURL = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
            realmConf.fileURL = applicationSupportURL.appendingPathComponent("default.realm")
            if let documentDirectoryURL = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
                let existingRealmURL = documentDirectoryURL.appendingPathComponent("default.realm")
                if FileManager.default.fileExists(atPath: existingRealmURL.path) {
                    try? FileManager.default.moveItem(at: existingRealmURL, to: realmConf.fileURL!)
                }
            }
        }
        
        realm = try! Realm(
            configuration: realmConf
        )
        
        kfImageCache.diskStorage.config.expiration = .never
        KingfisherManager.shared.defaultOptions = [.requestModifier(AuthPlugin(modelData: self))]
        ImageDownloader.default.authenticationChallengeResponder = authResponsor
        
        let serversCached = realm.objects(CalibreServerRealm.self).sorted(by: [SortDescriptor(keyPath: "username"), SortDescriptor(keyPath: "baseUrl")])
        serversCached.forEach { serverRealm in
            guard serverRealm.baseUrl != nil else { return }
            let calibreServer = CalibreServer(
                name: serverRealm.name ?? serverRealm.baseUrl!,
                baseUrl: serverRealm.baseUrl!,
                publicUrl: serverRealm.publicUrl ?? "",
                username: serverRealm.username ?? "",
                password: serverRealm.password ?? "",
                defaultLibrary: serverRealm.defaultLibrary ?? "",
                lastLibrary: serverRealm.lastLibrary ?? ""
            )
            calibreServers[calibreServer.id] = calibreServer
            
            if calibreServer.username.isEmpty == false && calibreServer.password.isEmpty == false {
                if let url = URL(string: calibreServer.baseUrl), let host = url.host, let port = url.port {
                    var authMethod = NSURLAuthenticationMethodDefault
                    if url.scheme == "http" {
                        authMethod = NSURLAuthenticationMethodHTTPDigest
                    }
                    if url.scheme == "https" {
                        authMethod = NSURLAuthenticationMethodHTTPBasic
                    }
                    let protectionSpace = URLProtectionSpace.init(host: host,
                                                                  port: port,
                                                                  protocol: url.scheme,
                                                                  realm: "calibre",
                                                                  authenticationMethod: authMethod)
                    let userCredential = URLCredential(user: calibreServer.username,
                                                       password: calibreServer.password,
                                                       persistence: .permanent)
                    URLCredentialStorage.shared.set(userCredential, for: protectionSpace)
                }
                if let url = URL(string: calibreServer.publicUrl), let host = url.host, let port = url.port {
                    var authMethod = NSURLAuthenticationMethodDefault
                    if url.scheme == "http" {
                        authMethod = NSURLAuthenticationMethodHTTPDigest
                    }
                    if url.scheme == "https" {
                        authMethod = NSURLAuthenticationMethodHTTPBasic
                    }
                    let protectionSpace = URLProtectionSpace.init(host: host,
                                                                  port: port,
                                                                  protocol: url.scheme,
                                                                  realm: "calibre",
                                                                  authenticationMethod: authMethod)
                    let userCredential = URLCredential(user: calibreServer.username,
                                                       password: calibreServer.password,
                                                       persistence: .permanent)
                    URLCredentialStorage.shared.set(userCredential, for: protectionSpace)
                }
            }
        }
        
        if let lastServerId = UserDefaults.standard.string(forKey: Constants.KEY_DEFAULTS_SELECTED_SERVER_ID), calibreServers[lastServerId] != nil {
            currentCalibreServerId = lastServerId
        }
        
        populateLibraries()
        
        if currentCalibreLibraryId.isEmpty == false {
            DispatchQueue(label: "data").async {
                let realm = try! Realm(configuration: self.realmConf)
                self.populateServerLibraryBooks(realm: realm)
            }
        }
        
        populateBookShelf()
        
        populateLocalLibraryBooks()
        
        switch UIDevice.current.userInterfaceIdiom {
            case .phone:
                defaultFormat = Format.EPUB
            case .pad:
                defaultFormat = Format.PDF
            default:
                defaultFormat = Format.EPUB
        }
        
        formatReaderMap[Format.EPUB] = [ReaderType.FolioReader, ReaderType.ReadiumEPUB]
        formatReaderMap[Format.PDF] = [ReaderType.YabrPDFView, ReaderType.ReadiumPDF]
        formatReaderMap[Format.CBZ] = [ReaderType.ReadiumCBZ]

    }
    
    func populateBookShelf() {
        let booksInShelfRealm = realm.objects(CalibreBookRealm.self).filter(
            NSPredicate(format: "inShelf = true")
        )
        
        booksInShelfRealm.forEach {
            // print(bookRealm)
            guard let server = calibreServers[CalibreServer(name: "", baseUrl: $0.serverUrl!, publicUrl: "", username: $0.serverUsername!, password: "").id] else {
                print("ERROR booksInShelfRealm missing server \($0)")
                return
            }
            guard let library = calibreLibraries[CalibreLibrary(server: server, key: "", name: $0.libraryName!).id] else {
                print("ERROR booksInShelfRealm missing library \($0)")
                return
            }
            let book = self.convert(library: library, bookRealm: $0)
            self.booksInShelf[book.inShelfId] = book
            
            print("booksInShelfRealm \(book.inShelfId)")
        }
    }
    
    func populateLibraries() {
        guard let currentCalibreServer = calibreServers[currentCalibreServerId]
                else { return }
        
        let librariesCached = realm.objects(CalibreLibraryRealm.self)

        librariesCached.forEach { libraryRealm in
            guard let calibreServer = calibreServers[CalibreServer(name: "", baseUrl: libraryRealm.serverUrl!, publicUrl: "", username: libraryRealm.serverUsername!, password: "").id] else {
                print("Unknown Server: \(libraryRealm)")
                return
            }
            let calibreLibrary = CalibreLibrary(server: calibreServer, key: libraryRealm.key ?? libraryRealm.name!, name: libraryRealm.name!, readPosColumnName: libraryRealm.readPosColumnName, goodreadsSyncProfileName: libraryRealm.goodreadsSyncProfileName)
            calibreLibraries[calibreLibrary.id] = calibreLibrary
        }
        
        if let lastCalibreLibrary = UserDefaults.standard.string(forKey: Constants.KEY_DEFAULTS_SELECTED_LIBRARY_ID), calibreLibraries[lastCalibreLibrary] != nil {
            currentCalibreLibraryId = lastCalibreLibrary
        } else {
            let defaultLibrary = CalibreLibrary(server: currentCalibreServer, key: currentCalibreServer.defaultLibrary, name: currentCalibreServer.defaultLibrary)
            currentCalibreLibraryId = defaultLibrary.id
        }
        
        print("populateLibraries \(calibreLibraries)")
    }
    
    /**
            Must not run on main thread
     */
    func populateServerLibraryBooks(realm: Realm) {
        guard let currentCalibreLibrary = calibreLibraries[currentCalibreLibraryId] else {
            return
        }
        
        let booksCached = realm.objects(CalibreBookRealm.self).filter(
            NSPredicate(format: "serverUrl = %@ AND serverUsername = %@ AND libraryName = %@",
                        currentCalibreLibrary.server.baseUrl,
                        currentCalibreLibrary.server.username,
                        currentCalibreLibrary.name
            )
        )
        let booksCount = booksCached.count
        DispatchQueue.main.sync {
            self.calibreServerLibraryUpdatingTotal = booksCount
            self.calibreServerLibraryUpdatingProgress = 0
        }
        
        var calibreServerLibraryBooks = [Int32: CalibreBook]()
        booksCached.forEach { bookRealm in
            calibreServerLibraryBooks[bookRealm.id] = self.convert(library: currentCalibreLibrary, bookRealm: bookRealm)
            DispatchQueue.main.async {
                self.calibreServerLibraryUpdatingProgress += 1
            }
        }
        
        DispatchQueue.main.sync {
            self.calibreServerLibraryBooks = calibreServerLibraryBooks
        }
    }
    
    func populateLocalLibraryBooks() {
        guard let documentDirectoryURL = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            return
        }
        
        let tmpServer = CalibreServer(name: "Document Folder", baseUrl: ".", publicUrl: "", username: "", password: "")
        documentServer = calibreServers[tmpServer.id]
        if documentServer == nil {
            calibreServers[tmpServer.id] = tmpServer
            documentServer = calibreServers[tmpServer.id]
            do {
                try updateServerRealm(server: documentServer!)
            } catch {
                
            }
            if calibreServers.count == 1 {
                currentCalibreServerId = documentServer!.id
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
            server: documentServer!,
            key: localLibraryURL.lastPathComponent,
            name: localLibraryURL.lastPathComponent)
        localLibrary = calibreLibraries[tmpLibrary.id]
        if localLibrary == nil {
            calibreLibraries[tmpLibrary.id] = tmpLibrary
            localLibrary = calibreLibraries[tmpLibrary.id]
            do {
                try updateLibraryRealm(library: localLibrary!)
            } catch {
                
            }
            if calibreLibraries.count == 1 {
                currentCalibreLibraryId = localLibrary!
                    .id
            }
        }
        
        guard let dirEnum = FileManager.default.enumerator(atPath: localLibraryURL.path) else {
            return
        }
        
        dirEnum.forEach {
            guard let fileName = $0 as? String else {
                return
            }
            
            loadLocalLibraryBookMetadata(fileName: fileName, in: localLibrary!, on: documentServer!)
        }
        
        let removedBooks: [CalibreBook] = booksInShelf.compactMap { inShelfId, book in
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
            self.removeFromShelf(inShelfId: $0.inShelfId)
            self.removeFromRealm(book: $0)
            print("populateLocalLibraryBooks removeFromShelf \($0)")
        }
        

    }
    
    func updateFilteredBookList() {
        let filteredBookList = calibreServerLibraryBooks.values.filter { [self] (book) -> Bool in
            if !(searchString.isEmpty || book.title.contains(searchString) || book.authors.reduce(into: false, { result, author in
                result = result || author.contains(searchString)
            })) {
                return false
            }
            if !(filterCriteriaRating.isEmpty || filterCriteriaRating.contains(book.ratingDescription)) {
                return false
            }
            if !filterCriteriaFormat.isEmpty && filterCriteriaFormat.intersection(book.formats.compactMap { $0.key }).isEmpty {
                return false
            }
            if !filterCriteriaIdentifier.isEmpty && filterCriteriaIdentifier.intersection(book.identifiers.compactMap { $0.key }).isEmpty {
                return false
            }
            if !filterCriteriaSeries.isEmpty && filterCriteriaSeries.contains(book.seriesDescription) == false {
                return false
            }
            switch filterCriteriaShelved {
            case .shelvedOnly:
                if book.inShelf == false {
                    return false
                }
                break
            case .notShelvedOnly:
                if book.inShelf == true {
                    return false
                }
                break
            case .none:
                break
            }
            return true
        }.sorted { (lhs, rhs) -> Bool in
            lhs.title < rhs.title
        }.map({ $0.id })
        if !Thread.isMainThread {
            DispatchQueue.main.sync {
                self.filteredBookList = filteredBookList
            }
        } else {
            self.filteredBookList = filteredBookList
        }
        print("updateFilteredBookList finished count=\(self.filteredBookList.count)")
    }
    
    func convert(library: CalibreLibrary, bookRealm: CalibreBookRealm) -> CalibreBook {
        var calibreBook = CalibreBook(
            id: bookRealm.id,
            library: library,
            title: bookRealm.title,
            comments: bookRealm.comments,
            publisher: bookRealm.publisher,
            series: bookRealm.series,
            rating: bookRealm.rating,
            size: bookRealm.size,
            pubDate: bookRealm.pubDate,
            timestamp: bookRealm.timestamp,
            lastModified: bookRealm.lastModified,
            formats: bookRealm.formats(),
            readPos: bookRealm.readPos(),
            inShelf: bookRealm.inShelf,
            inShelfName: bookRealm.inShelfName)
        if bookRealm.identifiersData != nil {
            calibreBook.identifiers = bookRealm.identifiers()
        }
        calibreBook.authors.append(contentsOf: bookRealm.authors)
        calibreBook.tags.append(contentsOf: bookRealm.tags)
        return calibreBook
    }
    
    func updateStoreReadingPosition(enabled: Bool, value: String) {
        calibreLibraries[currentCalibreLibraryId]!.readPosColumnName = enabled ? value : nil
        do {
            try updateLibraryRealm(library: calibreLibraries[currentCalibreLibraryId]!)
        } catch {
            
        }
    }
    
    func updateGoodreadsSyncProfileName(enabled: Bool, value: String) {
        calibreLibraries[currentCalibreLibraryId]!.goodreadsSyncProfileName = enabled ? value : nil
        do {
            try updateLibraryRealm(library: calibreLibraries[currentCalibreLibraryId]!)
        } catch {
            
        }
    }
    
    func updateCustomDictViewer(enabled: Bool, value: String) {
        //TODO
    }
    
    func addServer(server: CalibreServer, libraries: [CalibreLibrary]) {
        calibreServers[server.id] = server
        do {
            try updateServerRealm(server: server)
        } catch {
            
        }
        
        libraries.forEach { (library) in
            calibreLibraries[library.id] = library
            do {
                try updateLibraryRealm(library: library)
            } catch {
            
            }
        }
    }
    
    func updateServerRealm(server: CalibreServer) throws {
        let serverRealm = CalibreServerRealm()
        serverRealm.name = server.name
        serverRealm.baseUrl = server.baseUrl
        serverRealm.publicUrl = server.publicUrl
        serverRealm.username = server.username
        serverRealm.password = server.password
        serverRealm.defaultLibrary = server.defaultLibrary
        serverRealm.lastLibrary = server.lastLibrary
        try realm.write {
            realm.add(serverRealm, update: .all)
        }
    }
    
    func updateLibraryRealm(library: CalibreLibrary) throws {
        let libraryRealm = CalibreLibraryRealm()
        libraryRealm.key = library.key
        libraryRealm.name = library.name
        libraryRealm.serverUrl = library.server.baseUrl
        libraryRealm.serverUsername = library.server.username
        libraryRealm.readPosColumnName = library.readPosColumnName
        libraryRealm.goodreadsSyncProfileName = library.goodreadsSyncProfileName
        try realm.write {
            realm.add(libraryRealm, update: .all)
        }
    }
    
    func updateBook(book: CalibreBook) {
        updateBookRealm(book: book, realm: realm)
        if currentCalibreLibraryId == book.library.id {
            calibreServerLibraryBooks[book.id] = book
        }
        if readingBook?.inShelfId == book.inShelfId {
            readingBook = book
        }
        if book.inShelf {
            booksInShelf[book.inShelfId] = book
        }
    }
    
    func updateBookRealm(book: CalibreBook, realm: Realm) {
        let bookRealm = CalibreBookRealm()
        bookRealm.id = book.id
        bookRealm.serverUrl = book.library.server.baseUrl
        bookRealm.serverUsername = book.library.server.username
        bookRealm.libraryName = book.library.name
        bookRealm.title = book.title
        bookRealm.authors.append(objectsIn: book.authors)
        bookRealm.comments = book.comments
        bookRealm.publisher = book.publisher
        bookRealm.series = book.series
        bookRealm.rating = book.rating
        bookRealm.size = book.size
        bookRealm.pubDate = book.pubDate
        bookRealm.timestamp = book.timestamp
        bookRealm.lastModified = book.lastModified
        bookRealm.tags.append(objectsIn: book.tags)
        bookRealm.inShelf = book.inShelf
        bookRealm.inShelfName = book.inShelfName
        
        bookRealm.formatsData = try! JSONSerialization.data(withJSONObject: book.formats, options: []) as NSData
        
        bookRealm.identifiersData = try! JSONSerialization.data(withJSONObject: book.identifiers, options: []) as NSData
        
        let deviceMapSerialize = book.readPos.getCopy().compactMapValues { (value) -> Any? in
            try? JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
        }
        bookRealm.readPosData = try! JSONSerialization.data(withJSONObject: ["deviceMap": deviceMapSerialize], options: []) as NSData
        
        try! realm.write {
            realm.add(bookRealm, update: .modified)
        }
    }
    
    func removeFromRealm(book: CalibreBook) {
        let bookRealm = CalibreBookRealm()
        bookRealm.id = book.id
        bookRealm.serverUrl = book.library.server.baseUrl
        bookRealm.serverUsername = book.library.server.username
        bookRealm.libraryName = book.library.name
        
        let objects = realm.objects(CalibreBookRealm.self).filter( "primaryKey = '\(bookRealm.primaryKey!)'" )
        
        try! realm.write {
            realm.delete(objects)
        }
    }
    
    
    /// update server library infos,
    /// make sure libraries' server ids equal to serverId
    /// - Parameters:
    ///   - serverId: id of target server
    ///   - libraries: library list
    ///   - defaultLibrary: key of default library
    /// - TODO: update & remove
    func updateServerLibraryInfo(serverId: String, libraries: [CalibreLibrary], defaultLibrary: String) {
        guard let server = calibreServers[serverId] else { return }
        
        libraries.filter { $0.server.id == server.id }
            .forEach { newLibrary in
                let libraryId = newLibrary.id
            
                if calibreLibraries[libraryId] == nil {
                    let library = CalibreLibrary(server: server, key: newLibrary.key, name: newLibrary.name)
                    calibreLibraries[libraryId] = library
                    do {
                        try updateLibraryRealm(library: library)
                    } catch {
                        
                    }
                }
        }
        
        if server.defaultLibrary != defaultLibrary {
            calibreServers[serverId]!.defaultLibrary = defaultLibrary
            do {
                try updateServerRealm(server: calibreServers[serverId]!)
            } catch {
                
            }
        }
    }
    
    //TODO merge with ServerView's handleLibraryInfo
//    func handleLibraryInfo(jsonData: Data) {
//        do {
//            let libraryInfo = try JSONSerialization.jsonObject(with: jsonData, options: []) as! NSDictionary
//            defaultLog.info("libraryInfo: \(libraryInfo)")
//
//            let libraryMap = libraryInfo["library_map"] as! [String: String]
//            libraryMap.forEach { (key, value) in
//                let library = CalibreLibrary(server: calibreServers[currentCalibreServerId]!, key: key, name: value)
//                if calibreLibraries[library.id] == nil {
//                    calibreLibraries[library.id] = library
//
//                    updateLibraryRealm(library: library)
//                }
//            }
//            if let defaultLibrary = libraryInfo["default_library"] as? String {
//                if calibreServers[currentCalibreServerId]!.defaultLibrary != defaultLibrary {
//                    calibreServers[currentCalibreServerId]!.defaultLibrary = defaultLibrary
//
//                    updateServerRealm(server: calibreServers[currentCalibreServerId]!)
//                }
//            }
//        } catch {
//
//        }
//
//    }
    
    /**
     run on background threads, call completionHandler on main thread
     */
    func handleLibraryBooks(json: Data, completionHandler: @escaping (Bool) -> Void) {
        let library = calibreLibraries[currentCalibreLibraryId]!
        
        DispatchQueue.main.async {
            self.calibreServerLibraryUpdating = true
            self.calibreServerLibraryUpdatingTotal = 0
            self.calibreServerLibraryUpdatingProgress = 0
        }
        
        guard let root = try? JSONSerialization.jsonObject(with: json, options: []) as? NSDictionary else {
            DispatchQueue.main.async {
                self.calibreServerLibraryUpdating = false
            }
            completionHandler(false)
            return
        }
        
        var calibreServerLibraryBooks = self.calibreServerLibraryBooks
        
        let resultElement = root["result"] as! NSDictionary
        let bookIds = resultElement["book_ids"] as! NSArray
        
        bookIds.forEach { idNum in
            let id = (idNum as! NSNumber).int32Value
            if calibreServerLibraryBooks[id] == nil {
                calibreServerLibraryBooks[id] = CalibreBook(id: id, library: library)
            }
        }
        
        let bookCount = calibreServerLibraryBooks.count
        DispatchQueue.main.async {
            self.calibreServerLibraryUpdatingTotal = bookCount
        }
        
        let dataElement = resultElement["data"] as! NSDictionary
        
        let titles = dataElement["title"] as! NSDictionary
        titles.forEach { (key, value) in
            let id = (key as! NSString).intValue
            let title = value as! String
            calibreServerLibraryBooks[id]!.title = title
        }
        
        let authors = dataElement["authors"] as! NSDictionary
        authors.forEach { (key, value) in
            let id = (key as! NSString).intValue
            let authors = value as! NSArray
            calibreServerLibraryBooks[id]!.authors = authors.compactMap({ (author) -> String? in
                author as? String
            })
        }
        
        let formats = dataElement["formats"] as! NSDictionary
        formats.forEach { (key, value) in
            let id = (key as! NSString).intValue
            let formats = value as! NSArray
            formats.forEach { format in
                calibreServerLibraryBooks[id]!.formats[(format as! String)] = ""
            }
        }
        
        if let identifiers = dataElement["identifiers"] as? NSDictionary {
            identifiers.forEach { (key, value) in
                let id = (key as! NSString).intValue
                if let idDict = value as? NSDictionary {
                    calibreServerLibraryBooks[id]!.identifiers = idDict as! [String: String]
                }
            }
        }
        
        let ratings = dataElement["rating"] as! NSDictionary
        ratings.forEach { (key, value) in
            let id = (key as! NSString).intValue
            if let rating = value as? NSNumber {
                calibreServerLibraryBooks[id]!.rating = rating.intValue
            }
        }
        
        let series = dataElement["series"] as! NSDictionary
        series.forEach { (key, value) in
            let id = (key as! NSString).intValue
            if let series = value as? String {
                calibreServerLibraryBooks[id]!.series = series
            } else {
                calibreServerLibraryBooks[id]!.series = ""
            }
        }
        
        let realm = try! Realm(configuration: self.realmConf)
        calibreServerLibraryBooks.values.forEach { (book) in
            updateBookRealm(book: book, realm: realm)
            DispatchQueue.main.async {
                self.calibreServerLibraryUpdatingProgress += 1
            }
        }
        
        DispatchQueue.main.async {
            self.calibreServerLibraryBooks = calibreServerLibraryBooks
            self.updateFilteredBookList()
            
            self.calibreServerLibraryUpdating = false
            completionHandler(true)
        }
        
    }
    
    func handleLibraryBookOne(oldbook: CalibreBook, json: Data) -> CalibreBook? {
        guard let root = try? JSONSerialization.jsonObject(with: json, options: []) as? NSDictionary,
              let resultElement = root["result"] as? NSDictionary,
              let bookIds = resultElement["book_ids"] as? NSArray,
              let dataElement = resultElement["data"] as? NSDictionary,
              let bookId = bookIds.firstObject as? NSNumber else {
            updatingMetadataStatus = "Failed to Parse Calibre Server Response."
            updatingMetadata = false
            return nil
        }
        
        let bookIdKey = bookId.stringValue
        var book = oldbook
        if let d = dataElement["title"] as? NSDictionary, let v = d[bookIdKey] as? String {
            book.title = v
        }
        if let d = dataElement["publisher"] as? NSDictionary, let v = d[bookIdKey] as? String {
            book.publisher = v
        }
        if let d = dataElement["series"] as? NSDictionary, let v = d[bookIdKey] as? String {
            book.series = v
        }
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = .withInternetDateTime
        if let d = dataElement["pubdate"] as? NSDictionary, let v = d[bookIdKey] as? NSDictionary, let t = v["v"] as? String, let date = dateFormatter.date(from: t) {
            book.pubDate = date
        }
        if let d = dataElement["last_modified"] as? NSDictionary, let v = d[bookIdKey] as? NSDictionary, let t = v["v"] as? String, let date = dateFormatter.date(from: t) {
            book.lastModified = date
        }
        if let d = dataElement["timestamp"] as? NSDictionary, let v = d[bookIdKey] as? NSDictionary, let t = v["v"] as? String, let date = dateFormatter.date(from: t) {
            book.timestamp = date
        }
        
        if let d = dataElement["tags"] as? NSDictionary, let v = d[bookIdKey] as? NSArray {
            book.tags = v.compactMap { (t) -> String? in
                t as? String
            }
        }
        if let d = dataElement["size"] as? NSDictionary, let v = d[bookIdKey] as? NSNumber {
            book.size = v.intValue
        }
        
        if let d = dataElement["rating"] as? NSDictionary, let v = d[bookIdKey] as? NSNumber {
            book.rating = v.intValue
        }
        
        if let d = dataElement["authors"] as? NSDictionary, let v = d[bookIdKey] as? NSArray {
            book.authors = v.compactMap { (t) -> String? in
                if let t = t as? String {
                    return t
                } else {
                    return nil
                }
            }
        }

        if let d = dataElement["identifiers"] as? NSDictionary, let v = d[bookIdKey] as? NSDictionary {
            if let ids = v as? [String: String] {
                book.identifiers = ids
            }
        }
        
        let comments = dataElement["comments"] as! NSDictionary
        comments.forEach { (key, value) in
            book.comments = value as? String ?? "Without Comments"
        }
        
        do {
            guard let readPosColumnName = calibreLibraries[oldbook.library.id]?.readPosColumnName else {
                return book
            }
            guard let readPosDict = dataElement[readPosColumnName] as? NSDictionary else {
                return book
            }
            try readPosDict.forEach { (key, value) in
                if( value is NSString ) {
                    let readPosString = value as! NSString
                    let readPosObject = try JSONSerialization.jsonObject(with: Data(base64Encoded: readPosString as String)!, options: [])
                    let readPosDict = readPosObject as! NSDictionary
                    defaultLog.info("readPosDict \(readPosDict)")
                    
                    let deviceMapObject = readPosDict["deviceMap"]
                    let deviceMapDict = deviceMapObject as! NSDictionary
                    deviceMapDict.forEach { key, value in
                        let deviceName = key as! String
                        if deviceName == self.deviceName && getDeviceReadingPosition() != nil {
                            //ignore server, trust local record
                            return
                        }
                        
                        let deviceReadingPositionDict = value as! [String: Any]
                        //TODO merge
                        var deviceReadingPosition = BookDeviceReadingPosition(id: deviceName, readerName: deviceReadingPositionDict["readerName"] as! String)
                        
                        deviceReadingPosition.lastReadPage = deviceReadingPositionDict["lastReadPage"] as! Int
                        deviceReadingPosition.lastReadChapter = deviceReadingPositionDict["lastReadChapter"] as! String
                        deviceReadingPosition.lastChapterProgress = deviceReadingPositionDict["lastChapterProgress"] as? Double ?? 0.0
                        deviceReadingPosition.lastProgress = deviceReadingPositionDict["lastProgress"] as? Double ?? 0.0
                        deviceReadingPosition.furthestReadPage = deviceReadingPositionDict["furthestReadPage"] as! Int
                        deviceReadingPosition.furthestReadChapter = deviceReadingPositionDict["furthestReadChapter"] as! String
                        deviceReadingPosition.maxPage = deviceReadingPositionDict["maxPage"] as! Int
                        if let lastPosition = deviceReadingPositionDict["lastPosition"] {
                            deviceReadingPosition.lastPosition = lastPosition as! [Int]
                        }
                        book.readPos.updatePosition(deviceName, deviceReadingPosition)
                        
                        defaultLog.info("book.readPos.getDevices().count \(book.readPos.getDevices().count)")
                    }
                }
            }
        } catch {
            defaultLog.warning("handleLibraryBooks: \(error.localizedDescription)")
        }
        return book
    }
    
    func handleLibraryBookOneNew(oldbook: CalibreBook, json: Data) -> CalibreBook? {
        guard let root = try? JSONSerialization.jsonObject(with: json, options: []) as? NSDictionary else {
            updatingMetadataStatus = "Failed to Parse Calibre Server Response."
            updatingMetadata = false
            return nil
        }
        
        var book = oldbook
        if let v = root["title"] as? String {
            book.title = v
        }
        if let v = root["publisher"] as? String {
            book.publisher = v
        }
        if let v = root["series"] as? String {
            book.series = v
        }
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = .withInternetDateTime
        if let v = root["pubdate"] as? String, let date = dateFormatter.date(from: v) {
            book.pubDate = date
        }
        if let v = root["last_modified"] as? String, let date = dateFormatter.date(from: v) {
            book.lastModified = date
        }
        if let v = root["timestamp"] as? String, let date = dateFormatter.date(from: v) {
            book.timestamp = date
        }
        
        if let v = root["tags"] as? NSArray {
            book.tags = v.compactMap { (t) -> String? in
                t as? String
            }
        }
        
        if let v = root["format_metadata"] as? NSDictionary {
            book.formats = v.reduce(into: [String: String]()) { result, format in
                if let fKey = format.key as? String, let fVal = format.value as? NSDictionary, let fValData = try? JSONSerialization.data(withJSONObject: fVal, options: []) {
                    result[fKey.uppercased()] = fValData.base64EncodedString()
                }
            }
        }
        
        book.size = 0   //parse later
        
        if let v = root["rating"] as? NSNumber {
            book.rating = v.intValue * 2
        }
        
        if let v = root["authors"] as? NSArray {
            book.authors = v.compactMap { (t) -> String? in
                t as? String
            }
        }

        if let v = root["identifiers"] as? NSDictionary {
            if let ids = v as? [String: String] {
                book.identifiers = ids
            }
        }
        
        if let v = root["comments"] as? String {
            book.comments = v
        }
        
        
        //Parse Reading Position
        if let readPosColumnName = calibreLibraries[oldbook.library.id]?.readPosColumnName,
              let userMetadata = root["user_metadata"] as? NSDictionary,
              let userMetadataReadPosDict = userMetadata[readPosColumnName] as? NSDictionary,
              let readPosString = userMetadataReadPosDict["#value#"] as? String,
              let readPosData = Data(base64Encoded: readPosString),
              let readPosDict = try? JSONSerialization.jsonObject(with: readPosData, options: []) as? NSDictionary,
              let deviceMapDict = readPosDict["deviceMap"] as? NSDictionary {
            deviceMapDict.forEach { key, value in
                let deviceName = key as! String
                
                if deviceName == self.deviceName && getDeviceReadingPosition() != nil {
                    //ignore server, trust local record
                    return
                }
                
                let deviceReadingPositionDict = value as! [String: Any]
                //TODO merge
                var deviceReadingPosition = BookDeviceReadingPosition(id: deviceName, readerName: deviceReadingPositionDict["readerName"] as! String)
                
                deviceReadingPosition.lastReadPage = deviceReadingPositionDict["lastReadPage"] as! Int
                deviceReadingPosition.lastReadChapter = deviceReadingPositionDict["lastReadChapter"] as! String
                deviceReadingPosition.lastChapterProgress = deviceReadingPositionDict["lastProgress"] as? Double ?? 0.0
                deviceReadingPosition.lastProgress = deviceReadingPositionDict["lastProgress"] as? Double ?? 0.0
                deviceReadingPosition.furthestReadPage = deviceReadingPositionDict["furthestReadPage"] as! Int
                deviceReadingPosition.furthestReadChapter = deviceReadingPositionDict["furthestReadChapter"] as! String
                deviceReadingPosition.maxPage = deviceReadingPositionDict["maxPage"] as! Int
                if let lastPosition = deviceReadingPositionDict["lastPosition"] {
                    deviceReadingPosition.lastPosition = lastPosition as! [Int]
                }
                book.readPos.updatePosition(deviceName, deviceReadingPosition)
                
                defaultLog.info("book.readPos.getDevices().count \(book.readPos.getDevices().count)")
            }
        }
                
        return book
    }
    
    func addToShelf(_ bookId: Int32, shelfName: String) {
        guard var book = calibreServerLibraryBooks[bookId] else {
            return
        }
        
        book.inShelfName = shelfName
        book.inShelf = true
        book.timestamp = Date()
        
        calibreServerLibraryBooks[bookId] = book
        
        if readingBook?.id == bookId {
            readingBook = book
        }
        
        updateBookRealm(book: book, realm: self.realm)
        booksInShelf[book.inShelfId] = book
        
        if let goodreadsId = book.identifiers["goodreads"], let goodreadsSyncProfileName = book.library.goodreadsSyncProfileName, goodreadsSyncProfileName.isEmpty == false {
            let connector = GoodreadsSyncConnector(server: book.library.server, profileName: goodreadsSyncProfileName)
            let ret = connector.addToShelf(goodreads_id: goodreadsId, shelfName: "currently-reading")
        }
    }
    
    func removeFromShelf(inShelfId: String) {
        if readingBook?.inShelfId == inShelfId {
            readingBook?.inShelf = false
        }
        booksInShelf[inShelfId]!.inShelf = false
        
        let book = booksInShelf[inShelfId]!
        updateBookRealm(book: book, realm: self.realm)
        if book.library.id == currentCalibreLibraryId {
            calibreServerLibraryBooks[book.id]!.inShelf = false
        }
        booksInShelf.removeValue(forKey: inShelfId)
        
        if let book = readingBook, let library = calibreLibraries[book.library.id], let goodreadsId = book.identifiers["goodreads"], let goodreadsSyncProfileName = library.goodreadsSyncProfileName, goodreadsSyncProfileName.count > 0 {
            let connector = GoodreadsSyncConnector(server: library.server, profileName: goodreadsSyncProfileName)
            let ret = connector.removeFromShelf(goodreads_id: goodreadsId, shelfName: "currently-reading")
            
            if let position = getDeviceReadingPosition(), position.lastProgress > 99 {
                connector.addToShelf(goodreads_id: goodreadsId, shelfName: "read")
            }
        }
    }
    
    func downloadFormat(book: CalibreBook, format: Format, modificationDate: Date? = nil, overwrite: Bool = false, complete: @escaping (Bool) -> Void) -> Bool {
        guard book.formats.contains(where: { $0.key == format.rawValue }) else {
            complete(false)
            return false
        }
        
        guard let url = URL(string: book.library.server.serverUrl)?
                .appendingPathComponent("get", isDirectory: true)
                .appendingPathComponent(format.rawValue, isDirectory: true)
                .appendingPathComponent(book.id.description, isDirectory: true)
                .appendingPathComponent(book.library.key, isDirectory: false)
                else {
            complete(false)
            return false
        }

        defaultLog.info("downloadURL: \(url.absoluteString)")
        
        guard let savedURL = getSavedUrl(book: book, format: format) else {
            complete(false)
            return false
        }
        
        self.defaultLog.info("savedURL: \(savedURL.absoluteString)")
        
        if FileManager.default.fileExists(atPath: savedURL.path) && !overwrite {
            complete(true)
            return false
        }
        
        let downloadTask = URLSession.shared.downloadTask(with: url) {
            urlOrNil, responseOrNil, errorOrNil in
            // check for and handle errors:
            // * errorOrNil should be nil
            // * responseOrNil should be an HTTPURLResponse with statusCode in 200..<299
            guard errorOrNil == nil else {
                
                complete(false)
                return
            }
            guard let fileURL = urlOrNil else { complete(false); return }
            do {
                self.defaultLog.info("fileURL: \(fileURL.absoluteString)")
                
                if FileManager.default.fileExists(atPath: savedURL.path) {
                    try FileManager.default.removeItem(at: savedURL)
                }
                try FileManager.default.moveItem(at: fileURL, to: savedURL)
                if let modificationDate = modificationDate {
                    let attributes = [FileAttributeKey.modificationDate: modificationDate]
                    try FileManager.default.setAttributes(attributes, ofItemAtPath: savedURL.path)
                }
                
                let isFileExist = FileManager.default.fileExists(atPath: savedURL.path)
                self.defaultLog.info("isFileExist: \(isFileExist)")
                
                complete(isFileExist)
            } catch {
                print ("file error: \(error)")
                complete(false)
            }
        }
        downloadTask.resume()
        return true
    }
    
    func startBatchDownload(bookIds: [Int32], formats: [String]) {
        
    }
    
    func clearCache(inShelfId: String, _ format: Format) {
        guard let book = booksInShelf[inShelfId] else {
            return
        }
        
        clearCache(book: book,  format: format)
        
    }
    
    func clearCache(book: CalibreBook, format: Format) {
        guard let bookFileURL = getSavedUrl(book: book, format: format) else { return }
        
        if FileManager.default.fileExists(atPath: bookFileURL.path) {
            do {
                try FileManager.default.removeItem(at: bookFileURL)
            } catch {
                defaultLog.error("clearCache \(error.localizedDescription)")
            }
        }
    }
    
    func getCacheInfo(book: CalibreBook, format: Format) -> (UInt64, Date?)? {
        var resultStorage: ObjCBool = false
        guard let bookFileURL = getSavedUrl(book: book, format: format) else {
            return nil
        }
        
        if FileManager.default.fileExists(atPath: bookFileURL.path, isDirectory: &resultStorage),
           resultStorage.boolValue == false,
           let attribs = try? FileManager.default.attributesOfItem(atPath: bookFileURL.path) as NSDictionary {
            return (attribs.fileSize(), attribs.fileModificationDate())
        }
        
        return nil
    }
    
    func onOpenURL(url: URL) {
        guard let localBaseUrl = documentServer?.localBaseUrl else { return }
        
        if url.isFileURL && !url.isAppFile {
            guard url.startAccessingSecurityScopedResource() else {
                print("onOpenURL url.startAccessingSecurityScopedResource() -> false")
                return
            }

            do {
                try FileManager.default.copyItem(at: url, to: localBaseUrl.appendingPathComponent("Local Library", isDirectory: true).appendingPathComponent(url.lastPathComponent, isDirectory: false))
                
                loadLocalLibraryBookMetadata(fileName: url.lastPathComponent, in: localLibrary!, on: documentServer!)
            } catch {
                print("onOpenURL \(error)")
            }
            
            url.stopAccessingSecurityScopedResource()
        }
        if url.isHTTP {
            
        }
    }
    
    func loadLocalLibraryBookMetadata(fileName: String, in library: CalibreLibrary, on server: CalibreServer) {
        Format.allCases.forEach { format in
            guard fileName.hasSuffix(".\(format.ext)") else {
                return
            }
            
            let fileURL = server.localBaseUrl!.appendingPathComponent(library.key, isDirectory: true).appendingPathComponent(fileName, isDirectory: false)
            guard let md5 = fileName.data(using: .utf8)?.md5() else {
                return
            }
            let bookId = Int32(bigEndian: md5.prefix(4).withUnsafeBytes{$0.load(as: Int32.self)})
            
            var book = CalibreBook(
                id: bookId,
                library: library
            )
            
            guard booksInShelf[book.inShelfId] == nil else {
                return  //already loaded
            }
            let streamer = Streamer()
            streamer.open(asset: FileAsset(url: fileURL), allowUserInteraction: false) { result in
                guard let publication = try? result.get() else {
                    print("Streamer \(fileURL)")
                    return
                }
                
                var formatVal: [String: Any] = [:]
                formatVal["filename"] = fileName
                
                guard let formatData = try? JSONSerialization.data(withJSONObject: formatVal, options: []).base64EncodedString() else {
                    return
                }
                book.formats[format.rawValue] = formatData
                
                book.inShelf = true
                
                book.title = publication.metadata.title
                if let cover = publication.cover, let coverData = cover.pngData(), let coverUrl = book.coverURL {
                    self.kfImageCache.storeToDisk(coverData, forKey: coverUrl.absoluteString)
                }
                
                
                book.readPos.addInitialPosition(
                    self.deviceName,
                    self.formatReaderMap[format]!.first!.rawValue
                )
                
                self.booksInShelf[book.inShelfId] = book
                
                self.updateBook(book: book)
            }
                
        }
    }
    
    func deleteLocalLibraryBook(book: CalibreBook, format: Format) {
        guard let bookFileUrl = getSavedUrl(book: book, format: format) else { return }
        do {
            try FileManager.default.removeItem(at: bookFileUrl)
        } catch {
            print(error)
        }
    }
    
    func getSelectedReadingPosition() -> BookDeviceReadingPosition? {
        return readingBook!.readPos.getPosition(selectedPosition)
    }
    
    func getDeviceReadingPosition() -> BookDeviceReadingPosition? {
        return readingBook!.readPos.getPosition(deviceName)
    }
    
    func getInitialReadingPosition() -> BookDeviceReadingPosition {
        return BookDeviceReadingPosition(id: deviceName, readerName: "YABR")
    }
    
    func getLatestReadingPosition() -> BookDeviceReadingPosition? {
        return readingBook!.readPos.getDevices().first
    }
    
    func getLatestReadingPosition(by reader: ReaderType) -> BookDeviceReadingPosition? {
        return readingBook!.readPos.getDevices().first
    }
    
    func updateCurrentPosition(alertDelegate: AlertDelegate) {
        guard var readingBook = self.readingBook else {
            return
        }
        do {
            defaultLog.info("pageNumber:  \(self.updatedReadingPosition.lastPosition[0])")
            defaultLog.info("pageOffsetX: \(self.updatedReadingPosition.lastPosition[1])")
            defaultLog.info("pageOffsetY: \(self.updatedReadingPosition.lastPosition[2])")
            
            readingBook.readPos.updatePosition(deviceName, updatedReadingPosition)
            
            self.updateBook(book: readingBook)
            
            guard let readPosColumnName = calibreLibraries[readingBook.library.id]?.readPosColumnName else {
                return
            }
            
            var deviceMapSerialize = [String: Any]()
            try readingBook.readPos.getCopy().forEach { key, value in
                deviceMapSerialize[key] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
            }
            
            let readPosData = try JSONSerialization.data(withJSONObject: ["deviceMap": deviceMapSerialize], options: []).base64EncodedString()
            
            let endpointUrl = URL(string: readingBook.library.server.serverUrl + "/cdb/cmd/set_metadata/0?library_id=" + readingBook.library.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)!
            let json:[Any] = ["fields", readingBook.id, [[readPosColumnName, readPosData]]]
            
            let data = try JSONSerialization.data(withJSONObject: json, options: [])
            defaultLog.warning("JSON: \(String(data: data, encoding: .utf8)!)")
            
            var request = URLRequest(url: endpointUrl)
            request.httpMethod = "POST"
            request.httpBody = data
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("application/json", forHTTPHeaderField: "Accept")
            
            if updatingMetadata && updatingMetadataTask != nil {
                updatingMetadataTask!.cancel()
            }
            updatingMetadataTask = URLSession.shared.dataTask(with: request) { [self] data, response, error in
                let emptyData = "".data(using: .utf8) ?? Data()
                if let error = error {
                    // self.handleClientError(error)
                    defaultLog.warning("error: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        updatingMetadataStatus = error.localizedDescription
                        updatingMetadata = false
                        alertDelegate.alert(msg: updatingMetadataStatus)
                    }
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse else {
                    defaultLog.warning("not httpResponse: \(response.debugDescription)")
                    DispatchQueue.main.async {
                        updatingMetadataStatus = String(data: data ?? emptyData, encoding: .utf8) ?? "" + response.debugDescription
                        updatingMetadata = false
                        alertDelegate.alert(msg: updatingMetadataStatus)
                    }
                    return
                }
                if !(200...299).contains(httpResponse.statusCode) {
                    defaultLog.warning("statusCode not 2xx: \(httpResponse.debugDescription)")
                    DispatchQueue.main.async {
                        updatingMetadataStatus = String(data: data ?? emptyData, encoding: .utf8) ?? "" + httpResponse.debugDescription
                        updatingMetadata = false
                        alertDelegate.alert(msg: updatingMetadataStatus)
                    }
                    return
                }
                
                guard let mimeType = httpResponse.mimeType, mimeType == "application/json",
                      let data = data else {
                    DispatchQueue.main.async {
                        updatingMetadataStatus = String(data: data ?? emptyData, encoding: .utf8) ?? "" + httpResponse.debugDescription
                        updatingMetadata = false
                        alertDelegate.alert(msg: updatingMetadataStatus)
                    }
                    return
                }
                
                guard let root = try? JSONSerialization.jsonObject(with: data, options: []) as? NSDictionary else {
                    DispatchQueue.main.async {
                        updatingMetadataStatus = String(data: data ?? emptyData, encoding: .utf8) ?? "" + httpResponse.debugDescription
                        updatingMetadata = false
                        alertDelegate.alert(msg: updatingMetadataStatus)
                    }
                    return
                }
                
                guard let result = root["result"] as? NSDictionary, let resultv = result["v"] as? NSDictionary else {
                    DispatchQueue.main.async {
                        updatingMetadataStatus = String(data: data ?? emptyData, encoding: .utf8) ?? "" + httpResponse.debugDescription
                        updatingMetadata = false
                        alertDelegate.alert(msg: updatingMetadataStatus)
                    }
                    return
                }
                    
                DispatchQueue.main.async {
                    //self.webView.loadHTMLString(string, baseURL: url)
                    //result = string
                    //defaultLog.warning("httpResponse: \(string)")
                    
                    print("updateCurrentPosition result=\(result)")
                    
                    if let lastModifiedDict = resultv["last_modified"] as? NSDictionary, var lastModifiedV = lastModifiedDict["v"] as? String {
                        print("last_modified \(lastModifiedV)")
                        if let idxMilli = lastModifiedV.firstIndex(of: "."), let idxTZ = lastModifiedV.firstIndex(of: "+"), idxMilli < idxTZ {
                            lastModifiedV = lastModifiedV.replacingCharacters(in: idxMilli..<idxTZ, with: "")
                        }
                        print("last_modified_new \(lastModifiedV)")
                        
                        let dateFormatter = ISO8601DateFormatter()
                        dateFormatter.formatOptions = .withInternetDateTime
                        if let date = dateFormatter.date(from: lastModifiedV) {
                            readingBook.lastModified = date
                            self.updateBook(book: readingBook)
                        }
                    }
                    
                    updatingMetadataStatus = "Success"
                    updatingMetadata = false
                    
                    if let library = calibreLibraries[readingBook.library.id], let goodreadsId = readingBook.identifiers["goodreads"], let goodreadsSyncProfileName = library.goodreadsSyncProfileName, goodreadsSyncProfileName.count > 0 {
                        let connector = GoodreadsSyncConnector(server: library.server, profileName: goodreadsSyncProfileName)
                        connector.updateReadingProgress(goodreads_id: goodreadsId, progress: updatedReadingPosition.lastProgress)
                    }
                }
            }
            updatingMetadata = true
            updatingMetadataTask!.resume()
            
        }catch{
        }
    }
    
    func getMetadataNew(oldbook: CalibreBook, completion: ((_ newbook: CalibreBook) -> Void)? = nil) {
        let endpointUrl = URL(string: oldbook.library.server.serverUrl + "/get/json/\(oldbook.id)/" + oldbook.library.key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)!

        let request = URLRequest(url: endpointUrl, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        
        let task = URLSession.shared.dataTask(with: request) { [self] data, response, error in
            if let error = error {
                defaultLog.warning("error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    updatingMetadataStatus = error.localizedDescription
                    updatingMetadata = false
                    completion?(oldbook)
                }
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                defaultLog.warning("not httpResponse: \(response.debugDescription)")
                DispatchQueue.main.async {
                    updatingMetadataStatus = response.debugDescription
                    updatingMetadata = false
                    completion?(oldbook)
                }
                return
            }
            guard httpResponse.statusCode != 404 else {
                defaultLog.warning("statusCode 404: \(httpResponse.debugDescription)")
                DispatchQueue.main.async {
                    updatingMetadataStatus = "Deleted"
                    updatingMetadata = false
                    completion?(oldbook)
                }
                return
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                defaultLog.warning("statusCode not 2xx: \(httpResponse.debugDescription)")
                DispatchQueue.main.async {
                    updatingMetadataStatus = httpResponse.debugDescription
                    updatingMetadata = false
                    completion?(oldbook)
                }
                return
            }
            
            guard let mimeType = httpResponse.mimeType, mimeType == "application/json",
                  let data = data,
                  let string = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async {
                    updatingMetadataStatus = httpResponse.debugDescription
                    updatingMetadata = false
                    completion?(oldbook)
                }
                return
            }
            
            DispatchQueue.main.async {
                //self.webView.loadHTMLString(string, baseURL: url)
                //                            defaultLog.warning("httpResponse: \(string)")
                //book.comments = string
                guard var book = handleLibraryBookOneNew(oldbook: oldbook, json: data) else {
                    completion?(oldbook)
                    return
                }
                
                if( book.readPos.getDevices().isEmpty) {
                    book.readPos.addInitialPosition(deviceName, defaultReaderForDefaultFormat(book: book).rawValue)
                }
                
                updateBook(book: book)
                
                updatingMetadataStatus = "Success"
                updatingMetadata = false
                
                completion?(book)
            }
        }
        
        updatingMetadata = true
        task.resume()
    }
    
    func getBookManifest(book: CalibreBook, format: Format, completion: ((_ manifest: Data) -> Void)? = nil) {
        let emptyData = "{}".data(using: .ascii)!
        
        guard formatReaderMap[format] != nil else {
            updatingMetadataStatus = "Success"
            updatingMetadata = false
            completion?(emptyData)
            return
        }
        
        let endpointUrl = URL(string: book.library.server.serverUrl + "/book-manifest/\(book.id)/\(format.id)?library_id=" + book.library.key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)!

        let request = URLRequest(url: endpointUrl)
        
        let task = URLSession.shared.dataTask(with: request) { [self] data, response, error in
            if let error = error {
                defaultLog.warning("error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    updatingMetadataStatus = error.localizedDescription
                    updatingMetadata = false
                    completion?(emptyData)
                }
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                defaultLog.warning("not httpResponse: \(response.debugDescription)")
                DispatchQueue.main.async {
                    updatingMetadataStatus = response.debugDescription
                    updatingMetadata = false
                    completion?(emptyData)
                }
                return
            }
            
            guard httpResponse.statusCode != 404 else {
                DispatchQueue.main.async {
                    updatingMetadataStatus = "Deleted"
                    updatingMetadata = false
                    completion?(emptyData)
                }
                return
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                defaultLog.warning("statusCode not 2xx: \(httpResponse.debugDescription)")
                DispatchQueue.main.async {
                    updatingMetadataStatus = httpResponse.debugDescription
                    updatingMetadata = false
                    completion?(emptyData)
                }
                return
            }
            
            if let mimeType = httpResponse.mimeType, mimeType == "application/json",
               let data = data {
                DispatchQueue.main.async {
                    updatingMetadataStatus = "Success"
                    updatingMetadata = false
                    
                    completion?(data)
                }
            }
        }
        
        updatingMetadata = true
        task.resume()
    }
    
    func goToPreviousBook() {
        if let curIndex = filteredBookList.firstIndex(of: currentBookId), curIndex > 0 {
            currentBookId = filteredBookList[curIndex-1]
        }
    }
    
    func goToNextBook() {
        if let curIndex = filteredBookList.firstIndex(of: selectedBookId ?? currentBookId), curIndex < filteredBookList.count - 1 {
            currentBookId = filteredBookList[curIndex + 1]
        }
    }
    
    func defaultReaderForDefaultFormat(book: CalibreBook) -> ReaderType {
        if book.formats.contains(where: { $0.key == defaultFormat.rawValue }) {
            return formatReaderMap[defaultFormat]!.first!
        } else {
            return book.formats.keys.compactMap {
                Format(rawValue: $0)
            }
            .reversed()
            .reduce(ReaderType.UNSUPPORTED) { formatReaderMap[$1]!.first! }
        }
    }
    
    func formatOfReader(readerName: String) -> Format? {
        let formats = formatReaderMap.filter {
            $0.value.contains(where: { reader in reader.rawValue == readerName } )
        }
        return formats.first?.key
    }
    
    func prepareBookReading(book: CalibreBook) -> ReaderInfo? {
        var candidatePositions = [BookDeviceReadingPosition]()

        if let position = getDeviceReadingPosition() {
            candidatePositions.append(position)
        }
        if let position = getLatestReadingPosition() {
            candidatePositions.append(position)
        }
        if let position = getSelectedReadingPosition() {
            candidatePositions.append(position)
        }
        candidatePositions.append(contentsOf: book.readPos.getDevices())
        
        var formatReaderPairArray = [(Format, ReaderType, BookDeviceReadingPosition)]()
        candidatePositions.forEach { position in
            formatReaderPairArray.append(
                contentsOf: formatReaderMap.compactMap {
                    guard let index = $0.value.firstIndex(where: { $0.rawValue == position.readerName }) else { return nil }
                    return ($0.key, $0.value[index], position)
                } as [(Format, ReaderType, BookDeviceReadingPosition)]
            )
        }
        
        guard let formatReaderPair = formatReaderPairArray.first else { return nil }
        guard let savedURL = getSavedUrl(book: book, format: formatReaderPair.0) else { return nil }
        guard FileManager.default.fileExists(atPath: savedURL.path) else {
            return nil
        }
        
        return ReaderInfo(url: savedURL, format: formatReaderPair.0, readerType: formatReaderPair.1, position: formatReaderPair.2)
    }
    
    func prepareBookReading(url: URL, format: Format, readerType: ReaderType, position: BookDeviceReadingPosition) {
        let readerInfo = ReaderInfo(
            url: url,
            format: format,
            readerType: readerType,
            position: position
        )
        self.readerInfo = readerInfo
    }
    
    func removeLibrary(libraryId: String) -> Bool {
        guard let library = calibreLibraries[libraryId] else { return false }
        
        //remove cached book files
        let libraryBooksInShelf = booksInShelf.filter {
            $0.value.library.id == libraryId
        }
        libraryBooksInShelf.forEach {
            self.removeFromShelf(inShelfId: $0.key)
        }
        
        //remove library info
        do {
            let booksCached = realm.objects(CalibreBookRealm.self).filter(
                NSPredicate(format: "serverUrl = %@ AND serverUsername = %@ AND libraryName = %@",
                            library.server.baseUrl,
                            library.server.username,
                            library.name
                )
            )
            try realm.write {
                realm.delete(booksCached)
            }
        } catch {
            return false
        }
        
        return true
    }
    
    func removeServer(serverId: String) -> Bool {
        guard let server = calibreServers[serverId] else { return false }
        
        let libraries = calibreLibraries.filter {
            $0.value.server == server
        }
        
        var isSuccess = true
        libraries.forEach {
            let result = removeLibrary(libraryId: $0.key)
            isSuccess = isSuccess && result
        }
        if !isSuccess {
            return false
        }
        
        //remove library info
        libraries.forEach {
            calibreLibraries.removeValue(forKey: $0.key)
        }
        do {
            let serverLibraryRealms = realm.objects(CalibreLibraryRealm.self).filter(
                NSPredicate(format: "serverUrl = %@ AND serverUsername = %@",
                            server.baseUrl,
                            server.username
                ))
            try realm.write {
                realm.delete(serverLibraryRealms)
            }
        } catch {
            return false
        }
        
        //remove server
        calibreServers.removeValue(forKey: serverId)
        do {
            let serverRealms = realm.objects(CalibreServerRealm.self).filter(
                NSPredicate(format: "baseUrl = %@ AND username = %@",
                            server.baseUrl,
                            server.username
                )
            )
            try realm.write {
                realm.delete(serverRealms)
            }
        } catch {
            return false
        }
        
        //reset current server id
        currentCalibreServerId = calibreServers.keys.first!
        
        return true
    }
    
    func updateServer(oldServer: CalibreServer, newServer: CalibreServer) {
        
        do {
            try self.updateServerRealm(server: newServer)
        } catch {
            
        }
        self.calibreServers.removeValue(forKey: oldServer.id)
        self.calibreServers[newServer.id] = newServer
        
        if oldServer.id != newServer.id {
            calibreServerUpdating = true
            calibreServerUpdatingStatus = "Updating..."
            
            //if major change occured
            //remove old server from realm
            
            realm.objects(CalibreServerRealm.self).forEach { serverRealm in
                guard serverRealm.baseUrl == oldServer.baseUrl && serverRealm.username == oldServer.username else {
                    return
                }
                do {
                    try realm.write {
                        realm.delete(serverRealm)
                    }
                } catch {
                    
                }
            }
            
            
            //update library
            let librariesCached = realm.objects(CalibreLibraryRealm.self)
            librariesCached.forEach { oldLibraryRealm in
                guard oldLibraryRealm.serverUrl == oldServer.baseUrl && oldLibraryRealm.serverUsername == oldServer.username else { return }
                    
                let oldLibrary = CalibreLibrary(
                    server: oldServer,
                    key: oldLibraryRealm.key!,
                    name: oldLibraryRealm.name!,
                    readPosColumnName: oldLibraryRealm.readPosColumnName,
                    goodreadsSyncProfileName: oldLibraryRealm.goodreadsSyncProfileName)
                
                
                let newLibrary = CalibreLibrary(
                    server: newServer,
                    key: oldLibraryRealm.key!,
                    name: oldLibraryRealm.name!,
                    readPosColumnName: oldLibraryRealm.readPosColumnName,
                    goodreadsSyncProfileName: oldLibraryRealm.goodreadsSyncProfileName)
                
                do {
                    try realm.write {
                        realm.delete(oldLibraryRealm)
                    }
                    try updateLibraryRealm(library: newLibrary)
                } catch {
                    
                }
                
                calibreLibraries.removeValue(forKey: oldLibrary.id)
                calibreLibraries[newLibrary.id] = newLibrary
            }
            
            //update books
            let booksCached = realm.objects(CalibreBookRealm.self)
            do {
                try realm.write {
                    booksCached.forEach { oldBookRealm in
                        guard oldBookRealm.serverUrl == oldServer.baseUrl && oldBookRealm.serverUsername == oldServer.username else { return }
                        let newBookRealm = CalibreBookRealm(value: oldBookRealm)
                        newBookRealm.serverUrl = newServer.baseUrl
                        newBookRealm.serverUsername = newServer.username
                        
                        realm.delete(oldBookRealm)
                        realm.add(newBookRealm, update: .all)
                    }
                }
            } catch {
                
            }
            
            //reload shelf
            booksInShelf.removeAll(keepingCapacity: true)
            populateBookShelf()
            
            //reload book list
            calibreServerUpdating = false
            calibreServerUpdatingStatus = "Finished"
            
            currentCalibreServerId = newServer.id
        }
    }
    
    func syncLibrary(alertDelegate: AlertDelegate) {
        guard let server = currentCalibreServer,
              let library = currentCalibreLibrary,
              let libraryKeyEncoded = library.key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let endpointUrl = URL(string: server.serverUrl + "/cdb/cmd/list/0?library_id=" + libraryKeyEncoded)
              else {
            return
        }
        
        let json:[Any] = [["title", "authors", "formats", "rating", "series", "identifiers"], "", "", "", -1]
        
        let data = try! JSONSerialization.data(withJSONObject: json, options: [])
        
        var request = URLRequest(url: endpointUrl)
        request.httpMethod = "POST"
        request.httpBody = data
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                self.defaultLog.warning("error: \(error.localizedDescription)")

                let alertItem = AlertItem(id: error.localizedDescription, action: {
                    self.calibreServerUpdating = false
                    self.calibreServerUpdatingStatus = "Failed"
                })
                alertDelegate.alert(alertItem: alertItem)

                return
            }
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                self.defaultLog.warning("not httpResponse: \(response.debugDescription)")
                
                let alertItem = AlertItem(id: response?.description ?? "nil reponse", action: {
                    self.calibreServerUpdating = false
                    self.calibreServerUpdatingStatus = "Failed"
                })
                alertDelegate.alert(alertItem: alertItem)
                
                return
            }
            
            if let mimeType = httpResponse.mimeType, mimeType == "application/json",
               let data = data {
                DispatchQueue(label: "data").async {
                    //self.webView.loadHTMLString(string, baseURL: url)
                    //result = string
                    self.handleLibraryBooks(json: data) { isSuccess in
                        self.calibreServerUpdating = false
                        if !isSuccess {
                            let alertItem = AlertItem(id: "Failed to parse calibre server response.")
                            alertDelegate.alert(alertItem: alertItem)
                            
                            self.calibreServerUpdatingStatus = "Failed"
                        } else {
                            self.calibreServerUpdatingStatus = "Refreshed"
                        }
                    }
                }
            }
        }
        
        calibreServerUpdating = true
        calibreServerUpdatingStatus = "Refreshing"
        
        task.resume()
    }
    
}

func load<T: Decodable>(_ filename: String) -> T {
    let data: Data
    
    guard let file = Bundle.main.url(forResource: filename, withExtension: nil)
    else {
        fatalError("Couldn't find \(filename) in main bundle.")
    }
    
    do {
        data = try Data(contentsOf: file)
    } catch {
        fatalError("Couldn't load \(filename) from main bundle:\n\(error)")
    }
    
    do {
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    } catch {
        fatalError("Couldn't parse \(filename) as \(T.self):\n\(error)")
    }
}
