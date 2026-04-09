//
//  RealmModel.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/7/22.
//

import Foundation
import UIKit
import RealmSwift

public protocol Persistable {
    associatedtype ManagedObject: RealmSwift.Object
    init(managedObject: ManagedObject)
    func managedObject() -> ManagedObject
}

class CalibreServerRealm: Object {
    @Persisted(primaryKey: true) var primaryKey: String?
    
    @Persisted var name: String?
    @Persisted var baseUrl: String?
    @Persisted var hasPublicUrl = false
    @Persisted var publicUrl: String?
    
    @Persisted var hasAuth = false
    @Persisted var username: String?
    @Persisted var password: String?

    @Persisted var defaultLibrary: String?

    @Persisted var removed = false

    @Persisted var dsreaderHelper: CalibreServerDSReaderHelper?
}

extension CalibreServer: Persistable {
    init(managedObject: CalibreServerRealm) {
        self.name = managedObject.name ?? managedObject.baseUrl!
        self.baseUrl = managedObject.baseUrl!
        self.hasPublicUrl = managedObject.hasPublicUrl
        self.publicUrl = managedObject.publicUrl ?? ""
        self.hasAuth = managedObject.hasAuth
        self.username = managedObject.username ?? ""
        self.password = managedObject.password ?? ""
        self.defaultLibrary = managedObject.defaultLibrary ?? ""
        self.removed = managedObject.removed
        self.uuid = UUID(uuidString: managedObject.primaryKey ?? "") ?? .init()
    }
    
    func managedObject() -> CalibreServerRealm {
        let serverRealm = CalibreServerRealm()
        serverRealm.name = self.name
        serverRealm.baseUrl = self.baseUrl
        serverRealm.hasPublicUrl = self.hasPublicUrl
        serverRealm.publicUrl = self.publicUrl
        serverRealm.hasAuth = self.hasAuth
        serverRealm.username = self.username
        serverRealm.password = self.password
        serverRealm.defaultLibrary = self.defaultLibrary
        serverRealm.removed = self.removed
        serverRealm.primaryKey = self.uuid.uuidString
        
        return serverRealm
    }
}

extension CalibreServer {
    var realmPerf: Realm {
        try! Realm(configuration: BookAnnotation.getBookPreferenceServerConfig(self))
    }
}

class CalibreLibraryRealm: Object, ObjectKeyIdentifiable {
    @Persisted(primaryKey: true) var primaryKey: String?
    
    @Persisted var key: String?
    @Persisted var name: String?
    @Persisted var serverUUID: String?
    
    func updatePrimaryKey() {
        primaryKey = CalibreLibraryRealm.PrimaryKey(serverUUID: serverUUID ?? "-", libraryName: name ?? "-")
    }
    
    static func PrimaryKey(serverUUID: String, libraryName: String) -> String {
        return [libraryName, "@", serverUUID].joined()
    }
    
    var customColumns = List<CalibreCustomColumnRealm>()
    @Persisted var pluginDSReaderHelper:     CalibreLibraryDSReaderHelper?
    @Persisted var pluginReadingPosition:    CalibreLibraryReadingPosition?
    @Persisted var pluginDictionaryViewer:   CalibreLibraryDictionaryViewer?

    @Persisted var pluginGoodreadsSync:      CalibreLibraryGoodreadsSync?
    @Persisted var pluginCountPages:         CalibreLibraryCountPages?
    
    @Persisted var autoUpdate = true
    @Persisted var discoverable = true
    @Persisted var hidden = false
    @Persisted var lastModified = Date(timeIntervalSince1970: 0)
}

class CalibreBookRealm: Object, ObjectKeyIdentifiable {
    @Persisted(primaryKey: true) var primaryKey: String?
    
    @Persisted var serverUUID: String?
    
    @Persisted(indexed: true) var libraryName: String?
    
    @Persisted(indexed: true) var idInLib: Int32 = 0 {
        didSet {
            updatePrimaryKey()
        }
    }
    @Persisted(indexed: true) var title = ""
    @Persisted(indexed: true) var authorFirst: String?
    @Persisted var authorSecond: String?
    @Persisted var authorThird: String?
    @Persisted var authorsMore = List<String>()
    @Persisted var comments = ""
    @Persisted var publisher = ""
    @Persisted(indexed: true) var series = ""
    @Persisted var seriesIndex = 0.0
    @Persisted var rating = 0
    @Persisted var size = 0
    @Persisted(indexed: true) var pubDate = Date(timeIntervalSince1970: 0)
    @Persisted var timestamp = Date(timeIntervalSince1970: 0)
    @Persisted var lastModified = Date(timeIntervalSince1970: 0)
    @Persisted var lastSynced = Date(timeIntervalSince1970: 0)
    @Persisted var lastUpdated = Date(timeIntervalSince1970: 0)  //local only
    @Persisted var lastProgress = 0.0
    
    @Persisted(indexed: true) var tagFirst: String?
    @Persisted var tagSecond: String?
    @Persisted var tagThird: String?
    @Persisted var tagsMore = List<String>()
    @Persisted var formatsData: Data?
    @Persisted var readPosData: Data?
    @Persisted var identifiersData: Data?
    @Persisted var userMetaData: Data?
    
    @Persisted(indexed: true) var inShelf = false
    
    func formats() -> [String: FormatInfo] {
        guard let formatsData = formatsData else { return [:] }
        return (try? JSONDecoder().decode([String:FormatInfo].self, from: formatsData)) ?? [:]
        //return (try? JSONSerialization.jsonObject(with: formatsData as Data, options: []) as? [String: String]) ?? [:]
    }
    
    func identifiers() -> [String: String] {
        guard let identifiersData = identifiersData else { return [:] }
        return (try? JSONDecoder().decode([String:String].self, from: identifiersData)) ?? [:]
//        let identifiers = try! JSONSerialization.jsonObject(with: identifiersData! as Data, options: []) as! [String: String]
//        return identifiers
    }
    
    func userMetadatas() -> [String: Any] {
        guard let userMetaData = userMetaData else { return [:] }
        return (try? JSONSerialization.jsonObject(with: userMetaData, options: []) as? [String:Any]) ?? [:]
    }
    
    func readPos(library: CalibreLibrary) -> BookAnnotation {
        let readPos = BookAnnotation(id: idInLib, library: library)
        
        guard let readPosData = readPosData,
              let readPosDict = try? JSONSerialization.jsonObject(with: readPosData, options: []) as? NSDictionary,
              let deviceMapDict = readPosDict["deviceMap"] as? NSDictionary
        else {
            return readPos
        }
        
        deviceMapDict.forEach { key, value in
            guard let deviceName = key as? String,
                  let deviceReadingPositionDict = value as? [String: Any],
                  var readerName = deviceReadingPositionDict["readerName"] as? String else {
                return
            }
            
            // MARK: TEMPFIX for reader name changes
            if readerName == "FolioReader" {
                readerName = ReaderType.YabrEPUB.rawValue
            }
            if readerName == "YabrPDFView" {
                readerName = ReaderType.YabrPDF.rawValue
            }
            
            var deviceReadingPosition = BookDeviceReadingPosition(id: deviceName, readerName: readerName)
            
            deviceReadingPosition.lastReadPage = deviceReadingPositionDict["lastReadPage"] as? Int ?? 0
            deviceReadingPosition.lastReadChapter = deviceReadingPositionDict["lastReadChapter"] as? String ?? ""
            deviceReadingPosition.lastChapterProgress = deviceReadingPositionDict["lastChapterProgress"] as? Double ?? 0.0
            deviceReadingPosition.lastProgress = deviceReadingPositionDict["lastProgress"] as? Double ?? 0.0
            deviceReadingPosition.furthestReadPage = deviceReadingPositionDict["furthestReadPage"] as? Int ?? deviceReadingPosition.lastReadPage
            deviceReadingPosition.furthestReadChapter = deviceReadingPositionDict["furthestReadChapter"] as? String ?? deviceReadingPosition.lastReadChapter
            deviceReadingPosition.maxPage = deviceReadingPositionDict["maxPage"] as? Int ?? 1
            if let cfi = deviceReadingPositionDict["cfi"] as? String {
                deviceReadingPosition.cfi = cfi
            }
            deviceReadingPosition.epoch = deviceReadingPositionDict["epoch"] as? Double ?? 0.0
            if let lastPosition = deviceReadingPositionDict["lastPosition"] as? [Int] {
                deviceReadingPosition.lastPosition = lastPosition
            }
            
            deviceReadingPosition.structuralStyle = deviceReadingPositionDict["structuralStyle"] as? Int ?? .zero
            deviceReadingPosition.structuralRootPageNumber = deviceReadingPositionDict["structuralRootPageNumber"] as? Int ?? .zero
            deviceReadingPosition.positionTrackingStyle = deviceReadingPositionDict["positionTrackingStyle"] as? Int ?? .zero
            deviceReadingPosition.lastReadBook = deviceReadingPositionDict["lastReadBook"] as? String ?? .init()
            deviceReadingPosition.lastBundleProgress = deviceReadingPositionDict["lastBundleProgress"] as? Double ?? .zero
            
            readPos.updatePosition(deviceReadingPosition)
        }
        return readPos
    }
    
