# P2/A19 Network Error Handling Audit

## Status

- **Audit date:** 2026-06-19
- **Scope:** Calibre server networking, DSReader Helper calls, search/category
  services, download paths, and view-layer URLSession usage.
- **Remediation Status:** Fully completed and verified (2026-06-20). All stages (A19-S1 through A19-S9) have been implemented, tested, and cleared of whitespace issues, with zero test suite regressions (122 unit/UI tests passed).
- **Current baseline:** P1d-A04 introduced `CalibreAPIError` and the shared
  `CalibreServerService` helpers:
  - `makeEndpointURL(server:path:queryItems:)`
  - `makeJSONRequest(url:method:body:acceptEncoding:)`
  - `validatedData(from:server:timeout:qos:)`
  - `validatedData(for:server:timeout:qos:)`
  - `validatedDataPublisher(from:server:timeout:qos:)`
  - `validatedDataPublisher(for:server:timeout:qos:)`
- **Audit result:** The helper layer exists and is used in many high-value
  paths, but network error handling is still inconsistent. The remaining gaps
  are concentrated in category/search fetching, legacy Combine facades,
  DSReader Helper fire-and-forget calls, and compatibility APIs that collapse
  errors into `Bool`, `Never`, `nil`, or empty model values.

## Decision Rules

Use these rules when implementing A19 so the fix stays incremental and does not
turn into a broad network rewrite.

- Preserve existing facade methods unless the caller can be migrated in the same
  patch.
- New async APIs should be `async throws` and throw `CalibreAPIError` or a
  domain error that wraps `CalibreAPIError`.
- New Combine APIs should use `Failure == CalibreAPIError` unless the caller is
  still compatibility-only; in compatibility adapters, convert at the boundary.
- Do not use `replaceError(with:)` with a valid-looking domain object. Use
  optional payloads, a result wrapper, or a typed error.
- Do not use `URLError` as the app-level network error unless the API is truly
  URLSession-only and not Calibre-aware.
- Do not add new `print` logging in network, manager, or view-model code. Use
  `OSLog.Logger` or the existing `CalibreActivityLogger` for user/action
  relevant network failures.
- Treat local Realm/file URLs separately from HTTP URLs. Only HTTP paths should
  require HTTP status validation.

## Priority Fix List

### P0: Prevent Corrupt Or Misleading Data

These are the first A19 fixes because they can produce false success or write
bad data.

| ID | Location | Current behavior | Required fix | Acceptance |
|---|---|---|---|---|
| A19-01 | `Models/Services/LibraryCategoryService.swift:51-53` | Uses `session.data(from:)`, discards the response, and decodes any payload. A 401/404 HTML page becomes a `DecodingError` rather than a network error. | Route HTTP URLs through `CalibreServerService.validatedData(from:server:qos:)`; preserve file/local behavior if introduced later. | Add a test or mock path where a non-2xx response becomes `CalibreAPIError.httpStatus` and no category cache write occurs. |
| A19-02 | `Network/CalibreServerService+Metadata.swift:324-331` | `getMetadata(task:)` publishes `Never` and replaces any failure with `CalibreBookEntry()`. Callers can treat an empty entry as real metadata. | Change the internal path to publish `CalibreAPIError` or publish `(task, CalibreBookEntry?)`; keep a compatibility wrapper only if existing callers require `Never`. | Network/decode failure no longer creates a non-optional empty `CalibreBookEntry`. |
| A19-03 | `Network/DSReaderHelperConnector.swift:103-207` | `addToShelf`, `removeFromShelf`, and `updateReadingProgress` return `true` after `task.resume()`, not after server success. Error branches are empty. | Introduce `async throws` helper methods using validated HTTP response handling. Keep the current `Bool` methods as thin compatibility adapters only if needed. | Callers can observe failure; 4xx/5xx and transport failures are logged or surfaced. |

### P1: Preserve Error Meaning And Reduce High-Volume Noise

These fixes make failures diagnosable without large API churn.

