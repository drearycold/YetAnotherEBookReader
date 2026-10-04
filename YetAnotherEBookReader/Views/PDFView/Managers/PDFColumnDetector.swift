//
//  PDFColumnDetector.swift
//  YetAnotherEBookReader
//
//  Finds the text columns of a page (#19) and the order they are read in (#97):
//  full-width blocks and bands of columns, top to bottom, the columns of a band
//  left to right. Vertical text is read in tiers (段), found the same way on
//  the page turned a quarter.
//

import CoreGraphics

/// Which pixels of a part of the page thumbnail hold ink, with each column's
/// inked rows and each row's inked columns counted cumulatively, so the ink of
/// a column over any rows, or of a row over any columns, is O(1).
struct PDFInkMap {
    let width: Int
    let height: Int
    private let ink: [Bool]
    /// `columnInk[row * width + x]`: inked pixels of column `x` above `row`.
    private let columnInk: [Int32]
    /// `rowInk[y * (width + 1) + column]`: inked pixels of row `y` left of `column`.
    private let rowInk: [Int32]

    init(width: Int, height: Int, isInked: (_ x: Int, _ y: Int) -> Bool) {
        self.width = width
        self.height = height
        var ink = [Bool](repeating: false, count: width * height)
        var columnInk = [Int32](repeating: 0, count: width * (height + 1))
        var rowInk = [Int32](repeating: 0, count: (width + 1) * height)
        for y in 0..<height {
            for x in 0..<width {
                let inked = isInked(x, y)
                ink[y * width + x] = inked
                columnInk[(y + 1) * width + x] = columnInk[y * width + x] + (inked ? 1 : 0)
                rowInk[y * (width + 1) + x + 1] = rowInk[y * (width + 1) + x] + (inked ? 1 : 0)
            }
        }
        self.ink = ink
        self.columnInk = columnInk
        self.rowInk = rowInk
    }

    func isInked(x: Int, y: Int) -> Bool {
        ink[y * width + x]
    }

    /// Inked pixels of column `x` in `rows`.
    func inkedRows(column x: Int, rows: Range<Int>) -> Int {
        Int(columnInk[rows.upperBound * width + x] - columnInk[rows.lowerBound * width + x])
    }

    /// Inked pixels of row `y` in `columns`.
    func inkedColumns(row y: Int, columns: Range<Int>) -> Int {
        Int(rowInk[y * (width + 1) + columns.upperBound] - rowInk[y * (width + 1) + columns.lowerBound])
    }

    /// This map turned a quarter turn anticlockwise: vertical text, read in
    /// lines top to bottom from right to left, becomes rows read left to right
    /// from the top. (x, y) of the turned map is (width - 1 - y, x) of this one.
    func turnedForVerticalText() -> PDFInkMap {
        PDFInkMap(width: height, height: width) { x, y in
            isInked(x: width - 1 - y, y: x)
        }
    }

    /// The bounding box of the ink in `columns` × `rows`, or nil when blank.
    func inkBounds(columns: Range<Int>, rows: Range<Int>) -> CGRect? {
        let inkedColumns = columns.filter { inkedRows(column: $0, rows: rows) > 0 }
        guard let minX = inkedColumns.first, let maxX = inkedColumns.last else { return nil }
        func rowHasInk(_ y: Int) -> Bool {
            columns.contains { isInked(x: $0, y: y) }
        }
        guard let minY = rows.first(where: rowHasInk),
              let maxY = rows.reversed().first(where: rowHasInk)
        else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}

/// Text columns in an ink map of a page's content (its detected content box).
enum PDFColumnDetector {
    struct Region: Equatable {
        /// Ink map pixels, top-down.
        var rect: CGRect
        var kind: PDFReadingRegion.Kind
    }

