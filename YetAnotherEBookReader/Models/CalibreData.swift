//
//  CalibreData.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/4/8.
//

import Foundation

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
    var lastLibrary = ""
    
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
        get { return server.id + " - " + name }
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
    
    var autoUpdate = true
    var discoverable = true
    var lastModified = Date(timeIntervalSince1970: 0)
    
    var customColumnInfos = [String: CalibreCustomColumnInfo]() //label as key
    var customColumnInfosUnmatched: [CalibreCustomColumnInfo] {
        var result = customColumnInfos
        // print("customColumnInfosUnmatched \(customColumnInfos) \(pluginReadingPositionWithDefault) \(pluginGoodreadsSyncWithDefault) \(pluginCountPagesWithDefault)")
        result.removeValue(forKey: pluginReadingPositionWithDefault?.readingPositionCN.removingPrefix("#") ?? "_")

        result.removeValue(forKey: pluginGoodreadsSyncWithDefault?.tagsColumnName.removingPrefix("#") ?? "_")
        result.removeValue(forKey: pluginGoodreadsSyncWithDefault?.ratingColumnName.removingPrefix("#") ?? "_")
        result.removeValue(forKey: pluginGoodreadsSyncWithDefault?.readingProgressColumnName.removingPrefix("#") ?? "_")
        result.removeValue(forKey: pluginGoodreadsSyncWithDefault?.dateReadColumnName.removingPrefix("#") ?? "_")
        result.removeValue(forKey: pluginGoodreadsSyncWithDefault?.reviewColumnName.removingPrefix("#") ?? "_")

        result.removeValue(forKey: pluginCountPagesWithDefault?.pageCountCN.removingPrefix("#") ?? "_")
        result.removeValue(forKey: pluginCountPagesWithDefault?.wordCountCN.removingPrefix("#") ?? "_")
        result.removeValue(forKey: pluginCountPagesWithDefault?.fleschKincaidGradeCN.removingPrefix("#") ?? "_")
        result.removeValue(forKey: pluginCountPagesWithDefault?.fleschReadingEaseCN.removingPrefix("#") ?? "_")
        result.removeValue(forKey: pluginCountPagesWithDefault?.gunningFogIndexCN.removingPrefix("#") ?? "_")

        return result.map { $0.value }
    }
    
    var customColumnInfoNumberKeysFull: [CalibreCustomColumnInfo] {
        customColumnInfos.values.filter{ $0.datatype == "int" || $0.datatype == "float" }
    }
    var customColumnInfoTextKeysFull: [CalibreCustomColumnInfo] {
        customColumnInfos.values.filter{ $0.datatype == "comments" || $0.datatype == "text" }
    }
    var customColumnInfoDateKeysFull: [CalibreCustomColumnInfo] {
        customColumnInfos.values.filter{ $0.datatype == "datetime" }
    }
    var customColumnInfoRatingKeysFull: [CalibreCustomColumnInfo] {
        customColumnInfos.values.filter{ $0.datatype == "rating" }
    }
    var customColumnInfoMultiTextKeysFull: [CalibreCustomColumnInfo] {
        customColumnInfos.values.filter{ $0.datatype == "text" && $0.isMultiple }
    }
    var customColumnInfoCommentsKeysFull: [CalibreCustomColumnInfo] {
        customColumnInfos.values.filter{ $0.datatype == "comments" }
    }
    
    var customColumnInfoNumberKeys: [CalibreCustomColumnInfo] {
        customColumnInfosUnmatched.filter{ $0.datatype == "int" || $0.datatype == "float" }
    }
    var customColumnInfoTextKeys: [CalibreCustomColumnInfo] {
        customColumnInfosUnmatched.filter{ $0.datatype == "comments" || $0.datatype == "text" }
    }
    var customColumnInfoDateKeys: [CalibreCustomColumnInfo] {
        customColumnInfosUnmatched.filter{ $0.datatype == "datetime" }
    }
    var customColumnInfoRatingKeys: [CalibreCustomColumnInfo] {
        customColumnInfosUnmatched.filter{ $0.datatype == "rating" }
    }
    var customColumnInfoMultiTextKeys: [CalibreCustomColumnInfo] {
        customColumnInfosUnmatched.filter{ $0.datatype == "text" && $0.isMultiple }
    }
    var customColumnInfoCommentsKeys: [CalibreCustomColumnInfo] {
        customColumnInfosUnmatched.filter{ $0.datatype == "comments" }
    }
    
    var readPosColumnNameDefault: String {
        if server.username.isEmpty {
            return "#read_pos"
        } else {
            return "#read_pos_\(server.username)"
        }
    }
    
    var pluginColumns = [String: CalibreLibraryPluginColumnInfo]()
    
    var pluginDSReaderHelper: CalibreLibraryDSReaderHelper? {
        get {
            pluginColumns[CalibreLibrary.PLUGIN_DSREADER_HELPER] as? CalibreLibraryDSReaderHelper
        }
        set {
            pluginColumns[CalibreLibrary.PLUGIN_DSREADER_HELPER] = newValue
        }
    }
    var pluginDSReaderHelperWithDefault: CalibreLibraryDSReaderHelper? {
        var dsreaderHelper: CalibreLibraryDSReaderHelper? = nil
        if let dsreaderHelperUser = pluginDSReaderHelper {  //donot check override
            dsreaderHelper = dsreaderHelperUser
        } else if let modelData = ModelData.shared {
            dsreaderHelper = .init(libraryId: id, configuration: modelData.queryServerDSReaderHelper(server: server)?.configuration)
        }
        
        return dsreaderHelper
    }
    
    var pluginReadingPosition: CalibreLibraryReadingPosition? {
        get {
            pluginColumns[CalibreLibrary.PLUGIN_READING_POSITION] as? CalibreLibraryReadingPosition
        }
        set {
            pluginColumns[CalibreLibrary.PLUGIN_READING_POSITION] = newValue
        }
    }
    var pluginReadingPositionWithDefault: CalibreLibraryReadingPosition? {
        var readingPosition: CalibreLibraryReadingPosition? = nil
        if let readingPositionUser = pluginReadingPosition, readingPositionUser.isOverride() {
            readingPosition = readingPositionUser
        } else if let modelData = ModelData.shared {
            readingPosition = .init(libraryId: id, configuration: modelData.queryServerDSReaderHelper(server: server)?.configuration)
        }
        
        return readingPosition
    }

    var pluginDictionaryViewer: CalibreLibraryDictionaryViewer? {
        get {
            pluginColumns[CalibreLibrary.PLUGIN_DICTIONARY_VIEWER] as? CalibreLibraryDictionaryViewer
        }
        set {
            pluginColumns[CalibreLibrary.PLUGIN_DICTIONARY_VIEWER] = newValue
        }
    }
    var pluginDictionaryViewerWithDefault: CalibreLibraryDictionaryViewer? {
        var dictionaryViewer: CalibreLibraryDictionaryViewer? = nil
        if let dictionaryViewerUser = pluginDictionaryViewer, dictionaryViewerUser.isOverride() {
            dictionaryViewer = dictionaryViewerUser
        } else if let modelData = ModelData.shared {
            dictionaryViewer = .init(libraryId: id, configuration: modelData.queryServerDSReaderHelper(server: server)?.configuration)
        }
        
        return dictionaryViewer
    }
    
    var pluginGoodreadsSync: CalibreLibraryGoodreadsSync? {
        get {
            pluginColumns[CalibreLibrary.PLUGIN_GOODREADS_SYNC] as? CalibreLibraryGoodreadsSync
        }
        set {
            pluginColumns[CalibreLibrary.PLUGIN_GOODREADS_SYNC] = newValue
        }
    }
    var pluginGoodreadsSyncWithDefault: CalibreLibraryGoodreadsSync? {
        var goodreadsSync: CalibreLibraryGoodreadsSync? = nil
        if let goodreadsSyncUser = pluginGoodreadsSync, goodreadsSyncUser.isOverride() {
            goodreadsSync = goodreadsSyncUser
        } else if let modelData = ModelData.shared {
            goodreadsSync = .init(libraryId: id, configuration: modelData.queryServerDSReaderHelper(server: server)?.configuration)
        }
        
        return goodreadsSync
    }
    
    var pluginCountPages: CalibreLibraryCountPages? {
        get {
            pluginColumns[CalibreLibrary.PLUGIN_COUNT_PAGES] as? CalibreLibraryCountPages
        }
        set {
            pluginColumns[CalibreLibrary.PLUGIN_COUNT_PAGES] = newValue
        }
    }
    var pluginCountPagesWithDefault: CalibreLibraryCountPages? {
        var countPages: CalibreLibraryCountPages? = nil
        if let countPagesUser = pluginCountPages, countPagesUser.isOverride() {
            countPages = countPagesUser
        } else if let modelData = ModelData.shared {
            countPages = .init(libraryId: id, configuration: modelData.queryServerDSReaderHelper(server: server)?.configuration)
        }
        
        return countPages
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
        guard let pluginGoodreadsSync = library.pluginGoodreadsSyncWithDefault, pluginGoodreadsSync.isEnabled(),
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
        guard let pluginGoodreadsSync = library.pluginGoodreadsSyncWithDefault, pluginGoodreadsSync.isEnabled(),
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
        guard let pluginGoodreadsSync = library.pluginGoodreadsSyncWithDefault, pluginGoodreadsSync.isEnabled(),
              let progressAny = userMetadatas[pluginGoodreadsSync.readingProgressColumnName.trimmingCharacters(in: CharacterSet(["#"]))],
              let prog = progressAny else { return nil }
        return Int(String(describing: prog))?.description
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
//        return "\(id)^\(library.id)"
        return CalibreBookRealm.PrimaryKey(serverUsername: library.server.username, serverUrl: library.server.baseUrl, libraryName: library.name, id: id.description)
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
    
    var epochByLocale: String {
        let dateFormatter = DateFormatter()
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

struct CalibreBooksTask {
    var library: CalibreLibrary
    var books: [String]
    var url: URL
    var data: Data? = nil
    var response: URLResponse? = nil
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
    var rating: Double = 0.0
    var authors: [String] = []
    var format_metadata: [String: CalibreBookFormatMetadataEntry] = [:]
    var formats: [String] = []
    var main_format: [String: String]? = [:]
    var other_formats: [String: String]? = [:]
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

struct CalibreCustomColumnInfoResult {
    var library: CalibreLibrary
    var result: [String: [String:CalibreCustomColumnInfo]]
    var errmsg = ""
    var list = CalibreCdbCmdListResult()
}

struct CalibreCdbCmdListResult: Codable, Hashable {
    struct DateValue: Codable, Hashable {
        var v: String
    }
    struct Data: Codable, Hashable {
        var title: [String: String] = [:]
        var authors: [String: [String]] = [:]
        var formats: [String: Set<String>] = [:]
        var series: [String: String?] = [:]
        var series_index: [String: Double] = [:]
        var identifiers: [String: [String: String]] = [:]
        var last_modified: [String: DateValue] = [:]
        var timestamp: [String: DateValue] = [:]
        var pubdate: [String: DateValue] = [:]
    }
    
    var book_ids = [Int32]()
    var data = Data()
}

struct CalibreServerDSReaderHelper: Codable, Hashable, Identifiable {
    /**
     corresponding server id
     */
    var id: String
    var port: Int
    
    var configurationData: Data? = nil
    
    /**
     parsed data
     */
    var configuration: CalibreDSReaderHelperConfiguration? = nil
}

protocol CalibreLibraryPluginColumnInfo {
    init()
    init(libraryId: String, configuration: CalibreDSReaderHelperConfiguration?)
    
    func getID() -> String
    func isEnabled() -> Bool
    func isDefault() -> Bool
    func isOverride() -> Bool
    func hasValidColumn() -> Bool
    func mappedColumnsCount() -> Int
}

struct CalibreLibraryGoodreadsSync: CalibreLibraryPluginColumnInfo, Codable, Hashable, Identifiable {
    var id: String {
        return CalibreLibrary.PLUGIN_GOODREADS_SYNC
    }
    
    func getID() -> String {
        return id
    }
    
    func isEnabled() -> Bool {
        return _isEnabled
    }
    
    func isDefault() -> Bool {
        return _isDefault
    }
    
    func isOverride() -> Bool {
        return _isOverride
    }
    
    var _isEnabled = false
    var _isDefault = false
    var _isOverride = false

    var profileName = "Default"
    var tagsColumnName = "#"
    var ratingColumnName = "#"
    var dateReadColumnName = "#"
    var reviewColumnName = "#"
    var readingProgressColumnName = "#"
    
    init() {
        //pass
    }
    
    init(libraryId: String, configuration: CalibreDSReaderHelperConfiguration?) {
        guard let grsync_plugin_prefs = configuration?.goodreads_sync_prefs?.plugin_prefs else { return }
        tagsColumnName = grsync_plugin_prefs.Goodreads.tagMappingColumn
        dateReadColumnName = grsync_plugin_prefs.Goodreads.dateReadColumn
        ratingColumnName = grsync_plugin_prefs.Goodreads.ratingColumn
        reviewColumnName = grsync_plugin_prefs.Goodreads.reviewTextColumn
        readingProgressColumnName = grsync_plugin_prefs.Goodreads.readingProgressColumn
        if grsync_plugin_prefs.Users.count == 1 {
            profileName = grsync_plugin_prefs.Users.keys.first!
        } else {
            profileName = ""
        }
        _isEnabled = hasValidColumn()
    }
    
    func hasValidColumn() -> Bool {
        return profileName.count > 0
            || mappedColumnsCount() > 0
    }

    func mappedColumnsCount() -> Int {
        return [(tagsColumnName.count > 0 && tagsColumnName != "#"),
                (ratingColumnName.count > 0 && ratingColumnName != "#"),
                (dateReadColumnName.count > 0 && dateReadColumnName != "#"),
                (reviewColumnName.count > 0 && reviewColumnName != "#"),
                (readingProgressColumnName.count > 0 && readingProgressColumnName != "#")].filter{$0}.count
    }
}

struct CalibreLibraryReadingPosition: CalibreLibraryPluginColumnInfo, Codable, Hashable, Identifiable {
    var id: String {
        return CalibreLibrary.PLUGIN_READING_POSITION
    }
    
    func getID() -> String {
        return id
    }
    
    func isEnabled() -> Bool {
        return _isEnabled
    }
    
    func isDefault() -> Bool {
        return _isDefault
    }
    
    func isOverride() -> Bool {
        return _isOverride
    }
    
    var _isEnabled = false
    var _isDefault = false
    var _isOverride = false

    var readingPositionCN = "#"
    
    init() {
        //pass
    }
    
    init(libraryId: String, configuration: CalibreDSReaderHelperConfiguration?) {
        guard let library = ModelData.shared?.calibreLibraries[libraryId] else { return }
        
        if let prefs = configuration?.reading_position_prefs,
           let library_config = prefs.library_config[library.name],
           let column_info = library_config.readingPositionColumns[library.server.username],
           column_info.exists {
            readingPositionCN = "#" + column_info.label
        } else {
            let filtered = library.customColumnInfoCommentsKeysFull.filter { $0.label.localizedCaseInsensitiveContains("read") && $0.label.localizedCaseInsensitiveContains("pos") }
            guard filtered.count > 0 else { return }
            if filtered.count == 1, let first = filtered.first {
                readingPositionCN = "#" + first.label
            } else {
                let filtered_username = filtered.filter { $0.label.localizedCaseInsensitiveContains(library.server.username) }
                if filtered_username.count == 1, let first = filtered_username.first {
                    readingPositionCN = "#" + first.label
                }
            }
        }
        
        _isEnabled = hasValidColumn()
    }
    
    func hasValidColumn() -> Bool {
        return mappedColumnsCount() > 0
    }
    
    func mappedColumnsCount() -> Int {
        return [(readingPositionCN.count > 0 && readingPositionCN != "#")].filter{$0}.count
    }
}

struct CalibreLibraryDictionaryViewer: CalibreLibraryPluginColumnInfo, Codable, Hashable, Identifiable {
    var id: String {
        return CalibreLibrary.PLUGIN_DICTIONARY_VIEWER
    }
    
    func getID() -> String {
        return id
    }
    
    func isEnabled() -> Bool {
        return _isEnabled
    }
    
    func isDefault() -> Bool {
        return _isDefault
    }
    
    func isOverride() -> Bool {
        return _isOverride
    }
    
    var _isEnabled = false
    var _isDefault = false
    var _isOverride = false
    
    init() {
        //pass
    }
    
    init(libraryId: String, configuration: CalibreDSReaderHelperConfiguration?) {
        if let prefs = configuration?.dsreader_helper_prefs?.plugin_prefs {
            _isEnabled = prefs.Options.dictViewerEnabled
        } else {
            _isEnabled = false
        }
    }
    
    func hasValidColumn() -> Bool {
        return mappedColumnsCount() > 0
    }
    
    func mappedColumnsCount() -> Int {
        return 0
    }
}

struct CalibreLibraryCountPages: CalibreLibraryPluginColumnInfo, Codable, Hashable, Identifiable {
    var id: String {
        return CalibreLibrary.PLUGIN_COUNT_PAGES
    }
    
    func getID() -> String {
        return id
    }
    
    func isEnabled() -> Bool {
        return _isEnabled
    }
    
    func isDefault() -> Bool {
        return _isDefault
    }
    
    func isOverride() -> Bool {
        return _isOverride
    }
    
    var _isEnabled = false
    var _isDefault = false
    var _isOverride = false

    var pageCountCN = "#"
    var wordCountCN = "#"
    var fleschReadingEaseCN = "#"
    var fleschKincaidGradeCN = "#"
    var gunningFogIndexCN = "#"
    
    init() {
        //pass
    }
    
    init(libraryId: String, configuration: CalibreDSReaderHelperConfiguration?) {
        guard let libraryName = ModelData.shared?.calibreLibraries[libraryId]?.name,
              let library_config = configuration?.count_pages_prefs?.library_config[libraryName] else { return }
        pageCountCN = library_config.customColumnPages
        wordCountCN = library_config.customColumnWords
        fleschReadingEaseCN = library_config.customColumnFleschReading
        fleschKincaidGradeCN = library_config.customColumnFleschGrade
        gunningFogIndexCN = library_config.customColumnGunningFog
        _isEnabled = hasValidColumn()
        
    }
    
    func hasValidColumn() -> Bool {
        return mappedColumnsCount() > 0
    }
    
    func mappedColumnsCount() -> Int {
        return [(pageCountCN.count > 0 && pageCountCN != "#"),
                (wordCountCN.count > 0 && wordCountCN != "#"),
                (fleschReadingEaseCN.count > 0 && fleschReadingEaseCN != "#"),
                (fleschKincaidGradeCN.count > 0 && fleschKincaidGradeCN != "#"),
                (gunningFogIndexCN.count > 0 && gunningFogIndexCN != "#")].filter{$0}.count
    }
}

struct CalibreLibraryDSReaderHelper: CalibreLibraryPluginColumnInfo, Codable, Hashable, Identifiable {
    
    var id: String {
        return CalibreLibrary.PLUGIN_DSREADER_HELPER
    }
    
    func getID() -> String {
        return id
    }
    
    func isEnabled() -> Bool {
        return _isEnabled
    }
    
    func isDefault() -> Bool {
        return _isDefault
    }
    
    func isOverride() -> Bool {
        return _isOverride
    }
    
    var _isEnabled = false
    var _isDefault = false
    var _isOverride = false
    
    //Client-side toggle
    var autoUpdateGoodreadsProgress = false
    var autoUpdateGoodreadsBookShelf = false
    
    init() {
        //pass
    }
    
    init(libraryId: String, configuration: CalibreDSReaderHelperConfiguration?) {
        guard let prefs = configuration?.dsreader_helper_prefs?.plugin_prefs, prefs.Options.goodreadsSyncEnabled else { return }
        guard let users = configuration?.goodreads_sync_prefs?.plugin_prefs.Users, users.count == 1 || users.contains(where: { $0.key == "Default" }) else { return }
        
        autoUpdateGoodreadsBookShelf = true
        autoUpdateGoodreadsProgress = true
        
        _isEnabled = hasValidColumn()
    }
    
    func hasValidColumn() -> Bool {
        return (autoUpdateGoodreadsProgress || autoUpdateGoodreadsBookShelf)
    }
    
    func mappedColumnsCount() -> Int {
        return 0
    }
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
    }
    
    var library_config: [String: LibraryConfig] = [:]
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
    }
    var plugin_prefs: PluginPrefs
}

struct CalibreReadingPositionPrefs: Codable, Hashable {
    
    struct ReadingPositionColumn: Codable, Hashable {
        var exists: Bool = false
        var label: String = ""
        var name: String = ""
    }
    
    struct ReadingPositionOptions: Codable, Hashable {
        var name: String = ""
        var prefix: String = ""
        var isUserSeparated: Bool = false
        
        enum CodingKeys: String, CodingKey {
            case name = "readingPositionColumnName"
            case prefix = "readingPositionColumnPrefix"
            case isUserSeparated = "readingPositionColumnUserSeparated"
        }
    }
    
    struct ReadingPositionLibraryConfig: Codable, Hashable {
        var readingPositionColumns: [String: ReadingPositionColumn] = [:]
        var readingPositionOptions: ReadingPositionOptions = .init()
    }
    
    // library name -> user name -> column info
    var library_config: [String: ReadingPositionLibraryConfig] = [:]
}

struct CalibreDSReaderHelperConfiguration: Codable, Hashable {
    var dsreader_helper_prefs: CalibreDSReaderHelperPrefs? = nil
    var count_pages_prefs: CalibreCountPagesPrefs? = nil
    var goodreads_sync_prefs: CalibreGoodreadsSyncPrefs? = nil
    var reading_position_prefs: CalibreReadingPositionPrefs? = nil
}

extension Array {
    func chunks(size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
