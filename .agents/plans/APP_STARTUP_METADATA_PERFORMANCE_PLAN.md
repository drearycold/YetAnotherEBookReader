# App 启动与 Metadata Sync 性能优化实施指南

创建日期：2026-06-27
状态：待实施

## 1. 目标

本计划处理两组已经由真机 Time Profiler 确认的问题：

1. App 冷启动期间 Recent shelf 在主线程重复读取 reading position，并伴随
   SwiftUI 重复建树和 ViewModel 重建。
2. `CalibreBookManager.getBooksMetadata(request:)` 在 MainActor 上同步合并
   position、highlight 和 bookmark，形成超过 1G cycles 的主线程 hang。

同时收敛 `takePrecedence` 的历史设计问题。该字段当前混合了 FolioReader
恢复过程中的瞬时控制状态和阅读历史 session 续接状态，但二者都不属于
`BookDeviceReadingPosition` 的长期领域数据。

实施必须遵循以下原则：

- 每个 Stage 单独提交、单独测试、单独允许回滚。
- 先锁定行为，再调整线程，最后优化算法。
- Realm 对象不得跨线程或 continuation 边界；跨边界只传值类型、配置或主键。
- MainActor 只更新 UI 状态和调度网络任务，不执行批量 Realm merge。
- 本轮不修改 `/Users/peterlee/git/FolioReaderKit`。

## 2. 已确认根因

### 2.1 启动路径

基线 profile：

- SwiftUI AttributeGraph 更新约占 `47.7%`。
- `registerRecentShelfUpdater()` 约占 `9.8%`。
- Shelf 对每本书先调用 `getPositions` 计算时间，随后
  `prepareBookReading` 再调用 `getPosition` 和 `getPositions`。
- `MainViewModel` 和 `SettingsViewModel` 在启动期存在创建后立即析构的路径。
- `MainView.init` 重复执行全局 navigation/tab bar appearance 配置。

### 2.2 Metadata merge 路径

已观察调用树：

```text
CalibreBookManager.refreshShelfMetadataV2
  CalibreBookManager.getBooksMetadata
    RealmAnnotationRepository.syncHighlights   47.7%
    RealmAnnotationRepository.syncBookmarks    29.9%
    RealmReadingPositionRepository.syncPositions 20.6%
```

根因：

- `getBooksMetadata` 标记为 `@MainActor`，网络 await 返回后的同步 merge
  全部恢复到主线程。
- `syncPositions` 对每条远端记录再次执行 Realm 查询，事务内又按条查询。
- `syncBookmarks` 对每个 pos 建立 live Results，并在排序比较器中重复解析日期。
- `syncHighlights(...) > 0 || syncBookmarks(...) > 0` 使用短路运算；当
  highlight pending 大于零时，bookmark merge 不会执行。

### 2.3 `takePrecedence` 的真实语义

当前存在两种无关场景：

1. FolioReader 在 reader 尚未 ready 时恢复指定位置。依赖内部把
   `FolioReaderReadPosition.takePrecedence` 临时设为 true，以绕过保存保护。
2. Reading history 在 app 短暂 background/active 时复用最近 session。
   当前借用 Realm position 上的同名字段，表示最近的 end position 仍可改写。

App 已通过 `ReaderInfo.position` 和
`readerConfig.savedPositionForCurrentBook` 显式传递恢复位置，因此
`takePrecedence` 不应进入 App 领域模型，也不应参与常规位置选择。

## 3. 锁定的设计

### 3.1 Position 选择

新增内部枚举：

```swift
enum ReadingPositionSelectionPolicy: Equatable, Sendable {
    case latest
    case latestForDevice(String)
}
```

选择只依据明确策略和 `epoch`：

- `.latest`：所有位置中 epoch 最大者。
- `.latestForDevice(name)`：指定 device 中 epoch 最大者。
- 用户从历史页面选择的位置直接作为 `ReaderInfo.position` 传递，不写入长期
  “preferred” 标志。

### 3.2 Session 生命周期

新增不暴露 Realm 类型的 handle：

```swift
struct ReadingSessionHandle: Hashable, Sendable {
    let bookId: String
    let historyId: String
}
```

Repository API 改为：

