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
        
        let bookPrefId = BookAnnotation.PrefId(library: library, id: idInLib)
        
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
            
            repository.savePosition(deviceReadingPosition, forBookId: bookPrefId)
        }
    }
    
    func updatePrimaryKey() {
        guard let serverUUID = serverUUID, let libraryName = libraryName else { return }
        primaryKey = CalibreBookRealm.PrimaryKey(serverUUID: serverUUID, libraryName: libraryName, id: idInLib.description)
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
    }
}

extension CalibreBook: Persistable {
    internal init(managedObject: CalibreBookRealm) {
        self.id = 0
        self.library = .init(server: .init(uuid: .init(), name: "", baseUrl: "", hasPublicUrl: false, publicUrl: "", hasAuth: false, username: "", password: ""), key: "", name: "")
    }
    
    public init(managedObject: CalibreBookRealm, library: CalibreLibrary) {
        let formatsVer1 = managedObject.formats().reduce(
            into: [String: FormatInfo]()
        ) { result, entry in
            result[entry.key] = FormatInfo(serverSize: 0, serverMTime: .distantPast, cached: false, cacheSize: 0, cacheMTime: .distantPast)
        }
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
        
        bookRealm.identifiersData = try? encoder.encode(self.identifiers)
        
        bookRealm.userMetaData = try? JSONSerialization.data(withJSONObject: self.userMetadatas, options: [])
        
        bookRealm.readPosData = nil
        
        return bookRealm
    }
}
