//
//  YabrEBookReaderMetaSource.swift
//  YetAnotherEBookReader
//
//  Created by Peter on 2022/10/1.
//

import Foundation
import UIKit
import PDFKit

class YabrEBookReaderPDFMetaSource: YabrPDFMetaSource {
    let book: CalibreBook
    let readerInfo: ReaderInfo
    private let preferenceRepository: ReaderPreferenceRepositoryProtocol
    
    var dictViewerItem = ""
    var dictViewerNav = UINavigationController()
    var dictViewerTab = DictTabBarController()
    
    var refText: String?
    
    private var pdfPreferences: PDFPreferenceValue
    
    init(
        book: CalibreBook,
        readerInfo: ReaderInfo,
        preferenceRepository: ReaderPreferenceRepositoryProtocol? = nil
    ) {
        self.book = book
        self.readerInfo = readerInfo
        self.preferenceRepository = preferenceRepository
            ?? AppContainer.shared?.readerPreferenceRepository
            ?? RealmReaderPreferenceRepository()
        if let savedPreferences = self.preferenceRepository.loadPDFPreferences(for: book) {
            self.pdfPreferences = savedPreferences
        } else {
            let defaultPreferences = PDFPreferenceValue()
            self.pdfPreferences = defaultPreferences
            self.preferenceRepository.savePDFPreferences(defaultPreferences, for: book)
        }
    }
    
    func yabrPDFBook(_ view: YabrPDFView?, info: String) -> String? {
        switch info {
        case "Title":
            return book.title
        case "Author":
            return book.authors.first!
        case "Key":
            return book.inShelfId
        default:
            return nil
        }
    }
    
    func yabrPDFURL(_ view: YabrPDFView?) -> URL? {
        return readerInfo.url
    }
    
    func yabrPDFDocument(_ view: YabrPDFView?) -> PDFDocument? {
        return view?.document
    }
    
    func yabrPDFNavigate(_ view: YabrPDFView?, pageNumber: Int, offset: CGPoint) {
        guard let page = view?.document?.page(at: pageNumber - 1)
        else { return }
        
        yabrPDFNavigate(view, destination: PDFDestination(page: page, at: offset))
    }
    
    func yabrPDFNavigate(_ view: YabrPDFView?, destination: PDFDestination) {
        if let curPage = view?.currentPage {
            view?.yabrPDFViewController?.updateHistoryMenu(curPage: curPage)
        }
        view?.go(to: destination)
    }
    
    func yabrPDFOutline(_ view: YabrPDFView?, for page: Int) -> PDFOutline? {
        guard let pdfDocument = yabrPDFDocument(view),
              let pdfPage = pdfDocument.page(at: page),
              let pdfPageSelection = pdfPage.selection(for: pdfPage.bounds(for: .mediaBox)),
              pdfPageSelection.selectionsByLine().isEmpty == false
        else { return nil }
        
        return pdfDocument.outlineItem(for: pdfPageSelection)
    }
    
    
    
    func yabrPDFOptions(_ view: YabrPDFView?) -> PDFPreferenceValue? {
        return pdfPreferences
    }
    
    func yabrPDFOptions(_ view: YabrPDFView?, update options: PDFPreferenceValue) {
        pdfPreferences = options
        preferenceRepository.savePDFPreferences(options, for: book)
        updateDictViewerStyle(options: options)
    }
    
    func yabrPDFDictViewer(_ view: YabrPDFView?) -> (String, UINavigationController)? {
        return (dictViewerItem, dictViewerNav)
    }
    
    func yabrPDFBookmarks(_ view: YabrPDFView?) -> [PDFBookmark] {
        return (AppContainer.shared?.annotationRepository.getBookmarks(forBookId: book.bookPrefId, excludeRemoved: true) ?? []).compactMap { $0.toPDFBookmark() }
    }
    
    func yabrPDFBookmarks(_ view: YabrPDFView?, update bookmark: PDFBookmark) {
        guard let bookBookmark = BookBookmark(bookId: book.bookPrefId, pdfBookmark: bookmark)
        else { return }
        
        _ = AppContainer.shared?.annotationRepository.saveBookmark(bookBookmark)
    }
    
    func yabrPDFBookmarks(_ view: YabrPDFView?, remove bookmark: PDFBookmark) {
        guard let bookBookmark = BookBookmark(bookId: book.bookPrefId, pdfBookmark: bookmark)
        else { return }
        
        AppContainer.shared?.annotationRepository.removeBookmark(pos: bookBookmark.pos, bookId: book.bookPrefId)
    }
    
    func yabrPDFHighlights(_ view: YabrPDFView?) -> [PDFHighlight] {
        return (AppContainer.shared?.annotationRepository.getHighlights(forBookId: book.bookPrefId, excludeRemoved: true) ?? []).compactMap { $0.toPDFHighlight() }
    }
    
