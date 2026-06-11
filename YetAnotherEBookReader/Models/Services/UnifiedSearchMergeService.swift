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
        
        // Always reset the merged books and offsets to rebuild from scratch.
        // This ensures sorting correctness when new paginated data arrives asynchronously.
        updatedResult.books.removeAll()
        updatedResult.unifiedOffsets.removeAll()
        
        var heap = Heap<MergeHead>()
        
        var targetLibraryIds = updatedResult.libraryIds
        if targetLibraryIds.isEmpty {
            targetLibraryIds = Set(libraryResults.keys)
        }
        
        for libraryId in targetLibraryIds {
            // Initialize offsets for all target libraries
            updatedResult.unifiedOffsets[libraryId] = MergeOffset(beenCutOff: false, beenConsumed: false, offset: 0)
            
            guard let libraryResult = libraryResults[libraryId],
                  !libraryResult.books.isEmpty else {
                continue
            }
            
            let head = MergeHead(
                libraryId: libraryId,
                books: libraryResult.books,
                offset: 0,
                sortBy: updatedResult.sortBy
            )
            heap.insert(head)
        }
        
        while updatedResult.books.count < updatedResult.limitNumber {
            guard var head = updatedResult.sortAsc ? heap.popMin() : heap.popMax() else {
                break
            }
            
            updatedResult.books.append(head.currentBook)
            
            var offsetEntry = updatedResult.unifiedOffsets[head.libraryId] ?? MergeOffset()
            offsetEntry.offset += 1
            
            let libraryResult = libraryResults[head.libraryId]
            let totalCountForLibrary = libraryResult?.totalNumber ?? 0
            let loadedCountForLibrary = libraryResult?.books.count ?? 0
            
            if offsetEntry.offset >= loadedCountForLibrary {
                if loadedCountForLibrary < totalCountForLibrary {
                    offsetEntry.beenCutOff = true
                    updatedResult.unifiedOffsets[head.libraryId] = offsetEntry
                    // Stop merging immediately if we hit the boundary of a partially loaded library.
                    // Continuing would pull elements from other libraries that might actually sort AFTER
                    // the unloaded elements of this library, causing a UI snap when data arrives.
                    break
                } else {
                    offsetEntry.beenConsumed = true
                }
            } else {
                if head.advance() {
                    heap.insert(head)
                }
            }
            
            updatedResult.unifiedOffsets[head.libraryId] = offsetEntry
        }
        
        updatedResult.totalNumber = libraryResults.values.reduce(0) { $0 + $1.totalNumber }
        
        return updatedResult
    }
}
