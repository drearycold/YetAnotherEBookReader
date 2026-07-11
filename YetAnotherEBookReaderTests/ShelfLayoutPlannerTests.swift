//
//  ShelfLayoutPlannerTests.swift
//  YetAnotherEBookReaderTests
//
//  Created by Codex on 2026-07-10.
//

import XCTest
@testable import YetAnotherEBookReader

final class ShelfLayoutPlannerTests: XCTestCase {
    private func book(_ id: String) -> ShelfBookItem {
        ShelfBookItem(
            id: id,
            title: id,
            coverURL: "",
            progress: 0,
            status: .ready
        )
    }

    private func input(
        width: CGFloat = 600,
        height: CGFloat = 800,
        bottomExclusionHeight: CGFloat = 0,
        widthClass: ShelfLayoutWidthClass = .regular,
        isEditing: Bool = false,
        isLoading: Bool = false,
        nativeAvailable: Bool = true,
        bannerAvailable: Bool = true
    ) -> ShelfLayoutInput {
        ShelfLayoutInput(
            containerSize: CGSize(width: width, height: height),
            bottomExclusionHeight: bottomExclusionHeight,
            widthClass: widthClass,
            isEditing: isEditing,
            isLoading: isLoading,
            adCapabilities: ShelfAdLayoutCapabilities(
                nativeAvailable: nativeAvailable,
                bannerAvailable: bannerAvailable
            )
        )
    }

    private func recentRows(_ plan: RecentShelfLayoutPlan) -> [RecentShelfRowPlan] {
        plan.elements.compactMap { element in
            guard case .row(let row) = element else { return nil }
            return row
        }
    }

    private func recentBooks(_ plan: RecentShelfLayoutPlan) -> [String] {
        recentRows(plan).flatMap { row in
            row.tiles.compactMap { tile in
                guard case .book(let book) = tile.content else { return nil }
                return book.id
            }
        }
    }

    private func discoverBooks(_ plan: DiscoverShelfLayoutPlan) -> [String] {
        var ids: [String] = []
        for element in plan.elements {
            guard case .section(let section) = element else { continue }
            for tile in section.tiles {
                if case .book(let book) = tile.content {
                    ids.append(book.id)
                }
            }
        }
        return ids
    }

    func testRecentEmptyAndIncompleteRowsCreateDeterministicFillers() {
        let emptyPlan = ShelfLayoutPlanner.recent(
            books: [],
            input: input(width: 300, height: 400)
        )
        let singleBookPlan = ShelfLayoutPlanner.recent(
            books: [book("book-1")],
            input: input(width: 300, height: 400)
        )

        XCTAssertEqual(emptyPlan.geometry.columnCount, 2)
        XCTAssertEqual(recentRows(emptyPlan).count, 2)
        XCTAssertEqual(recentRows(singleBookPlan).first?.tiles.count, 2)
        XCTAssertEqual(recentBooks(singleBookPlan), ["book-1"])
        XCTAssertEqual(
            recentRows(singleBookPlan).first?.tiles.compactMap { tile in
                if case .filler = tile.content { return tile.id }
                return nil
            },
            ["recent-filler-row-0-column-1"]
        )
    }

    func testRecentNativeEndcapPreservesOrderAndConsumesItsColumnSpan() {
        let books = (0..<60).map { index in book("book-\(index)") }
        let plan = ShelfLayoutPlanner.recent(
            books: books,
            input: input(width: 1024, height: 800)
        )

        XCTAssertEqual(recentBooks(plan), books.map { $0.id })
        XCTAssertEqual(Set(recentBooks(plan)).count, books.count)

        let endcapRows = recentRows(plan).filter { $0.nativeEndcap != nil }
        XCTAssertFalse(endcapRows.isEmpty)
        for row in endcapRows {
            guard case .nativeEndcap(_, let columnSpan) = row.nativeEndcap?.kind else {
                XCTFail("Expected native end-cap")
                continue
            }
            XCTAssertEqual(row.tiles.count + columnSpan, plan.geometry.columnCount)
        }
    }

    func testRecentCompactBannerIsAnIndependentElementAfterItsRow() {
        let plan = ShelfLayoutPlanner.recent(
            books: (0..<30).map { index in book("book-\(index)") },
            input: input(width: 430, height: 600, widthClass: .compact)
        )

        guard let bannerIndex = plan.elements.firstIndex(where: {
            if case .banner = $0 { return true }
            return false
        }) else {
            return XCTFail("Expected compact banner")
        }

        XCTAssertGreaterThan(bannerIndex, 0)
        if case .row(let row) = plan.elements[bannerIndex - 1] {
            XCTAssertEqual(row.index, 2)
        } else {
            XCTFail("Banner must follow a row")
        }
    }

    func testRecentRotationRecomputesLegalGeometryAndKeepsBooks() {
        let books = (0..<12).map { index in book("book-\(index)") }
        let portrait = ShelfLayoutPlanner.recent(
            books: books,
            input: input(width: 600, height: 800)
        )
        let landscape = ShelfLayoutPlanner.recent(
            books: books,
            input: input(width: 1024, height: 600)
        )

        XCTAssertNotEqual(portrait.geometry.columnCount, landscape.geometry.columnCount)
        XCTAssertEqual(recentBooks(portrait), books.map { $0.id })
        XCTAssertEqual(recentBooks(landscape), books.map { $0.id })
        let landscapeIDs = landscape.elements.map { $0.id }
        XCTAssertEqual(landscapeIDs.count, Set(landscapeIDs).count)
    }

