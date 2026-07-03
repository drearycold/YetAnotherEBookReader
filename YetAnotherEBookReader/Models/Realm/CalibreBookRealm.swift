//
//  CalibreBookRealm.swift
//  YetAnotherEBookReader
//

import Foundation
import RealmSwift

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
    }
    
    func identifiers() -> [String: String] {
        guard let identifiersData = identifiersData else { return [:] }
        return (try? JSONDecoder().decode([String:String].self, from: identifiersData)) ?? [:]
    }
    
    func userMetadatas() -> [String: Any] {
        guard let userMetaData = userMetaData else { return [:] }
        return (try? JSONSerialization.jsonObject(with: userMetaData, options: []) as? [String:Any]) ?? [:]
    }
    
    func migrateReadPos(library: CalibreLibrary, repository: ReadingPositionRepositoryProtocol) {
        guard let readPosData = readPosData,
              let readPosDict = try? JSONSerialization.jsonObject(with: readPosData, options: []) as? NSDictionary,
              let deviceMapDict = readPosDict["deviceMap"] as? NSDictionary
        else {
            return
        }
        
        let book = CalibreBook(id: idInLib, library: library)
        
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
            
            repository.savePosition(deviceReadingPosition, for: book)
        }
    }
    
    func updatePrimaryKey() {
        guard let serverUUID = serverUUID, let libraryName = libraryName else { return }
        primaryKey = CalibreBookRealm.PrimaryKey(serverUUID: serverUUID, libraryName: libraryName, id: idInLib.description)
    }
    
    static func PrimaryKey(serverUUID: String, libraryName: String, id: String) -> String {
        CalibreBook.identity(serverUUID: serverUUID, libraryName: libraryName, id: id)
    }
    
    var ratingDescription: String {
        CalibreBook.ratingDescription(for: rating)
    }
    
    static func RatingDescription(_ rating: Int) -> String {
        CalibreBook.ratingDescription(for: rating)
    }
}

extension CalibreBook: Persistable {
    internal init(managedObject: CalibreBookRealm) {
        self.id = 0
        self.library = .init(server: .init(uuid: .init(), name: "", baseUrl: "", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: ""), key: "", name: "")
    }
    
    public init(managedObject: CalibreBookRealm, library: CalibreLibrary) {
        self = managedObject.toDomain(library: library)
    }
    
    public func managedObject() -> CalibreBookRealm {
        return self.makeRealmObject()
    }
}
