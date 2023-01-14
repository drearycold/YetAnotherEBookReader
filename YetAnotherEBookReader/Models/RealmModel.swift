//
//  RealmModel.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/7/22.
//

import Foundation
import RealmSwift

public protocol Persistable {
    associatedtype ManagedObject: RealmSwift.Object
    init(managedObject: ManagedObject)
    func managedObject() -> ManagedObject
}

class CalibreServerRealm: Object {
    @objc dynamic var primaryKey: String?   //uuidString
    
    @objc dynamic var name: String?
    
    @objc dynamic var baseUrl: String? {
        didSet {
            updatePrimaryKey()
        }
    }
    
    @objc dynamic var hasPublicUrl = false
    
    @objc dynamic var publicUrl: String?
    
    @objc dynamic var hasAuth = false
    
    @objc dynamic var username: String? {
        didSet {
            updatePrimaryKey()
        }
    }
    @objc dynamic var password: String?
    
    @objc dynamic var defaultLibrary: String?
    
    @objc dynamic var removed = false
    
    override static func primaryKey() -> String? {
        return "primaryKey"
    }
    
    func updatePrimaryKey() {
//        primaryKey = "\(username ?? "-")@\(baseUrl ?? "-")"
    }
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

class CalibreLibraryRealm: Object {
    @objc dynamic var primaryKey: String?
    
    @objc dynamic var key: String? {
        didSet {
            updatePrimaryKey()
        }
    }
    @objc dynamic var name: String? {
        didSet {
            updatePrimaryKey()
        }
    }
    
    @objc dynamic var serverUUID: String? {
        didSet {
            updatePrimaryKey()
        }
    }
    
//    @objc dynamic var serverUrl: String? {
//        didSet {
//            updatePrimaryKey()
//        }
//    }
//    @objc dynamic var serverUsername: String? {
//        didSet {
//            updatePrimaryKey()
//        }
//    }
    
    override static func primaryKey() -> String? {
        return "primaryKey"
    }
    
    func updatePrimaryKey() {
//        primaryKey = "\(serverUsername ?? "-")@\(serverUrl ?? "-") - \(name ?? "-")"
        primaryKey = CalibreLibraryRealm.PrimaryKey(serverUUID: serverUUID ?? "-", libraryName: name ?? "-")
    }
    
    static func PrimaryKey(serverUUID: String, libraryName: String) -> String {
        return [libraryName, "@", serverUUID].joined()
    }
    var customColumns = List<CalibreCustomColumnRealm>()
    @objc dynamic var pluginDSReaderHelper:     CalibreLibraryDSReaderHelperRealm?
    @objc dynamic var pluginReadingPosition:    CalibreLibraryReadingPositionRealm?
    @objc dynamic var pluginDictionaryViewer:   CalibreLibraryDictionaryViewerRealm?

    @objc dynamic var pluginGoodreadsSync:      CalibreLibraryGoodreadsSyncRealm?
    @objc dynamic var pluginCountPages:         CalibreLibraryCountPageRealm?
    
    @objc dynamic var autoUpdate = true
    @objc dynamic var discoverable = true
    @objc dynamic var hidden = false
    @objc dynamic var lastModified = Date(timeIntervalSince1970: 0)
}

class CalibreBookRealm: Object {
    @objc dynamic var primaryKey: String?
    
//    @objc dynamic var serverUrl: String? {
//        didSet {
//            updatePrimaryKey()
//        }
//    }
//    @objc dynamic var serverUsername: String? {
//        didSet {
//            updatePrimaryKey()
//        }
//    }
    
    @objc dynamic var serverUUID: String?
    
    @objc dynamic var libraryName: String?
    
