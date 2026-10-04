//
//  PDFMarginDetectionBenchmarkTests.swift
//  YetAnotherEBookReaderTests
//
//  How long margin detection (`PDFMarginCropController`) takes on a fixed set
//  of pages, and how much of it is rendering the page. Opt-in:
//
//  TEST_RUNNER_YABR_BENCHMARK=1 xcodebuild test ... \
//      -only-testing:YetAnotherEBookReaderTests/PDFMarginDetectionBenchmarkTests
//
//  Build with SWIFT_OPTIMIZATION_LEVEL=-O (in its own derived data) for the
//  times of an optimized build; the tests otherwise run unoptimized.
//

import PDFKit
import UIKit
import XCTest
@testable import YetAnotherEBookReader

final class PDFMarginDetectionBenchmarkTests: XCTestCase {
    private static let letter = CGSize(width: 612, height: 792)
    private static let runs = 10

    private struct Sample {
        let name: String
        let data: Data
        var options = PDFPreferenceValue()
        /// The regions detection must find, so the work measured stays the same.
        var regions = 0
    }

    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["YABR_BENCHMARK"] != nil,
            "A benchmark: run with TEST_RUNNER_YABR_BENCHMARK=1"
        )
    }

    /// Per page, the median of `runs`, in ms:
    /// - total: a detection (`readingLayout`) on a fresh controller;
    /// - render: the page rendered for detection (`thumbnail(of:)`);
    /// - analyze: the edges and regions found on that render (`analyze`).
    func testDetectionTimings() throws {
        var lines = ["PDFBENCH page      raster     total    render   analyze"]
        for sample in try corpus() {
            lines.append(try timings(of: sample))
        }
        let report = lines.joined(separator: "\n")
        print(report)
        add(XCTAttachment(string: report))
    }

    private func timings(of sample: Sample) throws -> String {
        let key = PageVisibleContentKey(pageNumber: 1, options: sample.options)
        var totals: [Double] = []
        var renders: [Double] = []
        var analyses: [Double] = []
        var rasterSize = CGSize.zero
        for _ in 0..<Self.runs {
            // A fresh document each time: nothing PDFKit or CoreGraphics decoded
            // for an earlier run is reused.
            var (document, page) = try open(sample)
            var layout: PDFPageReadingLayout?
            totals.append(milliseconds { layout = PDFMarginCropController().readingLayout(for: page, key: key) })
            XCTAssertEqual(layout?.regions.count, sample.regions, "\(sample.name) \(String(describing: layout))")

            (document, page) = try open(sample)
            let detector = PDFMarginCropController()
            var thumbnail: PDFMarginCropController.Thumbnail?
            renders.append(milliseconds { thumbnail = detector.thumbnail(of: page) })
            let rendered = try XCTUnwrap(thumbnail)
            rasterSize = CGSize(width: rendered.image.width, height: rendered.image.height)
            analyses.append(milliseconds { _ = detector.analyze(rendered, key: key) })
            withExtendedLifetime(document) {}
        }
        let raster = "\(Int(rasterSize.width))x\(Int(rasterSize.height))"
        return "PDFBENCH "
            + sample.name.padding(toLength: 9, withPad: " ", startingAt: 0)
            + raster.padding(toLength: 9, withPad: " ", startingAt: 0)
            + String(format: " %9.2f %9.2f %9.2f", median(totals), median(renders), median(analyses))
    }

    private func open(_ sample: Sample) throws -> (PDFDocument, PDFPage) {
        let document = try XCTUnwrap(PDFDocument(data: sample.data))
        let page = try XCTUnwrap(document.page(at: 0))
        _ = page.bounds(for: .mediaBox)
        return (document, page)
    }

    private func milliseconds(_ body: () throws -> Void) rethrows -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        try body()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    private func median(_ values: [Double]) -> Double {
        values.sorted()[values.count / 2]
    }

    // MARK: - Pages

    private func corpus() throws -> [Sample] {
        var spread = PDFPreferenceValue()
        spread.spreadMode = .Auto
        var columns = PDFPreferenceValue()
        columns.columnsMode = .Auto
        var vertical = PDFPreferenceValue()
        vertical.readingDirection = .TtB_RtL
        vertical.columnsMode = .Auto
        let scan = try XCTUnwrap(UIImage(data: Self.scanJPEG()))

        return [
            Sample(name: "text", data: pdf(Self.letter) { drawLines(y: 96, count: 40, x: 81...531) }),
            // A chapter's last lines: the bottom pass crosses the blank below.
            Sample(name: "short", data: pdf(Self.letter) { drawLines(y: 96, count: 8, x: 81...531) }),
            // Every pass crosses the whole page.
            Sample(name: "blank", data: pdf(Self.letter) {}),
            Sample(
                name: "spread",
                data: pdf(CGSize(width: 1224, height: 792)) {
                    drawLines(y: 96, count: 40, x: 81...531)
                    drawLines(y: 96, count: 40, x: 693...1143)
                },
                options: spread,
                regions: 2
            ),
            Sample(
                name: "paper",
                data: pdf(Self.letter) {
                    drawLines(y: 96, count: 5, x: 60...552)
                    drawLines(y: 190, count: 34, x: 60...290)
                    drawLines(y: 190, count: 34, x: 322...552)
                },
                options: columns,
                regions: 3
            ),
            Sample(
                name: "vertical",
                data: pdf(Self.letter) {
                    drawVerticalLines(right: 552, count: 33, y: 96...380)
                    drawVerticalLines(right: 552, count: 33, y: 420...700)
                },
                options: vertical,
                regions: 2
            ),
            Sample(name: "scan", data: pdf(Self.letter) { scan.draw(in: CGRect(origin: .zero, size: Self.letter)) }),
        ]
    }

    private func pdf(_ size: CGSize, draw: () -> Void) -> Data {
        UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size)).pdfData { context in
            context.beginPage()
            draw()
        }
    }

    private static let words = "Margins of a page frame the text block where every line begins on some word and runs to the measure".split(separator: " ")

    /// 11 pt body lines on a 15 pt pitch across `x`, each starting on another word.
    private func drawLines(y: CGFloat, count: Int, x: ClosedRange<CGFloat>, fontSize: CGFloat = 11, pitch: CGFloat = 15) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "TimesNewRomanPSMT", size: fontSize) ?? .systemFont(ofSize: fontSize),
            .foregroundColor: UIColor.black,
        ]
        let words = Self.words
        for index in 0..<count {
            let rotated = words[(index % words.count)...] + words[..<(index % words.count)]
            let text = String(repeating: rotated.joined(separator: " ") + " ", count: 3) as NSString
            let line = CGRect(x: x.lowerBound, y: y + CGFloat(index) * pitch, width: x.upperBound - x.lowerBound, height: pitch)
            UIGraphicsGetCurrentContext()?.saveGState()
            UIRectClip(line)
            text.draw(at: line.origin, withAttributes: attributes)
            UIGraphicsGetCurrentContext()?.restoreGState()
        }
    }

    /// Vertical text: `count` lines from `right` leftward, 15 pt apart, each a
    /// run of 9 pt characters down `y`.
    private func drawVerticalLines(right: CGFloat, count: Int, y: ClosedRange<CGFloat>) {
        UIColor.black.setFill()
        for line in 0..<count {
            let x = right - CGFloat(line + 1) * 15 + 3
            var top = y.lowerBound
            while top + 9 <= y.upperBound {
                UIRectFill(CGRect(x: x, y: top, width: 9, height: 9))
                top += 11
            }
        }
    }

    /// A text page scanned at 300 dpi, as a JPEG: 2550×3300 px of body text
    /// with specks, a scanner border along the top and a binding shadow down
    /// the left.
    private static func scanJPEG() -> Data {
        let size = CGSize(width: 2550, height: 3300)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            for x in 0..<120 {
                UIColor(white: 0.35 + CGFloat(x) * 0.005, alpha: 1).setFill()
                context.fill(CGRect(x: CGFloat(x), y: 0, width: 1, height: size.height))
            }
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width, height: 40))

            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont(name: "TimesNewRomanPSMT", size: 46) ?? .systemFont(ofSize: 46),
                .foregroundColor: UIColor(white: 0.1, alpha: 1),
            ]
            for index in 0..<40 {
                let rotated = words[(index % words.count)...] + words[..<(index % words.count)]
                let text = String(repeating: rotated.joined(separator: " ") + " ", count: 3) as NSString
                let line = CGRect(x: 338, y: 400 + CGFloat(index) * 62, width: 1875, height: 62)
                context.cgContext.saveGState()
                context.cgContext.clip(to: line)
                text.draw(at: line.origin, withAttributes: attributes)
                context.cgContext.restoreGState()
            }

            // Specks, from a fixed seed.
            var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
            for _ in 0..<4000 {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                UIColor(white: CGFloat((seed >> 50) % 128) / 255, alpha: 1).setFill()
                context.fill(CGRect(x: CGFloat((seed >> 33) % 2550), y: CGFloat((seed >> 13) % 3300), width: 3, height: 3))
            }
        }
        return image.jpegData(compressionQuality: 0.85) ?? Data()
    }
}