    func updatePrimaryKey() {
        primaryKey = CalibreBookRealm.PrimaryKey(serverUUID: serverUUID!, libraryName: libraryName!, id: idInLib.description)
    }
    
    static func PrimaryKey(serverUUID: String, libraryName: String, id: String) -> String {
        return [id, "^", libraryName, "@", serverUUID].joined()
    }
    
    var ratingDescription: String {
        CalibreBookRealm.RatingDescription(rating)
    }
    
    static func RatingDescription(_ rating: Int) -> String {
        if rating == 0 {
            return "No Rating"
        } else {
            let starNum = rating / 2
            let half = (rating % 2) > 0
            
            return Array(repeating: "★", count: starNum).joined()
            + (half ? "☆" : "")
        }
//        if rating > 9 {
//            return "★★★★★"
//        } else if rating > 7 {
//            return "★★★★"
//        } else if rating > 5 {
//            return "★★★"
//        } else if rating > 3 {
//            return "★★"
//        } else if rating > 1 {
//            return "★"
//        } else {
//            return "☆"
//        }
    }
}

extension CalibreBook: Persistable {
    internal init(managedObject: CalibreBookRealm) {
        self.id = 0
        self.library = .init(server: .init(uuid: .init(), name: "", baseUrl: "", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: ""), key: "", name: "")
        self.readPos = BookAnnotation(id: id, library: library)
    }
    
    public init(managedObject: CalibreBookRealm, library: CalibreLibrary) {
        let formatsVer1 = managedObject.formats().reduce(
            into: [String: FormatInfo]()
        ) { result, entry in
            result[entry.key] = FormatInfo(serverSize: 0, serverMTime: .distantPast, cached: false, cacheSize: 0, cacheMTime: .distantPast)
        }
//        let formatsVer2 = try? JSONSerialization.jsonObject(with: bookRealm.formatsData! as Data, options: []) as? [String: FormatInfo]
        let decoder = JSONDecoder()
        let formatsVer2 = (try? decoder.decode([String:FormatInfo].self, from: managedObject.formatsData as Data? ?? .init()))
                ?? formatsVer1
        
        self.id = managedObject.idInLib
        self.library = library
        self.title = managedObject.title
        self.comments = managedObject.comments
        self.publisher = managedObject.publisher
        self.series = managedObject.series
        self.seriesIndex = managedObject.seriesIndex
        self.rating = managedObject.rating
        self.size = managedObject.size
        self.pubDate = managedObject.pubDate
        self.timestamp = managedObject.timestamp
        self.lastModified = managedObject.lastModified
        self.lastSynced = managedObject.lastSynced
        self.lastUpdated = managedObject.lastUpdated
        self.formats = formatsVer2
        self.readPos = managedObject.readPos(library: library)
        if managedObject.readPosData != nil,
           managedObject.isFrozen == false {
            try? managedObject.realm?.write({
                managedObject.readPosData = nil
            })
        }
        
        self.inShelf = managedObject.inShelf
        
        if managedObject.identifiersData != nil {
            self.identifiers = managedObject.identifiers()
        }
        if managedObject.userMetaData != nil {
            self.userMetadatas = managedObject.userMetadatas()
        }
        if let authorFirst = managedObject.authorFirst {
            self.authors.append(authorFirst)
        }
        if let authorSecond = managedObject.authorSecond {
            self.authors.append(authorSecond)
        }
        if let authorThird = managedObject.authorThird {
            self.authors.append(authorThird)
        }
        self.authors.append(contentsOf: managedObject.authorsMore)
        
        if let tagFirst = managedObject.tagFirst {
            self.tags.append(tagFirst)
        }
        if let tagSecond = managedObject.tagSecond {
            self.tags.append(tagSecond)
        }
        if let tagThird = managedObject.tagThird {
            self.tags.append(tagThird)
        }
        self.tags.append(contentsOf: managedObject.tagsMore)
    }
    
    public func managedObject() -> CalibreBookRealm {
        let bookRealm = CalibreBookRealm()
        bookRealm.serverUUID = self.library.server.uuid.uuidString
        bookRealm.libraryName = self.library.name
        bookRealm.idInLib = self.id

        bookRealm.title = self.title

        var authors = self.authors
        bookRealm.authorFirst = authors.popFirst() ?? "Unknown"
        bookRealm.authorSecond = authors.popFirst()
        bookRealm.authorThird = authors.popFirst()
        bookRealm.authorsMore.replaceSubrange(bookRealm.authorsMore.indices, with: authors)

        bookRealm.comments = self.comments
        bookRealm.publisher = self.publisher
        bookRealm.series = self.series
        bookRealm.seriesIndex = self.seriesIndex
        bookRealm.rating = self.rating
        bookRealm.size = self.size
        bookRealm.pubDate = self.pubDate
        bookRealm.timestamp = self.timestamp
        bookRealm.lastModified = self.lastModified
        bookRealm.lastSynced = self.lastSynced
        bookRealm.lastUpdated = self.lastUpdated
        
        var tags = self.tags
        bookRealm.tagFirst = tags.popFirst()
        bookRealm.tagSecond = tags.popFirst()
        bookRealm.tagThird = tags.popFirst()
        bookRealm.tagsMore.replaceSubrange(bookRealm.tagsMore.indices, with: tags)

        bookRealm.inShelf = self.inShelf
        
        let encoder = JSONEncoder()
        bookRealm.formatsData = try? encoder.encode(self.formats)
        
        //bookRealm.identifiersData = try JSONSerialization.data(withJSONObject: book.identifiers, options: []) as NSData
        bookRealm.identifiersData = try? encoder.encode(self.identifiers)
        
        bookRealm.userMetaData = try? JSONSerialization.data(withJSONObject: self.userMetadatas, options: [])
        
//        let deviceMapSerialize = self.readPos.getCopy().compactMapValues { (value) -> Any? in
//            try? JSONSerialization.jsonObject(with: encoder.encode(value))
//        }
//        bookRealm.readPosData = try? JSONSerialization.data(withJSONObject: ["deviceMap": deviceMapSerialize], options: []) as NSData
        bookRealm.readPosData = nil
        
        return bookRealm
    }
}

class CalibreCustomColumnRealm: Object {
    @objc dynamic var label = ""
    @objc dynamic var name = ""
    @objc dynamic var datatype = ""
    @objc dynamic var editable = false
    
    @objc dynamic var normalized = false
    @objc dynamic var num = 0
    @objc dynamic var isMultiple = false
    
    @objc dynamic var multipleSepsCacheToList: String?
    @objc dynamic var multipleSepsUiToList: String?
    @objc dynamic var multipleSepsListToUi: String?

    @objc dynamic var displayDescription = ""
    
    //type text
    @objc dynamic var displayIsNames = false
    