| ID | Location | Current behavior | Required fix | Acceptance |
|---|---|---|---|---|
| A19-04 | `Models/Services/LibrarySearchService.swift:87-100` | Search HTTP fetch bypasses `validatedData`; 401/403/404 collapse into generic `SearchError.network("Server returned invalid response code.")`. | Fetch via `validatedData(from:server:)`, then wrap the resulting `CalibreAPIError` in `SearchError.networkError(CalibreAPIError)` or equivalent. | Auth, HTTP status, transport, and decode failures remain distinguishable at `UnifiedSearchService`. |
| A19-05 | `Network/CalibreServerService+Annotations.swift:29-43` | Publisher downgrades `CalibreAPIError` to `URLError`. | Prefer `AnyPublisher<CalibreBooksTask, CalibreAPIError>` internally; keep `URLError` facade only at old call sites. | Structured cases are preserved through the modern path. |
| A19-06 | `Network/CalibreServerService+LibrarySync.swift:203-218` | `getBooksMetadata` downgrades `CalibreAPIError` to `URLError`. | Same as A19-05. | Metadata list failures preserve auth/status/decode cases. |
| A19-07 | `Network/CalibreServerService+ReadingPosition.swift:12-25` | `getLastReadPosition` downgrades `CalibreAPIError` to `URLError`. | Same as A19-05. | Reading position fetch failures preserve structured errors. |
| A19-08 | `Network/CalibreServerService+Metadata.swift:335-339` | `getMetadataNew` downgrades `CalibreAPIError` to `URLError`. | Same as A19-05. | Modern metadata callers can observe `CalibreAPIError`. |
| A19-09 | `Network/ImageRequest.swift:21`, `Network/CalibreServerService.swift:321`, `Network/DSReaderHelperConnector.swift:201`, `Network/BookDownloadManager.swift:268` | Network paths print on every image/auth/helper/download event or failure. | Remove noisy prints or replace failure-only diagnostics with `Logger`. | Normal browsing/auth/image loads do not spam stdout. |
| A19-10 | `Views/DictView/MDictViewEdit.swift:98` | View directly uses `URLSession.shared.data(from:)` and has an empty `catch`. | Move lookup networking into a service/helper that validates HTTP status and reports failure to the view model/UI state. | Dictionary lookup failure is observable and not silently swallowed. |

### P2: Compatibility Debt And Silent Failure Cleanup

These can be implemented after the P0/P1 behavior is stable.

| ID | Location | Current behavior | Required fix |
|---|---|---|---|
| A19-11 | `Network/CalibreServerService+Annotations.swift:81-100` | Async annotation upload catches errors and logs `"Unknown"`. | Store the caught `CalibreAPIError` in the task/result or log its localized description. |
| A19-12 | `Network/CalibreServerService+ReadingPosition.swift:52-71` | Async position upload catches errors and logs `"Unknown"`. | Same as A19-11. |
| A19-13 | `Network/CalibreServerService+Annotations.swift:103-112` | Publisher replaces upload failure with the original task. | Use a failure type or explicit result wrapper. |
| A19-14 | `Network/CalibreServerService+ReadingPosition.swift:74-83` | Publisher replaces upload failure with the original task. | Same as A19-13. |
| A19-15 | `Network/CalibreServerService+Metadata.swift:12-77` | Completion has no error parameter. | Add a result-based overload; leave the old completion as a compatibility shim. |
| A19-16 | `Network/CalibreServerService+Metadata.swift:202-251` | Manifest completion returns nullable `Data?`. | Add a result-based overload so nil is not the only failure signal. |
| A19-17 | `Network/CalibreServerService+Metadata.swift:253-290` | `updateMetadata` returns `Int` while actual work happens asynchronously. | Add an async throwing API and migrate callers away from the `Int` facade. |
| A19-18 | `Network/CalibreServerService+LibrarySync.swift:104-155` | `syncLibraryPublisher` collapses failures into `errmsg` on a `Never` publisher. | Keep compatibility result if needed, but preserve `CalibreAPIError` for modern callers. |
| A19-19 | `Network/CalibreServerService+LibrarySync.swift:257-280` | `getLibraryCategoriesPublisher` catches all failures and returns the previous result without setting `errmsg`. | Set a structured error/result field or publish failure. |
| A19-20 | `Network/CalibreServerService+Discovery.swift:96-132` | Reachability probe folds all failures into `errorMsg`. | Preserve typed reason internally; keep display string at UI boundary. |
| A19-21 | `Network/CalibreServerService+Annotations.swift:22,39` | Annotation decode failures are `try?` and silently dropped. | Decode with `do/catch`; record decode failure in task/result. |
| A19-22 | `Network/CalibreServerService+LibrarySync.swift:283-309` | Metadata payload JSON failures are partly hidden by `try?`. | Keep partial-book behavior, but explicitly mark payload-level decode failures. |
| A19-23 | `Network/CalibreServerService+Metadata.swift:79-136,167-198` | Decode/encode failures become nil or partial Realm writes. | Return/throw a typed decode failure before writing partial metadata where possible. |
| A19-24 | `Network/CalibreServerService+ReadingPosition.swift:28-49` and `Network/CalibreServerService+Annotations.swift:46-79` | Task builders return nil for URL/encoding failures. | Add throwing builders or result-returning builders for modern callers. |
| A19-25 | `Models/CalibreBookManager.swift:231,257,260` and `Models/ReadingSessionManager.swift:196,226` | DSReader Helper return values are discarded. | Migrate to the async throwing DSReader Helper APIs from A19-03. |
| A19-26 | `Models/CalibreLibraryManager.swift:253-255` and `Models/ModelData.swift:950-982` | Sync/helper-config failures can no-op at the Combine boundary. | Handle `.failure` completions or migrate the pipeline to typed results. |
| A19-27 | `Network/BookDownloadManager.swift:119-195` | `startDownload` returns `Bool` for several distinct failure modes. | Add a typed `DownloadStartError` or `Result` API. |
| A19-28 | `Views/Utils.swift:92` | Image data publisher uses `.replaceError(with: nil)`. | Decide whether this utility is still needed; if yes, surface error/retry state. |
| A19-29 | `Views/SettingsView/SupportInfoViewModel.swift:59,138` | Uses ad-hoc `NSError(domain: "YABRError", ...)`. | Replace with a small local typed error or shared support-export error. |

