//
//  Book.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/1/27.
//

import Foundation
import RealmSwift
import SwiftUI
import OSLog

struct ServerInfo {
    var calibreServer: String
}

struct LibraryInfo {
    var libraryMap = [String: Library]()
    var libraries = [Library]()
    
    private var defaultLog = Logger()
    
    mutating func getLibrary(name: String) -> Library {
        guard let library = libraryMap[name] else {
            let library = Library(name: name)
            libraryMap[name] = library
            libraries.append(library)
            libraries.sort { (lhs, rhs) -> Bool in
                lhs.name < rhs.name
            }
            return library
        }
        return library
    }
    
    mutating func regenArray() {
        libraries.removeAll()
        libraries.append(contentsOf: libraryMap.values)
        libraries.sort { (lhs, rhs) -> Bool in
            lhs.name < rhs.name
        }
    }
    
    mutating func updateBook(book: Book) {
        var library = libraryMap[book.libraryName]!
        
        library.booksMap[book.id] = book
        if let index = library.books.firstIndex(of: book) {
            library.books[index] = book
        } else {
            library.books.append(book)
        }
        library.books.sort {
            $0.title < $1.title
        }
        
        libraryMap[book.libraryName]! = library
        libraries[libraries.firstIndex(of: library)!] = library
    }
    
    mutating func deleteBook(book: Book) {
        var library = libraryMap[book.libraryName]!
        
        library.booksMap.removeValue(forKey: book.id)
        library.books.removeAll { inlist -> Bool in
            inlist == book
        }
        
        libraryMap[library.name]! = library
        libraries[libraries.firstIndex(of: library)!] = library
    }
    
    mutating func addToShelf(_ bookId: Int32, _ libraryName: String) {
        var book = libraryMap[libraryName]!.booksMap[bookId]!
        
        let realm = try! Realm(configuration: Realm.Configuration(schemaVersion: 2))
        
        let inShelf = realm.objects(BookRealm.self).filter(
            NSPredicate(format: "id = %@ AND libraryName = %@", NSNumber(value: book.id), book.libraryName)
        )
        if( !inShelf.isEmpty) {
            defaultLog.info("Already in shelf, count: \(realm.objects(BookRealm.self).count)")
            try! realm.write {
                realm.delete(inShelf)
            }
        }
        
        let bookRealm = BookRealm()
        bookRealm.id = book.id
        bookRealm.libraryName = book.libraryName
        bookRealm.title = book.title
        bookRealm.authors = book.authors
        bookRealm.comments = book.comments
        bookRealm.formatsData = try! JSONSerialization.data(withJSONObject: book.formats, options: []) as NSData
        
        try! realm.write {
            realm.add(bookRealm)
        }
        
        if book.inShelf == false {
            book.inShelf = true
            updateBook(book: book)
        }
        
        defaultLog.info("BookCount: \(realm.objects(BookRealm.self).count)")
    }
    
    mutating func removeFromShelf(_ bookId: Int32, _ libraryName: String) {
        var book = libraryMap[libraryName]!.booksMap[bookId]!
        
        let realm = try! Realm(configuration: Realm.Configuration(schemaVersion: 2))
        let inShelf = realm.objects(BookRealm.self).filter(
            NSPredicate(format: "id = %@ AND libraryName = %@", NSNumber(value: book.id), book.libraryName)
        )
        try! realm.write {
            realm.delete(inShelf)
        }
        
        book.inShelf = false
        updateBook(book: book)
        
        print(book.inShelf)
        
    }
    
    func downloadFormat(_ bookId: Int32, _ libraryName: String, _ format: Book.Format, complete: @escaping (Bool) -> Void) -> Bool {
        let book = libraryMap[libraryName]!.booksMap[bookId]!
        guard let formatDetail = book.formats[format.rawValue] else {
            complete(false)
            return false
        }
        
        let url = URL(string: book.serverInfo.calibreServer + "/get/\(format.rawValue)/\(book.id)/\(book.libraryName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)")
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
                let savedURL = downloadBaseURL.appendingPathComponent("\(book.libraryName) - \(book.id).\(format.rawValue.lowercased())")
                
                defaultLog.info("fileURL: \(fileURL.absoluteString)")
                defaultLog.info("savedURL: \(savedURL.absoluteString)")
                if FileManager.default.fileExists(atPath: savedURL.path) {
                    try FileManager.default.removeItem(at: savedURL)
                }
                try FileManager.default.moveItem(at: fileURL, to: savedURL)
                
                let isFileExist = FileManager.default.fileExists(atPath: savedURL.path)
                defaultLog.info("isFileExist: \(isFileExist)")
                
                complete(true)
            } catch {
                print ("file error: \(error)")
                complete(false)
            }
        }
        downloadTask.resume()
        return true
    }
    
    func clearCache(_ bookId: Int32, _ libraryName: String, _ format: Book.Format) {
        do {
            let documentURL = try FileManager.default.url(for: .documentDirectory,
                                                          in: .userDomainMask,
                                                          appropriateFor: nil,
                                                          create: false)
            let savedURL = documentURL.appendingPathComponent("\(libraryName) - \(bookId).\(format.rawValue.lowercased())")
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
            let savedURL = downloadBaseURL.appendingPathComponent("\(libraryName) - \(bookId).\(format.rawValue.lowercased())")
            let isFileExist = FileManager.default.fileExists(atPath: savedURL.path)
            if( isFileExist) {
                try FileManager.default.removeItem(at: savedURL)
            }
        } catch {
            defaultLog.error("clearCache \(error.localizedDescription)")
        }
    }
    
}

