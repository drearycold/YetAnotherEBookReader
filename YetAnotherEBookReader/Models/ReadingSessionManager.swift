//
//  ReadingSessionManager.swift
//  YetAnotherEBookReader
//
//  Created by Gemini on 2026/4/6.
//

import Foundation
import Combine
import SwiftUI
import RealmSwift

class ReadingSessionManager: ObservableObject {
    @Published var presentingEBookReaderFromShelf = false
    
    @Published var readingBookInShelfId: String? = nil {
        didSet {
            guard let readingBookInShelfId = readingBookInShelfId else {
                readingBook = nil
                return
            }
            if readingBook?.inShelfId != readingBookInShelfId {
                readingBook = modelData?.booksInShelf[readingBookInShelfId] ?? modelData?.getBook(for: readingBookInShelfId)
            }
        }
    }
    
    @available(*, deprecated)
    @Published var readingBook: CalibreBook? = nil {
        didSet {
            guard let readingBook = readingBook else {
                self.selectedPosition = ""
                return
            }
            
            readerInfo = prepareBookReading(book: readingBook)
            self.selectedPosition = readerInfo?.position.id ?? modelData?.deviceName ?? ""
        }
    }
    
    @Published var readerInfo: ReaderInfo? = nil
    @Published var selectedPosition = ""
    
    weak var modelData: ModelData?
    
    init(modelData: ModelData? = nil) {
        self.modelData = modelData
    }
    
    func setup(modelData: ModelData) {
        self.modelData = modelData
    }
    
    func prepareBookReading(book: CalibreBook) -> ReaderInfo {
        guard let modelData = modelData else {
            return ReaderInfo(deviceName: "", url: URL(fileURLWithPath: "/invalid"), missing: true, format: .UNKNOWN, readerType: .UNSUPPORTED, position: .init(readerName: ReaderType.UNSUPPORTED.id))
        }
        
        var candidatePositions = [BookDeviceReadingPosition]()

        //preference: device, latest, selected, any
        if let position = book.readPos.getPosition(modelData.deviceName) {
            candidatePositions.append(position)
        }
        if let position = book.readPos.getDevices().first {
            candidatePositions.append(position)
        }
//        candidatePositions.append(contentsOf: book.readPos.getDevices())
        if let format = modelData.getPreferredFormat(for: book) {
            candidatePositions.append(
                book.readPos.createInitial(
                    deviceName: modelData.deviceName,
                    reader: modelData.getPreferredReader(for: format)
                )
            )
        }
        
        let formatReaderPairArray: [(Format, ReaderType, BookDeviceReadingPosition)] = candidatePositions.compactMap { position in
            guard let reader = ReaderType(rawValue: position.readerName), reader != .UNSUPPORTED else { return nil }
            let format = reader.format
            
            return (format, reader, position)
        }
        
        let formatReaderPair = formatReaderPairArray.first ?? (Format.UNKNOWN, ReaderType.UNSUPPORTED, BookDeviceReadingPosition.init(readerName: ReaderType.UNSUPPORTED.id))
        let savedURL = getSavedUrl(book: book, format: formatReaderPair.0) ?? URL(fileURLWithPath: "/invalid")
        let urlMissing = !FileManager.default.fileExists(atPath: savedURL.path)
        
        return ReaderInfo(deviceName: modelData.deviceName, url: savedURL, missing: urlMissing, format: formatReaderPair.0, readerType: formatReaderPair.1, position: formatReaderPair.2)
    }
    
    func prepareBookReading(url: URL, format: Format, readerType: ReaderType, position: BookDeviceReadingPosition) {
        let readerInfo = ReaderInfo(
            deviceName: modelData?.deviceName ?? "",
            url: url,
            missing: false,
            format: format,
            readerType: readerType,
            position: position
        )
        self.readerInfo = readerInfo
    }
    
    func listBookDeviceReadingPositionHistory(library: CalibreLibrary? = nil, bookId: Int32? = nil, startDateAfter: Date? = nil) -> [String: [BookDeviceReadingPositionHistory]] {
        guard let modelData = modelData, let realm = try? Realm(configuration: modelData.realmConf) else { return [:] }
        
        var pred: NSPredicate?
        if let library = library, let bookId = bookId {
            pred = NSPredicate(format: "bookId = %@", "\(library.key) - \(bookId)")
            if let startDateAfter = startDateAfter {
                pred = NSPredicate(format: "bookId = %@ AND startDatetime >= %@", "\(library.key) - \(bookId)", startDateAfter as NSDate)
            }
        } else {
            if let startDateAfter = startDateAfter {
                pred = NSPredicate(
                    format: "startDatetime >= %@",
                    startDateAfter as NSDate
                )
            }
        }
        
        var results = realm.objects(BookDeviceReadingPositionHistoryRealm.self);
        if let predNotNil = pred {
            results = results.filter(predNotNil)
        }
        results = results.sorted(by: [SortDescriptor(keyPath: "startDatetime", ascending: false)])
        
        var historyList: [BookDeviceReadingPositionHistory] = results.filter { $0.endPosition != nil }
            .map { BookDeviceReadingPositionHistory(managedObject: $0) }
        
        if let library = library, let bookId = bookId {
            let bookInShelfId = CalibreBook(id: bookId, library: library).inShelfId
            if let book = modelData.booksInShelf[bookInShelfId] {
                historyList.append(contentsOf: book.readPos.sessions(list: startDateAfter))
            }
        } else {
            modelData.booksInShelf.forEach {
                historyList.append(contentsOf: $0.value.readPos.sessions(list: startDateAfter))
            }
        }
        
        let idMap = modelData.booksInShelf.reduce(into: [String: String]()) { partialResult, entry in
            partialResult["\(entry.value.library.key) - \(entry.value.id)"] = entry.value.inShelfId
        }
        
        return historyList.sorted(by:{ $0.startDatetime > $1.startDatetime }).removingDuplicates().reduce(into: [:]) { partialResult, history in
            guard let inShelfId = idMap[history.bookId] else { return }
            
            if partialResult[inShelfId] == nil {
                partialResult[inShelfId] = [history]
            } else {
                partialResult[inShelfId]?.append(history)
            }
        }
    }
}
