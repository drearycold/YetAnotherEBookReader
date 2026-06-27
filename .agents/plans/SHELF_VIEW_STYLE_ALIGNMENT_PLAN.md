# Shelf View UIKit 复刻对齐实施指南

创建日期：2026-06-23
迭代日期：2026-06-27
状态：待实施

## 1. 目标

将现有 SwiftUI `RecentShelfView` 和 `SectionShelfView` 的视觉层复刻为旧
UIKit `ShelfView` 的木质书架样式，同时保留 A21 已完成的数据流、ViewModel
和 SwiftUI 页面结构。

视觉基线：

- 当前问题截图：
  - `/Users/peterlee/git/YetAnotherEBookReader/ipad.png`
  - `/Users/peterlee/git/YetAnotherEBookReader/iphone.png`
- 目标截图：
  - `/Users/peterlee/git/ShelfView-iOS/ipad.png`
  - `/Users/peterlee/git/ShelfView-iOS/iphone.png`
- 目标实现参考：
  - `/Users/peterlee/git/ShelfView-iOS/ShelfView/Classes/Dimens.swift`
  - `/Users/peterlee/git/ShelfView-iOS/ShelfView/Classes/ShelfCellView.swift`
  - `/Users/peterlee/git/ShelfView-iOS/ShelfView/Classes/PlainShelfView.swift`
  - `/Users/peterlee/git/ShelfView-iOS/ShelfView/Classes/SectionShelfCompositionalView.swift`

## 2. 范围与约束

### 范围内

- 直接复用 `Assets.xcassets` 中已有的
  `left/center/right/header/spine/options/icon-book-*`，所有 shelf imageset
  保持原样。
- 新增纯值布局模型、样式常量和状态/进度映射。
- 将 `ShelfBookCard` 改造成固定 cover 区域的 legacy tile。
- 为 Recent shelf 实现连续网格、行尾 filler 和 viewport filler。
- 为 Discover shelf 实现 legacy header、连续横向 shelf row 和 filler。
- 补充布局、状态映射及现有行为回归测试。
- 对 iPhone、iPad、浅色和深色模式进行截图验收。

### 范围外

- 不恢复 `RecentShelfController`、`SectionShelfController` 或 UIKit wrapper。
- 不重新引入外部 `ShelfView` 包。
- 不改变 Realm、下载、阅读进度、Discover 自动填充或 shelf 数据流。
- 不改变 `RecentShelfViewModel`、`SectionShelfViewModel` 的职责边界。
- 不在本轮设计独立暗色木纹主题。

## 3. 锁定的视觉与布局规则

### 3.1 基准尺寸

新增内部 `ShelfLegacyMetrics`：

| 项目 | 值 |
| --- | ---: |
| 基准 tile 宽度 | 150 pt |
| tile 高度 | 200 pt |
| cover 宽度 | 120 pt |
| cover 高度 | 160 pt |
| section header 高度 | 32 pt |
| spine 宽度 | 8 pt |
| progress 宽度/高度 | 36 / 24 pt |
| status 宽度/高度 | 20 / 24 pt |
| selection 宽度/高度 | 32 / 32 pt |
| shelf 背景色 | `#C49E7A` |

列数和真实 tile 宽度复刻 UIKit：

```swift
columnCount = max(1, Int(floor(containerWidth / 150)))
tileWidth = containerWidth / CGFloat(columnCount)
```

因此：

- `393`、`414` pt 宽度为 2 列。
- `744` pt 宽度为 4 列。
- tile 图片允许横向拉伸，cover 始终保持 `120 x 160`。
- 行、列间距均为 `0`。

### 3.2 Tile 类型

新增 `ShelfTileKind`：

- 每行第一个 tile 为 `.left`。
- 每行最后一个 tile 为 `.right`。
- 中间 tile 为 `.center`。
- 单列布局使用 `.left`，背景图横向铺满；不额外引入第四种资产。
- filler tile 参与相同位置计算，保证不完整行最终以 `.right` 收口。

### 3.3 Cover 与叠层

