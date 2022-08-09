//
//  Providers.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/9/27.
//

import Foundation
import FolioReaderKit
import RealmSwift

extension EpubFolioReaderContainer {
    func folioReaderPreferenceProvider(_ folioReader: FolioReader) -> FolioReaderPreferenceProvider {
        if let preferenceProvider = folioReaderPreferenceProvider {
            return preferenceProvider
        } else {
            guard let book = modelData?.readingBook,
                  let format = modelData?.readerInfo?.format,
                  let realmConfig = getBookPreferenceConfig(book: book, format: format)
                  else { return FolioReaderDummyPreferenceProvider(folioReader) }
            let preferenceProvider = FolioReaderRealmPreferenceProvider(folioReader, realmConfig: realmConfig)
            self.folioReaderPreferenceProvider = preferenceProvider
            
            return preferenceProvider
        }
    }
    
    func folioReaderHighlightProvider(_ folioReader: FolioReader) -> FolioReaderHighlightProvider {
        if let highlightProvider = folioReaderHighlightProvider {
            return highlightProvider
        } else {
            guard let book = modelData?.readingBook,
                  let format = modelData?.readerInfo?.format,
                  let realmConfig = getBookPreferenceConfig(book: book, format: format)
                  else { return FolioReaderDummyHighlightProvider() }
            let highlightProvider = FolioReaderRealmHighlightProvider(realmConfig: realmConfig)
            self.folioReaderHighlightProvider = highlightProvider
            
            return highlightProvider
        }
    }
    
    func folioReaderReadPositionProvider(_ folioReader: FolioReader) -> FolioReaderReadPositionProvider {
        if let provider = folioReaderReadPositionProvider {
            return provider
        } else {
            guard let book = modelData?.readingBook,
                  let format = modelData?.readerInfo?.format,
                  let realmConfig = getBookPreferenceConfig(book: book, format: format),
                  let bookId = realmConfig.fileURL?.deletingPathExtension().lastPathComponent
                  else { return FolioReaderNaiveReadPositionProvider() }
            let provider = FolioReaderRealmReadPositionProvider(realmConfig: realmConfig)
            
            provider.realm?.objects(FolioReaderReadPositionRealm.self).compactMap { $0.toReadPosition() }.forEach { oldObject in
                provider.folioReaderReadPosition(folioReader, bookId: bookId, set: oldObject, completion: nil)
            }
            
            self.folioReaderReadPositionProvider = provider
            
            return provider
        }
    }
}

class FolioReaderPreferenceRealm: Object {
    override static func primaryKey() -> String? {
        return "id"
    }
    @objc dynamic var id: String = ""
    
    @objc dynamic var nightMode: Bool = false
    @objc dynamic var themeMode: Int = .min
    @objc dynamic var currentFont: String?
    @objc dynamic var currentFontSize: String?
    @objc dynamic var currentFontWeight: String?
    @objc dynamic var currentAudioRate: Int = .min
    @objc dynamic var currentHighlightStyle: Int = .min
    @objc dynamic var currentMediaOverlayStyle: Int = .min
    @objc dynamic var currentScrollDirection: Int = .min
    @objc dynamic var currentMenuIndex: Int = .min
    @objc dynamic var currentVMarginLinked: Bool = true
    @objc dynamic var currentMarginTop: Int = .min
    @objc dynamic var currentMarginBottom: Int = .min
    @objc dynamic var currentHMarginLinked: Bool = true
    @objc dynamic var currentMarginLeft: Int = .min
    @objc dynamic var currentMarginRight: Int = .min
    @objc dynamic var currentLetterSpacing: Int = .min
    @objc dynamic var currentLineHeight: Int = .min
    @objc dynamic var currentTextIndent: Int = .min
    @objc dynamic var doWrapPara: Bool = false
    @objc dynamic var doClearClass: Bool = true
    @objc dynamic var styleOverride: Int = .min
    @objc dynamic var savedPosition: Data?
    @objc dynamic var structuralStyle: Int = 0
    @objc dynamic var structuralTocLevel: Int = 0
}

