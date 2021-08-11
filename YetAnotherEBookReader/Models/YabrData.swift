//
//  YabrData.swift
//  YetAnotherEBookReader
//
//  Created by 京太郎 on 2021/7/22.
//

import Foundation

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
    
    var cacheUptoDate: Bool {
        serverMTime.timeIntervalSince(cacheMTime) < 60
    }
}

enum ReaderType: String, CaseIterable, Identifiable {
    case UNSUPPORTED
    
    case FolioReader
    case YabrPDFView
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