    func yabrPDFHighlights(_ view: YabrPDFView?, getById highlightId: UUID) -> PDFHighlight? {
        return AppContainer.shared?.annotationRepository.getHighlight(byId: highlightId.uuidString)?.toPDFHighlight()
    }
    
    func yabrPDFHighlights(_ view: YabrPDFView?, update highlight: PDFHighlight) {
        guard let bookHighlight = BookHighlight(bookId: book.bookPrefId, pdfHighlight: highlight)
        else { return }
        
        AppContainer.shared?.annotationRepository.saveHighlight(bookHighlight)
    }
    
    func yabrPDFHighlights(_ view: YabrPDFView?, remove highlight: PDFHighlight) {
        guard let bookHighlight = BookHighlight(bookId: book.bookPrefId, pdfHighlight: highlight)
        else { return }
        
        AppContainer.shared?.annotationRepository.removeHighlight(id: bookHighlight.id)
        view?.removeHighlight(highlight: highlight)
    }
    
    func yabrPDFReferenceText(_ view: YabrPDFView?) -> String? {
        return refText
    }
    
    func yabrPDFReferenceText(_ view: YabrPDFView?, set refText: String?) {
        self.refText = refText
    }
    
    func yabrPDFOptionsIsNight<T>(_ view: YabrPDFView?, _ f: T, _ l: T) -> T {
        yabrPDFOptions(view)?.isDark(f, l) ?? l
    }
    
    func updateDictViewerStyle(options: PDFPreferenceValue) {
        let backgroundColor = UIColor(cgColor: options.fillColor)
        let textColor = options.isDark(UIColor(white: 0.7, alpha: 1.0), UIColor.black)
        let navBackgroundColor = backgroundColor
        
        dictViewerNav.navigationBar.tintColor = textColor
        dictViewerNav.navigationBar.backgroundColor = backgroundColor
        dictViewerNav.navigationBar.barTintColor = navBackgroundColor
        dictViewerNav.navigationBar.titleTextAttributes = [
            .foregroundColor: textColor
        ]
    
        dictViewerTab.updateStyle(textColor, backgroundColor, navBackgroundColor, options.isDark)
    }
}

extension BookBookmark {
    init?(bookId: String, pdfBookmark: PDFBookmark) {
        guard let posData = try? JSONEncoder().encode(pdfBookmark.pos),
              let pos = String(data: posData, encoding: .utf8)
        else { return nil }
        
        self.init(
            bookId: bookId,
            page: pdfBookmark.pos.page,
            pos_type: BookBookmarkRealm.PDFBookmarkPosType,
            pos: pos,
            title: pdfBookmark.title,
            date: pdfBookmark.date
        )
    }
    
    func toPDFBookmark() -> PDFBookmark? {
        guard self.pos_type == BookBookmarkRealm.PDFBookmarkPosType else { return nil }
        guard let posData = self.pos.data(using: .utf8),
              let pos = try? JSONDecoder().decode(PDFBookmark.Location.self, from: posData)
        else { return nil }
        
        return PDFBookmark(pos: pos, title: self.title, date: self.date)
    }
}

extension BookHighlight {
    init?(bookId: String, pdfHighlight: PDFHighlight) {
        guard let posData = try? JSONEncoder().encode(pdfHighlight.pos),
              let pos = String(data: posData, encoding: .utf8)
        else { return nil }
        
        self.init(
            id: pdfHighlight.uuid.uuidString,
            bookId: bookId,
            readerName: ReaderType.YabrPDF.rawValue,
            page: pdfHighlight.pos.first?.page ?? 1,
            startOffset: 0,
            endOffset: 0,
            date: pdfHighlight.date,
            type: pdfHighlight.type,
            note: pdfHighlight.note,
            tocFamilyTitles: [],
            content: pdfHighlight.content,
            contentPost: "",
            contentPre: "",
            cfiStart: "/\((pdfHighlight.pos.first?.page ?? 1) * 2)",
            cfiEnd: "/\((pdfHighlight.pos.last?.page ?? 1) * 2)",
            spineName: nil,
            ranges: pos,
            removed: false
        )
    }
    
    func toPDFHighlight() -> PDFHighlight? {
        guard readerName.isEmpty || readerName == ReaderType.YabrPDF.rawValue,
              let uuid = UUID(uuidString: self.id),
              let posData = self.ranges?.data(using: .utf8),
              let pos = try? JSONDecoder().decode([PDFHighlight.PageLocation].self, from: posData)
        else { return nil }
        
        return PDFHighlight(uuid: uuid, pos: pos, type: self.type, content: self.content, note: self.note, date: self.date)
    }
}
