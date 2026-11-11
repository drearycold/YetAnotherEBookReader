//
//  ReadingPositionModels.swift
//  YetAnotherEBookReader
//
//  Split from CalibreData.swift on 2026/6/18.
//  Zero-behavior-change move: reading-position value types and statistics.
//

import Foundation

/*
struct BookReadingPositionLegacy {
    private var deviceMap = [String: BookDeviceReadingPosition]()
    private var devices = [BookDeviceReadingPosition]()
    
    var isEmpty: Bool { get { deviceMap.isEmpty } }
    
    func getPosition(_ deviceName: String) -> BookDeviceReadingPosition? {
        return deviceMap[deviceName]
    }
    
    mutating func addInitialPosition(_ deviceName: String, _ readerName: String) {
        let initialPosition = BookDeviceReadingPosition(id: deviceName, readerName: readerName)
        self.updatePosition(deviceName, initialPosition)
    }
    
    mutating func updatePosition(_ deviceName: String, _ newPosition: BookDeviceReadingPosition) {
        if let oldPosition = deviceMap[deviceName] {
            devices.removeAll { (it) -> Bool in
                it.id == oldPosition.id
            }
        }
        deviceMap[deviceName] = newPosition
        devices.append(newPosition)
        devices.sort { (lhs, rhs) -> Bool in
            
            if lhs.lastPosition[0] == rhs.lastPosition[0] {
                return (lhs.lastPosition[1] + lhs.lastPosition[2]) > (rhs.lastPosition[1] + rhs.lastPosition[2])
            } else {
                return lhs.lastPosition[0] > rhs.lastPosition[0]
            }
        }
    }
    
    mutating func removePosition(_ deviceName: String) {
        deviceMap.removeValue(forKey: deviceName)
        devices.removeAll { position in
            position.id == deviceName
        }
    }
    
    func getCopy() -> [String: BookDeviceReadingPosition] {
        return deviceMap
    }
    
    func getDevices() -> [BookDeviceReadingPosition] {
        return devices
    }
    
    func getDevices(by reader: ReaderType) -> [BookDeviceReadingPosition] {
        return devices.filter {
            $0.readerName == reader.id
        }
    }
}
*/

struct BookDeviceReadingPosition : Hashable, Codable, Sendable {
    static func == (lhs: BookDeviceReadingPosition, rhs: BookDeviceReadingPosition) -> Bool {
        lhs.id == rhs.id
            && lhs.readerName == rhs.readerName
            && lhs.lastReadPage == rhs.lastReadPage
            && lhs.lastProgress == rhs.lastProgress
            && lhs.structuralRootPageNumber == rhs.structuralRootPageNumber
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(readerName)
        hasher.combine(lastReadPage)
        hasher.combine(structuralStyle)
        hasher.combine(positionTrackingStyle)
        hasher.combine(structuralRootPageNumber)
    }
    
    var id: String = ""  //device name
    
    var readerName: String
    
    var maxPage = 0
    var lastReadPage = 0
    var lastReadChapter = ""
    /// range 0 - 100
    var lastChapterProgress = 0.0
    /// range 0 - 100
    var lastProgress = 0.0
    var furthestReadPage = 0
    var furthestReadChapter = ""
    var lastPosition = [0, 0, 0]
    var cfi = "/"
    var epoch = 0.0     //timestamp
    
    //for non-linear book structure
    var structuralStyle: Int = .zero
    var structuralRootPageNumber: Int = .zero
    var positionTrackingStyle: Int = .zero
    var lastReadBook: String = .init()
    var lastBundleProgress: Double = .zero
    
    enum CodingKeys: String, CodingKey {
        case readerName
        case lastReadPage
        case lastReadChapter
        case lastChapterProgress
        case lastProgress
        case furthestReadPage
        case furthestReadChapter
        case maxPage
        case lastPosition
        case cfi
        case epoch
        
        case structuralStyle
        case structuralRootPageNumber
        case positionTrackingStyle
        case lastReadBook
        case lastBundleProgress
    }
    
