# 测试覆盖提升计划

> 状态: Phase 1-4 已完成，2026-06-24 全量验证 329/329 通过

> 目标: 191 → 250+ tests, 6,829 → 10,000+ 测试代码行
> 日期: 2026-06-23

## 最新结果

- 已删除占位文件 `YetAnotherEBookReaderTests.swift`
- 已新增 `IntegrationTests.swift`
- 已补齐：
  - `UnifiedSearchServiceTests` 的 cancellation / timeout / empty-result
  - `CalibreServerServiceTests` 的 discovery / probe / sync success
  - `BookDetailViewModelTests` 的 download / preview / metadata refresh
  - `FolioReaderProviderBookIdTests` 的 concurrent highlight / large bookmarks
- 当前全量测试：329/329 通过

---

## 一、当前覆盖状态

### 已有测试 (22 文件, 191 tests, 6,829 行)

| 测试文件 | tests | 覆盖目标 |
|---------|-------|---------|
| CalibreServerServiceTests | 28 | Network API + error mapping |
| BookDetailViewModelTests | 25 | ViewModel CRUD + state |
| CalibreDataSplitTests | 20 | 数据模型 identity/Codable |
| RealmDomainMappingTests | 15 | Realm ↔ 值类型映射 |
| FolioReaderProviderBookIdTests | 14 | FolioReader 适配器 |
| LibraryInfoBookListViewModelTests | 12 | 搜索列表 ViewModel |
| SectionShelfViewModelTests | 8 | 书架 ViewModel |
| YabrPDFViewControllerTests | 8 | PDF 控制器协调 |
| UnifiedSearchMergeServiceTests | 8 | K-way 合并算法 |
| UnifiedCategoryServiceTests | 7 | 分类缓存 + 合并 |
| RecentShelfViewModelTests | 7 | 最近阅读 ViewModel |
| DSReaderHelperConnectorTests | 7 | Helper 插件网络 |
| ReadiumVolumeKeyPagingCoordinatorTests | 6 | 音量键翻页 |
| UnifiedSearchServiceTests | 5 | 搜索协调 actor |
| MainViewModelTests | 5 | 主视图 ViewModel |
| V2MigrationDependencyTests | 4 | V2 依赖注入 |
| SettingsViewModelTests | 4 | 设置 ViewModel |
| ReaderOptionsViewModelTests | 4 | 阅读选项 ViewModel |
| UnifiedSearchIntegrationTests | 2 | 端到端搜索集成 |
| SupportInfoViewModelTests | 2 | 支持信息 ViewModel |
| ShelfDisplayModelsTests | 2 | 书架显示模型 |
| YetAnotherEBookReaderTests | 1 | 占位 (可删除) |

### 覆盖热力图

```
覆盖完善 ████████ : Services (Search/Category), ServerService API, ViewModel (BookDetail, Shelf)
覆盖基础 ████░░░░ : DSReaderHelper, PDF VC, FolioReader Adapter, Realm Mappers
无覆盖   ░░░░░░░░ : Managers (Book/Library/Server), Repositories (单独), Download, ModelData
```

---

## 二、覆盖缺口分析

### Tier 1: 高风险无覆盖 (建议优先)

| 生产文件 | 行数 | 风险 | 原因 |
|---------|------|------|------|
| **CalibreBookManager** | 750 | 🔴 高 | 核心 CRUD, 元数据管理, 书架变更, Realm 线程逻辑 |
| **CalibreLibraryManager** | 508 | 🔴 高 | 图书馆探测/同步, 本地图书馆逻辑, 状态广播 |
| **CalibreServerManager** | 256 | 🟡 中 | 服务器 CRUD, 连接探测, staging 逻辑 |
| **BookDownloadManager** | 349 | 🟡 中 | 下载状态机, 格式检查, 任务管理 |
| **ReadingSessionManager** | 311 | 🟡 中 | 格式偏好, 阅读会话, 位置更新 |

### Tier 2: 中风险低覆盖

