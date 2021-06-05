//
//  CalibreData.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/4/8.
//

import Foundation
import RealmSwift

struct CalibreServer: Hashable, Identifiable {
    var id: String {
        get {
            if isLocal {
                return "Document"
            }
            else if username.isEmpty {
                return baseUrl
            } else {
                return "\(username) @ \(baseUrl)"
            }
        }
    }
    
    var isLocal: Bool {
        baseUrl.hasPrefix(".")
    }
    
    var localBaseUrl: URL? {
        guard isLocal else {
            return nil
        }
        guard let documentDirectoryURL = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false) else {
            return nil
        }
        return documentDirectoryURL
    }
    
    var baseUrl: String
    var alternativeUrls = [String]()
    var username: String
    var password: String
    var defaultLibrary = ""
    
    static func == (lhs: CalibreServer, rhs: CalibreServer) -> Bool {
        lhs.baseUrl == rhs.baseUrl && lhs.username == rhs.username
    }
}

class CalibreServerRealm: Object {
    @objc dynamic var primaryKey: String?
    @objc dynamic var baseUrl: String? {
        didSet {
            updatePrimaryKey()
        }
    }
    @objc dynamic var username: String? {
        didSet {
            updatePrimaryKey()
        }
    }
    @objc dynamic var password: String?
    @objc dynamic var defaultLibrary: String?
    
    override static func primaryKey() -> String? {
        return "primaryKey"
    }
    
    func updatePrimaryKey() {
        primaryKey = "\(username ?? "-")@\(baseUrl ?? "-")"
    }
}

struct CalibreLibrary: Hashable, Identifiable {
    var id: String {
        get { return server.id + " - " + name }
    }
    static func == (lhs: CalibreLibrary, rhs: CalibreLibrary) -> Bool {
        lhs.server == rhs.server && lhs.id == rhs.id
    }
    let server: CalibreServer
    let key: String
    let name: String
    
    var readPosColumnName: String? = nil
    var readPosColumnNameDefault: String {
        if server.username.isEmpty {
            return "#read_pos"
        } else {
            return "#read_pos_\(server.username)"
        }
    }
    
    var goodreadsSyncProfileName: String? = nil
    var goodreadsSyncProfileNameDefault: String {
        return "Default"
    }
}

class CalibreLibraryRealm: Object {
    @objc dynamic var primaryKey: String?
    
    @objc dynamic var key: String? {
        didSet {
            
        }
    }
    @objc dynamic var name: String? {
        didSet {
            updatePrimaryKey()
        }
    }
    @objc dynamic var serverUrl: String? {
        didSet {
            updatePrimaryKey()
        }
    }
    @objc dynamic var serverUsername: String? {
        didSet {
            updatePrimaryKey()
        }
    }
    
    override static func primaryKey() -> String? {
        return "primaryKey"
    }
    
    func updatePrimaryKey() {
        primaryKey = "\(serverUsername ?? "-")@\(serverUrl ?? "-") - \(name ?? "-")"
    }
    
    @objc dynamic var readPosColumnName: String?
    @objc dynamic var goodreadsSyncProfileName: String?
}

struct CalibreBook: Hashable, Identifiable, Equatable {
    static func == (lhs: CalibreBook, rhs: CalibreBook) -> Bool {
        lhs.id == rhs.id && lhs.library.name == rhs.library.name
    }
    func hash(into hasher: inout Hasher) {
        library.hash(into: &hasher)
        hasher.combine(id)
    }
    
    let id: Int32
    let library: CalibreLibrary
    var title = "No Title"
    var authors = [String]()
    var authorsDescription: String {
        if authors.count == 0 {
            return "Unknown"
        }
        if authors.count == 1 {
            return authors[0]
        }
        return authors.reduce("") { (desc, author) -> String in
            if desc.count == 0 {
                return author
            } else {
                return desc + ", " + author
            }
        }
    }
    var authorsDescriptionShort: String {
        if authors.count == 0 {
            return "Unknown"
        }
        if authors.count == 1 {
            return authors[0]
        }
        return authors[0] + ", et al."
    }
    var comments = "Without Comments"
    var publisher = "Unknown"
    var series = ""
    var rating = 0
    var ratingDescription: String {
        if rating > 9 {
            return "★★★★★"
        } else if rating > 7 {
            return "★★★★"
        } else if rating > 5 {
            return "★★★"
        } else if rating > 3 {
            return "★★"
        } else if rating > 1 {
            return "★"
        } else {
            return "☆"
        }
    }
    var size = 0
    var pubDate = Date()
    var timestamp = Date()
    var lastModified = Date()
    var tags = [String]()
    var tagsDescription: String {
        if tags.count == 0 {
            return ""
        }
        if tags.count == 1 {
            return tags[0]
        }
        return tags.reduce("") { (desc, tag) -> String in
            if desc.count == 0 {
                return tag
            } else {
                return desc + ", " + tag
            }
        }
    }
    var formats = [String: String]()
    var readPos = BookReadingPosition()
    
    var identifiers = [String: String]()
    
    var coverURL : URL {
        return URL(string: "\(library.server.baseUrl)/get/thumb/\(id)/\(library.key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)?sz=300x400")!
    }
    var commentBaseURL : URL {  //fake
        return URL(string: "\(library.server.baseUrl)/get/\(id)/\(library.key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)")!
    }
    
    var inShelfId : String {
        return "\(id)^\(library.id)"
    }
    
    var inShelf = false
    var inShelfName = ""
    
