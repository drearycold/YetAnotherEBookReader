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
        rotation: Int = 0
    ) -> PDFPageReadingPlan {
        let display = PDFPageDisplaySpace(box: spread, rotation: rotation)
        return PDFPageReadingPlan(regions: regions, display: display) { region in
            PDFPageViewportFitter.Input(
                contentBounds: region,
                pageBounds: CGRect(origin: .zero, size: display.size),
                readableRect: readable,
                autoScaler: .Width,
                hMarginPercent: 5,
                vMarginPercent: 5,
                customScale: 1,
                readingDirection: .LtR_TtB,
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
