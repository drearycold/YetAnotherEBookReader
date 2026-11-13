import Foundation
import Darwin
import OSLog

struct LocalBookFileOperations {
    var copy: (URL, URL) throws -> Void = { try FileManager.default.copyItem(at: $0, to: $1) }
    var move: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }
    var replace: (URL, URL) throws -> Void = { staged, destination in
        // The staging directory is on the destination volume. POSIX rename either
        // installs the staged file or leaves the existing destination in place.
        guard rename(staged.path, destination.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
    var remove: (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }

    static func live() -> LocalBookFileOperations {
        #if FI1_UI_TEST_FIXTURE
        var files = LocalBookFileOperations()
        if ProcessInfo.processInfo.environment["YABR_FI1_FAIL_OVERWRITE"] == "1",
           UITestingConfiguration.skipsConsentPrompts() {
            let replace = files.replace
            var failOnce = true
            files.replace = { source, destination in
                if failOnce, source.lastPathComponent == "incoming" {
                    failOnce = false
                    throw CocoaError(.fileWriteNoPermission)
                }
                try replace(source, destination)
            }
        }
        return files
        #else
        return LocalBookFileOperations()
        #endif
    }
}

extension CalibreBook {
    func clearingCachedFormat(_ format: Format) -> CalibreBook {
        var book = self
        book.formats[format.rawValue]?.cacheMTime = .distantPast
        book.formats[format.rawValue]?.cacheSize = 0
        book.formats[format.rawValue]?.cached = false
        book.formats[format.rawValue]?.selected = nil
        book.lastUpdated = Date()
        return book
    }
}

/// Local file mutations are serialized through persistence, cleanup, and main-actor publication.
final class LocalBookImportCoordinator: @unchecked Sendable {
    typealias MetadataLoader = @Sendable (URL) async throws -> LocalPublicationMetadata
    typealias Publish = @MainActor (Changes) -> Void

    struct Scope: Sendable {
        let storage: LocalBookStorageScope
        let directory: URL
        let databaseChanges: @MainActor @Sendable () -> AsyncStream<Void>
        let libraryChanges: @MainActor @Sendable () -> AsyncStream<[String: CalibreLibrary]>
        let serverChanges: @MainActor @Sendable () -> AsyncStream<[String: CalibreServer]>
        var library: CalibreLibrary { storage.library }
        var databaseID: UUID { storage.database.id }
        let isCurrent: @MainActor @Sendable () -> Bool
    }

    struct Changes {
        var savedBooks = [CalibreBook]()
        var removedIDs = Set<String>()
        var replacedPaths = Set<URL>()
    }

    private struct FileVersion: Equatable, Sendable {
        let inode: UInt64
        let device: UInt64
        let size: UInt64
        let modified: Date
        let created: Date?

        init(_ url: URL) throws {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  let inode = attributes[.systemFileNumber] as? NSNumber,
                  let device = attributes[.systemNumber] as? NSNumber,
                  let size = attributes[.size] as? NSNumber, size.uint64Value > 0,
                  let modified = attributes[.modificationDate] as? Date
            else { throw ImportError.loadMetaFail }
            self.inode = inode.uint64Value
            self.device = device.uint64Value
            self.size = size.uint64Value
            self.modified = modified
            created = attributes[.creationDate] as? Date
        }
    }

    private struct Publication: Sendable {
        let operationID: UUID
        let shelfID: String
        let format: Format
        let filename: String
        let fallbackTitle: String?
        let url: URL
        let version: FileVersion
        let recordVersion: Date
        let coverURL: URL?
    }

    private struct ImportOutcome {
        var info: BookImportInfo
        var changes = Changes()
        var publication: Publication?
    }

    private struct RemovalOutcome {
        var result: BookFileRemovalResult
        var changes = Changes()
    }

    private struct Enrichment {
        let publication: Publication
        let task: Task<Void, Never>
        let scopeObservers: [Task<Void, Never>]
        let scope: Scope
    }

    private final class Cancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false

        func cancel() { lock.withLock { cancelled = true } }
        var isCancelled: Bool { lock.withLock { cancelled } }
    }

    // Only this worker uses the file adapter and scoped repository for local mutations.
    private let queue = DispatchQueue(label: "local-book-files", qos: .userInitiated)
    private let repository: BookRepositoryProtocol
    private let files: LocalBookFileOperations
    private let loadMetadata: MetadataLoader
    private let logger = Logger(subsystem: "YetAnotherEBookReader", category: "LocalBookImport")
    @MainActor private var tail: (id: UUID, task: Task<Void, Never>)?
    @MainActor private var enrichments = [String: Enrichment]()

    init(repository: BookRepositoryProtocol, files: LocalBookFileOperations, loadMetadata: @escaping MetadataLoader) {
        self.repository = repository
        self.files = files
        self.loadMetadata = loadMetadata
    }

    deinit {
        for enrichment in enrichments.values {
            enrichment.task.cancel()
            enrichment.scopeObservers.forEach { $0.cancel() }
        }
    }

    #if DEBUG
    @MainActor
    func enrichmentTask(bookID: String) -> Task<Void, Never>? { enrichments[bookID]?.task }
    #endif

    @MainActor
    func run(_ request: LocalBookImportRequest, scope: Scope, publish: @escaping Publish,
             coverCache: BookCoverCaching?) async -> BookImportInfo {
        // Hold access from submission until the queued worker has finished all source I/O.
        let accessed = request.url.startAccessingSecurityScopedResource()
        defer { if accessed { request.url.stopAccessingSecurityScopedResource() } }
        return await enqueue(scope: scope, work: { [self] cancelled in
            importFile(request, scope: scope, cancelled: cancelled)
        }, finish: { [self] outcome in
            guard scope.isCurrent() else {
                var info = outcome.info
                if outcome.publication == nil { info = info.with(error: .cancelled) }
                return info
            }
            retireEnrichments(bookIDs: outcome.changes.removedIDs, paths: [], coverCache: coverCache)
            publish(outcome.changes)
            if let publication = outcome.publication {
                startEnrichment(publication, scope: scope, publish: publish, coverCache: coverCache)
            }
            return outcome.info
        })
    }

    @MainActor
    func remove(bookID: String, format: Format? = nil, scope: Scope, publish: @escaping Publish,
                coverCache: BookCoverCaching?) async -> BookFileRemovalResult {
        await enqueue(scope: scope, work: { [self] cancelled in
            removeFiles(bookID: bookID, format: format, scope: scope, cancelled: cancelled)
        }, finish: { [self] outcome in
            if scope.isCurrent() {
                retireEnrichments(bookIDs: outcome.changes.removedIDs, paths: outcome.changes.replacedPaths, coverCache: coverCache)
                publish(outcome.changes)
            }
            return outcome.result
        })
    }

    @MainActor
    func scan(scope: Scope, publish: @escaping Publish, coverCache: BookCoverCaching?) async {
        await enqueue(scope: scope, work: { [self] cancelled in
            scanFiles(scope: scope, cancelled: cancelled)
        }, finish: { [self] scan in
            guard scope.isCurrent() else { return }
            retireEnrichments(bookIDs: scan.changes.removedIDs, paths: scan.changes.replacedPaths, coverCache: coverCache)
            publish(scan.changes)
            for publication in scan.publications {
                startEnrichment(publication, scope: scope, publish: publish, coverCache: coverCache)
            }
        })
    }

    /// The library transaction has already removed its records. Queue only file cleanup.
    @MainActor
    func cleanupRemovedLibraryFiles(_ paths: Set<URL>) {
        let stale = enrichments.values.filter { !$0.scope.isCurrent() }
        stale.forEach { retire($0.publication) }
        guard !paths.isEmpty else { return }
        let previous = tail?.task
        let task = Task { @MainActor [self] in
            await previous?.value
            await onFileWorker {
                for path in paths where FileManager.default.fileExists(atPath: path.path) {
                    do { try self.files.remove(path) }
                    catch { self.logger.error("File cleanup is pending after a committed library removal") }
                }
            }
        }
        track(task)
    }

    // A single queue runs the synchronous filesystem and Realm work. The next operation also
    // waits for the preceding main-actor publication so shelf snapshots keep commit order.
    @MainActor
    private func enqueue<Value, Output>(
        scope: Scope, isCurrent: @escaping @MainActor () -> Bool = { true },
        work: @escaping (@escaping () -> Bool) -> Value,
        finish: @escaping @MainActor (Value) -> Output
    ) async -> Output {
        let previous = tail?.task
        let cancellation = Cancellation()
        let operation = Task { @MainActor in
            await previous?.value
            if !scope.isCurrent() || !isCurrent() { cancellation.cancel() }
            let value = await onFileWorker {
                work { cancellation.isCancelled || (try? scope.storage.lifetime.checkCurrent()) == nil }
            }
            return finish(value)
        }
        track(operation)
        return await withTaskCancellationHandler {
            await operation.value
        } onCancel: {
            cancellation.cancel()
        }
    }

    private func onFileWorker<Value>(_ work: @escaping () -> Value) async -> Value {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: autoreleasepool(invoking: work)) }
        }
    }

    @MainActor
    private func track<Value>(_ operation: Task<Value, Never>) {
        let id = UUID()
        tail = (id, Task { @MainActor [weak self] in
            _ = await operation.value
            if self?.tail?.id == id { self?.tail = nil }
        })
    }

    private func importFile(_ request: LocalBookImportRequest, scope: Scope, cancelled: () -> Bool) -> ImportOutcome {
        let source = request.url
        var result = BookImportInfo(request: request, databaseID: scope.databaseID, libraryID: scope.library.id)
        guard !cancelled() else { return ImportOutcome(info: result.with(error: .cancelled)) }
        guard let format = Format(rawValue: source.pathExtension.uppercased()), format != .UNKNOWN else {
            return ImportOutcome(info: result.with(error: .formatUnsupported))
        }

        let name = source.deletingPathExtension().lastPathComponent
        var destination = scope.directory.appendingPathComponent(name).appendingPathExtension(format.ext)
        let sourcePath = source.resolvingSymlinksInPath().standardizedFileURL
        let destinationPath = destination.resolvingSymlinksInPath().standardizedFileURL
        let sourceIdentity = try? source.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
        let destinationIdentity = try? destination.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
        let sameFile = sourcePath == destinationPath || sourceIdentity?.isEqual(destinationIdentity) == true
        if sameFile, sourcePath.deletingLastPathComponent() == destinationPath.deletingLastPathComponent() {
            destination = source
        }

        var workspace: URL?
        var backup: URL?
        var keepBackup = false
        var installed = false
        do {
            try checkCancellation(cancelled)
            guard let sourceID = localBookID(source) else { throw ImportError.idCalcFail }
            try checkCancellation(cancelled)
            result.bookId = sourceID
            let existingBook = try book(sourceID, scope: scope)
            if let existingBook, existingBook.inShelf,
               let info = existingBook.formats[format.rawValue], info.cached, let filename = info.filename,
               FileManager.default.isReadableFile(atPath: scope.directory.appendingPathComponent(filename).path) {
                return ImportOutcome(info: result, changes: Changes(savedBooks: [existingBook]))
            }

            if !sameFile, FileManager.default.fileExists(atPath: destination.path) {
                if request.asNew {
                    guard let available = (1..<100).lazy.map({
                        scope.directory.appendingPathComponent("\(name) (\($0))").appendingPathExtension(format.ext)
                    }).first(where: { !FileManager.default.fileExists(atPath: $0.path) }) else {
                        throw ImportError.tooManyFiles
                    }
                    destination = available
                } else if !request.overwrite {
                    throw ImportError.destConflict
                }
            }

            let input: URL
            if sameFile {
                input = source
            } else {
                let folder = try makeWorkspace(near: destination, id: request.id)
                workspace = folder
                input = folder.appendingPathComponent("incoming")
                try files.copy(source, input)
            }
            try checkCancellation(cancelled)
            let version = try FileVersion(input)
            guard localBookID(input) == sourceID else { throw ImportError.idCalcFail }
            let previous = try repository.localFileOwners(scope: scope.storage, filename: destination.lastPathComponent, format: format)
                .filter { $0.id != sourceID }
            if let workspace {
                if FileManager.default.fileExists(atPath: destination.path) {
                    guard request.overwrite else { throw ImportError.destConflict }
                    let saved = workspace.appendingPathComponent("previous")
                    try files.copy(destination, saved)
                    backup = saved
                    try checkCancellation(cancelled)
                    try files.replace(input, destination)
                } else {
                    try checkCancellation(cancelled)
                    try files.move(input, destination)
                }
                installed = true
            }

            let cleared = previous.map { $0.clearingCachedFormat(format) }
            let removed = Set(cleared.filter { !$0.formats.values.contains(where: \.cached) }.map(\.inShelfId))
            let retained = cleared.filter { !removed.contains($0.inShelfId) }
            let preparedBook: CalibreBook
            do {
                try checkCancellation(cancelled)
                guard try FileVersion(destination) == version else { throw ImportError.fileOpFail }
                preparedBook = makeBook(try book(sourceID, scope: scope), id: sourceID, scope: scope,
                                        destination: destination, format: format, version: version)
                try repository.commitLocalBookFiles(scope: scope.storage, saving: [preparedBook] + retained, deleting: removed, cancelled: cancelled)
            } catch {
                if installed, let workspace {
                    if let backup {
                        keepBackup = !restore(backup, to: destination)
                    } else {
                        do { try files.move(destination, workspace.appendingPathComponent("uncommitted")) }
                        catch { keepBackup = true }
                    }
                }
                if keepBackup { throw ImportError.recoveryRequired }
                throw (error as? ImportError) ?? ImportError.loadMetaFail
            }

            if request.doMove && !sameFile {
                do { try files.remove(source) }
                catch {
                    logger.error("The import committed, but the source could not be removed")
                    result.cleanupPending = true
                }
            }
            let cleaned = cleanWorkspace(workspace)
            result.cleanupPending = result.cleanupPending || !cleaned
            let publication = Publication(
                operationID: request.id, shelfID: preparedBook.inShelfId, format: format,
                filename: destination.lastPathComponent, fallbackTitle: preparedBook.title,
                url: destination, version: version, recordVersion: preparedBook.lastSynced,
                coverURL: preparedBook.coverURL
            )
            return ImportOutcome(info: result, changes: Changes(savedBooks: [preparedBook] + retained, removedIDs: removed),
                                 publication: publication)
        } catch {
            let failure = error as? ImportError ?? .fileOpFail
            if failure != .destConflict && failure != .cancelled {
                logger.error("Local import failed with \(failure.rawValue, privacy: .public)")
            }
            if keepBackup { result.recoveryFolder = backup == nil ? nil : workspace?.lastPathComponent }
            else { result.cleanupPending = !cleanWorkspace(workspace) }
            if failure != .destConflict { result.bookId = nil }
            return ImportOutcome(info: result.with(error: failure))
        }
    }

    private func book(_ id: Int32, scope: Scope) throws -> CalibreBook? {
        try repository.localFileBook(scope: scope.storage, id: CalibreBook.identity(library: scope.library, bookId: id))
    }

    private func makeBook(_ existing: CalibreBook?, id: Int32, scope: Scope,
                          destination: URL, format: Format, version: FileVersion) -> CalibreBook {
        var book = existing ?? CalibreBook(id: id, library: scope.library)
        book.title = destination.deletingPathExtension().lastPathComponent
        book.lastModified = Date()
        book.lastSynced = book.lastModified
        book.timestamp = max(book.timestamp, version.modified)
        book.formats[format.rawValue] = FormatInfo(filename: destination.lastPathComponent,
                                                  serverSize: version.size, serverMTime: version.modified,
                                                  cached: true, cacheSize: version.size, cacheMTime: version.modified)
        book.inShelf = true
        return book
    }

    private func makeWorkspace(near destination: URL, id: UUID = UUID()) throws -> URL {
        let folder = destination.deletingLastPathComponent().appendingPathComponent(".dsreader-file-\(id)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        return folder
    }

    private func restore(_ backup: URL, to destination: URL) -> Bool {
        do {
            try files.replace(backup, destination)
            return true
        } catch {
            logger.error("Could not restore local book file. Recovery folder: \(backup.deletingLastPathComponent().lastPathComponent, privacy: .public)")
            return false
        }
    }

    private func cleanWorkspace(_ workspace: URL?) -> Bool {
        guard let workspace else { return true }
        do {
            try files.remove(workspace)
            return true
        } catch {
            logger.error("Could not clean local file workspace: \(workspace.lastPathComponent, privacy: .public)")
            return false
        }
    }

    private func checkCancellation(_ cancelled: () -> Bool) throws {
        if cancelled() { throw ImportError.cancelled }
    }
}

