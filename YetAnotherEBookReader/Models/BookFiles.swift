//
//  BookFiles.swift
//  YetAnotherEBookReader
//
//  Created by liyi on 2021/6/1.
//

import Foundation

func getSavedUrl(book: CalibreBook, format: CalibreBook.Format) -> URL? {
    var downloadBaseURL = try!
        FileManager.default.url(for: .documentDirectory,
                                in: .userDomainMask,
                                appropriateFor: nil,
                                create: false)
    var savedURL = downloadBaseURL.appendingPathComponent("\(book.library.name) - \(book.id).\(format.rawValue.lowercased())")
    if FileManager.default.fileExists(atPath: savedURL.path) {
        return savedURL
    }
    
    downloadBaseURL = try!
        FileManager.default.url(for: .cachesDirectory,
                                in: .userDomainMask,
                                appropriateFor: nil,
                                create: false)
    savedURL = downloadBaseURL.appendingPathComponent("\(book.library.name) - \(book.id).\(format.rawValue.lowercased())")
    if FileManager.default.fileExists(atPath: savedURL.path) {
        return savedURL
    }
    
    if let localBaseUrl = book.library.server.localBaseUrl,
       let formatDataEncoded = book.formats[format.rawValue],
       let formatData = Data(base64Encoded: formatDataEncoded),
       let formatVal = try? JSONSerialization.jsonObject(with: formatData, options: []) as? [String: Any],
       let localFilename = formatVal["filename"] as? String {
        return localBaseUrl.appendingPathComponent(book.library.key, isDirectory: true).appendingPathComponent(localFilename, isDirectory: false)
    }
    
    return savedURL
}

func makeFolioReaderUnzipPath() -> URL? {
    guard let cacheDirectory = try? FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true) else {
        return nil
    }
    let folioReaderUnzipped = cacheDirectory.appendingPathComponent("FolioReaderUnzipped", isDirectory: true)
    if !FileManager.default.fileExists(atPath: folioReaderUnzipped.path) {
        do {
            try FileManager.default.createDirectory(at: folioReaderUnzipped, withIntermediateDirectories: true, attributes: nil)
        } catch {
            return nil
        }
    }
    
    return folioReaderUnzipped
}
