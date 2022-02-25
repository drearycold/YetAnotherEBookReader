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
    let authors = List<String>()
    @objc dynamic var comments = ""
    @objc dynamic var publisher = ""
    @objc dynamic var series = ""
    @objc dynamic var seriesIndex = 0.0
    @objc dynamic var rating = 0
    @objc dynamic var size = 0
    @objc dynamic var pubDate = Date()
    @objc dynamic var timestamp = Date()
    @objc dynamic var lastModified = Date()
    let tags = List<String>()
    @objc dynamic var formatsData: NSData?
    @objc dynamic var readPosData: NSData?
    @objc dynamic var identifiersData: NSData?
    @objc dynamic var userMetaData: NSData?
    
    @objc dynamic var inShelf = false
    @objc dynamic var inShelfName = ""
    
    func formats() -> [String: String] {
        guard let formatsData = formatsData as Data? else { return [:] }
        return (try? JSONDecoder().decode([String:String].self, from: formatsData)) ?? [:]
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
    
    func readPos() -> BookReadingPosition {
        var readPos = BookReadingPosition()
        
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
            if let lastPosition = deviceReadingPositionDict["lastPosition"] {
                deviceReadingPosition.lastPosition = lastPosition as! [Int]
            }
            
            readPos.updatePosition(deviceName, deviceReadingPosition)
        }
        return readPos
    }
    
    override static func primaryKey() -> String? {
        return "primaryKey"
    }
    
    func updatePrimaryKey() {
        primaryKey = "\(serverUsername ?? "-")@\(serverUrl ?? "-") - \(libraryName ?? "-") ^ \(id)"
    }
    
    override static func indexedProperties() -> [String] {
        return ["serverUrl", "serverUsername", "libraryName", "id", "title", "inShelf"]
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
