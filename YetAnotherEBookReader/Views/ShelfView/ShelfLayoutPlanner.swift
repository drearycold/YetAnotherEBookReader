//
//  ShelfLayoutPlanner.swift
//  YetAnotherEBookReader
//
//  Created by Codex on 2026-07-10.
//

import CoreGraphics
import Foundation

enum ShelfLayoutWidthClass: Equatable, Sendable {
    case compact
    case regular
}

struct ShelfLayoutInput: Equatable, Sendable {
    let containerSize: CGSize
    let bottomExclusionHeight: CGFloat
    let widthClass: ShelfLayoutWidthClass
    let isEditing: Bool
    let isLoading: Bool
    let adCapabilities: ShelfAdLayoutCapabilities

    init(
        containerSize: CGSize,
        bottomExclusionHeight: CGFloat,
        widthClass: ShelfLayoutWidthClass,
        isEditing: Bool,
        isLoading: Bool,
        adCapabilities: ShelfAdLayoutCapabilities
    ) {
        self.containerSize = containerSize
        self.bottomExclusionHeight = bottomExclusionHeight
        self.widthClass = widthClass
        self.isEditing = isEditing
        self.isLoading = isLoading
        self.adCapabilities = adCapabilities
    }
}

struct ShelfLayoutGeometry: Equatable, Sendable {
    let shelfWidth: CGFloat
    let effectiveViewportHeight: CGFloat
    let columnCount: Int
    let tileWidth: CGFloat
}

enum ShelfTileContent: Equatable, Sendable {
    case book(ShelfBookItem)
    case filler
}

struct ShelfTilePlan: Identifiable, Equatable, Sendable {
    let id: String
    let columnIndex: Int
    let kind: ShelfTileKind
    let content: ShelfTileContent
}

struct RecentShelfRowPlan: Identifiable, Equatable, Sendable {
    let id: String
    let index: Int
    let tiles: [ShelfTilePlan]
    let nativeEndcap: ShelfAdInsertion?
}

enum RecentShelfLayoutElement: Identifiable, Equatable, Sendable {
    case row(RecentShelfRowPlan)
    case banner(ShelfAdInsertion)

    var id: String {
        switch self {
        case .row(let row):
            return row.id
        case .banner(let insertion):
            return insertion.slotID
        }
    }
}

struct RecentShelfLayoutPlan: Equatable, Sendable {
    let geometry: ShelfLayoutGeometry
    let elements: [RecentShelfLayoutElement]
}

enum DiscoverShelfSectionLayoutMode: Equatable, Sendable {
    case fixed
    case horizontalScroll
}

struct DiscoverShelfSectionPlan: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let layoutMode: DiscoverShelfSectionLayoutMode
    let tiles: [ShelfTilePlan]
}

struct DiscoverShelfFillerRowPlan: Identifiable, Equatable, Sendable {
    let id: String
    let tiles: [ShelfTilePlan]
}

enum DiscoverShelfLayoutElement: Identifiable, Equatable, Sendable {
    case section(DiscoverShelfSectionPlan)
    case ad(ShelfAdInsertion)
    case fillerRow(DiscoverShelfFillerRowPlan)

    var id: String {
        switch self {
        case .section(let section):
            return "section:\(section.id)"
        case .ad(let insertion):
            return "ad:\(insertion.slotID)"
        case .fillerRow(let row):
            return "filler:\(row.id)"
        }
    }
}

struct DiscoverShelfLayoutPlan: Equatable, Sendable {
    let geometry: ShelfLayoutGeometry
    let elements: [DiscoverShelfLayoutElement]
}

enum ShelfLayoutPlanner {
    static func recent(books: [ShelfBookItem], input: ShelfLayoutInput) -> RecentShelfLayoutPlan {
        let geometry = makeGeometry(input: input)
        let insertions = ShelfAdLayoutPolicy.recentInsertions(
            bookCount: books.count,
            context: adContext(input: input, geometry: geometry, isEmpty: books.isEmpty)
        )

        var endcapsByRow: [Int: ShelfAdInsertion] = [:]
        var bannersAfterRow: [Int: ShelfAdInsertion] = [:]
        for insertion in insertions {
            switch insertion.kind {
            case .nativeEndcap(let row, _):
                endcapsByRow[row] = insertion
            case .adaptiveBanner(let row):
                bannersAfterRow[row] = insertion
            case .nativeStrip:
                break
            }
        }

        let minimumRowCount = max(
            1,
            Int(ceil(geometry.effectiveViewportHeight / ShelfLegacyMetrics.tileHeight))
        )

        var elements: [RecentShelfLayoutElement] = []
        var bookIndex = 0
        var rowIndex = 0

        while bookIndex < books.count || rowIndex < minimumRowCount {
            var nativeEndcap = endcapsByRow[rowIndex]
            var rowCapacity = geometry.columnCount

            if case .nativeEndcap(_, let columnSpan) = nativeEndcap?.kind {
                rowCapacity = max(0, geometry.columnCount - columnSpan)
                if books.count - bookIndex < rowCapacity {
                    nativeEndcap = nil
                    rowCapacity = geometry.columnCount
                }
            }

            var tiles: [ShelfTilePlan] = []
            for columnIndex in 0..<rowCapacity {
                let content: ShelfTileContent
                let tileID: String
                if bookIndex < books.count {
                    content = .book(books[bookIndex])
                    tileID = "recent-row-\(rowIndex)-tile-\(columnIndex)"
                    bookIndex += 1
                } else {
                    content = .filler
                    tileID = "recent-filler-row-\(rowIndex)-column-\(columnIndex)"
                }

                tiles.append(
                    ShelfTilePlan(
                        id: tileID,
                        columnIndex: columnIndex,
                        kind: ShelfLegacyLayout.tileKind(
                            index: columnIndex,
                            columnCount: geometry.columnCount
                        ),
                        content: content
                    )
                )
            }

            elements.append(
                .row(
                    RecentShelfRowPlan(
                        id: "recent-row-\(rowIndex)",
                        index: rowIndex,
                        tiles: tiles,
                        nativeEndcap: nativeEndcap
                    )
                )
            )

            if let banner = bannersAfterRow[rowIndex] {
                elements.append(.banner(banner))
            }

            rowIndex += 1
        }

        return RecentShelfLayoutPlan(geometry: geometry, elements: elements)
    }

