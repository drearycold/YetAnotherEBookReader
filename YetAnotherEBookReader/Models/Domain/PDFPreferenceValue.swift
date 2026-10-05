//
//  PDFPreferenceValue.swift
//  YetAnotherEBookReader
//

import Foundation

enum PDFAutoScaler: String, CaseIterable, Identifiable {
    case Custom
    case Width
    case Height
    case Page

    var id: String { rawValue }
}

enum PDFReadDirection: String, CaseIterable, Identifiable {
    case LtR_TtB
    case TtB_RtL

    var id: String { rawValue }
}

enum PDFScrollDirection: String, CaseIterable, Identifiable {
    case Vertical
    case Horizontal

    var id: String { rawValue }
}

enum PDFThemeMode: String, CaseIterable, Identifiable {
    case none
    case serpia
    case forest
    case dark

    var id: String { rawValue }
}

enum PDFLayoutMode: String, CaseIterable, Identifiable {
    case Page
    case Scroll

    var id: String { rawValue }
}

/// Two-page spreads (#97): a landscape scan of two book pages, read one half at
/// a time. Auto splits a landscape page that shows a gutter or binding shadow at
/// its centre; On splits every page.
enum PDFSpreadMode: String, CaseIterable, Identifiable {
    case Off
    case Auto
    case On

    var id: String { rawValue }
}

/// Multi-column text (#19, #97): Auto reads the columns a page is found to have
/// one at a time, with full-width blocks in between.
enum PDFColumnsMode: String, CaseIterable, Identifiable {
    case Off
    case Auto

    var id: String { rawValue }
}

struct PDFPreferenceValue: Equatable {
    var themeMode = PDFThemeMode.serpia
    var selectedAutoScaler = PDFAutoScaler.Width
    var pageMode = PDFLayoutMode.Page
    var readingDirection = PDFReadDirection.LtR_TtB
    var scrollDirection = PDFScrollDirection.Vertical

    var hMarginAutoScaler = 5.0
    var vMarginAutoScaler = 5.0
    var hMarginDetectStrength = 2.0
    var vMarginDetectStrength = 2.0
    var marginOffset = 0.0
    var lastScale = 1.0
    var rememberInPagePosition = true
    var spreadMode = PDFSpreadMode.Off
    var columnsMode = PDFColumnsMode.Off
}
