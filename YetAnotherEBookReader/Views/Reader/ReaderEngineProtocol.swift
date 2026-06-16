//
//  ReaderEngineProtocol.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026-06-15.
//

import Foundation
import UIKit

struct ReaderEnginePosition {
    var pageNumber: Int = 1
    var maxPage: Int = 1
    var pageOffsetX: Int = 0
    var pageOffsetY: Int = 0
    var bookProgress: Double = 0.0      // 0 - 100
    var chapterProgress: Double = 0.0   // 0 - 100
    var chapterName: String? = nil
    var cfi: String? = nil
    
    // For non-linear book structures (e.g. PDF/FolioReader custom tracking)
    var structuralStyle: Int = 0
    var structuralRootPageNumber: Int = 0
    var positionTrackingStyle: Int = 0
}

struct ReaderEnginePreferences {
    var themeMode: Int = 0 // 0: Light, 1: Sepia, 2: Dark
    var fontSizePercentage: Double = 100.0
    var fontFamily: String = "Original"
    var lineHeight: Double = 1.2
    var pageMargins: Double = 1.0
    var scroll: Bool = false
    var scrollDirection: Int = 0 // 0: vertical, 1: horizontal
    var volumeKeyPaging: Bool = false
}

struct ReaderEngineHighlight {
    var id: String
    var bookId: String
    var readerName: String // "YabrEPUB" or "YabrPDF"
    var page: Int
    var startOffset: Int = 0
    var endOffset: Int = 0
    var date: Date
    var type: Int
    var note: String? = nil
    var tocFamilyTitles: [String] = []
    var content: String
    var contentPost: String = ""
    var contentPre: String = ""
    
    // EPUB specific
    var cfiStart: String? = nil
    var cfiEnd: String? = nil
    var spineName: String? = nil
    
    // PDF specific
    var ranges: String? = nil
    
    var removed: Bool = false
}

protocol ReaderEngineDelegate: AnyObject {
    func readerEngine(_ engine: AnyObject, didUpdatePosition position: ReaderEnginePosition)
    func readerEngine(_ engine: AnyObject, didAddHighlight highlight: ReaderEngineHighlight)
    func readerEngine(_ engine: AnyObject, didRemoveHighlight highlightId: String)
    func readerEngine(_ engine: AnyObject, didUpdatePreferences prefs: ReaderEnginePreferences)
}

protocol ReaderEngineController {
    func applyPreferences(_ preferences: ReaderEnginePreferences)
    func applyHighlights(_ highlights: [ReaderEngineHighlight])
}
