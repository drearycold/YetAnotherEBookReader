//
//  ReadiumPreferenceValue.swift
//  YetAnotherEBookReader
//

import Foundation

struct ReadiumPreferenceValue: Equatable {
    var id: String = ""

    var themeMode: Int = 0
    var fontSizePercentage: Double = 100.0
    var fontFamily: String = "Original"
    var lineHeight: Double = 1.2
    var pageMargins: Double = 1.0
    var publisherStyles: Bool = true
    var scroll: Bool = false
    var textAlign: Int = 0

    var columnCount: Int = 0
    var fontWeight: Double = 1.0
    var letterSpacing: Double = 0.0
    var wordSpacing: Double = 0.0
    var hyphens: Bool = false
    var imageFilter: Int = 0
    var textNormalization: Bool = false
    var typeScale: Double = 1.2
    var paragraphIndent: Double = 0.0
    var paragraphSpacing: Double = 0.0

    var volumeKeyPaging: Bool = false
    var verticalMargin: Double = 0.0
    var readingProgression: Int = 0

    var fit: Int = 0
    var ligatures: Bool = false
    var offsetFirstPage: Bool?
    var spread: Int = 0
    var verticalText: Bool = false

    var pageSpacing: Double = 0.0
    var scrollAxis: Int = 0
    var visibleScrollbar: Bool = true
}