```swift
func beginSession(
    at position: BookDeviceReadingPosition,
    forBookId bookId: String
) -> ReadingSessionHandle?

func endSession(
    _ handle: ReadingSessionHandle,
    at position: BookDeviceReadingPosition
)
```

`historyId` 是 `BookDeviceReadingPositionHistoryRealm._id` 的 opaque string。
调用方不得解析它。

### 3.3 Metadata merge 线程

`CalibreBookManager` 拥有一条专用串行队列：

```swift
DispatchQueue(label: "book-metadata-sync", qos: .userInitiated)
```

- 网络请求继续并发。
- metadata 主 Realm 写入继续使用 `SaveBooksMetadataRealmQueue`。
- position/highlight/bookmark merge 统一进入 `book-metadata-sync`。
- worker 输入和输出只能是 detached value types。
- MainActor 只接收 merge outcome、更新 Published state，并创建上传 task。

## 4. 分阶段实施

每个阶段完成后必须先满足本阶段退出条件，再开始下一阶段。

### Stage P0：冻结性能与行为基线

目标：建立优化前可重复比较的数据，不改变业务行为。

修改范围：

- 为启动、shelf build 和 metadata merge 增加统一 signpost。
- 可新增内部 `AppPerformanceSignpost` 辅助类型。

实施步骤：

1. 为以下区间增加 Points of Interest：
   - database migration
   - database bootstrap
   - Recent shelf rebuild
   - first Recent shelf publish
   - metadata HTTP fetch
   - metadata Realm save
   - position merge
   - highlight merge
   - bookmark merge
2. signpost metadata 至少包含 library id、book count 和 annotation count。
3. 不把书名、URL、用户名等隐私数据写入 signpost。
4. 使用相同真机、相同数据库和相同书架执行 5 次冷启动。
5. 对同一 library 执行一次完整 shelf metadata refresh。
6. 保存 median 数据：
   - launch 到 database ready
   - launch 到 first shelf publish
   - main-thread CPU cycles
   - metadata merge wall time
   - position/highlight/bookmark 条目数

自动化验证：

- iOS Simulator build。
- 现有完整测试保持通过。

手动验证：

- Instruments Points of Interest 可看到完整、无重叠错误的区间。
- Time Profiler 中可关联 signpost 与已知调用树。

退出条件：

- 基线设备、数据规模、结果和采集步骤记录在本计划的实施 PR。
- 本阶段不包含业务逻辑修改。

建议提交：

```text
chore(perf): add startup and metadata sync signposts
```

### Stage P1：锁定 Position 选择行为

目标：先用纯测试定义不依赖 `takePrecedence` 的选择规则。

修改文件：

- `Models/ReadingPositionModels.swift`
- 新增或扩展 reading position 纯逻辑测试。

实施步骤：

1. 定义 `ReadingPositionSelectionPolicy`。
2. 定义纯值 selector，从 `[BookDeviceReadingPosition]` 中选出结果。
3. selector 不假设输入顺序，内部按 epoch 比较。
4. epoch 相同时使用稳定规则：
   - 保持输入中先出现的位置。
   - 不使用 reader type、page 或 Realm ObjectId 作为隐式 tie-breaker。
5. 不给 `BookDeviceReadingPosition` 增加 `takePrecedence`。
6. 不修改 repository 或生产调用方。

自动化测试：

- 空数组返回 nil。
- `.latest` 返回全局最大 epoch。
- `.latestForDevice` 只在目标 device 中选择。
- device 不存在时返回 nil。
- epoch 相同保持输入顺序。
- 任意排列输入都符合策略定义。

验证命令：

```bash
xcodebuild test \
  -project YetAnotherEBookReader.xcodeproj \
  -scheme YetAnotherEBookReader \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/YabrDerivedData \
  -only-testing:YetAnotherEBookReaderTests/ReadingPositionSelectionTests
```

退出条件：

- 选择语义完全由纯测试描述。
- 生产代码行为尚未改变。

建议提交：

```text
test(reading): define explicit position selection policy
```

### Stage P2：迁移 Repository 和 ReaderInfo 选择

目标：删除常规位置读取对持久化 precedence flag 的依赖，并消除
`prepareBookReading` 的重复查询。

修改文件：

- `Models/Repositories/ReadingPositionRepository.swift`
- `Models/ReadingSessionManager.swift`
- `Models/ShelfDataManager.swift`
- repository mocks 和相关测试。

