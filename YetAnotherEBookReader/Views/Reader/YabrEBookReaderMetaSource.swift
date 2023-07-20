//
//  YabrEBookReaderMetaSource.swift
//  YetAnotherEBookReader
//
//  Created by Peter on 2022/10/1.
//

import Foundation
import UIKit
import PDFKit
import RealmSwift

class YabrEBookReaderPDFMetaSource: YabrPDFMetaSource {
    let book: CalibreBook
    let readerInfo: ReaderInfo
    var dictViewer: (String, UIViewController)? = nil
    
    var refText: String?
    
    let prefObj: YabrPDFOptionsRealm
    
    init(book: CalibreBook, readerInfo: ReaderInfo) {
        self.book = book
        self.readerInfo = readerInfo
        
        if let prefObj = book.readPos.realm?
            .objects(YabrPDFOptionsRealm.self)
            .where({ $0.bookId == book.id && $0.libraryName == book.library.name })
            .first {
            self.prefObj = prefObj
        } else {
            self.prefObj = YabrPDFOptionsRealm()
            self.prefObj.bookId = book.id
            self.prefObj.libraryName = book.library.name
            try? book.readPos.realm?.write {
                book.readPos.realm?.add(self.prefObj)
            }
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
    
    func yabrPDFReadPosition(_ view: YabrPDFView?) -> BookDeviceReadingPosition? {
        return readerInfo.position
    }
    
    func yabrPDFReadPosition(_ view: YabrPDFView?, update readPosition: BookDeviceReadingPosition) {
        var readPosition = readPosition
        readPosition.id = readerInfo.deviceName
        readPosition.readerName = readerInfo.readerType.rawValue
        book.readPos.updatePosition(readPosition)
    }
    
    func yabrPDFOptions(_ view: YabrPDFView?) -> PDFOptions? {
        return PDFOptions(managedObject: prefObj)
    }
    
    func yabrPDFOptions(_ view: YabrPDFView?, update options: PDFOptions) {
//        guard let realm = book.readPos.realm
//        else { return }
//
//        try? realm.write {
//            realm.add(options.managedObject(), update: .all)
//        }
        try? prefObj.realm?.write({
            options.update(obj: prefObj)
        })
    }
    
    func yabrPDFDictViewer(_ view: YabrPDFView?) -> (String, UIViewController)? {
        return dictViewer
    }
    
    func yabrPDFBookmarks(_ view: YabrPDFView?) -> [PDFBookmark] {
        return book.readPos.bookmarks().compactMap { $0.toPDFBookmark() }
    }
    
    func yabrPDFBookmarks(_ view: YabrPDFView?, update bookmark: PDFBookmark) {
        guard let bookBookmark = BookBookmark(bookId: book.readPos.bookPrefId, pdfBookmark: bookmark)
        else { return }
        
        book.readPos.bookmarks(added: bookBookmark)
    }
    
    func yabrPDFBookmarks(_ view: YabrPDFView?, remove bookmark: PDFBookmark) {
        guard let bookBookmark = BookBookmark(bookId: book.readPos.bookPrefId, pdfBookmark: bookmark)
        else { return }
        
        book.readPos.bookmarks(removed: bookBookmark.pos)
    }
    
    func yabrPDFHighlights(_ view: YabrPDFView?) -> [PDFHighlight] {
        return book.readPos.highlights().compactMap { $0.toPDFHighlight() }
    }
    
    func yabrPDFHighlights(_ view: YabrPDFView?, getById highlightId: UUID) -> PDFHighlight? {
        return book.readPos.highlight(getById: highlightId.uuidString)?.toPDFHighlight()
    }
    
    func yabrPDFHighlights(_ view: YabrPDFView?, update highlight: PDFHighlight) {
        guard let bookHighlight = BookHighlight(bookId: book.readPos.bookPrefId, pdfHighlight: highlight)
        else { return }
        
        book.readPos.highlight(added: bookHighlight)
    }
    
    func yabrPDFHighlights(_ view: YabrPDFView?, remove highlight: PDFHighlight) {
        guard let bookHighlight = BookHighlight(bookId: book.readPos.bookPrefId, pdfHighlight: highlight)
        else { return }
        
        book.readPos.highlight(removedId: bookHighlight.highlightId)
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
    
    
}

extension BookBookmark {
    static let PDFBookmarkPosType = "yabrpdf"
    
    init?(bookId: String, pdfBookmark: PDFBookmark) {
        guard let posData = try? JSONEncoder().encode(pdfBookmark.pos),
              let pos = String(data: posData, encoding: .utf8)
        else { return nil }
        
        self.bookId = bookId
        self.page = pdfBookmark.pos.page
        self.pos_type = BookBookmark.PDFBookmarkPosType
        self.pos = pos
        
        self.title = pdfBookmark.title
        self.date = pdfBookmark.date
        
        self.removed = false
    }
    
    func toPDFBookmark() -> PDFBookmark? {
        guard self.pos_type == BookBookmark.PDFBookmarkPosType else { return nil }
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
        
        self.bookId = bookId
        self.readerName = ReaderType.YabrPDF.rawValue
        self.highlightId = pdfHighlight.uuid.uuidString
        
        self.page = pdfHighlight.pos.first?.page ?? 1
        self.startOffset = 0
        self.endOffset = 0
        self.ranges = pos
        
        self.date = pdfHighlight.date
        self.type = pdfHighlight.type
        self.note = pdfHighlight.note
        
        self.tocFamilyTitles = []
        self.content = pdfHighlight.content
        self.contentPre = ""
        self.contentPost = ""
        
        self.cfiStart = "/\((pdfHighlight.pos.first?.page ?? 1) * 2)"
        self.cfiEnd = "/\((pdfHighlight.pos.last?.page ?? 1) * 2)"
        self.spineName = nil
    }
    
    func toPDFHighlight() -> PDFHighlight? {
        guard readerName.isEmpty || readerName == ReaderType.YabrPDF.rawValue,
              let uuid = UUID(uuidString: self.highlightId),
              let posData = self.ranges?.data(using: .utf8),
              let pos = try? JSONDecoder().decode([PDFHighlight.PageLocation].self, from: posData)
        else { return nil }
        
        return PDFHighlight(uuid: uuid, pos: pos, type: self.type, content: self.content, note: self.note, date: self.date)
    }
}

struct YabrEBookReaderReadiumMetaSource: YabrReadiumMetaSource {
    let book: CalibreBook
    let readerInfo: ReaderInfo
    var dictViewer: (String, UIViewController)? = nil
    
    func yabrReadiumReadPosition(_ viewController: YabrReadiumReaderViewController) -> BookDeviceReadingPosition? {
        return readerInfo.position
    }
    
    func yabrReadiumReadPosition(_ viewController: YabrReadiumReaderViewController, update readPosition: (Double, Double, [String: Any], String)) {
        var position = readerInfo.position
        position.id = readerInfo.deviceName
        position.readerName = readerInfo.readerType.rawValue
        
        position.lastChapterProgress = readPosition.0 * 100
        position.lastProgress = readPosition.1 * 100
        
        position.lastReadPage = readPosition.2["pageNumber"] as? Int ?? 1
        position.maxPage = readPosition.2["maxPage"] as? Int ?? 1
        position.lastPosition[0] = readPosition.2["pageNumber"] as? Int ?? 1
        position.lastPosition[1] = readPosition.2["pageOffsetX"] as? Int ?? 0
        position.lastPosition[2] = readPosition.2["pageOffsetY"] as? Int ?? 0
        
        position.lastReadChapter = readPosition.3
        
        position.cfi = ""

        position.epoch = Date().timeIntervalSince1970
        
        book.readPos.updatePosition(position)
    }
    
    func yabrReadiumDictViewer(_ viewController: YabrReadiumReaderViewController) -> (String, UIViewController)? {
        return dictViewer
    }
}
