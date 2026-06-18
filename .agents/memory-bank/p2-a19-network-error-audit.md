# P2 A19 Audit: Unified Network Error Handling Gaps

## Background

P1d-A04 (completed 2026-06-17) introduced `CalibreAPIError` in
`Network/CalibreAPIError.swift` and refactored `CalibreServerService` into a
shared core plus 5 domain extensions (`+LibrarySync`, `+Metadata`,
`+Discovery`, `+ReadingPosition`, `+Annotations`). Shared helpers
(`validatedData`, `validatedDataPublisher`, `makeJSONRequest`,
`makeEndpointURL`) now centralize HTTP status validation, transport error
mapping, and typed payload decoding.

However, the migration is **incomplete**. This audit (2026-06-18) catalogues
every remaining gap where network code bypasses `CalibreAPIError`, swallows
errors silently, uses raw `URLError`/`NSError`, or relies on `print` instead
of structured logging.

## Gap Inventory by Priority

### P0 — Data corruption / silent total failure

| # | Location | Anti-pattern | Risk |
|---|----------|--------------|------|
| 1 | `LibraryCategoryService.swift:52` | `session.data(from:)` with no HTTP status check; `_` discards response | 404 HTML page fed to decoder as if valid; raw `DecodingError` thrown instead of `CalibreAPIError` |
| 2 | `CalibreServerService+Metadata.swift:330` | `.replaceError(with: CalibreBookEntry())` on `Never` publisher | Network/decode failure yields empty `CalibreBookEntry()` that caller may write to Realm, wiping existing metadata |
| 3 | `DSReaderHelperConnector.swift:113,149,185` | 3 fire-and-forget `Bool` methods (`addToShelf`, `removeFromShelf`, `updateReadingProgress`) with empty error branches and empty `DispatchQueue.main.async {}` blocks | Goodreads shelf/progress sync silently broken; returns `true` on `task.resume()`, not on success |

### P1 — Error mis-attribution / high-volume noise

| # | Location | Anti-pattern | Risk |
|---|----------|--------------|------|
| 4 | `LibrarySearchService.swift:86` | `session.data(from:)` bypasses `validatedData`; manual HTTP check; throws `SearchError.network(String)` | Network failures mis-attributed as `SearchError.database`; 401 reported as generic "invalid response code" |
| 5 | `MDictViewEdit.swift:98` | `URLSession.shared.data(from:)` in view; empty `catch {}` | Dictionary lookup failures invisible to user |
| 6 | `ImageRequest.swift:21` | `print("AuthPlugin modified url ...")` on every Kingfisher image request | High-volume debug noise since 2021; fires on every cover/thumbnail load |
| 7 | `CalibreServerService.swift:321` | `print(...)` in `CalibreServerTaskDelegate` auth challenge | Fires on every authenticated request |
| 8 | `CalibreServerService+Annotations.swift:42` | `.mapError(\.asURLError)` downgrades `CalibreAPIError` to `URLError` | Structured error cases (`.httpStatus`, `.authFailed`, `.decoding`) lost |
| 9 | `CalibreServerService+LibrarySync.swift:217` | Same `.mapError(\.asURLError)` pattern | Same loss |
| 10 | `CalibreServerService+ReadingPosition.swift:24` | Same `.mapError(\.asURLError)` pattern | Same loss |
| 11 | `CalibreServerService+Metadata.swift:338` | Same `.mapError(\.asURLError)` pattern | Same loss |
| 12 | `DSReaderHelperConnector.swift:201` | `print(string)` for Goodreads progress response body | Only "handling" of response is to print it |
| 13 | `BookDownloadManager.swift:268` | `print("file error: ...")` in download delegate | File-system error only visible via print |

### P2 — Silent failures / compatibility debt