- cover 成功加载时只显示图片，不在 tile 下方显示书名。
- URL 无效或加载失败时，在 cover 区域显示居中的 fallback title。
- cover 左侧覆盖 `spine`。
- progress 位于 cover 右上角，`100` 显示 `FIN`，其余值限制到
  `0...100` 后显示百分比。
- status/refresh 位于 cover 左下角。
- options 位于 cover 右下角。
- edit selection 位于 cover 左上角。
- 不保留当前进度条、标题区和橙色 SF Symbol 状态徽标。

## 4. 分阶段实施

每个阶段应单独提交。只有当前阶段的自动化测试和手动检查通过后，才进入
下一阶段。

### Stage S0：冻结截图基线

目标：建立可重复比较的输入，不修改运行时代码。

实施步骤：

1. 将四张基线截图的设备、方向、外观模式和可见 book 数记录到本实施 PR。
2. 建立目标差异清单：
   - iPhone 从 3 列改为 2 列。
   - iPhone 内容不被 tab bar 截断。
   - iPad viewport 由连续 shelf filler 覆盖。
   - 状态、options、progress 和 selection 回到 cover 四角。
   - light/dark mode 均使用木质资产。

手动检查：

- 四张截图均可打开，方向和设备类别明确。

退出条件：

- PR 或实施记录中存在完整截图基线表和差异清单。
- 本阶段没有 app 源码或项目文件变更。

建议提交：`docs(shelf): freeze UIKit alignment baseline`

### Stage S1：建立纯布局与显示契约

目标：先用纯函数锁定列数、tile 类型、filler 数量和状态文字，不接入视图。

修改文件：

- 新增 `YetAnotherEBookReader/Views/ShelfView/ShelfLegacyStyle.swift`
- 新增 `YetAnotherEBookReaderTests/ShelfLegacyStyleTests.swift`
- 更新 `YetAnotherEBookReader.xcodeproj/project.pbxproj`，注册两个 Swift 文件。

实施步骤：

1. 定义 `ShelfLegacyMetrics`，集中保存第 3 节中的所有尺寸和颜色。
2. 定义 `ShelfTileKind: Equatable`，提供对应资产名：
   `left/center/right`。
3. 定义纯值 `ShelfLegacyLayout`，至少提供：
   - `columnCount(containerWidth:)`
   - `tileWidth(containerWidth:)`
   - `tileKind(index:columnCount:)`
   - `completedTileCount(itemCount:columnCount:)`
   - `viewportTileCount(itemCount:columnCount:viewportHeight:)`
4. `viewportTileCount` 使用以下规则：
   - 内容行数为 `ceil(itemCount / columnCount)`。
   - viewport 行数为 `ceil(viewportHeight / 200)`。
   - 最终行数取二者最大值。
   - 空数据也至少生成一屏 filler，空状态文案后续叠加显示。
5. 定义 `ShelfLegacyPresentation`：
   - `progressLabel(_:)`
   - `statusAssetName(_:)`
   - status asset 名固定为 `icon-book-ready`、`icon-book-noconnect`、
     `icon-book-hasupdate`、`icon-book-downloading`、`icon-book-local` 和
     `icon-book-updating`。
6. 不把布局字段添加到 `ShelfBookItem`；tile 类型和 filler 必须保持为
   view-local 派生数据。

自动化测试：

- 宽度 `149/150/299/300/393/414/744` 的列数边界。
- `393` 和 `414` 为 2 列，`744` 为 4 列。
- 2 列、4 列和单列时的 `.left/.center/.right` 分配。
- `0/1/3/4/5` 个 item 的行尾补齐数量。
- viewport 小于一行、整行和半行时的 filler 行数。
- progress `-1/0/61/100/101` 映射为
  `0%/0%/61%/FIN/FIN`。
- 六个 `ShelfBookStatus` 映射到预期资产名。

验证命令：

```bash
xcodebuild test \
  -project YetAnotherEBookReader.xcodeproj \
  -scheme YetAnotherEBookReader \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/YabrDerivedData \
  -only-testing:YetAnotherEBookReaderTests/ShelfLegacyStyleTests
```

退出条件：

