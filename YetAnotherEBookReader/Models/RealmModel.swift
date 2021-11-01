//
//  RealmModel.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/7/22.
//

import Foundation
import RealmSwift

class CalibreServerRealm: Object {
    @objc dynamic var primaryKey: String?
    
    @objc dynamic var name: String?
    
    @objc dynamic var baseUrl: String? {
        didSet {
            updatePrimaryKey()
        }
    }
    @objc dynamic var publicUrl: String?
    
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
    
    @objc dynamic var readPosColumnName: String?
    @objc dynamic var goodreadsSync: CalibreLibraryGoodreadsSyncRealm?
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
        
        let readPosObject = try! JSONSerialization.jsonObject(with: readPosData! as Data, options: [])
        let readPosDict = readPosObject as! NSDictionary
        
        let deviceMapObject = readPosDict["deviceMap"]
        let deviceMapDict = deviceMapObject as! NSDictionary
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
            
            deviceReadingPosition.lastReadPage = deviceReadingPositionDict["lastReadPage"] as! Int
            deviceReadingPosition.lastReadChapter = deviceReadingPositionDict["lastReadChapter"] as! String
            deviceReadingPosition.lastChapterProgress = deviceReadingPositionDict["lastChapterProgress"] as? Double ?? 0.0
            deviceReadingPosition.lastProgress = deviceReadingPositionDict["lastProgress"] as? Double ?? 0.0
            deviceReadingPosition.furthestReadPage = deviceReadingPositionDict["furthestReadPage"] as! Int
            deviceReadingPosition.furthestReadChapter = deviceReadingPositionDict["furthestReadChapter"] as! String
            deviceReadingPosition.maxPage = deviceReadingPositionDict["maxPage"] as! Int
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

class CalibreLibraryGoodreadsSyncRealm: Object {
    @objc dynamic var isEnabled = false
    @objc dynamic var isDefault = false
    
    @objc dynamic var profileName: String?
    @objc dynamic var tagsColumnName: String?
    @objc dynamic var ratingColumnName: String?
    @objc dynamic var dateReadColumnName: String?
    @objc dynamic var reviewColumnName: String?
    @objc dynamic var readingProgressColumnName: String?
}

public protocol Persistable {
    associatedtype ManagedObject: RealmSwift.Object
    init(managedObject: ManagedObject)
    func managedObject() -> ManagedObject
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

extension CalibreLibraryGoodreadsSync: Persistable {
    public init(managedObject: CalibreLibraryGoodreadsSyncRealm) {
        isEnabled = managedObject.isEnabled
        isDefault = managedObject.isDefault
        profileName = managedObject.profileName ?? profileName
        tagsColumnName = managedObject.tagsColumnName ?? tagsColumnName
        ratingColumnName = managedObject.ratingColumnName ?? ratingColumnName
        dateReadColumnName = managedObject.dateReadColumnName ?? dateReadColumnName
        reviewColumnName = managedObject.reviewColumnName ?? reviewColumnName
        readingProgressColumnName = managedObject.readingProgressColumnName ?? readingProgressColumnName
    }
    
    public func managedObject() -> CalibreLibraryGoodreadsSyncRealm {
        let obj = CalibreLibraryGoodreadsSyncRealm()
        obj.isEnabled = isEnabled
        obj.isDefault = isDefault
        obj.profileName = profileName
        obj.tagsColumnName = tagsColumnName
        obj.ratingColumnName = ratingColumnName
        obj.dateReadColumnName = dateReadColumnName
        obj.reviewColumnName = reviewColumnName
        obj.readingProgressColumnName = readingProgressColumnName
        return obj
    }
}

class CalibreActivityLogEntry: Object {
    @objc dynamic var type: String?
    
    @objc dynamic var startDatetime: Date?
    @objc dynamic var finishDatetime: Date?
    
    //book or library, not both
    @objc dynamic var bookInShelfId: String?
    @objc dynamic var libraryId: String?
    
    @objc dynamic var endpoingURL: String?
    @objc dynamic var httpMethod: String?
    @objc dynamic var httpBody: Data?       //if any
    let requestHeaders = List<String>()     //key1, value1, key2, value2, ...
    
    @objc dynamic var errMsg: String?
    
    var startDateByLocale: String? {
        guard let startDatetime = startDatetime else { return nil }
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .medium
        dateFormatter.locale = Locale.autoupdatingCurrent
        return dateFormatter.string(from: startDatetime)
    }
    var startDateByLocaleLong: String? {
        guard let startDatetime = startDatetime else { return nil }
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
