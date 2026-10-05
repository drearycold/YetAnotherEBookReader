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
    /// The regions, display space, in reading order.
    var regions: [CGRect]
    var display: PDFPageDisplaySpace

    /// Fits each region (display space) with the input `fitInput` gives for it,
    /// one step per screen.
    init(
        regions: [CGRect],
        display: PDFPageDisplaySpace,
        fitInput: (CGRect) -> PDFPageViewportFitter.Input
    ) {
        self.regions = regions
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

    /// What step `index` shows of the page in `viewRect` (view space), in
    /// display space.
    func shownRect(at index: Int, viewRect: CGRect) -> CGRect {
        let fit = steps[index].fit
        let size = CGSize(width: viewRect.width / fit.scale, height: viewRect.height / fit.scale)
        let minX = fit.pageAnchor.x + (viewRect.minX - fit.viewAnchor.x) / fit.scale
        let maxY = fit.pageAnchor.y - (viewRect.minY - fit.viewAnchor.y) / fit.scale
        return CGRect(x: minX, y: maxY - size.height, width: size.width, height: size.height)
    }

    /// The step a jump to `focus` (page space: a destination's point as a
    /// zero-size rect, a search hit's or a highlight's bounds) lands on: in the
    /// region holding the top of the focus as displayed, else the nearest one
    /// (the first in reading order on a tie), the last step whose readable part
    /// (`readableRect`, view space) shows it, where it is nearest the start of
    /// the screen. A NaN axis is left out (a destination's unspecified one).
    func stepIndex(showing focus: CGRect, readableRect: CGRect) -> Int {
        let a = display.toDisplay(CGPoint(x: focus.minX, y: focus.minY))
        let b = display.toDisplay(CGPoint(x: focus.maxX, y: focus.maxY))
        // NaN stays NaN through the turn and through max.
        let point = CGPoint(x: (a.x + b.x) / 2, y: max(a.y, b.y))
        guard !(point.x.isNaN && point.y.isNaN), !steps.isEmpty else { return 0 }

        func distance(_ rect: CGRect) -> CGFloat {
            let dx = point.x.isNaN ? 0 : max(rect.minX - point.x, 0, point.x - rect.maxX)
            let dy = point.y.isNaN ? 0 : max(rect.minY - point.y, 0, point.y - rect.maxY)
            return dx * dx + dy * dy
        }
        let region = regions.indices.min { distance(regions[$0]) < distance(regions[$1]) } ?? 0
        let inRegion = steps.indices.filter { steps[$0].region == region }
        func shownDistance(_ index: Int) -> CGFloat {
            distance(shownRect(at: index, viewRect: readableRect))
        }
        if let shown = inRegion.last(where: { shownDistance($0) == 0 }) {
            return shown
        }
        return inRegion.min { shownDistance($0) < shownDistance($1) } ?? stepIndex(region: region)
    }

    /// The step whose view (`viewBounds`) has `lowerLeft` at its lower-left
    /// corner (page space), or the nearest: a bookmark saves
    /// `PDFView.currentDestination`, that corner of what was on screen.
    func stepIndex(nearestLowerLeft lowerLeft: CGPoint, viewBounds: CGRect) -> Int {
        func distance(_ index: Int) -> CGFloat {
            let shown = display.toPage(shownRect(at: index, viewRect: viewBounds))
            let dx = lowerLeft.x.isNaN ? 0 : shown.minX - lowerLeft.x
            let dy = lowerLeft.y.isNaN ? 0 : shown.minY - lowerLeft.y
            return dx * dx + dy * dy
        }
        return steps.indices.min { distance($0) < distance($1) } ?? 0
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
    /// A jump's destination, page space (`stepIndex(showing:readableRect:)`):
    /// an outline or link destination's point as a zero-size rect, a search
    /// hit's or a highlight's bounds.
    case destination(CGRect)
    /// A bookmark's point, the lower-left corner of what was on screen
    /// (`stepIndex(nearestLowerLeft:viewBounds:)`).
    case lowerLeft(CGPoint)
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
