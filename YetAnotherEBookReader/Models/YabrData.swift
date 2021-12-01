//
//  YabrData.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/7/22.
//

import Foundation
import CoreText

enum Format: String, CaseIterable, Identifiable {
    case UNKNOWN
    
    case EPUB
    case PDF
    case CBZ
    
    
    var id: String { self.rawValue }
    
    var ext: String { self.rawValue.lowercased() }
}

struct FormatInfo: Codable {
    var filename: String?
    var serverSize: UInt64
    var serverMTime: Date
    var cached: Bool
    var cacheSize: UInt64
    var cacheMTime: Date
    var manifest: Data?   //json data
    
    var cacheUptoDate: Bool {
        serverMTime.timeIntervalSince(cacheMTime) < 60
    }
}

enum ReaderType: String, CaseIterable, Identifiable {
    case UNSUPPORTED
    
    case YabrEPUB
    case YabrPDF
    case ReadiumEPUB
    case ReadiumPDF
    case ReadiumCBZ
    
    var id: String { self.rawValue }
}

struct ReaderInfo {
    let url: URL
    let format: Format
    let readerType: ReaderType
    let position: BookDeviceReadingPosition
}

struct FontInfo {
    var descriptor: CTFontDescriptor
    
    var displayName: String?
    var localizedName: String?
    var fileURL: URL?
    var languages = Set<String>()
    
    init(descriptor: CTFontDescriptor) {
        self.descriptor = descriptor
        
        if let attrib = CTFontDescriptorCopyAttribute(descriptor, kCTFontDisplayNameAttribute),
           CFGetTypeID(attrib) == CFStringGetTypeID(),
           let displayName = attrib as? String {
            self.displayName = displayName
        }
        if let attrib = CTFontDescriptorCopyAttribute(descriptor, kCTFontURLAttribute),
           CFGetTypeID(attrib) == CFURLGetTypeID() {
            self.fileURL = attrib as? URL
        }
        if let attrib = CTFontDescriptorCopyAttribute(descriptor, kCTFontLanguagesAttribute),
           CFGetTypeID(attrib) == CFArrayGetTypeID(),
           let languages = attrib as? [String] {
            self.languages.formUnion(languages)
        }
        if let attrib = CTFontDescriptorCopyLocalizedAttribute(descriptor, kCTFontDisplayNameAttribute, nil),
           CFGetTypeID(attrib) == CFStringGetTypeID(),
           let localizedName = attrib as? String {
            self.localizedName = localizedName
        }
    }
}

extension Notification.Name {
    static let YABR_BooksRefreshed = Notification.Name("YABR.booksRefreshed")
    static let YABR_ReadingBookRemovedFromShelf = Notification.Name("YABR.readingBookRemovedFromShelf")
    static let YABR_BookImported = Notification.Name("YABR.bookImported")
    static let YABR_DismissAll = Notification.Name("YABR.dismissAll")
    static let YABR_ServerAdded = Notification.Name("YABR.serverAdded")
}
