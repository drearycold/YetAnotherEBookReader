//
//  Book.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/1/27.
//

import Foundation

struct LibraryInfo {
    var libraryMap = [String: Library]()
    var libraries = [Library]()
    
    mutating func addLibrary(name: String) {
        if(libraryMap[name] == nil) {
            let library = Library(name: name)
            libraryMap[name] = library
            libraries.append(library)
            libraries.sort { (lhs, rhs) -> Bool in
                lhs.name < rhs.name
            }
        }
    }
}

struct Library: Hashable {
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
    
    var id: Int32 = 0
    var libraryName = ""
    var title = ""
    var authors = ""
    var comments = ""
    var formats = [String: String]()
    var readPos = BookReadingPosition()
    
    enum Format: String, CaseIterable, Identifiable {
        case EPUB
        case PDF
        
        var id: String { self.rawValue }
    }
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
        let oldPosition = deviceMap[deviceName]
        if oldPosition != nil {
            devices.removeAll { (it) -> Bool in
                it.id == oldPosition!.id
            }
        }
        deviceMap[deviceName] = newPosition
        devices.append(newPosition)
        devices.sort { (lhs, rhs) -> Bool in
            lhs.lastPosition[0] > rhs.lastPosition[0]
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
    
}