    @objc dynamic var id: Int32 = 0 {
        didSet {
            updatePrimaryKey()
        }
    }
    @objc dynamic var title = ""
    @objc dynamic var authorFirst: String?
    @objc dynamic var authorSecond: String?
    @objc dynamic var authorThird: String?
    let authorsMore = List<String>()
    @objc dynamic var comments = ""
    @objc dynamic var publisher = ""
    @objc dynamic var series = ""
    @objc dynamic var seriesIndex = 0.0
    @objc dynamic var rating = 0
    @objc dynamic var size = 0
    @objc dynamic var pubDate = Date(timeIntervalSince1970: 0)
    @objc dynamic var timestamp = Date(timeIntervalSince1970: 0)
    @objc dynamic var lastModified = Date(timeIntervalSince1970: 0)
    @objc dynamic var lastSynced = Date(timeIntervalSince1970: 0)
    @objc dynamic var lastUpdated = Date(timeIntervalSince1970: 0)  //local only
    @objc dynamic var lastProgress = 0.0
    
    @objc dynamic var tagFirst: String?
    @objc dynamic var tagSecond: String?
    @objc dynamic var tagThird: String?
    let tagsMore = List<String>()
    @objc dynamic var formatsData: NSData?
    @objc dynamic var readPosData: NSData?
    @objc dynamic var identifiersData: NSData?
    @objc dynamic var userMetaData: NSData?
    
    @objc dynamic var inShelf = false
    
    func formats() -> [String: FormatInfo] {
        guard let formatsData = formatsData as Data? else { return [:] }
        return (try? JSONDecoder().decode([String:FormatInfo].self, from: formatsData)) ?? [:]
        //return (try? JSONSerialization.jsonObject(with: formatsData as Data, options: []) as? [String: String]) ?? [:]
    }
    
    func identifiers() -> [String: String] {
        guard let identifiersData = identifiersData as Data? else { return [:] }
        return (try? JSONDecoder().decode([String:String].self, from: identifiersData)) ?? [:]
//        let identifiers = try! JSONSerialization.jsonObject(with: identifiersData! as Data, options: []) as! [String: String]
//        return identifiers
    }
    
    func userMetadatas() -> [String: Any] {
        guard let userMetaData = userMetaData as Data? else { return [:] }
        return (try? JSONSerialization.jsonObject(with: userMetaData, options: []) as? [String:Any]) ?? [:]
    }
    