class FolioReaderRealmPreferenceProvider: FolioReaderPreferenceProvider {
    
    let folioReader: FolioReader
    
    let realm: Realm?
    
    var prefObj: FolioReaderPreferenceRealm?
    
    init(_ folioReader: FolioReader, realmConfig: Realm.Configuration) {
        self.folioReader = folioReader
        realm = try? Realm(configuration: realmConfig)
        
        guard let realm = realm else { return }
        
        let id = folioReader.readerConfig?.identifier ?? "Default"
        
        prefObj = realm.objects(FolioReaderPreferenceRealm.self).filter(
            NSPredicate(format: "id = %@", id)
        ).first
        
        if prefObj == nil {
            let newPrefObj = FolioReaderPreferenceRealm()
            newPrefObj.id = id
            do {
                try realm.write {
                    realm.add(newPrefObj, update: .all)
                }
                prefObj = newPrefObj
            } catch {

            }
        }
    }

    func preference(nightMode defaults: Bool) -> Bool {
        return prefObj?.nightMode ?? defaults
    }
    
    func preference(setNightMode value: Bool) {
        try? realm?.write { prefObj?.nightMode = value }
    }
    
    func preference(themeMode defaults: Int) -> Int {
        return value(of: prefObj?.themeMode, defaults: defaults)
    }
    
    func preference(setThemeMode value: Int) {
        try? realm?.write { prefObj?.themeMode = value }
    }
    
    func preference(currentFont defaults: String) -> String {
        return prefObj?.currentFont ?? defaults
    }
    
    func preference(setCurrentFont value: String) {
        try? realm?.write { prefObj?.currentFont = value }
    }
    
    func preference(currentFontSize defaults: String) -> String {
        return prefObj?.currentFontSize ?? defaults
    }
    
    func preference(setCurrentFontSize value: String) {
        try? realm?.write { prefObj?.currentFontSize = value }
    }
    
    func preference(currentFontWeight defaults: String) -> String {
        return prefObj?.currentFontWeight ?? defaults
    }
    
    func preference(setCurrentFontWeight value: String) {
        try? realm?.write { prefObj?.currentFontWeight = value }
    }
    
    func preference(currentAudioRate defaults: Int) -> Int {
        return value(of: prefObj?.currentAudioRate, defaults: defaults)
    }
    
    func preference(setCurrentAudioRate value: Int) {
        try? realm?.write { prefObj?.currentAudioRate = value }
    }
    
    func preference(currentHighlightStyle defaults: Int) -> Int {
        return value(of: prefObj?.currentHighlightStyle, defaults: defaults)
    }
    
    func preference(setCurrentHighlightStyle value: Int) {
        try? realm?.write { prefObj?.currentHighlightStyle = value }
    }
    
    func preference(currentMediaOverlayStyle defaults: Int) -> Int {
        return value(of: prefObj?.currentMediaOverlayStyle, defaults: defaults)
    }
    
    func preference(setCurrentMediaOverlayStyle value: Int) {
        try? realm?.write { prefObj?.currentMediaOverlayStyle = value }
    }
    
    func preference(currentScrollDirection defaults: Int) -> Int {
        return value(of: prefObj?.currentScrollDirection, defaults: defaults)
    }
    
    func preference(setCurrentScrollDirection value: Int) {
        try? realm?.write { prefObj?.currentScrollDirection = value }
    }
    
    func preference(currentMenuIndex defaults: Int) -> Int {
        return value(of: prefObj?.currentMenuIndex, defaults: defaults)
    }
    
    func preference(setCurrentMenuIndex value: Int) {
        try? realm?.write { prefObj?.currentMenuIndex = value }
    }
    
    func preference(currentMarginTop defaults: Int) -> Int {
        return value(of: prefObj?.currentMarginTop, defaults: defaults)
    }
    
    func preference(setCurrentVMarginLinked value: Bool) {
        try? realm?.write { prefObj?.currentVMarginLinked = value }
    }
    
