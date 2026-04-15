# 冒险指南设计

- 文档类型：设计
- 状态：已落地
- 主题：encounter-journal
- 适用范围：`encounter_journal`、`minimap_button`、`Toolbox.EJ`、`Toolbox.Questlines`
- 关联模块：`encounter_journal`、`minimap_button`
- 关联文档：
  - `docs/features/encounter-journal-features.md`
  - `docs/specs/encounter-journal-spec.md`
  - `docs/plans/encounter-journal-plan.md`
  - `docs/tests/encounter-journal-test.md`
  - `docs/FEATURES.md`
  - `docs/Toolbox-addon-design.md`
- 最后更新：2026-04-15

## 1. 背景

- 当前冒险指南相关能力已经落在代码中，但说明分散在 `FEATURES.md`、`Toolbox-addon-design.md` 和多份历史规格/计划文档里，且存在与现有代码不一致的表述。
- 当前实现已经覆盖“副本列表”“副本详情页”“任务页签”“小地图与微型按钮联动”四类场景，需要一份按代码现状收口的总设计文档。
- 本文以当前仓库代码为唯一事实来源，对现有冒险指南能力做统一设计说明，不再沿用旧模块拆分和旧数据链路表述。

## 2. 设计目标

- 用一份文档完整描述当前冒险指南相关能力、模块归属、数据来源和设置边界。
- 对齐当前代码实现，避免继续把已合并到 `encounter_journal` 的能力写成独立模块或独立子专题文档。
- 为 [FEATURES.md](../FEATURES.md) 和 [Toolbox-addon-design.md](../Toolbox-addon-design.md) 提供统一上游依据。

## 3. 非目标

- 不描述尚未落地的未来功能。
- 不覆盖与冒险指南无关的 Tooltip、Mover、聊天提示等功能设计。
- 不保留历史实现阶段的逐步计划细节；这些内容不再作为当前设计事实来源。
- 不再为 `encounter_journal` 下的导航、名称来源、测试补充等子专题单独维护并行设计文档。

## 4. 方案对比

### 4.1 方案 A：按子功能分散维护

- 做法：继续分别维护“仅坐骑”“锁定摘要”“任务页签”“小地图入口”等多份文档。
- 优点：单篇文档短，局部修改成本低。
- 风险 / 缺点：容易与代码现状脱节，也容易重复解释同一数据来源和模块边界。

### 4.2 方案 B：按代码现状合并为一份总设计

- 做法：以当前代码实现为准，统一描述 `encounter_journal`、`minimap_button`、`Toolbox.EJ`、`Toolbox.Questlines` 之间的协作。
- 优点：模块归属、数据来源、用户可见功能都能一次讲清，入口文档也能统一引用。
- 风险 / 缺点：单篇文档更长，需要控制层次与边界。

### 4.3 选型结论

- 选定方案：方案 B。
- 选择原因：用户要求“生成冒险指南所有功能的文档，并对齐现有代码”，因此必须由一份总设计统一收口，不能继续依赖分散历史文档。

## 5. 选定方案

### 5.1 功能范围

当前冒险指南设计覆盖以下能力：

1. 副本列表中的“仅坐骑”筛选。
2. 副本列表中的锁定信息叠加显示与悬停详情。
3. 副本详情页掉落列表中的“仅坐骑”筛选。
4. 副本详情页当前难度的重置时间标签。
5. 冒险指南根页中的“任务”页签，以及左侧 `资料片 -> 地图任务线 / 任务类型` 树导航。
6. 冒险指南根页签顺序与显隐设置。
7. 小地图悬停菜单中的“冒险手册”入口与锁定摘要。
8. `EJMicroButton` tooltip 末尾的当前副本锁定摘要。

### 5.2 模块归属