    static func discover(
        sections: [ShelfSectionItem],
        input: ShelfLayoutInput
    ) -> DiscoverShelfLayoutPlan {
        let geometry = makeGeometry(input: input)
        let insertions = ShelfAdLayoutPolicy.discoverInsertions(
            sectionCount: sections.count,
            context: adContext(input: input, geometry: geometry, isEmpty: sections.isEmpty)
        )

        var insertionsBySection: [Int: ShelfAdInsertion] = [:]
        for insertion in insertions {
            switch insertion.kind {
            case .nativeStrip(let afterSection), .adaptiveBanner(let afterSection):
                insertionsBySection[afterSection] = insertion
            case .nativeEndcap:
                break
            }
        }

        var elements: [DiscoverShelfLayoutElement] = []
        for (sectionIndex, section) in sections.enumerated() {
            let isFixed = section.books.count <= geometry.columnCount
            let totalTileCount = isFixed
                ? ShelfLegacyLayout.completedTileCount(
                    itemCount: section.books.count,
                    columnCount: geometry.columnCount
                )
                : section.books.count

            var tiles: [ShelfTilePlan] = []
            for tileIndex in 0..<totalTileCount {
                let content: ShelfTileContent
                let tileID: String
                if tileIndex < section.books.count {
                    content = .book(section.books[tileIndex])
                    tileID = "discover-section-\(section.id)-tile-\(tileIndex)"
                } else {
                    content = .filler
                    tileID = "discover-filler-section-\(section.id)-tile-\(tileIndex)"
                }

                tiles.append(
                    ShelfTilePlan(
                        id: tileID,
                        columnIndex: tileIndex,
                        kind: sectionTileKind(index: tileIndex, totalCount: totalTileCount),
                        content: content
                    )
                )
            }

            elements.append(
                .section(
                    DiscoverShelfSectionPlan(
                        id: section.id,
                        title: section.title,
                        layoutMode: isFixed ? .fixed : .horizontalScroll,
                        tiles: tiles
                    )
                )
            )

            if let insertion = insertionsBySection[sectionIndex] {
                elements.append(.ad(insertion))
            }
        }

        let totalAdHeight = insertions.reduce(CGFloat(0)) { total, insertion in
            total + adHeight(for: insertion)
        }
        let currentHeight = CGFloat(sections.count) * ShelfLegacyMetrics.shelfSectionRowHeight + totalAdHeight
        let remainingHeight = geometry.effectiveViewportHeight - currentHeight
        let fillerRowCount = remainingHeight > 0
            ? Int(ceil(remainingHeight / ShelfLegacyMetrics.tileHeight))
            : 0

        for rowIndex in 0..<fillerRowCount {
            let tiles = (0..<geometry.columnCount).map { columnIndex in
                ShelfTilePlan(
                    id: "discover-filler-row-\(rowIndex)-column-\(columnIndex)",
                    columnIndex: columnIndex,
                    kind: sectionTileKind(index: columnIndex, totalCount: geometry.columnCount),
                    content: .filler
                )
            }
            elements.append(
                .fillerRow(
                    DiscoverShelfFillerRowPlan(
                        id: "discover-filler-row-\(rowIndex)",
                        tiles: tiles
                    )
                )
            )
        }

        return DiscoverShelfLayoutPlan(geometry: geometry, elements: elements)
    }

    private static func makeGeometry(input: ShelfLayoutInput) -> ShelfLayoutGeometry {
        let shelfWidth = max(0, input.containerSize.width)
        let effectiveViewportHeight = max(1, input.containerSize.height - input.bottomExclusionHeight)
        let columnCount = max(1, Int(floor(shelfWidth / ShelfLegacyMetrics.baseTileWidth)))
        let tileWidth = shelfWidth / CGFloat(columnCount)

        return ShelfLayoutGeometry(
            shelfWidth: shelfWidth,
            effectiveViewportHeight: effectiveViewportHeight,
            columnCount: columnCount,
            tileWidth: tileWidth
        )
    }

    private static func adContext(
        input: ShelfLayoutInput,
        geometry: ShelfLayoutGeometry,
        isEmpty: Bool
    ) -> ShelfAdLayoutContext {
        ShelfAdLayoutContext(
            viewportHeight: geometry.effectiveViewportHeight,
            containerWidth: geometry.shelfWidth,
            columnCount: geometry.columnCount,
            isRegularWidth: input.widthClass == .regular,
            isEditing: input.isEditing,
            isLoading: input.isLoading,
            isEmpty: isEmpty,
            capabilities: input.adCapabilities
        )
    }

    private static func sectionTileKind(index: Int, totalCount: Int) -> ShelfTileKind {
        if index == 0 {
            return .left
        } else if index == totalCount - 1 {
            return .right
        } else {
            return .center
        }
    }

    private static func adHeight(for insertion: ShelfAdInsertion) -> CGFloat {
        switch insertion.kind {
        case .nativeStrip:
            return ShelfLegacyMetrics.shelfNativeStripRowHeight
        case .adaptiveBanner:
            return ShelfLegacyMetrics.shelfAdInlineRowHeight
        case .nativeEndcap:
            return 0
        }
    }
}
