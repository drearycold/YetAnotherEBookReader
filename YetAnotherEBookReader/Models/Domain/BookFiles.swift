//
//  BookFiles.swift
//  YetAnotherEBookReader
//
//  Created by liyi on 2021/6/1.
//

import Foundation
import CryptoKit
import OSLog

private let bookFilesLogger = Logger(subsystem: "YetAnotherEBookReader", category: "BookFiles")

private struct DownloadDirCache {
    static let url: URL? = {
        guard let docURL = try? FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        let dirURL = docURL.appendingPathComponent("Downloaded Books", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dirURL.path) {
            try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true, attributes: nil)
        }
        return dirURL
    }()
}

func getBookBaseUrl(id: Int32, library: CalibreLibrary, localFilename: String? = nil) -> URL? {
    if library.server.isLocal {
        guard let localBaseUrl = library.server.localBaseUrl,
              let localFilename = localFilename
        else { return nil }
        
        return localBaseUrl
                    .appendingPathComponent(library.key, isDirectory: true)
                    .appendingPathComponent(localFilename, isDirectory: false)
    }
    guard let downloadBaseURL = DownloadDirCache.url else { return nil }
    
    return downloadBaseURL.appendingPathComponent("\(library.key) - \(id)")
}

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
        guard let downloadBaseURL = DownloadDirCache.url else { return nil }
        let savedURL = downloadBaseURL
            .appendingPathComponent("\(book.library.key) - \(book.id).\(format.rawValue.lowercased())")
        
        return savedURL
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
        bookFilesLogger.error("Failed to remove FolioReader unzip path: \(error.localizedDescription)")
    }
}

func sha256new(for fileURL: URL) -> Data? {
    guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
    defer { try? handle.close() }
    let bufferSize = 1024*1024
    var hasher = SHA256()
    do {
        while try autoreleasepool(invoking: {
            guard let chunk = try handle.read(upToCount: bufferSize), !chunk.isEmpty else { return false }
            hasher.update(data: chunk)
            return true
        }) {}
    } catch {
        return nil
    }
    let digest = hasher.finalize()
    return Data(digest)
    
    // Here's how to convert to string form
    //return digest.map { String(format: "%02hhx", $0) }.joined()
}

enum ImportError: String, CaseIterable, Hashable, Identifiable, Error, Sendable {
    case protocolUnsupported
    case libraryAbsent
    case securityFail
    case idCalcFail
    case destConflict
    case fileOpFail
    case loadMetaFail
    case recoveryRequired
    case invalidArg
    case tooManyFiles
    case formatUnsupported
    case cancelled
    
    var id: String {
        return self.rawValue
    }
}

func localBookID(_ url: URL) -> Int32? {
    guard let digest = sha256new(for: url) else { return nil }
    return Int32(bigEndian: digest.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) })
}

struct LocalBookImportRequest: Sendable {
    let id = UUID()
    let url: URL
    var doMove = false
    var overwrite = false
    var asNew = false
}

struct BookImportInfo: Sendable {
    let request: LocalBookImportRequest
    var url: URL { request.url }
    var overwrite: Bool { request.overwrite }
    var asNew: Bool { request.asNew }
    var bookId: Int32?
    var error: ImportError?
    var cleanupPending = false
    var recoveryFolder: String?
    var databaseID: UUID?
    var libraryID: String?

    mutating func with(error: ImportError) -> BookImportInfo {
        self.error = error
        return self
    }
}

enum BookFileRemovalResult: Equatable {
    case committed(cleanupPending: Bool = false)
    case fileFailed
    case storageFailed
    case recoveryRequired(String?)

    var succeeded: Bool {
        if case .committed = self { return true }
        return false
    }

    var cleanupPending: Bool { self == .committed(cleanupPending: true) }

    var message: String {
        switch self {
        case .committed: return "The book was updated. Some temporary files could not be removed."
        case .fileFailed: return "The book file could not be removed. Try again."
        case .storageFailed: return "The library change could not be saved. Try again."
        case .recoveryRequired(let folder):
            return "The file could not be restored. A copy was kept for recovery\(folder.map { " in \($0)" } ?? "")."
        }
    }
}