实施步骤：

1. 将 repository 查询 API 改为显式 selection policy。
2. Realm 查询不得再读取 `takePrecedence`。
3. 迁移所有 `deviceName: nil` 调用为 `.latest`。
4. 迁移指定设备调用为 `.latestForDevice(deviceName)`。
5. 为 `prepareBookReading` 增加接收已加载 positions 的内部重载。
6. 原 `prepareBookReading(book:)` 只调用一次 `getPositions`，然后按以下顺序：
   - 当前设备最新位置
   - 全局最新位置
   - preferred format 的初始位置
7. Shelf updater 的后台阶段携带 positions，并同时用于：
   - 最近阅读时间计算
   - ReaderInfo 构建
8. Shelf 最终 publish 前不得回到主线程执行 Realm 或文件查询。
9. 保留现有 public behavior：缺文件、format 和 reader 选择结果不变。

自动化测试：

- Repository 中遗留 `takePrecedence=true` 的旧记录不会压过更新记录。
- `prepareBookReading` 每本书只调用一次 `getPositions`。
- 当前设备优先于其他设备的更新位置。
- 当前设备无位置时回退全局最新。
- 无位置时创建默认 reader position。
- Shelf 排序仍使用所有设备的最大 epoch。

性能验证：

- `registerRecentShelfUpdater → getPosition` 调用链消失。
- 一次 shelf rebuild 每本书最多打开一次 position Realm。

退出条件：

- App 内不存在依赖 `takePrecedence` 的常规 position selection。
- focused tests 和 iOS build 通过。

建议提交：

```text
refactor(reading): use explicit position selection policy
```

### Stage P3：引入 ReadingSessionHandle

目标：使用显式 session identity 替代 history position 上的 mutable flag。

修改文件：

- `Models/ReadingPositionModels.swift`
- `Models/Repositories/ReadingPositionRepository.swift`
- repository mocks 和 tests。

实施步骤：

1. 定义 `ReadingSessionHandle`。
2. 将 protocol 的 `session(start:)` 替换为 `beginSession`。
3. 将 `session(end:)` 替换为接收 handle 的 `endSession`。
4. `beginSession` 查找该 book 最新 history：
   - end epoch 距当前小于 60 秒时返回原 history handle。
   - end 为空且 start 距当前小于 300 秒时返回原 handle。
   - 其他情况创建 history 并返回新 handle。
5. 复用 history 时不修改 Realm，仅返回 identity。
6. `endSession` 用 handle 的 history ID 和 book ID 精确查询。
7. handle book ID 不匹配时 no-op 并记录 debug-level 日志。
8. 只有新 position epoch 不早于现有 end epoch 时才允许更新。
9. 更新 end 时保持 history `_id` 不变，并在一个 Realm transaction 中完成。
10. 删除 history start/end 对 `takePrecedence` 的全部读写。

自动化测试：

- 新 session 创建 handle。
- 60 秒内已结束 session 复用同一 handle。
- 60 秒后创建新 handle。
- 300 秒内未结束 session 复用。
- 300 秒后创建新 session。
- end 只更新 handle 指向的 history。
- forged/mismatched handle 不修改数据。
- 迟到的旧 end callback 不覆盖较新 end。
- 重复 end 具有幂等结果。

退出条件：

- Repository session 逻辑不再查询“最新 history 后猜测目标”。
- Repository 中除 legacy Realm 字段声明外无 `takePrecedence` 使用。

建议提交：

```text
refactor(reading): replace session precedence with handles
```

### Stage P4：迁移 Reader 生命周期到 Session Handle

目标：让 reader lifecycle 显式持有并结束正确的 session。

修改文件：

- `Views/Reader/YabrEBookReaderNavigationController.swift`
- `ReadingSessionManagerTests.swift`
- reader lifecycle tests。

实施步骤：

1. 为 navigation controller 增加可空 `readingSessionHandle`。
2. `viewWillAppear` 调用 `beginSession` 并保存 handle。
3. background 保存最新 position 后，用当前 handle 调用 `endSession`。
4. active 时重新调用 `beginSession`，允许 repository 按时间窗口续接。
5. `viewWillDisappear` 只结束当前 handle，然后清空 handle。
6. Folio、YabrPDF、Readium 三条路径使用相同 handle 规则。
7. position 保存异步回调晚于 active/disappear 时，仍使用捕获的 handle，
   不读取可能已经替换的 controller 当前 handle。