extension LocalBookImportCoordinator {
    private func removeFiles(bookID: String, format: Format?, scope: Scope, cancelled: () -> Bool) -> RemovalOutcome {
        var outcome = RemovalOutcome(result: .committed())
        do {
            guard let book = try repository.localFileBook(scope: scope.storage, id: bookID) else { return outcome }
            let formats = if let format { [format] } else {
                book.formats.compactMap { $0.value.cached ? Format(rawValue: $0.key) : nil }
            }
            for format in formats {
                try checkCancellation(cancelled)
                guard let current = try repository.localFileBook(scope: scope.storage, id: bookID) else { break }
                guard let filename = current.formats[format.rawValue]?.filename else {
                    outcome.result = .fileFailed
                    break
                }
                let url = scope.directory.appendingPathComponent(filename)
                let change = removeFile(url, book: current, format: format, scope: scope, cancelled: cancelled)
                outcome.changes.savedBooks = change.changes.savedBooks
                outcome.changes.removedIDs.formUnion(change.changes.removedIDs)
                outcome.changes.replacedPaths.formUnion(change.changes.replacedPaths)
                if !change.result.succeeded || change.result.cleanupPending { outcome.result = change.result }
                if !change.result.succeeded { break }
            }
        } catch {
            outcome.result = .storageFailed
        }
        return outcome
    }