- 所有布局结果可由纯测试验证。
- `ShelfBookCard`、Recent 和 Discover 页面尚未改变。

建议提交：`feat(shelf): add legacy layout contract`

### Stage S2：实现可复用的 shelf tile 外壳

目标：只建立连续木质 tile 和 filler，不迁移 cover/操作叠层。

修改文件：

- `ShelfLegacyStyle.swift`
- 新增 `YetAnotherEBookReader/Views/ShelfView/ShelfLegacyTile.swift`
- 更新 Xcode 项目注册新文件。

实施步骤：

1. 实现 `ShelfLegacyTile`，输入 `kind`、`width` 和可选 content。
2. 背景根据 `ShelfTileKind` 选择图片并拉伸到
   `width x ShelfLegacyMetrics.tileHeight`。
3. content 使用固定 `120 x 160` 区域居中，不随 tile 宽度伸缩。
4. 实现 `ShelfLegacyFillerTile`，只渲染背景且
   `accessibilityHidden(true)`，不生成虚假 book id。
5. 对 tile 和 cover 区域使用稳定 frame，避免图片加载或状态切换改变网格。
6. 添加仅用于开发的 Preview，覆盖 left、center、right、filler 和不同
   tile 宽度；Preview 不引入生产 mock 状态。

验证：

- `ShelfLegacyStyleTests` 继续通过。
- iPhone 宽度下并排 2 个 tile 无缝。
- iPad 宽度下并排 4 个 tile 无缝。
- tile 高度始终为 200 pt，cover 占位始终为 `120 x 160`。

退出条件：

- tile 外壳可独立渲染，但线上 Recent/Discover 仍使用旧卡片。
- filler 无手势、无 accessibility 元素。

建议提交：`feat(shelf): add reusable legacy shelf tile`

### Stage S3：迁移 cover、fallback 与 spine

目标：完成卡片主体，不引入 status/options/edit 操作。

修改文件：

- `YetAnotherEBookReader/Views/ShelfView/ShelfBookCard.swift`
- 可选新增
  `YetAnotherEBookReader/Views/ShelfView/ShelfLegacyCoverView.swift`

实施步骤：

1. 为 `ShelfBookCard` 增加 `tileKind` 和 `tileWidth` 参数。
2. 移除外层固定 `110` 宽度、下方 progress bar 和下方 title。
3. 使用 `ShelfLegacyTile` 包裹 cover。
4. 将 Kingfisher cover 固定为 `120 x 160`，使用 `.fill` 和裁剪，不使用
   12 pt 圆角。
5. 使用明确的 cover load state：
   - `.loading`：保留 cover 占位，可显示 activity indicator。
   - `.success`：显示 cover 和 spine，隐藏 fallback title。
   - `.failure`：隐藏 spine，在 cover 区域显示 title。
6. book id 或 cover URL 改变时重置 load state，避免 SwiftUI 重用导致前一本
   书的成功状态泄漏。
7. URL 无效直接进入 failure；图片请求失败也进入 failure。
8. fallback title 使用最多可读的多行居中文本，限制在 cover bounds 内。
9. cover 成功时覆盖现有 `spine` 资产，leading 对齐、宽 8 pt、高 160 pt。
10. 保留 cover shadow：黑色、radius 10、零 offset、opacity 0.7。

自动化验证：

- 继续运行 `ShelfLegacyStyleTests` 和现有
  `ShelfDisplayModelsTests`。
- 如将 load-state 归约抽成纯类型，为 URL 无效、success、failure 和 URL
  切换增加单元测试。

手动检查：

- 有效 cover：无下方书名，spine 可见。
- 无效 URL：显示 fallback title，spine 不可见。
- 网络加载失败：结果与无效 URL 一致。
- 长标题不越过 cover 边界。

退出条件：

- `ShelfBookCard` 主体与 UIKit cover 几何一致。
- tap、context menu 和 ViewModel 行为尚未改线。

建议提交：`refactor(shelf): align cover with UIKit cell`

### Stage S4：迁移 progress、status、options 与 edit 叠层

目标：复刻 cover 四角控件，并保持所有原有业务回调。

修改文件：

