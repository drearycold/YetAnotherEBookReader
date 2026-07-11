//
//  ShelfAdLayoutPolicy.swift
//  YetAnotherEBookReader
//
//  Created by Codex on 2026-07-10.
//

import CoreGraphics
import Foundation

struct ShelfAdInsertion: Equatable, Identifiable, Sendable {
    enum Kind: Equatable, Sendable {
        case nativeEndcap(recentRow: Int, columnSpan: Int)
        case nativeStrip(afterSection: Int)
        case adaptiveBanner(afterContentRow: Int)
    }

    let slotID: String
    let kind: Kind

    var id: String { slotID }
}

struct ShelfAdLayoutCapabilities: Equatable, Sendable {
    let nativeAvailable: Bool
    let bannerAvailable: Bool
}

struct ShelfAdLayoutContext: Equatable, Sendable {
    let viewportHeight: CGFloat
    let containerWidth: CGFloat
    let columnCount: Int
    let isRegularWidth: Bool
    let isEditing: Bool
    let isLoading: Bool
    let isEmpty: Bool
    let capabilities: ShelfAdLayoutCapabilities
}

enum ShelfAdLayoutPolicy {
    static let recentNativeMinimumWidth: CGFloat = 800
    static let recentNativeMinimumColumns = 5
    static let recentNativeColumnSpan = 3

    static func recentInsertions(bookCount: Int, context: ShelfAdLayoutContext) -> [ShelfAdInsertion] {
        guard canShowAds(itemCount: bookCount, context: context) else { return [] }
        guard context.columnCount > 0 else { return [] }

        let contentRows = Int(ceil(Double(bookCount) / Double(context.columnCount)))
        guard contentRows > 0 else { return [] }

        if shouldUseRecentNativeEndcap(context: context) {
            return recentNativeEndcapInsertions(bookCount: bookCount, contentRows: contentRows, context: context)
        }

        guard context.capabilities.bannerAvailable else { return [] }

        let rowsPerAd = max(
            1,
            Int(ceil(max(1, context.viewportHeight - ShelfLegacyMetrics.shelfAdInlineRowHeight) / ShelfLegacyMetrics.tileHeight))
        )

        return rowBasedInsertions(
            contentCount: contentRows,
            firstOffset: Int(ceil(Double(rowsPerAd) / 2.0)),
            interval: rowsPerAd
        ) { row in
            ShelfAdInsertion(
                slotID: "recent-banner-after-row-\(row)",
                kind: .adaptiveBanner(afterContentRow: row)
            )
        }
    }

    static func discoverInsertions(sectionCount: Int, context: ShelfAdLayoutContext) -> [ShelfAdInsertion] {
        guard canShowDiscoverAds(sectionCount: sectionCount, context: context) else { return [] }

        if context.isRegularWidth, context.capabilities.nativeAvailable {
            let sectionsPerAd = max(
                1,
                Int(ceil(max(1, context.viewportHeight - ShelfLegacyMetrics.shelfNativeStripRowHeight) / ShelfLegacyMetrics.shelfSectionRowHeight))
            )

            return sectionBasedInsertions(sectionCount: sectionCount, interval: sectionsPerAd) { sectionIndex in
                ShelfAdInsertion(
                    slotID: "discover-ad-after-section-\(sectionIndex)",
                    kind: .nativeStrip(afterSection: sectionIndex)
                )
            }
        }

        guard context.capabilities.bannerAvailable else { return [] }

        let sectionsPerAd = max(
            1,
            Int(ceil(max(1, context.viewportHeight - ShelfLegacyMetrics.shelfAdInlineRowHeight) / ShelfLegacyMetrics.shelfSectionRowHeight))
        )

        return sectionBasedInsertions(sectionCount: sectionCount, interval: sectionsPerAd) { sectionIndex in
            ShelfAdInsertion(
                slotID: "discover-banner-after-section-\(sectionIndex)",
                kind: .adaptiveBanner(afterContentRow: sectionIndex)
            )
        }
    }