## Cross-Cutting Architecture Work

### Error Taxonomy

`CalibreAPIError` and `SearchError` currently overlap. `SearchError` is still
valuable because search has non-network cases, but it should preserve network
details instead of stringifying them.

Recommended shape:

```swift
enum SearchError: Error, Equatable, Sendable {
    case network(CalibreAPIError)
    case database(String)
    case invalidState(String)
    case cancelled
}
```

If `Equatable` becomes awkward because `CalibreAPIError` carries underlying
errors, add a stable comparison key to `CalibreAPIError` rather than reverting
to strings.

### Logging Boundary

- Use `CalibreActivityLogger` for user-initiated Calibre operations that should
  appear in activity/history.
- Use `OSLog.Logger` for developer diagnostics and non-user-visible helper
  failures.
- Avoid logging expected cancellation as an error.
- Keep UI display strings at the ViewModel/UI boundary, not inside low-level
  networking helpers.

### Dead Or Low-Confidence Code

- `Network/Downloader.swift` still appears unused. If `rg` continues to show no
  callers, prefer deletion or quarantine before modernizing it.
- Broad PDF/shelf/debug `print` cleanup is outside A19 unless it touches network
  behavior. Track it separately to keep A19 focused.

## Implementation Sequence

The A19 work should be implemented as small stages. Each stage must leave the
project buildable, should have focused tests, and should be independently
reviewable. Do not bundle later stages into an earlier stage just because the
files are nearby.

### Stage A19-S1: Category Fetch HTTP Validation

- **Goal:** Close the highest-risk cache corruption path first.
- **Scope:** A19-01 only.
- **Files:** `Models/Services/LibraryCategoryService.swift`, new or existing
  category-service tests.
- **Actions:**
  1. Route HTTP category page fetches through
     `CalibreServerService.validatedData(from:server:qos:)`.
  2. Preserve existing cache freshness behavior and repository write behavior.
  3. Add a non-2xx test that proves no category cache write occurs.
- **Verification:**
  - Focused category service tests pass.
  - `xcodebuild ... build` passes.
- **Exit criteria:** 2xx category responses still decode and cache; 4xx/5xx
  responses surface as `CalibreAPIError` and leave the cache unchanged.

### Stage A19-S2: Metadata Empty-Entry Protection

- **Goal:** Prevent failed metadata fetches from producing a valid-looking empty
  `CalibreBookEntry`.
- **Scope:** A19-02 only.
- **Files:** `Network/CalibreServerService+Metadata.swift`,
  `CalibreServerServiceTests`, any direct callers of `getMetadata(task:)`.
- **Actions:**
  1. Add a typed or optional-result metadata publisher path.
  2. Keep a compatibility wrapper only if existing callers still require
     `Failure == Never`.
  3. Add tests for HTTP failure and decode failure.
- **Verification:**
  - Metadata service tests pass.
  - Search/library sync tests that consume metadata still pass.
  - `xcodebuild ... build` passes.
