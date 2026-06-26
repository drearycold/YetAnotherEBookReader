//
//  CalibreData.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/4/8.
//

import Foundation
import UIKit

struct CalibreServer: Hashable, Identifiable {
    static let LocalServerUUID = UUID(uuidString: "c54ba2ae-67af-46f6-af64-504fd5d756eb")!
    
    var id: String {
//        get {
//            if isLocal {
//                return "Document Folder"
//            }
//            else if username.isEmpty {
//                return baseUrl
//            } else {
//                return "\(username) @ \(baseUrl)"
//            }
//        }
        uuid.uuidString
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(self.baseUrl)
        hasher.combine(self.username)
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
    
    let uuid: UUID
    
    var name: String
    var baseUrl: String
    var hasPublicUrl: Bool
    var publicUrl: String
    var serverUrl: String {
        if hasPublicUrl && usePublic && publicUrl.isEmpty == false {
            return publicUrl
        } else {
            return baseUrl
        }
    }
    var hasAuth: Bool
    var username: String
    var password: String
    var defaultLibrary = ""
    var removed = false
    
    var usePublic: Bool = false     //runtime only
    
    static func == (lhs: CalibreServer, rhs: CalibreServer) -> Bool {
        lhs.baseUrl == rhs.baseUrl && lhs.username == rhs.username
    }
}


struct CalibreLibrary: Hashable, Identifiable {
    static let PLUGIN_DSREADER_HELPER = "DSReader Helper"

    static let PLUGIN_READING_POSITION = "Reading Position"
    static let PLUGIN_DICTIONARY_VIEWER = "Dictionary Viewer"

    static let PLUGIN_GOODREADS_SYNC = "Goodreads Sync"
    static let PLUGIN_COUNT_PAGES = "Count Pages"
    
    var id: String {
//        get { return server.id + " - " + name }
        CalibreLibraryRealm.PrimaryKey(serverUUID: server.uuid.uuidString, libraryName: name)
    }
    static func == (lhs: CalibreLibrary, rhs: CalibreLibrary) -> Bool {
        lhs.server == rhs.server && lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) {
        server.hash(into: &hasher)
        hasher.combine(key)
        hasher.combine(name)
    }
    var server: CalibreServer
    var key: String
    var name: String
    
    var autoUpdate = false
    var discoverable = true
    var hidden = false
    var lastModified = Date(timeIntervalSince1970: 0)
    
    var customColumnInfos = [String: CalibreCustomColumnInfo]() //label as key
    
    var pluginDSReaderHelperWithDefault: CalibreDSReaderHelperPrefs.Options {
        guard let modelData = ModelData.shared,
              let configuration = modelData.queryServerDSReaderHelper(server: server)?.configuration,
              let prefs = configuration.dsreader_helper_prefs?.plugin_prefs
        else { return .init() }
        
        return prefs.Options
    }

    var pluginDictionaryViewerWithDefault: CalibreDSReaderHelperPrefs.Options {
        return pluginDSReaderHelperWithDefault
    }
    
    var pluginGoodreadsSyncWithDefault: CalibreGoodreadsSyncPrefs.PluginPrefs {
        guard let modelData = ModelData.shared,
              let configuration = modelData.queryServerDSReaderHelper(server: server)?.configuration,
              let grsync_plugin_prefs = configuration.goodreads_sync_prefs?.plugin_prefs
        else {
            return .init(Goodreads: .init(), Users: [:])
        }
        
        return grsync_plugin_prefs
    }
    
    var pluginCountPagesWithDefault: CalibreCountPagesPrefs.LibraryConfig {
        guard let modelData = ModelData.shared,
              let configuration = modelData.queryServerDSReaderHelper(server: server)?.configuration,
              let library_config = configuration.count_pages_prefs?.library_config?[name]
        else { return .init() }
        
        return library_config
    }
    
    var urlForDeleteBook: URL? {
        guard let keyEncoded = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        
        let serverUrl = server.serverUrl
        
        return URL(string: "\(serverUrl)/cdb/cmd/remove/0?library_id=\(keyEncoded)")
    }
}

struct CalibreBook: Hashable {
    static func == (lhs: CalibreBook, rhs: CalibreBook) -> Bool {
        lhs.inShelfId == rhs.inShelfId
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(inShelfId)
    }
    
