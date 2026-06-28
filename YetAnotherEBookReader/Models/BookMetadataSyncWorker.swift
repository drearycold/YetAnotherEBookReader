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

    private func sharesStore(_ lhs: Realm, _ rhs: Realm) -> Bool {
        if let lhsURL = lhs.configuration.fileURL?.standardizedFileURL,
           let rhsURL = rhs.configuration.fileURL?.standardizedFileURL {
            return lhsURL == rhsURL
        }

        if let lhsIdentifier = lhs.configuration.inMemoryIdentifier,
           let rhsIdentifier = rhs.configuration.inMemoryIdentifier {
            return lhsIdentifier == rhsIdentifier
        }

        return false
    }
    
    func executeSync(jobs: [SyncJob]) async -> SyncOutcome {
        await withCheckedContinuation { continuation in
            queue.async {
                var outcome = SyncOutcome()
                for job in jobs {
                    let book = job.book
                    let format = job.format
                    let entry = job.entry
                    
                    var pendingPositions = [CalibreBookLastReadPositionEntry]()
                    var highlightPending = 0
                    var bookmarkPending = 0
                    
                    let remoteHighlights = entry.annotations_map.highlight ?? []
                    let remoteBookmarks = entry.annotations_map.bookmark ?? []
                    let shouldMergeAnnotations = job.needUpload || !remoteHighlights.isEmpty || !remoteBookmarks.isEmpty
                    
                    let positionRealm = self.readingPositionRepository.getRealm(forBookId: book.bookPrefId)
                    let annotationRealm = shouldMergeAnnotations ? self.annotationRepository.getRealm(forBookId: book.bookPrefId) : nil
                    
                    if let pRealm = positionRealm {
                        pendingPositions = self.readingPositionRepository.syncPositions(
                            entries: entry.last_read_positions,
                            forBookId: book.bookPrefId,
                            in: pRealm
                        )

                        if let aRealm = annotationRealm {
                            let annotationWriteRealm = self.sharesStore(pRealm, aRealm) ? pRealm : aRealm
                            highlightPending = self.annotationRepository.syncHighlights(
                                entries: remoteHighlights,
                                forBookId: book.bookPrefId,
                                in: annotationWriteRealm
                            )
                            bookmarkPending = self.annotationRepository.syncBookmarks(
                                entries: remoteBookmarks,
                                forBookId: book.bookPrefId,
                                in: annotationWriteRealm
                            )
                        }
                    } else {
                        // Fallback (e.g. mock repositories in tests where getRealm returns nil)
                        pendingPositions = self.readingPositionRepository.syncPositions(
                            entries: entry.last_read_positions,
                            forBookId: book.bookPrefId
                        )
                        if shouldMergeAnnotations {
                            highlightPending = self.annotationRepository.syncHighlights(
                                entries: remoteHighlights,
                                forBookId: book.bookPrefId
                            )
                            bookmarkPending = self.annotationRepository.syncBookmarks(
                                entries: remoteBookmarks,
                                forBookId: book.bookPrefId
                            )
                        }
                    }
                    
                    if job.needUpload && !pendingPositions.isEmpty {
                        outcome.positionsToUpload.append(
                            SyncOutcome.UploadPositions(
                                book: book,
                                format: format,
                                entries: pendingPositions
                            )
                        )
                    }
                    
                    if shouldMergeAnnotations && job.needUpload && (highlightPending > 0 || bookmarkPending > 0) {
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
                continuation.resume(returning: outcome)
            }
        }
    }
}
