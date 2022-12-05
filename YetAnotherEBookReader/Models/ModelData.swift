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
import ShelfView

import CryptoSwift
#if canImport(R2Shared)
import R2Shared
import R2Streamer
#endif

final class ModelData: ObservableObject {
    static var shared: ModelData?
    
    @Published var deviceName = UIDevice.current.name
    
    @Published var calibreServers = [String: CalibreServer]()
    @Published var calibreServerInfo: CalibreServerInfo?
    @Published var calibreServerInfoStaging = [String: CalibreServerInfo]()
    
    @Published var calibreLibraries = [String: CalibreLibrary]()
    @Published var calibreLibraryCategories = [CalibreLibraryCategoryKey: CalibreLibraryCategoryValue]()
    @Published var calibreLibraryCategoryMerged = [String: [String]]()
    
    /// Used for server level activities
    @Published var calibreServerUpdating = false
    @Published var calibreServerUpdatingStatus: String? = nil
    
    @Published var activeTab = 0
    var documentServer: CalibreServer?
    var localLibrary: CalibreLibrary?
    
    //for LibraryInfoView
    @Published var defaultFormat = Format.PDF
    var formatReaderMap = [Format: [ReaderType]]()
    var formatList = [Format]()
    
    @Published var searchString = ""
    @Published var searchLibraryResults = [LibrarySearchKey: LibrarySearchResult]()
    @Published var sortCriteria = LibrarySearchSort(by: SortCriteria.Modified, ascending: false)
    @Published var filterCriteriaCategory = [String: Set<String>]()
    @Published var filterCriteriaShelved = FilterCriteriaShelved.none

    @Published var filterCriteriaLibraries = Set<String>()
    
    @Published var searchCriteriaResults = [LibrarySearchCriteria: LibrarySearchCriteriaResultMerged]()
    
    @Published var filteredBookListPageCount = 0
    @Published var filteredBookListPageSize = 100
    @Published var filteredBookListPageNumber = 0

    static let SearchLibraryResultsRealmConfiguration = Realm.Configuration(fileURL: nil, inMemoryIdentifier: "searchLibraryResultsRealm")
    
    static let SearchLibraryResultsRealmQueue = DispatchQueue(label: "searchLibraryResultsRealm", qos: .userInitiated)
    
    let searchLibraryResultsRealmMainThread = try? Realm(configuration: SearchLibraryResultsRealmConfiguration)
    
    var searchLibraryResultsRealmQueue: Realm?
    
    @Published var booksInShelf = [String: CalibreBook]()
    
    let bookImportedSubject = PassthroughSubject<BookImportInfo, Never>()
    let dismissAllSubject = PassthroughSubject<String, Never>()
    
    let recentShelfModelSubject = PassthroughSubject<[BookModel], Never>()
    let discoverShelfModelSubject = PassthroughSubject<[ShelfModelSection], Never>()
    
    var presentingStack = [Binding<Bool>]()
    
    var currentBookId: String = "" {
        didSet {
            self.selectedBookId = currentBookId
        }
    }

    @Published var selectedBookId: String? = nil {
        didSet {
            if let selectedBookId = selectedBookId,
               readingBookInShelfId != selectedBookId {
                readingBookInShelfId = selectedBookId
            }
        }
    }
    
    @Published var selectedPosition = ""
    
    @available(*, deprecated, message: "use readPos")
    @Published var updatedReadingPosition = BookDeviceReadingPosition(id: UIDevice().name, readerName: "") {
        didSet {
            self.defaultLog.info("updatedReadingPosition=\(self.updatedReadingPosition.description)")
        }
    }
    let bookReaderClosedSubject = PassthroughSubject<(book: CalibreBook, position: BookDeviceReadingPosition), Never>()
    let bookReaderActivitySubject = PassthroughSubject<ScenePhase, Never>()
    
    var calibreCancellables = Set<AnyCancellable>()
    
    let bookFormatDownloadSubject = PassthroughSubject<(book: CalibreBook, format: Format), Never>()
    let bookDownloadedSubject = PassthroughSubject<CalibreBook, Never>()
    
    let librarySearchSubject = PassthroughSubject<LibrarySearchKey, Never>()
    let librarySearchReturnedSubject = PassthroughSubject<LibrarySearchKey, Never>()
    
    let filteredBookListMergeSubject = PassthroughSubject<LibrarySearchKey, Never>()
    let librarySearchResetSubject = PassthroughSubject<LibrarySearchKey, Never>()
    let filteredBookListRefreshingSubject = PassthroughSubject<Any, Never>()
    
    let libraryCategorySubject = PassthroughSubject<LibraryCategoryList, Never>()
    let libraryCategoryMergeSubject = PassthroughSubject<String, Never>()
    
    let categoryItemListSubject = PassthroughSubject<String, Never>()
    