    let id: Int32
    let library: CalibreLibrary
    var title = "No Title"
    var authors = [String]()
    var authorsDescription: String {
        if authors.count == 0 {
            return "Unknown"
        }
        return authors.joined(separator: ", ")
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
    var seriesIndex = 0.0
    var seriesIndexDescription: String {
        return String(format: "%.1f", seriesIndex)
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
    var ratingGRDescription: String? {
        let pluginGoodreadsSync = library.pluginGoodreadsSyncWithDefault
        guard pluginGoodreadsSync.isEnabled,
              let rating = userMetadatas[pluginGoodreadsSync.ratingColumnName.trimmingCharacters(in: CharacterSet(["#"]))] as? Int else { return nil }

        switch(rating) {
        case 10:
            return "★★★★★"
        case 9:
            return "★★★★☆"
        case 8:
            return "★★★★"
        case 7:
            return "★★★☆"
        case 6:
            return "★★★"
        case 5:
            return "★★☆"
        case 4:
            return "★★"
        case 3:
            return "★☆"
        case 2:
            return "★"
        case 1:
            return "☆"
        default:
            return "-"
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
    var lastSynced  = Date(timeIntervalSince1970: .zero)
    var lastUpdated = Date(timeIntervalSince1970: .zero)

    var readDateGRByLocale: String? {
        let pluginGoodreadsSync = library.pluginGoodreadsSyncWithDefault
        guard pluginGoodreadsSync.isEnabled,
              let dateReadString = userMetadatas[pluginGoodreadsSync.dateReadColumnName.trimmingCharacters(in: CharacterSet(["#"]))] as? String else { return nil }

        
        let parser = ISO8601DateFormatter()
        parser.formatOptions = .withInternetDateTime
        guard let dateRead = parser.date(from: dateReadString) else { return nil }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        dateFormatter.locale = Locale.autoupdatingCurrent
        return dateFormatter.string(from: dateRead)
    }
    
    var readProgressGRDescription: String? {
        let pluginGoodreadsSync = library.pluginGoodreadsSyncWithDefault
        guard pluginGoodreadsSync.isEnabled,
              let progressAny = userMetadatas[pluginGoodreadsSync.readingProgressColumnName.trimmingCharacters(in: CharacterSet(["#"]))],
              let prog = progressAny else { return nil }
        return Int(String(describing: prog))?.description
    }
    
    var tags = [String]()
    var tagsDescription: String {
        if tags.count == 0 {
            return "No Tag"
        }
        return tags.joined(separator: ", ")
    }
    var formats = [String: FormatInfo]()
    var bookPrefId: String {
        BookAnnotation.PrefId(library: library, id: id)
    }
    
    var identifiers = [String: String]()
    
    var userMetadatas = [String: Any?]()
    func userMetadataNumberAsIntDescription(column: String) -> String? {
        guard let numberAny = userMetadatas[column.trimmingCharacters(in: CharacterSet(["#"]))],
              let number = numberAny else { return nil }
        return Int(String(describing: number))?.description
    }
    func userMetadataNumberAsFloatDescription(column: String) -> String? {
        guard let numberAny = userMetadatas[column.trimmingCharacters(in: CharacterSet(["#"]))],
              let number = numberAny else { return nil }
        guard let d = Double(String(describing: number)) else { return nil }
        return String(format: "%.2f", d)
    }
    
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
        return CalibreBookRealm.PrimaryKey(
            serverUUID: library.server.uuid.uuidString,
            libraryName: library.name,
            id: id.description
        )
    }
    
    var inShelf = false
    
    init(id: Int32, library: CalibreLibrary) {
        self.id = id
        self.library = library
    }
}

struct CalibreSyncStatus {
    var library: CalibreLibrary
    var isSync = false
    var isUpd = false
    var isError = false
    var msg: String? = nil
    var cnt: Int? = nil
    var upd = Set<Int32>()  //ongoing requests
    var del = Set<Int32>()
    var err = Set<Int32>()
}

/*
struct BookReadingPositionLegacy {
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
*/

struct BookDeviceReadingPosition : Hashable, Codable {
    static func == (lhs: BookDeviceReadingPosition, rhs: BookDeviceReadingPosition) -> Bool {
        lhs.id == rhs.id
            && lhs.readerName == rhs.readerName
            && lhs.lastReadPage == rhs.lastReadPage
            && lhs.lastProgress == rhs.lastProgress
            && lhs.structuralRootPageNumber == rhs.structuralRootPageNumber
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(readerName)
        hasher.combine(lastReadPage)
        hasher.combine(structuralStyle)
        hasher.combine(positionTrackingStyle)
        hasher.combine(structuralRootPageNumber)
    }
    
    var id: String = ""  //device name
    
    var readerName: String
    
    var maxPage = 0
    var lastReadPage = 0
    var lastReadChapter = ""
    /// range 0 - 100
    var lastChapterProgress = 0.0
    /// range 0 - 100
    var lastProgress = 0.0
    var furthestReadPage = 0
    var furthestReadChapter = ""
    var lastPosition = [0, 0, 0]
    var cfi = "/"
    var epoch = 0.0     //timestamp
    
    //for non-linear book structure
    var structuralStyle: Int = .zero
    var structuralRootPageNumber: Int = .zero
    var positionTrackingStyle: Int = .zero
    var lastReadBook: String = .init()
    var lastBundleProgress: Double = .zero
    
    enum CodingKeys: String, CodingKey {
        case readerName
        case lastReadPage
        case lastReadChapter
        case lastChapterProgress
        case lastProgress
        case furthestReadPage
        case furthestReadChapter
        case maxPage
        case lastPosition
        case cfi
        case epoch
        
        case structuralStyle
        case structuralRootPageNumber
        case positionTrackingStyle
        case lastReadBook
        case lastBundleProgress
    }
    
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
        cfi = other.cfi
        epoch = other.epoch
    }
    
    func isSameProgress(with other: BookDeviceReadingPosition) -> Bool {
        if id == other.id,
            readerName == other.readerName,
            lastReadPage == other.lastReadPage,
            lastChapterProgress == other.lastChapterProgress,
            lastProgress == other.lastProgress {
            return true
        }
        return false
    }
    
    func isSameType(with other: BookDeviceReadingPosition) -> Bool {
        return id == other.id && readerName == other.readerName
    }
    
    var epochByLocale: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .medium
        dateFormatter.locale = Locale.autoupdatingCurrent
        return dateFormatter.string(from: Date(timeIntervalSince1970: epoch))
    }
    
    var epochByLocaleRelative: String {
        let dateFormatter = DateFormatter()
        dateFormatter.doesRelativeDateFormatting = true
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .medium
        dateFormatter.locale = Locale.autoupdatingCurrent
        return dateFormatter.string(from: Date(timeIntervalSince1970: epoch))
    }
    
    var epochLocaleLong: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .long
        dateFormatter.locale = Locale.autoupdatingCurrent
        return dateFormatter.string(from: Date(timeIntervalSince1970: epoch))
    }
}



struct BookDeviceReadingPositionHistory : Hashable, Codable {
    var bookId: String
    
