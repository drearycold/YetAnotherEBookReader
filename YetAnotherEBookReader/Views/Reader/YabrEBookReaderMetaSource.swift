//
//  YabrEBookReaderMetaSource.swift
//  YetAnotherEBookReader
//
//  Created by Peter on 2022/10/1.
//

import Foundation
import UIKit
import RealmSwift

struct YabrEBookReaderPDFMetaSource: YabrPDFMetaSource {
    let book: CalibreBook
    let readerInfo: ReaderInfo
    var dictViewer: (String, UIViewController)? = nil
    
    func yabrPDFURL(_ viewController: YabrPDFViewController) -> URL? {
        return readerInfo.url
    }
    
    func yabrPDFReadPosition(_ viewController: YabrPDFViewController) -> BookDeviceReadingPosition? {
        return readerInfo.position
    }
    
    func yabrPDFReadPosition(_ viewController: YabrPDFViewController, update readPosition: BookDeviceReadingPosition) {
        var readPosition = readPosition
        readPosition.id = readerInfo.deviceName
        readPosition.readerName = readerInfo.readerType.rawValue
        book.readPos.updatePosition(readPosition)
    }
    
    func yabrPDFOptions(_ viewController: YabrPDFViewController) -> PDFOptions? {
        guard let config = getBookPreferenceConfig(bookFileURL: readerInfo.url),
              let realm = try? Realm(configuration: config),
              let pdfOptionsRealm = realm.objects(PDFOptionsRealm.self).first
        else { return nil }
        
        return PDFOptions(managedObject: pdfOptionsRealm)
    }
    
    func yabrPDFOptions(_ viewController: YabrPDFViewController, update options: PDFOptions) {
        guard let config = getBookPreferenceConfig(bookFileURL: readerInfo.url),
              let realm = try? Realm(configuration: config)
        else { return }
        
        try? realm.write {
            realm.add(options.managedObject(), update: .all)
        }
    }
    
    func yabrPDFDictViewer(_ viewController: YabrPDFViewController) -> (String, UIViewController)? {
        return dictViewer
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