    var description: String {
        return """
            \(id) with \(readerName):
                Chapter: \(lastReadChapter), \(String(format: "%.2f", 100 - lastChapterProgress))% Left
                Book: Page \(lastReadPage), \(String(format: "%.2f", 100 - lastProgress))% Left
                (\(lastPosition[0]):\(lastPosition[1]):\(lastPosition[2]))
            """
    }
    
    static func < (lhs: BookDeviceReadingPosition, rhs: BookDeviceReadingPosition) -> Bool {
        if lhs.lastReadPage < rhs.lastReadPage {
            return true
        } else if lhs.lastReadPage > rhs.lastReadPage {
            return false
        }
        if lhs.lastChapterProgress < rhs.lastChapterProgress {
            return true
        } else if lhs.lastChapterProgress > rhs.lastChapterProgress {
            return false
        }
        if lhs.lastProgress < rhs.lastProgress {
            return true
        }
        return false
    }
    
    static func << (lhs: BookDeviceReadingPosition, rhs: BookDeviceReadingPosition) -> Bool {
        if (lhs.lastProgress + 10) < rhs.lastProgress {
            return true
        }
        return false
    }
    
    mutating func update(with other: BookDeviceReadingPosition) {
        maxPage = other.maxPage
        lastReadPage = other.lastReadPage
        lastReadChapter = other.lastReadChapter
        lastChapterProgress = other.lastChapterProgress
        lastProgress = other.lastProgress
        lastPosition = other.lastPosition
        cfi = other.cfi
        epoch = other.epoch
    }
    
    /// Where this position is, for prompts: "Chapter 3 · 45.0% · iPad, Yesterday 21:30".
    var promptSummary: String {
        let chapter = lastReadChapter.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = chapter.isEmpty ? "Page \(lastReadPage)" : chapter
        return "\(place) · \(String(format: "%.1f%%", lastProgress)) · \(id), \(epochByLocaleRelative)"
    }
    
    func isSameProgress(with other: BookDeviceReadingPosition) -> Bool {
        if id == other.id,
            readerName == other.readerName,
            lastReadPage == other.lastReadPage,
            lastChapterProgress == other.lastChapterProgress,
            lastProgress == other.lastProgress {
            return true
        }
        return false
    }
    
    func isSameType(with other: BookDeviceReadingPosition) -> Bool {
        return id == other.id && readerName == other.readerName
    }
    
    var epochByLocale: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .medium
        dateFormatter.locale = Locale.autoupdatingCurrent
        return dateFormatter.string(from: Date(timeIntervalSince1970: epoch))
    }
    
    var epochByLocaleRelative: String {
        let dateFormatter = DateFormatter()
        dateFormatter.doesRelativeDateFormatting = true
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .medium
        dateFormatter.locale = Locale.autoupdatingCurrent
        return dateFormatter.string(from: Date(timeIntervalSince1970: epoch))
    }
    
    var epochLocaleLong: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .long
        dateFormatter.locale = Locale.autoupdatingCurrent
        return dateFormatter.string(from: Date(timeIntervalSince1970: epoch))
    }
}



struct ReadingHistorySessionID: Hashable, Sendable {
    /// A nil server UUID identifies the main Realm, which also contains legacy rows.
    let serverUUID: UUID?
    let objectID: String
}

struct ReadingSessionTiming: Sendable {
    let id: ReadingHistorySessionID
    let startDatetime: Date
    let endEpoch: TimeInterval

    func elapsedSeconds(through now: Date) -> TimeInterval? {
        let start = startDatetime.timeIntervalSince1970
        guard start.isFinite, endEpoch.isFinite,
              start >= 0, endEpoch >= start, endEpoch <= now.timeIntervalSince1970 else { return nil }
        return endEpoch - start
    }
}

struct BookDeviceReadingPositionHistory: Identifiable, Sendable {
    let id: ReadingHistorySessionID
    /// The persisted preference key, interpreted within the session's Realm scope.
    let bookId: String
    let startDatetime: Date
    let startPosition: BookDeviceReadingPosition?
    let endPosition: BookDeviceReadingPosition?

    var timing: ReadingSessionTiming? {
        endPosition.map { ReadingSessionTiming(id: id, startDatetime: startDatetime, endEpoch: $0.epoch) }
    }
}