    func readPos(library: CalibreLibrary) -> BookAnnotation {
        let readPos = BookAnnotation(id: id, library: library)
        
        let readPosObject = try? JSONSerialization.jsonObject(with: readPosData as Data? ?? Data(), options: [])
        let readPosDict = readPosObject as! NSDictionary? ?? NSDictionary()
        
        let deviceMapObject = readPosDict["deviceMap"]
        let deviceMapDict = deviceMapObject as! NSDictionary? ?? NSDictionary()
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
    
    override static func primaryKey() -> String? {
        return "primaryKey"
    }
    
    func updatePrimaryKey() {
        primaryKey = CalibreBookRealm.PrimaryKey(serverUUID: serverUUID!, libraryName: libraryName!, id: id.description)
    }
    
    static func PrimaryKey(serverUUID: String, libraryName: String, id: String) -> String {
        return [id, "^", libraryName, "@", serverUUID].joined()
    }
    
    override static func indexedProperties() -> [String] {
        return ["serverUrl", "serverUsername", "libraryName", "id", "title", "inShelf", "series", "authorFirst", "tagFirst", "pubDate"]
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
        
        self.id = managedObject.id
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
        bookRealm.id = self.id

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
        bookRealm.formatsData = try? encoder.encode(self.formats) as NSData
        
        //bookRealm.identifiersData = try JSONSerialization.data(withJSONObject: book.identifiers, options: []) as NSData
        bookRealm.identifiersData = try? encoder.encode(self.identifiers) as NSData
        
        bookRealm.userMetaData = try? JSONSerialization.data(withJSONObject: self.userMetadatas, options: []) as NSData
        
        let deviceMapSerialize = self.readPos.getCopy().compactMapValues { (value) -> Any? in
            try? JSONSerialization.jsonObject(with: encoder.encode(value))
        }
        bookRealm.readPosData = try? JSONSerialization.data(withJSONObject: ["deviceMap": deviceMapSerialize], options: []) as NSData
        
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

class CalibreLibraryGoodreadsSyncRealm: Object {
    @objc dynamic var isEnabled = false
    @objc dynamic var isDefault = false
    @objc dynamic var isOverride = false
    
    @objc dynamic var profileName: String?
    @objc dynamic var tagsColumnName: String?
    @objc dynamic var ratingColumnName: String?
    @objc dynamic var dateReadColumnName: String?
    @objc dynamic var reviewColumnName: String?
    @objc dynamic var readingProgressColumnName: String?
}

extension CalibreLibraryGoodreadsSync: Persistable {
    public init(managedObject: CalibreLibraryGoodreadsSyncRealm) {
        _isEnabled = managedObject.isEnabled
        _isDefault = managedObject.isDefault
        _isOverride = managedObject.isOverride
        profileName = managedObject.profileName ?? profileName
        tagsColumnName = managedObject.tagsColumnName ?? tagsColumnName
        ratingColumnName = managedObject.ratingColumnName ?? ratingColumnName
        dateReadColumnName = managedObject.dateReadColumnName ?? dateReadColumnName
        reviewColumnName = managedObject.reviewColumnName ?? reviewColumnName
        readingProgressColumnName = managedObject.readingProgressColumnName ?? readingProgressColumnName
    }
    
    public func managedObject() -> CalibreLibraryGoodreadsSyncRealm {
        let obj = CalibreLibraryGoodreadsSyncRealm()
        obj.isEnabled = isEnabled()
        obj.isDefault = isDefault()
        obj.isOverride = isOverride()
        obj.profileName = profileName
        obj.tagsColumnName = tagsColumnName
        obj.ratingColumnName = ratingColumnName
        obj.dateReadColumnName = dateReadColumnName
        obj.reviewColumnName = reviewColumnName
        obj.readingProgressColumnName = readingProgressColumnName
        return obj
    }
}

class CalibreLibraryCountPageRealm: Object {
    @objc dynamic var isEnabled = false
    @objc dynamic var isDefault = false
    @objc dynamic var isOverride = false

    @objc dynamic var pageCountCN: String?
    @objc dynamic var wordCountCN: String?
    @objc dynamic var fleschReadingEaseCN: String?
    @objc dynamic var fleschKincaidGradeCN: String?
    @objc dynamic var gunningFogIndexCN: String?
}

extension CalibreLibraryCountPages: Persistable {
    public init(managedObject: CalibreLibraryCountPageRealm) {
        _isEnabled = managedObject.isEnabled
        _isDefault = managedObject.isDefault
        _isOverride = managedObject.isOverride
        pageCountCN = managedObject.pageCountCN ?? pageCountCN
        wordCountCN = managedObject.wordCountCN ?? wordCountCN
        fleschReadingEaseCN = managedObject.fleschReadingEaseCN ?? fleschReadingEaseCN
        fleschKincaidGradeCN = managedObject.fleschKincaidGradeCN ?? fleschKincaidGradeCN
        gunningFogIndexCN = managedObject.gunningFogIndexCN ?? gunningFogIndexCN
    }
    
    public func managedObject() -> CalibreLibraryCountPageRealm {
        let obj = CalibreLibraryCountPageRealm()
        obj.isEnabled = isEnabled()
        obj.isDefault = isDefault()
        obj.isOverride = isOverride()
        obj.pageCountCN = pageCountCN
        obj.wordCountCN = wordCountCN
        obj.fleschReadingEaseCN = fleschReadingEaseCN
        obj.fleschKincaidGradeCN = fleschKincaidGradeCN
        obj.gunningFogIndexCN = gunningFogIndexCN
        return obj
    }
}

class CalibreLibraryReadingPositionRealm: Object {
    @objc dynamic var isEnabled = false
    @objc dynamic var isDefault = false
    @objc dynamic var isOverride = false

    @objc dynamic var readingPositionCN: String?
}

extension CalibreLibraryReadingPosition: Persistable {
    public init(managedObject: CalibreLibraryReadingPositionRealm) {
        _isEnabled = managedObject.isEnabled
        _isDefault = managedObject.isDefault
        _isOverride = managedObject.isOverride
        readingPositionCN = managedObject.readingPositionCN ?? readingPositionCN
    }
    
    public func managedObject() -> CalibreLibraryReadingPositionRealm {
        let obj = CalibreLibraryReadingPositionRealm()
        obj.isEnabled = isEnabled()
        obj.isDefault = isDefault()
        obj.isOverride = isOverride()
        obj.readingPositionCN = readingPositionCN
        return obj
    }
}

class CalibreLibraryDictionaryViewerRealm: Object {
    @objc dynamic var isEnabled = false
    @objc dynamic var isDefault = false
    @objc dynamic var isOverride = false

    @objc dynamic var readingPositionCN: String?
}

extension CalibreLibraryDictionaryViewer: Persistable {
    public init(managedObject: CalibreLibraryDictionaryViewerRealm) {
        _isEnabled = managedObject.isEnabled
        _isDefault = managedObject.isDefault
        _isOverride = managedObject.isOverride
    }
    
    public func managedObject() -> CalibreLibraryDictionaryViewerRealm {
        let obj = CalibreLibraryDictionaryViewerRealm()
        obj.isEnabled = isEnabled()
        obj.isDefault = isDefault()
        obj.isOverride = isOverride()
        return obj
    }
}

class CalibreActivityLogEntry: Object {
    @objc dynamic var type: String?
    
    @objc dynamic var startDatetime = Date.distantPast
    @objc dynamic var finishDatetime: Date?
    
    //book or library, not both
    @objc dynamic var bookId: Int32 = 0
    @objc dynamic var libraryId: String?
    
    @objc dynamic var endpoingURL: String?
    @objc dynamic var httpMethod: String?
    @objc dynamic var httpBody: Data?       //if any
    let requestHeaders = List<String>()     //key1, value1, key2, value2, ...
    
    @objc dynamic var errMsg: String?
    
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

class BookDeviceReadingPositionRealm: Object {
    @objc dynamic var bookId: String = .init()
    @objc dynamic var id = ""
    
    @objc dynamic var readerName = ""
    @objc dynamic var maxPage = 0
    @objc dynamic var lastReadPage = 0
    @objc dynamic var lastReadChapter = ""
    /// range 0 - 100
    @objc dynamic var lastChapterProgress = 0.0
    /// range 0 - 100
    @objc dynamic var lastProgress = 0.0
    @objc dynamic var furthestReadPage = 0
    @objc dynamic var furthestReadChapter = ""
    let lastPosition = List<Int>()
    @objc dynamic var cfi = "/"
    @objc dynamic var epoch = 0.0
    
    @objc dynamic var takePrecedence: Bool = false
    
    //for non-linear book structure
    @objc dynamic var structuralStyle: Int = .zero
    @objc dynamic var structuralRootPageNumber: Int = 1
    @objc dynamic var positionTrackingStyle: Int = .zero
    @objc dynamic var lastReadBook = ""
    @objc dynamic var lastBundleProgress: Double = .zero
    
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
        id = managedObject.id
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
        obj.id = id
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

class BookDeviceReadingPositionHistoryRealm: Object {
    @objc dynamic var bookId: String = ""
    
    @objc dynamic var startDatetime = Date()
    @objc dynamic var startPosition: BookDeviceReadingPositionRealm?
    @objc dynamic var endPosition: BookDeviceReadingPositionRealm?
    
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

class CalibreBookLastReadPositionRealm: Object {
    @objc dynamic var device = ""
    @objc dynamic var cfi = ""
    @objc dynamic var epoch = 0.0
    @objc dynamic var pos_frac = 0.0
    
    override static func primaryKey() -> String? {
        return "device"
    }
}

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

extension BookDeviceReadingPosition {
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

class CalibreServerDSReaderHelperRealm: Object {
    @objc dynamic var id: String?
    @objc dynamic var port: Int = 0
    @objc dynamic var data: Data?
    
    override static func primaryKey() -> String? {
        return "id"
    }
}

extension CalibreServerDSReaderHelper: Persistable {
    public init(managedObject: CalibreServerDSReaderHelperRealm) {
        self.id = managedObject.id ?? ""
        self.port = managedObject.port
        self.configurationData = managedObject.data
        if let data = self.configurationData {
            self.configuration = try? JSONDecoder().decode(CalibreDSReaderHelperConfiguration.self, from: data)
        }
    }
    
    public func managedObject() -> CalibreServerDSReaderHelperRealm {
        let obj = CalibreServerDSReaderHelperRealm()
        obj.id = self.id
        obj.port = self.port
        obj.data = self.configurationData
        
        return obj
    }
}

class CalibreLibraryDSReaderHelperRealm: Object {
    @objc dynamic var isEnabled = false
    @objc dynamic var isDefault = false
    @objc dynamic var isOverride = false

    @objc dynamic var port = Int()
    
    @objc dynamic var autoUpdateGoodreadsProgress = false
    @objc dynamic var autoUpdateGoodreadsBookShelf = false
}

extension CalibreLibraryDSReaderHelper: Persistable {
    public init(managedObject: CalibreLibraryDSReaderHelperRealm) {
        self._isEnabled = managedObject.isEnabled
        self._isDefault = managedObject.isDefault
        self._isOverride = managedObject.isOverride
        self.autoUpdateGoodreadsProgress = managedObject.autoUpdateGoodreadsProgress
        self.autoUpdateGoodreadsBookShelf = managedObject.autoUpdateGoodreadsBookShelf
    }
    
    public func managedObject() -> CalibreLibraryDSReaderHelperRealm {
        let obj = CalibreLibraryDSReaderHelperRealm()
        obj.isEnabled = isEnabled()
        obj.isDefault = isDefault()
        obj.isOverride = isOverride()
        obj.autoUpdateGoodreadsProgress = self.autoUpdateGoodreadsProgress
        obj.autoUpdateGoodreadsBookShelf = self.autoUpdateGoodreadsBookShelf
        
        return obj
    }
}

class BookBookmarkRealm: Object {
    @objc dynamic var bookId: String = .init()
    @objc dynamic var page: Int = .zero
    
    @objc dynamic var pos_type: String = .init()
    @objc dynamic var pos: String = .init()
    
    @objc dynamic var title: String = .init()
    @objc dynamic var date: Date = .init()
    
    @objc dynamic var removed: Bool = false
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

extension PDFOptions: Persistable {
    public init(managedObject: PDFOptionsRealm) {
        self.id = managedObject.id
        self.libraryName = managedObject.libraryName
        self.themeMode = .init(rawValue: managedObject.themeMode) ?? .serpia
        self.selectedAutoScaler = .init(rawValue: managedObject.selectedAutoScaler) ?? .Width
        self.pageMode = .init(rawValue: managedObject.pageMode) ?? .Page
        self.readingDirection = .init(rawValue: managedObject.readingDirection) ?? .LtR_TtB
        self.scrollDirection = .init(rawValue: managedObject.scrollDirection) ?? .Vertical
        self.hMarginAutoScaler = managedObject.hMarginAutoScaler
        self.vMarginAutoScaler = managedObject.vMarginAutoScaler
        self.hMarginDetectStrength = managedObject.hMarginDetectStrength
        self.vMarginDetectStrength = managedObject.vMarginDetectStrength
        self.marginOffset = managedObject.marginOffset
        self.lastScale = managedObject.lastScale
        self.rememberInPagePosition = managedObject.rememberInPagePosition
    }
    
    public func managedObject() -> PDFOptionsRealm {
        let obj = PDFOptionsRealm()
        
        obj.id = self.id
        obj.libraryName = self.libraryName
        obj.themeMode = self.themeMode.rawValue
        obj.selectedAutoScaler = self.selectedAutoScaler.rawValue
        obj.pageMode = self.pageMode.rawValue
        obj.readingDirection = self.readingDirection.rawValue
        obj.scrollDirection = self.scrollDirection.rawValue
        obj.hMarginAutoScaler = self.hMarginAutoScaler
        obj.vMarginAutoScaler = self.vMarginAutoScaler
        obj.hMarginDetectStrength = self.hMarginDetectStrength
        obj.vMarginDetectStrength = self.vMarginDetectStrength
        obj.marginOffset = self.marginOffset
        obj.lastScale = self.lastScale
        obj.rememberInPagePosition = self.rememberInPagePosition
        
        return obj
    }
}
