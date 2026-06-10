//
//  UnifiedSearchMergeService.swift
//  YetAnotherEBookReader
//
//  Created by Antigravity on 2026-06-10.
//

import Foundation
import Collections

class UnifiedSearchMergeService {
    
    /// Merges book lists from multiple libraries in memory using a Min-Max Heap.
    /// - Parameters:
    ///   - libraryResults: Map of library ID to their current retrieved search result.
    ///   - currentResult: The existing `UnifiedSearchResult` containing current offsets, total numbers, merged books, etc.
    /// - Returns: An updated `UnifiedSearchResult` with newly merged books and updated offsets.
    func merge(
        libraryResults: [String: LibrarySourceSearchResult],
        currentResult: UnifiedSearchResult
    ) -> UnifiedSearchResult {
        var updatedResult = currentResult
        
        // Initialize Heap. Apple's Collections.Heap is double-ended, supporting min/max extraction.
        var heap = Heap<MergeHead>()
        
        // Resolve empty libraryIds to all libraries present in libraryResults
        var targetLibraryIds = updatedResult.libraryIds
        if targetLibraryIds.isEmpty {
            targetLibraryIds = Set(libraryResults.keys)
        }
        
        // Populate Heap with the head element of each library
        for libraryId in targetLibraryIds {
            let offsetEntry = updatedResult.unifiedOffsets[libraryId] ?? MergeOffset()
            
            // If the library is already fully consumed or cut off, skip it
            if offsetEntry.beenConsumed || offsetEntry.beenCutOff {
                continue
            }
            
            guard let libraryResult = libraryResults[libraryId],
                  offsetEntry.offset < libraryResult.books.count else {
                continue
            }
            
            let head = MergeHead(
                libraryId: libraryId,
                books: libraryResult.books,
                offset: offsetEntry.offset,
                sortBy: updatedResult.sortBy
            )
            heap.insert(head)
        }
        
        while updatedResult.books.count < updatedResult.limitNumber {
            guard var head = updatedResult.sortAsc ? heap.popMin() : heap.popMax() else {
                break // Heap is empty, no more elements to merge
            }
            
            // Append the book
            updatedResult.books.append(head.currentBook)
            
            // Update the offset in unifiedOffsets
            var offsetEntry = updatedResult.unifiedOffsets[head.libraryId] ?? MergeOffset()
            offsetEntry.offset += 1
            
            let libraryResult = libraryResults[head.libraryId]
            let totalCountForLibrary = libraryResult?.totalNumber ?? 0
            let loadedCountForLibrary = libraryResult?.books.count ?? 0
            
            // Determine if consumed or cut off
            if offsetEntry.offset >= loadedCountForLibrary {
                if loadedCountForLibrary < totalCountForLibrary {
                    offsetEntry.beenCutOff = true
                } else {
                    offsetEntry.beenConsumed = true
                }
            } else {
                // We still have local elements loaded in the books array
                if head.advance() {
                    heap.insert(head)
                }
            }
            
            updatedResult.unifiedOffsets[head.libraryId] = offsetEntry
        }
        
        // Re-calculate the totalNumber across all libraries
        updatedResult.totalNumber = libraryResults.values.reduce(0) { $0 + $1.totalNumber }
        
        return updatedResult
    }
}