    //tyoe composite
    @objc dynamic var displayCompositeTemplate: String?
    @objc dynamic var displayCompositeSort: String?
    @objc dynamic var displayUseDecorations = 0
    @objc dynamic var displayMakeCategory = false
    @objc dynamic var displayContainsHtml = false
    
    //type int, float
    @objc dynamic var displayNumberFormat: String?
    
    //type comments
    @objc dynamic var displayHeadingPosition: String?
    @objc dynamic var displayInterpretAs: String?
    
    //type rating
    @objc dynamic var displayAllowHalfStars = false
    
    override static func primaryKey() -> String? {
        return "label"
    }
}

extension CalibreCustomColumnInfo: Persistable {
    public init(managedObject: CalibreCustomColumnRealm) {
        label = managedObject.label
        name = managedObject.name
        datatype = managedObject.datatype
        editable = managedObject.editable
        normalized = managedObject.normalized
        num = managedObject.num
        isMultiple = managedObject.isMultiple
        multipleSeps = [:]
        display = CalibreCustomColumnDisplayInfo(description: "", isNames: nil, compositeTemplate: nil, compositeSort: nil, useDecorations: nil, makeCategory: nil, containsHtml: nil, numberFormat: nil, headingPosition: nil, interpretAs: nil, allowHalfStars: nil)
    }
    
    public func managedObject() -> CalibreCustomColumnRealm {
        let obj = CalibreCustomColumnRealm()
        obj.label = label
        obj.name = name
        obj.datatype = datatype
        obj.editable = editable
        obj.normalized = normalized
        obj.num = num
        obj.isMultiple = isMultiple
        
        return obj
    }
}

class CalibreLibraryGoodreadsSync: EmbeddedObject, ObjectKeyIdentifiable, CalibreLibraryPluginColumnInfo {
    @Persisted var _isEnabled = false
    @Persisted var _isDefault = false
    @Persisted var _isOverride = false
    
    @Persisted var profileName: String = ""
    @Persisted var tagsColumnName: String = "#"
    @Persisted var ratingColumnName: String = "#"
    @Persisted var dateReadColumnName: String = "#"
    @Persisted var reviewColumnName: String = "#"
    @Persisted var readingProgressColumnName: String = "#"
    
    convenience init(libraryId: String, configuration: CalibreDSReaderHelperConfiguration?) {
        self.init()
        self.setup(libraryId: libraryId, configuration: configuration)
    }
    
    func getID() -> String { return CalibreLibrary.PLUGIN_GOODREADS_SYNC }
    
    func setup(libraryId: String, configuration: CalibreDSReaderHelperConfiguration?) {
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

    func update(from other: CalibreLibraryGoodreadsSync) {
        self._isEnabled = other._isEnabled
        self._isDefault = other._isDefault
        self._isOverride = other._isOverride
        self.profileName = other.profileName
        self.tagsColumnName = other.tagsColumnName
        self.ratingColumnName = other.ratingColumnName
        self.dateReadColumnName = other.dateReadColumnName
        self.reviewColumnName = other.reviewColumnName
        self.readingProgressColumnName = other.readingProgressColumnName
    }
}

class CalibreLibraryCountPages: EmbeddedObject, ObjectKeyIdentifiable, CalibreLibraryPluginColumnInfo {
    @Persisted var _isEnabled = false
    @Persisted var _isDefault = false
    @Persisted var _isOverride = false

    @Persisted var pageCountCN: String = "#"
    @Persisted var wordCountCN: String = "#"
    @Persisted var fleschReadingEaseCN: String = "#"
    @Persisted var fleschKincaidGradeCN: String = "#"
    @Persisted var gunningFogIndexCN: String = "#"
    
    convenience init(libraryId: String, configuration: CalibreDSReaderHelperConfiguration?) {
        self.init()
        self.setup(libraryId: libraryId, configuration: configuration)
    }
    
    func getID() -> String { return CalibreLibrary.PLUGIN_COUNT_PAGES }

    func setup(libraryId: String, configuration: CalibreDSReaderHelperConfiguration?) {
        guard let libraryName = ModelData.shared?.calibreLibraries[libraryId]?.name,
              let library_config = configuration?.count_pages_prefs?.library_config?[libraryName] else { return }
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

    func update(from other: CalibreLibraryCountPages) {
        self._isEnabled = other._isEnabled
        self._isDefault = other._isDefault
        self._isOverride = other._isOverride
        self.pageCountCN = other.pageCountCN
        self.wordCountCN = other.wordCountCN
        self.fleschReadingEaseCN = other.fleschReadingEaseCN
        self.fleschKincaidGradeCN = other.fleschKincaidGradeCN
        self.gunningFogIndexCN = other.gunningFogIndexCN
    }
}

class CalibreLibraryReadingPosition: EmbeddedObject, ObjectKeyIdentifiable, CalibreLibraryPluginColumnInfo {
    @Persisted var _isEnabled = false
    @Persisted var _isDefault = false
    @Persisted var _isOverride = false

    @Persisted var readingPositionCN: String = "#"
    
    convenience init(libraryId: String, configuration: CalibreDSReaderHelperConfiguration?) {
        self.init()
        self.setup(libraryId: libraryId, configuration: configuration)
    }
    
    func getID() -> String { return CalibreLibrary.PLUGIN_READING_POSITION }
    
    func setup(libraryId: String, configuration: CalibreDSReaderHelperConfiguration?) {
        guard let library = ModelData.shared?.calibreLibraries[libraryId] else { return }
        let library_config = configuration?.reading_position_prefs?.library_config[library.name]
        if let column_info = library_config?.readingPositionColumns[library.server.username],
           column_info.exists {
            readingPositionCN = "#" + column_info.label
        } else if library.server.username.isEmpty,
                  let prefix = library_config?.readingPositionOptions.prefix,
                  prefix.isEmpty == false,
                  let column_info = library.customColumnInfos[prefix],
                  column_info.datatype == "comments" {
            readingPositionCN = "#" + column_info.label
        }
        else {
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

    func update(from other: CalibreLibraryReadingPosition) {
        self._isEnabled = other._isEnabled
        self._isDefault = other._isDefault
        self._isOverride = other._isOverride
        self.readingPositionCN = other.readingPositionCN
    }
}

class CalibreLibraryDictionaryViewer: EmbeddedObject, ObjectKeyIdentifiable, CalibreLibraryPluginColumnInfo {
    @Persisted var _isEnabled = false
    @Persisted var _isDefault = false
    @Persisted var _isOverride = false

    @Persisted var readingPositionCN: String = "#"
    
    convenience init(libraryId: String, configuration: CalibreDSReaderHelperConfiguration?) {
        self.init()
        self.setup(libraryId: libraryId, configuration: configuration)
    }
    
    func getID() -> String { return CalibreLibrary.PLUGIN_DICTIONARY_VIEWER }

    func setup(libraryId: String, configuration: CalibreDSReaderHelperConfiguration?) {
        if let prefs = configuration?.dsreader_helper_prefs?.plugin_prefs {
            _isEnabled = prefs.Options.dictViewerEnabled
        } else {
            _isEnabled = false
        }
    }
    
    func hasValidColumn() -> Bool {
        return _isEnabled
    }
    
    func mappedColumnsCount() -> Int {
        return (readingPositionCN.count > 0 && readingPositionCN != "#") ? 1 : 0
    }

    func update(from other: CalibreLibraryDictionaryViewer) {
        self._isEnabled = other._isEnabled
        self._isDefault = other._isDefault
        self._isOverride = other._isOverride
        self.readingPositionCN = other.readingPositionCN
    }
}

class CalibreActivityLogEntry: Object, Identifiable {
    @Persisted(primaryKey: true) var id = UUID().uuidString
    @Persisted var type: String?
    
    @Persisted var startDatetime = Date.distantPast
    @Persisted var finishDatetime: Date?
    
    //book or library, not both
    @Persisted var bookId: Int32 = 0
    @Persisted var libraryId: String?
    
    @Persisted var endpoingURL: String?
    @Persisted var httpMethod: String?
    @Persisted var httpBody: Data?       //if any
    @Persisted var requestHeaders = List<String>()     //key1, value1, key2, value2, ...
    
    @Persisted var errMsg: String?
    
    var startDateByLocale: String? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .medium
        dateFormatter.locale = Locale.autoupdatingCurrent
        return dateFormatter.string(from: startDatetime)
    }
    var startDateByLocaleLong: String? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .long
        dateFormatter.locale = Locale.autoupdatingCurrent
        return dateFormatter.string(from: startDatetime)
    }
    
