//
//  BookFiles.swift
//  YetAnotherEBookReader
//
//  Created by liyi on 2021/6/1.
//

import Foundation

func getSavedUrl(book: CalibreBook, format: Format) -> URL? {
    if book.library.server.isLocal {
        if let localBaseUrl = book.library.server.localBaseUrl,
           let formatInfo = book.formats[format.rawValue],
           let localFilename = formatInfo.filename {
            return localBaseUrl
                    .appendingPathComponent(book.library.key, isDirectory: true)
                    .appendingPathComponent(localFilename, isDirectory: false)
        }
    } else {
        if let downloadBaseURL =
            try? FileManager.default.url(for: .documentDirectory,
                                    in: .userDomainMask,
                                    appropriateFor: nil,
                                    create: false)
            .appendingPathComponent("Downloaded Books", isDirectory: true) {
            if FileManager.default.fileExists(atPath: downloadBaseURL.path) == false {
                do {
                    try FileManager.default.createDirectory(at: downloadBaseURL, withIntermediateDirectories: true, attributes: nil)
                } catch {
                    print(error)
                    return nil
                }
            }
            let savedURL = downloadBaseURL
                .appendingPathComponent("\(book.library.key) - \(book.id).\(format.rawValue.lowercased())")
            
            return savedURL
        }
    }
    book.formats.sorted {
        $0.key < $1.key
    }.compactMap {
        if let format = Format(rawValue: $0.key) {
            return (format, $0.value)
        }
        return nil
    } as [(Format, FormatInfo)]
    return nil
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

func removeFolioCache(book: CalibreBook, format: Format) {
    guard let savedURL = getSavedUrl(book: book, format: format),
          let folioUnzippedPath = makeFolioReaderUnzipPath(),
          FileManager.default.fileExists(atPath: folioUnzippedPath.appendingPathComponent(savedURL.lastPathComponent, isDirectory: true).path)
    else { return }
    
    do {
        try FileManager.default.removeItem(at: folioUnzippedPath.appendingPathComponent(savedURL.lastPathComponent, isDirectory: true))
    } catch {
        print(error)
    }
}