    var startDatetime = Date()
    var startPosition: BookDeviceReadingPosition?
    var endPosition: BookDeviceReadingPosition?
    
    static func == (lhs: BookDeviceReadingPositionHistory, rhs: BookDeviceReadingPositionHistory) -> Bool {
        lhs.bookId == rhs.bookId
        && lhs.endPosition == rhs.endPosition
        // && lhs.startPosition == rhs.startPosition
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(bookId)
        hasher.combine(endPosition)
        // hasher.combine(startPosition)
    }
}

extension BookDeviceReadingPositionHistory {
    static func getReadingStatistics(list: [BookDeviceReadingPositionHistory], limitDays: Int) -> [Double] {
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
}

enum BookHighlightStyle: Int, CaseIterable, Identifiable {
    case yellow
    case green
    case blue
    case pink
    case underline

    var id: Int {
        self.rawValue
    }
    
    var description: String {
        switch self {
        case .yellow:
            return "Yellow"
        case .green:
            return "Green"
        case .blue:
            return "Blue"
        case .pink:
            return "Pink"
        case .underline:
            return "Underline"
        }
    }
    
    public init () {
        // Default style is `.yellow`
        self = .yellow
    }
    
    /**
     Return HighlightStyle for CSS class.
     */
    public static func styleForClass(_ className: String) -> BookHighlightStyle {
        switch className {
        case "highlight-yellow": return .yellow
        case "highlight-green": return .green
        case "highlight-blue": return .blue
        case "highlight-pink": return .pink
        case "highlight-underline": return .underline
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "pink": return .pink
        case "underline": return .underline
        default: return .yellow
        }
    }