    enum Format: String, CaseIterable, Identifiable {
        case UNKNOWN
        
        case EPUB
        case PDF
        case CBZ
        
        
        var id: String { self.rawValue }
        
        var ext: String { self.rawValue.lowercased() }
    }
}

class CalibreBookRealm: Object {
    @objc dynamic var primaryKey: String?
    
    @objc dynamic var serverUrl: String? {
        didSet {
            updatePrimaryKey()
        }
    }
    @objc dynamic var serverUsername: String? {
        didSet {
            updatePrimaryKey()
        }
    }
    @objc dynamic var libraryName: String? {
        didSet {
            updatePrimaryKey()
        }
    }
    
    @objc dynamic var id: Int32 = 0 {
        didSet {
            updatePrimaryKey()
        }
    }
    @objc dynamic var title = ""
    let authors = List<String>()
    @objc dynamic var comments = ""
    @objc dynamic var publisher = ""
    @objc dynamic var series = ""
    @objc dynamic var rating = 0
    @objc dynamic var size = 0
    @objc dynamic var pubDate = Date()
    @objc dynamic var timestamp = Date()
    @objc dynamic var lastModified = Date()
    let tags = List<String>()
    @objc dynamic var formatsData: NSData?
    @objc dynamic var readPosData: NSData?
    @objc dynamic var identifiersData: NSData?
    
    @objc dynamic var inShelf = false
    @objc dynamic var inShelfName = ""
    
    func formats() -> [String: String] {
        let formats = try! JSONSerialization.jsonObject(with: formatsData! as Data, options: []) as! [String: String]
        return formats
    }
    
    func identifiers() -> [String: String] {
        let identifiers = try! JSONSerialization.jsonObject(with: identifiersData! as Data, options: []) as! [String: String]
        return identifiers
    }
    
    func readPos() -> BookReadingPosition {
        var readPos = BookReadingPosition()
        
        let readPosObject = try! JSONSerialization.jsonObject(with: readPosData! as Data, options: [])
        let readPosDict = readPosObject as! NSDictionary
        
        let deviceMapObject = readPosDict["deviceMap"]
        let deviceMapDict = deviceMapObject as! NSDictionary
        deviceMapDict.forEach { key, value in
            let deviceName = key as! String
            let deviceReadingPositionDict = value as! [String: Any]
            
            var deviceReadingPosition = BookDeviceReadingPosition(id: deviceName, readerName: "FolioReader")
            
            deviceReadingPosition.readerName = deviceReadingPositionDict["readerName"] as! String
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
            
            readPos.updatePosition(deviceName, deviceReadingPosition)
        }
        return readPos
    }
    
    override static func primaryKey() -> String? {
        return "primaryKey"
    }
    
    func updatePrimaryKey() {
        primaryKey = "\(serverUsername ?? "-")@\(serverUrl ?? "-") - \(libraryName ?? "-") ^ \(id)"
    }
    
    override static func indexedProperties() -> [String] {
            return ["serverUrl", "serverUsername", "libraryName", "id", "title", "inShelf"]
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
        lhs.id == rhs.id
            && lhs.readerName == rhs.readerName
            && lhs.lastReadPage == rhs.lastReadPage
            && lhs.lastProgress == rhs.lastProgress
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
    var lastChapterProgress = 0.0
    var lastProgress = 0.0
    var furthestReadPage = 0
    var furthestReadChapter = ""
    var lastPosition = [0, 0, 0]
    
    var description: String {
        return """
            \(id) with \(readerName):
                Chapter: \(lastReadChapter), \(String(format: "%.2f", 100 - lastChapterProgress))% Left
                Book: Page \(lastReadPage), \(String(format: "%.2f", 100 - lastProgress))% Left
                (\(lastPosition[0]):\(lastPosition[1]):\(lastPosition[2]))
            """
    }
    
    static func < (lhs: BookDeviceReadingPosition, rhs: BookDeviceReadingPosition) -> Bool {
        if lhs.lastReadPage < rhs.lastReadPage {
            return true
        } else if lhs.lastReadPage > rhs.lastReadPage {
            return false
        }
        if lhs.lastChapterProgress < rhs.lastChapterProgress {
            return true
        } else if lhs.lastChapterProgress > rhs.lastChapterProgress {
            return false
        }
        if lhs.lastProgress < rhs.lastProgress {
            return true
        }
        return false
    }
    
    static func << (lhs: BookDeviceReadingPosition, rhs: BookDeviceReadingPosition) -> Bool {
        if (lhs.lastProgress + 10) < rhs.lastProgress {
            return true
        }
        return false
    }
    
    mutating func update(with other: BookDeviceReadingPosition) {
        maxPage = other.maxPage
        lastReadPage = other.lastReadPage
        lastReadChapter = other.lastReadChapter
        lastChapterProgress = other.lastChapterProgress
        lastProgress = other.lastProgress
        lastPosition = other.lastPosition
    }
    
    func isSameProgress(with other: BookDeviceReadingPosition) -> Bool {
        if lastReadPage == other.lastReadPage
            && lastChapterProgress == other.lastChapterProgress
            && lastProgress == other.lastProgress {
            return true
        }
        return false
    }
}

struct ServerErrorDelegate {
    
}

enum ReaderType: String, CaseIterable, Identifiable {
    case UNSUPPORTED
    
    case FolioReader
    case YabrPDFView
    case ReadiumReader
    
    var id: String { self.rawValue }
}