| 生产文件 | 行数 | 现有测试 | 缺口 |
|---------|------|---------|------|
| **AnnotationRepository** | 371 | RealmDomainMappingTests (间接) | 缺 CRUD 操作直接测试 |
| **ReadingPositionRepository** | 296 | RealmDomainMappingTests (间接) | 缺 savePosition, getPositions 测试 |
| **BookRepository** | 128 | RealmDomainMappingTests (间接) | 缺独立 CRUD 测试 |
| **ShelfDataManager** | 370 | ShelfDisplayModelsTests (间接) | 缺 section 解析, 数据变更 |
| **LibrarySearchService** | 304 | UnifiedSearchServiceTests (间接) | 缺 source selection, offline fallback |

### Tier 3: 低风险但有价值

| 生产文件 | 行数 | 备注 |
|---------|------|------|
| **ModelData** 协调逻辑 | 1,061 | 管理器联动, 初始化, 事件转发 |
| **CalibreServerService+LibrarySync** | 348 | 复杂增量同步逻辑 |
| **CalibreServerService+Metadata** | 344 | 批量元数据解析 |
| **FontsManager** | 113 | 字体导入/删除 |
| **CalibreActivityLogger** | 109 | 活动日志 |
| **Downloader** | 96 | 简单下载器 |

---

## 三、分阶段实施计划

### Phase 1: Manager 核心测试 (预计 +40 tests, ~2 天)

**目标**: 覆盖三大 Manager 的 CRUD 和状态管理

#### 1a. CalibreBookManagerTests (~15 tests)

```swift
// 测试文件: YetAnotherEBookReaderTests/CalibreBookManagerTests.swift

// CRUD 与元数据
func testAddBookToShelf_updatesPublishedProperty()
func testRemoveBookFromShelf_updatesPublishedProperty()
func testGetBook_returnsNilForUnknownId()
func testGetBook_returnsCachedBook()
func testSaveBooksMetadata_writesViaRepository()
func testSaveBooksMetadata_updatesInMemoryCache()

// 书架管理
func testBookInShelf_filtersByLibraryId()
func testSelectedBookId_publishesChange()
func testBookModelSection_returnsCorrectSection()

// Realm 线程安全
func testGetRealm_returnsMainRealmOnMainThread()
func testGetRealm_createsNewRealmOnBackgroundThread()

// Combine 集成
func testObjectWillChange_firesOnBookChange()

// Goodreads 集成
func testGoodreadsShelfUpdate_callsDSReaderHelper()

// 边界条件
func testEmptyShelf_returnsEmptyDictionary()
func testConcurrentShelfAccess_doesNotCrash()
```

**Mock 需求**: `MockBookRepository`, `MockDatabaseService`

#### 1b. CalibreLibraryManagerTests (~12 tests)

```swift
// 测试文件: YetAnotherEBookReaderTests/CalibreLibraryManagerTests.swift

// CRUD
func testAddLibrary_updatesPublishedProperty()
func testRemoveLibrary_updatesPublishedProperty()
func testGetLibrary_returnsCachedLibrary()

// 同步状态
func testLibrarySyncStatus_defaultsToIdle()
func testLibrarySyncStatus_updatesCorrectly()
func testUpdateSyncStatus_publishesChange()

// 本地图书馆
func testLocalLibrary_isCreatedOnInit()
func testLocalLibrary_hasCorrectConfiguration()

// Staging (临时编辑)
func testStagingAdd_doesNotAffectLiveData()
func testStagingCommit_appliesChanges()

// 图书馆列表
func testActiveLibraries_filtersDeleted()
func testLibrariesForServer_returnsCorrectSubset()
```

**Mock 需求**: `MockLibraryRepository`, `MockServerManager`

#### 1c. CalibreServerManagerTests (~8 tests)