- `ShelfBookCard.swift`
- 必要时新增
  `ShelfLegacyBookActions.swift` 或 view-local action menu。

实施步骤：

1. 将卡片根节点从嵌套 `Button` 改为带 `contentShape` 的 tile 容器，避免在
   外层 Button 中嵌套 options `Menu/Button`。
2. 在非编辑模式显示：
   - 右上 progress badge。
   - 左下 status/refresh 资产。
   - 右下 options 资产。
3. status 图使用 `ShelfLegacyPresentation.statusAssetName`，不再使用 SF
   Symbol、capsule 或圆形橙色 badge。
4. progress badge 使用 UIKit 尺寸、半透明浅灰背景和 8 pt 圆角。
5. options 作为可见主入口，菜单复用现有 actions：
   Details、Refresh、Delete、Goodreads、Douban、Progress History。
6. 保留 context menu 作为辅助入口，但其 action 列表必须调用同一组 closure，
   不复制业务逻辑。
7. 在编辑模式隐藏 status、progress 和 options，左上显示 selection control。
8. selection 图标使用 circle/checkmark.circle；选中状态不能改变 tile 或
   cover 尺寸。
9. 恢复当前声明但未挂接的 `onLongPress` 手势；只调用既有 closure，不新增
   ViewModel 行为。
10. 为所有图片按钮增加 accessibility label、hint 和 selected value。

行为验证：

- 普通 tap 仍调用 `onTap` 一次。
- long press 调用 `onLongPress`，不触发 options。
- options 中每个可用 action 恰好调用一次。
- nil action 不出现在 menu 中。
- 编辑模式 tap 仍经现有 `onTap` 进入选择逻辑。

自动化验证：

```bash
xcodebuild test \
  -project YetAnotherEBookReader.xcodeproj \
  -scheme YetAnotherEBookReader \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/YabrDerivedData \
  -only-testing:YetAnotherEBookReaderTests/ShelfLegacyStyleTests \
  -only-testing:YetAnotherEBookReaderTests/ShelfDisplayModelsTests
```

手动检查：

- 四个角的叠层不重叠。
- options 可点击区域不少于 44 pt，但图片视觉尺寸保持 legacy 值。
- VoiceOver 不把 filler 或 shelf 背景读成控件。

退出条件：

- 单个 `ShelfBookCard` 已完成 UIKit cell 视觉与行为复刻。
- Recent/Discover 尚未切换布局，可单独回滚本阶段。

建议提交：`feat(shelf): restore legacy book overlays`

### Stage S5：切换 Recent 连续网格

目标：将 Recent 从自适应卡片网格改为连续 shelf rows。

修改文件：

- `YetAnotherEBookReader/Views/ShelfView/RecentShelfView.swift`
- `ShelfLegacyStyle.swift`
- `ShelfLegacyTile.swift`

实施步骤：

1. 使用 `GeometryReader` 获取可用 container width 和 viewport height。
2. 通过 `ShelfLegacyLayout` 计算 column count、真实 tile width 和目标
   tile count。
3. 使用固定列数的 `LazyVGrid`：
   - 每列宽度为计算出的 tile width。
   - row/column spacing 均为 0。
   - 不再使用 `.padding(20)`。
4. 将真实 books 和 view-local filler 组合为渲染序列；真实 book identity
   继续使用 `ShelfBookItem.id`，filler 使用独立稳定 identity。
5. tile kind 仅由最终渲染 index 和 column count 计算。
6. 背景改为 legacy `#C49E7A`，不再使用
   `systemGroupedBackground`。
7. 保留 refreshable、navigation title、toolbar、alert、sheet 和 edit toolbar。
8. 空 shelf 仍生成一屏 filler；现有空状态文案以 overlay 方式显示，不占用
   网格布局。
9. 容器宽度变化时重新计算，不把旧 filler 缓存在 ViewModel。

自动化验证：

- 扩充 `ShelfLegacyStyleTests`：
  - 5 本书在 2 列下生成 6 个内容 tile。
  - 5 本书在 4 列下生成 8 个内容 tile。
  - viewport 高度大于内容时继续补完整行。
  - 每行最后一个 filler 为 `.right`。