    func preference(currentVMarginLinked defaults: Bool) -> Bool {
        prefObj?.currentVMarginLinked ?? defaults
    }
    
    func preference(setCurrentMarginTop value: Int) {
        try? realm?.write { prefObj?.currentMarginTop = value }
    }
    
    func preference(currentMarginBottom defaults: Int) -> Int {
        return value(of: prefObj?.currentMarginBottom, defaults: defaults)
    }
    
    func preference(setCurrentMarginBottom value: Int) {
        try? realm?.write { prefObj?.currentMarginBottom = value }
    }
    
    func preference(setCurrentHMarginLinked value: Bool) {
        try? realm?.write { prefObj?.currentHMarginLinked = value }
    }
    
    func preference(currentHMarginLinked defaults: Bool) -> Bool {
        prefObj?.currentHMarginLinked ?? defaults
    }
    
    func preference(currentMarginLeft defaults: Int) -> Int {
        return value(of: prefObj?.currentMarginLeft, defaults: defaults)
    }
    
    func preference(setCurrentMarginLeft value: Int) {
        try? realm?.write { prefObj?.currentMarginLeft = value }
    }
    
    func preference(currentMarginRight defaults: Int) -> Int {
        return value(of: prefObj?.currentMarginRight, defaults: defaults)
    }
    
    func preference(setCurrentMarginRight value: Int) {
        try? realm?.write { prefObj?.currentMarginRight = value }
    }
    
    func preference(currentLetterSpacing defaults: Int) -> Int {
        return value(of: prefObj?.currentLetterSpacing, defaults: defaults)
    }
    
    func preference(setCurrentLetterSpacing value: Int) {
        try? realm?.write { prefObj?.currentLetterSpacing = value }
    }
    
    func preference(currentLineHeight defaults: Int) -> Int {
        return value(of: prefObj?.currentLineHeight, defaults: defaults)
    }
    
    func preference(setCurrentLineHeight value: Int) {
        try? realm?.write { prefObj?.currentLineHeight = value }
    }
    
    func preference(currentTextIndent defaults: Int) -> Int {
        return value(of: prefObj?.currentTextIndent, defaults: defaults)
    }
    
    func preference(setCurrentTextIndent value: Int) {
        try? realm?.write { prefObj?.currentTextIndent = value }
    }
    func preference(doWrapPara defaults: Bool) -> Bool {
        return prefObj?.doWrapPara ?? defaults
    }
    
    func preference(setDoWrapPara value: Bool) {
        try? realm?.write {
            prefObj?.doWrapPara = value
        }
    }
    
    func preference(doClearClass defaults: Bool) -> Bool {
        return prefObj?.doClearClass ?? defaults

    }
    
    func preference(setDoClearClass value: Bool) {
        try? realm?.write {
            prefObj?.doClearClass = value
        }
    }
    
    func preference(savedPosition defaults: [String : Any]?) -> [String : Any]? {
        guard let data = prefObj?.savedPosition,
              let dict = try? JSONSerialization.jsonObject(with: data, options: []) as? [String : Any] else {
            return defaults
        }
        
        return dict
    }
    
    func preference(setSavedPosition value: [String : Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: []) else { return }
        try? realm?.write {
            prefObj?.savedPosition = data
        }
    }
    
    func preference(styleOverride defaults: Int) -> Int {
        return prefObj?.styleOverride ?? defaults
    }
    
    func preference(setStyleOverride value: Int) {
        try? realm?.write {
            prefObj?.styleOverride = value
        }
    }
    
    func preference(structuralStyle defaults: Int) -> Int {
        return prefObj?.structuralStyle ?? defaults
    }
    
    func preference(setStructuralStyle value: Int) {
        try? realm?.write {
            prefObj?.structuralStyle = value
        }
    }
    
    func preference(structuralTocLevel defaults: Int) -> Int {
        return prefObj?.structuralTocLevel ?? defaults
    }
    
    func preference(setStructuralTocLevel value: Int) {
        try? realm?.write {
            prefObj?.structuralTocLevel = value
        }
    }
    