    /// The page's reading regions in `readingDirection`. Vertical text is read
    /// in tiers (段): on the page turned a quarter (`turnedForVerticalText`)
    /// its tiers are columns and a block across them (a title the height of the
    /// page) is full-width. So it is read from the right, band by band, each
    /// band's tiers from the top.
    static func regions(in map: PDFInkMap, readingDirection: PDFReadDirection) -> [Region] {
        switch readingDirection {
        case .LtR_TtB:
            return regions(in: map)
        case .TtB_RtL:
            let width = CGFloat(map.width)
            return regions(in: map.turnedForVerticalText()).map { region in
                let turned = region.rect
                return Region(
                    rect: CGRect(x: width - turned.maxY, y: turned.minX, width: turned.height, height: turned.width),
                    kind: region.kind
                )
            }
        }
    }

    /// The page's reading regions when it is set in columns, in reading order:
    /// each full-width block, and each band of columns column by column. Empty
    /// when it is not: a single column, columns that do not read like text (a
    /// table, a figure grid), or columns over less than 40% of the content.
    static func regions(in map: PDFInkMap) -> [Region] {
        let width = map.width
        let height = map.height
        guard width >= 40, height >= 40 else { return [] }

        // About four lines of text: tall enough that word spaces do not line up
        // into a gutter, short enough to find where columns start and end.
        let windowHeight = max(24, height * 5 / 100)
        var bands: [Band] = []
        var top = 0
        while top < height {
            let rows = top..<min(height, top + windowHeight)
            bands.append(Band(rows: rows, kind: classify(rows, in: map)))
            top = rows.upperBound
        }
        bands = merged(bands)
        bands = refined(bands, in: map)

        // Split bands too short to read as columns are full-width blocks; then
        // a full-width sliver between two matching column bands (a rule, an
        // equation across the gutter) joins them.
        let minimumSplitHeight = max(windowHeight * 2, height * 15 / 100)
        bands = bands.map { band in
            guard case .split = band.kind, band.rows.count < minimumSplitHeight else { return band }
            return Band(rows: band.rows, kind: .spanning)
        }
        bands = mergedSlivers(bands, maximumSliver: max(windowHeight, height * 3 / 100))
        bands = merged(bands)

        // A table's or a figure grid's columns are not text: their band is read
        // whole, like a full-width block.
        bands = bands.map { band in
            guard case .split(let gutters) = band.kind,
                  !cells(between: gutters, width: width).allSatisfy({ readsLikeText(map, columns: $0, rows: band.rows) })
            else { return band }
            return Band(rows: band.rows, kind: .spanning)
        }
        bands = merged(bands)

        let splitHeight = bands.reduce(0) { total, band in
            if case .split = band.kind { return total + band.rows.count }
            return total
        }
        guard splitHeight * 10 >= height * 4 else { return [] }

        return bands.flatMap { band -> [Region] in
            switch band.kind {
            case .blank:
                return []
            case .spanning:
                return map.inkBounds(columns: 0..<width, rows: band.rows)
                    .map { [Region(rect: $0, kind: .spanning)] } ?? []
            case .split(let gutters):
                return cells(between: gutters, width: width).compactMap { columns in
                    map.inkBounds(columns: columns, rows: band.rows).map { Region(rect: $0, kind: .column) }
                }
            }
        }
    }

    // MARK: - Text

    /// Whether `columns` × `rows` hold running text: at least four lines of
    /// text height that fill the column, covering 30% or more of its inked
    /// height, so a column that also holds a figure still counts.
    /// - A line fills the column when it is inked across half its width or
    ///   more without a gap wider than an eighth of it: words are a few pixels
    ///   apart, a table's cells (a label and a number) far apart.
    /// - Text height is at most 4% of the content's: a picture is one tall blob.
    private static func readsLikeText(_ map: PDFInkMap, columns: Range<Int>, rows: Range<Int>) -> Bool {
        let width = columns.count
        guard width > 0, !rows.isEmpty else { return false }
        // Touching descenders and ascenders do not join two lines.
        let lineInk = max(1, width / 20)
        let tallestLine = max(6, map.height * 4 / 100)
        let widestGap = max(4, width / 8)

        var lines: [Range<Int>] = []
        var start: Int?
        for y in rows.lowerBound...rows.upperBound {
            let inked = y < rows.upperBound && map.inkedColumns(row: y, columns: columns) >= lineInk
            if inked, start == nil {
                start = y
            } else if !inked, let lineStart = start {
                lines.append(lineStart..<y)
                start = nil
            }
        }
        guard let first = lines.first, let last = lines.last else { return false }

        var textLines = 0
        var textRows = 0
        for line in lines where line.count <= tallestLine {
            var inked = 0
            var gap = 0
            var widest = 0
            var seenInk = false
            for x in columns {
                if map.inkedRows(column: x, rows: line) > 0 {
                    inked += 1
                    if seenInk { widest = max(widest, gap) }
                    seenInk = true
                    gap = 0
                } else {
                    gap += 1
                }
            }
            if inked * 2 >= width, widest <= widestGap {
                textLines += 1
                textRows += line.count
            }
        }
        let inkedHeight = last.upperBound - first.lowerBound
        return textLines >= 4 && textRows * 10 >= inkedHeight * 3
    }