- 运行 `RecentShelfViewModelTests`，确认没有业务回归。

验证命令：

```bash
xcodebuild test \
  -project YetAnotherEBookReader.xcodeproj \
  -scheme YetAnotherEBookReader \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/YabrDerivedData \
  -only-testing:YetAnotherEBookReaderTests/ShelfLegacyStyleTests \
  -only-testing:YetAnotherEBookReaderTests/RecentShelfViewModelTests
```

手动检查：

- 393/414 pt iPhone portrait 为 2 列。
- 744 pt iPad portrait 为 4 列。
- 每行木纹连续，partial row 以 right tile 结束。
- 旋转或窗口 resize 后列数和 filler 立即重算。

退出条件：

- Recent 主体已切换为 legacy shelf。
- edit、refresh、详情、删除、阅读入口均可用。

建议提交：`feat(shelf): align Recent grid with UIKit shelf`

### Stage S6：处理 Recent safe area、tab bar 与编辑工具栏

目标：独立消除 iPhone 底部截断，避免将 safe-area 修复混入网格算法。

修改文件：

- `RecentShelfView.swift`
- 如需复用，新增小型 `ShelfBottomBar`，但不迁移业务状态。

实施步骤：

1. 使用 SwiftUI safe-area API 获取底部占用，不硬编码设备或 tab bar 高度。
2. 让 shelf 背景延伸到底部，但 scroll content 的最后一行可完整滚动到 tab
   bar 上方。
3. 编辑工具栏使用 `.safeAreaInset(edge: .bottom)` 或等价布局，成为明确的
   content inset，而不是覆盖最后一行。
4. 非编辑模式也保留足够的底部 scroll inset，避免最后一行 cover 被 tab bar
   覆盖。
5. viewport filler 计算使用实际可滚动可见高度，不能把 tab bar 覆盖区重复
   计入。
6. 键盘、sheet 和横竖屏变化不应产生永久额外 padding。

自动化验证：

- 现有 `RecentShelfViewModelTests` 全部通过。
- 布局纯函数继续使用传入 viewport height，不读取全局 screen bounds。

手动检查：

- iPhone portrait 最后一行 cover、status 和 options 均可完整滚动显示。
- 进入/退出 edit mode 时内容不跳到错误 offset。
- iPad 无 tab bar 截断和重复底部空行。

退出条件：

- `iphone.png` 中的底部 cover 截断问题消失。
- 不存在 `UIScreen.main.bounds` 或硬编码 tab bar 高度。

建议提交：`fix(shelf): respect shelf bottom safe area`

### Stage S7：切换 Discover header 与横向 shelf row

目标：只改 Discover 视觉布局，保留 section 数据和 library filter。

修改文件：

- `YetAnotherEBookReader/Views/ShelfView/SectionShelfView.swift`
- 新增 `ShelfLegacySectionHeader.swift`
- 可选新增 `ShelfLegacySectionRow.swift`
- 更新 Xcode 项目注册新增 Swift 文件。

实施步骤：

1. 实现 `ShelfLegacySectionHeader`：
   - 高度固定 32 pt。
   - 现有 `header` 资产使用 stretchable image。
   - 标题居中，左右各 8 pt。
   - 使用旧 UIKit 的 brown shadow 和 1 pt 垂直 offset。
2. 每个 section 由 header + 200 pt shelf row 组成，section 间距为 0。
3. row 使用 container width 计算可见列数和 tile width。
4. 当 book 数少于可见列数时补 filler 到一整行。
5. 当 book 数超过可见列数时使用横向 `ScrollView`：
   - item width 保持当前 container 计算出的 tile width。
   - 第一个 tile 为 `.left`，最后一个真实或 filler tile 为 `.right`。
   - 中间 tile 为 `.center`。
   - 横向 spacing 和 content inset 均为 0。
6. 空 section 仍渲染 header 和一整行 filler；不生成虚假 domain book。
7. 页面不足一屏时，在 section 列表底部增加无标题 filler shelf rows，填满
   viewport；这些行不进入 `displaySections`。