    private func value(of: Int?, defaults: Int) -> Int {
        if let v = of, v != .min {
            return v
        } else {
            return defaults
        }
    }
}

class FolioReaderHighlightRealm: Object {
    @objc open dynamic var removed: Bool = false
    @objc open dynamic var bookId: String?
    @objc open dynamic var content: String?
    @objc open dynamic var contentPost: String?
    @objc open dynamic var contentPre: String?
    @objc open dynamic var date: Date!
    @objc open dynamic var highlightId: String?
    @objc open dynamic var page: Int = 0
    @objc open dynamic var type: Int = 0
    @objc open dynamic var startOffset: Int = -1
    @objc open dynamic var endOffset: Int = -1
    @objc open dynamic var noteForHighlight: String?
    @objc open dynamic var cfiStart: String?
    @objc open dynamic var cfiEnd: String?
    @objc open dynamic var spineName: String?
    open dynamic var tocFamilyTitles = List<String>()

    override static func primaryKey()-> String? {
        return "highlightId"
    }
    
    func fromHighlight(_ highlight: FolioReaderHighlight) {
        bookId = highlight.bookId
        content = highlight.content
        contentPost = highlight.contentPost
        contentPre = highlight.contentPre
        date = highlight.date
        highlightId = highlight.highlightId
        page = highlight.page
        type = highlight.type
        startOffset = highlight.startOffset
        endOffset = highlight.endOffset
        noteForHighlight = highlight.noteForHighlight
        cfiStart = highlight.cfiStart
        cfiEnd = highlight.cfiEnd
        spineName = highlight.spineName
        tocFamilyTitles.removeAll()
        tocFamilyTitles.append(objectsIn: highlight.tocFamilyTitles)
        removed = false
    }
    
    func toHighlight() -> FolioReaderHighlight {
        let highlight = FolioReaderHighlight()
        highlight.bookId = bookId
        highlight.content = content
        highlight.contentPost = contentPost
        highlight.contentPre = contentPre
        highlight.date = date
        highlight.highlightId = highlightId
        highlight.page = page
        highlight.type = type
        highlight.style = FolioReaderHighlightStyle.classForStyle(type)
        highlight.startOffset = startOffset
        highlight.endOffset = endOffset
        highlight.noteForHighlight = noteForHighlight
        highlight.cfiStart = cfiStart
        highlight.cfiEnd = cfiEnd
        highlight.spineName = spineName
        highlight.tocFamilyTitles.removeAll()
        highlight.tocFamilyTitles.append(contentsOf: tocFamilyTitles)
        
        highlight.encodeContents()
        
        return highlight
    }
}

public class FolioReaderRealmHighlightProvider: FolioReaderHighlightProvider {
    let realm: Realm?

    init(realmConfig: Realm.Configuration) {
        realm = try? Realm(configuration: realmConfig)
    }
    
    public func folioReaderHighlight(_ folioReader: FolioReader, added highlight: FolioReaderHighlight, completion: Completion?) {
//        print("highlight added \(highlight)")
        
        var error: NSError? = nil
        defer {
            completion?(error)
        }
        
        guard let realm = self.realm else {
            error = NSError(domain: "Realm Error", code: -1, userInfo: nil)
            return
        }
        do {
            let highlightRealm = FolioReaderHighlightRealm()
            highlightRealm.fromHighlight(highlight)
            
            try realm.write {
                realm.add(highlightRealm, update: .all)
            }
        } catch let e as NSError {
            print("Error on persist highlight: \(e)")
            error = e
        }
    }
    
    public func folioReaderHighlight(_ folioReader: FolioReader, removedId highlightId: String) {
        try? realm?.write {
            if let object = realm?.object(ofType: FolioReaderHighlightRealm.self, forPrimaryKey: highlightId) {
                object.removed = true
                object.date = Date()
            }
        }
    }
    
