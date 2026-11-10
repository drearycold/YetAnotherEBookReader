import Foundation
import OSLog
import UIKit

actor CalibreActivityLogger {
    private let repository: ActivityLogRepositoryProtocol
    private let flushDelayNanoseconds: UInt64
    private let retryDelaysNanoseconds: [UInt64]
    private let log = Logger(subsystem: "io.github.dsreader", category: "ActivityLog")
    private let pendingLimit = 2048
    private var pendingEvents: [ActivityLogWriteEvent] = []
    private var acceptedCount = 0
    private var resolvedCount = 0
    private var reportedOverflow = false
    private var flushTask: Task<Void, Never>?
    private struct FlushBarrier {
        let target: Int
        let continuation: CheckedContinuation<Bool, Never>
        var succeeded = true
    }
    private var barriers: [FlushBarrier] = []
    private var isWriting = false

    init(
        repository: ActivityLogRepositoryProtocol,
        flushDelayNanoseconds: UInt64 = 1_000_000_000,
        retryDelaysNanoseconds: [UInt64] = [100_000_000, 300_000_000]
    ) {
        self.repository = repository
        self.flushDelayNanoseconds = flushDelayNanoseconds
        self.retryDelaysNanoseconds = retryDelaysNanoseconds
    }

    func start(_ activity: ActivityLogStartValue) {
        submit(.start(activity))
    }

    func update(id: ActivityID, _ update: ActivityLogUpdate) {
        submit(.update(id: id, update))
    }

    @discardableResult
    func submit(_ event: ActivityLogWriteEvent) -> Bool {
        guard pendingEvents.count < pendingLimit else {
            if !reportedOverflow {
                reportedOverflow = true
                log.error("Activity log buffer is full. Dropping new events until a batch can drain.")
            }
            return false
        }
        pendingEvents.append(event)
        acceptedCount += 1
        guard flushTask == nil else { return true }

        flushTask = Task { [flushDelayNanoseconds] in
            do {
                try await Task.sleep(nanoseconds: flushDelayNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self.flushTask = nil
            await self.flush()
        }
        return true
    }

    /// Waits for every event accepted before this call, including an in-flight write.
    /// Returns false if a batch awaited by this call exhausted its retries. Later events
    /// can join a batch, but a steady stream of new events cannot extend this barrier.
    @discardableResult
    func flush() async -> Bool {
        flushTask?.cancel()
        flushTask = nil
        let target = acceptedCount
        guard resolvedCount < target else { return true }
        return await withCheckedContinuation { continuation in
            barriers.append(.init(target: target, continuation: continuation))
            if !isWriting { beginWrite() }
        }
    }

    private func beginWrite() {
        let events = pendingEvents
        let through = acceptedCount
        pendingEvents.removeAll()
        reportedOverflow = false
        isWriting = true
        Task {
            let persisted = await persist(events)
            resolveWrite(through: through, persisted: persisted)
        }
    }

    private func resolveWrite(through: Int, persisted: Bool) {
        resolvedCount = through
        isWriting = false
        var remaining: [FlushBarrier] = []
        for var barrier in barriers {
            barrier.succeeded = barrier.succeeded && persisted
            if barrier.target <= through {
                barrier.continuation.resume(returning: barrier.succeeded)
            } else {
                remaining.append(barrier)
            }
        }
        barriers = remaining
        if !barriers.isEmpty { beginWrite() }
    }

    private func persist(_ events: [ActivityLogWriteEvent]) async -> Bool {
        for delay in [UInt64(0)] + retryDelaysNanoseconds {
            if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
            do {
                try await repository.writeActivityLogEvents(events)
                return true
            } catch {
                log.error("Activity log batch write failed: \(error.localizedDescription, privacy: .private)")
            }
        }
        log.error("Activity log retries exhausted. Dropping batch of \(events.count) events.")
        return false
    }

    func flushPendingActivitiesForTesting() async {
        await flush()
    }

    func removeCalibreActivity(id: ActivityID) async {
        submit(.remove(id))
        await flush()
    }

    func cleanCalibreActivities(startDatetime: Date) async {
        submit(.prune(before: startDatetime))
        await flush()
    }

    func maintainHistory(at date: Date = Date()) async {
        // A full buffer already has work scheduled. Make room for maintenance before submitting it.
        if pendingEvents.count >= pendingLimit { await flush() }
        submit(.recoverAndPrune(at: date))
        await flush()
    }
}

/// One finite background lease for each aggregate foreground-to-background transition.
@MainActor
final class ActivityLogBackgroundFlush {
    private let begin: (@escaping () -> Void) -> UIBackgroundTaskIdentifier
    private let end: (UIBackgroundTaskIdentifier) -> Void
    private var isBackgrounded = false
    private var requested = false
    private var generation: UUID?
    private var lease = UIBackgroundTaskIdentifier.invalid
    private var work: Task<Void, Never>?

    init(
        begin: @escaping (@escaping () -> Void) -> UIBackgroundTaskIdentifier = {
            UIApplication.shared.beginBackgroundTask(withName: "Activity Log", expirationHandler: $0)
        },
        end: @escaping (UIBackgroundTaskIdentifier) -> Void = { UIApplication.shared.endBackgroundTask($0) }
    ) {
        self.begin = begin
        self.end = end
    }

    func setBackgrounded(_ value: Bool) {
        guard value != isBackgrounded else { return }
        isBackgrounded = value
        requested = false
        if let generation { finish(generation, cancel: true) }
    }

    func requestIfNeeded(hasActiveScenes: Bool, flush: @escaping @MainActor () async -> Void) {
        guard isBackgrounded, !hasActiveScenes, !requested else { return }
        requested = true
        let generation = UUID()
        self.generation = generation
        lease = begin { [weak self] in
            // UIKit invokes the expiration handler on the main thread.
            MainActor.assumeIsolated { self?.finish(generation, cancel: true) }
        }
        work = Task {
            await flush()
            finish(generation, cancel: false)
        }
    }

    private func finish(_ generation: UUID, cancel: Bool) {
        guard self.generation == generation else { return }
        self.generation = nil
        if cancel { work?.cancel() }
        work = nil
        if lease != .invalid { end(lease) }
        lease = .invalid
    }
}