    var finishDateByLocale: String? {
        guard let finishDatetime = finishDatetime else { return nil }
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .medium
        dateFormatter.locale = Locale.autoupdatingCurrent
        return dateFormatter.string(from: finishDatetime)
    }
    
    var finishDateByLocaleLong: String? {
        guard let finishDatetime = finishDatetime else { return nil }
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .long
        dateFormatter.locale = Locale.autoupdatingCurrent
        return dateFormatter.string(from: finishDatetime)
    }
}

class BookDeviceReadingPositionRealm: Object, ObjectKeyIdentifiable {
    @Persisted(primaryKey: true) var _id: ObjectId
    
    @Persisted var bookId: String = .init()
//    @Persisted var id = ""
    @Persisted var deviceId: String
    
    @Persisted var readerName: String
    @Persisted var maxPage = 0
    @Persisted var lastReadPage = 0
    @Persisted var lastReadChapter = ""
    /// range 0 - 100
    @Persisted var lastChapterProgress = 0.0
    /// range 0 - 100
    @Persisted var lastProgress = 0.0
    @Persisted var furthestReadPage = 0
    @Persisted var furthestReadChapter = ""
    @Persisted var lastPosition: List<Int>
    @Persisted var cfi = "/"
    @Persisted var epoch = 0.0
    
    @Persisted var takePrecedence: Bool = false
    
    //for non-linear book structure
    @Persisted var structuralStyle: Int = .zero
    @Persisted var structuralRootPageNumber: Int = 1
    @Persisted var positionTrackingStyle: Int = .zero
    @Persisted var lastReadBook = ""
    @Persisted var lastBundleProgress: Double = .zero
    
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

extension BookDeviceReadingPosition: Persistable {
    public init(managedObject: BookDeviceReadingPositionRealm) {
        id = managedObject.deviceId
        readerName = managedObject.readerName
        maxPage = managedObject.maxPage
        lastReadPage = managedObject.lastReadPage
        lastReadChapter = managedObject.lastReadChapter
        lastChapterProgress = managedObject.lastChapterProgress
        lastProgress = managedObject.lastProgress
        furthestReadPage = managedObject.furthestReadPage
        furthestReadChapter = managedObject.furthestReadChapter
        lastPosition = managedObject.lastPosition.map{$0}
        cfi = managedObject.cfi
        epoch = managedObject.epoch
        
        structuralStyle = managedObject.structuralStyle
        structuralRootPageNumber = managedObject.structuralRootPageNumber
        positionTrackingStyle = managedObject.positionTrackingStyle
        lastReadBook = managedObject.lastReadBook
        lastBundleProgress = managedObject.lastBundleProgress
    }
    
    public func managedObject() -> BookDeviceReadingPositionRealm {
        let obj = BookDeviceReadingPositionRealm()
        obj.deviceId = id
        obj.readerName = readerName
        obj.maxPage = maxPage
        obj.lastReadPage = lastReadPage
        obj.lastReadChapter = lastReadChapter
        obj.lastChapterProgress = lastChapterProgress
        obj.lastProgress = lastProgress
        obj.furthestReadPage = furthestReadPage
        obj.furthestReadChapter = furthestReadChapter
        obj.lastPosition.append(objectsIn: lastPosition)
        obj.cfi = cfi
        obj.epoch = epoch
        
        obj.structuralStyle = structuralStyle
        obj.structuralRootPageNumber = structuralRootPageNumber
        obj.positionTrackingStyle = positionTrackingStyle
        obj.lastReadBook = lastReadBook
        obj.lastBundleProgress = lastBundleProgress
        
        return obj
    }
    
    public func managedObject(bookId: String) -> BookDeviceReadingPositionRealm {
        let obj = managedObject()
        obj.bookId = bookId
        return obj
    }
}

class BookDeviceReadingPositionHistoryRealm: Object, ObjectKeyIdentifiable {
    @Persisted(primaryKey: true) var _id: ObjectId
    
    @Persisted var bookId: String = ""
    
    @Persisted var startDatetime = Date()
    @Persisted var startPosition: BookDeviceReadingPositionRealm?
    @Persisted var endPosition: BookDeviceReadingPositionRealm?
    
    var startDateByLocale: String? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .medium
        dateFormatter.locale = Locale.autoupdatingCurrent
        return dateFormatter.string(from: startDatetime)
    }
    var startDateByLocaleLong: String? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .long
        dateFormatter.locale = Locale.autoupdatingCurrent
        return dateFormatter.string(from: startDatetime)
    }
    
    override static func primaryKey()-> String? {
        return "_id"
    }
}

extension BookDeviceReadingPositionHistory: Persistable {
    public init(managedObject: BookDeviceReadingPositionHistoryRealm) {
        self.bookId = managedObject.bookId
        self.startDatetime = managedObject.startDatetime
        if let startPosition = managedObject.startPosition {
            self.startPosition = .init(managedObject: startPosition)
        }
        if let endPosition = managedObject.endPosition {
            self.endPosition = .init(managedObject: endPosition)
        }
    }
    
    public func managedObject() -> BookDeviceReadingPositionHistoryRealm {
        let object = BookDeviceReadingPositionHistoryRealm()
        object.bookId = self.bookId
        object.startDatetime = self.startDatetime
        object.startPosition = self.startPosition?.managedObject()
        object.endPosition = self.endPosition?.managedObject()
        return object
    }
}

@available(*, deprecated, message: "Remove CalibreBookLastReadPositionRealm")
class CalibreBookLastReadPositionRealm: Object {
    @objc dynamic var device = ""
    @objc dynamic var cfi = ""
    @objc dynamic var epoch = 0.0
    @objc dynamic var pos_frac = 0.0
    