- **Exit criteria:** No failure path emits a non-optional
  `CalibreBookEntry()` placeholder.

### Stage A19-S3: DSReader Helper Result Semantics

- **Goal:** Make Goodreads shelf/progress helper calls report real completion
  instead of task-start success.
- **Scope:** A19-03 and A19-25.
- **Files:** `Network/DSReaderHelperConnector.swift`,
  `Models/CalibreBookManager.swift`, `Models/ReadingSessionManager.swift`,
  `DSReaderHelperConnectorTests`.
- **Actions:**
  1. Introduce async throwing helper methods for add-to-shelf,
     remove-from-shelf, and reading-progress updates.
  2. Validate HTTP status and map failures through `CalibreAPIError`.
  3. Migrate manager/session call sites to observe the async result or log
     failure.
  4. Keep old `Bool` methods only as temporary adapters if needed.
- **Verification:**
  - DSReader helper tests cover success, 4xx, and transport failure.
  - Manager/session tests or focused mocks verify failures are not discarded.
  - `xcodebuild ... build` passes.
- **Exit criteria:** Callers no longer interpret `task.resume()` as sync
  success, and helper failures are observable.

### Stage A19-S4: Search Error Preservation

- **Goal:** Keep Calibre network failures structured through unified search.
- **Scope:** A19-04 and the `SearchError` taxonomy work.
- **Files:** `Models/UnifiedSearchModels.swift`,
  `Models/Services/LibrarySearchService.swift`,
  `Models/Services/UnifiedSearchService.swift`, search tests.
- **Actions:**
  1. Add a `SearchError` case that wraps `CalibreAPIError` or equivalent stable
     representation.
  2. Route HTTP search fetches through `validatedData(from:server:)`.
  3. Preserve local file search behavior.
  4. Update error handling in unified search to avoid stringifying structured
     network failures.
- **Verification:**
  - Library search tests cover auth/status/decode failure.
  - Unified search tests still pass, including cancellation and cache fallback
    cases.
  - `xcodebuild ... build` passes.
- **Exit criteria:** Search callers can distinguish auth, HTTP status,
  transport, decode, database, and cancellation failures.

### Stage A19-S5: Modern CalibreAPIError Publisher Overloads

- **Goal:** Stop losing structured errors at Combine boundaries without
  breaking old callers in one large patch.
- **Scope:** A19-05 through A19-08.
- **Files:** `Network/CalibreServerService+Annotations.swift`,
  `Network/CalibreServerService+LibrarySync.swift`,
  `Network/CalibreServerService+ReadingPosition.swift`,
  `Network/CalibreServerService+Metadata.swift`, related tests.
- **Actions:**
  1. Add modern overloads returning `AnyPublisher<..., CalibreAPIError>`.
  2. Reimplement legacy `URLError` publishers as adapters where required.
  3. Migrate low-risk internal call sites to the modern overloads.
  4. Leave larger caller migrations for later stages if they cross feature
     boundaries.
- **Verification:**
  - Existing publisher tests still pass.
  - New tests assert auth/status/decode errors survive through modern overloads.
  - `xcodebuild ... build` passes.
- **Exit criteria:** Modern publisher paths preserve `CalibreAPIError`; legacy
  `URLError` conversion is isolated and intentional.

### Stage A19-S6: Upload And Task-Builder Failure Visibility

- **Goal:** Make annotation and reading-position upload failures visible.
- **Scope:** A19-11 through A19-14, A19-21, and A19-24.
- **Files:** `Network/CalibreServerService+Annotations.swift`,
  `Network/CalibreServerService+ReadingPosition.swift`, annotation/position
  tests.
- **Actions:**
  1. Replace empty upload `catch {}` blocks with captured/logged
     `CalibreAPIError`.
  2. Replace `replaceError(with: task)` with a result-aware API or failure
     publisher.
  3. Add throwing builders for new annotation and position call sites while
     preserving optional builders as adapters if needed.
  4. Replace silent annotation decode `try?` with explicit decode handling.
- **Verification:**
  - Upload tests cover success, HTTP failure, and payload-encoding failure.
  - Reader progress and annotation sync flows still build.
  - `xcodebuild ... build` passes.
- **Exit criteria:** Upload failures no longer return an unchanged task without
  an attached or logged reason.

### Stage A19-S7: Legacy Facade Cleanup (Completed)

- **Goal:** Modernize compatibility APIs that hide errors behind `Never`, nil,
  integers, or stale result objects.
