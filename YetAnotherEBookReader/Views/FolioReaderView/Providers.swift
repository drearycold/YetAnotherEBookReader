//
//  Providers.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/9/27.
//

import Foundation
import UIKit
import FolioReaderKit
import RealmSwift

extension EpubFolioReaderContainer {
    func folioReaderPreferenceProvider(_ folioReader: FolioReader) -> FolioReaderPreferenceProvider {
        if let preferenceProvider = folioReaderPreferenceProvider {
            return preferenceProvider
        } else {
            guard let book = modelData?.readingBook else {
                return FolioReaderDummyPreferenceProvider(folioReader)
            }
            let preferenceProvider = FolioReaderDelegatePreferenceProvider(folioReader, delegate: self.readerEngineDelegate, bookId: book.bookPrefId)
            self.folioReaderPreferenceProvider = preferenceProvider
            return preferenceProvider
        }
    }
    
    func folioReaderHighlightProvider(_ folioReader: FolioReader) -> FolioReaderHighlightProvider {
        if let highlightProvider = folioReaderHighlightProvider {
            return highlightProvider
        } else {
            guard let book = modelData?.readingBook else {
                return FolioReaderDummyHighlightProvider()
            }
            let highlightProvider = FolioReaderDelegateHighlightProvider(delegate: self.readerEngineDelegate, bookId: book.bookPrefId)
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
            let provider = FolioReaderYabrReadPositionProvider(book: book, readerInfo: readerInfo, readerEngineDelegate: self.readerEngineDelegate)
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

private let folioFontSizes = ["15.5px", "17px", "18.5px", "20px", "22px", "24px", "26px", "28px", "30.5px", "33px", "35.5px"]

func folioFontSizeToPercentage(_ fontSize: String) -> Double {
    if let index = folioFontSizes.firstIndex(of: fontSize) {
        return 100.0 + Double(index - 3) * 10.0
    }
    if fontSize.hasSuffix("px"), let val = Double(fontSize.dropLast(2)) {
        return (val / 20.0) * 100.0
    }
    if fontSize.hasSuffix("%"), let val = Double(fontSize.dropLast()) {
        return val
    }
    return 100.0
}

func percentageToFolioFontSize(_ percentage: Double) -> String {
    let indexDouble = (percentage - 100.0) / 10.0 + 3.0
    let index = max(0, min(folioFontSizes.count - 1, Int(round(indexDouble))))
    return folioFontSizes[index]
}

class FolioReaderDelegatePreferenceProvider: FolioReaderPreferenceProvider {
    let folioReader: FolioReader
    weak var delegate: ReaderEngineDelegate?
    var bookId: String
    
    private var values = [String: Any]()
    
    init(_ folioReader: FolioReader, delegate: ReaderEngineDelegate?, bookId: String) {
        self.folioReader = folioReader
        self.delegate = delegate
        self.bookId = bookId
        
        values["nightMode"] = false
        values["themeMode"] = FolioReaderThemeMode.serpia.rawValue
        values["currentFont"] = "Georgia"
        values["currentFontSize"] = FolioReader.DefaultFontSize
        values["currentFontWeight"] = FolioReader.DefaultFontWeight
        values["currentScrollDirection"] = folioReader.defaultScrollDirection.rawValue
        values["currentMarginTop"] = folioReader.defaultMarginTop
        values["currentMarginBottom"] = folioReader.defaultMarginBottom
        values["currentMarginLeft"] = folioReader.defaultMarginLeft
        values["currentMarginRight"] = folioReader.defaultMarginRight
        values["currentVMarginLinked"] = true
        values["currentHMarginLinked"] = true
        values["currentLetterSpacing"] = FolioReader.DefaultLetterSpacing
        values["currentLineHeight"] = FolioReader.DefaultLineHeight
        values["currentTextIndent"] = FolioReader.DefaultTextIndent
        values["doWrapPara"] = false
        values["doClearClass"] = true
    }
    
    func preference(stringFor key: String, default defaultValue: String) -> String {
        return values[key] as? String ?? defaultValue
    }
    
    func preference(setString value: String, for key: String) {
        values[key] = value
        notifyDelegate()
    }
    
    func preference(intFor key: String, default defaultValue: Int) -> Int {
        return values[key] as? Int ?? defaultValue
    }
    
    func preference(setInt value: Int, for key: String) {
        values[key] = value
        notifyDelegate()
    }
    
    func preference(boolFor key: String, default defaultValue: Bool) -> Bool {
        return values[key] as? Bool ?? defaultValue
    }
    
    func preference(setBool value: Bool, for key: String) {
        values[key] = value
        notifyDelegate()
    }
    
    func preference(loadProfile name: String) {}
    func preference(saveProfile name: String) {}
    func preference(listProfile filter: String?) -> [String] { return [] }
    func preference(removeProfile name: String) {}
    
    func applyPreferences(_ preferences: ReaderEnginePreferences) {
        let nightMode = (preferences.themeMode == 2)
        values["nightMode"] = nightMode
        values["themeMode"] = preferences.themeMode
        
        values["currentFontSize"] = percentageToFolioFontSize(preferences.fontSizePercentage)
        values["currentFont"] = preferences.fontFamily
        values["currentScrollDirection"] = preferences.scrollDirection
    }
    
    private func notifyDelegate() {
        let themeMode = values["themeMode"] as? Int ?? (values["nightMode"] as? Bool == true ? 2 : 1)
        let fontSizeStr = values["currentFontSize"] as? String ?? FolioReader.DefaultFontSize
        let fontSizePercentage = folioFontSizeToPercentage(fontSizeStr)
        let fontFamily = values["currentFont"] as? String ?? "Original"
        let scrollDirection = values["currentScrollDirection"] as? Int ?? 0
        
        let enginePrefs = ReaderEnginePreferences(
            themeMode: themeMode,
            fontSizePercentage: fontSizePercentage,
            fontFamily: fontFamily,
            lineHeight: 1.2,
            pageMargins: 1.0,
            scroll: scrollDirection == 0 ? false : true,
            scrollDirection: scrollDirection,
            volumeKeyPaging: false
        )
        
        delegate?.readerEngine(folioReader, didUpdatePreferences: enginePrefs)
    }
}

class FolioReaderDelegateHighlightProvider: FolioReaderHighlightProvider {
    weak var delegate: ReaderEngineDelegate?
    var bookId: String
    
    private var activeHighlights = [String: ReaderEngineHighlight]()
    
    init(delegate: ReaderEngineDelegate?, bookId: String) {
        self.delegate = delegate
        self.bookId = bookId
    }
    
    func applyHighlights(_ highlights: [ReaderEngineHighlight]) {
        activeHighlights.removeAll()
        highlights.forEach {
            activeHighlights[$0.id] = $0
        }
    }
    
    public func folioReaderHighlight(_ folioReader: FolioReader, added highlight: FolioReaderHighlight, completion: Completion?) {
        defer {
            completion?(nil)
        }
        let engineHighlight = highlight.toReaderEngineHighlight()
        activeHighlights[highlight.highlightId] = engineHighlight
        delegate?.readerEngine(folioReader, didAddHighlight: engineHighlight)
    }
    
    public func folioReaderHighlight(_ folioReader: FolioReader, removedId highlightId: String) {
        activeHighlights.removeValue(forKey: highlightId)
        delegate?.readerEngine(folioReader, didRemoveHighlight: highlightId)
    }
    
    public func folioReaderHighlight(_ folioReader: FolioReader, updateById highlightId: String, type style: FolioReaderHighlightStyle) {
        if var existing = activeHighlights[highlightId] {
            existing.type = style.rawValue
            existing.date = Date()
            activeHighlights[highlightId] = existing
            delegate?.readerEngine(folioReader, didAddHighlight: existing)
        }
    }
    
    public func folioReaderHighlight(_ folioReader: FolioReader, getById highlightId: String) -> FolioReaderHighlight? {
        return activeHighlights[highlightId]?.toFolioReaderHighlight()
    }
    
    public func folioReaderHighlight(_ folioReader: FolioReader, allByBookId bookId: String, andPage page: NSNumber?) -> [FolioReaderHighlight] {
        return activeHighlights.values.filter { $0.bookId == bookId && (page == nil || $0.page == page?.intValue) }.compactMap {
            $0.toFolioReaderHighlight()
        }
    }
    
    public func folioReaderHighlight(_ folioReader: FolioReader) -> [FolioReaderHighlight] {
        return activeHighlights.values.filter { $0.bookId == bookId }.compactMap {
            $0.toFolioReaderHighlight()
        }
    }
    
    public func folioReaderHighlight(_ folioReader: FolioReader, saveNoteFor highlight: FolioReaderHighlight) {
        if var existing = activeHighlights[highlight.highlightId] {
            existing.note = highlight.noteForHighlight
            existing.date = Date()
            activeHighlights[highlight.highlightId] = existing
            delegate?.readerEngine(folioReader, didAddHighlight: existing)
        }
    }
}

extension FolioReaderHighlight {
    func toReaderEngineHighlight() -> ReaderEngineHighlight {
        return self.toBookHighlight().toReaderEngineHighlight()
    }
}

extension ReaderEngineHighlight {
    func toFolioReaderHighlight() -> FolioReaderHighlight? {
        return self.toBookHighlight().toFolioReaderHighlight()
    }
}

extension EpubFolioReaderContainer: ReaderEngineController {
    func applyPreferences(_ preferences: ReaderEnginePreferences) {
        if let preferenceProvider = self.folioReaderPreferenceProvider as? FolioReaderDelegatePreferenceProvider {
            preferenceProvider.applyPreferences(preferences)
        }
    }
    
    func applyHighlights(_ highlights: [ReaderEngineHighlight]) {
        if let highlightProvider = self.folioReaderHighlightProvider as? FolioReaderDelegateHighlightProvider {
            highlightProvider.applyHighlights(highlights)
        }
    }
}




extension BookHighlight {
    func toFolioReaderHighlight() -> FolioReaderHighlight? {
        guard readerName.isEmpty || readerName == ReaderType.YabrEPUB.rawValue
        else { return nil }
        
        let highlight = FolioReaderHighlight()
        highlight.bookId = bookId
        highlight.highlightId = id
        
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

extension FolioReaderHighlight {
    func toBookHighlight() -> BookHighlight {
        return BookHighlight(
            id: highlightId,
            bookId: bookId,
            readerName: ReaderType.YabrEPUB.rawValue,
            page: page,
            startOffset: startOffset,
            endOffset: endOffset,
            date: date,
            type: type,
            note: noteForHighlight,
            tocFamilyTitles: tocFamilyTitles,
            content: content ?? "",
            contentPost: contentPost ?? "",
            contentPre: contentPre ?? "",
            cfiStart: cfiStart,
            cfiEnd: cfiEnd,
            spineName: spineName,
            ranges: nil,
            removed: false
        )
    }
}

extension BookDeviceReadingPositionRealm {
    func fromFolioReaderReadPosition(_ position: FolioReaderReadPosition, bookId: String) {
        self.bookId = bookId
        self.deviceId = position.deviceId
        
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
            deviceId: deviceId,
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
    weak var readerEngineDelegate: ReaderEngineDelegate?
    
    init(book: CalibreBook, readerInfo: ReaderInfo, readerEngineDelegate: ReaderEngineDelegate? = nil) {
        self.book = book
        self.readerInfo = readerInfo
        self.readerEngineDelegate = readerEngineDelegate
    }
    
    public func folioReaderReadPosition(_ folioReader: FolioReader, bookId: String) -> FolioReaderReadPosition? {
        guard book.bookPrefId == bookId else { return nil }
        
        return ModelData.shared?.readingPositionRepository.getPosition(forBookId: book.bookPrefId, deviceName: nil)?.toFolioReaderReadPosition()
    }
    
    public func folioReaderReadPosition(_ folioReader: FolioReader, bookId: String, by rootPageNumber: Int) -> FolioReaderReadPosition? {
        guard book.bookPrefId == bookId else { return nil }

        return (ModelData.shared?.readingPositionRepository.getPositions(forBookId: book.bookPrefId) ?? [])
            .filter({
                $0.readerName == ReaderType.YabrEPUB.rawValue
                &&
                $0.structuralStyle == FolioReaderStructuralStyle.bundle.rawValue
                &&
                $0.structuralRootPageNumber == rootPageNumber
            })
            .first?.toFolioReaderReadPosition()
    }
    
    public func folioReaderReadPosition(_ folioReader: FolioReader, bookId: String, set readPosition: FolioReaderReadPosition, completion: Completion?) {
        guard book.bookPrefId == bookId else { return }
        
        let bookDevPos = readPosition.toBookDeviceReadingPosition()
        let enginePos = ReaderEnginePosition(
            pageNumber: bookDevPos.lastReadPage,
            maxPage: bookDevPos.maxPage,
            pageOffsetX: bookDevPos.lastPosition[1],
            pageOffsetY: bookDevPos.lastPosition[2],
            bookProgress: bookDevPos.lastProgress,
            chapterProgress: bookDevPos.lastChapterProgress,
            chapterName: bookDevPos.lastReadChapter,
            cfi: bookDevPos.cfi,
            structuralStyle: bookDevPos.structuralStyle,
            structuralRootPageNumber: bookDevPos.structuralRootPageNumber,
            positionTrackingStyle: bookDevPos.positionTrackingStyle
        )
        
        if let delegate = readerEngineDelegate {
            delegate.readerEngine(self, didUpdatePosition: enginePos)
        } else {
            ModelData.shared?.readingPositionRepository.savePosition(bookDevPos, forBookId: book.bookPrefId)
        }
    }
    
    public func folioReaderReadPosition(_ folioReader: FolioReader, bookId: String, remove readPosition: FolioReaderReadPosition) {
        guard book.bookPrefId == bookId else { return }
        
        ModelData.shared?.readingPositionRepository.removePosition(position: readPosition.toBookDeviceReadingPosition(), forBookId: book.bookPrefId)
    }
    
    public func folioReaderReadPosition(_ folioReader: FolioReader, bookId: String, getById deviceId: String) -> [FolioReaderReadPosition] {
        
        return folioReaderReadPosition(folioReader, allByBookId: bookId).filter { $0.deviceId == deviceId }
    }
    
    public func folioReaderReadPosition(_ folioReader: FolioReader, allByBookId bookId: String) -> [FolioReaderReadPosition] {
        guard book.bookPrefId == bookId else { return [] }
        
        return (ModelData.shared?.readingPositionRepository.getPositions(forBookId: book.bookPrefId) ?? []).map { $0.toFolioReaderReadPosition() }
    }
    
    public func folioReaderReadPosition(_ folioReader: FolioReader) -> [FolioReaderReadPosition] {
        return (ModelData.shared?.readingPositionRepository.getPositions(forBookId: book.bookPrefId) ?? []).map { $0.toFolioReaderReadPosition() }
    }
    
    public func folioReaderPositionHistory(_ folioReader: FolioReader, bookId: String) -> [FolioReaderReadPositionHistory] {
        guard book.bookPrefId == bookId else { return [] }
        
        return (ModelData.shared?.readingPositionRepository.sessions(forBookId: book.bookPrefId, list: nil) ?? []).map { $0.toFolioReaderReadPositionHistory() }
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
        
        return BookBookmark(
            bookId: self.bookId,
            page: self.page,
            pos_type: pos_type,
            pos: pos,
            title: self.title,
            date: self.date,
            removed: false
        )
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
        
        let result = ModelData.shared?.annotationRepository.saveBookmark(bookBookmark) ?? (-1, nil)
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
        ModelData.shared?.annotationRepository.removeBookmark(pos: bookmarkPos, bookId: book.bookPrefId)
    }
    
    public func folioReaderBookmark(_ folioReader: FolioReader, updated bookmarkPos: String, title: String) {
        if let existing = ModelData.shared?.annotationRepository.getBookmark(byPos: bookmarkPos, bookId: book.bookPrefId) {
            var updated = existing
            updated.title = title
            updated.date = Date()
            _ = ModelData.shared?.annotationRepository.saveBookmark(updated)
        }
    }
    
    public func folioReaderBookmark(_ folioReader: FolioReader, getBy bookmarkPos: String) -> FolioReaderBookmark? {
        return ModelData.shared?.annotationRepository.getBookmark(byPos: bookmarkPos, bookId: book.bookPrefId)?.toFolioReaderBookmark()
    }
    
    public func folioReaderBookmark(_ folioReader: FolioReader, allByBookId bookId: String, andPage page: NSNumber?) -> [FolioReaderBookmark] {
        return (ModelData.shared?.annotationRepository.getBookmarks(forBookId: book.bookPrefId, excludeRemoved: true) ?? []).filter { page == nil || $0.page == page?.intValue }.map { $0.toFolioReaderBookmark() }
    }
    
    public func folioReaderBookmark(_ folioReader: FolioReader) -> [FolioReaderBookmark] {
        return (ModelData.shared?.annotationRepository.getBookmarks(forBookId: book.bookPrefId, excludeRemoved: true) ?? []).map { $0.toFolioReaderBookmark() }
    }
}