| # | Location | Anti-pattern | Risk |
|---|----------|--------------|------|
| 14 | `CalibreServerService+Annotations.swift:89-90` | Empty `catch {}` in async `updateAnnotationByTask` | Error logged as "Unknown"; caller gets unchanged task |
| 15 | `CalibreServerService+ReadingPosition.swift:60-61` | Empty `catch {}` in async `setLastReadPositionByTask` | Same pattern |
| 16 | `CalibreServerService+Annotations.swift:111` | `.replaceError(with: task)` on `Never` publisher | Upload failure re-emits original task; no signal to caller |
| 17 | `CalibreServerService+ReadingPosition.swift:82` | `.replaceError(with: task)` on `Never` publisher | Same pattern |
| 18 | `CalibreServerService+Metadata.swift:12-77` | Optional completion `((CalibreBook) -> Void)?` with no error param | Caller can't distinguish success from failure |
| 19 | `CalibreServerService+Metadata.swift:202-251` | Optional completion `((Data?) -> Void)?` with nullable Data | Silent no-op on failure; user sees "Without TOC" |
| 20 | `CalibreServerService+Metadata.swift:253-290` | `updateMetadata` returns `Int` (0/-1); callers ignore it | Fire-and-forget metadata update |
| 21 | `CalibreServerService+LibrarySync.swift:104-155` | `syncLibraryPublisher` returns `Never`; errors stringified into `errmsg` | Structured `CalibreAPIError` lost |
| 22 | `CalibreServerService+LibrarySync.swift:257-281` | `getLibraryCategoriesPublisher` `.catch { _ in Just(resultPrev) }` | Error entirely discarded; `errmsg` not even set |
| 23 | `CalibreServerService+Discovery.swift:96-133` | `probeServerReachabilityNew` returns `Never`; errors folded into `errorMsg` | Downstream can't differentiate auth vs transport vs HTTP |
| 24 | `CalibreServerService+Annotations.swift:22,39` | `try? JSONDecoder().decode(...)` | Decode failures silently dropped |
| 25 | `CalibreServerService+LibrarySync.swift:286,304` | `try?` on JSONSerialization/JSONDecoder in `applyBooksMetadataPayload` | JSON failures hidden from callers |
| 26 | `CalibreServerService+Metadata.swift:167,180,184,198` | `try?` on encode/decode in `handleLibraryBookOne` | Partial metadata written to Realm on failure |
| 27 | `CalibreServerService+Metadata.swift:79-136` | `handleLibraryBookOne` `catch { return nil }` then caller fabricates `NSError` | Real decode error discarded; fake `NSError` substituted |
| 28 | `CalibreServerService+ReadingPosition.swift:29,36` | `try?` in `buildSetLastReadPositionTask` | URL/encode failure returns nil |
| 29 | `CalibreServerService+Annotations.swift:47,57,58,61,62,66` | `try?` chain in `buildUpdateAnnotationsTask` | Any failure silently skips upload |
| 30 | `CalibreBookManager.swift:231,257,260` | `let _ = connector.addToShelf(...)` discards `Bool` | Goodreads sync failures invisible |
| 31 | `ReadingSessionManager.swift:196,226` | `_ = connector.updateReadingProgress(...)` | Reading-progress sync silently fails |
| 32 | `CalibreLibraryManager.swift:253-255` | `syncLibraryPublisher` failure silently no-ops | Persistent server failure looks like "library hasn't changed" |
| 33 | `ModelData.swift:950-982` | `registerSyncServerHelperConfigCancellable` empty completion handler | `.failure` completions silently dropped |
| 34 | `BookDownloadManager.swift:119-195` | `startDownload` returns `Bool`; 5 indistinguishable `return false` cases | Caller can't tell why download failed |
| 35 | `Utils.swift:92` | `URLSession.shared.dataTaskPublisher` with `.replaceError(with: nil)` | Image load failures show placeholder forever, no retry |
| 36 | `SupportInfoViewModel.swift:59,138` | Ad-hoc `NSError(domain: "YABRError", ...)` | Undermines unified error contract |

### Cross-cutting