    override static func primaryKey() -> String? {
        return "device"
    }
}

/*
extension CalibreBookLastReadPositionEntry: Persistable {
    public init(managedObject: CalibreBookLastReadPositionRealm) {
        device = managedObject.device
        cfi = managedObject.cfi
        epoch = managedObject.epoch
        pos_frac = managedObject.pos_frac
    }
    
    public func managedObject() -> CalibreBookLastReadPositionRealm {
        let obj = CalibreBookLastReadPositionRealm()
        obj.device = device
        obj.cfi = cfi
        obj.epoch = epoch
        obj.pos_frac = pos_frac
        
        return obj
    }
}
*/

extension BookDeviceReadingPosition {
    /*
    public init?(managedObject: CalibreBookLastReadPositionRealm) {
        guard let vndFirstRange = managedObject.cfi.range(of: ";vndYabr_") ?? managedObject.cfi.range(of: ";vnd_"),
              let vndEndRange = managedObject.cfi.range(of: "]", range: vndFirstRange.upperBound..<managedObject.cfi.endIndex)
        else { return nil }
        
        
        let vndParameters = managedObject.cfi[vndFirstRange.lowerBound..<vndEndRange.lowerBound]
        
        var parameters = [String: String]()
        vndParameters.split(separator: ";").forEach { p in
            guard let equalIndex = p.firstIndex(of: "=") else { return }
            parameters[String(p[p.startIndex..<equalIndex])] = String(p[(p.index(after: equalIndex))..<p.endIndex])
        }
        
//        print("\(#function) cfi=\(managedObject.cfi) vndParameters=\(vndParameters) parameters=\(parameters)")
        
        guard let readerName = parameters["vndYabr_readerName"] ?? parameters["vnd_readerName"] else { return nil }
        
        self.id = managedObject.device
        self.readerName = readerName
        
        if let vndYabr_maxPage = parameters["vndYabr_maxPage"] ?? parameters["vnd_maxPage"], let maxPage = Int(vndYabr_maxPage) {
            self.maxPage = maxPage
        }
        if let vndYabr_lastReadPage = parameters["vndYabr_lastReadPage"] ?? parameters["vnd_lastReadPage"], let lastReadPage = Int(vndYabr_lastReadPage) {
            self.lastReadPage = lastReadPage
        }
        if let vndYabr_lastReadChapter = parameters["vndYabr_lastReadChapter"] ?? parameters["vnd_lastReadChapter"] {
            self.lastReadChapter = vndYabr_lastReadChapter
        }
        if let vndYabr_lastChapterProgress = parameters["vndYabr_lastChapterProgress"] ?? parameters["vnd_lastChapterProgress"], let lastChapterProgress = Double(vndYabr_lastChapterProgress) {
            self.lastChapterProgress = lastChapterProgress
        }
        if let vndYabr_lastProgress = parameters["vndYabr_lastProgress"] ?? parameters["vnd_lastProgress"], let lastProgress = Double(vndYabr_lastProgress) {
            self.lastProgress = lastProgress
        }
        if let vndYabr_furthestReadPage = parameters["vndYabr_furthestReadPage"] ?? parameters["vnd_furthestReadPage"], let furthestReadPage = Int(vndYabr_furthestReadPage) {
            self.furthestReadPage = furthestReadPage
        }
        if let vndYabr_furthestReadChapter = parameters["vndYabr_furthestReadChapter"] ?? parameters["vnd_furthestReadChapter"] {
            self.furthestReadChapter = vndYabr_furthestReadChapter
        }
        if let vndYabr_epoch = parameters["vndYabr_epoch"] ?? parameters["vnd_epoch"], let epoch = Double(vndYabr_epoch), epoch > 0.0 {
            self.epoch = epoch
        } else if managedObject.epoch > 0.0 {
            self.epoch = managedObject.epoch
        } else {
            self.epoch = Date().timeIntervalSince1970
        }
        if let vndYabr_lastPosition = parameters["vndYabr_lastPosition"] ?? parameters["vnd_lastPosition"] {
            let positions = vndYabr_lastPosition.split(separator: ".").compactMap{ Int($0) }
            if positions.count == 3 {
                self.lastPosition = positions
            }
        }
        if let vndYabr_structuralStyle = parameters["vndYabr_structuralStyle"],
           let structuralStyle = Int(vndYabr_structuralStyle) {
            self.structuralStyle = structuralStyle
        }
        if let vndYabr_structuralRootPageNumber = parameters["vndYabr_structuralRootPageNumber"],
           let structuralRootPageNumber = Int(vndYabr_structuralRootPageNumber) {
            self.structuralRootPageNumber = structuralRootPageNumber
        }
        if let vndYabr_positionTrackingStyle = parameters["vndYabr_positionTrackingStyle"],
           let positionTrackingStyle = Int(vndYabr_positionTrackingStyle) {
            self.positionTrackingStyle = positionTrackingStyle
        }
        if let vndYabr_lastReadBook = parameters["vndYabr_lastReadBook"] {
            self.lastReadBook = vndYabr_lastReadBook
        }
        if let vndYabr_lastBundleProgress = parameters["vndYabr_lastBundleProgress"],
            let lastBundleProgress = Double(vndYabr_lastBundleProgress) {
            self.lastBundleProgress = lastBundleProgress
        }
        
        self.cfi = String(managedObject.cfi[managedObject.cfi.startIndex..<vndFirstRange.lowerBound] + managedObject.cfi[vndEndRange.lowerBound..<managedObject.cfi.endIndex]).replacingOccurrences(of: "[]", with: "")
        
    }
     */
    
    public init?(entry: CalibreBookLastReadPositionEntry) {
        guard let vndFirstRange = entry.cfi.range(of: ";vndYabr_") ?? entry.cfi.range(of: ";vnd_"),
              let vndEndRange = entry.cfi.range(of: "]", range: vndFirstRange.upperBound..<entry.cfi.endIndex)
        else { return nil }
        
        
        let vndParameters = entry.cfi[vndFirstRange.lowerBound..<vndEndRange.lowerBound]
        
        var parameters = [String: String]()
        vndParameters.split(separator: ";").forEach { p in
            guard let equalIndex = p.firstIndex(of: "=") else { return }
            parameters[String(p[p.startIndex..<equalIndex])] = String(p[(p.index(after: equalIndex))..<p.endIndex])
        }
        
//        print("\(#function) cfi=\(managedObject.cfi) vndParameters=\(vndParameters) parameters=\(parameters)")
        
        guard let readerName = parameters["vndYabr_readerName"] ?? parameters["vnd_readerName"] else { return nil }
        
        self.id = entry.device
        self.readerName = readerName
        
        if let vndYabr_maxPage = parameters["vndYabr_maxPage"] ?? parameters["vnd_maxPage"], let maxPage = Int(vndYabr_maxPage) {
            self.maxPage = maxPage
        }
        if let vndYabr_lastReadPage = parameters["vndYabr_lastReadPage"] ?? parameters["vnd_lastReadPage"], let lastReadPage = Int(vndYabr_lastReadPage) {
            self.lastReadPage = lastReadPage
        }
        if let vndYabr_lastReadChapter = parameters["vndYabr_lastReadChapter"] ?? parameters["vnd_lastReadChapter"] {
            self.lastReadChapter = vndYabr_lastReadChapter
        }
        if let vndYabr_lastChapterProgress = parameters["vndYabr_lastChapterProgress"] ?? parameters["vnd_lastChapterProgress"], let lastChapterProgress = Double(vndYabr_lastChapterProgress) {
            self.lastChapterProgress = lastChapterProgress
        }
        if let vndYabr_lastProgress = parameters["vndYabr_lastProgress"] ?? parameters["vnd_lastProgress"], let lastProgress = Double(vndYabr_lastProgress) {
            self.lastProgress = lastProgress
        }
        if let vndYabr_furthestReadPage = parameters["vndYabr_furthestReadPage"] ?? parameters["vnd_furthestReadPage"], let furthestReadPage = Int(vndYabr_furthestReadPage) {
            self.furthestReadPage = furthestReadPage
        }
        if let vndYabr_furthestReadChapter = parameters["vndYabr_furthestReadChapter"] ?? parameters["vnd_furthestReadChapter"] {
            self.furthestReadChapter = vndYabr_furthestReadChapter
        }
        if let vndYabr_epoch = parameters["vndYabr_epoch"] ?? parameters["vnd_epoch"], let epoch = Double(vndYabr_epoch), epoch > 0.0 {
            self.epoch = epoch
        } else if entry.epoch > 0.0 {
            self.epoch = entry.epoch
        } else {
            self.epoch = Date().timeIntervalSince1970
        }
        if let vndYabr_lastPosition = parameters["vndYabr_lastPosition"] ?? parameters["vnd_lastPosition"] {
            let positions = vndYabr_lastPosition.split(separator: ".").compactMap{ Int($0) }
            if positions.count == 3 {
                self.lastPosition = positions
            }
        }
        if let vndYabr_structuralStyle = parameters["vndYabr_structuralStyle"],
           let structuralStyle = Int(vndYabr_structuralStyle) {
            self.structuralStyle = structuralStyle
        }
        if let vndYabr_structuralRootPageNumber = parameters["vndYabr_structuralRootPageNumber"],
           let structuralRootPageNumber = Int(vndYabr_structuralRootPageNumber) {
            self.structuralRootPageNumber = structuralRootPageNumber
        }
        if let vndYabr_positionTrackingStyle = parameters["vndYabr_positionTrackingStyle"],
           let positionTrackingStyle = Int(vndYabr_positionTrackingStyle) {
            self.positionTrackingStyle = positionTrackingStyle
        }
        if let vndYabr_lastReadBook = parameters["vndYabr_lastReadBook"] {
            self.lastReadBook = vndYabr_lastReadBook
        }
        if let vndYabr_lastBundleProgress = parameters["vndYabr_lastBundleProgress"],
            let lastBundleProgress = Double(vndYabr_lastBundleProgress) {
            self.lastBundleProgress = lastBundleProgress
        }
        
        self.cfi = String(entry.cfi[entry.cfi.startIndex..<vndFirstRange.lowerBound] + entry.cfi[vndEndRange.lowerBound..<entry.cfi.endIndex]).replacingOccurrences(of: "[]", with: "")
        
    }
    
