//
//  ShelfAdLayoutPolicyTests.swift
//  YetAnotherEBookReaderTests
//
//  Created by Codex on 2026-07-10.
//

import XCTest
@testable import YetAnotherEBookReader

final class ShelfAdLayoutPolicyTests: XCTestCase {
    private func context(
        viewportHeight: CGFloat = 800,
        containerWidth: CGFloat = 820,
        columnCount: Int = 5,
        isRegularWidth: Bool = true,
        isEditing: Bool = false,
        isLoading: Bool = false,
        isEmpty: Bool = false,
        nativeAvailable: Bool = true,
        bannerAvailable: Bool = true
    ) -> ShelfAdLayoutContext {
        ShelfAdLayoutContext(
            viewportHeight: viewportHeight,
            containerWidth: containerWidth,
            columnCount: columnCount,
            isRegularWidth: isRegularWidth,
            isEditing: isEditing,
            isLoading: isLoading,
            isEmpty: isEmpty,
            capabilities: ShelfAdLayoutCapabilities(
                nativeAvailable: nativeAvailable,
                bannerAvailable: bannerAvailable
            )
        )
    }

    func testSingleScreenEmptyAndEditingReturnNoAds() {
        XCTAssertEqual(ShelfAdLayoutPolicy.recentInsertions(bookCount: 10, context: context(viewportHeight: 400, columnCount: 5)), [])
        XCTAssertEqual(ShelfAdLayoutPolicy.recentInsertions(bookCount: 0, context: context()), [])
        XCTAssertEqual(ShelfAdLayoutPolicy.recentInsertions(bookCount: 40, context: context(isEditing: true)), [])
        XCTAssertEqual(ShelfAdLayoutPolicy.discoverInsertions(sectionCount: 0, context: context()), [])
        XCTAssertEqual(ShelfAdLayoutPolicy.discoverInsertions(sectionCount: 8, context: context(isLoading: true)), [])
    }

    func testRecentNativeEndcapStartsMidFirstViewportAndRepeatsByViewport() {
        let insertions = ShelfAdLayoutPolicy.recentInsertions(
            bookCount: 60,
            context: context(viewportHeight: 800, containerWidth: 1024, columnCount: 6)
        )

        XCTAssertEqual(
            insertions.map(\.kind),
            [
                .nativeEndcap(recentRow: 2, columnSpan: 3),
                .nativeEndcap(recentRow: 6, columnSpan: 3)
            ]
        )
        XCTAssertEqual(insertions.map(\.slotID), ["recent-native-endcap-row-2", "recent-native-endcap-row-6"])
    }

    func testRecentNativeEndcapSkipsIncompleteTailRow() {
        let insertions = ShelfAdLayoutPolicy.recentInsertions(
            bookCount: 11,
            context: context(viewportHeight: 800, containerWidth: 820, columnCount: 5)
        )

        XCTAssertEqual(insertions, [])
    }

    func testRecentFallsBackToBannerForCompactOrNativeMissing() {
        let compactInsertions = ShelfAdLayoutPolicy.recentInsertions(
            bookCount: 30,
            context: context(viewportHeight: 600, containerWidth: 430, columnCount: 2, isRegularWidth: false)
        )

        XCTAssertEqual(compactInsertions.first?.kind, .adaptiveBanner(afterContentRow: 2))

        let missingNativeInsertions = ShelfAdLayoutPolicy.recentInsertions(
            bookCount: 40,
            context: context(viewportHeight: 600, containerWidth: 1024, columnCount: 6, nativeAvailable: false)
        )

        XCTAssertEqual(missingNativeInsertions.first?.kind, .adaptiveBanner(afterContentRow: 2))
    }

    func testDiscoverNativeAdsAppearOnlyBetweenSections() {
        let insertions = ShelfAdLayoutPolicy.discoverInsertions(
            sectionCount: 8,
            context: context(viewportHeight: 696, containerWidth: 1024, columnCount: 6)
        )

        XCTAssertEqual(
            insertions.map(\.kind),
            [
                .nativeStrip(afterSection: 1),
                .nativeStrip(afterSection: 4)
            ]
        )
        XCTAssertEqual(insertions.map(\.slotID), ["discover-ad-after-section-1", "discover-ad-after-section-4"])
    }

    func testDiscoverFallsBackToBannerWhenNativeUnavailable() {
        let insertions = ShelfAdLayoutPolicy.discoverInsertions(
            sectionCount: 8,
            context: context(viewportHeight: 696, containerWidth: 1024, columnCount: 6, nativeAvailable: false)
        )

        XCTAssertEqual(insertions.first?.kind, .adaptiveBanner(afterContentRow: 1))
        XCTAssertEqual(insertions.first?.slotID, "discover-banner-after-section-1")
    }

    func testLongShelfSlotIDsAreUniqueAndStable() {
        let first = ShelfAdLayoutPolicy.recentInsertions(
            bookCount: 120,
            context: context(viewportHeight: 800, containerWidth: 1024, columnCount: 6)
        )
        let second = ShelfAdLayoutPolicy.recentInsertions(
            bookCount: 120,
            context: context(viewportHeight: 800, containerWidth: 1024, columnCount: 6)
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(Set(first.map(\.slotID)).count, first.count)
    }

    func testNativeAdStoresAreIsolated() {
        let firstStore = ShelfNativeAdStore()
        let secondStore = ShelfNativeAdStore()

        firstStore.recordLoadedForTesting(for: "slot")

        XCTAssertEqual(firstStore.status(for: "slot"), .loaded)
        XCTAssertEqual(secondStore.status(for: "slot"), .missing)
    }

    func testLoadedAdExpiresAfterLifetime() {
        var now = Date(timeIntervalSince1970: 100)
        let store = ShelfNativeAdStore(now: { now })

        store.recordLoadedForTesting(for: "slot")
        XCTAssertEqual(store.status(for: "slot"), .loaded)

        now = now.addingTimeInterval(ShelfNativeAdStore.loadedAdLifetime + 1)

        XCTAssertEqual(store.status(for: "slot"), .missing)
    }

    func testFailedAdCanRetryAfterCooldown() {
        var now = Date(timeIntervalSince1970: 100)
        let store = ShelfNativeAdStore(now: { now })

        store.recordFailure(for: "slot")
        XCTAssertEqual(store.status(for: "slot"), .failed)

        now = now.addingTimeInterval(ShelfNativeAdStore.failedAdCooldown + 1)

        XCTAssertEqual(store.status(for: "slot"), .missing)
    }

    func testNativeAdStoreEvictsLeastRecentlyUsedEntry() {
        let store = ShelfNativeAdStore()

        for index in 0..<ShelfNativeAdStore.maximumEntryCount {
            store.recordLoadedForTesting(for: "slot-\(index)")
        }

        XCTAssertEqual(store.status(for: "slot-0"), .loaded)
        store.recordLoadedForTesting(for: "slot-new")

        XCTAssertEqual(store.status(for: "slot-0"), .loaded)
        XCTAssertEqual(store.status(for: "slot-1"), .missing)
        XCTAssertEqual(store.status(for: "slot-new"), .loaded)
    }
}