    private static func canShowDiscoverAds(sectionCount: Int, context: ShelfAdLayoutContext) -> Bool {
        guard sectionCount > 0 else { return false }
        guard !context.isEditing, !context.isLoading, !context.isEmpty else { return false }
        guard context.capabilities.nativeAvailable || context.capabilities.bannerAvailable else { return false }

        return CGFloat(sectionCount) * ShelfLegacyMetrics.shelfSectionRowHeight > context.viewportHeight
    }

    private static func canShowAds(itemCount: Int, context: ShelfAdLayoutContext) -> Bool {
        guard itemCount > 0 else { return false }
        guard !context.isEditing, !context.isLoading, !context.isEmpty else { return false }
        guard context.capabilities.nativeAvailable || context.capabilities.bannerAvailable else { return false }

        return publisherContentHeight(itemCount: itemCount, context: context) > context.viewportHeight
    }

    private static func publisherContentHeight(itemCount: Int, context: ShelfAdLayoutContext) -> CGFloat {
        if context.columnCount > 0 {
            let rows = Int(ceil(Double(itemCount) / Double(context.columnCount)))
            return CGFloat(rows) * ShelfLegacyMetrics.tileHeight
        }

        return CGFloat(itemCount) * ShelfLegacyMetrics.shelfSectionRowHeight
    }

    private static func shouldUseRecentNativeEndcap(context: ShelfAdLayoutContext) -> Bool {
        context.isRegularWidth
            && context.containerWidth >= recentNativeMinimumWidth
            && context.columnCount >= recentNativeMinimumColumns
            && context.capabilities.nativeAvailable
    }

    private static func recentNativeEndcapInsertions(
        bookCount: Int,
        contentRows: Int,
        context: ShelfAdLayoutContext
    ) -> [ShelfAdInsertion] {
        let rowsPerAd = max(1, Int(ceil(context.viewportHeight / ShelfLegacyMetrics.tileHeight)))
        let leftColumnCount = context.columnCount - recentNativeColumnSpan
        guard leftColumnCount > 0 else { return [] }

        return rowBasedInsertions(
            contentCount: contentRows,
            firstOffset: Int(ceil(Double(rowsPerAd) / 2.0)),
            interval: rowsPerAd
        ) { row in
            let rowStart = row * context.columnCount
            guard bookCount >= rowStart + leftColumnCount else { return nil }

            return ShelfAdInsertion(
                slotID: "recent-native-endcap-row-\(row)",
                kind: .nativeEndcap(recentRow: row, columnSpan: recentNativeColumnSpan)
            )
        }
    }

    private static func rowBasedInsertions(
        contentCount: Int,
        firstOffset: Int,
        interval: Int,
        makeInsertion: (Int) -> ShelfAdInsertion?
    ) -> [ShelfAdInsertion] {
        guard contentCount > 0, interval > 0 else { return [] }

        var insertions: [ShelfAdInsertion] = []
        var row = max(0, firstOffset)
        while row < contentCount {
            if let insertion = makeInsertion(row) {
                insertions.append(insertion)
            }
            row += interval
        }
        return insertions
    }

    private static func sectionBasedInsertions(
        sectionCount: Int,
        interval: Int,
        makeInsertion: (Int) -> ShelfAdInsertion
    ) -> [ShelfAdInsertion] {
        guard sectionCount > 0, interval > 0 else { return [] }

        let firstAfterSection = max(0, Int(ceil(Double(interval) / 2.0)) - 1)
        guard firstAfterSection < sectionCount - 1 else { return [] }

        var insertions: [ShelfAdInsertion] = []
        var sectionIndex = firstAfterSection
        while sectionIndex < sectionCount - 1 {
            insertions.append(makeInsertion(sectionIndex))
            sectionIndex += interval
        }
        return insertions
    }
}