8. 不修改 Goodreads 更新和 reader-close metadata refresh 行为。

自动化测试：

- view appear 创建 session。
- background/end 后 active 在窗口内续接。
- disappear 精确结束当前 session。
- Folio 异步保存回调不会结束新 session。
- PDF 和 Readium 路径仍写入 end position。

手动验证：

- 打开书、切后台 10 秒、返回、关闭，只生成一条 history。
- 切后台超过 60 秒后返回，生成新 history。
- 快速 background/active 不丢失 end position。

退出条件：

- 所有 session 调用方均使用 handle API。
- 旧 `session(start/end)` API 已删除。

建议提交：

```text
refactor(reader): track reading history with session handles
```

### Stage P5：收紧 FolioReader Adapter 边界

目标：保证 Folio 的瞬时 precedence 永远不进入 App domain 或 Realm mapper。

修改文件：

- `Views/FolioReaderView/Providers.swift`
- `FolioReaderProviderBookIdTests.swift`
- Realm mapping tests。

实施步骤：

1. 保留 `BookDeviceReadingPosition → FolioReaderReadPosition` 转换，但不设置
   App 持久化 precedence。
2. `FolioReaderReadPosition → BookDeviceReadingPosition` 明确忽略
   `takePrecedence`。
3. 保持 `EpubFolioReaderContainer.open` 通过
   `readerConfig.savedPositionForCurrentBook` 注入精确位置。
4. 删除未使用的 `BookDeviceReadingPositionRealm ↔ FolioReaderReadPosition`
   直接转换扩展。
5. Realm mapper 不新增 `takePrecedence`。
6. 为 `BookDeviceReadingPositionRealm.takePrecedence` 添加 legacy/inert 注释。
7. 暂不删除 Realm 字段，避免本阶段引入 schema migration。

自动化测试：

- 明确选择的旧历史位置仍传入 Folio reader config。
- Folio position 的 `takePrecedence=true` 转换到 domain 后不产生持久化状态。
- Domain 转回 Folio 时不恢复数据库中的 legacy flag。
- Realm round-trip 不依赖 legacy flag。

静态验证：

```bash
rg -n "takePrecedence" YetAnotherEBookReader
```

预期仅剩：

- legacy Realm 字段声明/说明。
- Folio adapter 边界上解释为何忽略该字段的代码或注释。

退出条件：

- App domain 无 precedence 字段。
- 不修改外部 FolioReaderKit。

建议提交：

```text
refactor(folio): contain precedence inside adapter boundary
```

### Stage P6：建立 Metadata Sync Worker

目标：先把现有 merge 原样移出 MainActor，不同时重写算法。

修改文件：

- `Models/CalibreBookManager.swift`
- 可新增 `Models/BookMetadataSyncWorker.swift`
- `CalibreBookManagerTests.swift`
- repository mocks。

实施步骤：

1. 定义内部 value-only sync job：
   - library/book identity
   - format
   - remote positions/highlights/bookmarks
   - 是否需要生成回传 payload
2. 定义 value-only outcome：
   - positions to upload
   - optional highlights/bookmarks payload
   - pending counts
3. 创建串行 `book-metadata-sync` queue。
4. 使用 checked continuation 提交整批 jobs。
5. queue block 必须在所有返回路径 resume continuation。
6. worker 内按原顺序调用三个 repository sync 方法。
7. 分别保存 highlight 和 bookmark pending 值，禁止使用短路 `||`。
8. pending 任一大于零时，在 worker queue 获取本地 annotation payload。
9. MainActor 收到 outcome 后才构建并启动网络上传 task。
10. `librarySyncStatus`、`booksInShelf`、`calibreUpdatedSubject` 继续只在
    MainActor 更新。

自动化测试：

- Mock repository 记录 `Thread.isMainThread == false`。
- highlight pending 大于零时 bookmark sync 仍被调用。
- 无 annotations 时 worker 不打开 annotation repository。
- continuation 在缺 entry、空 jobs 和 repository no-op 时均完成。
- upload task 数量和旧实现一致。

性能验证：