| 能力 | 落点 | 说明 |
|------|------|------|
| 副本列表“仅坐骑”筛选 | `Toolbox/Modules/EncounterJournal.lua` | 在副本列表界面创建复选框，并在 `EncounterJournal_ListInstances` 后处理当前列表。 |
| 副本列表锁定叠加与 tooltip 详情 | `Toolbox/Modules/EncounterJournal.lua` + `Toolbox.EJ` | 列表行内显示重置时间，悬停补充难度、进度和延长状态。 |
| 副本详情页“仅坐骑”筛选 | `Toolbox/Modules/EncounterJournal.lua` | 仅在掉落页生效，按当前副本的坐骑掉落集合过滤显示。 |
| 副本详情页重置标签 | `Toolbox/Modules/EncounterJournal.lua` + `Toolbox.EJ` | 读取当前所选难度的锁定数据，展示“重置：xx”。 |
| 任务页签与导航模型 | `Toolbox/Modules/EncounterJournal.lua` + `Toolbox.Questlines` | 模块负责左侧资料片树、地图主区折叠列表、类型任务列表与详情弹框；领域 API 负责任务导航模型、资料片归属和运行时字段。 |
| 任务运行时模型 | `Toolbox/Core/API/QuestlineProgress.lua` | 负责静态结构缓存、资料片导航模型、任务日志枚举、任务详情和任务进度聚合。 |
| 副本锁定查询与摘要拼装 | `Toolbox/Core/API/EncounterJournal.lua` | 负责当前角色副本锁定汇总、难度匹配、坐骑掉落集合和 tooltip 文本拼装。 |
| 小地图“冒险手册”入口 | `Toolbox/Modules/MinimapButton.lua` | 内置飞出项，点击后加载并打开 `Blizzard_EncounterJournal`。 |
| `EJMicroButton` tooltip 锁定摘要 | `Toolbox/Modules/EncounterJournal.lua` | 在右下角微型按钮 tooltip 末尾追加当前锁定摘要，与小地图摘要同源。 |

#### 5.2.1 已确认的内部结构重构方向

- `encounter_journal` 继续作为**单模块能力边界**存在，不拆成新的 `RegisterModule`。
- 允许将当前单文件实现重构为 `Toolbox/Modules/EncounterJournal/` 下的多个**私有实现文件**，并通过 `Toolbox/Toolbox.toc` 明确加载顺序。
- 推荐内部职责拆分如下：
  - `EncounterJournal.lua`：模块注册、事件入口、总协调。
  - `EncounterJournal/QuestNavigation.lua`：任务页签主对象与外部入口。
  - `EncounterJournal/QuestNavigationView.lua`：任务页签 widgets、左树、主区、breadcrumb、popup 渲染。
  - `EncounterJournal/QuestNavigationState.lua`：`questNav*` 状态归一化与存档读写。
  - `EncounterJournal/LockoutOverlay.lua`：副本列表 CD 叠加与相关 tooltip。
  - `EncounterJournal/DetailEnhancer.lua`：详情页“仅坐骑”和重置时间标签。
- 该重构属于**纯结构优化**，不改变现有玩家可见行为，也不改变 `Toolbox.EJ`、`Toolbox.Questlines` 的对外契约。

### 5.3 数据来源

| 数据 | 来源 | 用途 |
|------|------|------|
| 坐骑掉落映射 | `Toolbox.Data.MountDrops` | 判断某个冒险指南副本是否存在坐骑掉落，并构建详情页“仅坐骑”物品集合。 |
| 冒险指南副本到地图 ID 映射 | `Toolbox.Data.InstanceMapIDs` | 将 `GetSavedInstanceInfo` 返回的实例 ID 反查为 `journalInstanceID`。 |
| 任务线静态结构 | `Toolbox.Data.InstanceQuestlines` | 提供任务线、地图、资料片归属与任务链路等稳定 DB 结构；`questLines` 块保留 `ID` / `UiMapID` / `ExpansionID`，任务线名称只以 Lua 尾注释保留。 |
| 任务类型名称 | `C_QuestLog.GetQuestTagInfo` | 在构建类型索引时，按代表任务读取运行时 `tagName`；失败时回退到 `Unknown Type (%s)`。 |
| 角色副本锁定 | `GetNumSavedInstances` / `GetSavedInstanceInfo` | 生成副本列表叠加文案、详情页重置标签和两处锁定摘要。 |
| 任务日志运行时字段 | `C_QuestLog.*` / 兼容 API | 提供任务名、任务状态、可交付状态、任务类型、任务类型显示名、当前任务列表等运行时信息。 |
| 任务线运行时名称 | `C_QuestLine.GetQuestLineInfo` | 通过代表任务解析任务线运行时名称；失败时回退到 `QuestLine #<id>`。 |

### 5.4 用户可见行为

#### 5.4.1 副本列表

- 当当前根页签处于地下城或团队副本列表时，列表上方出现“仅坐骑”复选框。
- 勾选后，仅保留当前列表中可掉落坐骑的副本。
- 开启“显示副本 CD”时，列表行内会直接显示重置时间；团队副本同时显示首领进度。
- 鼠标悬停副本列表项时，tooltip 会补充当前角色的锁定难度、进度、精确重置时间和延长状态。