    public func folioReaderHighlight(_ folioReader: FolioReader, updateById highlightId: String, type style: FolioReaderHighlightStyle) {
        try? realm?.write {
            realm?.object(ofType: FolioReaderHighlightRealm.self, forPrimaryKey: highlightId)?.type = style.rawValue
        }
    }

    public func folioReaderHighlight(_ folioReader: FolioReader, getById highlightId: String) -> FolioReaderHighlight? {
        return realm?.object(ofType: FolioReaderHighlightRealm.self, forPrimaryKey: highlightId)?.toHighlight()
    }
    
    public func folioReaderHighlight(_ folioReader: FolioReader, allByBookId bookId: String, andPage page: NSNumber?) -> [FolioReaderHighlight] {
        var predicate = NSPredicate(format: "removed == false && bookId = %@", bookId)
        if let page = page {
            predicate = NSPredicate(format: "removed == false && bookId = %@ && page = %@", bookId, page)
        }

        return realm?.objects(FolioReaderHighlightRealm.self)
            .filter(predicate)
            .map { $0.toHighlight() } ?? []
    }

    public func folioReaderHighlight(_ folioReader: FolioReader) -> [FolioReaderHighlight] {
        return realm?.objects(FolioReaderHighlightRealm.self)
            .filter(NSPredicate(format: "removed == false"))
            .map { $0.toHighlight() } ?? []
    }
    
    public func folioReaderHighlight(_ folioReader: FolioReader, saveNoteFor highlight: FolioReaderHighlight) {
        try? realm?.write {
            if let object = realm?.object(ofType: FolioReaderHighlightRealm.self, forPrimaryKey: highlight.highlightId) {
                object.noteForHighlight = highlight.noteForHighlight
                object.date = Date()
            }
        }
    }
}

extension FolioReaderRealmHighlightProvider {
    
    func folioReaderHighlight(bookId: String) -> [CalibreBookAnnotationEntry] {
        print("highlight all")
        
        guard let realm = realm else { return [] }
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = .withInternetDateTime.union(.withFractionalSeconds)
        
        let highlights:[CalibreBookAnnotationEntry] = realm.objects(FolioReaderHighlightRealm.self)
            .filter(NSPredicate(format: "bookId = %@", bookId))
            .compactMap { object -> CalibreBookAnnotationEntry? in
                guard let highlightId = object.highlightId,
                      let uuid = uuidFolioToCalibre(highlightId),
                      let cfiStart = object.cfiStart,
                      let cfiEnd = object.cfiEnd
                else { return nil }
                return CalibreBookAnnotationEntry(
                    type: "highlight",
                    timestamp: dateFormatter.string(from: object.date),
                    uuid: uuid,
                    removed: object.removed,
                    startCfi: cfiStart,
                    endCfi: cfiEnd,
                    highlightedText: object.content,
                    style: ["kind":"color", "type":"builtin", "which":FolioReaderHighlightStyle.classForStyleCalibre(object.type)],
                    spineName: object.spineName,
                    spineIndex: object.page - 1,
                    tocFamilyTitles: object.tocFamilyTitles.map { $0 },
                    notes: object.noteForHighlight
                )
            }
        print("highlight all \(highlights)")
        
        return highlights
    }
    
