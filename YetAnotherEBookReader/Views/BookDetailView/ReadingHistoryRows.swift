import Foundation

/// One saved position in a device section of Reading History.
struct ReadingHistoryPositionRow: Identifiable {
    let id: String
    let position: BookDeviceReadingPosition
    /// The chapter, or the book of a bundle (`structuralStyle != 0`).
    let title: String
    /// The chapter, when `title` is the book of a bundle.
    let detail: String?
    let percentText: String
    let relativeTimeText: String
    let readerName: String
    let canContinue: Bool
}

struct ReadingHistoryDeviceSection: Identifiable {
    var id: String { deviceName }
    let deviceName: String
    let isThisDevice: Bool
    let rows: [ReadingHistoryPositionRow]
}

/// One reading session on this device, from its start to its last saved position.
struct ReadingHistorySessionRow: Identifiable {
    let id: ReadingHistorySessionID
    let chapter: String
    let durationText: String
    let dateText: String
}

