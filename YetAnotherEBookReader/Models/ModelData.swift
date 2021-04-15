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
import GoogleMobileAds

final class ModelData: ObservableObject {
//    @Published var calibreServer = "http://calibre-server.lan:8080/"
//    @Published var calibreUsername = ""
//    @Published var calibrePassword = ""
    @Published var calibreServers = [String: CalibreServer]()
    @Published var currentCalibreServerId = "" {
        didSet {
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
            currentBookId = 0
            filteredBookList.removeAll()
            calibreServerLibraryBooks.removeAll()
            populateServerLibraryBooks()
        }
    }
    
    @Published var calibreServerLibraryBooks = [Int32: CalibreBook]()
    
    //for LibraryInfoView
    @Published var defaultFormat = CalibreBook.Format.PDF
    @Published var searchString = ""
    @Published var filteredBookList = [Int32]()
    
    @Published var booksInShelf = [String: CalibreBook]()
    
    var currentBookId: Int32 = -1 {
            didSet {
                self.selectionLibraryNav = currentBookId
            }
        }

    @Published var selectionLibraryNav: Int32? = nil
    
    @Published var loadLibraryResult = "Waiting"
    
    private var defaultLog = Logger()
    
    private var realm: Realm!
    init() {
        GADMobileAds.sharedInstance().start(completionHandler: nil)
        
        realm = try! Realm(
            configuration: Realm.Configuration(
                schemaVersion: 8,
                migrationBlock: { migration, oldSchemaVersion in
                        if oldSchemaVersion < 5 {
                            // if you added a new property or removed a property you don't
                            // have to do anything because Realm automatically detects that
                        }
                    }
            )
        )
        
        let lastServerUrl = UserDefaults.standard.string(forKey: Constants.KEY_DEFAULTS_SELECTED_SERVER_URL)
        let lastServerUsername = UserDefaults.standard.string(forKey: Constants.KEY_DEFAULTS_SELECTED_SERVER_USERNAME)
        
        let serverSortProperties = [SortDescriptor(keyPath: "username"), SortDescriptor(keyPath: "baseUrl")]
        let serversCached = realm.objects(CalibreServerRealm.self).sorted(by: serverSortProperties)
        serversCached.forEach { serverRealm in
            let calibreServer = CalibreServer(baseUrl: serverRealm.baseUrl!, username: serverRealm.username!, password: serverRealm.password!)
            calibreServers[calibreServer.id] = calibreServer
            if lastServerUrl == calibreServer.baseUrl && lastServerUsername == calibreServer.username {
                currentCalibreServerId = calibreServer.id
            }
        }
        
        if calibreServers.isEmpty {
            let localServer = CalibreServer(baseUrl: UIDevice().name, username: "", password: "")
            calibreServers[localServer.id] = localServer
            updateServerRealm(server: localServer)
            currentCalibreServerId = localServer.id
        }
        
        if currentCalibreServerId.isEmpty == false {
            let currentCalibreServer = calibreServers[currentCalibreServerId]!
            populateServerLibraries()
        }
        
        if currentCalibreLibraryId.isEmpty == false {
            let currentCalibreLibrary = calibreServerLibraries[currentCalibreLibraryId]!
            populateServerLibraryBooks()
        }
        
        let booksInShelfRealm = realm.objects(CalibreBookRealm.self).filter(
            NSPredicate(format: "inShelf = true")
        )
        
        booksInShelfRealm.forEach { (bookRealm) in
            // print(bookRealm)
            let server = calibreServers[CalibreServer(baseUrl: bookRealm.serverUrl!, username: bookRealm.serverUsername!, password: "").id]!
            let library = CalibreLibrary(server: server, name: bookRealm.libraryName!)
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
            
        let lastLibraryName = UserDefaults.standard.string(forKey: Constants.KEY_DEFAULTS_SELECTED_LIBRARY_NAME)
        
        librariesCached.forEach { libraryRealm in
            let calibreLibrary = CalibreLibrary(server: currentCalibreServer, name: libraryRealm.name!)
            calibreServerLibraries[calibreLibrary.id] = calibreLibrary
            if lastLibraryName == calibreLibrary.name {
                currentCalibreLibraryId = calibreLibrary.id
            }
        }
        if calibreServerLibraries[currentCalibreLibraryId] == nil {
            let defaultLibrary = CalibreLibrary(server: currentCalibreServer, name: currentCalibreServer.defaultLibrary)
            currentCalibreLibraryId = defaultLibrary.id
        }
        
        if librariesCached.isEmpty && calibreServers.count == 1 {
            let localLibrary = CalibreLibrary(server: calibreServers.values.first!, name: "Local Library")
            calibreServerLibraries[localLibrary.id] = localLibrary
            updateLibraryRealm(library: localLibrary)
            currentCalibreLibraryId = localLibrary.id
        }
    }
    
    func populateServerLibraryBooks() {
        guard let currentCalibreLibrary = calibreServerLibraries[currentCalibreLibraryId] else {
            return
        }
        
        let booksCached = realm.objects(CalibreBookRealm.self).filter(
            NSPredicate(format: "serverUrl = %@ AND serverUsername = %@ AND libraryName = %@",
                        currentCalibreLibrary.server.baseUrl,
                        currentCalibreLibrary.server.username,
                        currentCalibreLibrary.name
            )
        ).sorted(byKeyPath: "id")
        booksCached.forEach { bookRealm in
            calibreServerLibraryBooks[bookRealm.id] = self.convert(library: currentCalibreLibrary, bookRealm: bookRealm)
        }
    }
    
    func updateFilteredBookList(searchString: String?) {
        filteredBookList = calibreServerLibraryBooks.values.filter { (book) -> Bool in
            return (book.formats["EPUB"] != nil || book.formats["PDF"] != nil )
                && (searchString == nil || searchString!.isEmpty || book.title.contains(searchString!))
        }.sorted { (lhs, rhs) -> Bool in
            lhs.title < rhs.title
        }.map({ $0.id })
    }
    
    func convert(library: CalibreLibrary, bookRealm: CalibreBookRealm) -> CalibreBook {
        let calibreBook = CalibreBook(
            id: bookRealm.id,
            library: library,
            title: bookRealm.title,
            authors: bookRealm.authors,
            comments: bookRealm.comments,
            rating: bookRealm.rating,
            formats: bookRealm.formats(),
            readPos: bookRealm.readPos(),
            inShelf: bookRealm.inShelf)
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
                updateBookRealm(book: book)
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
        libraryRealm.name = library.name
        libraryRealm.serverUrl = library.server.baseUrl
        libraryRealm.serverUsername = library.server.username
        try! realm.write {
            realm.add(libraryRealm, update: .all)
        }
    }
    
    func updateBookRealm(book: CalibreBook) {
        let bookRealm = CalibreBookRealm()
        bookRealm.id = book.id
        bookRealm.serverUrl = book.library.server.baseUrl
        bookRealm.serverUsername = book.library.server.username
        bookRealm.libraryName = book.library.name
        bookRealm.title = book.title
        bookRealm.authors = book.authors
        bookRealm.comments = book.comments
        bookRealm.rating = book.rating
        bookRealm.inShelf = book.inShelf
        
        bookRealm.formatsData = try! JSONSerialization.data(withJSONObject: book.formats, options: []) as NSData
        
        let deviceMapSerialize = book.readPos.getCopy().mapValues { (value) -> Any in
            try! JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
        }
        
        bookRealm.readPosData = try! JSONSerialization.data(withJSONObject: ["deviceMap": deviceMapSerialize], options: []) as NSData
        
        try! realm.write {
            realm.add(bookRealm, update: .modified)
        }
    }
    
    func startLoad(calibreServer: CalibreServer, success: @escaping (_ jsonData: Data) -> Void) -> Int {
        guard let url = URL(string: calibreServer.baseUrl + "/ajax/library-info") else {
            return 2
        }
        if calibreServer.username.count > 0 && calibreServer.password.count > 0 {
            let protectionSpace = URLProtectionSpace.init(host: url.host!,
                                                          port: url.port ?? 0,
                                                          protocol: url.scheme,
                                                          realm: "calibre",
                                                          authenticationMethod: NSURLAuthenticationMethodHTTPBasic)
            let userCredential = URLCredential(user: calibreServer.username,
                                               password: calibreServer.password,
                                               persistence: .permanent)
            URLCredentialStorage.shared.setDefaultCredential(userCredential, for: protectionSpace)
        }
        
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                // self.handleClientError(error)
                print(error.localizedDescription)
                self.loadLibraryResult = error.localizedDescription
                return
            }
            guard let httpResponse = response as? HTTPURLResponse,
                (200...299).contains(httpResponse.statusCode) else {
                // self.handleServerError(response)
                self.loadLibraryResult = "not httpResponse"
                return
            }
            if let mimeType = httpResponse.mimeType, mimeType == "application/json",
                let data = data,
                let string = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    //self.webView.loadHTMLString(string, baseURL: url)
                    self.loadLibraryResult = string
                    //self.handleLibraryInfo(jsonData: data)
                    success(data)
                }
            }
        }
        task.resume()
        return 0
    }
    
    func handleLibraryInfo(jsonData: Data) {
        do {
            let libraryInfo = try JSONSerialization.jsonObject(with: jsonData, options: []) as! NSDictionary
            defaultLog.info("libraryInfo: \(libraryInfo)")
            
            let libraryMap = libraryInfo["library_map"] as! [String: String]
            libraryMap.forEach { (key, value) in
                let library = CalibreLibrary(server: calibreServers[currentCalibreServerId]!, name: value)
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
    
    func handleLibraryBooks(json: Data) {
        let library = calibreServerLibraries[currentCalibreLibraryId]!
        
        do {
            let root = try JSONSerialization.jsonObject(with: json, options: []) as! NSDictionary
            let resultElement = root["result"] as! NSDictionary
            let bookIds = resultElement["book_ids"] as! NSArray
            
            bookIds.forEach { idNum in
                let id = (idNum as! NSNumber).int32Value
                if calibreServerLibraryBooks[id] == nil {
                    calibreServerLibraryBooks[id] = CalibreBook(id: id, library: library)
                }
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
                calibreServerLibraryBooks[id]!.authors = authors[0] as? String ?? "Unknown"
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
            
//            try! realm.write {
//                realm.add(calibreServerLibraryBooks.values.map({ (book) -> CalibreBookRealm in
//                    convert(book: book)
//                }), update: .modified)
//            }
            calibreServerLibraryBooks.values.forEach { (book) in
                updateBookRealm(book: book)
            }
        } catch {
        
        }
        
    }
    
    func addToShelf(_ bookId: Int32) {
        calibreServerLibraryBooks[bookId]!.inShelf = true
        
        updateBookRealm(book: calibreServerLibraryBooks[bookId]!)
        booksInShelf[calibreServerLibraryBooks[bookId]!.inShelfId] = calibreServerLibraryBooks[bookId]!
    }
    
    func removeFromShelf(inShelfId: String) {
        booksInShelf[inShelfId]!.inShelf = false
        
        let book = booksInShelf[inShelfId]!
        updateBookRealm(book: book)
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
        let downloadTask = URLSession.shared.downloadTask(with: url!) {
            urlOrNil, responseOrNil, errorOrNil in
            // check for and handle errors:
            // * errorOrNil should be nil
            // * responseOrNil should be an HTTPURLResponse with statusCode in 200..<299
            
            guard let fileURL = urlOrNil else { complete(false); return }
            do {
                let downloadBaseURL = try
                    FileManager.default.url(for: .cachesDirectory,
                                            in: .userDomainMask,
                                            appropriateFor: nil,
                                            create: false)
                if !FileManager.default.fileExists(atPath: downloadBaseURL.path) {
                    try FileManager.default.createDirectory(atPath: downloadBaseURL.path, withIntermediateDirectories: true)
                }
                let savedURL = downloadBaseURL.appendingPathComponent("\(book.library.name) - \(book.id).\(format.rawValue.lowercased())")
                
                self.defaultLog.info("fileURL: \(fileURL.absoluteString)")
                self.defaultLog.info("savedURL: \(savedURL.absoluteString)")
                if FileManager.default.fileExists(atPath: savedURL.path) {
                    try FileManager.default.removeItem(at: savedURL)
                }
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