    func encodeEPUBCFI() -> String {
        var parameters = [String: String]()
        parameters["vndYabr_readerName"] = readerName
        parameters["vndYabr_maxPage"] = maxPage.description
        parameters["vndYabr_lastReadPage"] = lastReadPage.description
        parameters["vndYabr_lastReadChapter"] = lastReadChapter
        parameters["vndYabr_lastChapterProgress"] = lastChapterProgress.description
        parameters["vndYabr_lastProgress"] = lastProgress.description
        parameters["vndYabr_furthestReadPage"] = furthestReadPage.description
        parameters["vndYabr_furthestReadChapter"] = furthestReadChapter
        parameters["vndYabr_lastPosition"] = lastPosition.map { $0.description }.joined(separator: ".")
        if epoch > 0.0 {
            parameters["vndYabr_epoch"] = epoch.description
        } else {
            parameters["vndYabr_epoch"] = Date().timeIntervalSince1970.description
        }
        parameters["vndYabr_structuralStyle"] = structuralStyle.description
        parameters["vndYabr_structuralRootPageNumber"] = structuralRootPageNumber .description
        parameters["vndYabr_positionTrackingStyle"] = positionTrackingStyle.description
        parameters["vndYabr_lastReadBook"] = lastReadBook
        parameters["vndYabr_lastBundleProgress"] = lastBundleProgress.description
        
        
        let vndParameters = parameters.map {
            "\($0.key)=\($0.value.replacingOccurrences(of: ",|;|=|\\[|\\]|\\s", with: ".", options: .regularExpression))"
        }.sorted().joined(separator: ";")
        
        var cfi = cfi
        if cfi.isEmpty || cfi == "/" {
            let typeKey = (ReaderType(rawValue: readerName) ?? .UNSUPPORTED).format.rawValue.lowercased()
            cfi = "\(typeKey)cfi(/\(lastReadPage*2))"
        }
        
        var insertIndex = cfi.endIndex
        var insertFragment = "[;\(vndParameters)]"
        if cfi.hasSuffix("])") {
            insertIndex = cfi.index(cfi.endIndex, offsetBy: -2, limitedBy: cfi.startIndex) ?? cfi.startIndex
            insertFragment = ";\(vndParameters)"
        } else if cfi.hasSuffix(")") {
            insertIndex = cfi.index(cfi.endIndex, offsetBy: -1, limitedBy: cfi.startIndex) ?? cfi.startIndex
        } else {
            //insert at end
        }
        cfi.insert(contentsOf: insertFragment, at: insertIndex)
        
//        print("\(#function) cfi=\(cfi)")
        
        return cfi
    }
    
    func toEntry() -> CalibreBookLastReadPositionEntry {
        return .init(
            device: id,
            cfi: encodeEPUBCFI(),
            epoch: epoch,
            pos_frac: lastProgress / 100.0
        )
    }
}

class BookHighlightRealm: Object {
    @objc open dynamic var removed: Bool = false
    
    @objc open dynamic var bookId: String = ""
    @objc open dynamic var highlightId: String = ""
    @objc open dynamic var readerName: String = ""
    
    @objc open dynamic var page: Int = 0
    @objc open dynamic var startOffset: Int = -1
    @objc open dynamic var endOffset: Int = -1
    
    @objc open dynamic var date: Date = .init()
    @objc open dynamic var type: Int = 0
    @objc open dynamic var note: String?
    
    open dynamic var tocFamilyTitles = List<String>()
    @objc open dynamic var content: String = ""
    @objc open dynamic var contentPost: String = ""
    @objc open dynamic var contentPre: String = ""
    
    // MARK: EPUB Specific
    @objc open dynamic var cfiStart: String?
    @objc open dynamic var cfiEnd: String?
    @objc open dynamic var spineName: String?
    
    // MARK: PDF Specific
    @objc open dynamic var ranges: String?
    
    override static func primaryKey()-> String? {
        return "highlightId"
    }
}

extension BookHighlight: Persistable {
    init(managedObject: BookHighlightRealm) {
        removed = managedObject.removed
        
        bookId = managedObject.bookId
        highlightId = managedObject.highlightId
        readerName = managedObject.readerName
        
        page = managedObject.page
        startOffset = managedObject.startOffset
        endOffset = managedObject.endOffset
        ranges = managedObject.ranges
        
        date = managedObject.date
        type = managedObject.type
        note = managedObject.note
        
        tocFamilyTitles = managedObject.tocFamilyTitles.map { $0 }
        content = managedObject.content
        contentPost = managedObject.contentPost
        contentPre = managedObject.contentPre
        
        cfiStart = managedObject.cfiStart
        cfiEnd = managedObject.cfiEnd
        spineName = managedObject.spineName
    }
    
    func managedObject() -> BookHighlightRealm {
        let managedObject = BookHighlightRealm()
        managedObject.removed = removed
        
        managedObject.bookId = bookId
        managedObject.highlightId = highlightId
        managedObject.readerName = readerName
        
        managedObject.page = page
        managedObject.startOffset = startOffset
        managedObject.endOffset = endOffset
        managedObject.ranges = ranges
        
        managedObject.date = date
        managedObject.type = type
        managedObject.note = note
        
        managedObject.tocFamilyTitles.append(objectsIn: tocFamilyTitles)
        managedObject.content = content
        managedObject.contentPost = contentPost
        managedObject.contentPre = contentPre
        
        managedObject.cfiStart = cfiStart
        managedObject.cfiEnd = cfiEnd
        managedObject.spineName = spineName
        
        return managedObject
    }
}

extension FolioReaderHighlightRealm {
    func toBookHighlightRealm(readerName: String) -> BookHighlightRealm? {
        guard let bookId = bookId, let highlightId = highlightId else { return nil }
        
        let managedObject = BookHighlightRealm()
        managedObject.bookId = bookId
        managedObject.highlightId = highlightId
        managedObject.readerName = readerName
        
        managedObject.page = page
        managedObject.startOffset = startOffset
        managedObject.endOffset = endOffset
        
        managedObject.date = date
        managedObject.type = type
        managedObject.note = noteForHighlight
        
        managedObject.tocFamilyTitles.append(objectsIn: tocFamilyTitles)
        managedObject.content = content ?? ""
        managedObject.contentPost = contentPost ?? ""
        managedObject.contentPre = contentPre ?? ""
        
        managedObject.cfiStart = cfiStart
        managedObject.cfiEnd = cfiEnd
        managedObject.spineName = spineName
        
        return managedObject
    }
}

class CalibreServerDSReaderHelper: EmbeddedObject, ObjectKeyIdentifiable {
    @Persisted var port: Int = 0
    @Persisted var configurationData: Data?
    
    convenience init(port: Int) {
        self.init()
        self.port = port
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

    func update(from other: CalibreServerDSReaderHelper) {
        self.port = other.port
        self.configurationData = other.configurationData
    }
}

class CalibreLibraryDSReaderHelper: EmbeddedObject, ObjectKeyIdentifiable, CalibreLibraryPluginColumnInfo {
    @Persisted var _isEnabled = false
    @Persisted var _isDefault = false
    @Persisted var _isOverride = false

    @Persisted var port: Int = 0
    
    @Persisted var autoUpdateGoodreadsProgress = false
    @Persisted var autoUpdateGoodreadsBookShelf = false
    
    convenience init(libraryId: String, configuration: CalibreDSReaderHelperConfiguration?) {
        self.init()
        self.setup(libraryId: libraryId, configuration: configuration)
    }
    
    func getID() -> String { return CalibreLibrary.PLUGIN_DSREADER_HELPER }