    var readingBookInShelfId: String? = nil {
        didSet {
            guard let readingBookInShelfId = readingBookInShelfId else {
                readingBook = nil
                return
            }
            if readingBook?.inShelfId != readingBookInShelfId {
                readingBook = booksInShelf[readingBookInShelfId]
            }
            if readingBook == nil,
               let bookRealm = realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: readingBookInShelfId) {
                readingBook = convert(bookRealm: bookRealm)
            }
            
            if readingBook == nil,
               let bookRealm = self.searchLibraryResultsRealmMainThread?.object(ofType: CalibreBookRealm.self, forPrimaryKey: readingBookInShelfId) {
                readingBook = convert(bookRealm: bookRealm)
            }
        }
    }
    @Published var readingBook: CalibreBook? = nil {
        didSet {
            guard let readingBook = readingBook else {
                self.selectedPosition = ""
                return
            }
            
            readerInfo = prepareBookReading(book: readingBook)
            self.selectedPosition = readerInfo?.position.id ?? deviceName
        }
    }
    
    @Published var readerInfo: ReaderInfo? = nil
    
    @Published var presentingEBookReaderFromShelf = false
        
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
    
    static var RealmSchemaVersion:UInt64 = 1
    var realm: Realm!
    var realmConf: Realm.Configuration!
    
    let activityDispatchQueue = DispatchQueue(label: "io.github.dsreader.activity")
    
    let kfImageCache = ImageCache.default
    var authResponsor = AuthResponsor()
    
    lazy var downloadService = BookFormatDownloadService(modelData: self)
    @Published var activeDownloads: [URL: BookFormatDownload] = [:]

    lazy var calibreServerService = CalibreServerService(modelData: self)
    @Published var metadataSessions = [String: URLSession]()

    var calibreServiceCancellable: AnyCancellable?
    var shelfRefreshCancellable: AnyCancellable?
    var dshelperRefreshCancellable: AnyCancellable?
    
    let syncLibrarySubject = PassthroughSubject<CalibreSyncLibraryRequest, Never>()
    var syncLibrariesIncrementalCancellable: AnyCancellable?
    
    lazy var metadataQueue: OperationQueue = {
        var queue = OperationQueue()
        queue.name = "Book Metadata queue"
        queue.maxConcurrentOperationCount = 2
        return queue
    }()
    
    /// inShelfId for single book
    /// empty string for full update
    let calibreUpdatedSubject = PassthroughSubject<calibreUpdatedSignal, Never>()
    let getBooksMetadataSubject = PassthroughSubject<CalibreBooksTask, Never>()
    let setLastReadPositionSubject = PassthroughSubject<CalibreBookSetLastReadPositionTask, Never>()
    let updateAnnotationsSubject = PassthroughSubject<CalibreBookUpdateAnnotationsTask, Never>()
    
    @Published var librarySyncStatus = [String: CalibreSyncStatus]()

    @Published var userFontInfos = [String: FontInfo]()

    @Published var bookModelSection = [ShelfModelSection]()

    var resourceFileDictionary: NSDictionary?

    init(mock: Bool = false) {
        ModelData.shared = self
        
        //Load content of Info.plist into resourceFileDictionary dictionary
        if let path = Bundle.main.path(forResource: "Info", ofType: "plist") {
            resourceFileDictionary = NSDictionary(contentsOfFile: path)
        } else {
            resourceFileDictionary = try? NSDictionary(contentsOf: Bundle.main.bundleURL.appendingPathComponent("Contents", isDirectory: true).appendingPathComponent("Info.plist", isDirectory: false), error: ())
        }
        
        
        kfImageCache.diskStorage.config.expiration = .days(28)
        KingfisherManager.shared.defaultOptions = [.requestModifier(AuthPlugin(modelData: self))]
        ImageDownloader.default.authenticationChallengeResponder = authResponsor
        
        switch UIDevice.current.userInterfaceIdiom {
            case .phone:
                defaultFormat = Format.EPUB
            case .pad:
                defaultFormat = Format.PDF
            default:
                defaultFormat = Format.EPUB
        }
        
        formatReaderMap[Format.EPUB] = [ReaderType.YabrEPUB, ReaderType.ReadiumEPUB]
        formatReaderMap[Format.PDF] = [ReaderType.YabrPDF, ReaderType.ReadiumPDF]
        formatReaderMap[Format.CBZ] = [ReaderType.ReadiumCBZ]

        downloadService.modelData = self
        
        self.reloadCustomFonts()
        
        registerSyncLibraryCancellable()
        registerGetBooksMetadataCancellable()
        registerSetLastReadPositionCancellable()
        registerUpdateAnnotationsCancellable()
        registerBookReaderClosedCancellable()
        
        registerRecentShelfUpdater()
        registerDiscoverShelfUpdater()
        
        bookDownloadedSubject.sink { book in
            self.calibreUpdatedSubject.send(.book(book))
            if self.activeTab == 2 {
                self.filteredBookListMergeSubject.send(LibrarySearchKey(libraryId: "", criteria: self.currentLibrarySearchCriteria))
            }
        }.store(in: &calibreCancellables)
        
        self.calibreServerService.registerLibraryCategoryHandler()
        self.calibreServerService.registerLibrarySearchHandler()
        self.calibreServerService.registerLibrarySearchResetHandler()
        
        self.calibreServerService.registerFilteredBookListMergeHandler()
        self.calibreServerService.registerLibraryCategoryMergeHandler()
        
        self.calibreServerService.registerBookFormatDownloadHandler()
        
        ModelData.SearchLibraryResultsRealmQueue.sync {
            self.searchLibraryResultsRealmQueue = try? Realm(configuration: ModelData.SearchLibraryResultsRealmConfiguration, queue: ModelData.SearchLibraryResultsRealmQueue)
        }
        
        if mock {
            let library = calibreLibraries.first!.value
            
            var book = CalibreBook(id: 1, library: library)
            
            book.title = "Mock Book Title"
            
            book.formats[Format.EPUB.rawValue] = .init(filename: book.title + ".epub", serverSize: 1024000, serverMTime: Date(timeIntervalSince1970: 1645495322), cached: true, cacheSize: 1024000, cacheMTime: Date(timeIntervalSince1970: 1645495322), manifest: nil)
            if let bookSavedUrl = getSavedUrl(book: book, format: Format.EPUB),
               FileManager.default.fileExists(atPath: bookSavedUrl.path) == false {
                FileManager.default.createFile(atPath: bookSavedUrl.path, contents: String("EPUB").data(using: .utf8), attributes: nil)
            }
            book.readPos = BookAnnotation(id: book.id, library: book.library, localFilename: book.title + ".epub")
            
            var position = BookDeviceReadingPosition(
                id: self.deviceName,
                readerName: ReaderType.YabrEPUB.rawValue,
                maxPage: 99,
                lastReadPage: 1,
                lastReadChapter: "Mock Last Chapter",
                lastChapterProgress: 5,
                lastProgress: 1,
                furthestReadPage: 98,
                furthestReadChapter: "Mock Furthest Chapter",
                lastPosition: [1,1,1]
            )
            position.epoch = 1645495322
            
            book.readPos.updatePosition(position)
            
            self.readingBook = book
            
            
//                title: "Mock Title",
//                authors: ["Mock Author", "Mock Auther 2"],
//                comments: "<p>Mock Comment",
//                publisher: "Mock Publisher",
//                series: "Mock Series",
//                rating: 8,
//                size: 12345678,
//                pubDate: Date.init(timeIntervalSince1970: TimeInterval(1262275200)),
//                timestamp: Date.init(timeIntervalSince1970: TimeInterval(1262275200)),
//                lastModified: Date.init(timeIntervalSince1970: TimeInterval(1577808000)),
//                lastSynced: Date.init(timeIntervalSince1970: TimeInterval(1577808000)),
//                lastUpdated: Date.init(timeIntervalSince1970: TimeInterval(1577808000)),
//                tags: ["Mock"],
//                formats: ["EPUB" : FormatInfo(
//                            filename: "file:///mock",
//                            serverSize: 123456,
//                            serverMTime: Date.init(timeIntervalSince1970: TimeInterval(1577808000)),
//                            cached: false, cacheSize: 123456,
//                            cacheMTime: Date.init(timeIntervalSince1970: TimeInterval(1577808000))
//                )],
//                readPos: readPos,
//                identifiers: [:],
//                inShelf: true,
//                inShelfName: "Default")
            self.booksInShelf[self.readingBook!.inShelfId] = self.readingBook
            
            cleanCalibreActivities(startDatetime: Date())
            logStartCalibreActivity(type: "Mock", request: URLRequest(url: URL(string: "http://calibre-server.lan:8080/")!), startDatetime: Date(), bookId: 1, libraryId: library.id)
        }
    }
    
    func tryInitializeDatabase(statusHandler: @escaping (String) -> Void) throws {
        ModelData.RealmSchemaVersion = UInt64(resourceFileDictionary?.value(forKey: "CFBundleVersion") as? String ?? "1") ?? 1
        realmConf = Realm.Configuration(
            schemaVersion: ModelData.RealmSchemaVersion,
            migrationBlock: { migration, oldSchemaVersion in
                if oldSchemaVersion < 42 {  //CalibreServerRealm's hasPublicUrl and hasAuth
                    migration.enumerateObjects(ofType: CalibreServerRealm.className()) { oldObject, newObject in
                        //print("migrationBlock \(String(describing: oldObject)) \(String(describing: newObject))")
                        if let publicUrl = oldObject!["publicUrl"] as? String {
                            newObject!["hasPublicUrl"] = publicUrl.count > 0
                        }
                        if let username = oldObject!["username"] as? String, let password = oldObject!["password"] as? String {
                            newObject!["hasAuth"] = username.count > 0 && password.count > 0
                        }
                    }
                }
                if oldSchemaVersion < 44 {  //authos to first/second/more, tags to first/second/third/more
                    migration.enumerateObjects(ofType: CalibreBookRealm.className()) { oldObject, newObject in
                        if let authorsOld = oldObject?.dynamicList("authors") {
                            var authors = Array<DynamicObject>(authorsOld)
                            ["First", "Second", "Third"].forEach {
                                newObject?.setValue(authors.popFirst(), forKey: "author\($0)")
                                
                            }
                            newObject?.dynamicList("authorsMore").append(objectsIn: authors)
                        }
                        
                        if let tagsOld = oldObject?.dynamicList("tags") {
                            var tags = Array<DynamicObject>(tagsOld)
                            ["First", "Second", "Third"].forEach {
                                newObject?.setValue(tags.popFirst(), forKey: "tag\($0)")
                            }
                            newObject?.dynamicList("tagsMore").append(objectsIn: tags)
                        }
                        
                    }
                }
                if oldSchemaVersion < 46 {
                    migration.enumerateObjects(ofType: CalibreBookRealm.className()) { oldObject, newObject in
                        if let lastModified = oldObject?.value(forKey: "lastModified") {
                            newObject?.setValue(lastModified, forKey: "lastModified")
                        }
                    }
                }
                if oldSchemaVersion < 80 {
                    migration.enumerateObjects(ofType: BookDeviceReadingPositionHistoryRealm.className()) { oldObject, newObject in
                        if let bookId = oldObject?.value(forKey: "bookId") as? Int32 {
                            if let libraryId = oldObject?.value(forKey: "libraryId") as? String,
                               let libraryName = libraryId.components(separatedBy: " - ").last {
                                newObject?.setValue("\(libraryName.replacingOccurrences(of: " ", with: "_")) - \(bookId)", forUndefinedKey: "bookId")
                            } else {
                                newObject?.setValue("Unknown - \(bookId)", forUndefinedKey: "bookId")
                            }
                        } else if let bookId = oldObject?.value(forKey: "bookId") as? String {
                            let components = bookId.components(separatedBy: " - ")
                            let newId = components.suffix(2).joined(separator: " - ")
                            newObject?.setValue(newId, forUndefinedKey: "bookId")
                        } else {
                            print("\(oldObject?.value(forKey: "bookId"))")
                        }
                    }
                }
                
                if oldSchemaVersion < 90 {
                    /**
                     migrate to UUID based server id
                     1. create new objects with valid UUID, remove old objects,
                     */
                    var servers = [UUID: (baseUrl: String, username: String?)]()
                    migration.enumerateObjects(ofType: CalibreServerRealm.className()) { oldObject, newObject in
                        guard let oldObject = oldObject, let newObject = newObject else { return }
                        guard let baseUrl = oldObject["baseUrl"] as? String else { return }
                        
//                        if let newObject = newObject {
//                            migration.delete(newObject)
//                        }
                        
                        let serverUUID = baseUrl.hasPrefix(".") ? CalibreServer.LocalServerUUID : .init()
//                        let uuidObject = oldObject.copy()
                        newObject["primaryKey"] = serverUUID.uuidString
//                        migration.create(CalibreServerRealm.className(), value: uuidObject)
                        print("\(#function) oldObject=\(oldObject) newObject=\(newObject)")
                        
                        servers[serverUUID] = (baseUrl: baseUrl, username: oldObject["username"] as? String)
                    }
                    
                    var libraries = [String: (serverUUID: UUID, baseUrl: String?, username: String?, key: String?, name: String?)]()
                    migration.enumerateObjects(ofType: CalibreLibraryRealm.className()) { oldObject, newObject in
                        guard let oldObject = oldObject, let newObject = newObject else { return }
                        guard let serverUUID = servers.first(where: {
                            $1.baseUrl == (oldObject["serverUrl"] as? String) && $1.username == (oldObject["serverUsername"] as? String)
                        })?.key else { return }
                        
                        let primaryKey = CalibreLibraryRealm.PrimaryKey(serverUUID: serverUUID.uuidString, libraryName: (oldObject["name"] as? String) ?? "Calibre Library")
                        
                        newObject["serverUUID"] = serverUUID.uuidString
                        newObject["primaryKey"] = primaryKey
                        print("\(#function) primaryKey=\(primaryKey) oldObject=\(oldObject) newObject=\(newObject)")
                        
                        libraries[primaryKey] = (
                            serverUUID: serverUUID,
                            baseUrl: oldObject["serverUrl"] as? String,
                            username: oldObject["serverUsername"] as? String,
                            key: oldObject["key"] as? String,
                            name: oldObject["name"] as? String
                        )
                    }
                    
                    var count = 0
                    migration.enumerateObjects(ofType: CalibreBookRealm.className()) { oldObject, newObject in
                        guard let oldObject = oldObject, let newObject = newObject else { return }
                        
                        guard let libraryInfo = libraries.first(where: {
                            $1.baseUrl == (oldObject["serverUrl"] as? String)
                            && $1.username == (oldObject["serverUsername"] as? String)
                            && $1.key != nil
                            && $1.name == (oldObject["libraryName"] as? String)
                        })?.value else {
                            migration.delete(newObject)
                            return
                        }
                        
                        let primaryKey = CalibreBookRealm.PrimaryKey(
                            serverUUID: libraryInfo.serverUUID.uuidString,
                            libraryName: (oldObject["libraryName"] as? String) ?? "Calibre Library",
                            id: (oldObject["id"] as! Int32).description
                        )
                                                
                        newObject["serverUUID"] = libraryInfo.serverUUID.uuidString
                        newObject["primaryKey"] = primaryKey
                        count += 1
                        
                        print("\(#function) count=\(count) oldKey=\(oldObject["primaryKey"]!) newKey=\(newObject["primaryKey"]!)")
                        
                        if count % 1000 == 0 {
                            statusHandler("Progress \(count)")
                        }
                    }
                    
//                    fatalError("TODO")
                    statusHandler("Finalizing...")
                }
            },
            shouldCompactOnLaunch: { fileSize, dataSize in
                return dataSize * 2 < fileSize || (dataSize + 33554432) < fileSize
            }
        )
        
        if let applicationSupportURL = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
            realmConf.fileURL = applicationSupportURL.appendingPathComponent("default.realm")
            if let documentDirectoryURL = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
                let existingRealmURL = documentDirectoryURL.appendingPathComponent("default.realm")
                if FileManager.default.fileExists(atPath: existingRealmURL.path) {
                    try? FileManager.default.moveItem(at: existingRealmURL, to: realmConf.fileURL!)
                }
            }
        }
        
        let _ = try Realm(configuration: realmConf)
        realmConf.migrationBlock = nil
    }
    
    func initializeDatabase() {
        realm = try! Realm(
            configuration: realmConf
        )
        
        populateServers()
        
        populateLibraries()
        
        populateBookShelf()
        
        populateLocalLibraryBooks()
        
        calibreUpdatedSubject.send(.shelf)
        
        cleanCalibreActivities(startDatetime: Date(timeIntervalSinceNow: TimeInterval(-86400*7)))
    }
    
    func importCustomFonts(urls: [URL]) -> [CFArray]? {
        guard let documentDirectory = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        else { return nil }
        
        let fontsDirectory = documentDirectory.appendingPathComponent("Fonts",  isDirectory: true)
        guard let _ = try? FileManager.default.createDirectory(atPath: fontsDirectory.path, withIntermediateDirectories: true, attributes: nil) else { return nil }
    
        var fontDescriptorArrays = [CFArray]()

        urls.forEach { url in
            guard let ctFontDescriptorArray = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL)
            else { return }
            
            let fontDestFile = fontsDirectory.appendingPathComponent(url.lastPathComponent)
            do {
                try FileManager.default.moveItem(atPath: url.path, toPath: fontDestFile.path)
                fontDescriptorArrays.append(ctFontDescriptorArray)
            } catch {
                print("importCustomFonts \(error.localizedDescription)")
            }
        }
        
        return fontDescriptorArrays
    }
    
    func removeCustomFonts(at offsets: IndexSet) {
        let list = userFontInfos.sorted {
            ( $0.value.displayName ?? $0.key) < ( $1.value.displayName ?? $1.key)
        }
        let candidates = offsets.map { list[$0] }
        candidates.forEach { (fontId, fontInfo) in
            guard let fileURL = fontInfo.fileURL else { return }
            try? FileManager.default.removeItem(atPath: fileURL.path)
        }
    }
    
    func reloadCustomFonts() {
        if let userFontDescriptors = loadUserFonts() {
            self.userFontInfos = userFontDescriptors.mapValues { FontInfo(descriptor: $0) }
        } else {
            self.userFontInfos.removeAll()
        }
        
    }
    
    func populateBookShelf() {
        let booksInShelfRealm = realm.objects(CalibreBookRealm.self).filter(
            NSPredicate(format: "inShelf = true")
        )
        
        booksInShelfRealm.forEach {
            // print(bookRealm)
            guard let serverUUIDString = $0.serverUUID,
                  let server = calibreServers[serverUUIDString],
                  let libraryName = $0.libraryName,
                  let library = calibreLibraries[CalibreLibrary(server: server, key: "", name: libraryName).id]
            else { return }
            
//            guard let server = calibreServers[CalibreServer(name: "", baseUrl: $0.serverUrl!, hasPublicUrl: false, publicUrl: "", hasAuth: $0.serverUsername?.count ?? 0 > 0, username: $0.serverUsername!, password: "").id] else {
//                print("ERROR booksInShelfRealm missing server \($0)")
//                return
//            }
//            guard  else {
//                print("ERROR booksInShelfRealm missing library \($0)")
//                return
//            }
            
            var book = self.convert(library: library, bookRealm: $0)
            
            book.formats.forEach { formatRaw, formatInfo in
                guard let format = Format(rawValue: formatRaw) else {
//                    var formatInfo = formatInfo
//                    formatInfo.cached = false
//                    book.formats[formatRaw] = formatInfo
                    return
                }
                var formatInfoNew = formatInfo
                if let cacheInfo = getCacheInfo(book: book, format: format),
                   let modified = cacheInfo.1 {
                    formatInfoNew.cached = true
                    formatInfoNew.cacheSize = cacheInfo.0
                    formatInfoNew.cacheMTime = modified
                } else {
                    formatInfoNew.cached = false
                    formatInfoNew.cacheSize = 0
                    formatInfoNew.cacheMTime = Date.distantPast
                }
                
                if formatInfoNew.cached != formatInfo.cached {
                    book.formats[formatRaw] = formatInfoNew
                    self.updateBook(book: book)
                }
            }
            
            self.booksInShelf[book.inShelfId] = book
            
            print("booksInShelfRealm \(book.inShelfId)")
        }
    }
    
    func populateServers() {
        let serversCached = realm.objects(CalibreServerRealm.self).sorted(by: [SortDescriptor(keyPath: "username"), SortDescriptor(keyPath: "baseUrl")])
        serversCached.forEach { serverRealm in
            guard serverRealm.baseUrl != nil else { return }
            guard let uuidString = serverRealm.primaryKey,
                  let uuid = UUID(uuidString: uuidString)
            else { return }
            
            let calibreServer = CalibreServer(
                uuid: uuid,
                name: serverRealm.name ?? serverRealm.baseUrl!,
                baseUrl: serverRealm.baseUrl!,
                hasPublicUrl: serverRealm.hasPublicUrl,
                publicUrl: serverRealm.publicUrl ?? "",
                hasAuth: serverRealm.hasAuth,
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
    }
    
    func populateLibraries() {
        let librariesCached = realm.objects(CalibreLibraryRealm.self)

        librariesCached.forEach { libraryRealm in
//            guard let calibreServer = calibreServers[CalibreServer(name: "", baseUrl: libraryRealm.serverUrl!, hasPublicUrl: false, publicUrl: "", hasAuth: libraryRealm.serverUsername?.count ?? 0 > 0, username: libraryRealm.serverUsername!, password: "").id] else {
//                print("Unknown Server: \(libraryRealm)")
//                return
//            }
            guard let serverUUIDString = libraryRealm.serverUUID,
                  let calibreServer = calibreServers[serverUUIDString]
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
                customColumnInfos: libraryRealm.customColumns.reduce(into: [String: CalibreCustomColumnInfo]()) {
                    $0[$1.label] = CalibreCustomColumnInfo(managedObject: $1)
                },
                pluginColumns: {
                    var result = [String: CalibreLibraryPluginColumnInfo]()
                    if let plugin = libraryRealm.pluginDSReaderHelper {
                        result[CalibreLibrary.PLUGIN_DSREADER_HELPER] = CalibreLibraryDSReaderHelper(managedObject: plugin)
                    }
                    if let plugin = libraryRealm.pluginDictionaryViewer {
                        result[CalibreLibrary.PLUGIN_DICTIONARY_VIEWER] = CalibreLibraryDictionaryViewer(managedObject: plugin)
                    }
                    if let plugin = libraryRealm.pluginReadingPosition {
                        result[CalibreLibrary.PLUGIN_READING_POSITION] = CalibreLibraryReadingPosition(managedObject: plugin)
                    }
                    if let plugin = libraryRealm.pluginGoodreadsSync {
                        result[CalibreLibrary.PLUGIN_GOODREADS_SYNC] = CalibreLibraryGoodreadsSync(managedObject: plugin)
                    }
                    if let plugin = libraryRealm.pluginCountPages {
                        result[CalibreLibrary.PLUGIN_COUNT_PAGES] = CalibreLibraryCountPages(managedObject: plugin)
                    }
                    return result
                }()
            )
            
            calibreLibraries[calibreLibrary.id] = calibreLibrary
        }
        
//        print("populateLibraries \(calibreLibraries)")
    }
    
    func populateLocalLibraryBooks() {
        guard let documentDirectoryURL = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            return
        }
        
        let tmpServer = CalibreServer(uuid: CalibreServer.LocalServerUUID, name: "Document Folder", baseUrl: ".", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: "")
        documentServer = calibreServers[tmpServer.id]
        if documentServer == nil || documentServer?.name != tmpServer.name {
            calibreServers[tmpServer.id] = tmpServer
            documentServer = calibreServers[tmpServer.id]
            do {
                try updateServerRealm(server: documentServer!)
            } catch {
                
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
                try updateLibraryRealm(library: localLibrary!, realm: self.realm)
            } catch {
                
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
            let fileURL = documentServer!.localBaseUrl!.appendingPathComponent(localLibrary!.key, isDirectory: true).appendingPathComponent(fileName, isDirectory: false)

            loadLocalLibraryBookMetadata(fileURL: fileURL, in: localLibrary!, on: documentServer!)
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
            // self.removeFromRealm(book: $0)
            print("populateLocalLibraryBooks removeFromShelf \($0)")
        }
    }
    
    // only move file when triggered by in-app importer, DO NOT MOVE FROM OTHER PLACES
    func onOpenURL(url: URL, doMove: Bool, doOverwrite: Bool, asNew: Bool, knownBookId: Int32? = nil) -> BookImportInfo {
        var bookImportInfo = BookImportInfo(url: url, bookId: nil, error: nil)
        
        guard let documentServer = documentServer,
              let localLibrary = localLibrary,
              let localBaseUrl = documentServer.localBaseUrl else {
            return bookImportInfo.with(error: .libraryAbsent)
        }
        
        guard let format = Format(rawValue: url.pathExtension.uppercased()) else {
            return bookImportInfo.with(error: .formatUnsupported)
        }

        if url.isFileURL {
            let _ = url.startAccessingSecurityScopedResource()
//            else {
//                print("onOpenURL url.startAccessingSecurityScopedResource() -> false")
//                return bookImportInfo.with(error: .securityFail)
//            }
            defer {
                url.stopAccessingSecurityScopedResource()
            }
            
            do {
                guard let bookId = knownBookId ?? calcLocalFileBookId(for: url) else { return bookImportInfo.with(error: .idCalcFail) }
                print("onOpenURL \(bookId)")
                bookImportInfo.bookId = bookId
                
                // check for identical file
                let bookForQuery = CalibreBook(id: bookId, library: localLibrary)
                if let book = booksInShelf[bookForQuery.inShelfId] {
                   let readerInfo = prepareBookReading(book: book)
                    if readerInfo.url.pathExtension.lowercased() == url.pathExtension.lowercased() {
                        return bookImportInfo
                    }
                }
                
                // check for dest file
                let basename = url.deletingPathExtension().lastPathComponent
                var dest = localBaseUrl.appendingPathComponent("Local Library", isDirectory: true).appendingPathComponent(basename, isDirectory: false).appendingPathExtension(format.ext)
                if FileManager.default.fileExists(atPath: dest.path) {
                    if !doOverwrite && !asNew {
                        return bookImportInfo.with(error: .destConflict)
                    }
                    if doOverwrite && asNew {
                        return bookImportInfo.with(error: .invalidArg)
                    }
                    if doOverwrite {
                        if let book = booksInShelf.filter (
                            {
                                guard $1.library.server.isLocal, let formatInfo = $1.formats[format.rawValue] else { return false }
                                return formatInfo.cached && formatInfo.filename == dest.lastPathComponent
                            }).first {
                            self.clearCache(book: book.value, format: format)   //should remove it from shelf
                        }
                    }
                    if asNew {
                        var found = false
                        for i in (1..<100) {
                            dest = localBaseUrl.appendingPathComponent("Local Library", isDirectory: true).appendingPathComponent("\(basename) (\(i))", isDirectory: false).appendingPathExtension(url.pathExtension.lowercased())
                            if FileManager.default.fileExists(atPath: dest.path) == false {
                                found = true
                                break
                            }
                        }
                        if !found {
                            return bookImportInfo.with(error: .tooManyFiles)
                        }
                    }
                }
                
                if doMove {
                    try FileManager.default.moveItem(at: url, to: dest)
                } else {
                    try FileManager.default.copyItem(at: url, to: dest)
                }
                
                if bookId == loadLocalLibraryBookMetadata(fileURL: dest, in: localLibrary, on: documentServer, knownBookId: bookId) {
                    return bookImportInfo
                } else {
                    return bookImportInfo.with(error: .loadMetaFail)
                }
                
                
            } catch {
                print("onOpenURL \(error)")
                return bookImportInfo.with(error: .fileOpFail)
            }
        }
        
        return bookImportInfo.with(error: .protocolUnsupported)
    }
    
    func calcLocalFileBookId(for fileURL: URL) -> Int32? {
        guard let digest = sha256new(for: fileURL) else { return nil }
        
        let bookId = Int32(bigEndian: digest.prefix(4).withUnsafeBytes{$0.load(as: Int32.self)})
        return bookId
    }
    
    func loadLocalLibraryBookMetadata(fileURL: URL, in library: CalibreLibrary, on server: CalibreServer, knownBookId: Int32? = nil) -> Int32? {
        guard let format = Format(rawValue: fileURL.pathExtension.uppercased()) else { return nil }
            
        guard let bookId = knownBookId ?? calcLocalFileBookId(for: fileURL) else { return nil }
        
        var book = CalibreBook(
            id: bookId,
            library: library
        )
        
        if let bookRealm = queryBookRealm(book: book, realm: realm) {
            book = convert(library: library, bookRealm: bookRealm)
        }
        
        book.title = fileURL.deletingPathExtension().lastPathComponent
        book.lastModified = Date()
        book.lastSynced = book.lastModified

        var formatInfo = FormatInfo(serverSize: 0, serverMTime: .distantPast, cached: true, cacheSize: 0, cacheMTime: .distantPast)
        formatInfo.filename = fileURL.lastPathComponent
        if let fileAttribs = try? FileManager.default.attributesOfItem(atPath: fileURL.path) {
            if let fileSize = fileAttribs[.size] as? NSNumber {
                formatInfo.serverSize = fileSize.uint64Value
                formatInfo.cacheSize = fileSize.uint64Value
            }
            if let fileTS = fileAttribs[.modificationDate] as? Date {
                formatInfo.serverMTime = fileTS
                formatInfo.cacheMTime = fileTS
                if book.timestamp < fileTS {
                    book.timestamp = fileTS
                }
            }
        }
        
        book.formats[format.rawValue] = formatInfo
        
        book.inShelf = true
        
        self.updateBook(book: book)
        
        #if canImport(R2Shared)
        let streamer = Streamer()
        streamer.open(asset: FileAsset(url: fileURL), allowUserInteraction: false) { result in
            guard let publication = try? result.get() else {
                print("Streamer \(fileURL)")
                return
            }
            
            book.title = publication.metadata.title
            if let cover = publication.cover, let coverData = cover.pngData(), let coverUrl = book.coverURL {
                self.kfImageCache.storeToDisk(coverData, forKey: coverUrl.absoluteString)
            }
            
            self.updateBook(book: book)
        }
        #endif
        return bookId
    }
    
    func convert(bookRealm: CalibreBookRealm) -> CalibreBook? {
//        let serverId = { () -> String in
//            let serverUrl = bookRealm.serverUrl ?? "."
//            if let username = bookRealm.serverUsername,
//               username.isEmpty == false {
//                return "\(username) @ \(serverUrl)"
//            } else {
//                return serverUrl
//            }
//        }()
        guard let serverUUID = bookRealm.serverUUID,
              let libraryName = bookRealm.libraryName,
              let library = calibreLibraries[CalibreLibraryRealm.PrimaryKey(serverUUID: serverUUID, libraryName: libraryName)] else { return nil }
        
        return convert(library: library, bookRealm: bookRealm)
    }
    
    func convert(library: CalibreLibrary, bookRealm: CalibreBookRealm) -> CalibreBook {
        let calibreBook = CalibreBook(managedObject: bookRealm, library: library)
        
        return calibreBook
    }
    
    func updateLibraryPluginColumnInfo(libraryId: String, columnInfo: CalibreLibraryPluginColumnInfo) -> CalibreLibrary? {
        guard calibreLibraries.contains(where: { $0.key == libraryId }) else { return nil }
        calibreLibraries[libraryId]?.pluginColumns[columnInfo.getID()] = columnInfo
        
        guard let library = calibreLibraries[libraryId] else { return nil }
        try? updateLibraryRealm(library: library, realm: self.realm)
        return library
    }
    
    func getCustomDictViewer() -> (Bool, URL?) {
        return (UserDefaults.standard.bool(forKey: Constants.KEY_DEFAULTS_MDICT_VIEWER_ENABLED),
            UserDefaults.standard.url(forKey: Constants.KEY_DEFAULTS_MDICT_VIEWER_URL)
        )
    }
    
    func getCustomDictViewerNew(library: CalibreLibrary) -> (Bool, URL?) {
        var result: (Bool, URL?) = (false, nil)
        guard let dsreaderHelperServer = queryServerDSReaderHelper(server: library.server),
              let pluginDictionaryViewer = library.pluginDictionaryViewerWithDefault,
              pluginDictionaryViewer.isEnabled() else { return result }

        let connector = DSReaderHelperConnector(calibreServerService: calibreServerService, server: library.server, dsreaderHelperServer: dsreaderHelperServer, goodreadsSync: CalibreLibraryGoodreadsSync())
        guard let endpoint = connector.endpointDictLookup() else { return result }
        result.1 = endpoint.url
        result.0 = result.1 != nil
        
        return result
    }
    
    func updateCustomDictViewer(enabled: Bool, value: String?) -> URL? {
        UserDefaults.standard.set(enabled, forKey: Constants.KEY_DEFAULTS_MDICT_VIEWER_ENABLED)
        guard let value = value else { return nil }
        let url = URL(string: value)
        UserDefaults.standard.set(url, forKey: Constants.KEY_DEFAULTS_MDICT_VIEWER_URL)
        return url
    }
    
    func getPreferredFormat() -> Format {
        return Format(rawValue: UserDefaults.standard.string(forKey: Constants.KEY_DEFAULTS_PREFERRED_FORMAT) ?? "" ) ?? defaultFormat
    }
    
    func getPreferredFormat(for book: CalibreBook) -> Format? {
        let selectedFormats = book.formats.filter { $0.value.selected == true }
        if selectedFormats.count == 1,
           let firstFormatRaw = selectedFormats.first?.key,
           let firstFormat = Format(rawValue: firstFormatRaw) {
            return firstFormat
        }
        if book.formats[getPreferredFormat().rawValue] != nil {
            return getPreferredFormat()
        } else if let format = book.formats.compactMap({ Format(rawValue: $0.key) }).first {
            return format
        }
        return nil
    }
    
    func updatePreferredFormat(for format: Format) {
        UserDefaults.standard.setValue(format.rawValue, forKey: Constants.KEY_DEFAULTS_PREFERRED_FORMAT)
    }
    
    // user preferred -> default -> unsupported
    func getPreferredReader(for format: Format) -> ReaderType {
        return ReaderType(
            rawValue: UserDefaults.standard.string(forKey: "\(Constants.KEY_DEFAULTS_PREFERRED_READER_PREFIX)\(format.rawValue)") ?? ""
        ) ?? formatReaderMap[format]?.first ?? ReaderType.UNSUPPORTED
    }
    
    func updatePreferredReader(for format: Format, with reader: ReaderType) {
        UserDefaults.standard.setValue(reader.rawValue, forKey: "\(Constants.KEY_DEFAULTS_PREFERRED_READER_PREFIX)\(format.rawValue)")
    }
    
    func addServer(server: CalibreServer, libraries: [CalibreLibrary]) {
        libraries.forEach {
            do {
                try updateLibraryRealm(library: $0, realm: self.realm)
                calibreLibraries[$0.id] = $0
            } catch {
                
            }
        }
        
        do {
            try updateServerRealm(server: server)
            calibreServers[server.id] = server
        } catch {
            
        }
    }
    
    func updateServerRealm(server: CalibreServer) throws {
        let serverRealm = CalibreServerRealm()
        serverRealm.primaryKey = server.uuid.uuidString
        serverRealm.name = server.name
        serverRealm.baseUrl = server.baseUrl
        serverRealm.hasPublicUrl = server.hasPublicUrl
        serverRealm.publicUrl = server.publicUrl
        serverRealm.hasAuth = server.hasAuth
        serverRealm.username = server.username
        serverRealm.password = server.password
        serverRealm.defaultLibrary = server.defaultLibrary
        serverRealm.lastLibrary = server.lastLibrary
        try realm.write {
            realm.add(serverRealm, update: .all)
        }
    }
    
    func updateLibraryRealm(library: CalibreLibrary, realm: Realm) throws {
        let libraryRealm = CalibreLibraryRealm()
        libraryRealm.key = library.key
        libraryRealm.name = library.name
        libraryRealm.serverUUID = library.server.uuid.uuidString
        
        libraryRealm.customColumns.append(objectsIn: library.customColumnInfos.values.map { $0.managedObject() })
        
        library.pluginColumns.forEach {
            if let plugin = $0.value as? CalibreLibraryDSReaderHelper {
                libraryRealm.pluginDSReaderHelper = plugin.managedObject()
            }
            if let plugin = $0.value as? CalibreLibraryReadingPosition {
                libraryRealm.pluginReadingPosition = plugin.managedObject()
            }
            if let plugin = $0.value as? CalibreLibraryDictionaryViewer {
                libraryRealm.pluginDictionaryViewer = plugin.managedObject()
            }
            if let plugin = $0.value as? CalibreLibraryGoodreadsSync {
                libraryRealm.pluginGoodreadsSync = plugin.managedObject()
            }
            if let plugin = $0.value as? CalibreLibraryCountPages {
                libraryRealm.pluginCountPages = plugin.managedObject()
            }
        }
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
            try? updateLibraryRealm(library: library, realm: realm)
        }
    }
    
    func restoreLibrary(libraryId: String) {
        calibreLibraries[libraryId]?.hidden = false
        calibreLibraries[libraryId]?.lastModified = Date(timeIntervalSince1970: 0)
        if let library = calibreLibraries[libraryId] {
            try? updateLibraryRealm(library: library, realm: realm)
        }
    }
    
    func updateBook(book: CalibreBook) {
        updateBookRealm(book: book, realm: (try? Realm(configuration: self.realmConf)) ?? self.realm)
        
        if readingBook?.inShelfId == book.inShelfId {
            readingBook = book
        }
        if book.inShelf {
            booksInShelf[book.inShelfId] = book
        }
    }
    
    func queryBookRealm(book: CalibreBook, realm: Realm) -> CalibreBookRealm? {
//        return realm.objects(CalibreBookRealm.self).filter(
//            NSPredicate(format: "id = %@ AND serverUrl = %@ AND serverUsername = %@ AND libraryName = %@",
//                        NSNumber(value: book.id),
//                        book.library.server.baseUrl,
//                        book.library.server.username,
//                        book.library.name
//            )
//        ).first
        
        return realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: CalibreBookRealm.PrimaryKey(serverUUID: book.library.server.uuid.uuidString, libraryName: book.library.name, id: book.id.description))
    }

    func queryLibraryBookRealmCount(library: CalibreLibrary, realm: Realm) -> Int {
        return realm.objects(CalibreBookRealm.self).filter(
            NSPredicate(format: "serverUUID = %@ AND libraryName = %@",
                        library.server.uuid.uuidString,
                        library.name
            )
        ).count
    }
    
    func updateBookRealm(book: CalibreBook, realm: Realm) {
        let bookRealm = book.managedObject()
        try? realm.write {
            realm.add(bookRealm, update: .modified)
        }
    }
    
    func removeFromRealm(book: CalibreBook) {
        removeFromRealm(for: CalibreBookRealm.PrimaryKey(serverUUID: book.library.server.uuid.uuidString, libraryName: book.library.name, id: book.id.description))
    }
    
    func removeFromRealm(for primaryKey: String) {
        guard let object = realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: primaryKey) else { return }
        
        try? realm.write {
            realm.delete(object)
        }
    }
    
    func queryServerDSReaderHelper(server: CalibreServer) -> CalibreServerDSReaderHelper? {
        guard let realm = Thread.isMainThread ? self.realm : try? Realm(configuration: self.realmConf) else { return nil }
        
        let objs = realm.objects(CalibreServerDSReaderHelperRealm.self).filter(
            NSPredicate(format: "id = %@", server.id)
        )
        guard objs.count > 0 else { return nil }
//        objs.forEach {
//            print("\(#function) \($0)")
//        }
        return CalibreServerDSReaderHelper(managedObject: objs.first!)
    }
    
    func updateServerDSReaderHelper(dsreaderHelper: CalibreServerDSReaderHelper, realm: Realm) {
        let obj = dsreaderHelper.managedObject()
        try? realm.write {
            realm.add(obj, update: .all)
        }
    }
    
    
    /// update server library infos,
    /// make sure libraries' server ids equal to serverId
    /// - Parameters:
    ///   - serverId: id of target server
    ///   - libraries: library list
    ///   - defaultLibrary: key of default library
    /// - TODO: update & remove
    func updateServerLibraryInfo(serverInfo: CalibreServerInfo) {
        guard let server = calibreServers[serverInfo.server.id] else { return }
        
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
                try updateLibraryRealm(library: calibreLibraries[libraryId]!, realm: self.realm)
            } catch {
                
            }
        }
        
        if server.defaultLibrary != serverInfo.defaultLibrary {
            calibreServers[server.id]!.defaultLibrary = serverInfo.defaultLibrary
            do {
                try updateServerRealm(server: calibreServers[server.id]!)
            } catch {
                
            }
        }
    }
    
    func shouldAutoUpdateGoodreads(library: CalibreLibrary) -> (CalibreServerDSReaderHelper, CalibreLibraryDSReaderHelper, CalibreLibraryGoodreadsSync)? {
        // must have dsreader helper info and enabled by server
        guard let dsreaderHelperServer = queryServerDSReaderHelper(server: library.server), dsreaderHelperServer.port > 0 else { return nil }
        guard let configuration = dsreaderHelperServer.configuration, let dsreader_helper_prefs = configuration.dsreader_helper_prefs, dsreader_helper_prefs.plugin_prefs.Options.goodreadsSyncEnabled else { return nil }
        
        // check if user disabled auto update
        guard let dsreaderHelperLibrary = library.pluginDSReaderHelperWithDefault, dsreaderHelperLibrary.isEnabled() else { return nil }
        
        // check if profile name exists
        guard let goodreadsSync = library.pluginGoodreadsSyncWithDefault, goodreadsSync.isEnabled() else { return nil }
        guard let goodreads_sync_prefs = configuration.goodreads_sync_prefs, goodreads_sync_prefs.plugin_prefs.Users.contains(where: { $0.key == goodreadsSync.profileName }) else { return nil }
        
        return (dsreaderHelperServer, dsreaderHelperLibrary, goodreadsSync)
    }
    
    func addToShelf(book: CalibreBook, formats: [Format]) {
        var book = book
        book.inShelf = true
        formats.forEach {
            book.formats[$0.rawValue]?.selected = true
        }
        
        updateBook(book: book)
        
        if let library = calibreLibraries[book.library.id],
           let goodreadsId = book.identifiers["goodreads"],
           let (dsreaderHelperServer, dsreaderHelperLibrary, goodreadsSync) = shouldAutoUpdateGoodreads(library: library),
           dsreaderHelperLibrary.autoUpdateGoodreadsBookShelf {
            let connector = DSReaderHelperConnector(calibreServerService: calibreServerService, server: library.server, dsreaderHelperServer: dsreaderHelperServer, goodreadsSync: goodreadsSync)
            let ret = connector.addToShelf(goodreads_id: goodreadsId, shelfName: "currently-reading")
        }
        
        calibreUpdatedSubject.send(.book(book))
    }
    
    func removeFromShelf(inShelfId: String) {
        if readingBook?.inShelfId == inShelfId {
            readingBook?.inShelf = false
//            NotificationCenter.default.post(Notification(name: .YABR_ReadingBookRemovedFromShelf))
        }
        
        guard var book = booksInShelf[inShelfId] else { return }
        book.inShelf = false

        updateBookRealm(book: book, realm: (try? Realm(configuration: self.realmConf)) ?? self.realm)
        
        booksInShelf.removeValue(forKey: inShelfId)
        
        if self.getLatestReadingPosition(book: book)?.id == deviceName,
           let library = calibreLibraries[book.library.id],
           let goodreadsId = book.identifiers["goodreads"],
           let (dsreaderHelperServer, dsreaderHelperLibrary, goodreadsSync) = shouldAutoUpdateGoodreads(library: library),
           dsreaderHelperLibrary.autoUpdateGoodreadsBookShelf {
            let connector = DSReaderHelperConnector(calibreServerService: calibreServerService, server: library.server, dsreaderHelperServer: dsreaderHelperServer, goodreadsSync: goodreadsSync)
            let ret = connector.removeFromShelf(goodreads_id: goodreadsId, shelfName: "currently-reading")
            
            if let position = getDeviceReadingPosition(book: book), position.lastProgress > 99 {
                connector.addToShelf(goodreads_id: goodreadsId, shelfName: "read")
            }
        }

        calibreUpdatedSubject.send(.deleted(book.inShelfId))
    }
    
    func startDownloadFormat(book: CalibreBook, format: Format, overwrite: Bool = false) -> Bool {
        return downloadService.startDownload(book, format: format, overwrite: overwrite)
    }
    
    func cancelDownloadFormat(book: CalibreBook, format: Format) {
        return downloadService.cancelDownload(book, format: format)
    }
    
    func pauseDownloadFormat(book: CalibreBook, format: Format) {
        return downloadService.pauseDownload(book, format: format)
    }
    
    func resumeDownloadFormat(book: CalibreBook, format: Format) -> Bool {
        let result = downloadService.resumeDownload(book, format: format)
        if !result {
            downloadService.cancelDownload(book, format: format)
        }
        return result
    }
    
    func startBatchDownload(books: [CalibreBook], formats: [String]) {
        books.forEach { book in
            let downloadFormats = formats.compactMap { format -> Format? in
                guard let f = Format(rawValue: format),
                      let formatInfo = book.formats[format],
                      formatInfo.serverSize > 0 else { return nil }
                return f
            }
            self.addToShelf(book: book, formats: downloadFormats)
        }
    }
    
    func clearCache(inShelfId: String) {
        guard let book = booksInShelf[inShelfId] else {
            return
        }
        
        book.formats.filter { $1.cached }.forEach {
            guard let format = Format(rawValue: $0.key) else { return }
            clearCache(book: book,  format: format)
        }
    }
    
    func addedCache(book: CalibreBook, format: Format) {
        guard var formatInfo = book.formats[format.rawValue] else { return }
        var newBook = book
        
        if let cacheInfo = getCacheInfo(book: newBook, format: format),
           let cacheMTime = cacheInfo.1 {
            print("cacheInfo: \(cacheInfo.0) \(cacheInfo.1!) vs \(formatInfo.serverSize) \(formatInfo.serverMTime)")
            formatInfo.cached = true
            formatInfo.cacheSize = cacheInfo.0
            formatInfo.cacheMTime = cacheMTime
        } else {
            formatInfo.cached = false
            formatInfo.cacheSize = 0
            formatInfo.cacheMTime = .distantPast
        }

        newBook.formats[format.rawValue] = formatInfo
        newBook.lastUpdated = .init()
        
        updateBook(book: newBook)

//        if newBook.inShelf == false {
//            addToShelf(newBook.inShelfId)
//        }
        
        if format == Format.EPUB {
            removeFolioCache(book: newBook, format: format)
        }
        
        refreshShelfMetadataV2(with: [book.library.server.id], for: [book.inShelfId], serverReachableChanged: true)
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
        var newBook = book
        
        newBook.formats[format.rawValue]?.cacheMTime = .distantPast
        newBook.formats[format.rawValue]?.cacheSize = 0
        newBook.formats[format.rawValue]?.cached = false
        newBook.formats[format.rawValue]?.selected = nil

        updateBook(book: newBook)
        
        if newBook.inShelf, newBook.formats.filter({ $1.cached }).isEmpty {
            removeFromShelf(inShelfId: newBook.inShelfId)
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
    
    
    func getSelectedReadingPosition(book: CalibreBook) -> BookDeviceReadingPosition? {
        return book.readPos.getPosition(selectedPosition)
    }
    
    func getDeviceReadingPosition(book: CalibreBook) -> BookDeviceReadingPosition? {
        var position = book.readPos.getPosition(deviceName)
//        position = nil
//
//        book.formats.filter { $0.value.cached }.forEach {
//            guard let format = Format(rawValue: $0.key),
//                  let bookPrefConfig = getBookPreferenceConfig(book: book, format: format),
//                  let bookPrefRealm = try? Realm(configuration: bookPrefConfig),
//                  let object = bookPrefRealm.object(ofType: CalibreBookLastReadPositionRealm.self, forPrimaryKey: deviceName),
//                  object.epoch > (position?.epoch ?? 0.0)
//            else { return }
//
//            position = BookDeviceReadingPosition(managedObject: object)
//        }
        
        return position
    }
    
    func getInitialReadingPosition(book: CalibreBook, format: Format, reader: ReaderType) -> BookDeviceReadingPosition {
        return BookDeviceReadingPosition(id: deviceName, readerName: reader.rawValue)
    }
    
    func getLatestReadingPosition(book: CalibreBook) -> BookDeviceReadingPosition? {
        var position = book.readPos.getDevices().first
//        position = nil
//        
//        position = book.formats.filter { $0.value.cached }.reduce(into: nil) { partialResult, format in
//            let lastEpoch = partialResult?.epoch ?? 0.0
//            guard let format = Format(rawValue: format.key),
//                  let bookPrefConfig = getBookPreferenceConfig(book: book, format: format),
//                  let bookPrefRealm = try? Realm(configuration: bookPrefConfig),
//                  let firstPosition = bookPrefRealm.objects(CalibreBookLastReadPositionRealm.self)
//                    .sorted(byKeyPath: "epoch", ascending: false)
//                    .filter({ $0.epoch > lastEpoch })
//                    .compactMap({ BookDeviceReadingPosition(managedObject: $0) })
//                    .first
//            else { return }
//            
//            partialResult = firstPosition
//        }
        
        return position
    }
    
    func getFurthestReadingPosition(book: CalibreBook) -> BookDeviceReadingPosition? {
        var position = book.readPos.getDevices().first
//        position = nil
//
//        position = book.formats.filter { $0.value.cached }.reduce(into: nil) { partialResult, format in
//            let lastProgress = partialResult?.lastProgress ?? 0.0
//            guard let format = Format(rawValue: format.key),
//                  let bookPrefConfig = getBookPreferenceConfig(book: book, format: format),
//                  let bookPrefRealm = try? Realm(configuration: bookPrefConfig),
//                  let firstPosition = bookPrefRealm.objects(CalibreBookLastReadPositionRealm.self)
//                    .sorted(byKeyPath: "pos_frac", ascending: false)
//                    .filter({ $0.pos_frac * 100 > lastProgress })
//                    .compactMap({ BookDeviceReadingPosition(managedObject: $0) })
//                    .first
//            else { return }
//
//            partialResult = firstPosition
//        }
        
        return position
    }
    
    func updateCurrentPosition(alertDelegate: AlertDelegate?) {
        guard let readingBook = self.readingBook,
              let updatedReadingPosition = getLatestReadingPosition(book: readingBook),
              let readerInfo = self.readerInfo
        else {
            return
        }
        
        defaultLog.info("pageNumber:  \(updatedReadingPosition.lastPosition[0])")
        defaultLog.info("pageOffsetX: \(updatedReadingPosition.lastPosition[1])")
        defaultLog.info("pageOffsetY: \(updatedReadingPosition.lastPosition[2])")
        
        refreshShelfMetadataV2(with: [readingBook.library.server.id], for: [readingBook.inShelfId], serverReachableChanged: true)
        
        if floor(updatedReadingPosition.lastProgress) > readerInfo.position.lastProgress || updatedReadingPosition.lastProgress < floor(readerInfo.position.lastProgress),
           let library = calibreLibraries[readingBook.library.id],
           let goodreadsId = readingBook.identifiers["goodreads"],
           let (dsreaderHelperServer, dsreaderHelperLibrary, goodreadsSync) = shouldAutoUpdateGoodreads(library: library),
           dsreaderHelperLibrary.autoUpdateGoodreadsProgress {
            let connector = DSReaderHelperConnector(calibreServerService: calibreServerService, server: library.server, dsreaderHelperServer: dsreaderHelperServer, goodreadsSync: goodreadsSync)
            connector.updateReadingProgress(goodreads_id: goodreadsId, progress: updatedReadingPosition.lastProgress)
            
            if goodreadsSync.isEnabled(), goodreadsSync.readingProgressColumnName.count > 1 {
                calibreServerService.updateMetadata(library: library, bookId: readingBook.id, metadata: [
                    [goodreadsSync.readingProgressColumnName, Int(updatedReadingPosition.lastProgress)]
                ])
            }
        }
        
    }
    
    /// used for removing position entries
    func updateReadingPosition(book: CalibreBook, alertDelegate: AlertDelegate) {
        self.updateBook(book: book)
        
        guard let pluginReadingPosition = calibreLibraries[book.library.id]?.pluginReadingPositionWithDefault, pluginReadingPosition.isEnabled() else {
            return
        }

        let ret = calibreServerService.updateBookReadingPosition(book: book, columnName: pluginReadingPosition.readingPositionCN, alertDelegate: alertDelegate) {
            // empty
        }
        if ret != 0 {
            updatingMetadataStatus = "Internal Error"
            updatingMetadata = false
            alertDelegate.alert(msg: updatingMetadataStatus)
        }
    }
    
    
    func goToPreviousBook() {
        //MARK: FIXME
//        if let curIndex = filteredBookList.firstIndex(of: currentBookId), curIndex > 0 {
//            currentBookId = filteredBookList[curIndex-1]
//        }
    }
    
    func goToNextBook() {
        //MARK: FIXME
//        if let curIndex = filteredBookList.firstIndex(of: selectedBookId ?? currentBookId), curIndex < filteredBookList.count - 1 {
//            currentBookId = filteredBookList[curIndex + 1]
//        }
    }
    
    func defaultReaderForDefaultFormat(book: CalibreBook) -> (Format, ReaderType) {
        if book.formats.contains(where: { $0.key == defaultFormat.rawValue }) {
            return (defaultFormat, formatReaderMap[defaultFormat]!.first!)
        } else {
            return book.formats.keys.compactMap {
                Format(rawValue: $0)
            }
            .reversed()
            .reduce((Format.UNKNOWN, ReaderType.UNSUPPORTED)) {
                ($1, formatReaderMap[$1]!.first!)
            }
        }
    }
    
    func formatOfReader(readerName: String) -> Format? {
        let formats = formatReaderMap.filter {
            $0.value.contains(where: { reader in reader.rawValue == readerName } )
        }
        return formats.first?.key
    }
    
    func prepareBookReading(book: CalibreBook) -> ReaderInfo {
        var candidatePositions = [BookDeviceReadingPosition]()

        //preference: device, latest, selected, any
        if let position = getDeviceReadingPosition(book: book) {
            candidatePositions.append(position)
        }
        if let position = getLatestReadingPosition(book: book) {
            candidatePositions.append(position)
        }
        if let position = getSelectedReadingPosition(book: book) {
            candidatePositions.append(position)
        }
//        candidatePositions.append(contentsOf: book.readPos.getDevices())
        if let format = getPreferredFormat(for: book) {
            candidatePositions.append(getInitialReadingPosition(book: book, format: format, reader: getPreferredReader(for: format)))
        }
        
        let formatReaderPairArray: [(Format, ReaderType, BookDeviceReadingPosition)] = candidatePositions.compactMap { position in
            guard let reader = ReaderType(rawValue: position.readerName), reader != .UNSUPPORTED else { return nil }
            let format = reader.format
            
            return (format, reader, position)
        }
        
        let formatReaderPair = formatReaderPairArray.first ?? (Format.UNKNOWN, ReaderType.UNSUPPORTED, BookDeviceReadingPosition.init(readerName: ReaderType.UNSUPPORTED.id))
        let savedURL = getSavedUrl(book: book, format: formatReaderPair.0) ?? URL(fileURLWithPath: "/invalid")
        let urlMissing = !FileManager.default.fileExists(atPath: savedURL.path)
        
        return ReaderInfo(deviceName: deviceName, url: savedURL, missing: urlMissing, format: formatReaderPair.0, readerType: formatReaderPair.1, position: formatReaderPair.2)
    }
    
    func prepareBookReading(url: URL, format: Format, readerType: ReaderType, position: BookDeviceReadingPosition) {
        let readerInfo = ReaderInfo(
            deviceName: deviceName,
            url: url,
            missing: false,
            format: format,
            readerType: readerType,
            position: position
        )
        self.readerInfo = readerInfo
    }
    
    func removeLibrary(libraryId: String, realm: Realm) -> Bool {
        guard let library = calibreLibraries[libraryId] else { return false }
        
        //remove cached book files
        let libraryBooksInShelf = booksInShelf.filter {
            $0.value.library.id == libraryId
        }
        libraryBooksInShelf.forEach {
            self.clearCache(inShelfId: $0.key)
            self.removeFromShelf(inShelfId: $0.key)     //just in case
        }
        
        //remove library info
        do {
            let predicate = NSPredicate(format: "serverUUID = %@ AND libraryName = %@", library.server.uuid.uuidString, library.name)
            var booksCached: [CalibreBookRealm] = realm.objects(CalibreBookRealm.self)
                .filter(predicate)
                .prefix(256)
                .map{ $0 }
            while booksCached.isEmpty == false {
                print("\(#function) will delete \(booksCached.count) entries of \(libraryId)")
                try realm.write {
                    realm.delete(booksCached)
                }
                booksCached = realm.objects(CalibreBookRealm.self)
                    .filter(predicate)
                    .prefix(256)
                    .map{ $0 }
            }
        } catch {
            return false
        }
        
        return true
    }
    
    func removeServer(serverId: String, realm: Realm) -> Bool {
        guard let server = calibreServers[serverId] else { return false }
        
        let libraries = calibreLibraries.filter {
            $0.value.server == server
        }
        
        DispatchQueue.main.async {
            libraries.forEach {
                self.hideLibrary(libraryId: $0.key)
            }
        }
        
        var isSuccess = true
        libraries.forEach {
            let result = removeLibrary(libraryId: $0.key, realm: realm)
            isSuccess = isSuccess && result
        }
        if !isSuccess {
            return false
        }
        
        //remove library info
        DispatchQueue.main.async {
            libraries.forEach {
                self.calibreLibraries.removeValue(forKey: $0.key)
            }
        }
        do {
            let serverLibraryRealms = realm.objects(CalibreLibraryRealm.self)
                .filter("serverUUID = %@", server.uuid.uuidString)
            try realm.write {
                realm.delete(serverLibraryRealms)
            }
        } catch {
            return false
        }
        
        //remove server
        DispatchQueue.main.async {
            self.calibreServers.removeValue(forKey: serverId)
        }
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
        
        return true
    }
    
    func removeDeleteBooksFromServer(server: CalibreServer) {
        librarySyncStatus.filter {
             $0.value.library.server.id == server.id && $0.value.del.count > 0
        }.forEach { lss in
            self.librarySyncStatus[lss.key]?.isSync = true
            var progress = 0
            let total = lss.value.del.count
            DispatchQueue.global(qos: .userInitiated).async {
                guard let realm = try? Realm(configuration: self.realmConf) else { return }
                
                try? realm.write {
                    lss.value.del.forEach { id in
                        if progress % 100 == 0 {
                            DispatchQueue.main.async {
                                self.librarySyncStatus[lss.key]?.msg = "Removing deleted \(progress) / \(total)"
                            }
                        }
                        
                        let primaryKey = CalibreBookRealm.PrimaryKey(
                            serverUUID: lss.value.library.server.uuid.uuidString,
                            libraryName: lss.value.library.name,
                            id: id.description)
                        
                        if let object = realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: primaryKey) {
                            realm.delete(object)
                        }
                        progress += 1
                        
                    }
                }
                
                DispatchQueue.main.async {
                    self.librarySyncStatus[lss.key]?.del.removeAll()
                    self.librarySyncStatus[lss.key]?.isSync = false
                    self.librarySyncStatus[lss.key]?.msg = nil
                }
            }
        }
        
        probeServersReachability(with: [server.id], updateLibrary: false, autoUpdateOnly: true, incremental: false)
    }
    
    func probeServersReachability(with serverIds: Set<String>, updateLibrary: Bool = false, autoUpdateOnly: Bool = true, incremental: Bool = true, disableAutoThreshold: Int = 0, completion: ((String) -> Void)? = nil) {
        guard calibreServerUpdating == false else { return }    //structural changing ongoing
        
        calibreServers.filter {
            $0.value.isLocal == false
        }.forEach { serverId, server in
            [true, false].forEach { isPublic in
                let infoId = serverId + " " + isPublic.description
                
                if calibreServerInfoStaging[infoId] == nil,
                   let url = URL(string: isPublic ? server.publicUrl : server.baseUrl) {
                    calibreServerInfoStaging[infoId] =
                        CalibreServerInfo(server: server, isPublic: isPublic, url: url, reachable: false, probing: false, errorMsg: "Waiting to connect", defaultLibrary: server.defaultLibrary, libraryMap: [:])
                }
            }
        }
        
        let probingList = calibreServerInfoStaging.filter {
            if serverIds.isEmpty {
                return true
            } else {
                return serverIds.contains($0.value.server.id)
            }
        }.sorted {
            if $0.value.reachable == $1.value.reachable {
                return $0.key < $1.key
            }
            return !$0.value.reachable  //put unreachable first
        }
        
        calibreServiceCancellable?.cancel()
        calibreServiceCancellable = probingList.publisher.flatMap { input -> AnyPublisher<CalibreServerInfo, Never> in
            self.calibreServerInfoStaging[input.key]?.probing = true
            self.calibreServerInfoStaging[input.key]?.errorMsg = "Connecting"
            return self.calibreServerService.probeServerReachabilityNew(serverInfo: input.value)
        }
        .collect()
        .eraseToAnyPublisher()
        .receive(on: DispatchQueue.main)
        .sink(receiveCompletion: { completion in
            switch(completion) {
            case .finished:
                break
            case .failure(_):
                break
            }
        }, receiveValue: { results in
            var serverReachableChanged = false
            
            results.forEach { newServerInfo in
                defer {
                    completion?(newServerInfo.server.id)
                }
                
                guard var serverInfo = self.calibreServerInfoStaging[newServerInfo.id] else { return }
                serverInfo.probing = false
                serverInfo.errorMsg = newServerInfo.errorMsg

                if newServerInfo.libraryMap.isEmpty {
                    serverReachableChanged = serverReachableChanged || (serverInfo.reachable != false)
                    serverInfo.reachable = false
                } else {
                    serverReachableChanged = serverReachableChanged || (serverInfo.reachable != newServerInfo.reachable)
                    serverInfo.reachable = newServerInfo.reachable
                    serverInfo.libraryMap = newServerInfo.libraryMap
                    serverInfo.defaultLibrary = newServerInfo.defaultLibrary
                }
                self.calibreServerInfoStaging[newServerInfo.id] = serverInfo
                
                guard updateLibrary else { return }
                //only auto adding new libraries upon self refreshing
                serverInfo.libraryMap.forEach { key, name in
                    let newLibrary = CalibreLibrary(server: serverInfo.server, key: key, name: name)
                    if self.calibreLibraries[newLibrary.id] == nil {
                        self.calibreLibraries[newLibrary.id] = newLibrary
                        try? self.updateLibraryRealm(library: newLibrary, realm: self.realm)
                    }
                }
            }
            
            self.refreshShelfMetadataV2(with: serverIds, serverReachableChanged: serverReachableChanged)
            
            if updateLibrary == true, autoUpdateOnly == false {
                let ids = self.calibreServers.filter {
                    $0.value.isLocal == false && ( serverIds.isEmpty || serverIds.contains($0.key) )
                }.map{ $0.key }
                if ids.isEmpty == false {
                    self.refreshServerDSHelperConfiguration(with: ids)
                }
            }
            
//            self.syncLibraries(
//                with: self.calibreServers.filter {
//                    $0.value.isLocal == false
//                }.map{ $0.key },
//                autoUpdateOnly: autoUpdateOnly,
//                incremental: incremental,
//                disableAutoThreshold: disableAutoThreshold
//            )
            let serverIds = self.calibreServers.filter { $0.value.isLocal == false }.map{ $0.key }
            self.calibreLibraries.filter {
                serverIds.contains( $0.value.server.id )
            }.forEach { id, library in
                self.syncLibrarySubject.send(
                    .init(
                        library: library,
                        autoUpdateOnly: autoUpdateOnly,
                        incremental: incremental,
                        disableAutoThreshold: disableAutoThreshold
                    )
                )
            }
        })
    }
    
    func isServerReachable(server: CalibreServer, isPublic: Bool) -> Bool? {
        return calibreServerInfoStaging.filter {
            $1.server.id == server.id && $1.isPublic == isPublic
        }.first?.value.reachable
    }
    
    func getServerInfo(server: CalibreServer) -> CalibreServerInfo? {
        let serverInfos = calibreServerInfoStaging.filter { $1.server.id == server.id }
        if let reachable = serverInfos.filter({ $1.reachable }).first {
            return reachable.value
        } else {
            return serverInfos.first?.value
        }
    }
    
    func refreshShelfMetadataV2(with serverIds: Set<String> = [], for bookInShelfIds: Set<String> = [], serverReachableChanged: Bool) {
        shelfRefreshCancellable?.cancel()
        
        let refreshTasks = booksInShelf.values
            .filter { serverIds.isEmpty || serverIds.contains($0.library.server.id) }
            .reduce(into: [CalibreLibrary: [CalibreBook]]()) { partialResult, book in
                guard bookInShelfIds.isEmpty || bookInShelfIds.contains(book.inShelfId) else { return }
                if partialResult[book.library] == nil {
                    partialResult[book.library] = []
                }
                partialResult[book.library]?.append(book)
            }
            .compactMap { calibreServerService.buildBooksMetadataTask(library: $0.0, books: $0.1) }
        
        if serverReachableChanged && refreshTasks.isEmpty {
            calibreUpdatedSubject.send(.shelf)
            return
        }
        
        shelfRefreshCancellable = refreshTasks.publisher
            .flatMap { task in
                self.calibreServerService.getBooksMetadata(task: task)
            }
            .flatMap { task in
                self.calibreServerService.getAnnotations(task: task)
            }
            .subscribe(on: DispatchQueue.global(qos: .userInitiated))
            .collect()
            .eraseToAnyPublisher()
            .sink(receiveCompletion: { completion in
                switch completion {
                case .finished:
                    self.defaultLog.info("Refresh Finished")
                case .failure(let error):
                    self.defaultLog.info("Refresh Failure \(error.localizedDescription)")
                }
            }, receiveValue: { tasks in
                let decoder = JSONDecoder()
                guard let realm = try? Realm(configuration: self.realmConf) else { return }
                
                var updated = 0
                tasks.forEach { result in
                    guard let entries = result.booksMetadataEntry,
                          let json = result.booksMetadataJSON else {
                              print("getBookMetadataCancellable nildata \(result.library.name)")
                              return
                          }
                    
                    let serverUUID = result.library.server.uuid.uuidString
                    let libraryName = result.library.name
                    
                    try? realm.write {
                        result.books.forEach { id in
                            guard let obj = realm.object(
                                ofType: CalibreBookRealm.self,
                                forPrimaryKey: CalibreBookRealm.PrimaryKey(serverUUID: serverUUID, libraryName: libraryName, id: id)) else { return }
                            guard let entryOptional = entries[id],
                                  let entry = entryOptional,
                                  let root = json[id] as? NSDictionary else {
                                      // null data, treat as delted, update lastSynced to lastModified to prevent further actions
                                      obj.lastSynced = obj.lastModified
                                      return
                                  }
                            
                            let needProcess = floor(obj.lastModified.timeIntervalSince1970) != floor(parseLastModified(entry.last_modified)?.timeIntervalSince1970 ?? 0)
                            
                            defer {
                                let newBook = self.convert(library: result.library, bookRealm: obj)
                                newBook.formats.forEach {
                                    guard let format = Format(rawValue: $0.key), $0.value.cached else { return }
                                    readPosToLastReadPosition(book: newBook, format: format, formatInfo: $0.value)
                                }
                                
                                if needProcess {
                                    DispatchQueue.main.async {
                                        self.booksInShelf[newBook.inShelfId] = newBook
                                    }
                                }
                            }
                            
                            guard needProcess else { return }
                            
                            self.calibreServerService.handleLibraryBookOne(library: result.library, bookRealm: obj, entry: entry, root: root)
                            updated += 1
                            self.defaultLog.info("Refreshed \(obj.id) \(result.library.id)")
                        }
                    }
                    
                    do {
                        guard let annotationsData = result.annotationsData
                        else { return }
                        
                        let annotationsResult = try JSONDecoder().decode([String:CalibreBookAnnotationsResult].self, from: annotationsData)
                        
                        annotationsResult.forEach { entry in
//                            print("\(#function) annotationEntry=\(entry)")
                            
                            let keySplit = entry.key.split(separator: ":")
                            guard keySplit.count == 2,
                                  let bookId = Int32(keySplit[0]),
                                  let format = Format(rawValue: String(keySplit[1]))
                            else {
                                return
                            }
                            
                            guard let book = self.booksInShelf[CalibreBook(id: bookId, library: result.library).inShelfId]
                            else { return }
                            
                            book.readPos.positions(added: entry.value.last_read_positions).forEach {
                                guard let task = self.calibreServerService.buildSetLastReadPositionTask(
                                    library: result.library,
                                    bookId: bookId,
                                    format: format,
                                    entry: $0
                                ) else { return }
                                self.setLastReadPositionSubject.send(task)
                            }
                            
                            var highlightPending = [CalibreBookAnnotationHighlightEntry]()
                            var bookmarkPending = [CalibreBookAnnotationBookmarkEntry]()
                            
                            if book.readPos.highlights(added: entry.value.annotations_map.highlight ?? []) > 0 {
                                let highlights = book.readPos.highlights(excludeRemoved: false).compactMap {
                                    $0.toCalibreBookAnnotationHighlightEntry()
                                }
                                highlightPending.append(contentsOf: highlights)
                            }
                            
                            if book.readPos.bookmarks(added: entry.value.annotations_map.bookmark ?? []) > 0 {
                                let bookmarks = book.readPos.bookmarks().map { $0.toCalibreBookAnnotationBookmarkEntry() }
                                bookmarkPending.append(contentsOf: bookmarks)
                            }
                             
                            if highlightPending.isEmpty == false || bookmarkPending.isEmpty == false,
                               let task = self.calibreServerService.buildUpdateAnnotationsTask(
                                library: result.library, bookId: bookId, format: format, highlights: highlightPending, bookmarks: bookmarkPending
                               ) {
                                self.updateAnnotationsSubject.send(task)
                            }
                        }
                    } catch {
                        print("\(#function) annotationEntry error=\(error)")
                    }
                }
                
                if updated > 0 || serverReachableChanged {
                    self.calibreUpdatedSubject.send(.shelf)
                }
            })
    }
    
    func refreshServerDSHelperConfiguration(with serverIds: [String]) {
        dshelperRefreshCancellable?.cancel()
        
        dshelperRefreshCancellable = serverIds.publisher.flatMap { serverId -> AnyPublisher<(id: String, port: Int, data: Data), URLError> in
            guard let server = self.calibreServers[serverId],
                  let dsreaderHelperServer = self.queryServerDSReaderHelper(server: server),
                  let publisher = DSReaderHelperConnector(calibreServerService: self.calibreServerService, server: server, dsreaderHelperServer: dsreaderHelperServer, goodreadsSync: nil).refreshConfiguration()
            else {
                return Just((id: serverId, port: 0, data: Data())).setFailureType(to: URLError.self).eraseToAnyPublisher()
            }
            
            return publisher
        }
        .sink(receiveCompletion: { completion in
            
        }, receiveValue: { task in
            let decoder = JSONDecoder()
            var config: CalibreDSReaderHelperConfiguration? = nil
            do {
                config = try decoder.decode(CalibreDSReaderHelperConfiguration.self, from: task.data)
            } catch {
                print(error)
            }
            print("\(#function) \(task.id) \(task.port)")
            if let config = config, config.dsreader_helper_prefs != nil, let realm = try? Realm(configuration: self.realmConf) {
                let dsreaderHelperServer = CalibreServerDSReaderHelper(id: task.id, port: task.port, configurationData: task.data, configuration: config)
                
                self.updateServerDSReaderHelper(dsreaderHelper: dsreaderHelperServer, realm: realm)
            }
        })
    }
    
    func syncLibraries(with serverIds: [String], autoUpdateOnly: Bool, incremental: Bool, disableAutoThreshold: Int) {
        syncLibrariesIncrementalCancellable?.cancel()
        
        syncLibrariesIncrementalCancellable = calibreLibraries.filter {
            serverIds.contains( $0.value.server.id )
        }
        .map { $0.value }
        .publisher
        .flatMap { library -> AnyPublisher<CalibreSyncLibraryResult, Never> in
            guard (self.librarySyncStatus[library.id]?.isSync ?? false) == false else {
                print("\(#function) isSync \(library.id)")
                return Just(
                    CalibreSyncLibraryResult(
                        request: .init(
                            library: library,
                            autoUpdateOnly: autoUpdateOnly,
                            incremental: incremental,
                            disableAutoThreshold: disableAutoThreshold
                        ),
                        result: ["just_syncing":[:]]
                    )
                ).setFailureType(to: Never.self).eraseToAnyPublisher()
            }
            
            DispatchQueue.main.sync {
                if self.librarySyncStatus[library.id] == nil {
                    self.librarySyncStatus[library.id] = .init(library: library, isSync: true)
                } else {
                    self.librarySyncStatus[library.id]?.isSync = true
                    self.librarySyncStatus[library.id]?.isError = false
                    self.librarySyncStatus[library.id]?.msg = ""
                    self.librarySyncStatus[library.id]?.cnt = nil
                    self.librarySyncStatus[library.id]?.upd = nil
                    self.librarySyncStatus[library.id]?.del.removeAll()
                }
            }
            
            guard library.hidden == false,
                  autoUpdateOnly == false || library.autoUpdate else {
                print("\(#function) autoUpdate \(library.id)")
                return Just(
                    CalibreSyncLibraryResult(
                        request: .init(
                            library: library,
                            autoUpdateOnly: autoUpdateOnly,
                            incremental: incremental,
                            disableAutoThreshold: disableAutoThreshold
                        ), result: ["auto_update":[:]]
                    )
                ).setFailureType(to: Never.self).eraseToAnyPublisher()
            }
            
            print("\(#function) startSync \(library.id)")

            return self.calibreServerService.getCustomColumnsPublisher(
                request: .init(
                    library: library,
                    autoUpdateOnly: autoUpdateOnly,
                    incremental: incremental,
                    disableAutoThreshold: disableAutoThreshold
                )
            )
        }
        .flatMap { result -> AnyPublisher<CalibreSyncLibraryResult, Never> in
            self.calibreServerService.getLibraryCategoriesPublisher(resultPrev: result)
        }
        .flatMap { customColumnResult -> AnyPublisher<CalibreSyncLibraryResult, Never> in
            print("\(#function) syncLibraryPublisher \(customColumnResult.request.library.id) \(customColumnResult.categories)")
            guard customColumnResult.result["just_syncing"] == nil,
                  customColumnResult.result["auto_update"] == nil else {
                return Just(customColumnResult).setFailureType(to: Never.self).eraseToAnyPublisher()
            }
            var filter = ""     //  "last_modified:>2022-02-20T00:00:00.000000+00:00"
            if incremental,
               let realm = try? Realm(configuration: self.realmConf),
               let libraryRealm = realm.object(
                ofType: CalibreLibraryRealm.self,
                forPrimaryKey: CalibreLibraryRealm.PrimaryKey(
                    serverUUID: customColumnResult.request.library.server.uuid.uuidString,
                    libraryName: customColumnResult.request.library.name)
               ) {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions.formUnion(.withColonSeparatorInTimeZone)
                formatter.timeZone = .current
                let lastModifiedStr = formatter.string(from: libraryRealm.lastModified)
                filter = "last_modified:\">=\(lastModifiedStr)\""
            }
            print("\(#function) syncLibraryPublisher \(customColumnResult.request.library.id) \(filter)")
            
            var customColumnResult = customColumnResult
            customColumnResult.isIncremental = incremental
            return self.calibreServerService.syncLibraryPublisher(resultPrev: customColumnResult, filter: filter)
        }
        .subscribe(on: DispatchQueue.global())
        .sink { complete in
            
        } receiveValue: { results in
            if disableAutoThreshold > 0,
               results.list.book_ids.count > disableAutoThreshold {
                DispatchQueue.main.async {
                    self.librarySyncStatus[results.request.library.id]?.isSync = false
                    self.librarySyncStatus[results.request.library.id]?.isError = true
                    self.librarySyncStatus[results.request.library.id]?.msg = "Large Library, Must Enable Manually"
                    self.librarySyncStatus[results.request.library.id]?.cnt = results.list.book_ids.count

                    self.calibreLibraries[results.request.library.id]?.autoUpdate = false
                    if let library = self.calibreLibraries[results.request.library.id] {
                        try? self.updateLibraryRealm(library: library, realm: self.realm)
                    }
                }
                return
            }
            self.syncLibrariesSinkValue(results: results)
        }
    }
    
    func syncLibrariesSinkValue(results: CalibreSyncLibraryResult) {
        var library = results.request.library
        let serverUUID = library.server.uuid.uuidString
        
        print("\(#function) receiveValue \(library.id) count=\(results.list.book_ids.count)")
        
        var isError = false
        var bookCount = 0
        var bookNeedUpdateCount = 0
        var bookDeleted = [Int32]()
        
        defer {
            DispatchQueue.main.async {
                results.categories.filter {
                    $0.is_category //&& $0.name != "Authors"
                }.forEach { category in
                    self.libraryCategorySubject.send(
                        .init(
                            library: library,
                            category: category,
                            reqId: (self.calibreLibraryCategories[.init(libraryId: library.id, categoryName: category.name)]?.reqId ?? 0) + 1,
                            offset: 0,
                            num: 0
                        )
                    )   //get total_num
                }
                
                self.librarySyncStatus[library.id]?.isSync = false
                self.librarySyncStatus[library.id]?.isError = isError
                if isError, results.errmsg.isEmpty == false {
                    self.librarySyncStatus[library.id]?.msg = results.errmsg
                }
                self.librarySyncStatus[library.id]?.cnt = bookCount
                self.librarySyncStatus[library.id]?.upd = bookNeedUpdateCount
                self.librarySyncStatus[library.id]?.del.formUnion(bookDeleted)
                
//                print("\(#function) finishSync \(library.id) \(self.librarySyncStatus[library.id].debugDescription)")
            }
        }
        
        guard let realm = try? Realm(configuration: self.realmConf) else {
            isError = true
            return
        }
        
        defer {
            let objects = realm.objects(CalibreBookRealm.self).filter(
                "serverUUID = %@ AND libraryName = %@", library.server.uuid.uuidString, library.name
            )
            bookCount = objects.count
            
            let objectsNeedUpdate = objects.filter("lastSynced < lastModified")
            bookNeedUpdateCount = objectsNeedUpdate.count
            
            DispatchQueue.main.async {
                self.calibreLibraries[library.id] = library
                try? self.updateLibraryRealm(library: library, realm: self.realm)
            }
        }
        
        guard results.result["error"] == nil else {
            isError = true
            return
        }
        
        guard results.result["just_syncing"] == nil else { return }
        guard results.result["auto_update"] == nil else { return }
        
        
        if let result = results.result["result"] {
            library.customColumnInfos = result
            
            DispatchQueue.main.async {
                self.librarySyncStatus[library.id]?.msg = "Success"
            }
        }
        
        guard results.list.book_ids.first != -1 else {
            isError = true
            return
        }
        
        let dateFormatter = ISO8601DateFormatter()
        let dateFormatter2 = ISO8601DateFormatter()
        dateFormatter2.formatOptions.formUnion(.withFractionalSeconds)
        
        var writeSucc = true
        var progress = 0
        let total = results.list.book_ids.count
        results.list.book_ids.chunks(size: 1024).forEach { chunk in
            do {
                DispatchQueue.main.async {
                    self.librarySyncStatus[library.id]?.msg = "\(progress) / \(total)"
                }
                try realm.write {
                    chunk.map {(i:$0, s:$0.description)}.forEach { id in
                        guard let lastModifiedStr = results.list.data.last_modified[id.s]?.v,
                              let lastModified = dateFormatter.date(from: lastModifiedStr) ?? dateFormatter2.date(from: lastModifiedStr) else { return }
                        realm.create(CalibreBookRealm.self, value: [
                            "primaryKey": CalibreBookRealm.PrimaryKey(serverUUID: serverUUID, libraryName: library.name, id: id.s),
                            "serverUUID": serverUUID,
                            "libraryName": library.name,
                            "lastModified": lastModified,
                            "id": id.i
                        ], update: .modified)
                    }
                }
                progress += chunk.count
            } catch {
                writeSucc = false
            }
        }
        defer {
            let objects = realm.objects(CalibreBookRealm.self).filter(
                "serverUUID = %@ AND libraryName = %@", library.server.uuid.uuidString, library.name
            )
            if writeSucc == true, results.isIncremental == false {
                bookDeleted = objects.filter {
                    $0.inShelf == false && results.list.data.last_modified[$0.id.description] == nil
                }
                .map { $0.id }
            }
        }
        
        if writeSucc,
           let lastId = results.list.book_ids.last,
           lastId > 0,
           let lastModifiedStr = results.list.data.last_modified[lastId.description]?.v,
           let lastModified = dateFormatter.date(from: lastModifiedStr) ?? dateFormatter2.date(from: lastModifiedStr) {
            print("\(#function) updateLibraryLastModified \(library.name) \(library.lastModified) -> \(lastModified)")
            library.lastModified = lastModified
            
            DispatchQueue.main.async {
                self.librarySyncStatus[library.id]?.msg = "Success"
            }
        }
        
        self.trySendGetBooksMetadataTask(library: library)
    }
    
    func trySendGetBooksMetadataTask(library: CalibreLibrary) {
        guard let realm = try? Realm(configuration: self.realmConf) else {
            return
        }
        guard self.librarySyncStatus[library.id]?.isUpd == false else { return }
        guard let hidden = self.calibreLibraries[library.id]?.hidden, hidden == false else { return }
        
        DispatchQueue.main.sync {
            self.librarySyncStatus[library.id]?.isUpd = true
        }
        
        let chunk = realm.objects(CalibreBookRealm.self).filter(
            "lastSynced < lastModified AND serverUUID = %@ AND libraryName = %@", library.server.uuid.uuidString, library.name
        )
        .sorted(byKeyPath: "lastModified", ascending: false)
        .map { $0.id }
        .filter { self.librarySyncStatus[library.id]?.err.contains($0) == false }
        .prefix(256)
        
        guard chunk.isEmpty == false else {
            DispatchQueue.main.sync {
                self.librarySyncStatus[library.id]?.isUpd = false
            }
            return
        }
        print("\(#function) prepareGetBooksMetadata \(library.name) \(chunk.count)")
        if let task = calibreServerService.buildBooksMetadataTask(library: library, books: chunk.map{ CalibreBook(id: $0, library: library) }) {
            getBooksMetadataSubject.send(task)
        }
    }
    
    func registerSyncLibraryCancellable() {
        syncLibrarySubject
            .receive(on: DispatchQueue.global())
            .flatMap { request -> AnyPublisher<CalibreSyncLibraryResult, Never> in
                let library = request.library
                let autoUpdateOnly = request.autoUpdateOnly
                guard (self.librarySyncStatus[library.id]?.isSync ?? false) == false else {
                    print("\(#function) isSync \(library.id)")
                    return Just(CalibreSyncLibraryResult(request: request, result: ["just_syncing":[:]]))
                        .setFailureType(to: Never.self).eraseToAnyPublisher()
                }
                
                DispatchQueue.main.sync {
                    if self.librarySyncStatus[library.id] == nil {
                        self.librarySyncStatus[library.id] = .init(library: library, isSync: true)
                    } else {
                        self.librarySyncStatus[library.id]?.isSync = true
                        self.librarySyncStatus[library.id]?.isError = false
                        self.librarySyncStatus[library.id]?.msg = ""
                        self.librarySyncStatus[library.id]?.cnt = nil
                        self.librarySyncStatus[library.id]?.upd = nil
                        self.librarySyncStatus[library.id]?.del.removeAll()
                    }
                }
                
                guard library.hidden == false,
                      autoUpdateOnly == false || library.autoUpdate else {
                    print("\(#function) autoUpdate \(library.id)")
                    return Just(CalibreSyncLibraryResult(request: request, result: ["auto_update":[:]]))
                        .setFailureType(to: Never.self).eraseToAnyPublisher()
                }
                
                print("\(#function) startSync \(library.id)")

                return self.calibreServerService.getCustomColumnsPublisher(request: request)
            }
            .flatMap { result -> AnyPublisher<CalibreSyncLibraryResult, Never> in
                self.calibreServerService.getLibraryCategoriesPublisher(resultPrev: result)
            }
            .flatMap { customColumnResult -> AnyPublisher<CalibreSyncLibraryResult, Never> in
                print("\(#function) syncLibraryPublisher \(customColumnResult.request.library.id) \(customColumnResult.categories)")
                guard customColumnResult.result["just_syncing"] == nil,
                      customColumnResult.result["auto_update"] == nil else {
                    return Just(customColumnResult).setFailureType(to: Never.self).eraseToAnyPublisher()
                }
                var filter = ""     //  "last_modified:>2022-02-20T00:00:00.000000+00:00"
                if customColumnResult.request.incremental,
                   let realm = try? Realm(configuration: self.realmConf),
                   let libraryRealm = realm.object(
                    ofType: CalibreLibraryRealm.self,
                    forPrimaryKey: CalibreLibraryRealm.PrimaryKey(
                        serverUUID: customColumnResult.request.library.server.uuid.uuidString,
                        libraryName: customColumnResult.request.library.name)
                   ) {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions.formUnion(.withColonSeparatorInTimeZone)
                    formatter.timeZone = .current
                    let lastModifiedStr = formatter.string(from: libraryRealm.lastModified)
                    filter = "last_modified:\">=\(lastModifiedStr)\""
                }
                print("\(#function) syncLibraryPublisher \(customColumnResult.request.library.id) \(filter)")
                
                var customColumnResult = customColumnResult
                customColumnResult.isIncremental = customColumnResult.request.incremental
                return self.calibreServerService.syncLibraryPublisher(resultPrev: customColumnResult, filter: filter)
            }
            .subscribe(on: DispatchQueue.global())
            .sink { complete in
                
            } receiveValue: { results in
                if results.request.disableAutoThreshold > 0,
                   results.list.book_ids.count > results.request.disableAutoThreshold {
                    DispatchQueue.main.async {
                        self.librarySyncStatus[results.request.library.id]?.isSync = false
                        self.librarySyncStatus[results.request.library.id]?.isError = true
                        self.librarySyncStatus[results.request.library.id]?.msg = "Large Library, Must Enable Manually"
                        self.librarySyncStatus[results.request.library.id]?.cnt = results.list.book_ids.count

                        self.calibreLibraries[results.request.library.id]?.autoUpdate = false
                        if let library = self.calibreLibraries[results.request.library.id] {
                            try? self.updateLibraryRealm(library: library, realm: self.realm)
                        }
                    }
                    return
                }
                self.syncLibrariesSinkValue(results: results)
            }.store(in: &calibreCancellables)
    }
    
    func registerGetBooksMetadataCancellable() {
        getBooksMetadataSubject.flatMap { task in
            self.calibreServerService.getBooksMetadata(task: task)
        }
        .subscribe(on: DispatchQueue.global())
        .sink(receiveCompletion: { completion in
            
            print("getBookMetadataCancellable error \(completion)")
        }, receiveValue: { result in
//            print("getBookMetadataCancellable response \(result.response)")
            
            let decoder = JSONDecoder()
            guard let realm = try? Realm(configuration: self.realmConf) else { return }
            let serverUUID = result.library.server.uuid.uuidString
            let libraryName = result.library.name
            do {
                guard let data = result.data else {
                    print("getBookMetadataCancellable nildata \(result.library.name)")
                    return
                }
                let entries = try decoder.decode([String:CalibreBookEntry?].self, from: data)
                let json = try JSONSerialization.jsonObject(with: data, options: []) as? NSDictionary
                
                try realm.write {
                    result.books.forEach { id in
                        guard let obj = realm.object(
                                ofType: CalibreBookRealm.self,
                                forPrimaryKey: CalibreBookRealm.PrimaryKey(serverUUID: serverUUID, libraryName: libraryName, id: id)
                        ) else { return }
                        guard let entryOptional = entries[id],
                              let entry = entryOptional,
                              let root = json?[id] as? NSDictionary else {
                            // null data, treat as delted, update lastSynced to lastModified to prevent further actions
                            obj.lastSynced = obj.lastModified
                            return
                        }
                        
                        self.calibreServerService.handleLibraryBookOne(library: result.library, bookRealm: obj, entry: entry, root: root)
                    }
                }
                DispatchQueue.main.sync {
                    if let upd = self.librarySyncStatus[result.library.id]?.upd {
                        self.librarySyncStatus[result.library.id]?.upd = upd - result.books.count
                    }
                    self.librarySyncStatus[result.library.id]?.isUpd = false
                }
                
                self.trySendGetBooksMetadataTask(library: result.library)
                
                print("getBookMetadataCancellable count \(result.library.name) \(entries.count)")
            } catch let DecodingError.keyNotFound(key, context) {
                print("getBookMetadataCancellable decode keyNotFound \(result.library.name) \(key) \(context) \(result.data?.count ?? -1)")
                if key.stringValue == "path",
                   let firstCodingPath = context.codingPath.first,
                   let bookId = Int32(firstCodingPath.stringValue), bookId > 0 {
                    DispatchQueue.main.sync {
                        self.librarySyncStatus[result.library.id]?.err.insert(bookId)
                        self.librarySyncStatus[result.library.id]?.isUpd = false
                    }
                    self.trySendGetBooksMetadataTask(library: result.library)
                }
            } catch {
                print("getBookMetadataCancellable decode \(result.library.name) \(error) \(result.data?.count ?? -1)")
            }
        }).store(in: &calibreCancellables)
    }
    
    func registerSetLastReadPositionCancellable() {
        setLastReadPositionSubject
            .eraseToAnyPublisher()
            .flatMap { task in
                return self.calibreServerService.setLastReadPositionByTask(task: task)
            }
            .subscribe(on: DispatchQueue.global())
            .sink(receiveValue: { output in
                print("\(#function) output=\(output)")
            }).store(in: &calibreCancellables)
    }
    
    func registerUpdateAnnotationsCancellable() {
        updateAnnotationsSubject
            .eraseToAnyPublisher()
            .flatMap { task -> AnyPublisher<CalibreBookUpdateAnnotationsTask, Never> in
                self.logStartCalibreActivity(type: "Update Annotations", request: task.urlRequest, startDatetime: task.startDatetime, bookId: task.bookId, libraryId: task.library.id)
                return self.calibreServerService.updateAnnotationByTask(task: task)
            }
            .subscribe(on: DispatchQueue.global())
            .sink(
                receiveCompletion: { completion in
                    print("updateAnnotations \(completion)")
//                    switch completion {
//                    case .finished:
//                        self.logFinishCalibreActivity(type: "Update Annotations", request: urlRequest, startDatetime: startDatetime, finishDatetime: Date(), errMsg: "Empty Result")
//                        break
//                    case .failure(let error):
//                        self.logFinishCalibreActivity(type: "Update Annotations", request: urlRequest, startDatetime: startDatetime, finishDatetime: Date(), errMsg: error.localizedDescription)
//                        break
//                    }
                },
                receiveValue: { task in
//                    print("updateAnnotations count=\(results.count)")
//                    results.forEach { result in
//                        print("updateAnnotations \(result)")
//                    }
                    var logErrMsg = "Unknown"
                    if let httpUrlResponse = task.urlResponse as? HTTPURLResponse {
                        logErrMsg = "HTTP \(httpUrlResponse.statusCode)"
                    }
                    self.logFinishCalibreActivity(type: "Update Annotations", request: task.urlRequest, startDatetime: task.startDatetime, finishDatetime: Date(), errMsg: logErrMsg)
                }
            ).store(in: &calibreCancellables)
    }
    
    func registerBookReaderClosedCancellable() {
        bookReaderClosedSubject.sink { subject in
            let book = subject.book
            let lastPosition = subject.position
            
            self.refreshShelfMetadataV2(with: [book.library.server.id], for: [book.inShelfId], serverReachableChanged: true)
            
            guard let updatedReadingPosition = book.readPos.getDevices().first
            else { return }
            
            if floor(updatedReadingPosition.lastProgress) > lastPosition.lastProgress || updatedReadingPosition.lastProgress < floor(lastPosition.lastProgress),
               let library = self.calibreLibraries[book.library.id],
               let goodreadsId = book.identifiers["goodreads"],
               let (dsreaderHelperServer, dsreaderHelperLibrary, goodreadsSync) = self.shouldAutoUpdateGoodreads(library: library),
               dsreaderHelperLibrary.autoUpdateGoodreadsProgress {
                let connector = DSReaderHelperConnector(calibreServerService: self.calibreServerService, server: library.server, dsreaderHelperServer: dsreaderHelperServer, goodreadsSync: goodreadsSync)
                connector.updateReadingProgress(goodreads_id: goodreadsId, progress: updatedReadingPosition.lastProgress)
                
                if goodreadsSync.isEnabled(), goodreadsSync.readingProgressColumnName.count > 1 {
                    self.calibreServerService.updateMetadata(library: library, bookId: book.id, metadata: [
                        [goodreadsSync.readingProgressColumnName, Int(updatedReadingPosition.lastProgress)]
                    ])
                }
            }
        }.store(in: &calibreCancellables)
    }
    
    func logStartCalibreActivity(type: String, request: URLRequest, startDatetime: Date, bookId: Int32?, libraryId: String?) {
        activityDispatchQueue.async {
            guard let realm = try? Realm(configuration: self.realmConf) else { return }
            
            let obj = CalibreActivityLogEntry()
            
            obj.type = type
            
            obj.startDatetime = startDatetime
            obj.bookId = bookId ?? 0
            obj.libraryId = libraryId
            
            obj.endpoingURL = request.url?.absoluteString
            obj.httpMethod = request.httpMethod
            obj.httpBody = request.httpBody
            request.allHTTPHeaderFields?.forEach {
                obj.requestHeaders.append($0.key)
                obj.requestHeaders.append($0.value)
            }
            
            try? realm.write {
                realm.add(obj)
            }
        }
    }
    
    func logFinishCalibreActivity(type: String, request: URLRequest, startDatetime: Date, finishDatetime: Date, errMsg: String) {
        activityDispatchQueue.async {
            guard let realm = try? Realm(configuration: self.realmConf) else { return }
            
            guard let activity = realm.objects(CalibreActivityLogEntry.self).filter(
                NSPredicate(format: "type = %@ AND startDatetime = %@ AND endpoingURL = %@",
                            type,
                            startDatetime as NSDate,
                            request.url?.absoluteString ?? ""
                )
            ).first else { return }
            
            try? realm.write {
                activity.finishDatetime = finishDatetime
                activity.errMsg = errMsg
            }
        }
    }
    
    func removeCalibreActivity(obj: CalibreActivityLogEntry) {
        guard let realm = try? Realm(configuration: self.realmConf) else { return }

        try? realm.write {
            realm.delete(obj)
        }
    }
    
    func listCalibreActivities(libraryId: String? = nil, bookId: Int32? = nil, startDatetime: Date = Date(timeIntervalSinceNow: TimeInterval(-86400))) -> [CalibreActivityLogEntry] {
        guard let realm = try? Realm(configuration: self.realmConf) else { return [] }
        
        var pred = NSPredicate()
        if let libraryId = libraryId {
            if let bookId = bookId {
                pred = NSPredicate(
                    format: "startDatetime >= %@ AND libraryId = %@ AND bookId = %@",
                    Date(timeIntervalSinceNow: TimeInterval(-86400)) as NSDate,
                    libraryId,
                    NSNumber(value: bookId)
                )
            } else {
                pred = NSPredicate(
                    format: "startDatetime >= %@ AND libraryId = %@",
                    Date(timeIntervalSinceNow: TimeInterval(-86400)) as NSDate,
                    libraryId
                )
            }
        } else {
            pred = NSPredicate(
                format: "startDatetime > %@",
                Date(timeIntervalSinceNow: TimeInterval(-86400)) as NSDate
            )
        }
        
        let activities = realm.objects(CalibreActivityLogEntry.self).filter(pred)
        
        return activities.map { $0 }.sorted { $1.startDatetime < $0.startDatetime }
    }
    
    func cleanCalibreActivities(startDatetime: Date) {
        let activities = realm.objects(CalibreActivityLogEntry.self).filter(
            NSPredicate(
                format: "startDatetime < %@",
                startDatetime as NSDate
            )
        )
        try? realm.write {
            realm.delete(activities)
        }
    }
    
    /**
     key: inShelfId
     */
    func listBookDeviceReadingPositionHistory(library: CalibreLibrary? = nil, bookId: Int32? = nil, startDateAfter: Date? = nil) -> [String:[BookDeviceReadingPositionHistory]] {
        guard let realm = try? Realm(configuration: self.realmConf) else { return [:] }

        var pred: NSPredicate? = nil
        if let library = library, let bookId = bookId {
            pred = NSPredicate(format: "bookId = %@", "\(library.key) - \(bookId)")
            if let startDateAfter = startDateAfter {
                pred = NSPredicate(format: "bookId = %@ AND startDatetime >= %@", "\(library.key) - \(bookId)", startDateAfter as NSDate)
            }
        } else {
            if let startDateAfter = startDateAfter {
                pred = NSPredicate(
                    format: "startDatetime >= %@",
                    startDateAfter as NSDate
                )
            }
        }
        
        var results = realm.objects(BookDeviceReadingPositionHistoryRealm.self);
        if let predNotNil = pred {
            results = results.filter(predNotNil)
        }
        results = results.sorted(by: [SortDescriptor(keyPath: "startDatetime", ascending: false)])
        print("\(#function) \(results.count)")
        
        var historyList: [BookDeviceReadingPositionHistory] = results.filter { $0.endPosition != nil }
            .map { BookDeviceReadingPositionHistory(managedObject: $0) }
        
        if let library = library, let bookId = bookId {
            let bookInShelfId = CalibreBook(id: bookId, library: library).inShelfId
            if let book = self.booksInShelf[bookInShelfId] {
                historyList.append(contentsOf: book.readPos.sessions(list: startDateAfter))
            }
        } else {
            self.booksInShelf.forEach {
                historyList.append(contentsOf: $0.value.readPos.sessions(list: startDateAfter))
            }
        }
        
        let idMap = booksInShelf.reduce(into: [String: String]()) { partialResult, entry in
            partialResult["\(entry.value.library.key) - \(entry.value.id)"] = entry.value.inShelfId
        }

        return historyList.sorted(by:{ $0.startDatetime > $1.startDatetime }).removingDuplicates().reduce(into: [:]) { partialResult, history in
            guard let inShelfId = idMap[history.bookId] else { return }
            
            if partialResult[inShelfId] == nil {
                partialResult[inShelfId] = [history]
            } else {
                partialResult[inShelfId]?.append(history)
            }
        }
    }
    
    func getReadingStatistics(list: [BookDeviceReadingPositionHistory], limitDays: Int) -> [Double] {
        let result = list.reduce(into: [Double].init(repeating: 0.0, count: limitDays+1) ) { result, history in
            guard let epoch = history.endPosition?.epoch, epoch > history.startDatetime.timeIntervalSince1970 else { return }
            let duration = epoch - history.startDatetime.timeIntervalSince1970
            let readDayDate = Calendar.current.startOfDay(for: history.startDatetime)
            let nowDayDate = Calendar.current.startOfDay(for: Date())
            let offset = limitDays - Int(floor(nowDayDate.timeIntervalSince(readDayDate) / 86400.0))
            if offset < 0 || offset > limitDays { return }
            result[offset] += duration / 60
        }
        return result
    }
    
    func getBookRealm(forPrimaryKey: String) -> CalibreBookRealm? {
        return realm.object(ofType: CalibreBookRealm.self, forPrimaryKey: forPrimaryKey)
    }
    
    func generateShelfBookModel(limit: Int = 100, earlyCut: Bool = false) -> [ShelfModelSection] {
        var shelfModelSection = [ShelfModelSection]()

        let discoverableLibraries = self.calibreLibraries.filter { $1.discoverable && !$1.hidden }
//            .map {
//            CalibreBookRealm.PrimaryKey(serverUUID: $1.server.uuid.uuidString, libraryName: $1.name, id: "")
//        }
        
        let discoverableLibrariesFilter = NSCompoundPredicate(orPredicateWithSubpredicates: discoverableLibraries.map {
            NSPredicate(format: "serverUUID = %@ AND libraryName = %@", $1.server.uuid.uuidString, $1.name)
        })
        
        guard discoverableLibraries.count > 0 else { return [] }
        
        guard let realm = try? Realm(configuration: self.realmConf) else { return [] }
        
//        let discoverableLibrariesFilter = Array(repeating: "primaryKey BEGINSWITH %@", count: discoverableLibraries.count).joined(separator: " OR ")
        
        let baselinePredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "inShelf == false"),
            discoverableLibrariesFilter
        ])
