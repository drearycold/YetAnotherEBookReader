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
                  let readerInfo = modelData?.readerInfo
                  else { return FolioReaderDummyHighlightProvider() }
            let highlightProvider = FolioReaderYabrHighlightProvider(book: book, readerInfo: readerInfo)
            self.folioReaderHighlightProvider = highlightProvider
            
            return highlightProvider
        }
    }
    
    func folioReaderReadPositionProvider(_ folioReader: FolioReader) -> FolioReaderReadPositionProvider {
        if let provider = folioReaderReadPositionProvider {
            return provider
        } else {
            guard let book = modelData?.readingBook,
                  let readerInfo = modelData?.readerInfo
                  else { return FolioReaderNaiveReadPositionProvider() }
            let provider = FolioReaderYabrReadPositionProvider(book: book, readerInfo: readerInfo)
            self.folioReaderReadPositionProvider = provider
            
            return provider
        }
    }

    func folioReaderBookmarkProvider(_ folioReader: FolioReader) -> FolioReaderBookmarkProvider {
        if let bookmarkProvider = folioReaderBookmarkProvider {
            return bookmarkProvider
        } else {
            guard let book = modelData?.readingBook,
                  let readerInfo = modelData?.readerInfo
                  else { return FolioReaderNaiveBookmarkProvider() }
            let bookmarkProvider = FolioReaderYabrBookmarkProvider(book: book, readerInfo: readerInfo)
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

@available(*, deprecated, message: "replaced by BookHighlightRealm")
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

public class FolioReaderYabrHighlightProvider: FolioReaderHighlightProvider {
    let book: CalibreBook
    let readerInfo: ReaderInfo
    
    init(book: CalibreBook, readerInfo: ReaderInfo) {
        self.book = book
        self.readerInfo = readerInfo
    }
    
    public func folioReaderHighlight(_ folioReader: FolioReader, added highlight: FolioReaderHighlight, completion: Completion?) {
//        print("highlight added \(highlight)")
        
//        var error: NSError? = nil
        defer {
            completion?(nil)
        }
        
        book.readPos.highlight(added: highlight.toBookHighlight())
    }
    
    public func folioReaderHighlight(_ folioReader: FolioReader, removedId highlightId: String) {
        book.readPos.highlight(removedId: highlightId)
    }
    
    public func folioReaderHighlight(_ folioReader: FolioReader, updateById highlightId: String, type style: FolioReaderHighlightStyle) {
        book.readPos.highlight(updateById: highlightId, type: style.rawValue)
    }

    public func folioReaderHighlight(_ folioReader: FolioReader, getById highlightId: String) -> FolioReaderHighlight? {
        book.readPos.highlight(getById: highlightId)?.toFolioReaderHighlight()
    }
    
    public func folioReaderHighlight(_ folioReader: FolioReader, allByBookId bookId: String, andPage page: NSNumber?) -> [FolioReaderHighlight] {
        book.readPos.highlights(allByBookId: bookId, andPage: page).compactMap {
            $0.toFolioReaderHighlight()
        }
    }

    public func folioReaderHighlight(_ folioReader: FolioReader) -> [FolioReaderHighlight] {
        book.readPos.highlights().compactMap { $0.toFolioReaderHighlight() }
    }
    
    public func folioReaderHighlight(_ folioReader: FolioReader, saveNoteFor highlight: FolioReaderHighlight) {
        book.readPos.highlights(saveNoteFor: highlight.highlightId, with: highlight.noteForHighlight)
    }
}

fileprivate extension BookHighlight {
    func toFolioReaderHighlight() -> FolioReaderHighlight? {
        guard readerName.isEmpty || readerName == ReaderType.YabrEPUB.rawValue
        else { return nil }
        
        let highlight = FolioReaderHighlight()
        highlight.bookId = bookId
        highlight.highlightId = highlightId
        
        highlight.page = page
        highlight.startOffset = startOffset
        highlight.endOffset = endOffset
        
        highlight.date = date
        highlight.type = type
        highlight.noteForHighlight = note
        
        highlight.tocFamilyTitles.append(contentsOf: tocFamilyTitles)
        highlight.content = content
        highlight.contentPost = contentPost
        highlight.contentPre = contentPre
        
        highlight.cfiStart = cfiStart
        highlight.cfiEnd = cfiEnd
        highlight.spineName = spineName
        
        highlight.style = FolioReaderHighlightStyle.classForStyle(type)
        
        return highlight
    }
}

fileprivate extension FolioReaderHighlight {
    func toBookHighlight() -> BookHighlight {
        BookHighlight(
            bookId: bookId,
            highlightId: highlightId,
            readerName: ReaderType.YabrEPUB.rawValue,
            page: page,
            startOffset: startOffset,
            endOffset: endOffset,
            date: date,
            type: type,
            note: noteForHighlight,
            tocFamilyTitles: tocFamilyTitles,
            content: content,
            contentPost: contentPost,
            contentPre: contentPre,
            cfiStart: cfiStart,
            cfiEnd: cfiEnd,
            spineName: spineName,
            ranges: nil
        )
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

extension BookDeviceReadingPosition {
    func toFolioReaderReadPosition() -> FolioReaderReadPosition {
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
        position.takePrecedence = false
        
        return position
    }
}

extension FolioReaderReadPosition {
    func toBookDeviceReadingPosition() -> BookDeviceReadingPosition {
        return BookDeviceReadingPosition(
            id: self.deviceId,
            readerName: ReaderType.YabrEPUB.rawValue,
            maxPage: self.maxPage,
            lastReadPage: self.pageNumber,
            lastReadChapter: self.chapterName,
            lastChapterProgress: self.chapterProgress,
            lastProgress: self.bookProgress,
            furthestReadPage: 0,
            furthestReadChapter: "",
            lastPosition: [self.pageNumber, Int(self.pageOffset.x), Int(self.pageOffset.y)],
            cfi: self.cfi,
            epoch: self.epoch.timeIntervalSince1970,
            structuralStyle: self.structuralStyle.rawValue,
            structuralRootPageNumber: self.structuralRootPageNumber,
            positionTrackingStyle: self.positionTrackingStyle.rawValue,
            lastReadBook: self.bookName,
            lastBundleProgress: self.bundleProgress
        )
    }
}

extension BookDeviceReadingPositionHistory {
    func toFolioReaderReadPositionHistory() -> FolioReaderReadPositionHistory {
        let history = FolioReaderReadPositionHistory()
        history.startDatetime = self.startDatetime
        history.startPosition = self.startPosition?.toFolioReaderReadPosition()
        history.endPosition = self.endPosition?.toFolioReaderReadPosition()
        return history
    }
}

public class FolioReaderYabrReadPositionProvider: FolioReaderReadPositionProvider {
    let book: CalibreBook
    let readerInfo: ReaderInfo
    
    init(book: CalibreBook, readerInfo: ReaderInfo) {
        self.book = book
        self.readerInfo = readerInfo
    }
    
    public func folioReaderReadPosition(_ folioReader: FolioReader, bookId: String) -> FolioReaderReadPosition? {
        guard book.readPos.bookPrefId == bookId else { return nil }
        
        return book.readPos.getPosition(nil)?.toFolioReaderReadPosition()
    }
    
    public func folioReaderReadPosition(_ folioReader: FolioReader, bookId: String, by rootPageNumber: Int) -> FolioReaderReadPosition? {
        guard book.readPos.bookPrefId == bookId else { return nil }

        return book.readPos.getDevices(by: ReaderType.YabrEPUB).first?.toFolioReaderReadPosition()
    }
    
    public func folioReaderReadPosition(_ folioReader: FolioReader, bookId: String, set readPosition: FolioReaderReadPosition, completion: Completion?) {
        guard book.readPos.bookPrefId == bookId else { return }
        
        book.readPos.updatePosition(readPosition.toBookDeviceReadingPosition())
    }
    
    public func folioReaderReadPosition(_ folioReader: FolioReader, bookId: String, remove readPosition: FolioReaderReadPosition) {
        guard book.readPos.bookPrefId == bookId else { return }
        
        book.readPos.removePosition(position: readPosition.toBookDeviceReadingPosition())
    }
    
    public func folioReaderReadPosition(_ folioReader: FolioReader, bookId: String, getById deviceId: String) -> [FolioReaderReadPosition] {
        
        return folioReaderReadPosition(folioReader, allByBookId: bookId).filter { $0.deviceId == deviceId }
    }
    
    public func folioReaderReadPosition(_ folioReader: FolioReader, allByBookId bookId: String) -> [FolioReaderReadPosition] {
        guard book.readPos.bookPrefId == bookId else { return [] }
        
        return book.readPos.getDevices().map { $0.toFolioReaderReadPosition() }
    }
    
    public func folioReaderReadPosition(_ folioReader: FolioReader) -> [FolioReaderReadPosition] {
        return book.readPos.getDevices().map { $0.toFolioReaderReadPosition() }
    }
    
    public func folioReaderPositionHistory(_ folioReader: FolioReader, bookId: String) -> [FolioReaderReadPositionHistory] {
        guard book.readPos.bookPrefId == bookId else { return [] }
        
        return book.readPos.sessions(list: nil).map { $0.toFolioReaderReadPositionHistory() }
    }
    
}

fileprivate extension BookBookmark {
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

fileprivate extension FolioReaderBookmark {
    func toBookBookmark() -> BookBookmark? {
        guard let pos_type = self.pos_type,
              let pos = self.pos
        else { return nil }
        
        let bookmark = BookBookmark(
            bookId: self.bookId,
            page: self.page,
            pos_type: pos_type,
            pos: pos,
            title: self.title,
            date: self.date,
            removed: false
        )
        return bookmark
    }
}

public class FolioReaderYabrBookmarkProvider: FolioReaderBookmarkProvider {
    let book: CalibreBook
    let readerInfo: ReaderInfo

    init(book: CalibreBook, readerInfo: ReaderInfo) {
        self.book = book
        self.readerInfo = readerInfo
    }
    
    public func folioReaderBookmark(_ folioReader: FolioReader, added bookmark: FolioReaderBookmark, completion: Completion?) {
        var error: FolioReaderBookmarkError? = nil
        defer {
            completion?(error as NSError?)
        }
        
        guard let bookBookmark = bookmark.toBookBookmark() else {
            error = FolioReaderBookmarkError.emptyError("")
            return
        }
        
        let result = book.readPos.bookmarks(added: bookBookmark)
        switch result.0 {
        case 0:
            error = nil
        case -1:
            error = FolioReaderBookmarkError.runtimeError("Realm Provider Error")
        case -2:
            error = FolioReaderBookmarkError.duplicateError(result.1 ?? "No Title")
        case -3:
            error = FolioReaderBookmarkError.runtimeError(result.1 ?? "Realm Provider Error")
        default:
            error = FolioReaderBookmarkError.runtimeError(result.1 ?? "Unknown Error")
        }
    }
    
    public func folioReaderBookmark(_ folioReader: FolioReader, removed bookmarkPos: String) {
        book.readPos.bookmarks(removed: bookmarkPos)
    }
    
    public func folioReaderBookmark(_ folioReader: FolioReader, updated bookmarkPos: String, title: String) {
        book.readPos.bookmarks(updated: bookmarkPos, title: title)
    }
    
    public func folioReaderBookmark(_ folioReader: FolioReader, getBy bookmarkPos: String) -> FolioReaderBookmark? {
        return book.readPos.bookmarks(getBy: bookmarkPos)?.toFolioReaderBookmark()
    }
    
    public func folioReaderBookmark(_ folioReader: FolioReader, allByBookId bookId: String, andPage page: NSNumber?) -> [FolioReaderBookmark] {
        return book.readPos.bookmarks(andPage: page).map { $0.toFolioReaderBookmark() }
    }
    
    public func folioReaderBookmark(_ folioReader: FolioReader) -> [FolioReaderBookmark] {
        return book.readPos.bookmarks().map { $0.toFolioReaderBookmark() }
    }
}
