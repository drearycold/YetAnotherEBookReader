//
//  PDFPageRasterTests.swift
//  YetAnotherEBookReaderTests
//
//  `PageRaster` sums a line's darkness in exact integers, and `PDFInkMap`
//  answers from a table of ink counts. These pin every answer to reading each
//  pixel in floating point, as detection used to: the same ink, the same
//  darkness to within rounding, along every line from every edge, in parts
//  and turned.
//

import CoreGraphics
import ImageIO
import XCTest
@testable import YetAnotherEBookReader

final class PDFPageRasterTests: XCTestCase {
    /// Detection's ink rule for one pixel, in floating point: Rec. 601
    /// luminance below 200 is ink, of darkness (255 - luminance) / 255.
    private static func referenceDarkness(red: UInt8, green: UInt8, blue: UInt8) -> Double {
        let luminance = 0.299 * Double(red) + 0.587 * Double(green) + 0.114 * Double(blue)
        return luminance < 200 ? (255 - luminance) / 255 : 0
    }

    // MARK: - The ink rule

    /// Near the threshold, where rounding decides, a colour is ink exactly when
    /// the floating-point rule says so, and as dark; a sweep of all colours too.
    func testInkRuleMatchesFloatingPoint() {
        var mismatches: [String] = []
        var checked = 0
        func check(_ red: Int, _ green: Int, _ blue: Int) {
            checked += 1
            let reference = Self.referenceDarkness(red: UInt8(red), green: UInt8(green), blue: UInt8(blue))
            let darkness = Double(PageRaster.darkness(red: UInt8(red), green: UInt8(green), blue: UInt8(blue))) / PageRaster.darknessScale
            if (darkness > 0) != (reference > 0) || abs(darkness - reference) > 1e-12 {
                mismatches.append("(\(red), \(green), \(blue)) \(darkness) vs \(reference)")
            }
        }
        for red in 0...255 {
            for green in 0...255 {
                // The blues that bring 299 r + 587 g + 114 b nearest 200000.
                let blue = (200_000 - 299 * red - 587 * green) / 114
                for blue in (blue - 2)...(blue + 2) where (0...255).contains(blue) {
                    check(red, green, blue)
                }
            }
        }
        let onThreshold = checked
        for red in stride(from: 0, through: 255, by: 5) {
            for green in stride(from: 0, through: 255, by: 5) {
                for blue in stride(from: 0, through: 255, by: 5) {
                    check(red, green, blue)
                }
            }
        }
        XCTAssertGreaterThan(onThreshold, 10_000)
        XCTAssertEqual(mismatches, [], "\(mismatches.count) of \(checked) colours")
    }

    // MARK: - Lines

    /// Density and ink of every line from every edge, over the whole line and
    /// random runs of it, on the whole raster and on a part of it.
    func testLinesMatchReadingEveryPixel() throws {
        var mismatches: [String] = []
        for seed in UInt64(1)...4 {
            let sample = try Sample(width: 97 + Int(seed), height: 61 + 3 * Int(seed), seed: seed, padding: seed.isMultiple(of: 2) ? 64 : 0)
            var generator = SeededGenerator(seed: seed)
            let read: Void? = PageRaster.reading(sample.image) { whole in
                XCTAssertEqual(whole.width, sample.width)
                XCTAssertEqual(whole.height, sample.height)
                let part = whole.cropped(columns: 7..<(whole.width - 11), lines: 5..<(whole.height - 3))
                for (name, raster) in [("whole", whole), ("part", part)] {
                    mismatches += lineMismatches(raster, of: sample, using: &generator).map { "seed \(seed) \(name) \($0)" }
                }
            }
            XCTAssertNotNil(read)
        }
        XCTAssertEqual(mismatches.count, 0, "\(mismatches.prefix(5))")
    }

