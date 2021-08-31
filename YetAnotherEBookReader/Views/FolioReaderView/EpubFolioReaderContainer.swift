//
//  ViewController.swift
//  Example
//
//  Created by Heberti Almeida on 08/04/15.
//  Copyright (c) 2015 Folio Reader. All rights reserved.
//

import UIKit
import FolioReaderKit
import RealmSwift

@available(macCatalyst 14.0, *)
class EpubFolioReaderContainer: FolioReaderContainer, FolioReaderDelegate {
//    var savedPositionObserver: NSKeyValueObservation?
    var modelData: ModelData?
    
    var yabrFolioReaderPageDelegate: YabrFolioReaderPageDelegate!
    
    var folioReaderPreferenceProvider: FolioReaderPreferenceProvider?
    
    func open(bookReadingPosition: BookDeviceReadingPosition) {
        readerConfig.loadSavedPositionForCurrentBook = true
        
        //if bookReadingPosition.lastProgress > 0 {
            var position = [String: Any]()
            position["pageNumber"] = bookReadingPosition.lastPosition[0]
            position["pageOffsetX"] = CGFloat(bookReadingPosition.lastPosition[1])
            position["pageOffsetY"] = CGFloat(bookReadingPosition.lastPosition[2])
            readerConfig.savedPositionForCurrentBook = position
        //}
        
        self.yabrFolioReaderPageDelegate = YabrFolioReaderPageDelegate(readerConfig: self.readerConfig)
        self.folioReader.delegate = self
        
        NotificationCenter.default.removeObserver(self, name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.willTerminateNotification, object: nil)
        
        // NotificationCenter.default.addObserver(self, selector: #selector(folioReader.saveReaderState), name: UIApplication.willResignActiveNotification, object: nil)
        // NotificationCenter.default.addObserver(self, selector: #selector(folioReader.saveReaderState), name: UIApplication.willTerminateNotification, object: nil)
        
        super.initialization()
    }

    override func viewDidDisappear(_ animated: Bool) {
        updateReadingPosition(self.folioReader)
        
        super.viewDidDisappear(animated)
    }
    
    func folioReader(_ folioReader: FolioReader, didFinishedLoading book: FRBook) {
        folioReader.readerCenter?.delegate = MyFolioReaderCenterDelegate()
        folioReader.readerCenter?.pageDelegate = yabrFolioReaderPageDelegate
    }
    
    func folioReaderDidClose(_ folioReader: FolioReader) {
        updateReadingPosition(folioReader)
    }
    
    func updateReadingPosition(_ folioReader: FolioReader) {
        guard var updatedReadingPosition = modelData?.updatedReadingPosition else { return }
        
        guard let chapterProgress = folioReader.readerCenter?.getCurrentPageProgress(),
           let bookProgress = folioReader.readerCenter?.getBookProgress(),
           let savedPosition = folioReader.savedPositionForCurrentBook
        else {
            return
        }
        
        if let currentChapterName = folioReader.readerCenter?.getCurrentChapterName() {
            updatedReadingPosition.lastReadChapter = currentChapterName
        } else {
            updatedReadingPosition.lastReadChapter = "Untitled Chapter"
        }
        
        updatedReadingPosition.lastChapterProgress = chapterProgress
        updatedReadingPosition.lastProgress = bookProgress
        
        guard let pageNumber = savedPosition["pageNumber"] as? Int,
              let pageOffsetX = savedPosition["pageOffsetX"] as? CGFloat,
              let pageOffsetY = savedPosition["pageOffsetY"] as? CGFloat
        else {
            return
        }
        
        updatedReadingPosition.lastPosition[0] = pageNumber
        updatedReadingPosition.lastPosition[1] = Int(pageOffsetX.rounded())
        updatedReadingPosition.lastPosition[2] = Int(pageOffsetY.rounded())
        updatedReadingPosition.lastReadPage = pageNumber
        
        updatedReadingPosition.readerName = "FolioReader"
        
        modelData?.updatedReadingPosition = updatedReadingPosition
    }

}

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
}

class FolioReaderPreferenceRealm: Object {
    override static func primaryKey() -> String? {
        return "id"
    }
    @objc dynamic var id: String = ""
    
