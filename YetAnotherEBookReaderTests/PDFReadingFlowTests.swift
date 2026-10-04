import XCTest
@testable import YetAnotherEBookReader

final class PDFReadingFlowTests: XCTestCase {
    /// A 1224 x 792 spread with a text block in each half (display space).
    private let spread = CGRect(x: 0, y: 0, width: 1224, height: 792)
    private let leftHalf = CGRect(x: 81, y: 96, width: 450, height: 600)
    private let rightHalf = CGRect(x: 693, y: 96, width: 450, height: 600)
    private let landscape = CGRect(x: 0, y: 0, width: 844, height: 390)

    private func plan(
        regions: [CGRect],
        readable: CGRect,
        rotation: Int = 0,
        autoScaler: PDFAutoScaler = .Width,
        readingDirection: PDFReadDirection = .LtR_TtB
    ) -> PDFPageReadingPlan {
        let display = PDFPageDisplaySpace(box: spread, rotation: rotation)
        return PDFPageReadingPlan(regions: regions, display: display) { region in
            PDFPageViewportFitter.Input(
                contentBounds: region,
                pageBounds: CGRect(origin: .zero, size: display.size),
                readableRect: readable,
                autoScaler: autoScaler,
                hMarginPercent: 5,
                vMarginPercent: 5,
                customScale: 1,
                readingDirection: readingDirection,
                marginOffsetPercent: 0
            )
        }
    }

    /// The page point a step puts at the view's top-left corner, as
    /// `getPagePoint` reads it back.
    private func upperLeft(_ plan: PDFPageReadingPlan, _ index: Int, _ viewBounds: CGRect) -> CGPoint {
        plan.display.toPage(PDFPageViewportFitter.upperLeft(of: plan.steps[index].fit, viewBounds: viewBounds))
    }

    func testPlanReadsRegionsInOrderAScreenAtATime() {
        let plan = plan(regions: [leftHalf, rightHalf], readable: landscape)
        let regions = plan.steps.map(\.region)

        XCTAssertGreaterThan(plan.steps.count, 2, "each half takes several screens in landscape")
        XCTAssertEqual(regions, regions.sorted(), "regions in order")
        XCTAssertEqual(Set(regions), [0, 1])
        for region in 0...1 {
            let screens = plan.steps.filter { $0.region == region }.map(\.screen)
            XCTAssertEqual(screens, Array(0..<screens.count))
        }
        XCTAssertEqual(plan.stepIndex(region: 0), 0)
        XCTAssertEqual(plan.steps[plan.stepIndex(region: 1)].region, 1)
        XCTAssertEqual(plan.steps[plan.stepIndex(region: 1)].screen, 0)
        XCTAssertEqual(plan.stepIndex(region: 9), plan.steps.count - 1, "past the last region: its last step")
    }

    /// Each step is found again from the point it puts at the view's corner,
    /// also on a turned page.
    func testEveryStepIsFoundFromItsUpperLeftPoint() {
        for rotation in [0, 90] {
            let plan = plan(regions: [leftHalf, rightHalf], readable: landscape, rotation: rotation)
            for index in plan.steps.indices {
                let found = plan.stepIndex(
                    nearestUpperLeft: upperLeft(plan, index, landscape),
                    scale: plan.steps[index].fit.scale,
                    viewBounds: landscape
                )
                XCTAssertEqual(found, index, "rotation \(rotation)")
            }
        }
    }

    /// An options change keeps one axis of the saved point: matched on it alone.
    /// Both missing: the first step.
    func testNaNAxesAreLeftOut() {
        let plan = plan(regions: [leftHalf, rightHalf], readable: landscape)
        let last = plan.steps.count - 1
        let point = upperLeft(plan, last, landscape)
        let scale = plan.steps[last].fit.scale

        XCTAssertEqual(plan.stepIndex(nearestUpperLeft: CGPoint(x: point.x, y: .nan), scale: scale, viewBounds: landscape), plan.stepIndex(region: 1))
        XCTAssertEqual(plan.steps[plan.stepIndex(nearestUpperLeft: CGPoint(x: .nan, y: point.y), scale: scale, viewBounds: landscape)].screen, plan.steps[last].screen)
        XCTAssertEqual(plan.stepIndex(nearestUpperLeft: CGPoint(x: CGFloat.nan, y: .nan), scale: scale, viewBounds: landscape), 0)
    }

    /// A view at one region's scale is matched among that region's steps, even
    /// when a step at another scale has a closer corner.
    func testStepsAtTheViewsScaleArePreferred() {
        let wide = CGRect(x: 81, y: 96, width: 1062, height: 100)
        let column = CGRect(x: 81, y: 220, width: 450, height: 476)
        let plan = plan(regions: [wide, column], readable: landscape)
        let columnStep = plan.stepIndex(region: 1)
        XCTAssertNotEqual(plan.steps[0].fit.scale, plan.steps[columnStep].fit.scale, accuracy: 0.01)

        let found = plan.stepIndex(
            nearestUpperLeft: upperLeft(plan, 0, landscape),
            scale: plan.steps[columnStep].fit.scale,
            viewBounds: landscape
        )
        XCTAssertEqual(plan.steps[found].region, 1)
    }

