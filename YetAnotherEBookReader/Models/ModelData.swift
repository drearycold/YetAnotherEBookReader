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

#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

final class ModelData: ObservableObject {
//    @Published var calibreServer = "http://calibre-server.lan:8080/"
//    @Published var calibreUsername = ""
//    @Published var calibrePassword = ""
    @Published var deviceName = UIDevice().name
    
    @Published var calibreServers = [String: CalibreServer]()
    @Published var currentCalibreServerId = "" {
        didSet {
            UserDefaults.standard.set(currentCalibreServerId, forKey: Constants.KEY_DEFAULTS_SELECTED_SERVER_ID)
            
            currentBookId = 0
            filteredBookList.removeAll()
            calibreServerLibraryBooks.removeAll()
            //calibreServerLibraries.removeAll()
            //populateServerLibraries()
        }
    }
    
    @Published var calibreLibraries = [String: CalibreLibrary]()
    @Published var currentCalibreLibraryId = "" {
        didSet {
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
                }
            }
        }
    }
    @Published var calibreServerLibraryUpdating = false
    @Published var calibreServerLibraryUpdatingProgress = 0
    @Published var calibreServerLibraryUpdatingTotal = 0
    
    @Published var calibreServerLibraryBooks = [Int32: CalibreBook]()
    
    //for LibraryInfoView
    @Published var defaultFormat = CalibreBook.Format.PDF
    @Published var searchString = "" {
        didSet {
            updateFilteredBookList()
        }
    }
    @Published var filterCriteriaRating = Set<String>() {
        didSet {
            updateFilteredBookList()
        }
    }
    
    @Published var filterCriteriaFormat = Set<String>() {
        didSet {
            updateFilteredBookList()
        }
    }
    @Published var filterCriteriaIdentifier = Set<String>() {
        didSet {
            updateFilteredBookList()
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
            self.readingBook = self.calibreServerLibraryBooks[selectedBookId ?? currentBookId]
        }
    }
    
    @Published var selectedPosition = ""
    @Published var updatedReadingPosition = BookDeviceReadingPosition(id: UIDevice().name, readerName: "")
    
    var readingBookInShelfId: String? = nil {
        didSet {
            if readingBookInShelfId != nil {
                readingBook = booksInShelf[readingBookInShelfId!]
            }
        }
    }
    @Published var readingBook: CalibreBook? = nil
    
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
            if updatingMetadataStatus == "Success" {
                updatingMetadataSucceed = true
            }
        }
    }
    @Published var updatingMetadataSucceed = false
    
    private var defaultLog = Logger()
    
    private var realm: Realm!
    private let realmConf = Realm.Configuration(
        schemaVersion: 15,
        migrationBlock: { migration, oldSchemaVersion in
                if oldSchemaVersion < 9 {
                    // if you added a new property or removed a property you don't
                    // have to do anything because Realm automatically detects that
                    
                }
            }
    )
    
    let kfImageCache = ImageCache.default
    
    init() {
        #if canImport(GoogleMobileAds)
        GADMobileAds.sharedInstance().start(completionHandler: nil)
        #endif
        
        realm = try! Realm(
            configuration: realmConf
        )
        
        kfImageCache.diskStorage.config.expiration = .never
        
        let serversCached = realm.objects(CalibreServerRealm.self).sorted(by: [SortDescriptor(keyPath: "username"), SortDescriptor(keyPath: "baseUrl")])
        serversCached.forEach { serverRealm in
            let calibreServer = CalibreServer(baseUrl: serverRealm.baseUrl!, username: serverRealm.username!, password: serverRealm.password!)
            calibreServers[calibreServer.id] = calibreServer
        }
        
        if let lastServerId = UserDefaults.standard.string(forKey: Constants.KEY_DEFAULTS_SELECTED_SERVER_ID), calibreServers[lastServerId] != nil {
            currentCalibreServerId = lastServerId
        }
        
        if calibreServers.isEmpty {
            let localServer = CalibreServer(baseUrl: UIDevice().name, username: "", password: "")
            calibreServers[localServer.id] = localServer
            updateServerRealm(server: localServer)
            currentCalibreServerId = localServer.id
        }
        
        populateLibraries()
        
        if currentCalibreLibraryId.isEmpty == false {
            DispatchQueue(label: "data").async {
                let realm = try! Realm(configuration: self.realmConf)
                self.populateServerLibraryBooks(realm: realm)
            }
        }
        
        let booksInShelfRealm = realm.objects(CalibreBookRealm.self).filter(
            NSPredicate(format: "inShelf = true")
        )
        
        booksInShelfRealm.forEach { (bookRealm) in
            // print(bookRealm)
            let server = calibreServers[CalibreServer(baseUrl: bookRealm.serverUrl!, username: bookRealm.serverUsername!, password: "").id]!
            let library = CalibreLibrary(server: server, key: bookRealm.libraryName!, name: bookRealm.libraryName!)
            let book = self.convert(library: library, bookRealm: bookRealm)
            self.booksInShelf[book.inShelfId] = book
        }
        
        switch UIDevice.current.userInterfaceIdiom {
            case .phone:
                defaultFormat = CalibreBook.Format.EPUB
            case .pad:
                defaultFormat = CalibreBook.Format.PDF
            default:
                defaultFormat = CalibreBook.Format.EPUB
        }
    }
    
    func populateLibraries() {
        let currentCalibreServer = calibreServers[currentCalibreServerId]!
        
        let librariesCached = realm.objects(CalibreLibraryRealm.self)

        librariesCached.forEach { libraryRealm in
            guard let calibreServer = calibreServers[CalibreServer(baseUrl: libraryRealm.serverUrl!, username: libraryRealm.serverUsername!, password: "").id] else {
                print("Unknown Server: \(libraryRealm)")
                return
            }
            let calibreLibrary = CalibreLibrary(server: calibreServer, key: libraryRealm.key ?? libraryRealm.name!, name: libraryRealm.name!, readPosColumnName: libraryRealm.readPosColumnName, goodreadsSyncProfileName: libraryRealm.goodreadsSyncProfileName)
            calibreLibraries[calibreLibrary.id] = calibreLibrary
        }
        
        if librariesCached.isEmpty && calibreServers.count == 1 {
            let localLibrary = CalibreLibrary(server: calibreServers.values.first!, key: "Local_Library", name: "Local Library")
            calibreLibraries[localLibrary.id] = localLibrary
            updateLibraryRealm(library: localLibrary)
            currentCalibreLibraryId = localLibrary.id
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
    
    func getBookInShelf(inShelfId: String) -> Binding<CalibreBook> {
        return getBook(library: booksInShelf[inShelfId]!.library, bookId: booksInShelf[inShelfId]!.id)
    }
    
    func getCurrentServerLibraryBook(bookId: Int32) -> Binding<CalibreBook> {
        return getBook(library: calibreLibraries[currentCalibreLibraryId]!, bookId: bookId)
    }
    
    func getBook(library: CalibreLibrary, bookId: Int32) -> Binding<CalibreBook> {
        return Binding<CalibreBook>(
            get: {
                if library.id == self.currentCalibreLibraryId {
                    return self.calibreServerLibraryBooks[bookId]!
                } else {
                    let booksRealm = self.realm.objects(CalibreBookRealm.self).filter(
                        NSPredicate(format: "serverUrl = %@ AND serverUsername = %@ AND libraryName = %@ AND id = %@",
                                    library.server.baseUrl,
                                    library.server.username,
                                    library.name,
                                    NSNumber(value: bookId))
                        )
                    assert(!booksRealm.isEmpty, "illegal params")
                    
                    return self.convert(library: library, bookRealm: booksRealm.first!)
                }
            },
            set: { [self] book in
                updateBookRealm(book: book, realm: realm)
                if calibreLibraries[currentCalibreLibraryId] == library {
                    calibreServerLibraryBooks[book.id] = book
                }
                if book.inShelf {
                    //TODO
                }
            }
        )
    }


    func updateStoreReadingPosition(enabled: Bool, value: String) {
        calibreLibraries[currentCalibreLibraryId]!.readPosColumnName = enabled ? value : nil
        updateLibraryRealm(library: calibreLibraries[currentCalibreLibraryId]!)
    }
    
    func updateGoodreadsSyncProfileName(enabled: Bool, value: String) {
        calibreLibraries[currentCalibreLibraryId]!.goodreadsSyncProfileName = enabled ? value : nil
        updateLibraryRealm(library: calibreLibraries[currentCalibreLibraryId]!)
    }
    
    func updateCustomDictViewer(enabled: Bool, value: String) {
        //TODO
    }
    
    func addServer(server: CalibreServer, libraries: [CalibreLibrary]) {
        calibreServers[server.id] = server
        updateServerRealm(server: server)
        
        libraries.forEach { (library) in
            calibreLibraries[library.id] = library
            updateLibraryRealm(library: library)
        }
    }
    
    func updateServerRealm(server: CalibreServer) {
        let serverRealm = CalibreServerRealm()
        serverRealm.baseUrl = server.baseUrl
        serverRealm.username = server.username
        serverRealm.password = server.password
        serverRealm.defaultLibrary = server.defaultLibrary
        try! realm.write {
            realm.add(serverRealm, update: .all)
        }
    }
    
    func updateLibraryRealm(library: CalibreLibrary) {
        let libraryRealm = CalibreLibraryRealm()
        libraryRealm.key = library.key
        libraryRealm.name = library.name
        libraryRealm.serverUrl = library.server.baseUrl
        libraryRealm.serverUsername = library.server.username
        libraryRealm.readPosColumnName = library.readPosColumnName
        libraryRealm.goodreadsSyncProfileName = library.goodreadsSyncProfileName
        try! realm.write {
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
    
    
    func handleLibraryInfo(jsonData: Data) {
        do {
            let libraryInfo = try JSONSerialization.jsonObject(with: jsonData, options: []) as! NSDictionary
            defaultLog.info("libraryInfo: \(libraryInfo)")
            
            let libraryMap = libraryInfo["library_map"] as! [String: String]
            libraryMap.forEach { (key, value) in
                let library = CalibreLibrary(server: calibreServers[currentCalibreServerId]!, key: key, name: value)
                if calibreLibraries[library.id] == nil {
                    calibreLibraries[library.id] = library
                    
                    updateLibraryRealm(library: library)
                }
            }
            if let defaultLibrary = libraryInfo["default_library"] as? String {
                if calibreServers[currentCalibreServerId]!.defaultLibrary != defaultLibrary {
                    calibreServers[currentCalibreServerId]!.defaultLibrary = defaultLibrary
                    
                    updateServerRealm(server: calibreServers[currentCalibreServerId]!)
                }
            }
        } catch {
        
        }
        
    }
    
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
            book.rating = v.intValue
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
    
    func addToShelf(_ bookId: Int32, shelfName: String? = nil) {
        readingBook?.inShelf = true
        calibreServerLibraryBooks[bookId]!.inShelf = true
        if let shelfName = shelfName {
            readingBook?.inShelfName = shelfName
            calibreServerLibraryBooks[bookId]!.inShelfName = shelfName
        } else if readingBook?.inShelfName.isEmpty ?? false, let tag = readingBook?.tags.first {
            readingBook?.inShelfName = tag
            calibreServerLibraryBooks[bookId]!.inShelfName = tag
        } else {
            
        }
        
        updateBookRealm(book: calibreServerLibraryBooks[bookId]!, realm: self.realm)
        booksInShelf[calibreServerLibraryBooks[bookId]!.inShelfId] = calibreServerLibraryBooks[bookId]!
        
        if let book = readingBook, let library = calibreLibraries[book.library.id], let goodreadsId = book.identifiers["goodreads"], let goodreadsSyncProfileName = library.goodreadsSyncProfileName, goodreadsSyncProfileName.count > 0 {
            let connector = GoodreadsSyncConnector(server: library.server, profileName: goodreadsSyncProfileName)
            let ret = connector.addToShelf(goodreads_id: goodreadsId, shelfName: "currently-reading")
        }
    }
    
    func removeFromShelf(inShelfId: String) {
        readingBook?.inShelf = false
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
    
    func downloadFormat(book: CalibreBook, format: CalibreBook.Format, modificationDate: Date? = nil, overwrite: Bool = false, complete: @escaping (Bool) -> Void) -> Bool {
        guard book.formats[format.rawValue] != nil else {
            complete(false)
            return false
        }
        
        let url = URL(string: book.library.server.baseUrl + "/get/\(format.rawValue)/\(book.id)/\(book.library.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)")
        defaultLog.info("downloadURL: \(url!.absoluteString)")
        
        let downloadBaseURL = try!
            FileManager.default.url(for: .cachesDirectory,
                                    in: .userDomainMask,
                                    appropriateFor: nil,
                                    create: false)
        if !FileManager.default.fileExists(atPath: downloadBaseURL.path) {
            try! FileManager.default.createDirectory(atPath: downloadBaseURL.path, withIntermediateDirectories: true)
        }
        let savedURL = downloadBaseURL.appendingPathComponent("\(book.library.name) - \(book.id).\(format.rawValue.lowercased())")
        
        self.defaultLog.info("savedURL: \(savedURL.absoluteString)")
        if FileManager.default.fileExists(atPath: savedURL.path) && !overwrite {
            complete(true)
            return false
        }
        
        let downloadTask = URLSession.shared.downloadTask(with: url!) {
            urlOrNil, responseOrNil, errorOrNil in
            // check for and handle errors:
            // * errorOrNil should be nil
            // * responseOrNil should be an HTTPURLResponse with statusCode in 200..<299
            
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
    
    func clearCache(inShelfId: String, _ format: CalibreBook.Format) {
        guard let book = booksInShelf[inShelfId] else {
            return
        }
        
        do {
            let documentURL = try FileManager.default.url(for: .documentDirectory,
                                                          in: .userDomainMask,
                                                          appropriateFor: nil,
                                                          create: false)
            let savedURL = documentURL.appendingPathComponent("\(book.library.name) - \(book.id).\(format.rawValue.lowercased())")
            let isFileExist = FileManager.default.fileExists(atPath: savedURL.path)
            if( isFileExist) {
                try FileManager.default.removeItem(at: savedURL)
            }
        } catch {
            defaultLog.error("clearCache \(error.localizedDescription)")
        }
        
        do {
            let downloadBaseURL = try FileManager.default.url(for: .cachesDirectory,
                                                          in: .userDomainMask,
                                                          appropriateFor: nil,
                                                          create: false)
            let savedURL = downloadBaseURL.appendingPathComponent("\(book.library.name) - \(book.id).\(format.rawValue.lowercased())")
            let isFileExist = FileManager.default.fileExists(atPath: savedURL.path)
            if( isFileExist) {
                try FileManager.default.removeItem(at: savedURL)
            }
        } catch {
            defaultLog.error("clearCache \(error.localizedDescription)")
        }
    }
    
    func clearCache(book: CalibreBook, format: CalibreBook.Format) {
        do {
            let documentURL = try FileManager.default.url(for: .documentDirectory,
                                                          in: .userDomainMask,
                                                          appropriateFor: nil,
                                                          create: false)
            let savedURL = documentURL.appendingPathComponent("\(book.library.name) - \(book.id).\(format.rawValue.lowercased())")
            let isFileExist = FileManager.default.fileExists(atPath: savedURL.path)
            if( isFileExist) {
                try FileManager.default.removeItem(at: savedURL)
            }
        } catch {
            defaultLog.error("clearCache \(error.localizedDescription)")
        }
        
        do {
            let downloadBaseURL = try FileManager.default.url(for: .cachesDirectory,
                                                          in: .userDomainMask,
                                                          appropriateFor: nil,
                                                          create: false)
            let savedURL = downloadBaseURL.appendingPathComponent("\(book.library.name) - \(book.id).\(format.rawValue.lowercased())")
            let isFileExist = FileManager.default.fileExists(atPath: savedURL.path)
            if( isFileExist) {
                try FileManager.default.removeItem(at: savedURL)
            }
        } catch {
            defaultLog.error("clearCache \(error.localizedDescription)")
        }
    }
    
    func getCacheInfo(book: CalibreBook, format: CalibreBook.Format) -> (UInt64, Date?)? {
        var resultStorage: ObjCBool = false
        if let documentURL = try? FileManager.default.url(for: .documentDirectory,
                                                      in: .userDomainMask,
                                                      appropriateFor: nil,
                                                      create: false) {
            let savedURL = documentURL.appendingPathComponent("\(book.library.name) - \(book.id).\(format.rawValue.lowercased())")
            if FileManager.default.fileExists(atPath: savedURL.path, isDirectory: &resultStorage), resultStorage.boolValue == false, let attribs = try? FileManager.default.attributesOfItem(atPath: savedURL.path) as NSDictionary {
                return (attribs.fileSize(), attribs.fileModificationDate())
            }
        }
        
        if let downloadBaseURL = try? FileManager.default.url(for: .cachesDirectory,
                                                             in: .userDomainMask,
                                                             appropriateFor: nil,
                                                             create: false) {
            let savedURL = downloadBaseURL.appendingPathComponent("\(book.library.name) - \(book.id).\(format.rawValue.lowercased())")
            if FileManager.default.fileExists(atPath: savedURL.path), let attribs = try? FileManager.default.attributesOfItem(atPath: savedURL.path) as NSDictionary {
                return (attribs.fileSize(), attribs.fileModificationDate())
            }
        }
        
        return nil
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
    
    func getMetadata(oldbook: CalibreBook, completion: ((_ newbook: CalibreBook) -> Void)? = nil) {
        let endpointUrl = URL(string: oldbook.library.server.baseUrl + "/cdb/cmd/list/0?library_id=" + oldbook.library.key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)!
        let json:[Any] = [["all"], "", "", "id:\(oldbook.id)", -1]
        do {
            let data = try JSONSerialization.data(withJSONObject: json, options: [])
            
            var request = URLRequest(url: endpointUrl)
            request.httpMethod = "POST"
            request.httpBody = data
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("application/json", forHTTPHeaderField: "Accept")
            
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
                if !(200...299).contains(httpResponse.statusCode) {
                    defaultLog.warning("statusCode not 2xx: \(httpResponse.debugDescription)")
                    DispatchQueue.main.async {
                        updatingMetadataStatus = httpResponse.debugDescription
                        updatingMetadata = false
                        completion?(oldbook)
                    }
                    return
                }
                
                if let mimeType = httpResponse.mimeType, mimeType == "application/json",
                   let data = data,
                   let string = String(data: data, encoding: .utf8) {
                    DispatchQueue.main.async {
                        //self.webView.loadHTMLString(string, baseURL: url)
                        //                            defaultLog.warning("httpResponse: \(string)")
                        //book.comments = string
                        guard var book = handleLibraryBookOne(oldbook: oldbook, json: data) else {
                            completion?(oldbook)
                            return
                        }
                        
                        if( book.readPos.getDevices().isEmpty) {
                            book.readPos.addInitialPosition(UIDevice().name, "FolioReader")
                        }
                        
                        updateBook(book: book)
                        
                        updatingMetadataStatus = "Success"
                        updatingMetadata = false
                        
                        completion?(book)
                    }
                }
            }
            
            updatingMetadata = true
            task.resume()
            
        }catch{
        }
    }
    
    func updateCurrentPosition() {
        guard var readingBook = self.readingBook else {
            return
        }
        do {
            var deviceReadingPosition = getDeviceReadingPosition()
            if( deviceReadingPosition == nil ) {
                deviceReadingPosition = BookDeviceReadingPosition(id: deviceName, readerName: "FolioReader")
            }
            
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
            
            let endpointUrl = URL(string: readingBook.library.server.baseUrl + "/cdb/cmd/set_metadata/0?library_id=" + readingBook.library.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)!
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
                if let error = error {
                    // self.handleClientError(error)
                    defaultLog.warning("error: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        updatingMetadataStatus = error.localizedDescription
                        updatingMetadata = false
                    }
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse else {
                    defaultLog.warning("not httpResponse: \(response.debugDescription)")
                    DispatchQueue.main.async {
                        updatingMetadataStatus = response.debugDescription
                        updatingMetadata = false
                    }
                    return
                }
                if !(200...299).contains(httpResponse.statusCode) {
                    defaultLog.warning("statusCode not 2xx: \(httpResponse.debugDescription)")
                    DispatchQueue.main.async {
                        updatingMetadataStatus = httpResponse.debugDescription
                        updatingMetadata = false
                    }
                    return
                }
                
                guard let mimeType = httpResponse.mimeType, mimeType == "application/json",
                      let data = data else {
                    DispatchQueue.main.async {
                        updatingMetadataStatus = httpResponse.debugDescription
                        updatingMetadata = false
                    }
                    return
                }
                
                guard let root = try? JSONSerialization.jsonObject(with: data, options: []) as? NSDictionary else {
                    DispatchQueue.main.async {
                        updatingMetadataStatus = httpResponse.debugDescription
                        updatingMetadata = false
                    }
                    return
                }
                
                guard let result = root["result"] as? NSDictionary, let resultv = result["v"] as? NSDictionary else {
                    DispatchQueue.main.async {
                        updatingMetadataStatus = httpResponse.debugDescription
                        updatingMetadata = false
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
        let endpointUrl = URL(string: oldbook.library.server.baseUrl + "/get/json/\(oldbook.id)/" + oldbook.library.key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)!
        do {
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
                if !(200...299).contains(httpResponse.statusCode) {
                    defaultLog.warning("statusCode not 2xx: \(httpResponse.debugDescription)")
                    DispatchQueue.main.async {
                        updatingMetadataStatus = httpResponse.debugDescription
                        updatingMetadata = false
                        completion?(oldbook)
                    }
                    return
                }
                
                if let mimeType = httpResponse.mimeType, mimeType == "application/json",
                   let data = data,
                   let string = String(data: data, encoding: .utf8) {
                    DispatchQueue.main.async {
                        //self.webView.loadHTMLString(string, baseURL: url)
                        //                            defaultLog.warning("httpResponse: \(string)")
                        //book.comments = string
                        guard var book = handleLibraryBookOneNew(oldbook: oldbook, json: data) else {
                            completion?(oldbook)
                            return
                        }
                        
                        if( book.readPos.getDevices().isEmpty) {
                            book.readPos.addInitialPosition(UIDevice().name, "FolioReader")
                        }
                        
                        updateBook(book: book)
                        
                        updatingMetadataStatus = "Success"
                        updatingMetadata = false
                        
                        completion?(book)
                    }
                }
            }
            
            updatingMetadata = true
            task.resume()
            
        }catch{
        }
    }
    
    func getBookManifest(book: CalibreBook, format: CalibreBook.Format, completion: ((_ manifest: Data) -> Void)? = nil) {
        let endpointUrl = URL(string: book.library.server.baseUrl + "/book-manifest/\(book.id)/\(format.id)?library_id=" + book.library.key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)!

        let request = URLRequest(url: endpointUrl)
        
        let task = URLSession.shared.dataTask(with: request) { [self] data, response, error in
            let emptyData = "{}".data(using: .ascii)!
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
            if !(200...299).contains(httpResponse.statusCode) {
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

enum LibraryError: Error {
    case runtimeError(String)
}