- Time Profiler 主线程不再出现 `getBooksMetadata → sync*`。
- 本阶段总 CPU 可能尚未下降，但 UI hang 必须消失。

退出条件：

- 三类 merge 全部运行在专用队列。
- 行为测试通过后才能开始算法优化。

建议提交：

```text
perf(metadata): move annotation merge off main actor
```

### Stage P7：线性化 Position Sync

目标：将 `syncPositions` 从逐 entry 查询改为一次预取、内存决策、单事务。

修改文件：

- `Models/Repositories/ReadingPositionRepository.swift`
- `RealmReadingPositionRepositoryTests.swift`

实施步骤：

1. 每次调用只获取一次 Realm。
2. 一次读取该 book 的所有 position Realm objects。
3. 在当前 queue 建立：
   - 按 device 分组的 epoch 排序索引。
   - 按 device/reader/structure identity 分组的索引。
4. 每个 remote CFI 只解析一次为 domain position。
5. 在内存中计算：
   - remote newer，需要替换本地。
   - remote missing，需要插入。
   - local newer，需要生成上传 entry。
6. 对待保存 positions 按完整 identity 去重。
7. 单个 write transaction：
   - 删除同 identity 的旧对象。
   - 仅在不存在相同或更新对象时新增。
8. transaction 内禁止调用 `realm.objects`、`getPosition` 或
   `getPositions`。
9. 保持返回 upload entries 的原有语义。

自动化测试：

- remote newer、remote older、equal epoch。
- 新 device。
- 同 device 不同 reader/structural identity。
- 重复 remote entries 不产生重复 Realm objects。
- 本地更新位置只生成一个 upload entry。
- 500+ positions 的结果正确。

性能验证：

- signpost 中 position merge 相对 P0 至少降低 50%。
- 调用树中没有 entry-loop 内 Realm query。

退出条件：

- 查询次数与 remote entry 数量无关。
- 所有 position repository tests 通过。

建议提交：

```text
perf(reading): linearize remote position merge
```

### Stage P8：线性化 Highlight Sync

目标：避免逐条主键查询和重复日期解析。

修改文件：

- `Models/Repositories/AnnotationRepository.swift`
- `RealmAnnotationRepositoryTests.swift`

实施步骤：

1. 每次调用创建一个 ISO8601 formatter。
2. 在 transaction 前把每个 remote timestamp 解析一次。
3. 丢弃 type、UUID、timestamp 或 spine 数据无效的 entries。
4. 一次读取本书所有 highlights，并按 highlight ID 建立索引。
5. 在内存中生成 add/update/remove/no-op actions。
6. 保持现有 0.1 秒 timestamp tolerance。
7. 只有 actions 非空时才打开 write transaction。
8. 单事务应用所有 actions。
9. 保持 pending count 的现有服务器回传语义。
10. 需要生成上传 payload 时，在同一 worker queue 完成 domain mapping。

自动化测试：

- server newer、local newer、近似相同 timestamp。
- remote removed、local removed。
- 新 highlight、重复 highlight、非法 UUID。
- style、note、TOC family titles 更新。
- pending count 与旧行为一致。
- 500+ highlights 压力样本。

性能验证：

- highlight merge 相对 P0 至少降低 40%。
- 每条 remote entry 不再触发 Realm primary-key query。

退出条件：

- Highlight merge 为 O(local + remote)。
- focused tests 通过。

建议提交：

```text
perf(annotation): linearize highlight merge
```

### Stage P9：线性化 Bookmark Sync

目标：移除逐 pos live Results 查询、循环 mutation 和比较器日期解析。

修改文件：

- `Models/Repositories/AnnotationRepository.swift`
- `RealmAnnotationRepositoryTests.swift`

实施步骤：

1. 一次读取本书所有 bookmarks，并按 pos 分组。
2. 每个 remote timestamp 只解析一次。
3. 单次 reduce 选出每个 pos 的最新 remote entry；不先收集再排序。
4. 每个 local pos 数组只排序一次。
5. 用普通数组计算 visible 和 removed 状态。
6. server newer 时，对预取的 visible objects 生成 remove actions。
7. 禁止在 live Results 上执行 `while`。
8. CFI page 解析在 transaction 前完成。
9. 单事务应用 remove/add actions。
10. 保持 pending set 和 0.1 秒 tolerance 语义。

自动化测试：