    /// Kept on a region (a rotation, an options change), the point is matched
    /// among that region's steps only: the same height in the other half, or
    /// its first step when the point is unknown.
    func testRegionKeepsThePlaceWithinIt() {
        let plan = plan(regions: [leftHalf, rightHalf], readable: landscape)
        let rightSteps = plan.steps.indices.filter { plan.steps[$0].region == 1 }
        let leftSteps = plan.steps.indices.filter { plan.steps[$0].region == 0 }
        XCTAssertGreaterThan(rightSteps.count, 1)

        for (left, right) in zip(leftSteps, rightSteps) {
            let point = upperLeft(plan, right, landscape)
            // At another view size: matched at any scale.
            XCTAssertEqual(plan.stepIndex(nearestUpperLeft: point, scale: 0, viewBounds: landscape, region: 1), right)
            XCTAssertEqual(plan.stepIndex(nearestUpperLeft: point, scale: 0, viewBounds: landscape, region: 0), left, "the same height in the other half")
        }
        XCTAssertEqual(plan.stepIndex(nearestUpperLeft: CGPoint(x: CGFloat.nan, y: .nan), scale: 0, viewBounds: landscape, region: 1), plan.stepIndex(region: 1))
    }

    // MARK: - Jumps

    private func point(_ point: CGPoint) -> CGRect {
        CGRect(origin: point, size: .zero)
    }

    /// The steps of `region` after `index` that also show `focus`'s point: none
    /// when `index` is the last step showing it.
    private func laterSteps(_ plan: PDFPageReadingPlan, after index: Int, showing point: CGPoint, readable: CGRect) -> [Int] {
        plan.steps.indices.filter {
            $0 > index && plan.steps[$0].region == plan.steps[index].region
                && plan.shownRect(at: $0, viewRect: readable).contains(point)
        }
    }

    /// A destination low in the right half lands on that half, on the last
    /// screen showing it (nearest its top); a search hit at the top of the
    /// left half on its first screen.
    func testDestinationLandsOnTheStepShowingIt() {
        let plan = plan(regions: [leftHalf, rightHalf], readable: landscape)
        let low = CGPoint(x: rightHalf.midX, y: rightHalf.minY + 100)
        let found = plan.stepIndex(showing: point(low), readableRect: landscape)
        XCTAssertEqual(plan.steps[found].region, 1)
        XCTAssertGreaterThan(plan.steps[found].screen, 0)
        XCTAssertTrue(plan.shownRect(at: found, viewRect: landscape).contains(low))
        XCTAssertEqual(laterSteps(plan, after: found, showing: low, readable: landscape), [])

        let hit = CGRect(x: leftHalf.minX + 10, y: leftHalf.maxY - 20, width: 60, height: 12)
        XCTAssertEqual(plan.stepIndex(showing: hit, readableRect: landscape), 0)
    }

    /// An unspecified x: matched by height, the first region in reading order
    /// holding it.
    func testUnspecifiedXIsMatchedByHeightInReadingOrder() {
        let plan = plan(regions: [leftHalf, rightHalf], readable: landscape)
        let low = CGPoint(x: CGFloat.nan, y: rightHalf.minY + 100)
        let found = plan.stepIndex(showing: point(low), readableRect: landscape)
        XCTAssertEqual(plan.steps[found].region, 0)
        let shown = plan.shownRect(at: found, viewRect: landscape)
        XCTAssertTrue(shown.minY <= low.y && low.y <= shown.maxY, "\(shown)")
    }

    /// A point between the halves goes to the nearer one.
    func testPointInAGapGoesToTheNearestRegion() {
        let plan = plan(regions: [leftHalf, rightHalf], readable: landscape)
        let gap = CGPoint(x: rightHalf.minX - 20, y: rightHalf.maxY - 10)
        XCTAssertEqual(plan.steps[plan.stepIndex(showing: point(gap), readableRect: landscape)].region, 1)
    }

    /// Vertical text is read from the right: a destination near its left end is
    /// on the last screen, near its right end on the first.
    func testVerticalTextDestinations() {
        let portrait = CGRect(x: 0, y: 0, width: 390, height: 844)
        let wide = CGRect(x: 81, y: 96, width: 1062, height: 600)
        let plan = plan(regions: [wide], readable: portrait, autoScaler: .Height, readingDirection: .TtB_RtL)
        XCTAssertGreaterThan(plan.steps.count, 2)
        XCTAssertEqual(plan.stepIndex(showing: point(CGPoint(x: wide.minX + 20, y: 400)), readableRect: portrait), plan.steps.count - 1)
        XCTAssertEqual(plan.stepIndex(showing: point(CGPoint(x: wide.maxX - 20, y: 400)), readableRect: portrait), 0)
    }

    /// A bookmark's point (the lower-left corner of what a step showed) finds
    /// that step again, also on a turned page.
    func testEveryStepIsFoundFromItsLowerLeftPoint() {
        for rotation in [0, 90] {
            let plan = plan(regions: [leftHalf, rightHalf], readable: landscape, rotation: rotation)
            for index in plan.steps.indices {
                let shown = plan.display.toPage(plan.shownRect(at: index, viewRect: landscape))
                let found = plan.stepIndex(nearestLowerLeft: CGPoint(x: shown.minX, y: shown.minY), viewBounds: landscape)
                XCTAssertEqual(found, index, "rotation \(rotation)")
            }
        }
    }

    func testPendingTargetIsConsumedOnceAndOnlyForItsPage() {
        let flow = PDFReadingFlowController()
        flow.setPendingTarget(.last, pageNumber: 4)
        XCTAssertNil(flow.consumeTarget(for: 5), "stale: for another page")
        XCTAssertNil(flow.consumeTarget(for: 4), "dropped with the stale check")

        flow.setPendingTarget(.region(1), pageNumber: 4)
        XCTAssertEqual(flow.consumeTarget(for: 4), .region(1))
        XCTAssertNil(flow.consumeTarget(for: 4))
    }
}
