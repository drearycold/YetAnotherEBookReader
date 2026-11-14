//
//  BookMetadataSyncWorker.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026-06-28.
//

import Foundation
import OSLog

final class BookMetadataSyncWorker {
    private let queue = DispatchQueue(label: "book-metadata-sync", qos: .userInitiated)
    private let readingPositionRepository: ReadingPositionRepositoryProtocol
    private let annotationRepository: AnnotationRepositoryProtocol
    private let logger = Logger(subsystem: "YetAnotherEBookReader", category: "BookMetadataSyncWorker")
    
    struct SyncJob: Sendable {
        let book: CalibreBook
        let format: Format
        let entry: CalibreBookAnnotationsResult
        let needUpload: Bool
    }
    
    struct SyncOutcome: Sendable {
        struct UploadPositions: Sendable {
            let book: CalibreBook
            let format: Format
            let entries: [CalibreBookLastReadPositionEntry]
        }
        
        struct UploadAnnotations: Sendable {
            let book: CalibreBook
            let format: Format
            let highlights: [CalibreBookAnnotationHighlightEntry]
            let bookmarks: [CalibreBookAnnotationBookmarkEntry]
        }
        
        var positionsToUpload: [UploadPositions] = []
        var annotationsToUpload: [UploadAnnotations] = []
        var changedPositionShelfIDs = Set<String>()
    }
    
    init(
        readingPositionRepository: ReadingPositionRepositoryProtocol,
        annotationRepository: AnnotationRepositoryProtocol
    ) {
        self.readingPositionRepository = readingPositionRepository
        self.annotationRepository = annotationRepository
    }
    
    func executeSync(jobs: [SyncJob], refresh: (scope: BookMetadataRefreshScope, repository: BookRepositoryProtocol)? = nil) async -> SyncOutcome {
        let readingPositionRepository = self.readingPositionRepository
        let annotationRepository = self.annotationRepository
        let logger = self.logger

        let lifetime = CacheLibraryLifetime()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                queue.async {
                    var outcome = SyncOutcome()
                    for job in jobs {
                        guard (try? lifetime.checkCurrent()) != nil else { break }
                        var changedPositionShelfID: String?
                        do {
                            let batch: SyncOutcome
                            if let refresh {
                                batch = try refresh.repository.withMetadataRefreshBook(refresh.scope, bookID: job.book.id) { book in
                                    try lifetime.checkCurrent()
                                    return try Self.merge(job: job, current: book, configuration: refresh.scope.database,
                                                          positions: readingPositionRepository, annotations: annotationRepository,
                                                          changedPositionShelfID: &changedPositionShelfID)
                                }
                            } else {
                                batch = try Self.merge(job: job, current: job.book, configuration: nil,
                                                       positions: readingPositionRepository, annotations: annotationRepository,
                                                       changedPositionShelfID: &changedPositionShelfID)
                            }
                            outcome.positionsToUpload.append(contentsOf: batch.positionsToUpload)
                            outcome.annotationsToUpload.append(contentsOf: batch.annotationsToUpload)
                        } catch CacheContextError.superseded {
                            continue
                        } catch {
                            logger.error("Could not merge remote positions or annotations: \(error.localizedDescription)")
                        }
                        // Position writes are committed in the server's Realm even
                        // if the following annotation transaction fails.
                        if let changedPositionShelfID { outcome.changedPositionShelfIDs.insert(changedPositionShelfID) }
                    }
                    continuation.resume(returning: outcome)
                }
            }
        } onCancel: {
            lifetime.invalidate()
        }
    }

    private static func merge(job: SyncJob, current book: CalibreBook, configuration: DatabaseService.CacheConfiguration?,
                              positions: ReadingPositionRepositoryProtocol, annotations: AnnotationRepositoryProtocol,
                              changedPositionShelfID: inout String?) throws -> SyncOutcome {
        var needsUpload = job.needUpload
        if configuration != nil {
            guard let format = book.formats[job.format.rawValue] else { return .init() }
            needsUpload = needsUpload && book.inShelf && format.cached
        }
        let pending = try positions.mergeRemotePositions(entries: job.entry.last_read_positions, for: book)
        if pending.didChange, book.inShelf { changedPositionShelfID = book.inShelfId }
        var result = SyncOutcome()
        if needsUpload, !pending.entriesToUpload.isEmpty {
            result.positionsToUpload.append(.init(book: book, format: job.format, entries: pending.entriesToUpload))
        }
        let entry = job.entry.annotations_map
        if needsUpload || entry.highlight?.isEmpty == false || entry.bookmark?.isEmpty == false {
            let merged = try annotations.mergeRemoteAnnotations(for: book, format: job.format, entry: entry,
                                                                configuration: configuration)
            if needsUpload, merged.needsUpload {
                result.annotationsToUpload.append(.init(book: book, format: job.format,
                                                        highlights: merged.highlights, bookmarks: merged.bookmarks))
            }
        }
        return result
    }
}