    func setup(libraryId: String, configuration: CalibreDSReaderHelperConfiguration?) {
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

    func update(from other: CalibreLibraryDSReaderHelper) {
        self._isEnabled = other._isEnabled
        self._isDefault = other._isDefault
        self._isOverride = other._isOverride
        self.port = other.port
        self.autoUpdateGoodreadsProgress = other.autoUpdateGoodreadsProgress
        self.autoUpdateGoodreadsBookShelf = other.autoUpdateGoodreadsBookShelf
    }
}

class BookBookmarkRealm: Object, ObjectKeyIdentifiable {
    @objc dynamic var _id: ObjectId = .generate()
    @objc dynamic var bookId: String = .init()
    @objc dynamic var page: Int = .zero
    
    @objc dynamic var pos_type: String = .init()
    @objc dynamic var pos: String = .init()
    
    @objc dynamic var title: String = .init()
    @objc dynamic var date: Date = .init()
    
    @objc dynamic var removed: Bool = false
    
    override static func primaryKey() -> String? {
        return "_id"
    }
}

extension BookBookmark: Persistable {
    public init(managedObject: BookBookmarkRealm) {
        self.bookId = managedObject.bookId
        self.page = managedObject.page
        
        self.pos_type = managedObject.pos_type
        self.pos = managedObject.pos
        
        self.title = managedObject.title
        self.date = managedObject.date
        
        self.removed = managedObject.removed
    }
    
    public func managedObject() -> BookBookmarkRealm {
        let obj = BookBookmarkRealm()
        obj.bookId = self.bookId
        obj.page = self.page
        
        obj.pos_type = self.pos_type
        obj.pos = self.pos
        
        obj.title = self.title
        obj.date = self.date
        
        obj.removed = self.removed
        
        return obj
    }
}


//MARK: PDF
@available(*, deprecated, renamed: "YabrPDFOptions")
class PDFOptionsRealm: Object {
    @objc dynamic var id: Int32 = 0
    @objc dynamic var libraryName = ""
    @objc dynamic var themeMode = PDFThemeMode.serpia.rawValue
    @objc dynamic var selectedAutoScaler = PDFAutoScaler.Width.rawValue
    @objc dynamic var pageMode = PDFLayoutMode.Page.rawValue
    @objc dynamic var readingDirection = PDFReadDirection.LtR_TtB.rawValue
    @objc dynamic var scrollDirection = PDFScrollDirection.Vertical.rawValue
    @objc dynamic var hMarginAutoScaler = 5.0
    @objc dynamic var vMarginAutoScaler = 5.0
    @objc dynamic var hMarginDetectStrength = 2.0
    @objc dynamic var vMarginDetectStrength = 2.0
    @objc dynamic var marginOffset = 0.0
    @objc dynamic var lastScale = 1.0
    @objc dynamic var rememberInPagePosition = true
    
    override static func primaryKey() -> String? {
        return "id"
    }
}


extension PDFThemeMode: PersistableEnum {}
extension PDFAutoScaler: PersistableEnum {}
extension PDFLayoutMode: PersistableEnum {}
extension PDFReadDirection: PersistableEnum {}
extension PDFScrollDirection: PersistableEnum {}

class PDFOptions: Object, ObjectKeyIdentifiable {
    @Persisted(primaryKey: true) var _id: ObjectId
    
    @Persisted var bookId: Int32 = 0
    @Persisted var libraryName: String = ""
    
    @Persisted var themeMode = PDFThemeMode.serpia
    @Persisted var selectedAutoScaler = PDFAutoScaler.Width
    @Persisted var pageMode = PDFLayoutMode.Page
    @Persisted var readingDirection = PDFReadDirection.LtR_TtB
    @Persisted var scrollDirection = PDFScrollDirection.Vertical
    
    @Persisted var hMarginAutoScaler = 5.0
    @Persisted var vMarginAutoScaler = 5.0
    @Persisted var hMarginDetectStrength = 2.0
    @Persisted var vMarginDetectStrength = 2.0
    @Persisted var marginOffset = 0.0
    @Persisted var lastScale = 1.0
    @Persisted var rememberInPagePosition = true
    
    var isDark: Bool {
        themeMode == .dark
    }

    func isDark<T>(_ f: T, _ l: T) -> T{
        isDark ? f : l
    }

    var fillColor: CGColor {
        switch (themeMode) {
        case .none:
            return .init(gray: 0.0, alpha: 0.0)
        case .serpia:   //#FBF0D9
            return CGColor(red: 0.98046875, green: 0.9375, blue: 0.84765625, alpha: 1.0)
        case .forest:   //#BAD5C1
            return CGColor(
                red: CGFloat(Int("BA", radix: 16) ?? 255) / 255.0,
                green: CGFloat(Int("D5", radix: 16) ?? 255) / 255.0,
                blue: CGFloat(Int("C1", radix: 16) ?? 255) / 255.0,
                alpha: 1.0)
        case .dark:
            return .init(gray: 0.0, alpha: 1.0)
        }
    }
    
    public func update(other: PDFOptions) {
        self.themeMode = other.themeMode
        self.selectedAutoScaler = other.selectedAutoScaler
        self.pageMode = other.pageMode
        self.readingDirection = other.readingDirection
        self.scrollDirection = other.scrollDirection
        self.hMarginAutoScaler = other.hMarginAutoScaler
        self.vMarginAutoScaler = other.vMarginAutoScaler
        self.hMarginDetectStrength = other.hMarginDetectStrength
        self.vMarginDetectStrength = other.vMarginDetectStrength
        self.marginOffset = other.marginOffset
        self.lastScale = other.lastScale
        self.rememberInPagePosition = other.rememberInPagePosition
    }
}

class ReadiumPreferenceRealm: Object, ObjectKeyIdentifiable {
    @Persisted(primaryKey: true) var id: String = ""
    
    @Persisted var themeMode: Int = 0
    @Persisted var fontSizePercentage: Double = 100.0
    @Persisted var fontFamily: String = "Original"
    @Persisted var lineHeight: Double = 1.2
    @Persisted var pageMargins: Double = 1.0
    @Persisted var publisherStyles: Bool = true
    @Persisted var scroll: Bool = false
    @Persisted var textAlign: Int = 0
    
    @Persisted var columnCount: Int = 0
    @Persisted var fontWeight: Double = 1.0
    @Persisted var letterSpacing: Double = 0.0
    @Persisted var wordSpacing: Double = 0.0
    @Persisted var hyphens: Bool = false
    @Persisted var imageFilter: Int = 0
    @Persisted var textNormalization: Bool = false
    @Persisted var typeScale: Double = 1.2
    @Persisted var paragraphIndent: Double = 0.0
    @Persisted var paragraphSpacing: Double = 0.0
    
    @Persisted var volumeKeyPaging: Bool = false
    @Persisted var verticalMargin: Double = 0.0
    @Persisted var readingProgression: Int = 0 // 0: LTR, 1: RTL
    
    @Persisted var fit: Int = 0 // 0: auto, 1: page, 2: width
    @Persisted var ligatures: Bool = false
    @Persisted var offsetFirstPage: Bool?
    @Persisted var spread: Int = 0 // 0: auto, 1: never, 2: always
    @Persisted var verticalText: Bool = false

    @Persisted var pageSpacing: Double = 0.0
    @Persisted var scrollAxis: Int = 0 // 0: vertical, 1: horizontal
    @Persisted var visibleScrollbar: Bool = true
}

import ReadiumNavigator
import ReadiumShared

extension ReadiumPreferenceRealm {
    
    var themeColor: UIColor {
        switch themeMode {
        case 1: // Sepia
            return UIColor(red: 0.98, green: 0.96, blue: 0.91, alpha: 1.0) // #FAF4E8
        case 2: // Dark
            return .black
        default: // Light
            return .white
        }
    }