    /**
     Return CSS class for HighlightStyle.
     */
    public static func classForStyle(_ style: Int) -> String {
        let enumStyle = (BookHighlightStyle(rawValue: style) ?? BookHighlightStyle())
        switch enumStyle {
        case .yellow: return "highlight-yellow"
        case .green: return "highlight-green"
        case .blue: return "highlight-blue"
        case .pink: return "highlight-pink"
        case .underline: return "highlight-underline"
        }
    }

    public static func classForStyleCalibre(_ style: Int) -> String {
        let enumStyle = (BookHighlightStyle(rawValue: style) ?? BookHighlightStyle())
        switch enumStyle {
        case .yellow: return "yellow"
        case .green: return "green"
        case .blue: return "blue"
        case .pink: return "pink"
        case .underline: return "underline"
        }
    }

    /// Color components for the style
    ///
    /// - Returns: Tuple of all color compnonents.
    private func colorComponents() -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        switch self {
        case .yellow: return (red: 255, green: 235, blue: 107, alpha: 0.9)
        case .green: return (red: 192, green: 237, blue: 114, alpha: 0.9)
        case .blue: return (red: 173, green: 216, blue: 255, alpha: 0.9)
        case .pink: return (red: 255, green: 176, blue: 202, alpha: 0.9)
        case .underline: return (red: 240, green: 40, blue: 20, alpha: 0.6)
        }
    }

    /**
     Return CSS class for HighlightStyle.
     */
    public static func colorForStyle(_ style: Int, nightMode: Bool = false) -> UIColor {
        let enumStyle = (BookHighlightStyle(rawValue: style) ?? BookHighlightStyle())
        let colors = enumStyle.colorComponents()
        return UIColor(red: colors.red/255, green: colors.green/255, blue: colors.blue/255, alpha: (nightMode ? colors.alpha : 1))
    }
}

struct CalibreBookLastReadPositionEntry: Codable {
    let device: String
    let cfi: String
    let epoch: Double
    let pos_frac: Double
}

struct CalibreBookTask {
    var server: CalibreServer
    var bookId: Int32
    var inShelfId: String
    var url: URL
}

struct CalibreBooksMetadataRequest {
    let library: CalibreLibrary
    let books: [Int32]
    let getAnnotations: Bool
}

struct CalibreBooksTask {
    let request: CalibreBooksMetadataRequest
    var library: CalibreLibrary {
        request.library
    }
    var books: [Int32] {
        request.books
    }
    var metadataUrl: URL?
    var lastReadPositionUrl: URL?
    var annotationsUrl: URL?
    var data: Data?
    var response: URLResponse?
    var lastReadPositionsData: Data?
    var annotationsData: Data?
    
    var booksMetadataEntry: [String: CalibreBookEntry?]?
    var booksMetadataJSON: NSDictionary?
    
    var booksAnnotationsEntry: [String:CalibreBookAnnotationsResult]?
    
    var searchCriteria: SearchCriteria?
    var searchTask: CalibreLibrarySearchTask?
    
    var booksUpdated = Set<Int32>()
    var booksError = Set<Int32>()
    var booksDeleted = Set<Int32>()
    var booksInShelf = [CalibreBook]()
    var booksAnnotation = [CalibreBook]()
}

struct CalibreLibraryProbeTask {
    let library: CalibreLibrary
    let probeUrl: URL
    
    var probeResult: CalibreLibraryBooksResult.SearchResult?
}

struct CalibreLibrarySearchTask: Identifiable {
    let id = UUID()
    let serverUrl: URL
    
    let generation: Date
    
    let library: CalibreLibrary
    let searchCriteria: SearchCriteria
    let booksListUrl: URL
    let offset: Int
    let num: Int
    
    //results
    var data: Data? = nil
    var booksMetadataEntry: [String: CalibreBookEntry?]? = nil
    var booksMetadataJSON: NSDictionary? = nil
    var ajaxSearchResult: CalibreLibraryBooksResult.SearchResult? = nil
    var ajaxSearchError = false
}

struct CalibreBookFormatMetadataEntry: Codable {
    var path: String?
    var size: UInt64 = 0
    var mtime: String = ""
    