    @objc dynamic var nightMode: Bool = false
    @objc dynamic var themeMode: Int = FolioReaderThemeMode.serpia.rawValue
    @objc dynamic var currentFont: String = "Georgia"
    @objc dynamic var currentFontSize: String = "20px"
    @objc dynamic var currentFontWeight: String = "500"
    @objc dynamic var currentAudioRate: Int = 2
    @objc dynamic var currentHighlightStyle: Int = HighlightStyle.yellow.rawValue
    @objc dynamic var currentMediaOverlayStyle: Int = MediaOverlayStyle.default.rawValue
    @objc dynamic var currentScrollDirection: Int = FolioReaderScrollDirection.horizontal.rawValue
    @objc dynamic var currentMenuIndex: Int = 0
    @objc dynamic var currentMarginTop: Int = 0
    @objc dynamic var currentMarginBottom: Int = 0
    @objc dynamic var currentMarginLeft: Int = 0
    @objc dynamic var currentMarginRight: Int = 0
    @objc dynamic var currentLetterSpacing: Int = 0
    @objc dynamic var currentLineHeight: Int = 0
    @objc dynamic var doWrapPara: Bool = false
    @objc dynamic var doClearClass: Bool = false
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
        return prefObj?.themeMode ?? defaults
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
        return prefObj?.currentAudioRate ?? defaults
    }
    
    func preference(setCurrentAudioRate value: Int) {
        try? realm?.write { prefObj?.currentAudioRate = value }
    }
    
    func preference(currentHighlightStyle defaults: Int) -> Int {
        return prefObj?.currentHighlightStyle ?? defaults
    }
    
    func preference(setCurrentHighlightStyle value: Int) {
        try? realm?.write { prefObj?.currentHighlightStyle = value }
    }
    
    func preference(currentMediaOverlayStyle defaults: Int) -> Int {
        return prefObj?.currentMediaOverlayStyle ?? defaults
    }
    
    func preference(setCurrentMediaOverlayStyle value: Int) {
        try? realm?.write { prefObj?.currentMediaOverlayStyle = value }
    }
    
    func preference(currentScrollDirection defaults: Int) -> Int {
        return prefObj?.currentScrollDirection ?? defaults
    }
    
    func preference(setCurrentScrollDirection value: Int) {
        try? realm?.write { prefObj?.currentScrollDirection = value }
    }
    
    func preference(currentMenuIndex defaults: Int) -> Int {
        return prefObj?.currentMenuIndex ?? defaults
    }
    
    func preference(setCurrentMenuIndex value: Int) {
        try? realm?.write { prefObj?.currentMenuIndex = value }
    }
    
    func preference(currentMarginTop defaults: Int) -> Int {
        return prefObj?.currentMarginTop ?? defaults
    }
    
    func preference(setCurrentMarginTop value: Int) {
        try? realm?.write { prefObj?.currentMarginTop = value }
    }
    
    func preference(currentMarginBottom defaults: Int) -> Int {
        return prefObj?.currentMarginBottom ?? defaults
    }
    
    func preference(setCurrentMarginBottom value: Int) {
        try? realm?.write { prefObj?.currentMarginBottom = value }
    }
    
    func preference(currentMarginLeft defaults: Int) -> Int {
        return prefObj?.currentMarginLeft ?? defaults
    }
    
    func preference(setCurrentMarginLeft value: Int) {
        try? realm?.write { prefObj?.currentMarginLeft = value }
    }
    
    func preference(currentMarginRight defaults: Int) -> Int {
        return prefObj?.currentMarginRight ?? defaults
    }
    
    func preference(setCurrentMarginRight value: Int) {
        try? realm?.write { prefObj?.currentMarginRight = value }
    }
    
    func preference(currentLetterSpacing defaults: Int) -> Int {
        return prefObj?.currentLetterSpacing ?? defaults
    }
    
    func preference(setCurrentLetterSpacing value: Int) {
        try? realm?.write { prefObj?.currentLetterSpacing = value }
    }
    
    func preference(currentLineHeight defaults: Int) -> Int {
        return prefObj?.currentLineHeight ?? defaults
    }
    
    func preference(setCurrentLineHeight value: Int) {
        try? realm?.write { prefObj?.currentLineHeight = value }
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
    
}