    // MARK: - Bands

    private enum Kind: Equatable {
        /// No ink.
        case blank
        /// Ink across the width: a heading, an abstract, a figure.
        case spanning
        /// Columns separated by these blank gutters (column ranges).
        case split([Range<Int>])
    }

    private struct Band {
        var rows: Range<Int>
        var kind: Kind
    }

    /// Whether `rows` hold ink in 2 or 3 columns of similar width.
    private static func classify(_ rows: Range<Int>, in map: PDFInkMap) -> Kind {
        let width = map.width
        // A speck or two in a gutter column is not ink.
        let blankLimit = max(2, rows.count / 50)
        let ink = (0..<width).map { map.inkedRows(column: $0, rows: rows) }
        guard ink.contains(where: { $0 > blankLimit }) else { return .blank }

        // Blank runs inside the content (not at its edges) wide enough to be a
        // gutter rather than a word space.
        let minimumGutter = max(3, width * 12 / 1000)
        var runs: [Range<Int>] = []
        var start: Int?
        for x in 0...width {
            let blank = x < width && ink[x] <= blankLimit
            if blank, start == nil {
                start = x
            } else if !blank, let runStart = start {
                if runStart > 0, x < width, x - runStart >= minimumGutter {
                    runs.append(runStart..<x)
                }
                start = nil
            }
        }

        // The widest runs first: a real gutter is wider than any chance gap.
        let candidates = runs.sorted { $0.count > $1.count }.prefix(4)
        for count in [2, 1] where candidates.count >= count {
            for gutters in combinations(Array(candidates), count) {
                let sorted = gutters.sorted { $0.lowerBound < $1.lowerBound }
                if splitsEvenly(sorted, width: width, ink: ink, blankLimit: blankLimit) {
                    return .split(sorted)
                }
            }
        }
        return .spanning
    }

    /// Whether `gutters` divide `width` into columns of at least 20% of it each,
    /// the narrowest at least 60% of the widest, all with ink.
    private static func splitsEvenly(_ gutters: [Range<Int>], width: Int, ink: [Int], blankLimit: Int) -> Bool {
        let columns = cells(between: gutters, width: width)
        let widths = columns.map(\.count)
        guard let narrowest = widths.min(), let widest = widths.max(),
              narrowest * 5 >= width,
              narrowest * 5 >= widest * 3
        else { return false }
        return columns.allSatisfy { column in column.contains { ink[$0] > blankLimit } }
    }

    private static func cells(between gutters: [Range<Int>], width: Int) -> [Range<Int>] {
        var cells: [Range<Int>] = []
        var start = 0
        for gutter in gutters {
            cells.append(start..<gutter.lowerBound)
            start = gutter.upperBound
        }
        cells.append(start..<width)
        return cells
    }

    private static func combinations(_ items: [Range<Int>], _ count: Int) -> [[Range<Int>]] {
        guard count > 0 else { return [[]] }
        guard items.count >= count else { return [] }
        var result: [[Range<Int>]] = []
        for (index, item) in items.enumerated() {
            for rest in combinations(Array(items[(index + 1)...]), count - 1) {
                result.append([item] + rest)
            }
        }
        return result
    }

    /// Whether two splits have the same number of gutters, each overlapping.
    private static func matches(_ a: [Range<Int>], _ b: [Range<Int>]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { $0.overlaps($1) }
    }

