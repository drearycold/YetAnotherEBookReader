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
    @objc dynamic var primaryKey: String?
    
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
    
    @objc dynamic var lastLibrary: String?
    
    override static func primaryKey() -> String? {
        return "primaryKey"
    }
    
    func updatePrimaryKey() {
        primaryKey = "\(username ?? "-")@\(baseUrl ?? "-")"
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
    @objc dynamic var inShelfName = ""
    
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
    
    func readPos(library: CalibreLibrary) -> BookReadingPosition {
        var readPos = BookReadingPosition(id: id, library: library)
        
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
            
            readPos.updatePosition(deviceName, deviceReadingPosition)
        }
        return readPos
    }
    
    override static func primaryKey() -> String? {
        return "primaryKey"
    }
    
    func updatePrimaryKey() {
        primaryKey = CalibreBookRealm.PrimaryKey(serverUsername: serverUsername, serverUrl: serverUrl, libraryName: libraryName, id: id.description)
    }
    
    static func PrimaryKey(serverUsername: String?, serverUrl: String?, libraryName: String?, id: String) -> String {
        return "\(serverUsername ?? "-")@\(serverUrl ?? "-") - \(libraryName ?? "-") ^ \(id)"
    }
    
    override static func indexedProperties() -> [String] {
        return ["serverUrl", "serverUsername", "libraryName", "id", "title", "inShelf", "series", "authorFirst", "tagFirst", "pubDate"]
    }
}