    enum CodingKeys: String, CodingKey {
        case path
        case size
        case mtime
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decodeIfPresent(String.self, forKey: .path)
        size = try container.decodeIfPresent(UInt64.self, forKey: .size) ?? 0
        mtime = try container.decodeIfPresent(String.self, forKey: .mtime) ?? ""
    }
    
    init(path: String? = nil, size: UInt64 = 0, mtime: String = "") {
        self.path = path
        self.size = size
        self.mtime = mtime
    }
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
//    var author_link_map: [String: String] = [:]   //removed as of calibre 6.18
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
    var rating: Double = 0.0
    var authors: [String] = []
    var format_metadata: [String: CalibreBookFormatMetadataEntry] = [:]
    var formats: [String] = []
    var main_format: [String: String]? = [:]
    var other_formats: [String: String]? = [:]
    var category_urls: [String: [String: String]] = [:]
}

struct CalibreBookAnnotationHighlightEntry: Codable {
    var type: String
    var timestamp: String
    var uuid: String

    var removed: Bool?

    var ranges: String?     //for PDF
    var startCfi: String?
    var endCfi: String?
    var highlightedText: String?
    var style:[String:String]?

    var spineName: String?
    var spineIndex: Int?
    var tocFamilyTitles: [String]?
    
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
        case ranges
        
        case removed
    }
}

struct CalibreBookAnnotationBookmarkEntry: Codable {
    var type: String
    var timestamp: String

    var pos_type: String
    var pos: String
    
    var title: String
    
    var removed: Bool?
    
    enum CodingKeys: String, CodingKey {
        case type
        case timestamp

        case pos_type
        case pos
        
        case title
        case removed
    }
}

struct CalibreBookAnnotationsResult: Codable {
    var last_read_positions: [CalibreBookLastReadPositionEntry]
    var annotations_map: CalibreBookAnnotationsMap
}

struct CalibreBookAnnotationsMap: Codable {
    var bookmark: [CalibreBookAnnotationBookmarkEntry]?
    var highlight: [CalibreBookAnnotationHighlightEntry]?
}

struct CalibreBookSetLastReadPositionTask {
    let library: CalibreLibrary
    let bookId: Int32
    let format: Format
    let entry: CalibreBookLastReadPositionEntry
    var urlRequest: URLRequest
    var urlResponse: URLResponse?
    var data: Data?
    let startDatetime: Date
}

struct CalibreBookUpdateAnnotationsTask {
    let library: CalibreLibrary
    let bookId: Int32
    let format: Format
    let entry: [String : [Any]]
    let startDatetime = Date()
    var urlRequest: URLRequest
    var urlResponse: URLResponse?
    var data: Data?
}

struct CalibreCustomColumnInfo: Codable, Hashable {
    var label: String
    var name: String
    var datatype: String
    var editable: Bool
    
    var display: CalibreCustomColumnDisplayInfo
    
    var normalized: Bool
    var num: Int
    var isMultiple: Bool
    var multipleSeps: [String: String]
    
    enum CodingKeys: String, CodingKey {
        case label
        case name
        case datatype
        case editable
        case display
        case normalized
        case num
        case isMultiple = "is_multiple"
        case multipleSeps = "multiple_seps"
    }
}

struct CalibreCustomColumnDisplayInfo: Codable, Hashable {
    var description: String
    
    //type text
    var isNames: Bool?
    
    //tyoe composite
    var compositeTemplate: String?
    var compositeSort: String?
    var useDecorations: Int?
    var makeCategory: Bool?
    var containsHtml: Bool?
    
    //type int, float
    var numberFormat: String?
    
    //type comments
    var headingPosition: String?
    var interpretAs: String?
    
    //type rating
    var allowHalfStars: Bool?
    
    enum CodingKeys: String, CodingKey {
        case description
        
        case isNames = "is_names"
        
        case compositeTemplate = "composite_template"
        case compositeSort = "composite_sort"
        case useDecorations = "use_decorations"
        case makeCategory = "make_category"
        case containsHtml = "contains_html"
        
        case numberFormat = "number_format"
        
        case headingPosition = "heading_position"
        case interpretAs = "interpret_as"
        
        case allowHalfStars = "allow_half_stars"
    }
}

struct CalibreLibraryCategoryKey: Hashable {
    let libraryId: String
    let categoryName: String
}