    func testDiscoverFixedSectionIsPaddedToACompleteRow() {
        let section = ShelfSectionItem(
            id: "section-1",
            title: "Section",
            books: [book("book-1")]
        )
        let plan = ShelfLayoutPlanner.discover(
            sections: [section],
            input: input(width: 600, height: 800)
        )

        guard case .section(let sectionPlan) = plan.elements.first else {
            return XCTFail("Expected section")
        }

        XCTAssertEqual(sectionPlan.layoutMode, .fixed)
        XCTAssertEqual(sectionPlan.tiles.count, plan.geometry.columnCount)
        XCTAssertEqual(discoverBooks(plan), ["book-1"])
        XCTAssertEqual(sectionPlan.tiles.first?.kind, .left)
        XCTAssertEqual(sectionPlan.tiles.last?.kind, .right)
    }

    func testDiscoverHorizontalSectionHasNoFillersAndKeepsEdgeKinds() {
        let section = ShelfSectionItem(
            id: "section-1",
            title: "Section",
            books: (0..<6).map { index in book("book-\(index)") }
        )
        let plan = ShelfLayoutPlanner.discover(
            sections: [section],
            input: input(width: 600, height: 800)
        )

        guard case .section(let sectionPlan) = plan.elements.first else {
            return XCTFail("Expected section")
        }

        XCTAssertEqual(sectionPlan.layoutMode, DiscoverShelfSectionLayoutMode.horizontalScroll)
        XCTAssertEqual(sectionPlan.tiles.count, 6)
        XCTAssertTrue(sectionPlan.tiles.allSatisfy { if case .filler = $0.content { return false }; return true })
        XCTAssertEqual(sectionPlan.tiles.first?.kind, .left)
        XCTAssertEqual(sectionPlan.tiles.last?.kind, .right)
    }

    func testDiscoverAdsOnlyAppearBetweenSections() {
        let sections = (0..<8).map { index in
            ShelfSectionItem(id: "section-\(index)", title: "Section \(index)", books: [book("book-\(index)")])
        }
        let plan = ShelfLayoutPlanner.discover(
            sections: sections,
            input: input(width: 1024, height: 696)
        )

        let sectionIndexes = plan.elements.enumerated().compactMap { index, element -> Int? in
            if case .section = element { return index }
            return nil
        }
        let adIndexes = plan.elements.enumerated().compactMap { index, element -> Int? in
            if case .ad = element { return index }
            return nil
        }

        XCTAssertFalse(adIndexes.isEmpty)
        for adIndex in adIndexes {
            XCTAssertGreaterThan(adIndex, sectionIndexes.first ?? 0)
            XCTAssertLessThan(adIndex, sectionIndexes.last ?? plan.elements.count)
            XCTAssertTrue(plan.elements[adIndex - 1].id.hasPrefix("section:"))
            XCTAssertTrue(plan.elements[adIndex + 1].id.hasPrefix("section:"))
        }
    }

    func testDiscoverFillerRowsIncludeEmptyShelfAndAdHeight() {
        let emptyPlan = ShelfLayoutPlanner.discover(
            sections: [],
            input: input(width: 600, height: 600)
        )
        let sections = (0..<8).map { index in
            ShelfSectionItem(id: "section-\(index)", title: "Section \(index)", books: [book("book-\(index)")])
        }
        let planWithSections = ShelfLayoutPlanner.discover(
            sections: sections,
            input: input(width: 1024, height: 696)
        )

        let emptyFillerCount = emptyPlan.elements.filter {
            if case .fillerRow = $0 { return true }
            return false
        }.count
        let sectionFillerCount = planWithSections.elements.filter {
            if case .fillerRow = $0 { return true }
            return false
        }.count

        XCTAssertEqual(emptyFillerCount, 3)
        XCTAssertEqual(sectionFillerCount, 0)
    }

    func testPlannerElementIDsAreUniqueAndDeterministic() {
        let sections = [
            ShelfSectionItem(id: "section-1", title: "One", books: [book("book-1"), book("book-2")]),
            ShelfSectionItem(id: "section-2", title: "Two", books: [book("book-3")])
        ]
        let first = ShelfLayoutPlanner.discover(sections: sections, input: input(width: 600, height: 800))
        let second = ShelfLayoutPlanner.discover(sections: sections, input: input(width: 600, height: 800))

        XCTAssertEqual(first, second)
        let elementIDs = first.elements.map { $0.id }
        XCTAssertEqual(Set(elementIDs).count, first.elements.count)
        XCTAssertEqual(discoverBooks(first), sections.flatMap { $0.books }.map { $0.id })
    }

    func testDiscoverElementIDsRemainUniqueWhenSectionIDsMatchGeneratedIDs() {
        let adCollisionSections = (0..<8).map { index in
            ShelfSectionItem(
                id: index == 1 ? "discover-ad-after-section-1" : "section-\(index)",
                title: "Section \(index)",
                books: [book("book-\(index)")]
            )
        }
        let adPlan = ShelfLayoutPlanner.discover(
            sections: adCollisionSections,
            input: input(width: 1024, height: 696)
        )
        let fillerPlan = ShelfLayoutPlanner.discover(
            sections: [
                ShelfSectionItem(
                    id: "discover-filler-row-0",
                    title: "Section",
                    books: [book("book")]
                )
            ],
            input: input(width: 600, height: 800)
        )

        let adIDs = adPlan.elements.map { $0.id }
        let fillerIDs = fillerPlan.elements.map { $0.id }

        XCTAssertEqual(Set(adIDs).count, adIDs.count)
        XCTAssertEqual(Set(fillerIDs).count, fillerIDs.count)
        XCTAssertTrue(adIDs.contains("section:discover-ad-after-section-1"))
        XCTAssertTrue(adIDs.contains("ad:discover-ad-after-section-1"))
        XCTAssertTrue(fillerIDs.contains("section:discover-filler-row-0"))
        XCTAssertTrue(fillerIDs.contains("filler:discover-filler-row-0"))
    }
}
