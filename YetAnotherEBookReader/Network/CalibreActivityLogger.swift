import Foundation

actor CalibreActivityLogger {
    private let repository: ActivityLogRepositoryProtocol
    private let flushDelayNanoseconds: UInt64
    private var pendingEvents: [ActivityLogWriteEvent] = []
    private var flushTask: Task<Void, Never>?
    private var latestWrite: Task<Void, Never>?

    init(
        repository: ActivityLogRepositoryProtocol,
        flushDelayNanoseconds: UInt64 = 1_000_000_000
    ) {
        self.repository = repository
        self.flushDelayNanoseconds = flushDelayNanoseconds
    }

    func start(_ activity: ActivityLogStartValue) {
        enqueue(.start(activity))
    }

    func update(id: ActivityID, _ update: ActivityLogUpdate) {
        enqueue(.update(id: id, update))
    }

    private func enqueue(_ event: ActivityLogWriteEvent) {
        pendingEvents.append(event)
        guard flushTask == nil else { return }

        flushTask = Task { [flushDelayNanoseconds] in
            do {
                try await Task.sleep(nanoseconds: flushDelayNanoseconds)
            } catch {
                return
            }
            await self.finishScheduledFlush()
        }
    }

    private func finishScheduledFlush() async {
        flushTask = nil
        await flush()
    }

    private func flush() async {
        if !pendingEvents.isEmpty {
            let events = pendingEvents
            pendingEvents.removeAll()

            // Actor reentrancy can allow another flush before this write returns.
            // Submit batches in order so an update can't reach Realm ahead of its start.
            let previousWrite = latestWrite
            latestWrite = Task { [repository] in
                await previousWrite?.value
                await repository.writeActivityLogEvents(events)
            }
        }
        await latestWrite?.value
    }

    func flushPendingActivitiesForTesting() async {
        flushTask?.cancel()
        flushTask = nil
        await flush()
    }

    func removeCalibreActivity(id: ActivityID) async {
        await repository.removeCalibreActivity(id: id)
    }

    func cleanCalibreActivities(startDatetime: Date) async {
        await repository.cleanCalibreActivities(startDatetime: startDatetime)
    }
}

// Temporary write adapter for the current service and download callers.
// Remove in AL4 after AL2 and AL3 switch to start/update.
extension CalibreActivityLogger {
    func logStartCalibreActivity(
        type: String,
        request: URLRequest,
        startDatetime: Date,
        bookId: Int32?,
        libraryId: String?
    ) {
        enqueue(.legacyStart(ActivityLogLegacyStartValue(
            type: type,
            request: ActivityLogRequestSnapshot(request: request),
            startDatetime: startDatetime,
            bookId: bookId,
            libraryId: libraryId
        )))
    }

    func logFinishCalibreActivity(
        type: String,
        request: URLRequest,
        startDatetime: Date,
        finishDatetime: Date,
        errMsg: String
    ) {
        enqueue(.legacyFinish(ActivityLogLegacyFinishValue(
            type: type,
            endpointURL: ActivityLogRequestSnapshot.redactedURL(request.url),
            startDatetime: startDatetime,
            finishDatetime: finishDatetime,
            errMsg: errMsg
        )))
    }
}