struct CalibreUnifiedCategoryKey: Hashable {
    let categoryName: String
    let search: String
}

struct CalibreLibraryCategoryValue {
    var category: CalibreLibraryCategory
    var reqId: Int
    var totalNumber: Int
    var items: [LibraryCategoryListResult.Item]
}

struct CalibreProbeServerRequest: Identifiable {
    var id: String {
        server.id + " " + isPublic.description
    }
    
    let server: CalibreServer
    let isPublic: Bool
    
    let updateLibrary: Bool
    let autoUpdateOnly: Bool
    let incremental: Bool
}

struct CalibreProbeLibraryRequest: Identifiable {
    var id: String {
        library.id
    }
    
    let library: CalibreLibrary
}

struct CalibreSyncLibraryRequest {
    let library: CalibreLibrary
    let autoUpdateOnly: Bool
    let incremental: Bool
}

struct CalibreSyncLibraryResult {
    let request: CalibreSyncLibraryRequest
    var isIncremental: Bool = true
    var result: [String: [String:CalibreCustomColumnInfo]]
    var errmsg = ""
    var categories: [CalibreLibraryCategory] = []
    var list = CalibreCdbCmdListResult()
    
    //parsed
    var isError = false
    var bookCount = 0
    var bookNeedUpdateCount = 0
    var bookDeleted = [Int32]()
    var lastModified: Date? = nil
}

struct CalibreSyncLibraryBooksMetadata {
    enum Action {
        case save([[String: Any]])
        case updateDeleted([String: CalibreCdbCmdListResult.DateValue])
        case complete(Date?, [String: CalibreCustomColumnInfo])
    }
    
    let library: CalibreLibrary
    let action: Action
    let preMsg: String
    let postMsg: String
    
    //parsed
    var bookCount = 0
    var bookNeedUpdateCount = 0
    var bookToUpdate = [Int32]()
    var bookDeleted = [Int32]()
}

struct CalibreLibraryCategory: Codable {
    var name: String
    var url: String
    var icon: String
    var is_category: Bool
}

struct CalibreCdbCmdListResult: Codable, Hashable {
    struct DateValue: Codable, Hashable {
        var v: String
    }
    struct Data: Codable, Hashable {
        var last_modified: [String: DateValue] = [:]
//        var title: [String: String] = [:]
//        var authors: [String: [String]] = [:]
//        var formats: [String: Set<String>] = [:]
//        var series: [String: String?] = [:]
//        var series_index: [String: Double] = [:]
//        var identifiers: [String: [String: String]] = [:]
//        var timestamp: [String: DateValue] = [:]
//        var pubdate: [String: DateValue] = [:]
    }
    
    var book_ids = [Int32]()
    var data = Data()
}

struct CalibreDSReaderHelperPrefs: Codable, Hashable {
    struct Options: Codable, Hashable {
        var servicePort = 0
        var goodreadsSyncEnabled = false
        var dictViewerEnabled = false
        var dictViewerLibraryName = ""
        var readingPositionColumnAllLibrary = false
        var readingPositionColumnName = ""
        var readingPositionColumnPrefix = ""
        var readingPositionColumnUserSeparated = false
        
        var isEnabled: Bool { goodreadsSyncEnabled || dictViewerEnabled }
        var autoUpdateGoodreadsProgress: Bool { goodreadsSyncEnabled }
        var autoUpdateGoodreadsBookShelf: Bool { goodreadsSyncEnabled }
    }
    
    struct PluginPrefs: Codable, Hashable {
        var Options: Options
    }
    
    var plugin_prefs: PluginPrefs
}

struct CalibreCountPagesPrefs: Codable, Hashable {
    struct LibraryConfig: Codable, Hashable {
        var SchemaVersion = 1.0
        var customColumnFleschGrade = ""
        var customColumnFleschReading = ""
        var customColumnGunningFog = ""
        var customColumnPages = ""
        var customColumnWords = ""
        
        var isEnabled: Bool {
            [customColumnPages, customColumnWords, customColumnFleschReading, customColumnFleschGrade, customColumnGunningFog].contains { $0.count > 0 && $0 != "#" }
        }
        var pageCountCN: String { customColumnPages }
        var wordCountCN: String { customColumnWords }
        var fleschReadingEaseCN: String { customColumnFleschReading }
        var fleschKincaidGradeCN: String { customColumnFleschGrade }
        var gunningFogIndexCN: String { customColumnGunningFog }
    }
    
