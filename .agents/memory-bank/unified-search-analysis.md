# Unified Search Subsystem Analysis

## Date: 2026-06-06

## Core Discovery: 7-Stage Reactive Pipeline

The `CalibreUnifiedSearchObject` is generated through a 7-stage Combine-based reactive pipeline
within `CalibreLibrarySearchManager` (CalibreBrowser.swift, 2137 lines):

1. **Create/Find** — `retrieveUnifiedSearchObject()` (L1587-1639)
2. **Register Observer** — `registerCacheUnifiedSearchObject()` (L617-701) with 5-second delay
3. **Search Refresh** — `registerSearchRefreshReceiver()` (L778-818)
4. **Search Request** — `registerSearchRequestReceiver()` (L820-914), crosses 4 DispatchQueues
5. **Network/Realm Search** — `searchLibraryBooks()` (L2005-2134), HTTP or offline Realm
6. **Metadata Fetch** — `registerMetadataRequestReceiver()` (L916-1018)
7. **K-way Merge** — `mergeBookListsNew()` (L1658-1757), uses sorted array (should be heap)

## Key Data Models
- `CalibreLibrarySearchObject` — per-library search criteria + `sources: Map<serverUrl, ValueObject>`
- `CalibreLibrarySearchValueObject` — per-source results with `bookIds` and `books` lists
- `CalibreUnifiedSearchObject` — merged result with `unifiedOffsets`, `books`, `limitNumber`
- `CalibreUnifiedOffsets` — per-library merge state (offset, beenCutOff, beenConsumed)
- `CalibreUnifiedSearchRuntime` — non-persisted indexMap and notification token

## 6 Consumer Views
1. LibraryInfoBookListView (@ObservedRealmObject)
2. LibraryInfoBookListInfoView (@ObservedRealmObject)
3. LibraryInfoBookRow (@ObservedRealmObject)
4. LibraryInfoView.ViewModel (@Published)
5. SectionShelfController (dict)
6. YabrShelfDataModel.CategoryObject (optional)

## Critical Issues Found
1. K-way merge uses O(K·logK) sort instead of O(logK) heap
2. Merge runs inside Realm write transaction (long lock)
3. `fatalError` in production code (L1670)
4. `try!` scattered 20+ places
5. retrieveUnifiedSearchObject called from 3 different threads without synchronization
6. cutOff in one library aborts entire merge (L1744 `break`)

## Artifact
Full analysis: `unified_search_analysis.md`
