//
//  BookmarkMerge.swift
//  YetAnotherEBookReader
//

import Foundation

/// How a book's bookmarks here and on calibre are kept the same.
///
/// calibre keeps one bookmark per title for each book, format and user
/// (`merge_annots_with_identical_field` in calibre's `db/annotations.py`):
/// - an upload replaces the bookmark of that title when its timestamp is newer;
/// - a removal is a newer copy marked `removed`;
/// - on equal timestamps the server keeps its own.
///
/// The app keeps every bookmark it has seen, removed ones included, and its readers address them
/// by position. So:
/// - a book's visible bookmarks have titles of their own (`uniqueTitle`);
/// - calibre's bookmark of a title is the local bookmark with that title *at the same position*,
///   and the newer of the two wins;
/// - calibre's bookmark of a title somewhere else is another bookmark. It keeps the title and the
///   local one gets a new title, so neither is lost. A bookmark moved in calibre's viewer (by
///   adding one with an existing title) therefore stays behind here under a new title.
enum BookmarkMerge {
    /// Timestamps this close are one edit: uploads carry milliseconds. Any wider and an edit made
    /// soon after a sync would count as the server's copy, which wins a tie.
    static let tolerance: TimeInterval = 0.002

    /// `title`, or the first of `title #2`, `title #3`… that isn't taken, as calibre's viewer
    /// numbers its default titles.
    static func uniqueTitle(_ title: String, avoiding taken: Set<String>) -> String {
        guard taken.contains(title) else { return title }
        var number = 2
        while taken.contains("\(title) #\(number)") {
            number += 1
        }
        return "\(title) #\(number)"
    }

    struct Plan {
        /// Local bookmarks whose title, date or removal changes.
        var updated: [BookBookmark] = []
        /// calibre's bookmarks this device doesn't have yet.
        var inserted: [BookBookmark] = []
        /// What calibre needs to match this device: one entry per title, where the server's
        /// differs. calibre merges an upload into what it has, so the rest needn't be sent.
        var upload: [CalibreBookAnnotationBookmarkEntry] = []
    }

    private struct Remote {
        let entry: CalibreBookAnnotationBookmarkEntry
        let date: Date
        var removed: Bool { entry.removed ?? false }

        func isAt(_ bookmark: BookBookmark) -> Bool {
            bookmark.pos_type == entry.pos_type && bookmark.pos == entry.pos
        }
    }