//        var baselinePredicate = NSPredicate(format: "libraryName != nil AND inShelf == false")
//        if discoverableLibraries.count > 1 {
//            baselinePredicate = NSPredicate(format: "libraryName != nil AND ( \(discoverableLibrariesFilter) ) AND inShelf == false", argumentArray: discoverableLibraries)
//        } else {
//            baselinePredicate = NSPredicate(format: "libraryName != nil AND \(discoverableLibrariesFilter) AND inShelf == false AND libraryName != nil", argumentArray: discoverableLibraries)
//        }
        
        let baselineObjects = realm.objects(CalibreBookRealm.self)
            .filter(baselinePredicate)
        
        for sectionInfo in [("lastModified", "Recently Modified", "last_modified"),
                            ("timestamp", "New in Library", "last_added"),
                            ("pubDate", "Last Published", "last_published")] {
            let results = baselineObjects.sorted(byKeyPath: sectionInfo.0, ascending: false)
                
            var shelfModel = [ShelfModel]()
            var parsed = 0
            for i in 0 ..< results.count {
                if shelfModel.count > limit {
                    break
                }
                parsed += 1
                if let book = self.convert(bookRealm: results[i]),
                   book.library.discoverable,
                   let coverURL = book.coverURL {
                    shelfModel.append(
                        ShelfModel(
                            bookCoverSource: coverURL.absoluteString,
                            bookId: book.inShelfId,
                            bookTitle: book.title,
                            bookProgress: Int(self.getLatestReadingPosition(book: book)?.lastProgress ?? 0.0),
                            bookStatus: .READY,
                            sectionId: sectionInfo.2)
                    )
                    // print("updateBookModel \(sectionInfo.0) \(book)")
                }
            }
            print("\(#function) parsed=\(parsed)")
            
            if shelfModel.count > 1 {
                let section = ShelfModelSection(sectionName: sectionInfo.1, sectionId: sectionInfo.2, sectionShelf: shelfModel)
                shelfModelSection.append(section)
            }
        }
        
        if earlyCut {
            return shelfModelSection
        }
        
        let emptyBook = CalibreBook(id: 0, library: .init(server: .init(uuid: .init(), name: "", baseUrl: "", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: ""), key: "", name: ""))
        
        guard let deviceMapSerialize = try? emptyBook.readPos.getCopy().compactMapValues( { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) } ),
              let readPosDataEmpty = try? JSONSerialization.data(withJSONObject: ["deviceMap": deviceMapSerialize], options: []) as NSData else {
            return []
        }

        let resultsWithReadPos = baselineObjects
            .filter(NSPredicate(format: "readPosData != nil AND readPosData != %@", readPosDataEmpty))
            .compactMap {
                self.convert(bookRealm: $0)
            }
            .filter { book in
                let lastProgress =
                book.readPos.getDevices().max { lhs, rhs in
                    lhs.lastProgress < rhs.lastProgress
                }?.lastProgress ?? 0.0
                return lastProgress > 5.0
            }
            .sorted { lb, rb in
                lb.readPos.getDevices().max { lhs, rhs in
                    lhs.lastProgress < rhs.lastProgress
                }?.lastProgress ?? 0.0 > rb.readPos.getDevices().max { lhs, rhs in
                    lhs.lastProgress < rhs.lastProgress
                }?.lastProgress ?? 0.0
            }
        print("resultsWithReadPos count=\(resultsWithReadPos.count)")
        
        var authorSet = Set<String>()
        var seriesSet = Set<String>()
        var tagSet = Set<String>()
        
        resultsWithReadPos.forEach { book in
//            print("resultsWithReadPos \(book.title)")
//            print("resultsWithReadPos \(String(describing: bookRealm.readPosData))")
//            guard let book = modelData.convert(bookRealm: bookRealm) else { return }
//            print("resultsWithReadPos pos=\(book)")
            if let author = book.authors.first {
                authorSet.insert(author)
            }
            if book.series.count > 0 {
                seriesSet.insert(book.series)
            }
            if let tag = book.tags.first {
                tagSet.insert(tag)
            }
            
            //guard let book = modelData.convert(bookRealm: bookRealm) else { return }
        }