    private func lineMismatches(_ raster: PageRaster, of sample: Sample, using generator: inout SeededGenerator) -> [String] {
        var mismatches: [String] = []
        for edge in [CGImagePropertyOrientation.up, .down, .left, .right] {
            let pixelCount = raster.pixelCount(edge)
            for line in 0..<raster.lineCount(edge) {
                var runs = [0..<pixelCount, 0..<0]
                for _ in 0..<3 {
                    let start = Int.random(in: 0...pixelCount, using: &generator)
                    runs.append(start..<Int.random(in: start...pixelCount, using: &generator))
                }
                for pixels in runs {
                    var density = 0.0
                    var inked = 0
                    for pixel in pixels {
                        let (x, y) = Self.pixel(of: raster, line: line, pixel: pixel, edge)
                        let darkness = sample.darkness(x: x, y: y)
                        density += darkness
                        inked += darkness > 0 ? 1 : 0
                    }
                    let found = raster.density(line: line, pixels: pixels, edge)
                    let foundInk = raster.inkedPixels(line: line, pixels: pixels, edge)
                    if abs(found - density) > 1e-9 || foundInk != inked {
                        mismatches.append("\(edge) line \(line) \(pixels): \(found)/\(foundInk) vs \(density)/\(inked)")
                    }
                }
            }
        }
        return mismatches
    }

    /// The thumbnail pixel of `pixel` along `line` counted in from `edge`, as
    /// detection has always mapped them: `.up` counts rows from the top,
    /// `.down` from the bottom, `.right` columns from the left, `.left` from
    /// the right; `pixel` runs left to right, or top to bottom.
    private static func pixel(of raster: PageRaster, line: Int, pixel: Int, _ edge: CGImagePropertyOrientation) -> (x: Int, y: Int) {
        switch edge {
        case .up: return (raster.originX + pixel, raster.originY + line)
        case .down: return (raster.originX + pixel, raster.originY + raster.height - line - 1)
        case .right: return (raster.originX + line, raster.originY + pixel)
        default: return (raster.originX + raster.width - line - 1, raster.originY + pixel)
        }
    }

    // MARK: - Ink maps

    /// A part's ink map, and the map turned for vertical text, answer every
    /// pixel, column and row as the pixels themselves do.
    func testInkMapsMatchReadingEveryPixel() throws {
        var mismatches: [String] = []
        for seed in UInt64(5)...7 {
            let sample = try Sample(width: 83 + Int(seed), height: 71, seed: seed, padding: 32)
            // A part 9 px in from the left and 3 px down. The map keeps its own
            // counts: it is read after the pixels are gone.
            let (originX, originY) = (9, 3)
            let map = try XCTUnwrap(PageRaster.reading(sample.image) { raster in
                PDFInkMap(raster.cropped(columns: originX..<(raster.width - 4), lines: originY..<(raster.height - 8)))
            })
            let turned = map.turnedForVerticalText()
            XCTAssertEqual(turned.width, map.height)
            XCTAssertEqual(turned.height, map.width)

            func inked(_ x: Int, _ y: Int) -> Bool {
                sample.darkness(x: originX + x, y: originY + y) > 0
            }
            // The turned map's (x, y) is (width - 1 - y, x) of the map.
            func turnedInked(_ x: Int, _ y: Int) -> Bool {
                inked(map.width - 1 - y, x)
            }
            var generator = SeededGenerator(seed: seed)
            func runs(_ count: Int) -> [Range<Int>] {
                var runs = [0..<count]
                for _ in 0..<4 {
                    let start = Int.random(in: 0...count, using: &generator)
                    runs.append(start..<Int.random(in: start...count, using: &generator))
                }
                return runs
            }
            for (name, map, isInked) in [("map", map, inked), ("turned", turned, turnedInked)] {
                for y in 0..<map.height {
                    for x in 0..<map.width where map.isInked(x: x, y: y) != isInked(x, y) {
                        mismatches.append("seed \(seed) \(name) pixel (\(x), \(y))")
                    }
                }
                for x in 0..<map.width {
                    for rows in runs(map.height) {
                        let expected = rows.filter { isInked(x, $0) }.count
                        if map.inkedRows(column: x, rows: rows) != expected {
                            mismatches.append("seed \(seed) \(name) column \(x) rows \(rows)")
                        }
                    }
                }
                for y in 0..<map.height {
                    for columns in runs(map.width) {
                        let expected = columns.filter { isInked($0, y) }.count
                        if map.inkedColumns(row: y, columns: columns) != expected {
                            mismatches.append("seed \(seed) \(name) row \(y) columns \(columns)")
                        }
                    }
                }
            }
        }
        XCTAssertEqual(mismatches.count, 0, "\(mismatches.prefix(5))")
    }

