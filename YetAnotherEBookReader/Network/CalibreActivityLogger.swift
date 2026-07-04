import Foundation

actor CalibreActivityLogger {
    private let repository: ActivityLogRepositoryProtocol
    private let flushDelayNanoseconds: UInt64
    private var pendingEvents: [ActivityLogWriteEvent] = []
    private var flushTask: Task<Void, Never>?

    init(
        repository: ActivityLogRepositoryProtocol,
        flushDelayNanoseconds: UInt64 = 1_000_000_000
    ) {
        self.repository = repository
        self.flushDelayNanoseconds = flushDelayNanoseconds
    }

    func logStartCalibreActivity(
        type: String,
        request: URLRequest,
        startDatetime: Date,
        bookId: Int32?,
        libraryId: String?
    ) {
        pendingEvents.append(
            .start(
                ActivityLogStartValue(
                    type: type,
                    request: ActivityLogRequestSnapshot(request: request),
                    startDatetime: startDatetime,
                    bookId: bookId,
                    libraryId: libraryId
                )
            )
        )
        scheduleFlush()
    }

    func logFinishCalibreActivity(
        type: String,
        request: URLRequest,
        startDatetime: Date,
        finishDatetime: Date,
        errMsg: String
    ) {
        pendingEvents.append(
            .finish(
                ActivityLogFinishValue(
                    type: type,
                    request: ActivityLogRequestSnapshot(request: request),
                    startDatetime: startDatetime,
                    finishDatetime: finishDatetime,
                    errMsg: errMsg
                )
            )
        )
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }

        flushTask = Task { [flushDelayNanoseconds] in
            try? await Task.sleep(nanoseconds: flushDelayNanoseconds)
            await self.finishScheduledFlush()
        }
    }

    private func finishScheduledFlush() async {
        flushTask = nil
        await flush()
    }

    private func flush() async {
        let events = pendingEvents
        pendingEvents.removeAll()

        guard !events.isEmpty else { return }

        await repository.writeActivityLogEvents(events)
    }

    func flushPendingActivitiesForTesting() async {
        flushTask?.cancel()
        flushTask = nil
        await flush()
    }

    func removeCalibreActivity(id: String) async {
        await repository.removeCalibreActivity(id: id)
    }

    func cleanCalibreActivities(startDatetime: Date) async {
        await repository.cleanCalibreActivities(startDatetime: startDatetime)
    }
}
