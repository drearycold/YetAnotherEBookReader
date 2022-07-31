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
    
    private func value(of: Int?, defaults: Int) -> Int {
        if let v = of, v != .min {
            return v
        } else {
            return defaults
        }
    }
}

class FolioReaderHighlightRealm: Object {
    @objc open dynamic var bookId: String!
    @objc open dynamic var content: String!
    @objc open dynamic var contentPost: String!
    @objc open dynamic var contentPre: String!
    @objc open dynamic var date: Date!
    @objc open dynamic var highlightId: String!
    @objc open dynamic var page: Int = 0
    @objc open dynamic var type: Int = 0
    @objc open dynamic var startOffset: Int = -1
    @objc open dynamic var endOffset: Int = -1
    @objc open dynamic var noteForHighlight: String?
    @objc open dynamic var cfiStart: String?
    @objc open dynamic var cfiEnd: String?
    @objc open dynamic var spineName: String?
    open dynamic var tocFamilyTitles = List<String>()

    override open class func primaryKey()-> String {
        return "highlightId"
    }
    
    func fromHighlight(_ highlight: Highlight) {
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
    }
    
    func toHighlight() -> Highlight {
        let highlight = Highlight()
        highlight.bookId = bookId
        highlight.content = content
        highlight.contentPost = contentPost
        highlight.contentPre = contentPre
        highlight.date = date
        highlight.highlightId = highlightId
        highlight.page = page
        highlight.type = type
        highlight.style = HighlightStyle.classForStyle(type)
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
    
    public func folioReaderHighlight(_ folioReader: FolioReader, added highlight: Highlight, completion: Completion?) {
        print("highlight added \(highlight)")
        
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
        print("highlight removed \(highlightId)")
        
        guard let realm = realm else { return }
        
        do {
            guard let highlightRealm = realm.objects(FolioReaderHighlightRealm.self).filter(
                    NSPredicate(format:"highlightId = %@", highlightId)
            ).toArray(FolioReaderHighlightRealm.self).first else { return }
            
            try realm.write {
                realm.delete(highlightRealm)
            }
        } catch let error as NSError {
            print("Error on remove highlight by id: \(error)")
        }
    }
    
    public func folioReaderHighlight(_ folioReader: FolioReader, updateById highlightId: String, type style: HighlightStyle) {
        print("highlight updated \(highlightId) \(style)")

        guard let realm = realm else { return }
        do {
            guard let highlight = realm.objects(FolioReaderHighlightRealm.self).filter(
                NSPredicate(format:"highlightId = %@", highlightId)
            ).toArray(FolioReaderHighlightRealm.self).first else { return }
            
            try realm.write {
                highlight.type = style.rawValue
            }
        } catch let error as NSError {
            print("Error on updateById: \(error)")
        }

    }

    public func folioReaderHighlight(_ folioReader: FolioReader, getById highlightId: String) -> Highlight? {
        print("highlight getById \(highlightId)")

        guard let realm = realm else { return nil }
        
        guard let highlightRealm = realm.objects(FolioReaderHighlightRealm.self).filter(
                NSPredicate(format:"highlightId = %@", highlightId)
        ).toArray(FolioReaderHighlightRealm.self).first else { return nil }
        
        return highlightRealm.toHighlight()
        
    }
    
    public func folioReaderHighlight(_ folioReader: FolioReader, allByBookId bookId: String, andPage page: NSNumber?) -> [Highlight] {
        print("highlight allByBookId \(bookId) \(page ?? 0)")

        guard let realm = realm else { return [] }

        var predicate = NSPredicate(format: "bookId = %@", bookId)
        if let page = page {
            predicate = NSPredicate(format: "bookId = %@ && page = %@", bookId, page)
        }

        let highlights:[Highlight] = realm.objects(FolioReaderHighlightRealm.self).filter(predicate).map {
            $0.toHighlight()
        }.sorted()
        print("highlight allByBookId \(highlights)")
        
        return highlights
        
    }

    public func folioReaderHighlight(_ folioReader: FolioReader) -> [Highlight] {
        print("highlight all")
        
        guard let realm = realm else { return [] }

        let highlights:[Highlight] = realm.objects(FolioReaderHighlightRealm.self).map {
            $0.toHighlight()
        }
        print("highlight all \(highlights)")
        
        return highlights
    }
    
    public func folioReaderHighlight(_ folioReader: FolioReader, saveNoteFor highlight: Highlight) {
        print("highlight saveNoteFor \(highlight)")

        guard let realm = realm else { return }
        do {
            guard let highlightRealm = realm.objects(FolioReaderHighlightRealm.self).filter(
                NSPredicate(format:"highlightId = %@", highlight.highlightId)
            ).toArray(FolioReaderHighlightRealm.self).first else { return }
        
            try realm.write {
                highlightRealm.noteForHighlight = highlight.noteForHighlight
                highlightRealm.date = Date()
            }
        } catch let error as NSError {
            print("Error on updateById: \(error)")
        }
        
    }
}

extension Results {
    func toArray<T>(_ ofType: T.Type) -> [T] {
        return compactMap { $0 as? T }
    }
}

extension FolioReaderRealmHighlightProvider {
    
