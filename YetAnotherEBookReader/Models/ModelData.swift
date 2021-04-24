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

#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

final class ModelData: ObservableObject {
//    @Published var calibreServer = "http://calibre-server.lan:8080/"
//    @Published var calibreUsername = ""
//    @Published var calibrePassword = ""
    @Published var calibreServers = [String: CalibreServer]()
    @Published var currentCalibreServerId = "" {
        didSet {
            UserDefaults.standard.set(currentCalibreServerId, forKey: Constants.KEY_DEFAULTS_SELECTED_SERVER_ID)
            
            currentBookId = 0
            filteredBookList.removeAll()
            calibreServerLibraryBooks.removeAll()
            calibreServerLibraries.removeAll()
            populateServerLibraries()
        }
    }
    
    @Published var calibreServerLibraries = [String: CalibreLibrary]()
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
    
    private var defaultLog = Logger()
    
    private var realm: Realm!
    private let realmConf = Realm.Configuration(
        schemaVersion: 11,
        migrationBlock: { migration, oldSchemaVersion in
                if oldSchemaVersion < 9 {
                    // if you added a new property or removed a property you don't
                    // have to do anything because Realm automatically detects that
                    
                }
            }
    )
    init() {
        #if canImport(GoogleMobileAds)
        GADMobileAds.sharedInstance().start(completionHandler: nil)
        #endif
        
        realm = try! Realm(
            configuration: realmConf
        )
        
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
        
        if currentCalibreServerId.isEmpty == false {
            populateServerLibraries()
        }
        
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
    
    func populateServerLibraries() {
        let currentCalibreServer = calibreServers[currentCalibreServerId]!
        
        let librariesCached = realm.objects(CalibreLibraryRealm.self).filter(
                    NSPredicate(format: "serverUrl = %@ AND serverUsername = %@",
                                currentCalibreServer.baseUrl,
                                currentCalibreServer.username)
        ).sorted(byKeyPath: "name")

        librariesCached.forEach { libraryRealm in
            let calibreLibrary = CalibreLibrary(server: currentCalibreServer, key: libraryRealm.key ?? libraryRealm.name!, name: libraryRealm.name!)
            calibreServerLibraries[calibreLibrary.id] = calibreLibrary
        }
        
        if librariesCached.isEmpty && calibreServers.count == 1 {
            let localLibrary = CalibreLibrary(server: calibreServers.values.first!, key: "Local_Library", name: "Local Library")
            calibreServerLibraries[localLibrary.id] = localLibrary
            updateLibraryRealm(library: localLibrary)
            currentCalibreLibraryId = localLibrary.id
        }
        
        if let lastCalibreLibrary = UserDefaults.standard.string(forKey: Constants.KEY_DEFAULTS_SELECTED_LIBRARY_ID), calibreServerLibraries[lastCalibreLibrary] != nil {
            currentCalibreLibraryId = lastCalibreLibrary

        } else {
            let defaultLibrary = CalibreLibrary(server: currentCalibreServer, key: currentCalibreServer.defaultLibrary, name: currentCalibreServer.defaultLibrary)
            currentCalibreLibraryId = defaultLibrary.id
        }
        
        
    }
    
    /**
            Must not run on main thread
     */
    func populateServerLibraryBooks(realm: Realm) {
        guard let currentCalibreLibrary = calibreServerLibraries[currentCalibreLibraryId] else {
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
            return (book.formats["EPUB"] != nil || book.formats["PDF"] != nil )
                && (searchString.isEmpty || book.title.contains(searchString))
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
            inShelf: bookRealm.inShelf)
        calibreBook.authors.append(contentsOf: bookRealm.authors)
        calibreBook.tags.append(contentsOf: bookRealm.tags)
        return calibreBook
    }
    
    func getBookInShelf(inShelfId: String) -> Binding<CalibreBook> {
        return getBook(library: booksInShelf[inShelfId]!.library, bookId: booksInShelf[inShelfId]!.id)
    }
    
    func getCurrentServerLibraryBook(bookId: Int32) -> Binding<CalibreBook> {
        return getBook(library: calibreServerLibraries[currentCalibreLibraryId]!, bookId: bookId)
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
                if calibreServerLibraries[currentCalibreLibraryId] == library {
                    calibreServerLibraryBooks[book.id] = book
                }
                if book.inShelf {
                    //TODO
                }
            }
        )
    }


    func updateStoreReadingPosition(enabled: Bool, value: String) {
        //TODO
    }
    
    func updateCustomDictViewer(enabled: Bool, value: String) {
        //TODO
    }
    
    func addServer(server: CalibreServer, libraries: [CalibreLibrary]) {
        calibreServers[server.id] = server
        updateServerRealm(server: server)
        
        libraries.forEach { (library) in
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
            //TODO
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
        
        bookRealm.formatsData = try! JSONSerialization.data(withJSONObject: book.formats, options: []) as NSData
        
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
                if calibreServerLibraries[library.id] == nil {
                    calibreServerLibraries[library.id] = library
                    
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
        let library = calibreServerLibraries[currentCalibreLibraryId]!
        
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
    
    func addToShelf(_ bookId: Int32) {
        readingBook?.inShelf = true
        calibreServerLibraryBooks[bookId]!.inShelf = true
        
        updateBookRealm(book: calibreServerLibraryBooks[bookId]!, realm: self.realm)
        booksInShelf[calibreServerLibraryBooks[bookId]!.inShelfId] = calibreServerLibraryBooks[bookId]!
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
    }
    
    func downloadFormat(_ bookId: Int32, _ format: CalibreBook.Format, complete: @escaping (Bool) -> Void) -> Bool {
        let book = calibreServerLibraryBooks[bookId]!
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
        if FileManager.default.fileExists(atPath: savedURL.path) {
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
                
                try FileManager.default.moveItem(at: fileURL, to: savedURL)
                
                let isFileExist = FileManager.default.fileExists(atPath: savedURL.path)
                self.defaultLog.info("isFileExist: \(isFileExist)")
                
                complete(true)
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
    
    func getSelectedReadingPosition() -> BookDeviceReadingPosition? {
        return readingBook!.readPos.getPosition(selectedPosition)
    }
    
    func updateCurrentPosition(_ position: [String: Any]?) {
        guard (position != nil) else { return }
        guard var readingBook = self.readingBook else {
            return
        }
        do {
            
            let deviceName = UIDevice().name
            
            var deviceReadingPosition = readingBook.readPos.getPosition(deviceName)
            if( deviceReadingPosition == nil ) {
                deviceReadingPosition = BookDeviceReadingPosition(id: deviceName, readerName: "FolioReader")
            }
            
            defaultLog.info("pageNumber:  \(position!["pageNumber"]! as! Int)")
            defaultLog.info("pageOffsetX: \(position!["pageOffsetX"]! as! CGFloat)")
            defaultLog.info("pageOffsetY: \(position!["pageOffsetY"]! as! CGFloat)")
            
            deviceReadingPosition!.lastPosition[0] = position!["pageNumber"]! as! Int
            deviceReadingPosition!.lastPosition[1] = Int((position!["pageOffsetX"]! as! CGFloat).rounded())
            deviceReadingPosition!.lastPosition[2] = Int((position!["pageOffsetY"]! as! CGFloat).rounded())
            deviceReadingPosition!.lastReadPage = position!["pageNumber"]! as! Int
            
            readingBook.readPos.updatePosition(deviceName, deviceReadingPosition!)
            
            var deviceMapSerialize = [String: Any]()
            try readingBook.readPos.getCopy().forEach { key, value in
                deviceMapSerialize[key] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
            }
            
            
            let readPosData = try JSONSerialization.data(withJSONObject: ["deviceMap": deviceMapSerialize], options: []).base64EncodedString()
            
            let endpointUrl = URL(string: readingBook.library.server.baseUrl + "/cdb/cmd/set_metadata/0?library_id=" + readingBook.library.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)!
            let json:[Any] = ["fields", readingBook.id, [["#read_pos", readPosData]]]
            
            let data = try JSONSerialization.data(withJSONObject: json, options: [])
            defaultLog.warning("JSON: \(String(data: data, encoding: .utf8)!)")
            
            var request = URLRequest(url: endpointUrl)
            request.httpMethod = "POST"
            request.httpBody = data
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("application/json", forHTTPHeaderField: "Accept")
            
            let task = URLSession.shared.dataTask(with: request) { [self] data, response, error in
                if let error = error {
                    // self.handleClientError(error)
                    defaultLog.warning("error: \(error.localizedDescription)")
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    // self.handleServerError(response)
                    defaultLog.warning("not httpResponse: \(response.debugDescription)")
                    return
                }
                
                if let mimeType = httpResponse.mimeType, mimeType == "application/json",
                   let data = data {
                    DispatchQueue.main.async {
                        //self.webView.loadHTMLString(string, baseURL: url)
                        //result = string
                        //                            defaultLog.warning("httpResponse: \(string)")
                        self.updateBook(book: readingBook)
                    }
                }
            }
            
            task.resume()
        }catch{
        }
        
        // modelData.isReading = false
    }
    
    
    func goToPreviousBook() {
        if let curIndex = filteredBookList.firstIndex(of: currentBookId), curIndex > 0 {
            currentBookId = filteredBookList[curIndex-1]
            
        }
    }
    
    func goToNextBook() {
        print("currentBookId before \(currentBookId) \(selectedBookId)")
        if let curIndex = filteredBookList.firstIndex(of: selectedBookId ?? currentBookId), curIndex < filteredBookList.count - 1 {
            currentBookId = filteredBookList[curIndex + 1]
        }
        print("currentBookId after \(currentBookId) \(selectedBookId)")
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

class ConfigurationRealm: Object {
    @objc dynamic var id: Int32 = 0
    @objc dynamic var libraryName = ""
    @objc dynamic var title = ""
    @objc dynamic var authors = ""
    @objc dynamic var comments = ""
    @objc dynamic var formatsData: NSData?
}