    private func removeFile(_ url: URL, book: CalibreBook, format: Format,
                            scope: Scope, cancelled: () -> Bool) -> RemovalOutcome {
        var workspace: URL?
        var backup: URL?
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let folder = try makeWorkspace(near: url)
                workspace = folder
                let saved = folder.appendingPathComponent("previous")
                try files.copy(url, saved)
                backup = saved
                try checkCancellation(cancelled)
                try files.remove(url)
            }
        } catch {
            if !FileManager.default.fileExists(atPath: url.path), let backup, !restore(backup, to: url) {
                return RemovalOutcome(result: .recoveryRequired(workspace?.lastPathComponent))
            }
            _ = cleanWorkspace(workspace)
            return RemovalOutcome(result: .fileFailed)
        }

        let updated = book.clearingCachedFormat(format)
        let deleted = !updated.formats.values.contains(where: \.cached)
        let changes = Changes(savedBooks: deleted ? [] : [updated], removedIDs: deleted ? [book.inShelfId] : [],
                              replacedPaths: [url])
        do {
            try checkCancellation(cancelled)
            try repository.commitLocalBookFiles(scope: scope.storage, saving: changes.savedBooks, deleting: changes.removedIDs, cancelled: cancelled)
        } catch {
            if let backup, !restore(backup, to: url) {
                return RemovalOutcome(result: .recoveryRequired(workspace?.lastPathComponent))
            }
            _ = cleanWorkspace(workspace)
            return RemovalOutcome(result: .storageFailed)
        }
        return RemovalOutcome(result: .committed(cleanupPending: !cleanWorkspace(workspace)),
                              changes: changes)
    }

    private struct ScannedFile {
        let url: URL
        let filename: String
        let format: Format
        let version: FileVersion
    }

    private func scanFiles(scope: Scope, cancelled: () -> Bool) -> (changes: Changes, publications: [Publication]) {
        var changes = Changes()
        var publications = [Publication]()
        let directory = scope.directory.standardizedFileURL
        var enumerationFailed = false
        guard !cancelled(), let paths = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey], errorHandler: { _, _ in
                enumerationFailed = true
                return false
            }
        ) else { return (changes, publications) }

        var inventory = [Int32: [Format: [ScannedFile]]]()
        var claimedPaths = Set<String>()
        var uncertainPaths = Set<String>()
        for case let url as URL in paths {
            if cancelled() { return (Changes(), []) }
            if url.lastPathComponent.hasPrefix(".dsreader-file-") {
                paths.skipDescendants()
                continue
            }
            guard let format = Format(rawValue: url.pathExtension.uppercased()), format != .UNKNOWN else { continue }
            let filename = String(url.standardizedFileURL.path.dropFirst(directory.path.count + 1))
            guard let version = try? FileVersion(url), let id = localBookID(url),
                  (try? FileVersion(url)) == version else {
                uncertainPaths.insert(filename)
                continue
            }
            let file = ScannedFile(url: url, filename: filename, format: format, version: version)
            inventory[id, default: [:]][format, default: []].append(file)
            claimedPaths.insert(filename)
        }
        guard !enumerationFailed else { return (Changes(), []) }

        do {
            let existingBooks = try repository.localFileBooks(scope: scope.storage)
            let existingByID = Dictionary(uniqueKeysWithValues: existingBooks.map { ($0.id, $0) })
            for (id, formats) in inventory {
                try checkCancellation(cancelled)
                let current = existingByID[id]
                var found = current ?? CalibreBook(id: id, library: scope.library)
                var changed = current?.inShelf != true
                var updatedFiles = [ScannedFile]()
                for format in Format.allCases {
                    guard let candidates = formats[format],
                          let first = candidates.min(by: { $0.filename < $1.filename }) else { continue }
                    let previous = found.formats[format.rawValue]
                    // Keep the recorded path only if the scan proved it contains this book.
                    let chosen = candidates.first { $0.filename == previous?.filename } ?? first
                    guard previous?.filename != chosen.filename || previous?.cached != true
                          || previous?.cacheSize != chosen.version.size || previous?.cacheMTime != chosen.version.modified
                    else { continue }
                    if let name = previous?.filename {
                        changes.replacedPaths.insert(directory.appendingPathComponent(name))
                    }
                    changes.replacedPaths.insert(chosen.url)
                    var info = previous ?? FormatInfo(serverSize: 0, serverMTime: .distantPast,
                                                      cached: false, cacheSize: 0, cacheMTime: .distantPast)
                    info.filename = chosen.filename
                    info.serverSize = chosen.version.size
                    info.serverMTime = chosen.version.modified
                    info.cached = true
                    info.cacheSize = chosen.version.size
                    info.cacheMTime = chosen.version.modified
                    found.formats[format.rawValue] = info
                    found.timestamp = max(found.timestamp, chosen.version.modified)
                    updatedFiles.append(chosen)
                    changed = true
                }
                for format in Format.allCases where formats[format] == nil {
                    guard let info = found.formats[format.rawValue],
                          let name = info.filename, !uncertainPaths.contains(name) else { continue }
                    let claimed = claimedPaths.contains(name)
                    guard info.cached || claimed else { continue }
                    changes.replacedPaths.insert(directory.appendingPathComponent(name))
                    found = found.clearingCachedFormat(format)
                    if claimed { found.formats[format.rawValue]?.filename = nil }
                    changed = true
                }
                guard changed else { continue }
                found.inShelf = true
                found.lastModified = Date()
                found.lastSynced = found.lastModified
                if current == nil, let first = updatedFiles.first {
                    found.title = first.url.deletingPathExtension().lastPathComponent
                }
                changes.savedBooks.append(found)
                if let first = updatedFiles.first {
                    // A changed binding retires the old parser. Replace only a filename fallback.
                    let previousFilename = current?.formats[first.format.rawValue]?.filename
                    let previousFallback = previousFilename.map {
                        URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent
                    }
                    let mayReplaceTitle = current == nil || current?.title == previousFallback
                    publications.append(Publication(
                        operationID: UUID(), shelfID: found.inShelfId, format: first.format,
                        filename: first.filename, fallbackTitle: mayReplaceTitle ? found.title : nil,
                        url: first.url, version: first.version, recordVersion: found.lastSynced,
                        coverURL: found.coverURL
                    ))
                }
            }

            var unshelved = [CalibreBook]()
            var displaced = Set<String>()
            for var book in existingBooks where inventory[book.id] == nil {
                try checkCancellation(cancelled)
                guard !book.formats.values.contains(where: { $0.filename.map(uncertainPaths.contains) == true }) else {
                    continue
                }
                let claimed = book.formats.values.contains { info in
                    guard let name = info.filename else { return false }
                    return claimedPaths.contains(name)
                }
                guard claimed || book.inShelf else { continue }
                changes.removedIDs.insert(book.inShelfId)
                if claimed { displaced.insert(book.inShelfId) }
                else {
                    book.inShelf = false
                    unshelved.append(book)
                }
            }

            if !changes.savedBooks.isEmpty || !changes.removedIDs.isEmpty {
                try repository.commitLocalBookFiles(scope: scope.storage, saving: changes.savedBooks + unshelved,
                                                    deleting: displaced, cancelled: cancelled)
            }
        } catch {
            logger.debug("Could not reconcile local library files")
            return (Changes(), [])
        }
        return (changes, publications)
    }

    @MainActor
    private func startEnrichment(_ publication: Publication, scope: Scope, publish: @escaping Publish,
                                 coverCache: BookCoverCaching?) {
        retireEnrichments(bookIDs: [publication.shelfID], paths: [publication.url], coverCache: coverCache)
        if let url = publication.coverURL { coverCache?.removeCover(for: url) }
        let loader = loadMetadata
        let task = Task.detached(priority: .utility) { [weak self, weak coverCache] in
            let metadata = try? await loader(publication.url)
            await self?.finishEnrichment(metadata, publication: publication, scope: scope,
                                         publish: publish, coverCache: coverCache)
        }
        let observers = [
            observeScope(scope.databaseChanges(), scope: scope, publication: publication),
            observeScope(scope.libraryChanges(), scope: scope, publication: publication),
            observeScope(scope.serverChanges(), scope: scope, publication: publication)
        ]
        enrichments[publication.shelfID] = Enrichment(publication: publication, task: task, scopeObservers: observers, scope: scope)
    }

    @MainActor
    private func observeScope<Value>(_ events: AsyncStream<Value>, scope: Scope, publication: Publication) -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            for await _ in events {
                guard !Task.isCancelled else { return }
                if !scope.isCurrent() {
                    self?.retire(publication)
                    return
                }
            }
        }
    }

    @MainActor
    private func retireEnrichments(bookIDs: Set<String>, paths: Set<URL>, coverCache: BookCoverCaching?) {
        let retired = enrichments.values.filter { bookIDs.contains($0.publication.shelfID) || paths.contains($0.publication.url) }
        for enrichment in retired {
            if let url = enrichment.publication.coverURL { coverCache?.removeCover(for: url) }
            retire(enrichment.publication)
        }
    }

    @MainActor
    private func retire(_ publication: Publication) {
        guard let current = enrichments[publication.shelfID],
              current.publication.operationID == publication.operationID else { return }
        enrichments.removeValue(forKey: publication.shelfID)
        current.task.cancel()
        current.scopeObservers.forEach { $0.cancel() }
    }

    @MainActor
    private func finishEnrichment(_ metadata: LocalPublicationMetadata?, publication: Publication, scope: Scope,
                                  publish: @escaping Publish, coverCache: BookCoverCaching?) async {
        guard enrichments[publication.shelfID]?.publication.operationID == publication.operationID else { return }
        guard let metadata, !Task.isCancelled, scope.isCurrent() else {
            retire(publication)
            return
        }
        await enqueue(scope: scope, isCurrent: { [self] in
            enrichments[publication.shelfID]?.publication.operationID == publication.operationID
        }, work: { [self] cancelled in
            guard !cancelled(), (try? FileVersion(publication.url)) == publication.version else { return nil as CalibreBook? }
            do {
                return try repository.mergeLocalPublication(scope: scope.storage, id: publication.shelfID,
                                                            format: publication.format, filename: publication.filename,
                                                            version: publication.recordVersion, fallbackTitle: publication.fallbackTitle,
                                                            title: metadata.title, cancelled: cancelled)
            } catch {
                logger.debug("Could not save local publication metadata")
                return nil
            }
        }, finish: { [self] book in
            guard enrichments[publication.shelfID]?.publication.operationID == publication.operationID else { return }
            defer { retire(publication) }
            guard scope.isCurrent(), let book else { return }
            if let cover = metadata.cover, let url = publication.coverURL {
                coverCache?.storeCoverData(cover, for: url)
            }
            publish(Changes(savedBooks: [book]))
        })
    }
}