- server newer 替换、local newer 保留、timestamp 相同。
- 新 pos、removed remote、多个 local duplicates。
- 同 pos 多个 remote entries 只采用最新。
- 非法 timestamp、非法 CFI 不写入。
- pending count 与旧实现一致。
- 500+ bookmarks 压力样本。

性能验证：

- bookmark merge 相对 P0 至少降低 40%。
- 调用树中不存在 per-pos Realm filter/sort。

退出条件：

- Bookmark merge 为 O(local + remote)。
- focused tests 通过。

建议提交：

```text
perf(annotation): linearize bookmark merge
```

### Stage P10：稳定 App 与 ViewModel 生命周期

目标：避免启动状态变化导致 MainView 和 ViewModel 重复创建。

修改文件：

- `YetAnotherEBookReaderApp.swift`
- `MainView.swift`
- `Views/MainViewModel.swift`
- `Views/SettingsView/SettingsView.swift`

实施步骤：

1. App init 创建唯一 `AppContainer`。
2. App 同时创建并持有唯一 `MainViewModel` StateObject。
3. `MainView` 改为观察由 App 持有的 ViewModel。
4. `MainViewModel` 持有唯一 `SettingsViewModel`。
5. `SettingsView` 观察外部 SettingsViewModel。
6. 引入内部 launch state：
   - initializing(status)
   - ready
   - failed(message)
7. database ready 前不构建完整 TabView。
8. migration status 回调通过 MainActor 更新 launch state。
9. 增加 bootstrap-in-flight 防重入保护。
10. 把 navigation/tab bar appearance 移到一次性启动配置。
11. 删除 scene phase 调试 print。
12. 保持数据库失败时不启动 probe timer 的现有行为。

自动化测试：

- MainViewModel 的 child ViewModels identity 稳定。
- database failure 保持 failed state。
- 重复 active 不触发并行 bootstrap。
- database success 后只触发一次 ready。

手动验证：

- 冷启动、前后台切换、数据库失败模拟。
- Main/Recent/Section/Settings ViewModel 每进程只初始化一次。

退出条件：

- Profile 中不存在 MainViewModel 创建后立即析构。
- appearance 配置只执行一次。

建议提交：

```text
perf(app): stabilize startup view model lifetime
```

### Stage P11：合并 Bootstrap 发布

目标：减少 manager 按 item 发布造成的 AttributeGraph 重算。

修改文件：

- `Models/CalibreServerManager.swift`
- `Models/CalibreLibraryManager.swift`
- `Models/CalibreBookManager.swift`
- 对应 manager tests。

实施步骤：

1. `populateServers` 在局部字典中构建结果，最后赋值一次。
2. credential 配置行为保持不变。
3. `populateLibraries` 在局部字典中构建结果，最后赋值一次。
4. `populateBookShelf` 在局部字典中构建结果。
5. 每本书先完成所有 format cache 检查。
6. 每本书最多调用一次 repository save。
7. shelf 字典最后赋值一次。
8. 删除 `booksInShelfRealm` 等启动调试 print。
9. 不在本阶段移除 `AppContainer.forwardObjectWillChange`。

自动化测试：

- 每个 populate 方法的 Published property 只产生一次非初始 emission。
- server/library/book 最终集合与旧实现一致。
- removed server、local library 和 cache format 状态保持不变。
- changed book 每本最多保存一次。

性能验证：

- 冷启动 manager publications 显著减少。
- AttributeGraph transaction 数量相对 P0 下降。

退出条件：

- Bootstrap 不再按 item 触发根视图更新。
- manager focused tests 通过。

建议提交：

```text
perf(bootstrap): batch manager state publication
```

### Stage P12：缓存 Server-Scoped Realm Configuration

目标：避免每本书重复构造相同 objectTypes、file URL 和 migration block。

修改文件：

- `Models/Repositories/DefaultServerScopedRealmConfigurationProvider.swift`
- provider tests。

实施步骤：

1. 缓存 key 使用 server UUID 和 `AppContainer.RealmSchemaVersion`。
2. 使用 lock 保护缓存读写。
3. lock 内只检查和写入缓存；昂贵 configuration 构建在 lock 外完成。
4. 双重检查，避免并发首次请求覆盖不同 schema version。
5. 返回 Realm.Configuration value copy，不缓存 Realm instance。
6. 测试环境继续使用现有 in-memory provider，不共享 production cache。