    // Used for syncing with calibre server
    func folioReaderHighlight(bookId: String, added highlights: [CalibreBookAnnotationEntry]) {
//        print("highlight added \(highlights)")
        
        try? realm?.write {
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = .withInternetDateTime.union(.withFractionalSeconds)
            
            highlights.forEach { hl in
                guard hl.type == "highlight",
                      let highlightId = uuidCalibreToFolio(hl.uuid),
                      let date = dateFormatter.date(from: hl.timestamp)
                else { return }
                if hl.uuid == "54dCT6cLoomi4hlUFUoxAA" {
                    print()
                }
                guard hl.removed != true else {
                    if let object = realm?.object(ofType: FolioReaderHighlightRealm.self, forPrimaryKey: highlightId), object.date <= date + 0.1 {
                        object.removed = true
                        object.date = date
                    }
                    return
                }
                
                guard let spineIndex = hl.spineIndex else { return }
                
                if let object = realm?.object(ofType: FolioReaderHighlightRealm.self, forPrimaryKey: highlightId) {
                    if object.date <= date + 0.1 {
                        object.date = date
                        object.type = FolioReaderHighlightStyle.styleForClass(hl.style?["which"] ?? "yellow").rawValue
                        object.noteForHighlight = hl.notes
                        object.removed = false
                    }
                } else {
                    let highlightRealm = FolioReaderHighlightRealm()
                    
                    highlightRealm.bookId = bookId
                    highlightRealm.content = hl.highlightedText
                    highlightRealm.contentPost = ""
                    highlightRealm.contentPre = ""
                    highlightRealm.date = date
                    highlightRealm.highlightId = highlightId
                    highlightRealm.page = spineIndex + 1
                    highlightRealm.type = FolioReaderHighlightStyle.styleForClass(hl.style?["which"] ?? "yellow").rawValue
                    highlightRealm.startOffset = 0
                    highlightRealm.endOffset = 0
                    highlightRealm.noteForHighlight = hl.notes
                    highlightRealm.cfiStart = hl.startCfi
                    highlightRealm.cfiEnd = hl.endCfi
                    highlightRealm.spineName = hl.spineName
                    if let tocFamilyTitles = hl.tocFamilyTitles {
                        highlightRealm.tocFamilyTitles.append(objectsIn: tocFamilyTitles)
                    }
                    
                    realm?.add(highlightRealm, update: .all)
                }
            }

        }
    }
    
}

@available(*, deprecated, message: "replaced by BookDeviceReadingPositionRealm")
class FolioReaderReadPositionRealm: Object {
    @objc open dynamic var bookId: String?
    @objc open dynamic var deviceId: String?
    @objc open dynamic var structuralStyle: Int = FolioReaderStructuralStyle.atom.rawValue
    @objc open dynamic var positionTrackingStyle: Int = FolioReaderPositionTrackingStyle.linear.rawValue
    
    /**
     .atom: should be 0
     .topic: should be equal to pageNumber
     .bundle: top level book toc pageNumer
     */
    @objc open dynamic var structuralRootPageNumber: Int = 0
    
    @objc open dynamic var pageNumber: Int = 1   //counting from 1
    @objc open dynamic var cfi: String?
    
    @objc open dynamic var maxPage: Int = 1
    @objc open dynamic var pageOffsetX: Double = .zero
    @objc open dynamic var pageOffsetY: Double = .zero
    
    @objc open dynamic var chapterProgress: Double = .zero
    @objc open dynamic var chapterName: String = "Untitled Chapter"
    @objc open dynamic var bookProgress: Double = .zero
    @objc open dynamic var bookName: String = ""
    @objc open dynamic var bundleProgress: Double = .zero
    
    @objc open dynamic var epoch: Date = Date()
    
    @objc open dynamic var takePrecedence: Bool = false
    
    func fromReadPosition(_ position: FolioReaderReadPosition, bookId: String) {
        self.bookId = bookId
        self.deviceId = position.deviceId
        self.structuralStyle = position.structuralStyle.rawValue
        self.positionTrackingStyle = position.positionTrackingStyle.rawValue
        self.structuralRootPageNumber = position.structuralRootPageNumber
        
        self.pageNumber = position.pageNumber
        self.cfi = position.cfi
        
        self.maxPage = position.maxPage
        self.pageOffsetX = position.pageOffset.x
        self.pageOffsetY = position.pageOffset.y
        
        self.chapterProgress = position.chapterProgress
        self.chapterName = position.chapterName
        self.bookProgress = position.bookProgress
        self.bookName = position.bookName
        self.bundleProgress = position.bundleProgress
        
        self.epoch = position.epoch
        
        self.takePrecedence = position.takePrecedence
    }
    