8. 保留 toolbar 中的 Libraries menu、refresh、edit、alert、detail sheet。
9. 保持跨库 Author section 的 id、排序和 book-level library filter 不变。
10. Discover options 只展示当前传入的 actions；不要为缺失的 delete/history
    closure 伪造入口。

自动化验证：

- 为 section row 纯布局增加测试：
  - 1 本书补齐到可见列数。
  - 恰好一屏不多补横向 tile。
  - 超过一屏保持真实数量并正确分配首尾 kind。
  - 页面高度不足时补无标题 viewport rows。
- 运行 `SectionShelfViewModelTests` 和 `ShelfDisplayModelsTests`。

验证命令：

```bash
xcodebuild test \
  -project YetAnotherEBookReader.xcodeproj \
  -scheme YetAnotherEBookReader \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/YabrDerivedData \
  -only-testing:YetAnotherEBookReaderTests/ShelfLegacyStyleTests \
  -only-testing:YetAnotherEBookReaderTests/SectionShelfViewModelTests \
  -only-testing:YetAnotherEBookReaderTests/ShelfDisplayModelsTests
```

手动检查：

- header 图横向拉伸无明显接缝，标题不截断。
- 短 section 铺满宽度，长 section 可连续横向滚动。
- Libraries filter 前后 section 和 books 与改造前一致。
- Author section 仍可合并跨库结果并按 book library 过滤。

退出条件：

- Discover 的 header、row 和 filler 达到 UIKit 目标。
- ViewModel 和 domain model 没有视觉字段或 filler 数据。

建议提交：`feat(shelf): align Discover sections with UIKit shelf`

### Stage S8：状态矩阵与交互回归

目标：覆盖容易在视觉改造中遗漏的数据状态和操作路径。

测试数据矩阵：

- book 数量：`0`、`1`、partial row、exact row、多行。
- cover：有效、空 URL、非法 URL、HTTP 加载失败。
- title：短标题、中文长标题、英文长单词。
- status：全部六个 `ShelfBookStatus`。
- progress：`0`、`61`、`100`。
- edit：未编辑、未选中、已选中、全选、清空。
- section：空、短 section、长 section、多 library、跨库 Author。

自动化验证：

```bash
xcodebuild test \
  -project YetAnotherEBookReader.xcodeproj \
  -scheme YetAnotherEBookReader \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/YabrDerivedData \
  -only-testing:YetAnotherEBookReaderTests/ShelfLegacyStyleTests \
  -only-testing:YetAnotherEBookReaderTests/RecentShelfViewModelTests \
  -only-testing:YetAnotherEBookReaderTests/SectionShelfViewModelTests \
  -only-testing:YetAnotherEBookReaderTests/ShelfDisplayModelsTests
```

交互验收：

1. Recent：打开书、详情、刷新、删除、Goodreads、Douban、历史记录。
2. Recent edit：选择、全选、清空、批量删除、取消确认。
3. Discover：打开详情、刷新、library filter、批量下载、取消确认。
4. pull-to-refresh 后布局不丢失 filler 或 tile kind。
5. cover 异步返回后不会改变 row 高度或滚动位置。

退出条件：

- 聚焦测试全部通过。
- 操作回调与改造前一致，没有双触发。

建议提交：`test(shelf): cover legacy shelf state matrix`

### Stage S9：视觉验收与全量验证

目标：完成设备矩阵比较并确认共享构建无回归。

截图矩阵：

| 设备 | 方向 | 外观 | Recent | Discover |
| --- | --- | --- | --- | --- |
| iPhone | portrait | light | 必测 | 必测 |
| iPhone | portrait | dark | 必测 | 必测 |
| iPhone | landscape | light | 必测 | 抽查 |
| iPad | portrait | light | 必测 | 必测 |
| iPad | portrait | dark | 必测 | 必测 |
| iPad | landscape | light | 抽查 | 抽查 |
| Catalyst | resizable | system | 抽查 | 抽查 |

视觉验收标准：