//        print("resultsWithReadPos \(authorSet) \(seriesSet) \(tagSet)")
        
        if resultsWithReadPos.count > 1 {
            let readingSection = ShelfModelSection(
            sectionName: "Reading",
            sectionId: "reading",
            sectionShelf: resultsWithReadPos
                .filter {
                    $0.readPos.getDevices().max { lhs, rhs in
                        lhs.lastProgress < rhs.lastProgress
                    }?.lastProgress ?? 0.0 < 95.0
                }
                .map { book in
                    ShelfModel(
                        bookCoverSource: book.coverURL?.absoluteString ?? ".",
                        bookId: book.inShelfId,
                        bookTitle: book.title,
                        bookProgress: Int(
                            book.readPos.getDevices().max { lhs, rhs in
                                lhs.lastProgress < rhs.lastProgress
                            }?.lastProgress ?? 0.0),
                        bookStatus: .READY,
                        sectionId: "reading")
                }
        )
        
            shelfModelSection.append(readingSection)
        }
        
        [
            (seriesSet, "series", "seriesIndex", "More in Series", true),
            (authorSet, "authorFirst", "pubDate", "More by Author", false),
            (tagSet, "tagFirst", "pubDate", "More of Tag", false)
        ].forEach { def in
            def.0.sorted().forEach { member in
                let sectionId = "\(def.1)-\(member)"
                let books: [ShelfModel] = baselineObjects
                    .filter(NSPredicate(format: "%K == %@", def.1, member))
                    .sorted(byKeyPath: def.2, ascending: def.4)
                    .prefix(limit)
                    .compactMap {
                        self.convert(bookRealm: $0)
                    }
                    .filter {
                        $0.readPos.getDevices().max { lhs, rhs in
                            lhs.lastProgress < rhs.lastProgress
                        }?.lastProgress ?? 0.0 < 95.0
                    }
                    .map { book in
                        ShelfModel(
                            bookCoverSource: book.coverURL?.absoluteString ?? ".",
                            bookId: book.inShelfId,
                            bookTitle: book.title,
                            bookProgress: Int(
                                book.readPos.getDevices().max { lhs, rhs in
                                    lhs.lastProgress < rhs.lastProgress
                                }?.lastProgress ?? 0.0),
                            bookStatus: .READY,
                            sectionId: sectionId)
                    }
                
                guard books.count > 1 else { return }
                
                let readingSection = ShelfModelSection(
                    sectionName: "\(def.3): \(member)",
                    sectionId: sectionId,
                    sectionShelf: books)

                shelfModelSection.append(readingSection)
            }
        }
        
        self.calibreLibraries
            .filter { $0.value.discoverable && $0.value.hidden == false }
            .sorted { $0.value.name < $1.value.name }
            .forEach { id, library in
            let sectionId = "\(library)-\(id)"
            let books: [ShelfModel] = baselineObjects
                .filter("serverUUID = %@ AND libraryName = %@", library.server.uuid.uuidString, library.name)
                .sorted(byKeyPath: "lastModified", ascending: false)
                .prefix(limit)
                .compactMap {
                    self.convert(bookRealm: $0)
                }
                .filter {
                    $0.readPos.getDevices().max { lhs, rhs in
                        lhs.lastProgress < rhs.lastProgress
                    }?.lastProgress ?? 0.0 < 95.0
                }
                .map { book in
                    ShelfModel(
                        bookCoverSource: book.coverURL?.absoluteString ?? ".",
                        bookId: book.inShelfId,
                        bookTitle: book.title,
                        bookProgress: Int(
                            book.readPos.getDevices().max { lhs, rhs in
                                lhs.lastProgress < rhs.lastProgress
                            }?.lastProgress ?? 0.0),
                        bookStatus: .READY,
                        sectionId: sectionId)
                }
            
            guard books.count > 1 else { return }
            
            let readingSection = ShelfModelSection(
                sectionName: "More in Library: \(library.name)",
                sectionId: sectionId,
                sectionShelf: books)

            shelfModelSection.append(readingSection)
        }

        return shelfModelSection
    }
    
}