    func toEPUBPreferences() -> EPUBPreferences {
        EPUBPreferences(
            columnCount: self.columnCount == 0 ? .auto : (self.columnCount == 1 ? .one : .two),
            fit: {
                switch self.fit {
                case 1: return .page
                case 2: return .width
                default: return .auto
                }
            }(),
            fontFamily: self.fontFamily == "Original" ? nil : ReadiumNavigator.FontFamily(rawValue: self.fontFamily),
            fontSize: self.fontSizePercentage / 100.0,
            fontWeight: self.fontWeight,
            hyphens: self.hyphens,
            imageFilter: self.imageFilter == 0 ? nil : (self.imageFilter == 1 ? .darken : .invert),
            letterSpacing: self.letterSpacing,
            ligatures: self.ligatures,
            lineHeight: self.lineHeight,
            offsetFirstPage: self.offsetFirstPage,
            pageMargins: self.pageMargins,
            paragraphIndent: self.paragraphIndent,
            paragraphSpacing: self.paragraphSpacing,
            publisherStyles: self.publisherStyles,
            readingProgression: self.readingProgression == 0 ? .ltr : .rtl,
            scroll: self.scroll,
            spread: {
                switch self.spread {
                case 1: return .never
                case 2: return .always
                default: return .auto
                }
            }(),
            textAlign: {
                switch self.textAlign {
                case 1: return .start
                case 2: return .left
                case 3: return .right
                case 4: return .justify
                default: return nil
                }
            }(),
            textNormalization: self.textNormalization,
            theme: {
                switch self.themeMode {
                case 1: return .sepia
                case 2: return .dark
                default: return .light
                }
            }(),
            typeScale: self.typeScale,
            verticalText: self.verticalText,
            wordSpacing: self.wordSpacing
        )
    }
    
    func toPDFPreferences() -> PDFPreferences {
        PDFPreferences(
            fit: {
                switch self.fit {
                case 1: return .page
                case 2: return .width
                default: return .auto
                }
            }(),
            offsetFirstPage: self.offsetFirstPage,
            pageSpacing: self.pageSpacing,
            readingProgression: self.readingProgression == 0 ? .ltr : .rtl,
            scroll: self.scroll,
            scrollAxis: self.scrollAxis == 1 ? .horizontal : .vertical,
            spread: {
                switch self.spread {
                case 1: return .never
                case 2: return .always
                default: return .auto
                }
            }(),
            visibleScrollbar: self.visibleScrollbar
        )
    }
    
    func update(from settings: EPUBSettings) {
        switch settings.theme {
        case .light: self.themeMode = 0
        case .sepia: self.themeMode = 1
        case .dark: self.themeMode = 2
        }
        
        self.fontSizePercentage = settings.fontSize * 100.0
        self.fontFamily = settings.fontFamily?.rawValue ?? "Original"
        self.lineHeight = settings.lineHeight ?? 1.2
        self.pageMargins = settings.pageMargins
        self.publisherStyles = settings.publisherStyles
        self.scroll = settings.scroll
        self.readingProgression = settings.readingProgression == .rtl ? 1 : 0
        
        switch settings.textAlign {
        case .start: self.textAlign = 1
        case .left: self.textAlign = 2
        case .right: self.textAlign = 3
        case .justify: self.textAlign = 4
        default: self.textAlign = 0
        }
        
        switch settings.columnCount {
        case .auto: self.columnCount = 0
        case .one: self.columnCount = 1
        case .two: self.columnCount = 2
        }
        
        self.fontWeight = settings.fontWeight ?? 1.0
        self.letterSpacing = settings.letterSpacing ?? 0.0
        self.wordSpacing = settings.wordSpacing ?? 0.0
        self.hyphens = settings.hyphens ?? false
        
        switch settings.imageFilter {
        case .darken: self.imageFilter = 1
        case .invert: self.imageFilter = 2
        default: self.imageFilter = 0
        }
        
        self.textNormalization = settings.textNormalization
        self.typeScale = settings.typeScale ?? 1.2
        self.paragraphIndent = settings.paragraphIndent ?? 0.0
        self.paragraphSpacing = settings.paragraphSpacing ?? 0.0
        self.ligatures = settings.ligatures ?? false
        self.offsetFirstPage = settings.offsetFirstPage ?? false
        self.verticalText = settings.verticalText
        
        switch settings.spread {
        case .never: self.spread = 1
        case .always: self.spread = 2
        default: self.spread = 0
        }
        
        switch settings.fit {
        case .page: self.fit = 1
        case .width: self.fit = 2
        default: self.fit = 0
        }
    }
    
    func update(from settings: PDFSettings) {
        self.scroll = settings.scroll
        self.readingProgression = settings.readingProgression == .rtl ? 1 : 0
        self.offsetFirstPage = settings.offsetFirstPage
        self.pageSpacing = settings.pageSpacing
        self.scrollAxis = settings.scrollAxis == .horizontal ? 1 : 0
        self.visibleScrollbar = settings.visibleScrollbar
        
        switch settings.fit {
        case .page: self.fit = 1
        case .width: self.fit = 2
        default: self.fit = 0
        }
        
        switch settings.spread {
        case .never: self.spread = 1
        case .always: self.spread = 2
        default: self.spread = 0
        }
    }
    
    func update(from preferences: EPUBPreferences) {
        switch preferences.theme {
        case .light?: self.themeMode = 0
        case .sepia?: self.themeMode = 1
        case .dark?: self.themeMode = 2
        case nil: self.themeMode = 0
        }
        
        self.fontSizePercentage = (preferences.fontSize ?? 1.0) * 100.0
        self.fontFamily = preferences.fontFamily?.rawValue ?? "Original"
        self.lineHeight = preferences.lineHeight ?? 1.2
        self.pageMargins = preferences.pageMargins ?? 1.0
        self.publisherStyles = preferences.publisherStyles ?? true
        self.scroll = preferences.scroll ?? false
        
        if let readingProgression = preferences.readingProgression {
            self.readingProgression = readingProgression == .rtl ? 1 : 0
        } else {
            self.readingProgression = 0
        }
        
        switch preferences.textAlign {
        case .start?: self.textAlign = 1
        case .left?: self.textAlign = 2
        case .right?: self.textAlign = 3
        case .justify?: self.textAlign = 4
        default: self.textAlign = 0
        }
        
        switch preferences.columnCount {
        case .one?: self.columnCount = 1
        case .two?: self.columnCount = 2
        default: self.columnCount = 0
        }
        
        self.fontWeight = preferences.fontWeight ?? 1.0
        self.letterSpacing = preferences.letterSpacing ?? 0.0
        self.wordSpacing = preferences.wordSpacing ?? 0.0
        self.hyphens = preferences.hyphens ?? false
        
        switch preferences.imageFilter {
        case .darken?: self.imageFilter = 1
        case .invert?: self.imageFilter = 2
        default: self.imageFilter = 0
        }
        
        self.textNormalization = preferences.textNormalization ?? false
        self.typeScale = preferences.typeScale ?? 1.2
        self.paragraphIndent = preferences.paragraphIndent ?? 0.0
        self.paragraphSpacing = preferences.paragraphSpacing ?? 0.0
        self.ligatures = preferences.ligatures ?? false
        self.offsetFirstPage = preferences.offsetFirstPage
        self.verticalText = preferences.verticalText ?? false
        
        switch preferences.spread {
        case .never?: self.spread = 1
        case .always?: self.spread = 2
        default: self.spread = 0
        }
        
        switch preferences.fit {
        case .page?: self.fit = 1
        case .width?: self.fit = 2
        default: self.fit = 0
        }
    }
    
    func update(from preferences: PDFPreferences) {
        self.scroll = preferences.scroll ?? false
        
        if let readingProgression = preferences.readingProgression {
            self.readingProgression = readingProgression == .rtl ? 1 : 0
        } else {
            self.readingProgression = 0
        }
        
        self.offsetFirstPage = preferences.offsetFirstPage
        self.pageSpacing = preferences.pageSpacing ?? 0.0
        self.scrollAxis = preferences.scrollAxis == .horizontal ? 1 : 0
        self.visibleScrollbar = preferences.visibleScrollbar ?? true
        
        switch preferences.fit {
        case .page?: self.fit = 1
        case .width?: self.fit = 2
        default: self.fit = 0
        }
        
        switch preferences.spread {
        case .never?: self.spread = 1
        case .always?: self.spread = 2
        default: self.spread = 0
        }
    }
}