struct ReadingStatisticsWindow: Sendable {
    let now: Date
    let calendar: Calendar
    let dayStarts: [Date]
    let sessionStartRange: ClosedRange<Date>

    init(now: Date, calendar: Calendar, previousDays: Int) {
        self.now = now
        self.calendar = calendar

        var day = calendar.startOfDay(for: now)
        var days = [day]
        for _ in 0..<max(0, previousDays) {
            // Use the actual previous day boundary, including days whose midnight is skipped.
            day = calendar.startOfDay(for: day.addingTimeInterval(-1))
            days.append(day)
        }
        dayStarts = Array(days.reversed())
        sessionStartRange = day...now
    }

    var dayLabels: [String] {
        let symbols = calendar.shortWeekdaySymbols
        return dayStarts.dropLast().map { symbols[calendar.component(.weekday, from: $0) - 1] } + ["Today"]
    }
}

struct ReadingStatistics: Sendable {
    let minutesByDay: [Double]
    let minutesByBook: [String: Double]
    let rankedBookIDs: [String]

    private init(minutesByDay: [Double], minutesByBook: [String: Double]) {
        self.minutesByDay = minutesByDay
        self.minutesByBook = minutesByBook
        rankedBookIDs = minutesByBook.sorted { first, second in
            first.value == second.value ? first.key < second.key : first.value > second.value
        }.map(\.key)
    }

    var previousDayAverage: Double {
        let previous = minutesByDay.dropLast()
        return previous.isEmpty ? 0 : previous.reduce(0, +) / Double(previous.count)
    }

    var previousDayMaximum: Double { minutesByDay.dropLast().max() ?? 0 }

    /// Keys are the canonical shelf book IDs. A whole session counts toward the day it starts.
    init(window: ReadingStatisticsWindow, historyByBook: [String: [BookDeviceReadingPositionHistory]]) {
        var accumulator = Accumulator(window: window)
        for bookID in historyByBook.keys.sorted() {
            for session in historyByBook[bookID, default: []] {
                if let timing = session.timing { accumulator.add(timing, bookID: bookID) }
            }
        }
        self = accumulator.result
    }

    struct Accumulator {
        private let window: ReadingStatisticsWindow
        private var days: [Double]
        private var books: [String: Double] = [:]
        private var counted = Set<ReadingHistorySessionID>()

        init(window: ReadingStatisticsWindow) {
            self.window = window
            days = Array(repeating: 0, count: window.dayStarts.count)
        }

        mutating func add(_ session: ReadingSessionTiming, bookID: String) {
            guard let seconds = session.elapsedSeconds(through: window.now), seconds > 0,
                  window.sessionStartRange.contains(session.startDatetime),
                  let day = window.dayStarts.firstIndex(of: window.calendar.startOfDay(for: session.startDatetime)),
                  counted.insert(session.id).inserted else { return }
            let minutes = seconds / 60
            days[day] += minutes
            books[bookID, default: 0] += minutes
        }

        var result: ReadingStatistics {
            ReadingStatistics(minutesByDay: days, minutesByBook: books)
        }
    }
}

enum ReadingPositionSelectionPolicy: Equatable, Sendable {
    case latest
    case latestForDevice(String)
    
    func select(from positions: [BookDeviceReadingPosition]) -> BookDeviceReadingPosition? {
        switch self {
        case .latest:
            guard !positions.isEmpty else { return nil }
            var best = positions[0]
            for position in positions.dropFirst() {
                if position.epoch > best.epoch {
                    best = position
                }
            }
            return best
            
          case .latestForDevice(let deviceName):
            let devicePositions = positions.filter { $0.id == deviceName }
            guard !devicePositions.isEmpty else { return nil }
            var best = devicePositions[0]
            for position in devicePositions.dropFirst() {
                if position.epoch > best.epoch {
                    best = position
                }
            }
            return best
        }
    }
}

public struct ReadingSessionHandle: Hashable, Sendable {
    public let bookId: String
    public let historyId: String
    
    public init(bookId: String, historyId: String) {
        self.bookId = bookId
        self.historyId = historyId
    }
}