extension CalibreBook: Persistable {
    internal init(managedObject: CalibreBookRealm) {
        self.id = 0
        self.library = .init(server: .init(name: "", baseUrl: "", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: ""), key: "", name: "")
        self.readPos = BookReadingPosition(id: id, library: library)
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
        self.inShelfName = managedObject.inShelfName
        
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
        bookRealm.id = self.id
        bookRealm.serverUrl = self.library.server.baseUrl
        bookRealm.serverUsername = self.library.server.username
        bookRealm.libraryName = self.library.name
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
        bookRealm.inShelfName = self.inShelfName
        
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

/**
 realm backed
 */
struct BookReadingPosition {
    let id: Int32
    let library: CalibreLibrary
    let bookPrefId: String
    
    var realm: Realm?
    
    var isEmpty: Bool { get { get()?.isEmpty ?? true } }
    
    init(id: Int32, library: CalibreLibrary) {
        self.id = id
        self.library = library
        bookPrefId = "\(library.key) - \(id)"
        
        realm = openRealm()
    }
    
    func openRealm() -> Realm? {
        guard let bookBaseUrl = getBookBaseUrl(id: id, library: library),
              let bookPrefConf = getBookPreferenceConfig(bookFileURL: bookBaseUrl),
              let basePrefUrl = bookPrefConf.fileURL,
              FileManager.default.fileExists(atPath: basePrefUrl.path)
        else { return nil }
        
        return try? Realm(configuration: bookPrefConf)
    }
    
    func getPosition(_ deviceName: String) -> BookDeviceReadingPosition? {
        let realm = Thread.isMainThread ? self.realm : openRealm()
        
        if let position = realm?.objects(BookDeviceReadingPositionRealm.self)
            .filter(NSPredicate(format: "bookId = %@ AND id= %@ AND takePrecedence = true", bookPrefId, deviceName))
            .sorted(byKeyPath: "epoch", ascending: false)
            .map({ BookDeviceReadingPosition(managedObject: $0) })
            .first {
            return position
        }
        return realm?.objects(BookDeviceReadingPositionRealm.self)
            .filter(NSPredicate(format: "bookId = %@", bookPrefId))
            .sorted(byKeyPath: "epoch", ascending: false)
            .map({ BookDeviceReadingPosition(managedObject: $0) })
            .first
    }
    
    func addInitialPosition(_ deviceName: String, _ readerName: String) {
        //TODO: try doing nothing
    }
    
    mutating func updatePosition(_ deviceName: String, _ newPosition: BookDeviceReadingPosition) {
        if realm == nil {
            realm = openRealm()
        }
        
        try? realm?.write {
            if let existing = realm?.objects(BookDeviceReadingPositionRealm.self)
                .filter(NSPredicate(
                    format: "bookId = %@ AND id = %@ AND structuralStyle = %@ AND positionTrackingStyle = %@ AND structuralRootPageNumber = %@",
                    bookPrefId,
                    newPosition.id,
                    NSNumber(value: newPosition.structuralStyle),
                    NSNumber(value: newPosition.positionTrackingStyle),
                    NSNumber(value: newPosition.structuralRootPageNumber)
                )),
               existing.isEmpty == false {
                let existingCount = existing.count
                let oldObjs = existing.filter { $0.epoch < newPosition.epoch }
                let oldobjsCount = oldObjs.count
                realm?.delete(oldObjs)
                
                if oldobjsCount == existingCount {
                    let obj = newPosition.managedObject()
                    obj.bookId = bookPrefId
                    realm?.add(obj)
                }
            } else {
                let obj = newPosition.managedObject()
                obj.bookId = bookPrefId
                realm?.add(obj)
            }
        }
    }
    
    func removePosition(_ deviceName: String) {
        if let objs = realm?.objects(BookDeviceReadingPositionRealm.self)
            .filter(NSPredicate(format: "bookId = %@ and id = %@", bookPrefId, deviceName)),
           objs.isEmpty == false {
            try? realm?.write {
                realm?.delete(objs)
            }
        }
    }
    
    func removePosition(position: BookDeviceReadingPosition) {
        try? realm?.write {
            if let existing = realm?.objects(BookDeviceReadingPositionRealm.self)
                .filter(NSPredicate(
                    format: "bookId = %@ AND id = %@ AND readerName = %@ AND structuralStyle = %@ AND positionTrackingStyle = %@ AND structuralRootPageNumber = %@",
                    bookPrefId,
                    position.id,
                    position.readerName,
                    NSNumber(value: position.structuralStyle),
                    NSNumber(value: position.positionTrackingStyle),
                    NSNumber(value: position.structuralRootPageNumber)
                )),
               existing.isEmpty == false {
                realm?.delete(existing)
            }
        }
    }
    
    func getCopy() -> [String: BookDeviceReadingPosition] {
        return get()?.reduce(into: [String: BookDeviceReadingPosition](), { partialResult, obj in
            if (partialResult[obj.id]?.epoch ?? Date.distantPast.timeIntervalSince1970) < obj.epoch {
                partialResult[obj.id] = BookDeviceReadingPosition(managedObject: obj)
            }
        }) ?? [:]
    }
    
    func getDevices() -> [BookDeviceReadingPosition] {
        return get()?.map { BookDeviceReadingPosition(managedObject: $0) } ?? []
    }
    
    func getDevices(by reader: ReaderType) -> [BookDeviceReadingPosition] {
        return getDevices().filter {
            $0.readerName == reader.id
        }
    }
    
    private func get() -> Results<BookDeviceReadingPositionRealm>? {
        let realm = Thread.isMainThread ? self.realm : openRealm()
        
        return realm?.objects(BookDeviceReadingPositionRealm.self)
            .filter(NSPredicate(format: "bookId = %@", bookPrefId))
    }
}

struct BookPreference {
    let id: Int32
    let library: CalibreLibrary
    let bookPrefId: String
    
    var realm: Realm?
    
    init(id: Int32, library: CalibreLibrary) {
        self.id = id
        self.library = library
        bookPrefId = "\(library.key) - \(id)"
        
        realm = openRealm()
    }
    
    func openRealm() -> Realm? {
        guard let bookBaseUrl = getBookBaseUrl(id: id, library: library),
              let bookPrefConf = getBookPreferenceConfig(bookFileURL: bookBaseUrl),
              let basePrefUrl = bookPrefConf.fileURL,
              FileManager.default.fileExists(atPath: basePrefUrl.path)
        else { return nil }
        
        return try? Realm(configuration: bookPrefConf)
    }
    
    func getObject(for reader: ReaderType) -> Object? {
        switch reader {
        case .UNSUPPORTED:
            return nil
        case .YabrEPUB:
            return realm?.object(ofType: FolioReaderPreferenceRealm.self, forPrimaryKey: bookPrefId + ".epub")
        case .YabrPDF:
            return realm?.object(ofType: PDFOptionsRealm.self, forPrimaryKey: Int(id))
        case .ReadiumEPUB:
            return nil
        case .ReadiumPDF:
            return nil
        case .ReadiumCBZ:
            return nil
        }
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
}

class BookDeviceReadingPositionHistoryRealm: Object {
    @objc dynamic var bookId = Int32()
    @objc dynamic var libraryId = ""
    
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
