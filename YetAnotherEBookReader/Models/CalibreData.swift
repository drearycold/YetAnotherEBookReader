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
                return "Document Folder"
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
    
    var name: String
    var baseUrl: String
    var publicUrl: String
    var serverUrl: String {
        if usePublic && publicUrl.isEmpty == false {
            return publicUrl
        } else {
            return baseUrl
        }
    }
    var username: String
    var password: String
    var defaultLibrary = ""
    var lastLibrary = ""
    var usePublic: Bool = false
    
    static func == (lhs: CalibreServer, rhs: CalibreServer) -> Bool {
        lhs.baseUrl == rhs.baseUrl && lhs.username == rhs.username
    }
}


struct CalibreLibrary: Hashable, Identifiable {
    var id: String {
        get { return server.id + " - " + name }
    }
    static func == (lhs: CalibreLibrary, rhs: CalibreLibrary) -> Bool {
        lhs.server == rhs.server && lhs.id == rhs.id
    }
    var server: CalibreServer
    var key: String
    var name: String
    
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
    
    var urlForDeleteBook: URL? {
        guard let keyEncoded = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        
        let serverUrl = server.serverUrl
        
        return URL(string: "\(serverUrl)/cdb/cmd/remove/0?library_id=\(keyEncoded)")
    }
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
    var seriesDescription: String {
        if series.isEmpty {
            return "Not in a Series"
        }
        return series
    }
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
    var pubDate = Date(timeIntervalSince1970: .zero)
    var pubDateByLocale: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        dateFormatter.locale = Locale.autoupdatingCurrent
        return dateFormatter.string(from: pubDate)
    }
    var timestamp = Date(timeIntervalSince1970: .zero)
    var lastModified = Date(timeIntervalSince1970: .zero)
    var lastModifiedByLocale: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        dateFormatter.locale = Locale.autoupdatingCurrent
        return dateFormatter.string(from: lastModified)
    }
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
    var formats = [String: FormatInfo]()
    var readPos = BookReadingPosition()
    
    var identifiers = [String: String]()
    
    var coverURL : URL? {
        guard let keyEncoded = library.key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        
        let url = URL(string: "\(library.server.serverUrl)/get/thumb/\(id)/\(keyEncoded)?sz=300x400&username=\(library.server.username)")
//        if url != nil {
//            print("coverURL: \(url!.absoluteString)")
//        }
        return url
    }
    var commentBaseURL : URL? {
        //fake
        guard let keyEncoded = library.key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: "\(library.server.serverUrl)/get/\(id)/\(keyEncoded)")!
    }
    
    var inShelfId : String {
        return "\(id)^\(library.id)"
    }
    
    var inShelf = false
    var inShelfName = ""
    
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
    
    mutating func removePosition(_ deviceName: String) {
        deviceMap.removeValue(forKey: deviceName)
        devices.removeAll { position in
            position.id == deviceName
        }
    }
    
    func getCopy() -> [String: BookDeviceReadingPosition] {
        return deviceMap
    }
    
    func getDevices() -> [BookDeviceReadingPosition] {
        return devices
    }
    
    func getDevices(by reader: ReaderType) -> [BookDeviceReadingPosition] {
        return devices.filter {
            $0.readerName == reader.id
        }
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
    
    var id: String  //device name
    
    var readerName: String
    var maxPage = 0
    var lastReadPage = 0
    var lastReadChapter = ""
    var lastChapterProgress = 0.0
    var lastProgress = 0.0
    var furthestReadPage = 0
    var furthestReadChapter = ""
    var lastPosition = [0, 0, 0]
    var cfi = "/"
    var epoch = 0.0
    
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

struct CalibreBookLastReadPositionEntry: Codable {
    var device: String = ""
    var cfi: String = ""
    var epoch: Double = 0.0
    var pos_frac: Double = 0.0
}

struct CalibreBookTask {
    var bookId: Int32
    var inShelfId: String
    var url: URL
    var username: String
}

struct CalibreBookFormatMetadataEntry: Codable {
    var path: String = ""
    var size: UInt64 = 0
    var mtime: String = ""
}

struct CalibreBookUserMetadataEntry: Codable {
    var table: String = ""
    var column: String = ""
    var datatype: String = ""
    var is_multiple: Bool? = nil
    var kind: String = ""
    var name: String = ""
    var search_terms: [String] = []
    var label: String = ""
    var colnum: Int = 0
    var display: [String: String?] = [:]
    var is_custom: Bool = false
    var is_category: Bool = false
    var link_column: String = ""
    var category_sort: String = ""
    var is_csp: Bool = false
    var is_editable: Bool = false
    var rec_index: Int = 0
    var value: Any? = nil   //dynamic
    var extra: Any? = nil   //dynamic
    //var is_multiple2: ???
    
    enum CodingKeys: String, CodingKey {
        case table
    }
}

struct CalibreBookEntry: Codable {
    var author_link_map: [String: String] = [:]
    var user_metadata: [String: CalibreBookUserMetadataEntry] = [:]
    var tags: [String] = []
    var author_sort: String = ""
    var comments: String? = nil
    var title_sort: String = ""
    var thumbnail: String = ""
    var timestamp: String = ""
    var uuid: String = ""
    var user_categories: [String: String] = [:]
    var cover: String = ""
    var title: String = ""
    var last_modified: String = ""
    var application_id: Int = 0
    var series_index: Double? = nil
    var author_sort_map: [String: String] = [:]
    var identifiers: [String: String] = [:]
    var languages: [String] = []
    var publisher: String? = nil
    var series: String? = nil
    var pubdate: String = ""
    var rating: Int = 0
    var authors: [String] = []
    var format_metadata: [String: CalibreBookFormatMetadataEntry] = [:]
    var formats: [String] = []
    var main_format: [String: String] = [:]
    var other_formats: [String: String] = [:]
    var category_urls: [String: [String: String]] = [:]
}

struct CalibreBookAnnotationEntry: Codable {
    var uuid: String
    var type: String

    var startCfi: String
    var endCfi: String
    var highlightedText: String
    var style:[String:String]
    var timestamp: String

    var spineName: String
    var spineIndex: Int
    var tocFamilyTitles: [String]
    
    var notes: String?
    
    enum CodingKeys: String, CodingKey {
        case uuid
        case type
        
        case startCfi = "start_cfi"
        case endCfi = "end_cfi"
        case highlightedText = "highlighted_text"
        case style
        case timestamp

        case spineName = "spine_name"
        case spineIndex = "spine_index"
        case tocFamilyTitles = "toc_family_titles"
        
        case notes
    }
}

struct CalibreBookAnnotationsResult: Codable {
    var last_read_positions: [CalibreBookLastReadPositionEntry]
    var annotations_map: [String: [CalibreBookAnnotationEntry]]
}