- iPhone portrait 为 2 列，无 3 列拥挤。
- iPad portrait 按容器宽度得到预期列数，底部无 grouped background 大空白。
- 所有 row 的 left/center/right 木纹连续，无 spacing 或 padding 裂缝。
- cover 为固定 `120 x 160`，不会被 tile 拉伸。
- status 左下、options 右下、progress 右上、selection 左上。
- `100%` 显示 `FIN`。
- 最后一行不被 tab bar 或编辑工具栏覆盖。
- dark mode 仍使用相同木质资产，不回退到纯黑背景。
- 动态字体下 header 和 fallback title 不越界；叠层位置不漂移。

全量验证：

```bash
xcodebuild test \
  -project YetAnotherEBookReader.xcodeproj \
  -scheme YetAnotherEBookReader \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/YabrDerivedData

xcodebuild \
  -project YetAnotherEBookReader.xcodeproj \
  -scheme YetAnotherEBookReader-Catalyst \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  build
```

静态检查：

```bash
rg 'systemGroupedBackground|secondarySystemGroupedBackground' \
  YetAnotherEBookReader/Views/ShelfView

rg '110|160|adaptive\\(' \
  YetAnotherEBookReader/Views/ShelfView

rg 'import RealmSwift' \
  YetAnotherEBookReader/Views/ShelfView
```

检查解释：

- 前两条允许命中非目标代码，但每个命中都需确认不是旧卡片布局残留。
- Realm 检查应无新增命中。

退出条件：

- 全量 iOS tests 和 Catalyst build 通过。
- 新截图与 UIKit 目标逐项比较完成。
- 将最终测试数、截图路径、已知视觉差异更新到
  `.agents/memory-bank/activeContext.md`。

建议提交：`docs(shelf): record UIKit alignment verification`

## 5. 阶段依赖与回滚边界

```text
S0 baseline
  -> S1 pure contract
  -> S2 tile shell
  -> S3 cover
  -> S4 overlays/actions
  -> S5 Recent grid
  -> S6 Recent safe area
  -> S7 Discover sections
  -> S8 regression matrix
  -> S9 final verification
```

- S2 依赖 S1 的纯布局和 asset name 映射。
- S3、S4 只影响共享 card，可在不回滚布局契约的情况下单独回滚。
- S5 和 S7 分别切换 Recent/Discover，可分开发布和回滚。
- S6 必须在 S5 后执行，但不依赖 Discover。
- 任何阶段失败时，不把 filler、tile kind 或资产名下沉到 ViewModel 规避问题。

## 6. 风险与防护

### 图片异步状态泄漏

风险：SwiftUI 重用 view 时，前一本书的 cover success 状态可能污染新 book。

防护：以 book id/cover URL 重置 load state，并测试 URL 切换。

### 嵌套交互冲突

风险：tile 外层 Button 与 options Menu 嵌套会导致重复触发或无效点击。

防护：根节点使用手势和 `contentShape`，options 保持独立 control。

### Filler 污染业务层

风险：把 filler 伪装成 `ShelfBookItem` 会进入选择、下载或 diff 逻辑。

防护：使用 view-local render item，filler 无 book id、手势和 accessibility。

### Safe area 重复计算

风险：GeometryReader、ScrollView 和 tab bar 同时增加 inset，形成多余空行。

防护：网格算法只接收实际 viewport height，底部 inset 由一个容器统一负责。

### Catalyst 伸缩异常

风险：窗口宽度大时列数和 raster asset 拉伸出现接缝。

防护：列数和 tile width 实时由容器计算；S9 执行 Catalyst 构建和窗口伸缩
抽查。

## 7. 完成定义

仅当以下条件全部满足，Shelf View UIKit 复刻才算完成：

- S0-S9 每阶段退出条件均满足。
- Recent 和 Discover 均未恢复 UIKit controller 或外部依赖。
- 纯布局、ViewModel 和显示模型聚焦测试通过。
- 全量 iOS tests 与 Catalyst build 通过，或明确记录与本改造无关的既有阻塞。
- iPhone/iPad light/dark 截图矩阵完成。
- 当前截图中的 3 列拥挤、底部截断、iPad 大空白和错误徽标位置均消失。
- `activeContext.md` 记录最终实现、测试结果和剩余差异。
