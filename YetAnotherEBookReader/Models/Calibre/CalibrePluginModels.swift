//
//  CalibrePluginModels.swift
//  YetAnotherEBookReader
//
//  Split from CalibreData.swift on 2026/6/18.
//  Zero-behavior-change move: Calibre plugin preference Codable models and
//  the DSReader Helper configuration aggregate.
//

import Foundation

struct CalibreServerDSReaderHelper: Hashable {
    static let validPorts = 1024...65535

    static func parsePort(_ text: String) -> Int? {
        guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }),
              let port = Int(text), validPorts.contains(port) else { return nil }
        return port
    }

    var port: Int
    var configurationData: Data?

    init(port: Int, configurationData: Data? = nil) {
        self.port = port
        self.configurationData = configurationData
    }

    var configuration: CalibreDSReaderHelperConfiguration? {
        get {
            guard let data = configurationData else { return nil }
            return try? JSONDecoder().decode(CalibreDSReaderHelperConfiguration.self, from: data)
        }
        set {
            if let newValue = newValue {
                configurationData = try? JSONEncoder().encode(newValue)
            } else {
                configurationData = nil
            }
        }
    }
}

/// CalibreServer equality is for address/username lookup. Configuration requests
/// also need the actual server identity, both addresses, and authentication settings.
struct DSReaderHelperConnection: Equatable {
    let serverID: String
    private let baseURL: String
    private let publicURL: String
    private let hasPublicURL: Bool
    private let hasAuth: Bool
    private let username: String
    private let password: String
    private let removed: Bool

    init(_ server: CalibreServer) {
        serverID = server.id
        baseURL = server.baseUrl
        publicURL = server.publicUrl
        hasPublicURL = server.hasPublicUrl
        hasAuth = server.hasAuth
        username = server.username
        password = server.password
        removed = server.removed
    }
}

struct DSReaderHelperStoredConfiguration: Equatable {
    let connection: DSReaderHelperConnection
    let helper: CalibreServerDSReaderHelper?
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

extension CalibreDSReaderHelperPrefs.Options {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        servicePort = try values.decode(Int.self, forKey: .servicePort)
        goodreadsSyncEnabled = try values.decodeIfPresent(Bool.self, forKey: .goodreadsSyncEnabled) ?? false
        dictViewerEnabled = try values.decodeIfPresent(Bool.self, forKey: .dictViewerEnabled) ?? false
        dictViewerLibraryName = try values.decodeIfPresent(String.self, forKey: .dictViewerLibraryName) ?? ""
        // Newer Helper versions omit the retired reading-position settings.
        readingPositionColumnAllLibrary = try values.decodeIfPresent(Bool.self, forKey: .readingPositionColumnAllLibrary) ?? false
        readingPositionColumnName = try values.decodeIfPresent(String.self, forKey: .readingPositionColumnName) ?? ""
        readingPositionColumnPrefix = try values.decodeIfPresent(String.self, forKey: .readingPositionColumnPrefix) ?? ""
        readingPositionColumnUserSeparated = try values.decodeIfPresent(Bool.self, forKey: .readingPositionColumnUserSeparated) ?? false
    }
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

enum CalibreLibraryPluginPreferences {
    static func dsReaderHelperOptions(
        configuration: CalibreDSReaderHelperConfiguration?
    ) -> CalibreDSReaderHelperPrefs.Options {
        configuration?.dsreader_helper_prefs?.plugin_prefs.Options ?? .init()
    }

    static func dictionaryViewerOptions(
        configuration: CalibreDSReaderHelperConfiguration?
    ) -> CalibreDSReaderHelperPrefs.Options {
        dsReaderHelperOptions(configuration: configuration)
    }

    static func goodreadsSyncPreferences(
        configuration: CalibreDSReaderHelperConfiguration?
    ) -> CalibreGoodreadsSyncPrefs.PluginPrefs {
        configuration?.goodreads_sync_prefs?.plugin_prefs ?? .init(Goodreads: .init(), Users: [:])
    }

    static func countPagesConfiguration(
        configuration: CalibreDSReaderHelperConfiguration?,
        libraryName: String
    ) -> CalibreCountPagesPrefs.LibraryConfig {
        configuration?.count_pages_prefs?.library_config?[libraryName] ?? .init()
    }
}
