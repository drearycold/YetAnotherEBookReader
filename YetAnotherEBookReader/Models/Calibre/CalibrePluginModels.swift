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
