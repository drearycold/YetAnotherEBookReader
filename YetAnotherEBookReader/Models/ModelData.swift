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
    @Published var calibreServerInfoStaging = [String: CalibreServerInfo]()
    
    @Published var calibreLibraries = [String: CalibreLibrary]()
    @Published var calibreLibraryInfoStaging = [String: CalibreLibraryInfo]()
    
    @Published var calibreLibraryCategories = [CalibreLibraryCategoryKey: CalibreLibraryCategoryValue]()
    @Published var calibreLibraryCategoryMerged = [String: [String]]()
    
    @Published var activeTab = 0
    var documentServer: CalibreServer?
    var localLibrary: CalibreLibrary?
    
    //for LibraryInfoView
    @Published var defaultFormat = Format.PDF
    var formatReaderMap = [Format: [ReaderType]]()
    var formatList = [Format]()
    
    //Search
    @Published var searchString = ""
    @Published var sortCriteria = LibrarySearchSort(by: SortCriteria.Modified, ascending: false)
    @Published var filterCriteriaCategory = [String: Set<String>]()
    @Published var filterCriteriaShelved = FilterCriteriaShelved.none

    @Published var filterCriteriaLibraries = Set<String>()

    @available(*, deprecated, renamed: "librarySearchManager")
    @Published var searchCriteriaMergedResults = [SearchCriteriaMergedKey: LibrarySearchCriteriaResultMerged]()
    
    @Published var filteredBookListPageCount = 0
    @Published var filteredBookListPageSize = 100
    @Published var filteredBookListPageNumber = 0

    static let SearchLibraryResultsRealmConfiguration = Realm.Configuration(fileURL: nil, inMemoryIdentifier: "searchLibraryResultsRealm")
    
    static let SearchLibraryResultsRealmQueue = DispatchQueue(label: "searchLibraryResultsRealm", qos: .userInitiated)
    
    internal let searchLibraryResultsRealmMainThread = try? Realm(configuration: SearchLibraryResultsRealmConfiguration)
    
    var searchLibraryResultsRealmQueue: Realm?
    
    static let SaveBooksMetadataRealmQueue = DispatchQueue(label: "saveBooksMetadata", qos: .userInitiated)
    
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
    
    let bookReaderClosedSubject = PassthroughSubject<(book: CalibreBook, position: BookDeviceReadingPosition), Never>()
    let bookReaderActivitySubject = PassthroughSubject<ScenePhase, Never>()
    
    var calibreCancellables = Set<AnyCancellable>()
    
    let bookFormatDownloadSubject = PassthroughSubject<(book: CalibreBook, format: Format), Never>()
    let bookDownloadedSubject = PassthroughSubject<CalibreBook, Never>()
    
    let librarySearchRequestSubject = PassthroughSubject<CalibreLibrarySearchTask, Never>()
    let librarySearchResultSubject = PassthroughSubject<CalibreLibrarySearchTask, Never>()
    
    let filteredBookListMergeSubject = PassthroughSubject<SearchCriteriaMergedKey, Never>()
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
                readingBook = booksInShelf[readingBookInShelfId] ?? getBook(for: readingBookInShelfId)
            }
        }
    }
    
    @available(*, deprecated)
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
    var realmSaveBooksMetadata: Realm!
    var realmConf: Realm.Configuration!
    
    let activityDispatchQueue = DispatchQueue(label: "io.github.dsreader.activity")
    
    let kfImageCache = ImageCache.default
    var authResponsor = AuthResponsor()
    
    lazy var downloadService = BookFormatDownloadService(modelData: self)
    @Published var activeDownloads: [URL: BookFormatDownload] = [:]

    lazy var calibreServerService = CalibreServerService(modelData: self)
    @Published var metadataSessions = [CalibreServerURLSessionKey: URLSession]()

    lazy var librarySearchManager = CalibreLibrarySearchManager(service: self.calibreServerService)
    
    lazy var shelfDataModel = YabrShelfDataModel(service: self.calibreServerService, searchManager: librarySearchManager)
    
    let probeServerSubject = PassthroughSubject<CalibreProbeServerRequest, Never>()
    let probeServerResultSubject = PassthroughSubject<CalibreServerInfo, Never>()
    let removeServerSubject = PassthroughSubject<CalibreServer, Never>()
    
    let probeLibrarySubject = PassthroughSubject<CalibreProbeLibraryRequest, Never>()
    let removeLibrarySubject = PassthroughSubject<CalibreLibrary, Never>()
    
    let syncServerHelperConfigSubject = PassthroughSubject<String, Never>()
    
    let syncLibrarySubject = PassthroughSubject<CalibreSyncLibraryRequest, Never>()
    let saveBookMetadataSubject = PassthroughSubject<CalibreSyncLibraryBooksMetadata, Never>()
    let getBooksMetadataSubject = PassthroughSubject<CalibreBooksMetadataRequest, Never>()
    
    lazy var metadataQueue: OperationQueue = {
        var queue = OperationQueue()
        queue.name = "Book Metadata queue"
        queue.maxConcurrentOperationCount = 2
        return queue
    }()
    
    /// inShelfId for single book
    /// empty string for full update
    let calibreUpdatedSubject = PassthroughSubject<calibreUpdatedSignal, Never>()
    let setLastReadPositionSubject = PassthroughSubject<CalibreBookSetLastReadPositionTask, Never>()
    let updateAnnotationsSubject = PassthroughSubject<CalibreBookUpdateAnnotationsTask, Never>()
    
    @Published var librarySyncStatus = [String: CalibreSyncStatus]()

    @Published var userFontInfos = [String: FontInfo]()

    @Published var bookModelSection = [ShelfModelSection]()

    var resourceFileDictionary: NSDictionary?
    var yabrResourceFileDictionary: NSDictionary?
    
    init(mock: Bool = false) {
        ModelData.shared = self
        
        //Load content of Info.plist into resourceFileDictionary dictionary
        if let path = Bundle.main.path(forResource: "Info", ofType: "plist") {
            resourceFileDictionary = NSDictionary(contentsOfFile: path)
        } else {
            resourceFileDictionary = try? NSDictionary(contentsOf: Bundle.main.bundleURL.appendingPathComponent("Contents", isDirectory: true).appendingPathComponent("Info.plist", isDirectory: false), error: ())
        }
        if let path = Bundle.main.path(forResource: "YabrInfo", ofType: "plist", inDirectory: "YabrResources") {
            yabrResourceFileDictionary = NSDictionary(contentsOfFile: path)
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
        
//        calibreServerService.defaultUrlSessionConfiguration.timeoutIntervalForRequest = 600
//        calibreServerService.defaultUrlSessionConfiguration.httpMaximumConnectionsPerHost = 2
        
        registerProbeServerCancellable()
        registerProbeServerResult()
        registerRemoveServerCancellable()
        
        registerProbeLibraryCancellable()
        registerRemoveLibraryCancellable()
        
        registerSyncLibraryCancellable()
        registerSaveBooksMetadataCancellable()
        registerGetBooksMetadataCancellable()
        registerSetLastReadPositionCancellable()
        registerUpdateAnnotationsCancellable()
        registerBookReaderClosedCancellable()
        
        registerRecentShelfUpdater()
        registerDiscoverShelfUpdater()
        
        bookDownloadedSubject.sink { book in
            self.calibreUpdatedSubject.send(.book(book))
            if self.activeTab == 2 {
                self.filteredBookListMergeSubject.send(self.currentLibrarySearchResultKey)
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
            try? tryInitializeDatabase() { _ in
                
            }
            initializeDatabase()
            
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
        ModelData.RealmSchemaVersion = UInt64(self.yabrBuild) ?? 1
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
                
                if oldSchemaVersion < 104 {
                    migration.renameProperty(onType: CalibreBookRealm.className(), from: "id", to: "idInLib")
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
        
        Realm.Configuration.defaultConfiguration = realmConf
    }
    
    func initializeDatabase() {
        realm = try! Realm(
            configuration: realmConf
        )
        ModelData.SaveBooksMetadataRealmQueue.sync {
            self.realmSaveBooksMetadata = try! Realm(
                configuration: realmConf, queue: ModelData.SaveBooksMetadataRealmQueue
            )
        }
        
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
            
//            self.shelfDataModel.addToShelf(book: book)
            
            print("booksInShelfRealm \(book.inShelfId)")
        }
    }
    
    func populateServers() {
        let serversCached = realm.objects(CalibreServerRealm.self).sorted(by: [SortDescriptor(keyPath: "username"), SortDescriptor(keyPath: "baseUrl")])
        serversCached.forEach { serverRealm in
            guard serverRealm.removed == false,
                  serverRealm.baseUrl != nil
            else { return }
            
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
                removed: serverRealm.removed
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
        guard let library = queryLibrary(for: bookRealm) else { return nil }
        
        return convert(library: library, bookRealm: bookRealm)
    }
    
    func convert(library: CalibreLibrary, bookRealm: CalibreBookRealm) -> CalibreBook {
        let calibreBook = CalibreBook(managedObject: bookRealm, library: library)
        
        return calibreBook
    }
    
    func queryLibrary(for bookRealm: CalibreBookRealm) -> CalibreLibrary? {
        guard let serverUUID = bookRealm.serverUUID,
              let libraryName = bookRealm.libraryName
        else { return nil }
        
        return calibreLibraries[CalibreLibraryRealm.PrimaryKey(serverUUID: serverUUID, libraryName: libraryName)]
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
        serverRealm.removed = server.removed
        try realm.write {
            realm.add(serverRealm, update: .modified)
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
        
        if book.readPos.getDevices().first?.id == deviceName,
           let library = calibreLibraries[book.library.id],
           let goodreadsId = book.identifiers["goodreads"],
           let (dsreaderHelperServer, dsreaderHelperLibrary, goodreadsSync) = shouldAutoUpdateGoodreads(library: library),
           dsreaderHelperLibrary.autoUpdateGoodreadsBookShelf {
            let connector = DSReaderHelperConnector(calibreServerService: calibreServerService, server: library.server, dsreaderHelperServer: dsreaderHelperServer, goodreadsSync: goodreadsSync)
            let ret = connector.removeFromShelf(goodreads_id: goodreadsId, shelfName: "currently-reading")
            
            if let position = book.readPos.getPosition(deviceName), position.lastProgress > 99 {
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
    
    
    func updateCurrentPosition(alertDelegate: AlertDelegate?) {
        guard let readingBook = self.readingBook,
              let updatedReadingPosition = readingBook.readPos.getDevices().first,
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
        if let position = book.readPos.getPosition(deviceName) {
            candidatePositions.append(position)
        }
        if let position = book.readPos.getDevices().first {
            candidatePositions.append(position)
        }
//        candidatePositions.append(contentsOf: book.readPos.getDevices())
        if let format = getPreferredFormat(for: book) {
            candidatePositions.append(
                book.readPos.createInitial(
                    deviceName: self.deviceName,
                    reader: getPreferredReader(for: format)
                )
            )
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
    
    func probeServersReachability(with serverIds: Set<String>, updateLibrary: Bool = false, autoUpdateOnly: Bool = true, incremental: Bool = true) {
        
        calibreServers.filter {
            $0.value.isLocal == false
            && (serverIds.isEmpty || serverIds.contains($0.value.id))
        }.forEach { serverId, server in
            self.probeServerSubject.send(.init(server: server, isPublic: false, updateLibrary: updateLibrary, autoUpdateOnly: autoUpdateOnly, incremental: incremental))
            if server.hasPublicUrl {
                self.probeServerSubject.send(.init(server: server, isPublic: true,  updateLibrary: updateLibrary, autoUpdateOnly: autoUpdateOnly, incremental: incremental))
            }
        }
    }
    
    func isServerReachable(server: CalibreServer, isPublic: Bool) -> Bool? {
        return calibreServerInfoStaging.filter {
            $1.server.id == server.id && $1.isPublic == isPublic
        }.first?.value.reachable
    }
    
    func isServerProbing(server: CalibreServer) -> Bool {
        return calibreServerInfoStaging.filter {
            $1.server.id == server.id
        }.allSatisfy {
            $1.probing == false
        } != true
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
        let libraryBooks = booksInShelf.values
            .filter { serverIds.isEmpty || serverIds.contains($0.library.server.id) }
            .filter { bookInShelfIds.isEmpty || bookInShelfIds.contains($0.inShelfId) }
            .reduce(into: [CalibreLibrary: [CalibreBook]]()) { partialResult, book in
                if partialResult[book.library] == nil {
                    partialResult[book.library] = []
                }
                partialResult[book.library]?.append(book)
            }
        
        if serverReachableChanged && libraryBooks.isEmpty {
            calibreUpdatedSubject.send(.shelf)
            return
        }
        
        libraryBooks.forEach { library, books in
            self.getBooksMetadataSubject.send(.init(library: library, books: books.map { $0.id }, getAnnotations: true))
        }
    }
    
    func registerProbeServerCancellable() {
        let queue = DispatchQueue(label: "probe-server", qos: .userInitiated)
        probeServerSubject.receive(on: DispatchQueue.main)
            .map { request -> CalibreServerInfo in
                if var info = self.calibreServerInfoStaging[request.id] {
                    info.probing = true
                    info.errorMsg = "Connecting"
                    info.request = request
                    self.calibreServerInfoStaging[request.id] = info
                    return info
                } else {
                    let info = CalibreServerInfo(
                        server: request.server,
                        isPublic: request.isPublic,
                        url: URL(string: request.isPublic ? request.server.publicUrl : request.server.baseUrl) ?? URL(fileURLWithPath: "/"),
                        probing: true,
                        errorMsg: "Connecting",
                        defaultLibrary: request.server.defaultLibrary,
                        request: request
                    )
                    self.calibreServerInfoStaging[request.id] = info
                    return info
                }
            }
            .receive(on: queue)
            .flatMap { serverInfo -> AnyPublisher<CalibreServerInfo, Never> in
                self.calibreServerService.probeServerReachabilityNew(serverInfo: serverInfo)
            }
            .receive(on: DispatchQueue.main)
            .sink { newServerInfo in
                guard var serverInfo = self.calibreServerInfoStaging[newServerInfo.id] else { return }
                serverInfo.probing = false
                serverInfo.errorMsg = newServerInfo.errorMsg

                if newServerInfo.libraryMap.isEmpty {
                    serverInfo.reachable = false
                    if serverInfo.errorMsg.isEmpty {
                        serverInfo.errorMsg = "Empty Server"
                    }
                } else {
                    serverInfo.reachable = newServerInfo.reachable
                    serverInfo.libraryMap = newServerInfo.libraryMap
                    serverInfo.defaultLibrary = newServerInfo.defaultLibrary
                }
                self.calibreServerInfoStaging[newServerInfo.id] = serverInfo
                
                self.probeServerResultSubject.send(serverInfo)
            }.store(in: &calibreCancellables)
    }
    
    func registerProbeServerResult() {
        probeServerResultSubject.receive(on: DispatchQueue.main)
            .filter {
                $0.server.isLocal == false && $0.request.updateLibrary
            }
            .map { serverInfo -> CalibreServerInfo in
                serverInfo.libraryMap.forEach { key, name in
                    let newLibrary = CalibreLibrary(server: serverInfo.server, key: key, name: name)
                    if self.calibreLibraries[newLibrary.id] == nil {
                        self.calibreLibraries[newLibrary.id] = newLibrary
                        try? self.updateLibraryRealm(library: newLibrary, realm: self.realm)
                    }
                }
                
                return serverInfo
            }
            .sink { serverInfo in
                if serverInfo.request.autoUpdateOnly == false {
                    self.syncServerHelperConfigSubject.send(serverInfo.server.id)
                }
                
                self.calibreLibraries.filter {
                    $0.value.server.id == serverInfo.server.id
                }.forEach { id, library in
                    self.syncLibrarySubject.send(
                        .init(
                            library: library,
                            autoUpdateOnly: serverInfo.request.autoUpdateOnly,
                            incremental: serverInfo.request.incremental
                        )
                    )
                }
                
                //TODO refresh shelf
                if serverInfo.reachable {
                    self.calibreUpdatedSubject.send(.server(serverInfo.server))
                }
            }.store(in: &calibreCancellables)
    }
    
    func registerRemoveServerCancellable() {
        let queue = DispatchQueue(label: "remove-server", qos: .background)
        removeServerSubject.receive(on: DispatchQueue.main)
            .map { server -> CalibreServer in
                
                self.calibreLibraries.filter {
                    $0.value.server.id == server.id
                }.forEach {
                    self.hideLibrary(libraryId: $0.key)
                    
                    self.removeLibrarySubject.send($0.value)
                }
                
                self.calibreUpdatedSubject.send(.shelf)
                
                return server
            }
            .sink { server in
                //FIXME: when to remove server from self?
                return;
                
                //remove server
                self.calibreServers.removeValue(forKey: server.id)
                
                let serverRealms = self.realm.objects(CalibreServerRealm.self).filter(
                    NSPredicate(format: "baseUrl = %@ AND username = %@",
                                server.baseUrl,
                                server.username
                               )
                )
                try? self.realm.write {
                    self.realm.delete(serverRealms)
                }
            }
            .store(in: &calibreCancellables)
    }
    
    func registerProbeLibraryCancellable() {
        let queue = DispatchQueue(label: "probe-library", qos: .userInitiated)
        probeLibrarySubject.receive(on: queue)
            .flatMap { request -> AnyPublisher<CalibreLibraryProbeTask, Never> in
                if let task = self.calibreServerService.buildProbeLibraryTask(library: request.library) {
                    return self.calibreServerService.urlSession(server: task.library.server).dataTaskPublisher(for: task.probeUrl)
                        .map { response -> CalibreLibraryProbeTask in
                            var task = task
                            task.probeResult = try? JSONDecoder().decode(CalibreLibraryBooksResult.SearchResult.self, from: response.data)
                
                            return task
                        }
                        .replaceError(with: task)
                        .eraseToAnyPublisher()
                } else {
                    return Just(CalibreLibraryProbeTask(library: request.library, probeUrl: .init(fileURLWithPath: "/realm"), probeResult: nil))
                        .setFailureType(to: Never.self)
                        .eraseToAnyPublisher()
                }
            }
            .receive(on: DispatchQueue.main)
            .sink { task in
                if let probeResult = task.probeResult {
                    self.calibreLibraryInfoStaging[task.library.id] = .init(library: task.library, totalNumber: probeResult.total_num, errorMessage: "Success")
                } else {
                    self.calibreLibraryInfoStaging[task.library.id] = .init(library: task.library, totalNumber: 0, errorMessage: "Failed")
                }
            }
            .store(in: &calibreCancellables)
    }
    
    func registerRemoveLibraryCancellable() {
        let queue = DispatchQueue(label: "remove-library", qos: .background)
        
        removeLibrarySubject.receive(on: DispatchQueue.main)
            .map { library -> CalibreLibrary in
                self.librarySyncStatus[library.id]?.isSync = true
                
                //remove cached book files
                let libraryBooksInShelf = self.booksInShelf.filter {
                    $0.value.library.id == library.id
                }
                libraryBooksInShelf.forEach {
                    self.clearCache(inShelfId: $0.key)
                    self.removeFromShelf(inShelfId: $0.key)     //just in case
                }
                return library
            }
            .receive(on: queue)
            .map { library -> CalibreLibrary in
                guard let realm = try? Realm(configuration: self.realmConf)
                else { return library }
                
                //remove library info
                let predicate = NSPredicate(format: "serverUUID = %@ AND libraryName = %@", library.server.uuid.uuidString, library.name)
                var booksCached: [CalibreBookRealm] = realm.objects(CalibreBookRealm.self)
                    .filter(predicate)
                    .prefix(256)
                    .map{ $0 }
                while booksCached.isEmpty == false {
                    print("\(#function) will delete \(booksCached.count) entries of \(library.id)")
                    try? realm.write {
                        realm.delete(booksCached)
                    }
                    booksCached = realm.objects(CalibreBookRealm.self)
                        .filter(predicate)
                        .prefix(256)
                        .map{ $0 }
                }
                
                return library
            }
            .receive(on: DispatchQueue.main)
            .sink { library in
                self.librarySyncStatus[library.id]?.isSync = false
//                self.calibreLibraries.removeValue(forKey: library.id)
            }
            .store(in: &calibreCancellables)
    }
    
    func registerSyncServerHelperConfigCancellable() {
        let queue = DispatchQueue(label: "sync-server-helper", qos: .userInitiated)
        syncServerHelperConfigSubject
            .receive(on: queue)
            .flatMap { serverId -> AnyPublisher<(id: String, port: Int, data: Data), URLError> in
                if let server = self.calibreServers[serverId],
                   let dsreaderHelperServer = self.queryServerDSReaderHelper(server: server),
                   let publisher = DSReaderHelperConnector(calibreServerService: self.calibreServerService, server: server, dsreaderHelperServer: dsreaderHelperServer, goodreadsSync: nil).refreshConfiguration() {
                    return publisher
                } else {
                    return Just((id: serverId, port: 0, data: Data())).setFailureType(to: URLError.self).eraseToAnyPublisher()
                }
            }
            .map { task -> (id: String, port: Int, data: Data, config: CalibreDSReaderHelperConfiguration?) in
                return (
                    id: task.id,
                    port: task.port,
                    data: task.data,
                    config: try? JSONDecoder().decode(CalibreDSReaderHelperConfiguration.self, from: task.data)
                )
            }
            .receive(on: DispatchQueue.main)
            .sink { completion in
                
            } receiveValue: { task in
                if let config = task.config, config.dsreader_helper_prefs != nil {
                    let dsreaderHelper = CalibreServerDSReaderHelper(id: task.id, port: task.port, configurationData: task.data, configuration: config)
                    
                    let obj = dsreaderHelper.managedObject()
                    try? self.realm.write {
                        self.realm.add(obj, update: .all)
                    }
                }
            }.store(in: &calibreCancellables)
    }
    
    func registerSyncLibraryCancellable() {
        let queue = DispatchQueue(label: "sync-library", qos: .userInitiated)
        syncLibrarySubject.receive(on: DispatchQueue.main)
            .flatMap { request -> AnyPublisher<CalibreSyncLibraryResult, Never> in
                let libraryId = request.library.id
                guard (self.librarySyncStatus[libraryId]?.isSync ?? false) == false else {
                    print("\(#function) isSync \(libraryId)")
                    return Just(CalibreSyncLibraryResult(request: request, result: ["just_syncing":[:]]))
                        .setFailureType(to: Never.self).eraseToAnyPublisher()
                }
                
                guard request.library.hidden == false,
                      request.autoUpdateOnly == false || request.library.autoUpdate else {
                    print("\(#function) autoUpdate \(request.library.id)")
                    return Just(CalibreSyncLibraryResult(request: request, result: ["auto_update":[:]]))
                        .setFailureType(to: Never.self).eraseToAnyPublisher()
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
                
                print("\(#function) startSync \(request.library.id)")

                return self.calibreServerService.getCustomColumnsPublisher(request: request)
            }
            .receive(on: queue)
            .flatMap { result -> AnyPublisher<CalibreSyncLibraryResult, Never> in
                guard result.request.library.hidden == false,
                      result.result["just_syncing"] == nil else {
                    return Just(result).setFailureType(to: Never.self).eraseToAnyPublisher()
                }
                
                return self.calibreServerService.getLibraryCategoriesPublisher(resultPrev: result)
            }
            .flatMap { result -> AnyPublisher<CalibreSyncLibraryResult, Never> in
                print("\(#function) syncLibraryPublisher categories \(result.request.library.id) \(result.categories)")
                guard result.result["just_syncing"] == nil,
                      result.result["auto_update"] == nil else {
                    return Just(result).setFailureType(to: Never.self).eraseToAnyPublisher()
                }
                
                var filter = ""     //  "last_modified:>2022-02-20T00:00:00.000000+00:00"
                if result.request.incremental,
                   let realm = try? Realm(configuration: self.realmConf),
                   let libraryRealm = realm.object(
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
                print("\(#function) syncLibraryPublisher filter \(result.request.library.id) \(filter)")
                
                return self.calibreServerService.syncLibraryPublisher(resultPrev: result, filter: filter)
            }
            .map { result -> CalibreSyncLibraryResult in
                let library = result.request.library
                let serverUUID = library.server.uuid.uuidString
                var result = result
                
                print("\(#function) receiveValue \(library.id) count=\(result.list.book_ids.count)")
                
                
                guard result.result["error"] == nil else {
                    result.isError = true
                    return result
                }
                
                guard result.result["just_syncing"] == nil else { return result }
                guard result.result["auto_update"] == nil else { return result }
                
                guard result.list.book_ids.first != -1 else {
                    result.isError = true
                    return result
                }
                
                let dateFormatter = ISO8601DateFormatter()
                let dateFormatter2 = ISO8601DateFormatter()
                dateFormatter2.formatOptions.formUnion(.withFractionalSeconds)
                
                var progress = 0
                let total = result.list.book_ids.count
                result.list.book_ids.chunks(size: 1024).forEach { chunk in
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
                            "id": id
                        ]
                    }
                    progress += chunk.count
                    let postMsg = "\(progress) / \(total)"
                    self.saveBookMetadataSubject.send(.init(library: library, action: .save(list), preMsg: preMsg, postMsg: postMsg))
                    
                    result.lastModified = list.last?["lastModified"] as? Date
                }
                
                if result.request.incremental == false {
                    self.saveBookMetadataSubject.send(.init(library: library, action: .updateDeleted(result.list.data.last_modified), preMsg: "", postMsg: ""))
                }
                
                
                return result
            }
            .receive(on: DispatchQueue.main)
            .sink { result in
                let library = result.request.library
                
                self.saveBookMetadataSubject.send(
                    .init(
                        library: library,
                        action: .complete(
                            result.lastModified,
                            result.result["result"] ?? [:]
                        ),
                        preMsg: "",
                        postMsg: result.isError ? result.errmsg : "Success"
                    )
                )
                
                result.categories.filter {
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
                
                self.librarySyncStatus[library.id]?.isError = result.isError
            }.store(in: &calibreCancellables)
    }
    
    func registerSaveBooksMetadataCancellable() {
        saveBookMetadataSubject
            .receive(on: DispatchQueue.main)
            .map { booksMetadata -> CalibreSyncLibraryBooksMetadata in
                self.librarySyncStatus[booksMetadata.library.id]?.msg = booksMetadata.preMsg
                return booksMetadata
            }
            .receive(on: ModelData.SaveBooksMetadataRealmQueue)
            .map { booksMetadata -> CalibreSyncLibraryBooksMetadata in
                var booksMetadata = booksMetadata
                
                switch booksMetadata.action {
                case let .save(list):
                    try? self.realmSaveBooksMetadata.write {
                        list.forEach {
                            self.realmSaveBooksMetadata.create(CalibreBookRealm.self, value: $0, update: .modified)
                        }
                    }
                case let .updateDeleted(last_modified):
                    let objects = self.realmSaveBooksMetadata.objects(CalibreBookRealm.self).filter(
                        "serverUUID = %@ AND libraryName = %@", booksMetadata.library.server.uuid.uuidString, booksMetadata.library.name
                    )
                    booksMetadata.bookDeleted = objects
                        .filter {
                            $0.inShelf == false && last_modified[$0.idInLib.description] == nil
                        }
                        .map { $0.idInLib }
                case .complete:
                    if booksMetadata.library.autoUpdate {
                        let objects = self.realmSaveBooksMetadata.objects(CalibreBookRealm.self).filter(
                            "serverUUID = %@ AND libraryName = %@", booksMetadata.library.server.uuid.uuidString, booksMetadata.library.name
                        )
                        booksMetadata.bookCount = objects.count
                    
                        let objectsNeedUpdate = objects.filter("lastSynced < lastModified")
                        let libraryStatus = self.librarySyncStatus[booksMetadata.library.id]
                        booksMetadata.bookToUpdate = objectsNeedUpdate
                            .sorted(byKeyPath: "lastModified", ascending: false)
                            .map { $0.idInLib }
                            .filter {
                                libraryStatus == nil || libraryStatus?.upd.contains($0) == false
                            }
                    }
                }
                
                return booksMetadata
            }
            .receive(on: DispatchQueue.main)
            .map { booksMetadata -> CalibreSyncLibraryBooksMetadata in
                var library = booksMetadata.library
                
                switch booksMetadata.action {
                case let .complete(lastModified, columnInfos):
                    if columnInfos.isEmpty == false {
                        library.customColumnInfos = columnInfos
                    }
                    if let lastModified = lastModified {
                        library.lastModified = lastModified
                    }
                    
                    self.calibreLibraries[library.id] = library
                    try? self.updateLibraryRealm(library: library, realm: self.realm)
                    
                    self.librarySyncStatus[library.id]?.isSync = false
                    self.librarySyncStatus[library.id]?.cnt = booksMetadata.bookCount
                    self.librarySyncStatus[library.id]?.upd.formUnion(booksMetadata.bookToUpdate)
                    
                    booksMetadata.bookToUpdate.chunks(size: 256).forEach { chunk in
                        self.getBooksMetadataSubject.send(.init(library: booksMetadata.library, books: chunk, getAnnotations: false))
                    }
                case .updateDeleted:
                    self.librarySyncStatus[library.id]?.del.formUnion(booksMetadata.bookDeleted)
                default:
                    break
                }
                
                return booksMetadata
            }
            .sink { booksMetadata in
                let library = booksMetadata.library
                
                self.librarySyncStatus[library.id]?.msg = booksMetadata.postMsg
            }
            .store(in: &calibreCancellables)
    }
    
    func registerGetBooksMetadataCancellable() {
        let queue = DispatchQueue(label: "get-books-metadata", qos: .userInitiated, attributes: [.concurrent])
        getBooksMetadataSubject
            .receive(on: DispatchQueue.main)
            .map { request -> CalibreBooksMetadataRequest in
                self.librarySyncStatus[request.library.id]?.isUpd = true
                return request
            }
            .receive(on: queue)
            .flatMap { request -> AnyPublisher<CalibreBooksTask, Never> in
                let books = request.books.map { bookId -> CalibreBook in
                    let book = CalibreBook(id: bookId, library: request.library)
                    return self.booksInShelf[book.inShelfId] ?? book
                }
                    
                if let task = self.calibreServerService.buildBooksMetadataTask(library: request.library, books: books, getAnnotations: request.getAnnotations) {
                    return self.calibreServerService
                        .getBooksMetadata(task: task)
                        .replaceError(with: task)
                        .eraseToAnyPublisher()
                } else {
                    return Just(CalibreBooksTask(request: request))
                        .setFailureType(to: Never.self)
                        .eraseToAnyPublisher()
                }
            }
            .flatMap { task -> AnyPublisher<CalibreBooksTask, Never> in
                if task.request.getAnnotations {
                    return self.calibreServerService
                        .getAnnotations(task: task)
                        .replaceError(with: task)
                        .eraseToAnyPublisher()
                } else {
                    return Just(task).setFailureType(to: Never.self).eraseToAnyPublisher()
                }
            }
            .receive(on: ModelData.SaveBooksMetadataRealmQueue)
            .map { result -> CalibreBooksTask in
                guard let entries = result.booksMetadataEntry,
                      let json = result.booksMetadataJSON else {
                    return result
                }
                
                var result = result
                let serverUUID = result.library.server.uuid.uuidString
                let libraryName = result.library.name
                try? self.realmSaveBooksMetadata.write {
                    result.books.map {
                        (
                            obj: self.realmSaveBooksMetadata.object(
                                ofType: CalibreBookRealm.self,
                                forPrimaryKey: CalibreBookRealm.PrimaryKey(serverUUID: serverUUID, libraryName: libraryName, id: $0.description)
                            ),
                            entry: entries[$0.description],
                            root: json[$0.description] as? NSDictionary
                        )
                    }.forEach {
                        guard let obj = $0.obj else { return }
                        
                        if let entryOptional = $0.entry, let entry = entryOptional, let root = $0.root {
                            self.calibreServerService.handleLibraryBookOne(library: result.library, bookRealm: obj, entry: entry, root: root)
                            result.booksUpdated.insert(obj.idInLib)
                            if obj.inShelf {
                                result.booksInShelf.append(self.convert(library: result.library, bookRealm: obj))
                            }
                        } else {
                            // null data, treat as delted, update lastSynced to lastModified to prevent further actions
                            obj.lastSynced = obj.lastModified
                            result.booksDeleted.insert(obj.idInLib)
                        }
                    }
                }
                print("getBookMetadataCancellable count \(result.library.name) \(entries.count)")
                
                return result
            }
        .map { result -> CalibreBooksTask in
                guard result.request.getAnnotations,
                      let annotationsResult = result.booksAnnotationsEntry
                else {
                    return result
                }
                
                result.booksInShelf.forEach { book in
                    book.formats.forEach { formatKey, formatInfo in
                        guard let format = Format(rawValue: formatKey),
                              let entry = annotationsResult["\(book.id):\(formatKey)"]
                        else { return }
                        
                        book.readPos.positions(added: entry.last_read_positions).forEach {
                            guard let task = self.calibreServerService.buildSetLastReadPositionTask(
                                library: result.library,
                                bookId: book.id,
                                format: format,
                                entry: $0
                            ) else { return }
                            self.setLastReadPositionSubject.send(task)
                        }
                        
                        if book.readPos.highlights(added: entry.annotations_map.highlight ?? []) > 0 || book.readPos.bookmarks(added: entry.annotations_map.bookmark ?? []) > 0,
                           let task = self.calibreServerService.buildUpdateAnnotationsTask(
                            library: result.library,
                            bookId: book.id,
                            format: format,
                            highlights: book.readPos.highlights(excludeRemoved: false).compactMap {
                                $0.toCalibreBookAnnotationHighlightEntry()
                            },
                            bookmarks: book.readPos.bookmarks().map { $0.toCalibreBookAnnotationBookmarkEntry() }
                           ) {
                            self.updateAnnotationsSubject.send(task)
                        }
                    }
                }
                
                return result
            }
        .receive(on: DispatchQueue.main)
            .sink { result in
                let booksHandled = result.booksUpdated.union(result.booksError).union(result.booksDeleted)
                
                self.librarySyncStatus[result.library.id]?.upd.subtract(booksHandled)
                
                if result.booksError.isEmpty == false {
                    self.librarySyncStatus[result.library.id]?.err.formUnion(result.booksError)
                    self.librarySyncStatus[result.library.id]?.del.formUnion(result.booksDeleted)
                    let booksRetry = result.books.filter { booksHandled.contains($0) == false }
                    
                    if booksRetry.isEmpty == false {
                        booksRetry.chunks(size: max(booksRetry.count / 16, 1)).forEach { chunk in
                            self.getBooksMetadataSubject.send(.init(library: result.library, books: chunk, getAnnotations: result.request.getAnnotations))
                        }
                    }
                }
                
                self.librarySyncStatus[result.library.id]?.isUpd = false
                
                result.booksInShelf.forEach { newBook in
                    self.booksInShelf[newBook.inShelfId] = newBook
                    self.calibreUpdatedSubject.send(.book(newBook))
                }
                
                if result.request.books.count == 1,
                   let book = self.getBook(
                    for: CalibreBookRealm.PrimaryKey(
                        serverUUID: result.library.server.uuid.uuidString,
                        libraryName: result.library.name,
                        id: result.request.books.first!.description
                    )
                   ) {
                    self.calibreUpdatedSubject.send(.book(book))
                }
            }.store(in: &calibreCancellables)
    }
    
    func registerSetLastReadPositionCancellable() {
        let queue = DispatchQueue(label: "set-last-read-position", qos: .userInitiated)
        setLastReadPositionSubject
            .eraseToAnyPublisher()
            .receive(on: queue)
            .flatMap { task in
                return self.calibreServerService.setLastReadPositionByTask(task: task)
            }
            .sink(receiveValue: { output in
                print("\(#function) output=\(output)")
            }).store(in: &calibreCancellables)
    }
    
    func registerUpdateAnnotationsCancellable() {
        let queue = DispatchQueue(label: "update-annotations", qos: .userInitiated)
        updateAnnotationsSubject
            .eraseToAnyPublisher()
            .receive(on: queue)
            .flatMap { task -> AnyPublisher<CalibreBookUpdateAnnotationsTask, Never> in
                self.logStartCalibreActivity(type: "Update Annotations", request: task.urlRequest, startDatetime: task.startDatetime, bookId: task.bookId, libraryId: task.library.id)
                return self.calibreServerService.updateAnnotationByTask(task: task)
            }
            .receive(on: DispatchQueue.main)
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
            
            book.formats.forEach {
                guard let format = Format(rawValue: $0.key), $0.value.cached else { return }
                readPosToLastReadPosition(book: book, format: format, formatInfo: $0.value)
            }

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
                    Date(timeIntervalSinceNow: TimeInterval(86400) * -1) as NSDate,
                    libraryId,
                    NSNumber(value: bookId)
                )
            } else {
                pred = NSPredicate(
                    format: "startDatetime >= %@ AND libraryId = %@",
                    Date(timeIntervalSinceNow: TimeInterval(86400) * -1) as NSDate,
                    libraryId
                )
            }
        } else {
            pred = NSPredicate(
                format: "startDatetime > %@",
                Date(timeIntervalSinceNow: TimeInterval(86400) * -1) as NSDate
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
    
}
