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

    var advancedQAStatus: AdvancedQAStatus? {
        CalibreLibraryPluginPreferences.advancedQAStatus(configuration: configuration)
    }

    var advancedQAAvailability: AdvancedQAAvailability {
        CalibreLibraryPluginPreferences.advancedQAAvailability(configuration: configuration)
    }

    var isAdvancedQAReady: Bool { advancedQAAvailability == .ready }

    mutating func setAdvancedQAState(status: AdvancedQAStatus?, availability: AdvancedQAAvailability) {
        var object = (configurationData.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }) ?? [:]

        if let status,
           let data = try? JSONEncoder().encode(status),
           let value = try? JSONSerialization.jsonObject(with: data) {
            object["advanced_qa_status"] = value
        } else {
            object.removeValue(forKey: "advanced_qa_status")
        }
        object["advanced_qa_availability"] = availability.rawValue
        configurationData = try? JSONSerialization.data(withJSONObject: object)
    }

    mutating func updateConfigurationDataPreservingAdvancedQA(_ data: Data) {
        let status = advancedQAStatus
        let availability = advancedQAAvailability
        configurationData = data
        guard status != nil || availability != .unknown else { return }
        setAdvancedQAState(status: status, availability: availability)
    }
}

struct CalibreDSReaderHelperPrefs: Codable, Hashable {
    struct Options: Codable, Hashable {
        var servicePort = 0
        var goodreadsSyncEnabled = false
        var dictViewerEnabled = false
        var dictViewerLibraryName = ""
        
        var isEnabled: Bool { goodreadsSyncEnabled || dictViewerEnabled }
        var autoUpdateGoodreadsProgress: Bool { goodreadsSyncEnabled }
        var autoUpdateGoodreadsBookShelf: Bool { goodreadsSyncEnabled }

        private enum CodingKeys: String, CodingKey {
            case servicePort, goodreadsSyncEnabled, dictViewerEnabled, dictViewerLibraryName
        }

        init(
            servicePort: Int = 0,
            goodreadsSyncEnabled: Bool = false,
            dictViewerEnabled: Bool = false,
            dictViewerLibraryName: String = ""
        ) {
            self.servicePort = servicePort
            self.goodreadsSyncEnabled = goodreadsSyncEnabled
            self.dictViewerEnabled = dictViewerEnabled
            self.dictViewerLibraryName = dictViewerLibraryName
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            servicePort = try values.decodeIfPresent(Int.self, forKey: .servicePort) ?? 0
            goodreadsSyncEnabled = try values.decodeIfPresent(Bool.self, forKey: .goodreadsSyncEnabled) ?? false
            dictViewerEnabled = try values.decodeIfPresent(Bool.self, forKey: .dictViewerEnabled) ?? false
            dictViewerLibraryName = try values.decodeIfPresent(String.self, forKey: .dictViewerLibraryName) ?? ""
        }
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

    private enum CodingKeys: String, CodingKey {
        case library_config
    }

    init(library_config: [String: LibraryConfig]? = [:]) {
        self.library_config = library_config
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        library_config = try values.decodeIfPresent([String: LibraryConfig].self, forKey: .library_config) ?? [:]
    }
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
    var advanced_qa_status: AdvancedQAStatus? = nil
    var advanced_qa_availability: AdvancedQAAvailability? = nil
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

    static func advancedQAStatus(
        configuration: CalibreDSReaderHelperConfiguration?
    ) -> AdvancedQAStatus? {
        configuration?.advanced_qa_status
    }

    static func advancedQAAvailability(
        configuration: CalibreDSReaderHelperConfiguration?
    ) -> AdvancedQAAvailability {
        configuration?.advanced_qa_availability
            ?? configuration?.advanced_qa_status.map(AdvancedQAAvailability.init(status:))
            ?? .unknown
    }
}