    /// Merges calibre's bookmarks of one format into a book's local ones.
    ///
    /// - Parameters:
    ///   - local: all of the book's bookmarks, removed ones included.
    ///   - entries: calibre's bookmarks of the format.
    ///   - posType: the bookmarks the format's reader makes. Only those are merged and uploaded;
    ///     titles stay unique across all of the book's bookmarks.
    static func plan(
        local: [BookBookmark],
        remote entries: [CalibreBookAnnotationBookmarkEntry],
        posType: String,
        bookId: String,
        now: Date = Date()
    ) -> Plan {
        var remote = [String: Remote]()
        for entry in entries where entry.type == "bookmark" {
            guard let date = parseLastModified(entry.timestamp) else { continue }
            if let kept = remote[entry.title], kept.date >= date { continue }
            remote[entry.title] = Remote(entry: entry, date: date)
        }

        var records = local
        var changed = Set<Int>()
        var inserted = [BookBookmark]()
        var taken = Set(local.map(\.title)).union(remote.keys)

        func retitle(_ index: Int) {
            let title = uniqueTitle(records[index].title, avoiding: taken)
            taken.insert(title)
            records[index].title = title
            records[index].date = now
            changed.insert(index)
        }

        /// The newest of `visible` keeps the title over calibre's removed or replaced one, so it
        /// has to be newer; the others get titles of their own.
        func keepNewest(of visible: [Int], over theirs: Remote) {
            guard let newest = visible.first else { return }
            if records[newest].date <= theirs.date.addingTimeInterval(tolerance) {
                records[newest].date = max(now, theirs.date.addingTimeInterval(1))
                changed.insert(newest)
            }
            visible.dropFirst().forEach(retitle)
        }

        let groups = Dictionary(grouping: local.indices.filter { local[$0].pos_type == posType }) { local[$0].title }
        for title in Set(groups.keys).union(remote.keys).sorted() {
            let group = groups[title] ?? []
            let visible = group.filter { !records[$0].removed }.sorted { records[$0].date > records[$1].date }

            guard let theirs = remote[title] else {
                visible.dropFirst().forEach(retitle)
                continue
            }

            let twin = group.filter { theirs.isAt(records[$0]) }.max { records[$0].date < records[$1].date }
            if let twin {
                let diff = records[twin].date.timeIntervalSince(theirs.date)
                if diff < -tolerance || (abs(diff) <= tolerance && records[twin].removed != theirs.removed) {
                    records[twin].date = theirs.date
                    records[twin].removed = theirs.removed
                    changed.insert(twin)
                }
                let others = visible.filter { $0 != twin }
                if records[twin].removed {
                    keepNewest(of: others, over: theirs)
                } else {
                    others.forEach(retitle)
                }
            } else if theirs.removed {
                keepNewest(of: visible, over: theirs)
            } else {
                visible.forEach(retitle)
                if theirs.entry.pos_type == posType,
                   let bookmark = BookBookmark(entry: theirs.entry, bookId: bookId, date: theirs.date) {
                    inserted.append(bookmark)
                }
            }
        }

        var upload = [CalibreBookAnnotationBookmarkEntry]()
        let merged = records.filter { $0.pos_type == posType } + inserted
        for (title, group) in Dictionary(grouping: merged, by: \.title).sorted(by: { $0.key < $1.key }) {
            let theirs = remote[title]
            if let mine = group.filter({ !$0.removed }).max(by: { $0.date < $1.date }) {
                if let theirs, !theirs.removed, theirs.isAt(mine),
                   mine.date <= theirs.date.addingTimeInterval(tolerance) {
                    continue
                }
                upload.append(mine.toCalibreBookAnnotationBookmarkEntry())
            } else if let theirs, !theirs.removed,
                      let mine = group.filter({ theirs.isAt($0) }).max(by: { $0.date < $1.date }),
                      mine.date > theirs.date.addingTimeInterval(tolerance) {
                upload.append(mine.toCalibreBookAnnotationBookmarkEntry())
            }
        }

        return Plan(
            updated: changed.sorted().map { records[$0] },
            inserted: inserted,
            upload: upload
        )
    }
}

extension Format {
    /// The bookmarks this format's reader makes, which its calibre bookmarks are merged with:
    /// FolioReader's for EPUB, YabrPDF's for PDF. No reader bookmarks a CBZ.
    var bookmarkPosType: String? {
        switch self {
        case .EPUB:
            return "epubcfi"
        case .PDF:
            return BookBookmarkRealm.PDFBookmarkPosType
        case .CBZ, .UNKNOWN:
            return nil
        }
    }
}

extension BookBookmark {
    /// calibre's bookmark, for a reader that can open its position.
    init?(entry: CalibreBookAnnotationBookmarkEntry, bookId: String, date: Date) {
        guard let page = Self.page(posType: entry.pos_type, pos: entry.pos) else { return nil }
        self.init(
            bookId: bookId,
            page: page,
            pos_type: entry.pos_type,
            pos: entry.pos,
            title: entry.title,
            date: date,
            removed: entry.removed ?? false
        )
    }

    /// The page a position is on: the spine item of an EPUB CFI (its first step is twice the
    /// item's number), or the page of a YabrPDF location.
    static func page(posType: String, pos: String) -> Int? {
        switch posType {
        case "epubcfi":
            let prefix = "epubcfi(/"
            guard pos.hasPrefix(prefix) else { return nil }
            let steps = pos.dropFirst(prefix.count)
            guard let end = steps.firstIndex(where: { $0 == "/" || $0 == ")" }),
                  let firstStep = Int(steps[..<end])
            else { return nil }
            return firstStep / 2
        case BookBookmarkRealm.PDFBookmarkPosType:
            return (try? JSONDecoder().decode(PDFLocationPage.self, from: Data(pos.utf8)))?.page
        default:
            return nil
        }
    }
}

/// The page of a YabrPDF bookmark's `pos` (an encoded `PDFBookmark.Location`).
private struct PDFLocationPage: Decodable {
    let page: Int
}