    // MARK: - Samples

    /// A seeded raster like a scanned page, as PDFKit's thumbnails lay them
    /// out (B G R A, alpha first, little-endian): text-like blocks of grey and
    /// coloured ink, specks, and colours on the ink threshold, on white.
    private struct Sample {
        let width: Int
        let height: Int
        let bytesPerRow: Int
        let bytes: [UInt8]
        let image: CGImage

        init(width: Int, height: Int, seed: UInt64, padding: Int) throws {
            self.width = width
            self.height = height
            bytesPerRow = width * 4 + padding
            bytes = Self.pixels(width: width, height: height, bytesPerRow: bytesPerRow, seed: seed)
            image = try XCTUnwrap(CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                provider: try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData)),
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            ))
        }

        private static func pixels(width: Int, height: Int, bytesPerRow: Int, seed: UInt64) -> [UInt8] {
            var bytes = [UInt8](repeating: 255, count: bytesPerRow * height)
            var generator = SeededGenerator(seed: seed)
            func paint(_ x: Int, _ y: Int, _ colour: (UInt8, UInt8, UInt8)) {
                let index = y * bytesPerRow + x * 4
                (bytes[index], bytes[index + 1], bytes[index + 2], bytes[index + 3]) = (colour.2, colour.1, colour.0, 255)
            }
            // Colours on and around the threshold, the ones rounding decides.
            let threshold: [(UInt8, UInt8, UInt8)] = [(114, 244, 199), (136, 246, 131), (148, 216, 254), (200, 200, 200), (199, 199, 199), (201, 201, 201)]
            func randomColour() -> (UInt8, UInt8, UInt8) {
                switch Int.random(in: 0..<4, using: &generator) {
                case 0: let grey = UInt8.random(in: 0...255, using: &generator); return (grey, grey, grey)
                case 1: return threshold[Int.random(in: 0..<threshold.count, using: &generator)]
                default: return (UInt8.random(in: 0...255, using: &generator), UInt8.random(in: 0...255, using: &generator), UInt8.random(in: 0...255, using: &generator))
                }
            }
            for _ in 0..<12 {
                let x = Int.random(in: 0..<width, using: &generator)
                let y = Int.random(in: 0..<height, using: &generator)
                let blockWidth = Int.random(in: 1...(width - x), using: &generator)
                let blockHeight = Int.random(in: 1...min(12, height - y), using: &generator)
                let colour = randomColour()
                for row in y..<(y + blockHeight) {
                    for column in x..<(x + blockWidth) where Int.random(in: 0..<10, using: &generator) < 6 {
                        paint(column, row, colour)
                    }
                }
            }
            for _ in 0..<200 {
                paint(Int.random(in: 0..<width, using: &generator), Int.random(in: 0..<height, using: &generator), randomColour())
            }
            return bytes
        }

        func darkness(x: Int, y: Int) -> Double {
            let index = y * bytesPerRow + x * 4
            return PDFPageRasterTests.referenceDarkness(red: bytes[index + 2], green: bytes[index + 1], blue: bytes[index])
        }
    }

    /// SplitMix64, so every run draws the same samples.
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64

        init(seed: UInt64) {
            state = seed
        }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }
}
