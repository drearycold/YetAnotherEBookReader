//
//  ReadiumPreferenceRealmMappers.swift
//  YetAnotherEBookReader
//
//  Mapper methods in this file must return detached value objects.
//

import Foundation
import RealmSwift

extension ReadiumPreferenceRealm {
    convenience init(id: String, value: ReadiumPreferenceValue) {
        self.init()
        self.id = id
        apply(value)
    }

    func apply(_ value: ReadiumPreferenceValue) {
        if realm == nil, !value.id.isEmpty {
            id = value.id
        }
        themeMode = value.themeMode
        fontSizePercentage = value.fontSizePercentage
        fontFamily = value.fontFamily
        lineHeight = value.lineHeight
        pageMargins = value.pageMargins
        publisherStyles = value.publisherStyles
        scroll = value.scroll
        textAlign = value.textAlign
        columnCount = value.columnCount
        fontWeight = value.fontWeight
        letterSpacing = value.letterSpacing
        wordSpacing = value.wordSpacing
        hyphens = value.hyphens
        imageFilter = value.imageFilter
        textNormalization = value.textNormalization
        typeScale = value.typeScale
        paragraphIndent = value.paragraphIndent
        paragraphSpacing = value.paragraphSpacing
        volumeKeyPaging = value.volumeKeyPaging
        verticalMargin = value.verticalMargin
        readingProgression = value.readingProgression
        fit = value.fit
        ligatures = value.ligatures
        offsetFirstPage = value.offsetFirstPage
        spread = value.spread
        verticalText = value.verticalText
        pageSpacing = value.pageSpacing
        scrollAxis = value.scrollAxis
        visibleScrollbar = value.visibleScrollbar
    }

    func toValue() -> ReadiumPreferenceValue {
        ReadiumPreferenceValue(
            id: id,
            themeMode: themeMode,
            fontSizePercentage: fontSizePercentage,
            fontFamily: fontFamily,
            lineHeight: lineHeight,
            pageMargins: pageMargins,
            publisherStyles: publisherStyles,
            scroll: scroll,
            textAlign: textAlign,
            columnCount: columnCount,
            fontWeight: fontWeight,
            letterSpacing: letterSpacing,
            wordSpacing: wordSpacing,
            hyphens: hyphens,
            imageFilter: imageFilter,
            textNormalization: textNormalization,
            typeScale: typeScale,
            paragraphIndent: paragraphIndent,
            paragraphSpacing: paragraphSpacing,
            volumeKeyPaging: volumeKeyPaging,
            verticalMargin: verticalMargin,
            readingProgression: readingProgression,
            fit: fit,
            ligatures: ligatures,
            offsetFirstPage: offsetFirstPage,
            spread: spread,
            verticalText: verticalText,
            pageSpacing: pageSpacing,
            scrollAxis: scrollAxis,
            visibleScrollbar: visibleScrollbar
        )
    }
}