    func toReadPosition() -> FolioReaderReadPosition? {
        guard let deviceId = deviceId,
              let cfi = cfi,
              let structuralStyle = FolioReaderStructuralStyle(rawValue: self.structuralStyle),
              let positionTrackingStyle = FolioReaderPositionTrackingStyle(rawValue: self.positionTrackingStyle) else {
            return nil
        }

        let position = FolioReaderReadPosition(
            deviceId: deviceId,
            structuralStyle: structuralStyle,
            positionTrackingStyle: positionTrackingStyle,
            structuralRootPageNumber: structuralRootPageNumber,
            pageNumber: pageNumber,
            cfi: cfi
        )
        
        position.maxPage = self.maxPage
        position.pageOffset = CGPoint(x: self.pageOffsetX, y: self.pageOffsetY)
        
        position.chapterProgress = self.chapterProgress
        position.chapterName = self.chapterName
        position.bookProgress = self.bookProgress
        position.bookName = self.bookName
        position.bundleProgress = self.bundleProgress
        
        position.epoch = self.epoch
        position.takePrecedence = self.takePrecedence
        
        return position
    }
}

extension BookDeviceReadingPositionRealm {
    func fromFolioReaderReadPosition(_ position: FolioReaderReadPosition, bookId: String) {
        self.bookId = bookId
        self.id = position.deviceId
        
        self.readerName = ReaderType.YabrEPUB.rawValue
        self.maxPage = position.maxPage
        self.lastReadPage = position.pageNumber
        self.lastReadChapter = position.chapterName
        self.lastChapterProgress = position.chapterProgress
        self.lastProgress = position.bookProgress
        
        self.lastPosition.removeAll()
        self.lastPosition.append(objectsIn: [self.lastReadPage, Int(position.pageOffset.x), Int(position.pageOffset.y)])
        
        self.cfi = position.cfi
        self.epoch = position.epoch.timeIntervalSince1970
        
        self.structuralStyle = position.structuralStyle.rawValue
        self.structuralRootPageNumber = position.structuralRootPageNumber
        self.positionTrackingStyle = position.positionTrackingStyle.rawValue
        
        self.lastReadBook = position.bookName
        self.lastBundleProgress = position.bundleProgress
        
        self.takePrecedence = position.takePrecedence
    }
    
    func toFolioReaderReadPosition() -> FolioReaderReadPosition? {
        guard readerName == ReaderType.YabrEPUB.rawValue,
              let structuralStyle = FolioReaderStructuralStyle(rawValue: self.structuralStyle),
              let positionTrackingStyle = FolioReaderPositionTrackingStyle(rawValue: self.positionTrackingStyle) else {
            return nil
        }

        let position = FolioReaderReadPosition(deviceId: id, structuralStyle: structuralStyle, positionTrackingStyle: positionTrackingStyle, structuralRootPageNumber: structuralRootPageNumber, pageNumber: lastReadPage, cfi: cfi)
        
        position.maxPage = self.maxPage
        position.pageOffset = CGPoint(x: self.lastPosition[1], y: self.lastPosition[2])
        
        position.chapterProgress = self.lastChapterProgress
        position.chapterName = self.lastReadChapter
        position.bookProgress = self.lastProgress
        position.bookName = self.lastReadBook
        position.bundleProgress = self.lastBundleProgress
        
        position.epoch = Date(timeIntervalSince1970: self.epoch)
        position.takePrecedence = self.takePrecedence
        
        return position
    }
}

public class FolioReaderRealmReadPositionProvider: FolioReaderReadPositionProvider {
    let realm: Realm?

    init(realmConfig: Realm.Configuration) {
        realm = try? Realm(configuration: realmConfig)
    }
    
    public func folioReaderReadPosition(_ folioReader: FolioReader, bookId: String) -> FolioReaderReadPosition? {
        if let position = realm?.objects(BookDeviceReadingPositionRealm.self).filter(NSPredicate(format: "bookId = %@ AND takePrecedence = true", bookId)).sorted(byKeyPath: "epoch", ascending: false).first?.toFolioReaderReadPosition() {
            return position
        }
        return realm?.objects(BookDeviceReadingPositionRealm.self).filter(NSPredicate(format: "bookId = %@", bookId)).sorted(byKeyPath: "epoch", ascending: false).compactMap{ $0.toFolioReaderReadPosition() }.first
    }
    
