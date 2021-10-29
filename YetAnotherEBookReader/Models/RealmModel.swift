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
    @objc dynamic var goodreadsSyncProfileName: String?
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
    
    @objc dynamic var inShelf = false
    @objc dynamic var inShelfName = ""
    
    func formats() -> [String: String] {
        do {
            if let formats = try JSONSerialization.jsonObject(with: formatsData! as Data, options: []) as? [String: String] {
                return formats
            }
        } catch {
            
        }
        return [:]
    }
    
    func identifiers() -> [String: String] {
        let identifiers = try! JSONSerialization.jsonObject(with: identifiersData! as Data, options: []) as! [String: String]
        return identifiers
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
        return obj
    }
}
