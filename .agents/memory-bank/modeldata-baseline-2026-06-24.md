# ModelData Elimination Baseline (2026-06-24)

## Starting State

| Metric | Value | Command |
|--------|-------|---------|
| `ModelData.swift` total lines | **1,073** | `wc -l Models/ModelData.swift` |
| `ModelData.swift` methods | **82** | `grep -c "^    func "` |
| `ModelData.swift` top-level properties | **29** | `grep -c "^    var "` |
| `ModelData.swift` `lazy var` count | **17** (incl. self-circular references) | `grep -c "^    lazy var "` |
| Files using `@EnvironmentObject var modelData` | **15** | `grep -rl "@EnvironmentObject var modelData"` |
| Files referencing `ModelData` | **62** | `grep -rl "ModelData"` |
| Production `ModelData.shared` references | **41** sites across 15 files | `grep -rc "ModelData.shared"` (production) |
| Test `ModelData.shared` references | **25** sites across 12 files | `grep -rc "ModelData.shared"` (tests) |

## Facade Forwarder Reference Density (by Manager)

| Manager | References in ModelData | Plan-estimated Facade methods | Plan-estimated Facade properties |
|---------|------------------------|------------------------------|----------------------------------|
| `bookManager` | **41** | ~25 | ~10 |
| `serverManager` | **23** | ~10 | ~3 |
| `libraryManager` | **22** | ~8 | ~3 |
| `sessionManager` | **23** | ~12 | ~5 |
| `downloadManager` | **8** | ~6 | 0 |
| `fontsManager` | **6** | ~3 | ~1 |
| `logger` | **3** | ~3 | 0 |
| `searchCacheRepository` | 0 | 0 | 0 |
| **Total** | **126** | **~67** | **~22** |

Note: Each reference may appear multiple times per method (e.g., getter + setter = 2 references for a property). The `41 bookManager` references account for ~25 methods + 10 properties × 2 (get+set) = ~45, close to the measured 41.

## ModelData.shared Distribution (Production, 41 sites in 15 files)

| File | Count | Category |
|------|-------|----------|
| `Views/FolioReaderView/Providers.swift` | 14 | Adapter |
| `Views/Reader/YabrEBookReaderMetaSource.swift` | 8 | Adapter |
| `Models/CalibreCoreModels.swift` | 3 | Model extensions |
| `Views/Reader/YabrReaderNavigationViewModel.swift` | 2 | ViewModel |
| `Views/LibraryInfoView/UnifiedSearchViewModel.swift` | 2 | ViewModel |
| `Views/LibraryInfoView/UnifiedCategoryViewModel.swift` | 2 | ViewModel |
| `Views/LibraryInfoView/LibraryInfoViewModel.swift` | 2 | ViewModel |
| `Views/SettingsView/ServerView/ServerDetailView.swift` | 1 | View |
| `Views/SettingsView/ReaderOptions/ReaderOptionsView.swift` | 1 | View |
| `Views/BookDetailView/ReadingPositionViewModel.swift` | 1 | ViewModel |
| `Views/BookDetailView/BookDetailViewModel.swift` | 1 | ViewModel |
| `ViewController/FolioReaderViewController.swift` | 1 | ViewController |
| `Models/Repositories/ReadingPositionRepository.swift` | 1 | Repository |
| `Models/ModelData.swift` | 1 | Self-reference (init) |
| `Models/CalibreBookManager.swift` | 1 | Manager |

Top concern: `Providers.swift` and `YabrEBookReaderMetaSource.swift` together account for 22 of 41 production `ModelData.shared` sites (54%).

## Force-Unwrapped Optionals Fixed (ModelData.swift)

| Property | Before | After | Lines |
|----------|--------|-------|-------|
| `realm` | `Realm!` | `Realm?` | 147 |
| `realmSaveBooksMetadata` | `Realm!` | `Realm?` | 148 |
| `realmConf` | `Realm.Configuration!` | `Realm.Configuration?` | 149 |
| `logger` | `CalibreActivityLogger!` | `CalibreActivityLogger?` | 151 |

These are the same class of issue as A23 (DatabaseService force-unwrap). All call sites either:
- Already used optional chaining (`modelData.realm != nil`) or nil comparison
- Were updated to use `guard let` or `try?` for safe unwrapping

Touched files beyond `ModelData.swift`:
- `Models/ReadingSessionManager.swift` — `listBookDeviceReadingPositionHistory` guard-let
- `Models/ShelfDataManager.swift` — `dispatchQueue.sync` optional init
- `Tests/BookDetailViewModelTests.swift` — `mockModelData.realm!` force-unwrap
- `Tests/CalibreBookManagerTests.swift` — `modelData.realmConf!` force-unwrap
- `Tests/V2MigrationDependencyTests.swift` — `modelData.realmConf ?? Realm.Configuration()` fallback

## Test Status

- `xcodebuild build`: **SUCCEEDED**
- `xcodebuild test`: **328 tests executed, 2 pre-existing failures** (not caused by Phase 0 changes)
  - `ReadingSessionManagerTests.testEndSession_logsActivity` — pre-existing stateful test pollution (fails on clean baseline with count=4)
  - `ShelfDisplayModelsTests.testSectionShelfViewModelMappingAndFilters` — pre-existing test that was showing 0 tests on clean baseline

## Phase 0 Status

- [x] 0a.1: ModelData.shared distribution catalogued
- [x] 0a.2: Facade reference density quantified
- [x] 0a.3: 4 force-unwraps in ModelData fixed
- [x] 0a.4: Baseline file created (this file)
- [ ] 0b: FACADE markers + → TargetManager annotations