#### 5.4.2 副本详情页

- 在掉落页内可切换“仅坐骑”，只保留当前副本掉落列表中的坐骑物品。
- 详情页标题区会显示当前选中难度的重置时间；若当前难度没有锁定，则显示“重置：无”。

#### 5.4.3 任务页签

- 在冒险指南根页签中新增“任务”页签。
- 左侧第一层固定为资料片列表；选中某个资料片后，展开两个子入口：`地图任务线` 与 `任务类型`。
- `地图任务线` 入口下显示当前资料片的地图列表；选中地图后，主区显示任务线单行列表。
- 地图主区中的每条任务线独占一行；点击后在原地展开其任务列表，再次点击折叠；同一时刻只展开一条任务线。
- `任务类型` 入口下显示归并后的任务类型大类；选中某个类型后，主区直接显示任务列表，不再增加任务线中间层。
- 任务线名称优先使用运行时 API，失败时回退为 `QuestLine #<id>`。
- `Toolbox.Data.InstanceQuestlines.questLines` 不再导出结构化 `Name_lang` 字段，只保留 Lua 注释供人工排查。
- 任务列表只显示任务名称；鼠标悬停显示 tooltip；点击后显示任务详情弹框，不再在主界面右侧内嵌详情文本。
- 当用户在任务页签中选中具体任务时，`Toolbox.Questlines` 允许按 `questID` 异步请求任务缓存，并将当前可获取到的任务详情分段输出到聊天框，作为任务运行时字段排查入口。
- 上述聊天调试输出只读取异步任务 API 返回的数据，不读取 `Toolbox.Data.InstanceQuestlines` 等静态数据做补齐；资料片字段仅输出 API 原始返回中可直接取得的相近字段，不再用静态任务线归属回填“资料片”。
- 若任务具备任务线归属，详情弹框提供“跳转到对应地图 / 任务线”的入口，并自动展开目标任务线。
- 模块记忆当前资料片、当前模式、当前地图 / 类型大类和当前展开任务线；旧的顶部分类与更早的三视图状态已迁移并清理。
- 设置页提供冒险指南主页页签顺序与显隐编辑器，支持拖拽排序、即时显隐和恢复默认顺序。

#### 5.4.4 外部入口与摘要

- 小地图按钮飞出菜单内置“冒险手册”入口，点击可直接打开冒险指南。
- 小地图“冒险手册”入口 tooltip 末尾会追加当前角色副本锁定摘要。
- 右下角 `EJMicroButton` 的 tooltip 也会追加同源锁定摘要。

### 5.5 设置与存档

冒险指南功能统一落在 `ToolboxDB.modules.encounter_journal`，当前主要字段包括：

- `mountFilterEnabled`
- `lockoutOverlayEnabled`
- `detailMountOnlyEnabled`
- `questlineTreeEnabled`
- `questNavExpansionID`
- `questNavModeKey`
- `questNavSelectedMapID`
- `questNavSelectedTypeKey`
- `questNavExpandedQuestLineID`
- `rootTabOrderIds`
- `rootTabHiddenIds`

这些字段分别对应列表筛选、锁定叠加、详情页过滤、任务页签开关、新左树状态与根页签排序设置。旧的 `questView*`、`questNavCategoryKey`、`questNavSelectedQuestLineID`、`questlineTreeCollapsed`、`questlineTreeSelection`、`ej_mount_filter` 与 `dungeon_raid_directory` 相关存档已迁移或清理，不再作为当前设计的一部分。

## 6. 影响面

- 数据与存档：
  `ToolboxDB.modules.encounter_journal` 保存所有冒险指南设置与浏览状态；`minimap_button` 仅保存小地图按钮与飞出菜单本身的配置。
- API 与模块边界：
  `encounter_journal` 负责界面、交互与 hook，`Toolbox.EJ` 负责锁定与坐骑查询，`Toolbox.Questlines` 负责任务模型与运行时字段。
- 文件与目录：
  关键代码文件为 `Toolbox/Modules/EncounterJournal.lua`、`Toolbox/Modules/MinimapButton.lua`、`Toolbox/Core/API/EncounterJournal.lua`、`Toolbox/Core/API/QuestlineProgress.lua`。
