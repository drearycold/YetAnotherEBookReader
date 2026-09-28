//
//  YabrData.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/7/22.
//

import Foundation
import CoreText

enum Format: String, CaseIterable, Identifiable, Codable {
    case UNKNOWN
    
    case EPUB
    case PDF
    case CBZ
    
    
    var id: String { self.rawValue }
    
    var ext: String { self.rawValue.lowercased() }
}

struct FormatInfo: Codable {
    var selected: Bool?
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

enum ReaderType: String, CaseIterable, Identifiable, Codable {
    case UNSUPPORTED
    
    case YabrEPUB
    case YabrPDF
    case ReadiumEPUB
    case ReadiumPDF
    case ReadiumCBZ
    
    var id: String { self.rawValue }
    
    var format: Format {
        switch self {
        case .UNSUPPORTED:
            return .UNKNOWN
        case .YabrEPUB:
            return .EPUB
        case .YabrPDF:
            return .PDF
        case .ReadiumEPUB:
            return .EPUB
        case .ReadiumPDF:
            return .PDF
        case .ReadiumCBZ:
            return .CBZ
        }
    }

    /// YabrPDF relies on iOS 16 APIs (edit menus); older systems read PDFs in
    /// Readium PDF.
    static var isYabrPDFAvailable: Bool {
        if #available(iOS 16.0, macCatalyst 16.0, *) {
            return true
        }
        return false
    }

    /// The reader to actually use on this system.
    func resolved(yabrPDFAvailable: Bool = Self.isYabrPDFAvailable) -> ReaderType {
        self == .YabrPDF && !yabrPDFAvailable ? .ReadiumPDF : self
    }

    /// Readers offered for `format`, preferred first.
    static func readers(for format: Format, yabrPDFAvailable: Bool = Self.isYabrPDFAvailable) -> [ReaderType] {
        let readers: [ReaderType]
        switch format {
        case .EPUB:
            readers = [.YabrEPUB, .ReadiumEPUB]
        case .PDF:
            readers = [.YabrPDF, .ReadiumPDF]
        case .CBZ:
            readers = [.ReadiumCBZ]
        case .UNKNOWN:
            readers = []
        }
        return readers.filter { $0.resolved(yabrPDFAvailable: yabrPDFAvailable) == $0 }
    }
}

struct ReaderInfo {
    let deviceName: String
    let url: URL
    let missing: Bool
    let format: Format
    let readerType: ReaderType
    let position: BookDeviceReadingPosition

    /// Every reader launch goes through here, so a reader unavailable on this
    /// system (YabrPDF before iOS 16) is swapped for its fallback in one place.
    init(deviceName: String, url: URL, missing: Bool, format: Format, readerType: ReaderType, position: BookDeviceReadingPosition) {
        self.deviceName = deviceName
        self.url = url
        self.missing = missing
        self.format = format
        self.readerType = readerType.resolved()
        self.position = position
    }
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

enum calibreUpdatedSignal: Hashable {
    case shelf
    case deleted(String)
    case book(CalibreBook)
    case library(CalibreLibrary)
    case server(CalibreServer)
}