    func folioReaderHighlight(bookId: String) -> [CalibreBookAnnotationEntry] {
        print("highlight all")
        
        guard let realm = realm else { return [] }
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = .withInternetDateTime.union(.withFractionalSeconds)
        
        let highlights = realm.objects(FolioReaderHighlightRealm.self)
            .filter(NSPredicate(format: "bookId = %@", bookId))
            .toArray(FolioReaderHighlightRealm.self)
            .compactMap { object -> CalibreBookAnnotationEntry? in
                guard let uuid = uuidFolioToCalibre(object.highlightId),
                      let cfiStart = object.cfiStart,
                      let cfiEnd = object.cfiEnd
                else { return nil }
                return CalibreBookAnnotationEntry(
                    type: "highlight",
                    timestamp: dateFormatter.string(from: object.date),
                    uuid: uuid,
                    removed: false,
                    startCfi: cfiStart,
                    endCfi: cfiEnd,
                    highlightedText: object.content,
                    style: ["kind":"color", "type":"builtin", "which":HighlightStyle.classForStyleCalibre(object.type)],
                    spineName: object.spineName,
                    spineIndex: object.page - 1,
                    tocFamilyTitles: object.tocFamilyTitles.map { $0 },
                    notes: object.noteForHighlight
                )
            }
        print("highlight all \(highlights)")
        
        return highlights
    }
    
    func folioReaderHighlight(bookId: String, added highlights: [CalibreBookAnnotationEntry]) {
        print("highlight added \(highlights)")
        
        guard let realm = self.realm else {
            return
        }
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = .withInternetDateTime.union(.withFractionalSeconds)
        
        highlights.forEach { hl in
            guard let highlightId = uuidCalibreToFolio(hl.uuid),
                  let date = dateFormatter.date(from: hl.timestamp),
                  let spineIndex = hl.spineIndex
                  else { return }
            
            let results = realm.objects(FolioReaderHighlightRealm.self).filter(
                    NSPredicate(format:"highlightId = %@", highlightId)
            )
            
            if results.isEmpty {
                let highlightRealm = FolioReaderHighlightRealm()

                highlightRealm.bookId = bookId
                highlightRealm.content = hl.highlightedText
                highlightRealm.contentPost = ""
                highlightRealm.contentPre = ""
                highlightRealm.date = date
                highlightRealm.highlightId = highlightId
                highlightRealm.page = spineIndex + 1
                highlightRealm.type = HighlightStyle.styleForClass(hl.style?["which"] ?? "yellow").rawValue
                highlightRealm.startOffset = 0
                highlightRealm.endOffset = 0
                highlightRealm.noteForHighlight = hl.notes
                highlightRealm.cfiStart = hl.startCfi
                highlightRealm.cfiEnd = hl.endCfi
                highlightRealm.spineName = hl.spineName
                if let tocFamilyTitles = hl.tocFamilyTitles {
                    highlightRealm.tocFamilyTitles.append(objectsIn: tocFamilyTitles)
                }
                try? realm.write {
                    realm.add(highlightRealm, update: .all)
                }
            } else if let highlightRealm = results.first, highlightRealm.date < date {
                try? realm.write {
                    highlightRealm.date = date
                    highlightRealm.type = HighlightStyle.styleForClass(hl.style?["which"] ?? "yellow").rawValue
                    highlightRealm.noteForHighlight = hl.notes
                }
            }
        }
            
    }
    
}