- 文档回写：
  [FEATURES.md](../FEATURES.md) 只保留产品向能力说明，[Toolbox-addon-design.md](../Toolbox-addon-design.md) 只保留长期架构与模块映射；`encounter_journal` 的后续子专题统一回写本设计文档，不再拆分新的 `encounter-journal-*.md` 设计文件。

## 7. 风险与回退

- 风险：
  Blizzard 可能调整冒险指南 Frame 名称、函数名或 tooltip 行为，导致 hook 和控件锚点失效。
- 风险：
  静态数据表与运行时 API 若出现版本偏差，会影响坐骑筛选和任务线展示完整性。
- 风险：
  任务页签依赖 `C_QuestLog` 运行时数据与导出的 `ExpansionID` 字段，个别任务或任务线可能出现“未知类型”或“未归类资料片”回退。
- 回退或缓解方式：
  各子能力均受模块总开关和对应设置控制；当某项能力失效时，可单独关闭该子开关而不影响其它冒险指南增强。

## 8. 验证策略

- 逻辑验证：
  运行 `python tests/run_all.py --ci`，确认静态校验与 `tests/logic/spec` 中的冒险指南相关用例通过。
- 游戏内验证：
  检查副本列表“仅坐骑”、CD 叠加、tooltip 详情、详情页“仅坐骑”、详情页重置标签、任务页签左侧资料片树、资料片下两个入口、地图列表、任务线折叠展开、类型任务列表、tooltip、详情弹框、详情回跳、根页签排序设置、小地图与 `EJMicroButton` 锁定摘要是否均可用。
- 文档验证：
  `FEATURES.md`、`Toolbox-addon-design.md` 与本文件的模块归属、数据来源和能力边界必须保持一致。

## 9. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-12 | 首版：按当前代码现状归并冒险指南全部能力，统一模块归属、数据来源与入口说明 |
| 2026-04-12 | 补充：任务页签中的任务线名称改为运行时 API 优先、静态名称兜底 |
| 2026-04-12 | 调整：`InstanceQuestlines.questLines` 不再导出 `Name_lang` 字段，只保留 Lua 注释；运行时失败回退为 `QuestLine #<id>` |
| 2026-04-12 | 更新：任务页签重构为“资料片 -> 分类 -> 任务线 -> 任务”导航，详情改为 tooltip + 点击弹框 |
| 2026-04-13 | 更新：任务页签最终改为左侧资料片树，资料片下收纳“地图任务线 / 任务类型”，地图主区使用任务线单展开列表 |
| 2026-04-13 | 文档收口：`encounter_journal` 的导航与名称来源子专题并回主设计文档，后续不再维护平行子设计文件 |
| 2026-04-14 | 补充：确认 `EncounterJournal.lua` 可按私有实现文件拆分，模块边界、存档键与对外 API 保持不变 |
| 2026-04-14 | 补充：确认任务页签选中任务时可调用 `Toolbox.Questlines` 的异步任务详情输出能力，输出落到聊天框用于运行时排查 |
| 2026-04-14 | 调整：任务页签聊天调试输出改为仅消费异步任务 API 返回字段，不再读取静态任务线数据补齐资料片等归属信息 |
| 2026-04-15 | 并回：新增“任务详情查询”独立设置子页面设计，采用 `QuestID + 运行时 API + 可复制文本结果区` 方案 |

## 10. 2026-04-15 任务详情查询独立子页面设计

### 10.1 背景

- 现有 `Toolbox.Questlines` 已具备较多任务运行时查询与异步加载能力，但面向玩家可见的查询入口仍只有任务页签内的浏览与聊天调试输出。
- 用户需要一个放在设置中的独立页面，用于输入 `QuestID` 后直接查看任务详细信息，并且结果文本必须可复制。

### 10.2 方案对比

#### 方案 A：把查询区塞进现有 `encounter_journal` 设置页

- 做法：继续沿用当前模块单页设置结构，在原页面底部增加输入框、按钮和结果区。
- 优点：对 `SettingsHost` 改动最小。
- 风险 / 缺点：结果文本会很长，和现有副本筛选、任务页签设置混在一起后可读性差，也不符合“新增一个页面”的用户要求。

#### 方案 B：在 `encounter_journal` 下新增独立设置子页面