| # | Issue | Details |
|---|-------|---------|
| 37 | Two parallel error taxonomies | `CalibreAPIError` (Network) and `SearchError` (UnifiedSearchModels.swift:89) both model network failures. `LibrarySearchService` converts `CalibreAPIError`-eligible failures into `SearchError.network(String)`, losing structured cases. `UnifiedSearchService` re-wraps unknown errors into `SearchError.unknown`. |
| 38 | `Downloader.swift` (whole file) | Uses raw `URLError`; appears to be dead code (no callers found). If revived, needs migration. |
| 39 | `CalibreLibraryManager.swift:71,105,137` | `print` statements in library bootstrap |
| 40 | `CalibreBookManager.swift:137,288,373,432,491` | `print` statements in shelf/cache/local-import paths |

## Files That Bypass `validatedData` / `validatedDataPublisher` / `makeJSONRequest`

- `LibrarySearchService.swift:86` — `session.data(from:)` (manual HTTP check, `SearchError`)
- `LibraryCategoryService.swift:52` — `session.data(from:)` (no HTTP check, raw `DecodingError`)
- `DSReaderHelperConnector.swift:85` — `urlSession.dataTaskPublisher(for:)` (no HTTP check, `URLError`)
- `DSReaderHelperConnector.swift:97` — `urlSession.data(from:)` (no HTTP check, raw errors)
- `DSReaderHelperConnector.swift:113,149,185` — `urlSession.dataTask(with:)` (no HTTP check, `Bool`, empty error branches)
- `BookDownloadManager.swift:155` — `downloadSession.downloadTask(with:)` (no HTTP check, `Bool`)
- `BookDownloadManager.swift:100` — `downloadSession.downloadTask(withResumeData:)` (same)
- `MDictViewEdit.swift:98` — `URLSession.shared.data(from:)` (view-layer, no auth, empty catch)
- `Utils.swift:92` — `URLSession.shared.dataTaskPublisher(for:)` (view-layer, no auth, `replaceError(with: nil)`)
- `Downloader.swift:65` — `session.downloadTask(with:)` (dead code, `URLError`)

## Recommended Remediation Phases

### Phase 1 — P0 data-corruption fixes (~0.5 day)
- Fix `LibraryCategoryService.swift:52`: route through `validatedData(from:server:)`
- Fix `CalibreServerService+Metadata.swift:330`: change `replaceError(with: CalibreBookEntry())` to `replaceError(with: nil)` and make return type `Optional<CalibreBookEntry>`
- Fix `DSReaderHelperConnector.swift:113,149,185`: route through `validatedData` or at minimum add HTTP status check and error logging

### Phase 2 — P1 error mis-attribution + print noise (~0.5 day)
- Fix `LibrarySearchService.swift:86`: route through `validatedData`
- Remove `print` from `ImageRequest.swift:21` and `CalibreServerService.swift:321`
- Migrate 4 `.mapError(\.asURLError)` publishers to `CalibreAPIError` failure type
- Remove `print` from `DSReaderHelperConnector.swift:201` and `BookDownloadManager.swift:268`

### Phase 3 — P2 silent failures + compatibility debt (~1 day)
- Replace empty `catch {}` with `CalibreAPIError` logging
- Migrate optional completions to `Result` or async throws
- Replace `Bool`-returning download methods with `Result` or throws
- Consolidate `SearchError` with `CalibreAPIError` (make `SearchError` wrap `CalibreAPIError`)
- Remove `print` from manager files

### Phase 4 — View-layer cleanup (~0.25 day)
- Fix `MDictViewEdit.swift:98`: use `CalibreServerService.urlSession` with HTTP check
- Fix `Utils.swift:92`: route through `CalibreServerService` or remove if dead
- Replace ad-hoc `NSError` in `SupportInfoViewModel.swift` with typed error

## Reference

- `CalibreAPIError` definition: `Network/CalibreAPIError.swift` (97 lines, 10 cases)
- Shared helpers: `Network/CalibreServerService.swift` (`validatedData`, `validatedDataPublisher`, `makeJSONRequest`, `makeEndpointURL`)
- P1d-A04 implementation notes: `.agents/memory-bank/refactoring-context.md` lines 71-177
- Tests: `CalibreServerServiceTests` (2 cases: auth error mapping, 4xx payload compatibility)