```swift
// 测试文件: YetAnotherEBookReaderTests/CalibreServerManagerTests.swift

func testAddServer_savesViaRepository()
func testRemoveServer_deletesViaRepository()
func testRemoveServer_cascadesLibraryDeletion()
func testGetServer_returnsCachedServer()
func testServerReachability_publishesChange()
func testStagingServer_doesNotAffectLive()
func testDocumentServer_returnsFirstSetup()
func testObjectWillChange_firesOnServerChange()
```

**Mock 需求**: `MockServerRepository`

#### 1d. Mock 基础设施补充

现有测试已有部分 Mock（如 `MockSearchCacheRepository`、`MockURLProtocol`）。
新增需要：

```swift
// YetAnotherEBookReaderTests/TestHelpers/MockRepositories.swift

class MockBookRepository: BookRepositoryProtocol { ... }
class MockServerRepository: ServerRepositoryProtocol { ... }
class MockLibraryRepository: LibraryRepositoryProtocol { ... }
class MockAnnotationRepository: AnnotationRepositoryProtocol { ... }
class MockDatabaseService { ... }
```

---

### Phase 2: Repository 独立测试 (预计 +25 tests, ~1.5 天)

**目标**: 验证每个 Repository 的 Realm CRUD 操作（使用 inMemory Realm）

#### 2a. RealmBookRepositoryTests (~8 tests)

```swift
func testSaveBook_persistsToRealm()
func testGetBook_byPrimaryKey()
func testDeleteBook_removesFromRealm()
func testGetAllBooks_returnsArray()
func testSaveBook_updatesExisting()
func testSaveBook_withReadingPositions()
func testGetBooksForLibrary_filters()
func testConcurrentSave_doesNotCrash()
```

#### 2b. RealmAnnotationRepositoryTests (~8 tests)

```swift
func testSaveHighlight_persistsToRealm()
func testGetHighlights_forBookId()
func testDeleteHighlight_byId()
func testSaveBookmark_persistsToRealm()
func testGetBookmarks_forBookId()
func testDeleteBookmark_byId()
func testSaveBookmark_updatesExisting_inPlace()
func testAtomicSavePosition_replaceOlder()
```

#### 2c. RealmReadingPositionRepositoryTests (~5 tests)

```swift
func testSavePosition_persistsToRealm()
func testGetPositions_forBookId()
func testGetLatestPosition_returnsNewest()
func testDeletePosition_removesFromRealm()
func testSavePosition_mainAndBackgroundThread()
```

#### 2d. RealmServerRepositoryTests + RealmLibraryRepositoryTests (~4 tests)

```swift
func testServerCRUD_roundTrip()
func testLibraryCRUD_roundTrip()
func testDeleteServer_cascadesLibraries()
func testLibraryQuery_byServerId()
```

---

### Phase 3: 网络与下载测试 (预计 +15 tests, ~1 天)

#### 3a. BookDownloadManagerTests (~8 tests)

```swift
func testStartDownload_addsToActiveDownloads()
func testCancelDownload_removesFromActive()
func testDownloadProgress_publishesUpdates()
func testIsFormatDownloaded_checksLocalFile()
func testConcurrentDownloads_limitsQueue()
func testDownloadCompletion_updatesState()
func testDownloadFailure_setsErrorState()
func testPendingDownloads_queueing()
```

**Mock 需求**: `MockDownloader`

#### 3b. ReadingSessionManagerTests (~7 tests)

```swift
func testDefaultFormat_returnsPreferredFormat()
func testFormatReaderMap_storesPreference()
func testUpdateCurrentPosition_savesViaRepository()
func testStartSession_recordsTimestamp()
func testEndSession_logsActivity()
func testSelectedReadingBook_publishesChange()
func testFormatList_orderedByPreference()
```

---

### Phase 4: 覆盖加深与边界测试 (预计 +20 tests, ~1.5 天)

#### 4a. 现有测试扩展

| 现有测试文件 | 新增方向 | +tests |
|------------|---------|--------|
| UnifiedSearchServiceTests | 并发取消, 超时, 空结果 | +3 |
| CalibreServerServiceTests | LibrarySync 增量/全量, Discovery | +5 |
| BookDetailViewModelTests | 下载交互, 预览, 元数据刷新 | +3 |
| FolioReaderProviderBookIdTests | 并发高亮写入, 大量书签 | +2 |