自动化测试：

- 同 server/schema 重复请求只构建一次。
- 不同 server 生成不同 file URL。
- schema version 改变后生成新 configuration。
- 并发请求返回一致配置。

退出条件：

- Shelf build 中 configuration 构造次数接近 server 数，而不是 book 数。
- 不引入跨线程 Realm instance。

建议提交：

```text
perf(realm): cache server scoped configurations
```

### Stage P13：最终回归与 Profile 验收

目标：确认行为、线程安全和性能目标同时满足。

自动化验证顺序：

1. Position/Session：

```bash
xcodebuild test \
  -project YetAnotherEBookReader.xcodeproj \
  -scheme YetAnotherEBookReader \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/YabrDerivedData \
  -only-testing:YetAnotherEBookReaderTests/RealmReadingPositionRepositoryTests \
  -only-testing:YetAnotherEBookReaderTests/ReadingSessionManagerTests \
  -only-testing:YetAnotherEBookReaderTests/FolioReaderProviderBookIdTests
```

2. Metadata merge：

```bash
xcodebuild test \
  -project YetAnotherEBookReader.xcodeproj \
  -scheme YetAnotherEBookReader \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/YabrDerivedData \
  -only-testing:YetAnotherEBookReaderTests/RealmAnnotationRepositoryTests \
  -only-testing:YetAnotherEBookReaderTests/CalibreBookManagerTests
```

3. Shelf/App：

```bash
xcodebuild test \
  -project YetAnotherEBookReader.xcodeproj \
  -scheme YetAnotherEBookReader \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/YabrDerivedData \
  -only-testing:YetAnotherEBookReaderTests/MainViewModelTests \
  -only-testing:YetAnotherEBookReaderTests/RecentShelfViewModelTests \
  -only-testing:YetAnotherEBookReaderTests/SectionShelfViewModelTests
```

4. 完整 test suite。
5. iOS Simulator build。
6. Mac Catalyst build。

真机手动回归：

- 冷启动 Recent shelf。
- Recent 和 Discover refresh。
- 打开 Folio、YabrPDF、Readium reader 并关闭。
- 从 reading history 打开旧位置。
- 前后台 10 秒与超过 60 秒的 session 行为。
- 有本地 pending annotations 时执行 server sync。
- 大量 highlights/bookmarks 的书籍执行 refresh，UI 可持续交互。

Profile 验收：

- 主线程不再出现 `getBooksMetadata → sync*`。
- metadata merge 主线程占比低于 1%。
- metadata merge 总 CPU 相对 P0 降低至少 40%。
- position merge 相对 P0 降低至少 50%。
- 冷启动主线程 CPU 中位数降低至少 15%。
- 首次 shelf publish 时间不回退。
- 每次 shelf rebuild 每本书最多读取一次 positions。

退出条件：

- 所有自动化与手动回归通过。
- 性能未达到目标时，根据最新 profile 新建独立后续计划，不在本阶段继续
  追加未经测量的优化。

建议提交：

```text
docs(perf): record startup and metadata optimization results
```

## 5. 明确排除项

- 不修改 `/Users/peterlee/git/FolioReaderKit`。
- 不在本轮删除 Realm `takePrecedence` 字段或增加 schema version。
- 不并行执行多个 annotation Realm write worker。
- 不改变 Calibre annotation payload 格式。
- 不修改 Goodreads progress、download 或 Discover 自动填充行为。
- 不因当前 profile 直接重写 `AppContainer.forwardObjectWillChange`。
- 不优先修改 Kingfisher；只有最终 profile 中图片处理超过 5% 才另行规划。

## 6. 最终 Definition of Done

- `takePrecedence` 只存在于 FolioReader 内部瞬时状态和待删除的 inert Realm
  字段，不再承担 App 业务选择或 session 续接语义。
- Reading position 选择策略在调用点显式可见。
- Reading history 使用 handle 精确更新。
- Metadata merge 不阻塞 MainActor。
- 三种 merge 算法不在 entry loop 中执行 Realm 查询。
- App 启动不重复构造主 ViewModel。
- Bootstrap 状态按 manager 批量发布。
- 完整测试、iOS build、Catalyst build 和真机 profile 均通过。
