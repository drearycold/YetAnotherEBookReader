//
//  ReadiumPreferenceRealm.swift
//  YetAnotherEBookReader
//

import Foundation
import RealmSwift

class ReadiumPreferenceRealm: Object, ObjectKeyIdentifiable {
    @Persisted(primaryKey: true) var id: String = ""
    
    @Persisted var themeMode: Int = 0
    @Persisted var fontSizePercentage: Double = 100.0
    @Persisted var fontFamily: String = "Original"
    @Persisted var lineHeight: Double = 1.2
    @Persisted var pageMargins: Double = 1.0
    @Persisted var publisherStyles: Bool = true
    @Persisted var scroll: Bool = false
    @Persisted var textAlign: Int = 0
    
    @Persisted var columnCount: Int = 0
    @Persisted var fontWeight: Double = 1.0
    @Persisted var letterSpacing: Double = 0.0
    @Persisted var wordSpacing: Double = 0.0
    @Persisted var hyphens: Bool = false
    @Persisted var imageFilter: Int = 0
    @Persisted var textNormalization: Bool = false
    @Persisted var typeScale: Double = 1.2
    @Persisted var paragraphIndent: Double = 0.0
    @Persisted var paragraphSpacing: Double = 0.0
    
    @Persisted var volumeKeyPaging: Bool = false
    @Persisted var verticalMargin: Double = 0.0
    @Persisted var readingProgression: Int = 0 // 0: LTR, 1: RTL
    
    @Persisted var fit: Int = 0 // 0: auto, 1: page, 2: width
    @Persisted var ligatures: Bool = false
    @Persisted var offsetFirstPage: Bool?
    @Persisted var spread: Int = 0 // 0: auto, 1: never, 2: always
    @Persisted var verticalText: Bool = false

    @Persisted var pageSpacing: Double = 0.0
    @Persisted var scrollAxis: Int = 0 // 0: vertical, 1: horizontal
    @Persisted var visibleScrollbar: Bool = true
}
