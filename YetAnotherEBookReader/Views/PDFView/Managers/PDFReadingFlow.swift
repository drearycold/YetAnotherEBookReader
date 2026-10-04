//
//  PDFReadingFlow.swift
//  YetAnotherEBookReader
//
//  Reading a page in steps (#97): region by region (the halves of a two-page
//  spread, or columns with full-width blocks between them), each a screen at a
//  time when it is longer than the view. A page read whole is one region.
//

import CoreGraphics

/// How a page is read in steps: every screen of every region, in reading
/// order. Fits are in the page's display space (`display`), where the fitter
/// works; `pageFit(at:)` maps one to page space for `applyViewport`.
struct PDFPageReadingPlan: Equatable {
    struct Step: Equatable {
        var region: Int
        var screen: Int
        var fit: PDFPageViewportFit
    }

    var steps: [Step]
    var display: PDFPageDisplaySpace

    /// Fits each region (display space) with the input `fitInput` gives for it,
    /// one step per screen.
    init(
        regions: [CGRect],
        display: PDFPageDisplaySpace,
        fitInput: (CGRect) -> PDFPageViewportFitter.Input
    ) {
        self.display = display
        steps = regions.enumerated().flatMap { region, rect in
            PDFPageViewportFitter.screens(fitInput(rect)).enumerated().map { screen, fit in
                Step(region: region, screen: screen, fit: fit)
            }
        }
    }

    /// The fit of step `index` in page space.
    func pageFit(at index: Int) -> PDFPageViewportFit {
        var fit = steps[index].fit
        fit.pageAnchor = display.toPage(fit.pageAnchor)
        return fit
    }

    /// The first step of `region`, or the last step when there is no such region.
    func stepIndex(region: Int) -> Int {
        steps.firstIndex { $0.region >= region } ?? max(steps.count - 1, 0)
    }

    /// The step a view shows, given the page point at its top-left corner
    /// (`upperLeft`, page space, as `PageViewPosition.point`) and its scale: the
    /// nearest step at that scale, or at any scale when none matches (the view
    /// size changed). A NaN axis is left out; with both NaN it is the first step.
    /// With `region`, only that region's steps count (a rotation or an options
    /// change keeps the region on screen and the place within it).
    func stepIndex(nearestUpperLeft upperLeft: CGPoint, scale: CGFloat, viewBounds: CGRect, region: Int? = nil) -> Int {
        let first = region.map(stepIndex(region:)) ?? 0
        // NaN stays NaN through the turn, on whichever display axis it lands.
        let target = display.toDisplay(upperLeft)
        let inRegion = steps.indices.filter { region == nil || steps[$0].region == region }
        guard !(target.x.isNaN && target.y.isNaN), !inRegion.isEmpty else { return first }

        let atScale = inRegion.filter { abs(steps[$0].fit.scale - scale) <= scale * 0.01 }
        let candidates = atScale.isEmpty ? inRegion : atScale
        func distance(_ index: Int) -> CGFloat {
            let point = PDFPageViewportFitter.upperLeft(of: steps[index].fit, viewBounds: viewBounds)
            let dx = target.x.isNaN ? 0 : point.x - target.x
            let dy = target.y.isNaN ? 0 : point.y - target.y
            return dx * dx + dy * dy
        }
        return candidates.min { distance($0) < distance($1) } ?? first
    }
}

/// Where to land on a page read in steps when it comes on screen.
enum PDFReadingTarget: Equatable {
    /// Its first step: turning forward onto it.
    case first
    /// Its last step: turning back onto it.
    case last
    /// A region, kept across a rotation or an options change: its step nearest
    /// the saved position, else its first.
    case region(Int)
}

/// The target of the page turn or change under way. It is set before PDFKit
/// changes page and consumed when the page change is handled, like
/// `pendingJumpMaskPage`: a target for another page is stale and dropped.
final class PDFReadingFlowController {
    private var pending: (pageNumber: Int, target: PDFReadingTarget)?

    func setPendingTarget(_ target: PDFReadingTarget, pageNumber: Int) {
        pending = (pageNumber, target)
    }

    /// The pending target for `pageNumber`, once; any pending target is cleared.
    func consumeTarget(for pageNumber: Int) -> PDFReadingTarget? {
        defer { pending = nil }
        guard let pending, pending.pageNumber == pageNumber else { return nil }
        return pending.target
    }
}