    var library_config: [String: LibraryConfig]? = [:]
}

struct CalibreGoodreadsSyncPrefs: Codable, Hashable {
    struct Goodreads: Codable, Hashable {
        var dateReadColumn = ""
        var ratingColumn = ""
        var readingProgressColumn = ""
        var reviewTextColumn = ""
        var tagMappingColumn = ""
    }
    struct Shelves: Codable, Hashable {
        var shelves: [Shelf]
    }
    struct Shelf: Codable, Hashable {
        var active: Bool
        var name: String
        var exclusive: Bool
        var book_count: String
        var tagMappings: [String]
    }
    
    struct PluginPrefs: Codable, Hashable {
        var SchemaVersion = 0.0
        var Goodreads: Goodreads
//        var Users: [String: [String: [Shelf]]]  //Profile -> "shelves" -> [Shelf]
        var Users: [String: Shelves]
        
        var isEnabled: Bool { !Users.isEmpty }
        var tagsColumnName: String { Goodreads.tagMappingColumn }
        var ratingColumnName: String { Goodreads.ratingColumn }
        var dateReadColumnName: String { Goodreads.dateReadColumn }
        var reviewColumnName: String { Goodreads.reviewTextColumn }
        var readingProgressColumnName: String { Goodreads.readingProgressColumn }
        
        var profileName: String {
            Users.count == 1 ? Users.keys.first ?? "" : (Users["Default"] != nil ? "Default" : "")
        }
    }
    var plugin_prefs: PluginPrefs
}

struct CalibreDSReaderHelperConfiguration: Codable, Hashable {
    var dsreader_helper_prefs: CalibreDSReaderHelperPrefs? = nil
    var count_pages_prefs: CalibreCountPagesPrefs? = nil
    var goodreads_sync_prefs: CalibreGoodreadsSyncPrefs? = nil
}

struct CalibreLibraryBooksResult: Codable {
    struct SearchResult: Codable {
        var total_num: Int
        var sort_order: String
        var num_books_without_search: Int
        var offset: Int
        var num: Int
        var sort: String
        var base_url: String
        var query: String?
        var library_id: String
        var book_ids: [Int32]
        var vl: String
    }
    
    struct BookMetadata: Codable {
        var title: String
        var authors: [String]
    }
    
    var search_result: SearchResult
    var metadata: [String: BookMetadata]
}

class CalibreActivity {
    let type: String
    
    init(_ type: String) {
        self.type = type
    }
}

class CalibreActivityStart: CalibreActivity {
    let request: URLRequest
    let startDatetime: Date
    let bookId: Int32?
    let libraryId: String?
    
    init(_ type: String, _ request: URLRequest, startDatetime: Date, bookId: Int32?, libraryId: String?) {
        self.request = request
        self.startDatetime = startDatetime
        self.bookId = bookId
        self.libraryId = libraryId
        
        super.init(type)
    }
}

class CalibreActivityFinish: CalibreActivity {
    let request: URLRequest
    let startDatetime: Date
    let finishDatetime: Date
    let errMsg: String
    
    init(_ type: String, _ request: URLRequest, startDatetime: Date, finishDatetime: Date, errMsg: String) {
        self.request = request
        self.startDatetime = startDatetime
        self.finishDatetime = finishDatetime
        self.errMsg = errMsg
        
        super.init(type)
    }
}

extension Array {
    func chunks(size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

protocol CalibreServerConfigProvider: AnyObject {
    var deviceName: String { get }
    var calibreLibraries: [String: CalibreLibrary] { get }
    var librarySyncStatus: [String: CalibreSyncStatus] { get set }
    var calibreServerInfoStaging: [String: CalibreServerInfo] { get }
    
    var updatingMetadata: Bool { get set }
    var updatingMetadataStatus: String { get set }
    var updatingMetadataSucceed: Bool { get set }
    
    func updateBook(book: CalibreBook)
    func getBookRealm(forPrimaryKey: String) -> CalibreBookRealm?
    func refreshShelfMetadataV2(with servers: Set<String>, for books: Set<String>, serverReachableChanged: Bool)
    func getPreferredFormat(for book: CalibreBook) -> Format?
}
