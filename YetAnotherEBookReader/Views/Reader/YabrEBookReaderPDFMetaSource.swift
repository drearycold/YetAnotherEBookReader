//
//  YabrEBookReaderPDFMetaSource.swift
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
        book.readPos.updatePosition(readPosition.id, readPosition)
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