#### 4b. 集成/冒烟测试

```swift
// YetAnotherEBookReaderTests/IntegrationTests/

// 模拟完整阅读流程
func testFullReadingFlow_openBook_savePosition_closeBook()

// 模拟搜索 → 详情 → 下载流程
func testSearchToDownloadFlow()

// 模拟服务器添加 → 图书馆同步
func testServerSetupAndLibrarySync()

// 数据库初始化 → 迁移验证
func testDatabaseInitialization_withCleanState()
func testDatabaseMigration_fromPreviousSchema()
```

#### 4c. 删除占位测试

- 删除 `YetAnotherEBookReaderTests.swift` 中的空 `testExample()`

---

## 四、Mock 基础设施规划

### 需要新建的 Mock 文件

```
YetAnotherEBookReaderTests/
├── TestHelpers/
│   ├── MockRepositories.swift       (Book/Server/Library/Annotation/Position)
│   ├── MockManagers.swift           (BookManager/LibraryManager/ServerManager)
│   ├── MockDatabaseService.swift    (in-memory Realm config)
│   └── TestFixtures.swift           (预定义的 CalibreServer/Library/Book 实例)
```

### 可复用的现有 Mock

| 现有 Mock | 位置 | 可扩展 |
|----------|------|--------|
| `MockSearchCacheRepository` | UnifiedSearchServiceTests | ✅ |
| `MockURLProtocol` | CalibreServerServiceTests | ✅ |
| `MockLibraryProvider` | UnifiedSearchServiceTests | ✅ |
| `StubAnnotationRepository` | FolioReaderProviderBookIdTests | ✅ |

### TestFixtures 示例

```swift
enum TestFixtures {
    static func makeServer(id: String = UUID().uuidString) -> CalibreServer { ... }
    static func makeLibrary(serverId: String, name: String = "Test") -> CalibreLibrary { ... }
    static func makeBook(libraryId: String, title: String = "Test Book") -> CalibreBook { ... }
    static func makeReadingPosition(bookId: String, progress: Double = 0.5) -> BookDeviceReadingPosition { ... }
    static func makeHighlight(bookId: String) -> BookHighlight { ... }
    static func inMemoryRealmConfig() -> Realm.Configuration { ... }
}
```

---

## 五、预期成果

| 指标 | Phase 1 后 | Phase 2 后 | Phase 3 后 | Phase 4 后 |
|------|-----------|-----------|-----------|-----------|
| **测试数** | ~231 | ~256 | ~271 | ~291 |
| **测试文件** | 26 | 30 | 32 | 34 |
| **测试代码行** | ~8,000 | ~9,200 | ~9,800 | ~10,500 |
| **Manager 覆盖** | ✅ 3/3 | ✅ | ✅ | ✅ |
| **Repository 覆盖** | 间接 | ✅ 5/5 | ✅ | ✅ |
| **Network 覆盖** | 现有 | 现有 | ✅ Download | ✅ |

### 执行优先级

```
Phase 1 (Manager 核心) ──── 最高优先级, 覆盖最高风险代码
  ↓
Phase 2 (Repository)  ──── 验证数据持久化正确性
  ↓
Phase 3 (Download)    ──── 覆盖用户可见的下载功能
  ↓
Phase 4 (加深+集成)   ──── 防回归安全网
```

---

## 六、验证标准

每个 Phase 完成后:

```bash
xcodebuild test \
  -project YetAnotherEBookReader.xcodeproj \
  -scheme YetAnotherEBookReader \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/YabrDerivedData
```

- 所有测试 0 failures
- 新测试覆盖的生产代码路径无 `force unwrap` 或 `try!`
- Mock 对象实现完整的 Protocol 协议
- 测试间无共享状态 (每个测试独立 setUp/tearDown)
