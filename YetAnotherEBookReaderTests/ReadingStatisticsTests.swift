import XCTest
@testable import YetAnotherEBookReader

final class ReadingStatisticsTests: XCTestCase {
    func testWindowIncludesSevenPreviousDaysAndTodayAndCountsByStartDay() throws {
        let now = try date("2024-04-08T12:00:00Z")
        let window = ReadingStatisticsWindow(now: now, calendar: try calendar("UTC"), previousDays: 7)
        XCTAssertEqual(window.sessionStartRange.lowerBound, try date("2024-04-01T00:00:00Z"))
        XCTAssertEqual(window.sessionStartRange.upperBound, now)
        XCTAssertEqual(window.dayLabels.count, 8)
        XCTAssertEqual(window.dayLabels.last, "Today")

        let firstBook = [
            try session("starts-before-window", "2024-03-31T23:45:00Z", "2024-04-01T00:15:00Z"),
            try session("starts-at-window", "2024-04-01T00:00:00Z", "2024-04-01T01:10:00Z"),
            try session("crosses-midnight", "2024-04-07T23:30:00Z", "2024-04-08T00:30:00Z")
        ]
        let secondBook = [
            try session("ends-at-now", "2024-04-08T11:50:00Z", "2024-04-08T12:00:00Z"),
            try session("ends-after-now", "2024-04-08T11:55:00Z", "2024-04-08T12:30:00Z"),
            try session("starts-after-now", "2024-04-08T14:00:00Z", "2024-04-08T15:00:00Z")
        ]
        let statistics = ReadingStatistics(window: window, historyByBook: ["first": firstBook, "second": secondBook])
        XCTAssertEqual(statistics.minutesByDay, [70, 0, 0, 0, 0, 0, 60, 10])
        XCTAssertEqual(statistics.minutesByBook, ["first": 130, "second": 10])
        XCTAssertEqual(statistics.previousDayAverage, 130.0 / 7)
        XCTAssertEqual(statistics.previousDayMaximum, 70)
    }

    func testTodayDoesNotRaiseThePreviousDayAverageOrMaximum() throws {
        let now = try date("2024-04-08T12:00:00Z")
        let window = ReadingStatisticsWindow(now: now, calendar: try calendar("UTC"), previousDays: 7)
        let records = [
            try session("previous", "2024-04-07T23:59:00Z", "2024-04-08T00:06:00Z"),
            try session("today", "2024-04-08T00:00:00Z", "2024-04-08T02:00:00Z")
        ]
        let statistics = ReadingStatistics(window: window, historyByBook: ["book": records])
        XCTAssertEqual(statistics.minutesByDay, [0, 0, 0, 0, 0, 0, 7, 120])
        XCTAssertEqual(statistics.previousDayAverage, 1)
        XCTAssertEqual(statistics.previousDayMaximum, 7)
    }

    func testCalendarDayBoundariesAcrossSpringAndFallClockChanges() throws {
        let pacific = try calendar("America/Los_Angeles")
        let spring = ReadingStatisticsWindow(
            now: try date("2024-03-11T07:30:00Z"), calendar: pacific, previousDays: 7
        )
        let fall = ReadingStatisticsWindow(
            now: try date("2024-11-05T07:30:00Z"), calendar: pacific, previousDays: 7
        )
        XCTAssertEqual(spring.dayStarts.first, try date("2024-03-04T08:00:00Z"))
        XCTAssertEqual(spring.dayStarts[7].timeIntervalSince(spring.dayStarts[6]), 23 * 3600)
        XCTAssertEqual(fall.dayStarts.first, try date("2024-10-28T07:00:00Z"))
        XCTAssertEqual(fall.dayStarts[7].timeIntervalSince(fall.dayStarts[6]), 25 * 3600)

        let springSession = try session("spring", "2024-03-10T09:30:00Z", "2024-03-10T10:30:00Z")
        let fallSession = try session("fall", "2024-11-03T08:30:00Z", "2024-11-03T09:30:00Z")
        XCTAssertEqual(
            ReadingStatistics(window: spring, historyByBook: ["book": [springSession]]).minutesByDay,
            [0, 0, 0, 0, 0, 0, 60, 0]
        )
        XCTAssertEqual(
            ReadingStatistics(window: fall, historyByBook: ["book": [fallSession]]).minutesByDay,
            [0, 0, 0, 0, 0, 0, 60, 0]
        )
    }

    func testChangingTimeZoneReassignsTheSameSessionWithoutChangingItsDuration() throws {
        let now = try date("2024-04-08T12:00:00Z")
        let utc = ReadingStatisticsWindow(now: now, calendar: try calendar("UTC"), previousDays: 7)
        let pacific = ReadingStatisticsWindow(now: now, calendar: try calendar("America/Los_Angeles"), previousDays: 7)
        let history = ["book": [try session("one", "2024-04-08T00:00:00Z", "2024-04-08T00:15:00Z")]]
        let utcStatistics = ReadingStatistics(window: utc, historyByBook: history)
        let pacificStatistics = ReadingStatistics(window: pacific, historyByBook: history)
        XCTAssertEqual(utcStatistics.minutesByDay, [0, 0, 0, 0, 0, 0, 0, 15])
        XCTAssertEqual(pacificStatistics.minutesByDay, [0, 0, 0, 0, 0, 0, 15, 0])
        XCTAssertEqual(utcStatistics.minutesByBook, pacificStatistics.minutesByBook)
    }

    func testMissingNonFiniteAndNonPositiveDurationsDoNotEnterStatistics() throws {
        let now = try date("2024-04-08T12:00:00Z")
        let window = ReadingStatisticsWindow(now: now, calendar: try calendar("UTC"), previousDays: 7)
        let start = try date("2024-04-08T10:00:00Z")
        let ends: [Double?] = [nil, .nan, .infinity, -.infinity, .greatestFiniteMagnitude, 0, start.timeIntervalSince1970]
        let invalid = ends.enumerated().map { index, end in
            BookDeviceReadingPositionHistory(
                id: ReadingHistorySessionID(serverUUID: nil, objectID: "\(index)"),
                bookId: "library - 1",
                startDatetime: start,
                startPosition: nil,
                endPosition: end.map { TestFixtures.makeReadingPosition(epoch: $0) }
            )
        }
        let statistics = ReadingStatistics(window: window, historyByBook: ["book": invalid])
        XCTAssertEqual(statistics.minutesByDay, Array(repeating: 0, count: 8))
        XCTAssertTrue(statistics.minutesByBook.isEmpty)
        XCTAssertEqual(statistics.previousDayAverage, 0)
        XCTAssertEqual(statistics.previousDayMaximum, 0)
    }

    private func session(_ id: String, _ start: String, _ end: String) throws -> BookDeviceReadingPositionHistory {
        BookDeviceReadingPositionHistory(
            id: ReadingHistorySessionID(serverUUID: nil, objectID: id),
            bookId: "library - 1",
            startDatetime: try date(start),
            startPosition: nil,
            endPosition: TestFixtures.makeReadingPosition(epoch: try date(end).timeIntervalSince1970)
        )
    }

    private func date(_ value: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: value))
    }

    private func calendar(_ zone: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: zone))
        return calendar
    }
}
