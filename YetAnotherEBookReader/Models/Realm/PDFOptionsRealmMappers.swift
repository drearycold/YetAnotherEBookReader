//
//  PDFOptionsRealmMappers.swift
//  YetAnotherEBookReader
//

import Foundation
import RealmSwift

extension PDFOptions {
    func toValue() -> PDFPreferenceValue {
        PDFPreferenceValue(
            themeMode: themeMode,
            selectedAutoScaler: selectedAutoScaler,
            pageMode: pageMode,
            readingDirection: readingDirection,
            scrollDirection: scrollDirection,
            hMarginAutoScaler: hMarginAutoScaler,
            vMarginAutoScaler: vMarginAutoScaler,
            hMarginDetectStrength: hMarginDetectStrength,
            vMarginDetectStrength: vMarginDetectStrength,
            marginOffset: marginOffset,
            lastScale: lastScale,
            rememberInPagePosition: rememberInPagePosition
        )
    }

    func apply(_ value: PDFPreferenceValue) {
        themeMode = value.themeMode
        selectedAutoScaler = value.selectedAutoScaler
        pageMode = value.pageMode
        readingDirection = value.readingDirection
        scrollDirection = value.scrollDirection
        hMarginAutoScaler = value.hMarginAutoScaler
        vMarginAutoScaler = value.vMarginAutoScaler
        hMarginDetectStrength = value.hMarginDetectStrength
        vMarginDetectStrength = value.vMarginDetectStrength
        marginOffset = value.marginOffset
        lastScale = value.lastScale
        rememberInPagePosition = value.rememberInPagePosition
    }
}
