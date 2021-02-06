//
//  Book.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/1/27.
//

import Foundation
import RealmSwift
import SwiftUI

struct ServerInfo {
    var calibreServer: String
}

struct LibraryInfo {
    var libraryMap = [String: Library]()
    var libraries = [Library]()
    
    mutating func addLibrary(name: String) -> Library {
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
        library.books[library.books.firstIndex(of: book)!] = book
        
        libraryMap[book.libraryName]! = library
        libraries[libraries.firstIndex(of: library)!] = library
    }
}

struct Library: Hashable, Identifiable {
    var id: String {
        get { return name }
    }
    
    var name: String
    var books = [Book]()
    var booksMap = [Int32: Book]()
    
    mutating func filterBooks(_ searchString: String) {
        books.removeAll()
        books.append(contentsOf: booksMap.values.filter({ book in
            (book.formats["EPUB"] != nil || book.formats["PDF"] != nil )
            && (searchString.isEmpty || book.title.contains(searchString))
        }).sorted(by: { (left, right) -> Bool in
            left.title < right.title
        }))
    }
}

struct Book: Hashable, Identifiable {
    static func == (lhs: Book, rhs: Book) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title
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
                return lhs.lastPosition[2] > rhs.lastPosition[2]
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
