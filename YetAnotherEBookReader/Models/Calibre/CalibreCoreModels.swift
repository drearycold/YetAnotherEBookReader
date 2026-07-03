//
//  CalibreCoreModels.swift
//  YetAnotherEBookReader
//
//  Split from CalibreData.swift on 2026/6/18.
//  Zero-behavior-change move: core Calibre domain value types.
//

import Foundation

enum BookAnnotation {
    static func PrefId(library: CalibreLibrary, id: Int32) -> String {
        "\(library.key) - \(id)"
    }
}

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
        guard let container = AppContainer.shared,
              let configuration = container.serverManager.queryServerDSReaderHelper(server: server)?.configuration,
              let prefs = configuration.dsreader_helper_prefs?.plugin_prefs
        else { return .init() }
        
        return prefs.Options
    }

    var pluginDictionaryViewerWithDefault: CalibreDSReaderHelperPrefs.Options {
        return pluginDSReaderHelperWithDefault
    }
    
    var pluginGoodreadsSyncWithDefault: CalibreGoodreadsSyncPrefs.PluginPrefs {
        guard let container = AppContainer.shared,
              let configuration = container.serverManager.queryServerDSReaderHelper(server: server)?.configuration,
              let grsync_plugin_prefs = configuration.goodreads_sync_prefs?.plugin_prefs
        else {
            return .init(Goodreads: .init(), Users: [:])
        }
        
        return grsync_plugin_prefs
    }
    
    var pluginCountPagesWithDefault: CalibreCountPagesPrefs.LibraryConfig {
        guard let container = AppContainer.shared,
              let configuration = container.serverManager.queryServerDSReaderHelper(server: server)?.configuration,
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