- **Scope:** A19-15 through A19-20, A19-22, A19-23, A19-26, and A19-27.
- **Files:** Metadata, manifest, library sync, discovery, download manager, and
  affected manager call sites.
- **Actions:**
  1. Add result-based or async throwing overloads for metadata, manifest, and
     metadata update.
  2. Preserve display-oriented compatibility fields such as `errmsg`, but keep
     typed errors internally.
  3. Replace silent category publisher fallback with a result that records the
     failure.
  4. Add a typed download-start failure API before changing UI call sites.
- **Verification:**
  - Existing sync/discovery/download tests pass.
  - New tests cover at least one failure mode for each newly typed facade.
  - `xcodebuild ... build` passes.
- **Exit criteria:** New code has a typed failure path; old no-error facades are
  adapters rather than the primary implementation.

### Stage A19-S8: View And Logging Boundary Cleanup (Completed)

- **Goal:** Remove remaining view-layer network error swallowing and noisy
  network prints.
- **Scope:** A19-09, A19-10, A19-28, A19-29, plus only network-related logging
  cleanup.
- **Files:** `Views/DictView/MDictViewEdit.swift`, `Views/Utils.swift`,
  `Views/SettingsView/SupportInfoViewModel.swift`, `Network/ImageRequest.swift`,
  `Network/CalibreServerService.swift`, `Network/BookDownloadManager.swift`,
  any tests for touched view models.
- **Actions:**
  1. Move dictionary lookup loading behind a service/helper with visible failure
     state.
  2. Delete or modernize the `Views/Utils.swift` image utility.
  3. Replace support-info ad-hoc `NSError` values with typed local errors.
  4. Remove network-related `print` calls or convert failure-only diagnostics to
     `Logger`.
- **Verification:**
  - View-model tests for changed UI state pass.
  - Manual smoke test dictionary lookup failure if no automated coverage exists.
  - `xcodebuild ... build` passes.
- **Exit criteria:** View-layer network failures are observable, and normal
  network usage does not spam stdout.

### Stage A19-S9: Final Integration And Regression Sweep

- **Goal:** Ensure the staged changes compose cleanly across search, sync,
  metadata, helper, and UI paths.
- **Scope:** Cross-stage regression only; avoid new behavior unless a regression
  is found.
- **Files:** Tests and documentation.
- **Actions:**
  1. Run the full iOS simulator test suite.
  2. Run targeted manual checks for server probe, library sync, search, category
     browsing, metadata refresh, DSReader Helper config/progress, and download
     start.
  3. Update `activeContext.md` and this audit with final implemented state,
     known residual risks, and exact verification commands/results.
- **Verification:**
  - Full `xcodebuild test` passes or failures are documented as unrelated and
    reproducible from baseline.
  - Memory-bank handoff notes are current.
- **Exit criteria:** A19 can be marked complete with clear residual follow-up
  items only for intentionally deferred non-network debug cleanup.

## Validation Plan

Run the narrowest relevant tests after each stage, then full validation before
closing A19. Each stage should produce a small diff and a clear pass/fail
verification result.

- `CalibreServerServiceTests`: add cases for non-2xx mapping, auth mapping,
  and payload decode failure.
- `LibraryCategoryService` tests: non-2xx response must not write cache.
- `LibrarySearchService` tests: auth/status/decode errors remain structured
  through `SearchError`.
- `DSReaderHelperConnectorTests`: success, 4xx failure, and transport failure
  for shelf/progress methods.
- Download start tests if `BookDownloadManager.startDownload` receives a typed
  error API.

Final command:

```bash
xcodebuild test -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/YabrDerivedData
```

If the full run is too expensive during intermediate work, at minimum run the
new/changed test classes plus:

```bash
xcodebuild -project YetAnotherEBookReader.xcodeproj -scheme YetAnotherEBookReader -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build
```

## Reference Files

- `Network/CalibreAPIError.swift`
- `Network/CalibreServerService.swift`
- `Network/CalibreServerService+LibrarySync.swift`
- `Network/CalibreServerService+Metadata.swift`
- `Network/CalibreServerService+Discovery.swift`
- `Network/CalibreServerService+ReadingPosition.swift`
- `Network/CalibreServerService+Annotations.swift`
- `Models/Services/LibrarySearchService.swift`
- `Models/Services/LibraryCategoryService.swift`
- `Network/DSReaderHelperConnector.swift`
- `Network/BookDownloadManager.swift`
- `.agents/memory-bank/refactoring-context.md`