    public func folioReaderReadPosition(_ folioReader: FolioReader, bookId: String, by rootPageNumber: Int) -> FolioReaderReadPosition? {
        let objects = realm?.objects(BookDeviceReadingPositionRealm.self)
            .filter(NSPredicate(
                format: "bookId = %@ AND structuralStyle = %@ AND positionTrackingStyle = %@ AND structuralRootPageNumber = %@",
                bookId,
                NSNumber(value: folioReader.structuralStyle.rawValue),
                NSNumber(value: folioReader.structuralTrackingTocLevel.rawValue),
                NSNumber(value: rootPageNumber)
            ))
        
        return objects?.max(by: { $0.epoch < $1.epoch })?.toFolioReaderReadPosition()
    }
    
    public func folioReaderReadPosition(_ folioReader: FolioReader, bookId: String, set readPosition: FolioReaderReadPosition, completion: Completion?) {
        try? realm?.write {
            if let existing = realm?.objects(BookDeviceReadingPositionRealm.self)
                .filter(NSPredicate(
                    format: "bookId = %@ AND id = %@ AND structuralStyle = %@ AND positionTrackingStyle = %@ AND structuralRootPageNumber = %@",
                    bookId,
                    readPosition.deviceId,
                    NSNumber(value: readPosition.structuralStyle.rawValue),
                    NSNumber(value: readPosition.positionTrackingStyle.rawValue),
                    NSNumber(value: readPosition.structuralRootPageNumber)
                )),
               existing.isEmpty == false {
                existing.forEach {
                    guard $0.epoch < readPosition.epoch.timeIntervalSince1970 || $0.takePrecedence != readPosition.takePrecedence else { return }
                    $0.fromFolioReaderReadPosition(readPosition, bookId: bookId)
                }
                
            } else {
                let object = BookDeviceReadingPositionRealm()
                object.fromFolioReaderReadPosition(readPosition, bookId: bookId)
                realm?.add(object)
            }
        }
    }
    
    public func folioReaderReadPosition(_ folioReader: FolioReader, bookId: String, remove readPosition: FolioReaderReadPosition) {
        try? realm?.write {
            if let existing = realm?.objects(BookDeviceReadingPositionRealm.self)
                .filter(NSPredicate(
                    format: "bookId = %@ AND id = %@ AND structuralStyle = %@ AND positionTrackingStyle = %@ AND structuralRootPageNumber = %@",
                    bookId,
                    readPosition.deviceId,
                    NSNumber(value: readPosition.structuralStyle.rawValue),
                    NSNumber(value: readPosition.positionTrackingStyle.rawValue),
                    NSNumber(value: readPosition.structuralRootPageNumber)
                )),
               existing.isEmpty == false {
                realm?.delete(existing)
            }
        }
    }
    
    public func folioReaderReadPosition(_ folioReader: FolioReader, bookId: String, getById deviceId: String) -> [FolioReaderReadPosition] {
        return realm?.objects(BookDeviceReadingPositionRealm.self).filter(NSPredicate(format: "bookId = %@ AND id = %@", bookId, deviceId)).compactMap { $0.toFolioReaderReadPosition() } ?? []
    }
    
    public func folioReaderReadPosition(_ folioReader: FolioReader, allByBookId bookId: String) -> [FolioReaderReadPosition] {
        return realm?.objects(BookDeviceReadingPositionRealm.self).filter(NSPredicate(format: "bookId = %@", bookId)).compactMap { $0.toFolioReaderReadPosition() } ?? []
    }
    
    public func folioReaderReadPosition(_ folioReader: FolioReader) -> [FolioReaderReadPosition] {
        return realm?.objects(BookDeviceReadingPositionRealm.self).compactMap { $0.toFolioReaderReadPosition() } ?? []
    }
}