    /// Joins neighbouring bands of the same kind (splits with matching gutters,
    /// keeping their common part); blank bands join the band above.
    private static func merged(_ bands: [Band]) -> [Band] {
        var result: [Band] = []
        for band in bands {
            guard var last = result.last else {
                result.append(band)
                continue
            }
            switch (last.kind, band.kind) {
            case (.split(let a), .split(let b)) where matches(a, b):
                last.kind = .split(common(a, b))
            case (.spanning, .spanning), (.blank, .blank), (_, .blank):
                break
            case (.blank, _):
                last.kind = band.kind
            default:
                result.append(band)
                continue
            }
            last.rows = last.rows.lowerBound..<band.rows.upperBound
            result[result.count - 1] = last
        }
        return result
    }

    /// Moves each boundary between a column band and a full-width one to the
    /// exact row: the column band takes the rows its gutters are blank in, up to
    /// the full-width block's first or last line across them.
    private static func refined(_ bands: [Band], in map: PDFInkMap) -> [Band] {
        var bands = bands
        func rowBlank(_ row: Int) -> Bool {
            (0..<map.width).allSatisfy { !map.isInked(x: $0, y: row) }
        }
        // The whole gutter: a full-width line may have a gap between two
        // letters at any one column of it.
        func gutterBlank(_ row: Int, _ gutters: [Range<Int>]) -> Bool {
            gutters.allSatisfy { gutter in
                gutter.allSatisfy { !map.isInked(x: $0, y: row) }
            }
        }
        for index in bands.indices {
            guard case .split(let gutters) = bands[index].kind else { continue }
            var rows = bands[index].rows
            if index > 0, bands[index - 1].kind == .spanning {
                // Up to the full-width block's last line across the gutter...
                var top = rows.lowerBound
                while top > bands[index - 1].rows.lowerBound, gutterBlank(top - 1, gutters) {
                    top -= 1
                }
                // ...then past that line's descenders, to the gap between blocks.
                var start = top
                while start < rows.upperBound, !rowBlank(start) {
                    start += 1
                }
                if start < rows.upperBound {
                    top = start
                }
                rows = top..<rows.upperBound
                bands[index - 1].rows = bands[index - 1].rows.lowerBound..<top
            }
            if index + 1 < bands.count, bands[index + 1].kind == .spanning {
                // Down to the full-width block's first line across the gutter...
                var bottom = rows.upperBound
                while bottom < bands[index + 1].rows.upperBound, gutterBlank(bottom, gutters) {
                    bottom += 1
                }
                // ...then back past that line's ascenders, to the gap.
                var end = bottom
                while end > rows.lowerBound, !rowBlank(end - 1) {
                    end -= 1
                }
                if end > rows.lowerBound {
                    bottom = end
                }
                rows = rows.lowerBound..<bottom
                bands[index + 1].rows = bottom..<bands[index + 1].rows.upperBound
            }
            bands[index].rows = rows
        }
        return bands.filter { !$0.rows.isEmpty }
    }

    /// Folds a short full-width band between two column bands with matching
    /// gutters into them.
    private static func mergedSlivers(_ bands: [Band], maximumSliver: Int) -> [Band] {
        var result: [Band] = []
        for band in bands {
            result.append(band)
            while result.count >= 3,
                  case .split(let above) = result[result.count - 3].kind,
                  result[result.count - 2].kind == .spanning,
                  result[result.count - 2].rows.count <= maximumSliver,
                  case .split(let below) = result[result.count - 1].kind,
                  matches(above, below) {
                let rows = result[result.count - 3].rows.lowerBound..<result[result.count - 1].rows.upperBound
                result.removeLast(3)
                result.append(Band(rows: rows, kind: .split(common(above, below))))
            }
        }
        return result
    }

    /// The parts of matching gutters both splits share.
    private static func common(_ a: [Range<Int>], _ b: [Range<Int>]) -> [Range<Int>] {
        zip(a, b).map { max($0.lowerBound, $1.lowerBound)..<min($0.upperBound, $1.upperBound) }
    }
}