- 做法：扩展 `SettingsHost` 页面注册模型，使同一模块可注册多个真实子页面；`encounter_journal` 保留现有主设置页，并新增“任务详情查询”页面。
- 优点：页面职责清晰，长文本结果区有独立空间，符合用户预期，也便于后续继续增加开发型查询工具。
- 风险 / 缺点：需要扩展现有设置页注册协议，而不是只改模块内部绘制代码。

#### 方案 C：仅保留聊天输出

- 做法：继续复用当前聊天调试接口，不新增设置页结果区。
- 优点：实现最省事。
- 风险 / 缺点：不满足“下方展示”和“文本可复制”的核心需求。

### 10.3 选型结论

- 选定方案：方案 B。
- 选择原因：这是唯一同时满足“独立页面”“长文本可复制”“不新增模块”“仅运行时 API”四项约束的方案。

### 10.4 选定方案

#### 10.4.1 页面归属与入口

- 页面仍归属 `encounter_journal`，不新增 `RegisterModule`。
- 在设置左侧导航中，`encounter_journal` 除现有主页面外，再注册一个“任务详情查询”真实子页面。
- 该页面只作为设置里的开发/查询工具，不新增菜单按钮、飞出项或 slash 命令。

#### 10.4.2 数据链路

- 查询主键固定为 `QuestID`。
- 任务详情与任务线信息仅通过运行时 API 获取，不使用 `Toolbox.Data.InstanceQuestlines` 或其它静态数据补齐。
- 推荐由 `Toolbox.Questlines` 暴露一个新的结构化快照接口，统一汇总：
  - 任务基础字段
  - 日志状态
  - 任务标签与类型
  - 地图与父地图链
  - 目标列表
  - 描述/任务文本
  - `C_QuestLine.GetQuestLineInfo` 可读出的任务线字段
- 若任务缓存未就绪，则由 `Toolbox.Questlines` 统一处理 `C_QuestLog.RequestLoadQuestByID` 和 `QUEST_DATA_LOAD_RESULT`，并在结果可读后回调页面刷新。

#### 10.4.3 UI 结构

- 页面顶部：说明文字，强调输入的是 `QuestID`。
- 中部：数字输入框 + 查询按钮。
- 下部：带滚动条的多行 `EditBox` 结果区，用户可直接选中文本并复制。
- 结果格式：一行一个字段，统一为 `字段名: 字段值`。
- 对于列表或嵌套表，采用扁平化键路径，例如：
  - `questLine.questLineID: 12345`
  - `objectives[1].text: ...`
  - `parentMaps[2].name: ...`

#### 10.4.4 存档

- 数据落在 `ToolboxDB.modules.encounter_journal`。
- 本轮仅计划新增轻量字段，例如：
  - `questInspectorLastQuestID`
- 若后续需要页面展示偏好，也继续落在同一模块键下。

### 10.5 影响面

- 数据与存档：
  `ToolboxDB.modules.encounter_journal` 新增任务详情查询页面专属键。
- API：
  `Toolbox.Questlines` 需要新增“生成结构化任务详情快照”与“异步请求后刷新页面”的调用面；页面代码不直接拼装底层 API。
- 文件与目录：
  预计主要影响 `Toolbox/UI/SettingsHost.lua`、`Toolbox/Modules/EncounterJournal.lua`、`Toolbox/Core/API/QuestlineProgress.lua`、`Toolbox/Core/Foundation/Config.lua`、`Toolbox/Core/Foundation/Locales.lua`。
- 文档回写：
  功能落地后需回写 `docs/features/encounter-journal-features.md` 与 `docs/Toolbox-addon-design.md`。

### 10.6 风险与回退

- 风险：
  部分任务字段依赖异步缓存；首次查询时可能先看到不完整结果，随后刷新补齐。
- 风险：
  运行时 API 对个别任务返回字段不全，结果区需要明确展示“不可用”，而不是伪造值。
- 回退方式：
  若页面注册模型扩展带来问题，可暂时只保留 `encounter_journal` 主页面不注册该子页面，并保留 `Toolbox.Questlines` 结构化快照接口供后续恢复。

### 10.7 验证策略

- 游戏内验证：
  打开设置，确认 `encounter_journal` 下新增“任务详情查询”页面；输入已知 QuestID，检查结果区是否可复制、是否会在异步加载后自动刷新。
- 稳定性验证：
  对非法 QuestID、空输入、任务数据加载失败场景验证页面提示，不出现 Lua 报错。
- 分层验证：
  确认任务数据采集逻辑集中在 `Toolbox.Questlines`，页面层只负责输入、触发和展示。
