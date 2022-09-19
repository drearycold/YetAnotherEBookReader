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
                  let realmConfig = getBookPreferenceConfig(book: book, format: format),
                  let profileRealmConfig = modelData?.realmConf
                  else { return FolioReaderDummyPreferenceProvider(folioReader) }
            let preferenceProvider = FolioReaderRealmPreferenceProvider(folioReader, realmConfig: realmConfig, profileRealmConfig: profileRealmConfig)
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
            
            provider.realm?.objects(FolioReaderReadPositionRealm.self)
                .filter(NSPredicate(format: "maxPage > %@", NSNumber(1)))
                .compactMap { $0.toReadPosition() }.forEach { oldObject in
                provider.folioReaderReadPosition(folioReader, bookId: bookId, set: oldObject, completion: nil)
            }
            
            self.folioReaderReadPositionProvider = provider
            
            return provider
        }
    }

    func folioReaderBookmarkProvider(_ folioReader: FolioReader) -> FolioReaderBookmarkProvider {
        if let bookmarkProvider = folioReaderBookmarkProvider {
            return bookmarkProvider
        } else {
            guard let book = modelData?.readingBook,
                  let format = modelData?.readerInfo?.format,
                  let realmConfig = getBookPreferenceConfig(book: book, format: format)
                  else { return FolioReaderNaiveBookmarkProvider() }
            let bookmarkProvider = FolioReaderRealmBookmarkProvider(realmConfig: realmConfig)
            self.folioReaderBookmarkProvider = bookmarkProvider
            
            return bookmarkProvider
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
    
    @objc dynamic var currentNavigationMenuIndex: Int = .min
    @objc dynamic var currentAnnotationMenuIndex: Int = .min
    @objc dynamic var currentNavigationBookListStyle: Int = .min
    
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
    @objc dynamic var structuralStyle: Int = 0
    @objc dynamic var structuralTocLevel: Int = 0
    
    func copyFrom(src: FolioReaderPreferenceRealm) {
        nightMode = src.nightMode
        themeMode = src.themeMode
        
        currentFont = src.currentFont
        currentFontSize = src.currentFontSize
        currentFontWeight = src.currentFontWeight
        
        //skipping currentAudioRate
        //skipping currentHighlightStyle
        //skipping currentMediaOverlayStyle
        
        currentScrollDirection = src.currentScrollDirection
        
        //skipping currentMenuIndex
        
        currentVMarginLinked = src.currentVMarginLinked
        currentMarginTop = src.currentMarginTop
        currentMarginBottom = src.currentMarginBottom
        
        currentHMarginLinked = src.currentHMarginLinked
        currentMarginLeft = src.currentMarginLeft
        currentMarginRight = src.currentMarginRight
        
        currentLetterSpacing = src.currentLetterSpacing
        currentLineHeight = src.currentLineHeight
        currentTextIndent = src.currentTextIndent
        
        doWrapPara = src.doWrapPara
        doClearClass = src.doClearClass
        
        //skipping styleOverride
        //skipping structuralStyle
        //skipping structuralTocLevel
    }
}

class FolioReaderRealmPreferenceProvider: FolioReaderPreferenceProvider {
    let folioReader: FolioReader
    
    let realm: Realm?
    let profileRealm: Realm?
    
    var prefObj: FolioReaderPreferenceRealm!
    
    init(_ folioReader: FolioReader, realmConfig: Realm.Configuration, profileRealmConfig: Realm.Configuration) {
        self.folioReader = folioReader
        realm = try? Realm(configuration: realmConfig)
        profileRealm = try? Realm(configuration: profileRealmConfig)
        
        guard let realm = realm else { return }
        
        if let profileRealm = profileRealm,
           profileRealm.object(ofType: FolioReaderPreferenceRealm.self, forPrimaryKey: "Default") == nil {
            let defaultProfile = FolioReaderPreferenceRealm()
            defaultProfile.id = "Default"
            
            defaultProfile.nightMode = false
            defaultProfile.themeMode = FolioReaderThemeMode.serpia.rawValue
            
            defaultProfile.currentFont = "Georgia"
            defaultProfile.currentFontSize = FolioReader.DefaultFontSize
            defaultProfile.currentFontWeight = FolioReader.DefaultFontWeight
            
            //skipping currentAudioRate
            //skipping currentHighlightStyle
            //skipping currentMediaOverlayStyle
            
            //skipping currentScrollDirection
            
            //skipping currentMenuIndex
            
            defaultProfile.currentVMarginLinked = true
            //defaultProfile.currentMarginTop
            //defaultProfile.currentMarginBottom
            
            defaultProfile.currentHMarginLinked = true
            //defaultProfile.currentMarginLeft
            //defaultProfile.currentMarginRight
            
            defaultProfile.currentLetterSpacing = FolioReader.DefaultLetterSpacing
            defaultProfile.currentLineHeight = FolioReader.DefaultLineHeight
            defaultProfile.currentTextIndent = FolioReader.DefaultTextIndent
            
            defaultProfile.doWrapPara = false
            defaultProfile.doClearClass = true
            
            //skipping styleOverride
            //skipping structuralStyle
            //skipping structuralTocLevel
            
            try? profileRealm.write {
                profileRealm.add(defaultProfile)
            }
        }
    
        let id = folioReader.readerConfig?.identifier ?? "Unidentified"
        let id2 = id + ".epub"
        
        prefObj = realm.objects(FolioReaderPreferenceRealm.self).filter(
            NSPredicate(format: "id = %@", id)
        ).first ?? realm.objects(FolioReaderPreferenceRealm.self).filter(
            NSPredicate(format: "id = %@", id2)
        ).first
        
        if prefObj == nil {
            let newPrefObj = FolioReaderPreferenceRealm()
            newPrefObj.id = id
            
            if let defaultProfile = profileRealm?.object(ofType: FolioReaderPreferenceRealm.self, forPrimaryKey: "Default") {
                newPrefObj.copyFrom(src: defaultProfile)
            }
            
            if newPrefObj.currentMarginTop == .min {
                newPrefObj.currentMarginTop = folioReader.defaultMarginTop
            }
            if newPrefObj.currentMarginBottom == .min {
                newPrefObj.currentMarginBottom = folioReader.defaultMarginBottom
            }
            if newPrefObj.currentMarginLeft == .min {
                newPrefObj.currentMarginLeft = folioReader.defaultMarginLeft
            }
            if newPrefObj.currentMarginRight == .min {
                newPrefObj.currentMarginRight = folioReader.defaultMarginRight
            }
            if newPrefObj.currentScrollDirection == .min {
                newPrefObj.currentScrollDirection = folioReader.defaultScrollDirection.rawValue
            }
            
            prefObj = newPrefObj
            
            try? realm.write {
                realm.add(newPrefObj, update: .all)
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
    
    func preference(currentNavigationMenuIndex defaults: Int) -> Int {
        return value(of: prefObj?.currentNavigationMenuIndex, defaults: defaults)
    }
    
    func preference(setCurrentNavigationMenuIndex value: Int) {
        try? realm?.write { prefObj?.currentNavigationMenuIndex = value }
    }
    
    func preference(currentAnnotationMenuIndex defaults: Int) -> Int {
        return value(of: prefObj?.currentAnnotationMenuIndex, defaults: defaults)
    }
    
    func preference(setCurrentAnnotationMenuIndex value: Int) {
        try? realm?.write { prefObj?.currentAnnotationMenuIndex = value }
    }
    
    func preference(currentNavigationMenuBookListSyle defaults: Int) -> Int {
        return value(of: prefObj?.currentNavigationBookListStyle, defaults: defaults)
    }
    
    func preference(setCurrentNavigationMenuBookListStyle value: Int) {
        try? realm?.write { prefObj?.currentNavigationBookListStyle = value}
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
    
    func preference(loadProfile name: String) {
        guard let profile = profileRealm?.object(ofType: FolioReaderPreferenceRealm.self, forPrimaryKey: name)
        else { return }
        
        try? realm?.write {
            prefObj?.copyFrom(src: profile)
        }
    }
    
    func preference(saveProfile name: String) {
        guard let prefObj = prefObj,
              let profileRealm = profileRealm else {
            return
        }

        var profile: FolioReaderPreferenceRealm!
        profile = profileRealm.object(ofType: FolioReaderPreferenceRealm.self, forPrimaryKey: name)
        if profile == nil {
            profile = FolioReaderPreferenceRealm()
            profile.id = name
            try? profileRealm.write {
                profileRealm.add(profile)
            }
        }
        
        try? profileRealm.write {
            profile.copyFrom(src: prefObj)
        }
    }
    
    func preference(listProfile filter: String?) -> [String] {
        return profileRealm?.objects(FolioReaderPreferenceRealm.self).filter {
            filter == nil || $0.id.contains(filter!)
        }.map {
            $0.id
        } ?? []
    }
    
    func preference(removeProfile name: String) {
        guard let profileRealm = profileRealm,
              let object = profileRealm.object(ofType: FolioReaderPreferenceRealm.self, forPrimaryKey: name)
        else {
            return
        }

        try? profileRealm.write {
            profileRealm.delete(object)
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
    
    func folioReaderHighlight(bookId: String) -> [CalibreBookAnnotationHighlightEntry] {
        print("highlight all")
        
        guard let realm = realm else { return [] }
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = .withInternetDateTime.union(.withFractionalSeconds)
        
        let highlights:[CalibreBookAnnotationHighlightEntry] = realm.objects(FolioReaderHighlightRealm.self)
            .filter(NSPredicate(format: "bookId = %@", bookId))
            .compactMap { object -> CalibreBookAnnotationHighlightEntry? in
                guard let highlightId = object.highlightId,
                      let uuid = uuidFolioToCalibre(highlightId),
                      let cfiStart = object.cfiStart,
                      let cfiEnd = object.cfiEnd
                else { return nil }
                return CalibreBookAnnotationHighlightEntry(
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
    func folioReaderHighlight(bookId: String, added highlights: [CalibreBookAnnotationHighlightEntry]) -> Int {
//        print("highlight added \(highlights)")
        
        var pending = realm?.objects(FolioReaderHighlightRealm.self).count ?? 0
        try? realm?.write {
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = .withInternetDateTime.union(.withFractionalSeconds)
            
            highlights.forEach { hl in
                guard hl.type == "highlight",
                      let highlightId = uuidCalibreToFolio(hl.uuid),
                      let date = dateFormatter.date(from: hl.timestamp)
                else { return }
                
                guard hl.removed != true else {
                    if let object = realm?.object(ofType: FolioReaderHighlightRealm.self, forPrimaryKey: highlightId) {
                        if object.date <= date + 0.1 {
                            object.removed = true
                            object.date = date
                            pending -= 1
                        } else if date <= object.date + 0.1 {
                            
                        } else {
                            pending -= 1
                        }
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
                        pending -= 1
                    } else if date <= object.date + 0.1 {
                        
                    } else {
                        pending -= 1
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
    
        return pending
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
        guard readerName == ReaderType.YabrEPUB.rawValue else {
            return nil
        }

        let position = FolioReaderReadPosition(
            deviceId: id,
            structuralStyle: FolioReaderStructuralStyle(rawValue: structuralStyle) ?? .atom,
            positionTrackingStyle: FolioReaderPositionTrackingStyle(rawValue: positionTrackingStyle) ?? .linear,
            structuralRootPageNumber: structuralRootPageNumber,
            pageNumber: lastReadPage,
            cfi: cfi
        )
        
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

extension BookDeviceReadingPositionHistoryRealm {
    func toFolioReaderReadPositionHistory() -> FolioReaderReadPositionHistory {
        let history = FolioReaderReadPositionHistory()
        history.startDatetime = self.startDatetime
        history.startPosition = self.startPosition?.toFolioReaderReadPosition()
        history.endPosition = self.endPosition?.toFolioReaderReadPosition()
        return history
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
    
    public func folioReaderPositionHistory(_ folioReader: FolioReader, bookId: String) -> [FolioReaderReadPositionHistory] {
        return realm?.objects(BookDeviceReadingPositionHistoryRealm.self)
            .filter(NSPredicate(format: "bookId = %@", bookId))
            .map { $0.toFolioReaderReadPositionHistory() } ?? []
    }
    
    public func folioReaderPositionHistory(_ folioReader: FolioReader, bookId: String, start readPosition: FolioReaderReadPosition) {
        guard let realm = realm else {
            return
        }

        let startDatetime = Date()
        
        let historyEntryFirst = realm.objects(BookDeviceReadingPositionHistoryRealm.self)
            .filter(NSPredicate(format: "bookId = %@", bookId))
            .sorted(by: [SortDescriptor(keyPath: "startDatetime", ascending: false)])
            .first
        
        try? realm.write {
            if let endPosition = historyEntryFirst?.endPosition, startDatetime.timeIntervalSince1970 < endPosition.epoch + 60 {
                historyEntryFirst?.endPosition = nil
            } else if let startPosition = historyEntryFirst?.startPosition, startDatetime.timeIntervalSince1970 < startPosition.epoch + 300 {
                historyEntryFirst?.endPosition = nil
            } else {
                let historyEntry = BookDeviceReadingPositionHistoryRealm()
                historyEntry.bookId = bookId
                historyEntry.startDatetime = startDatetime
                historyEntry.startPosition = .init()
                historyEntry.startPosition?.fromFolioReaderReadPosition(readPosition, bookId: "\(bookId) - History")
                realm.add(historyEntry)
            }
        }
    }
    
    public func folioReaderPositionHistory(_ folioReader: FolioReader, bookId: String, finish readPosition: FolioReaderReadPosition) {
        guard let realm = realm else {
            return
        }

        guard let historyEntry = realm.objects(BookDeviceReadingPositionHistoryRealm.self).filter(
            NSPredicate(format: "bookId = %@", bookId)
        ).sorted(by: [SortDescriptor(keyPath: "startDatetime", ascending: false)]).first else { return }
        
        guard historyEntry.endPosition == nil else { return }
        
        try? realm.write {
            historyEntry.endPosition = .init()
            historyEntry.endPosition?.fromFolioReaderReadPosition(readPosition, bookId: "\(bookId) - History")
        }
    }
}

fileprivate extension BookBookmarkRealm {
    func fromFolioReaderBookmark(_ bookmark: FolioReaderBookmark) {
        self.bookId = bookmark.bookId
        self.page = bookmark.page
        
        self.pos_type = bookmark.pos_type ?? ""
        self.pos = bookmark.pos ?? ""
        
        self.title = bookmark.title
        self.date = bookmark.date
        
        self.removed = false
    }
    
    func toFolioReaderBookmark() -> FolioReaderBookmark {
        let bookmark = FolioReaderBookmark()
        bookmark.bookId = self.bookId
        bookmark.page = self.page
        
        bookmark.pos_type = self.pos_type
        bookmark.pos = self.pos
        
        bookmark.title = self.title
        bookmark.date = self.date
        
        return bookmark
    }
}

public class FolioReaderRealmBookmarkProvider: FolioReaderBookmarkProvider {
    let realm: Realm?

    let dateFormatter = ISO8601DateFormatter()

    init(realmConfig: Realm.Configuration) {
        self.realm = try? Realm(configuration: realmConfig)
        dateFormatter.formatOptions = .withInternetDateTime.union(.withFractionalSeconds)
    }
    
    public func folioReaderBookmark(_ folioReader: FolioReader, added bookmark: FolioReaderBookmark, completion: Completion?) {
        var error: FolioReaderBookmarkError? = nil
        defer {
            completion?(error as NSError?)
        }
        
        guard let realm = self.realm else {
            error = FolioReaderBookmarkError.runtimeError("Realm Provider Error")
            return
        }
        
        guard let pos = bookmark.pos else {
            error = FolioReaderBookmarkError.emptyError("")
            return
        }
        
        if let existing = folioReaderBookmark(folioReader, getBy: pos) {
            error = FolioReaderBookmarkError.duplicateError(existing.title)
            return
        }
        
        do {
            try realm.write {
                let bookmarkRealm = BookBookmarkRealm()
                bookmarkRealm.fromFolioReaderBookmark(bookmark)
                realm.add(bookmarkRealm)
            }
        } catch let e as NSError {
            print("Error on persist highlight: \(e)")
            error = FolioReaderBookmarkError.runtimeError("Realm Provider Error")
        }
    }
    
    public func folioReaderBookmark(_ folioReader: FolioReader, removed bookmarkPos: String) {
        guard let realm = realm,
              let bookId = folioReader.readerConfig?.identifier else {
            return
        }
        
        try? realm.write {
            realm.objects(BookBookmarkRealm.self).filter(NSPredicate(format: "bookId = %@ AND pos = %@ AND removed != true", bookId, bookmarkPos)).forEach {
                $0.date = .init()
                $0.removed = true
            }
        }
    }
    
    public func folioReaderBookmark(_ folioReader: FolioReader, updated bookmarkPos: String, title: String) {
        guard let realm = realm,
              let bookId = folioReader.readerConfig?.identifier else {
            return
        }
        
        try? realm.write {
            realm.objects(BookBookmarkRealm.self).filter(NSPredicate(format: "bookId = %@ AND pos = %@ AND removed != true", bookId, bookmarkPos)).forEach {
                $0.date = .init()
                $0.title = title
            }
        }
    }
    
    public func folioReaderBookmark(_ folioReader: FolioReader, getBy bookmarkPos: String) -> FolioReaderBookmark? {
        guard let realm = realm,
              let bookId = folioReader.readerConfig?.identifier else {
            return nil
        }
        
        return realm.objects(BookBookmarkRealm.self)
            .filter(NSPredicate(format: "bookId = %@ AND pos = %@ AND removed != true", bookId, bookmarkPos))
            .first?
            .toFolioReaderBookmark()
    }
    
    public func folioReaderBookmark(_ folioReader: FolioReader, allByBookId bookId: String, andPage page: NSNumber?) -> [FolioReaderBookmark] {
        guard let realm = realm else {
            return []
        }
        
        let objects = realm.objects(BookBookmarkRealm.self)
            .filter(NSPredicate(format: "bookId = %@ AND removed != true", bookId))
            .filter{ page == nil || $0.page == page?.intValue }
        
        return objects.map { $0.toFolioReaderBookmark() }
    }
    
    public func folioReaderBookmark(_ folioReader: FolioReader) -> [FolioReaderBookmark] {
        guard let realm = realm else {
            return []
        }
        return realm.objects(BookBookmarkRealm.self).map { $0.toFolioReaderBookmark() }
    }
}

extension FolioReaderRealmBookmarkProvider {
    
    func folioReaderBookmark(bookId: String) -> [CalibreBookAnnotationBookmarkEntry] {
        print("bookmark all")
        
        guard let realm = realm else { return [] }
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = .withInternetDateTime.union(.withFractionalSeconds)
        
        let bookmarks:[CalibreBookAnnotationBookmarkEntry] = realm.objects(BookBookmarkRealm.self)
            .filter(NSPredicate(format: "bookId = %@", bookId))
            .compactMap { object -> CalibreBookAnnotationBookmarkEntry? in
                return CalibreBookAnnotationBookmarkEntry(
                    type: "bookmark",
                    timestamp: dateFormatter.string(from: object.date),
                    pos_type: object.pos_type,
                    pos: object.pos,
                    title: object.title,
                    removed: object.removed
                )
            }
        print("bookmark all \(bookmarks)")
        
        return bookmarks
    }
    
    // Used for syncing with calibre server
    func folioReaderBookmark(bookId: String, added bookmarks: [CalibreBookAnnotationBookmarkEntry]) -> Int {
//        print("highlight added \(highlights)")
        guard let realm = realm else { return 0 }
        
        let bookObjects = realm.objects(BookBookmarkRealm.self)
            .filter(NSPredicate(format: "bookId = %@", bookId))
        
        var pending = bookObjects
            .reduce(into: Set<String>()) { partialResult, object in
                partialResult.insert(object.pos)
            }
        
        let bookmarksByPos = bookmarks.reduce(into: [String: [CalibreBookAnnotationBookmarkEntry]]()) { partialResult, entry in
            guard entry.type == "bookmark",
                  let date = dateFormatter.date(from: entry.timestamp)
            else { return }
            
            if partialResult[entry.pos] != nil {
                partialResult[entry.pos]?.append(entry)
            } else {
                partialResult[entry.pos] = [entry]
            }
        }.map { posEntry in
            (key: posEntry.key, value: posEntry.value.sorted(by: { lhs, rhs in
                (dateFormatter.date(from: lhs.timestamp) ?? .distantPast) > (dateFormatter.date(from: rhs.timestamp) ?? .distantPast)
            }))
        }
        
        try? realm.write {
            bookmarksByPos.forEach { pos, entries in
                guard let entryNewest = entries.first,
                      let entryNewestDate = dateFormatter.date(from: entryNewest.timestamp) else { return }
                
                let objects = bookObjects
                    .filter(NSPredicate(format: "pos = %@", pos))
                    .sorted(byKeyPath: "date", ascending: false)
                
                let objectsVisible = objects.filter(NSPredicate(format: "removed != true"))
                
                if let objectNewest = objects.first {
                    if objectNewest.date == entryNewestDate
                        || (
                            (objectNewest.date < entryNewestDate + 0.1)
                            &&
                            (entryNewestDate < objectNewest.date + 0.1)
                        ) {
                        //same date, ignore server one
                        pending.remove(pos)
                    } else if objectNewest.date < entryNewestDate + 0.1 {
                        //server has newer entry, remove all local entries
                        while( objectsVisible.isEmpty == false ) {
                            objectsVisible.first?.date += 0.001
                            objectsVisible.first?.removed = true
                        }
                        pending.remove(pos)
                    } else if entryNewestDate < objectNewest.date + 0.1 {
                        //local has newer entry, ignore server one
                    } else {
                        //same date, ignore server one
                        pending.remove(pos)
                    }
                }
                
                guard objectsVisible.isEmpty,
                      entryNewest.removed != true
                else {
                    // only insert newest visible entry
                    // either local has no corresponding entry,
                    // or we have removed all existing ones (which means they are older)
                    return
                }
                
                let object = BookBookmarkRealm()
                object.bookId = bookId
                
                object.pos_type = entryNewest.pos_type
                object.pos = entryNewest.pos
                
                object.title = entryNewest.title
                object.date = entryNewestDate
                object.removed = entryNewest.removed ?? false
                
                guard object.pos_type == "epubcfi",
                      object.pos.starts(with: "epubcfi(/") else { return }
                let firstStepStartIndex = object.pos.index(object.pos.startIndex, offsetBy: 9)
                guard let firstStepEndIndex = object.pos[firstStepStartIndex..<object.pos.endIndex].firstIndex(where: { elem in
                    elem == "/" || elem == ")"
                }) else { return }
                
                guard let firstStep = Int(object.pos[firstStepStartIndex..<firstStepEndIndex]) else { return }
                object.page = firstStep / 2
                
                realm.add(object)
            }
        }
    
        return pending.count
    }
    
}