struct Library: Hashable, Identifiable {
    var id: String {
        get { return name }
    }
    static func == (lhs: Library, rhs: Library) -> Bool {
        lhs.id == rhs.id
    }
    var name: String
    var books = [Book]()
    var booksMap = [Int32: Book]()
    
    mutating func updateBooks(_ newBooksMap: [Int32: Book]) {
        booksMap.removeAll()
        booksMap.merge(newBooksMap) { $1 }
        
        books.removeAll()
        books.append(
            contentsOf: booksMap.values.sorted {
                        $0.title < $1.title
                    }
        )
    }
    
    func filterBooks(_ searchString: String) -> [Book]{
        return books.filter({ book in
            (book.formats["EPUB"] != nil || book.formats["PDF"] != nil )
            && (searchString.isEmpty || book.title.contains(searchString))
        }).sorted(by: { (left, right) -> Bool in
            left.title < right.title
        })
    }
}

struct Book: Hashable, Identifiable, Equatable {
    static func == (lhs: Book, rhs: Book) -> Bool {
        lhs.id == rhs.id && lhs.libraryName == rhs.libraryName
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(libraryName)
    }
    
    var serverInfo: ServerInfo
    var id: Int32 = 0
    var libraryName = ""
    var title = ""
    var authors = ""
    var comments = ""
    var formats = [String: String]()
    var readPos = BookReadingPosition()
    
    var inShelf = false
    
    enum Format: String, CaseIterable, Identifiable {
        case EPUB
        case PDF
        
        var id: String { self.rawValue }
    }
    
    init(serverInfo: ServerInfo) {
        self.serverInfo = serverInfo
    }
    
    init(serverInfo: ServerInfo, title: String, authors: String) {
        self.serverInfo = serverInfo
        self.title = title
        self.authors = authors
    }
}

class BookRealm: Object {
    @objc dynamic var id: Int32 = 0
    @objc dynamic var libraryName = ""
    @objc dynamic var title = ""
    @objc dynamic var authors = ""
    @objc dynamic var comments = ""
    @objc dynamic var formatsData: NSData?
}

struct BookReadingPosition {
    private var deviceMap = [String: BookDeviceReadingPosition]()
    private var devices = [BookDeviceReadingPosition]()
    
    var isEmpty: Bool { get { deviceMap.isEmpty } }
    
    func getPosition(_ deviceName: String) -> BookDeviceReadingPosition? {
        return deviceMap[deviceName]
    }
    
    mutating func addInitialPosition(_ deviceName: String, _ readerName: String) {
        let initialPosition = BookDeviceReadingPosition(id: deviceName, readerName: readerName)
        self.updatePosition(deviceName, initialPosition)
    }
    
    mutating func updatePosition(_ deviceName: String, _ newPosition: BookDeviceReadingPosition) {
        if let oldPosition = deviceMap[deviceName] {
            devices.removeAll { (it) -> Bool in
                it.id == oldPosition.id
            }
        }
        deviceMap[deviceName] = newPosition
        devices.append(newPosition)
        devices.sort { (lhs, rhs) -> Bool in
            if lhs.lastPosition[0] == rhs.lastPosition[0] {
                return (lhs.lastPosition[1] + lhs.lastPosition[2]) > (rhs.lastPosition[1] + rhs.lastPosition[2])
            } else {
                return lhs.lastPosition[0] > rhs.lastPosition[0]
            }
        }
    }
    
    func getCopy() -> [String: BookDeviceReadingPosition] {
        return deviceMap
    }
    
    func getDevices() -> [BookDeviceReadingPosition] {
        return devices
    }
}

struct BookDeviceReadingPosition : Hashable, Codable, Identifiable {
    static func == (lhs: BookDeviceReadingPosition, rhs: BookDeviceReadingPosition) -> Bool {
        lhs.id == rhs.id && lhs.readerName == rhs.readerName
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(readerName)
    }
    
    var id: String
    
    var readerName: String
    var maxPage = 0
    var lastReadPage = 0
    var lastReadChapter = ""
    var furthestReadPage = 0
    var furthestReadChapter = ""
    var lastPosition = [0, 0, 0]
    
    var description: String {
        return "\(id) with \(readerName): \(lastPosition[0]) \(lastPosition[1]) \(lastPosition[2]) \(lastReadPage)"
    }
}
