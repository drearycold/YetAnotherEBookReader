//
//  BookMetadataSyncWorker.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026-06-28.
//

import Foundation
import OSLog
import RealmSwift

final class BookMetadataSyncWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "book-metadata-sync", qos: .userInitiated)
    private let readingPositionRepository: ReadingPositionRepositoryProtocol
    private let annotationRepository: AnnotationRepositoryProtocol
    private let logger = Logger(subsystem: "io.github.drearycold.DSReader", category: "BookMetadataSyncWorker")
    
    struct SyncJob: Sendable {
        let book: CalibreBook
        let formatKey: String
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
    }
    
    init(
        readingPositionRepository: ReadingPositionRepositoryProtocol,
        annotationRepository: AnnotationRepositoryProtocol
    ) {
        self.readingPositionRepository = readingPositionRepository
        self.annotationRepository = annotationRepository
    }
    
    func executeSync(jobs: [SyncJob]) async -> SyncOutcome {
        await withCheckedContinuation { continuation in
            queue.async {
                var outcome = SyncOutcome()
                for job in jobs {
                    let book = job.book
                    let format = job.format
                    let entry = job.entry
                    
                    // 1. Sync Positions
                    let pendingPositions = self.readingPositionRepository.syncPositions(
                        entries: entry.last_read_positions,
                        forBookId: book.bookPrefId
                    )
                    
                    if job.needUpload && !pendingPositions.isEmpty {
                        outcome.positionsToUpload.append(
                            SyncOutcome.UploadPositions(
                                book: book,
                                format: format,
                                entries: pendingPositions
                            )
                        )
                    }
                    
                    // 2. Sync Annotations
                    let remoteHighlights = entry.annotations_map.highlight ?? []
                    let remoteBookmarks = entry.annotations_map.bookmark ?? []
                    
                    if !remoteHighlights.isEmpty || !remoteBookmarks.isEmpty {
                        // Always run sync for both highlights and bookmarks without short-circuiting
                        let highlightPending = self.annotationRepository.syncHighlights(
                            entries: remoteHighlights,
                            forBookId: book.bookPrefId
                        )
                        let bookmarkPending = self.annotationRepository.syncBookmarks(
                            entries: remoteBookmarks,
                            forBookId: book.bookPrefId
                        )
                        
                        if job.needUpload && (highlightPending > 0 || bookmarkPending > 0) {
                            let highlightsToUpload = self.annotationRepository.getHighlights(
                                forBookId: book.bookPrefId,
                                excludeRemoved: false
                            ).compactMap { $0.toCalibreBookAnnotationHighlightEntry() }
                            
                            let bookmarksToUpload = self.annotationRepository.getBookmarks(
                                forBookId: book.bookPrefId,
                                excludeRemoved: true
                            ).map { $0.toCalibreBookAnnotationBookmarkEntry() }
                            
                            outcome.annotationsToUpload.append(
                                SyncOutcome.UploadAnnotations(
                                    book: book,
                                    format: format,
                                    highlights: highlightsToUpload,
                                    bookmarks: bookmarksToUpload
                                )
                            )
                        }
                    }
                }
                continuation.resume(returning: outcome)
            }
        }
    }
}