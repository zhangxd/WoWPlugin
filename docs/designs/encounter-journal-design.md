# 冒险指南设计

- 文档类型：设计
- 状态：已落地
- 主题：encounter-journal
- 适用范围：`encounter_journal`、`minimap_button`、`Toolbox.EJ`、冒险指南副本列表入口导航
- 关联模块：`encounter_journal`、`minimap_button`
- 关联文档：
  - `docs/features/encounter-journal-features.md`
  - `docs/specs/encounter-journal-spec.md`
  - `docs/plans/encounter-journal-plan.md`
  - `docs/tests/encounter-journal-test.md`
  - `docs/features/quest-features.md`
  - `docs/Toolbox-addon-design.md`
- 最后更新：2026-04-27

## 1. 背景

- 当前实现里，`encounter_journal` 已经不再承载任务浏览或 Quest Inspector，但历史文档仍把任务能力算在本模块里，导致模块边界与代码现状不一致。
- 需要用当前代码重新收口 `encounter_journal` 的设计，只保留副本列表、详情页与锁定摘要相关能力。
- 2026-04-27 新增已确认需求，并经用户反馈修正落点：在冒险指南副本列表条目右下角提供图钉按钮，点击后打开目标地图并创建系统导航目标，行为接近在地图中点击副本入口图标。
- 2026-04-27 新增已确认交互增强：副本列表单击建立焦点、双击进入副本，图钉按钮支持“焦点 / 悬停显示”与“常驻显示”两种模式，并将现有图钉替换为更高辨识度的高亮版资源。

## 2. 设计目标

- 明确 `encounter_journal` 的真实职责边界。
- 明确 `encounter_journal` 与 `minimap_button`、`Toolbox.EJ` 的协作关系。
- 移除已迁移到 `quest` 模块的任务能力表述，避免后续继续误导实现与评审。
- 增加副本入口导航设计：用 Blizzard 运行时入口数据查找当前 `journalInstanceID` 的入口，并通过系统 waypoint / super tracking 创建导航目标。

## 3. 非目标

- 不描述独立任务界面、任务线浏览或 Quest Inspector 设计。
- 不覆盖与冒险指南无关的 Tooltip、Mover、聊天提示等功能设计。
- 不讨论任务静态数据导出流程本身。
- 不提供副本内部 boss、楼层、门、传送点或路径规划坐标。
- 不维护手写副本入口静态坐标表。

## 4. 方案对比

### 4.1 方案 A：继续把任务能力保留在 `encounter_journal` 文档里

- 做法：维持“冒险指南 + 任务页签 + Quest Inspector”合并描述，只在局部补一句“实现已拆分”。
- 优点：改动少。
- 风险 / 缺点：文档边界仍与代码不一致，后续维护者仍可能把任务改动误投到 `encounter_journal`。

### 4.2 方案 B：按当前模块边界重写 `encounter_journal` 设计

- 做法：把 `encounter_journal` 收敛为副本列表增强、详情页增强和锁定摘要联动；任务能力改由 `quest` 文档承接。
- 优点：与当前代码一致，模块职责清晰，后续文档回写路径稳定。
- 风险 / 缺点：需要同步更新功能、需求、计划、测试和总设计文档。

### 4.3 选型结论

- 选定方案：方案 B。
- 选择原因：这是唯一能让文档边界与当前实现重新对齐的方案。

### 4.4 详情页入口导航方案对比

#### 方案 A：扩展现有 `encounter_journal` 模块副本列表

- 做法：在副本列表条目右下角创建图钉按钮；入口查找与系统 waypoint 调用收口到 `Toolbox.EJ`。
- 优点：不新增模块，不新增存档，目标副本由列表条目直接决定；可复用当前 `EncounterJournal_ListInstances` 后刷新列表行的生命周期。
- 风险 / 缺点：需要在 `Toolbox.EJ` 中补运行时入口查找，且不同副本入口数据覆盖率需要游戏内验证。

#### 方案 B：新建独立地图导航模块

- 做法：新增 `RegisterModule` 模块，专门处理地图入口 pin 与导航。
- 优点：边界独立，后续可扩展为完整地图导航能力。
- 风险 / 缺点：当前需求只要求冒险指南列表图钉，新模块会扩大设置、存档与 TOC 影响面。

#### 方案 C：只做聊天命令或小地图菜单入口

- 做法：不改冒险指南详情页，只通过 slash 或小地图入口触发当前副本导航。
- 优点：UI 挂接风险低。
- 风险 / 缺点：不满足“冒险指南中右下角按钮”的确认需求。

#### 选型结论

- 选定方案：方案 A。
- 选择原因：满足用户修正后的列表条目图钉位置和行为，同时保持现有 `encounter_journal` 模块边界，不引入新模块和新存档。

## 5. 选定方案

### 5.1 模块归属

| 能力 | 落点 | 说明 |
|------|------|------|
| 副本列表“仅坐骑”筛选 | `Toolbox/Modules/EncounterJournal/Shared.lua` + `Toolbox/Modules/EncounterJournal.lua` | 在副本列表界面创建复选框，并在 `EncounterJournal_ListInstances` 后处理当前列表。 |
| 副本列表锁定叠加与 tooltip 详情 | `Toolbox/Modules/EncounterJournal/LockoutOverlay.lua` + `Toolbox.EJ` | 列表行内显示重置时间，悬停补充难度、进度和延长状态。 |
| 副本详情页“仅坐骑”筛选 | `Toolbox/Modules/EncounterJournal/DetailEnhancer.lua` | 仅在掉落页生效，按当前副本的坐骑掉落集合过滤显示。 |
| 副本详情页重置标签 | `Toolbox/Modules/EncounterJournal/DetailEnhancer.lua` + `Toolbox.EJ` | 读取当前选中难度的锁定数据，展示“重置：xx”。 |
| 副本列表图钉导航 | `Toolbox/Modules/EncounterJournal/DetailEnhancer.lua` + `Toolbox.EJ` | 在地下城 / 团队副本列表条目右下角创建图钉按钮；点击后查找该条目副本入口，打开世界地图到入口地图，并设置系统 waypoint / super tracking。 |
| 副本列表焦点 / 双击交互 | `Toolbox/Modules/EncounterJournal/DetailEnhancer.lua` | 在副本列表行上维护当前焦点副本 ID、悬停态与双击判定；焦点或悬停驱动图钉显隐，双击沿用 Blizzard 默认进入行为。 |
| `EJMicroButton` tooltip 锁定摘要 | `Toolbox/Modules/EncounterJournal.lua` | 在右下角微型按钮 tooltip 末尾追加当前锁定摘要。 |
| 小地图“冒险手册”入口摘要 | `Toolbox/Modules/MinimapButton.lua` + `Toolbox.EJ` | 小地图飞出项打开冒险指南，并在 tooltip 中显示同源锁定摘要。 |

### 5.2 内部结构

- `Toolbox/Modules/EncounterJournal.lua`
  负责模块注册、事件入口、刷新调度器与 `EJMicroButton` tooltip hook。
- `Toolbox/Modules/EncounterJournal/Shared.lua`
  负责模块内共享状态、宿主查找与公共工具。
- `Toolbox/Modules/EncounterJournal/DetailEnhancer.lua`
  负责详情页“仅坐骑”筛选、重置标签，以及副本列表图钉 / 焦点 / 双击交互。
- `Toolbox/Modules/EncounterJournal/LockoutOverlay.lua`
  负责副本列表 CD 叠加与 tooltip 详情。

### 5.3 数据与 API

| 数据 / API | 来源 | 用途 |
|------------|------|------|
| `Toolbox.Data.MountDrops` | 静态数据 | 判断副本是否掉落坐骑，并构建详情页“仅坐骑”集合。 |
| `Toolbox.Data.InstanceMapIDs` | 静态数据 | 提供 `journalInstanceID -> mapID` 单向映射，仅作为运行时 API 不可用时的兜底。 |
| `Toolbox.EJ` | 领域对外 API | 提供锁定查询、锁定摘要与坐骑掉落集合查询；锁定匹配优先走 `C_EncounterJournal.GetInstanceForGameMap(mapID)`，其次对齐 `EJ_GetInstanceInfo(journalInstanceID)` 的 mapID；若 SavedInstances 的 mapID 不可判定，则按副本名做兜底匹配。详情页读取当前副本时优先 `EJ_GetCurrentInstance()`，无效时回退 `EncounterJournal.instanceID`。 |
| `GetSavedInstanceInfo` / `GetNumSavedInstances` | WoW 原生 API | 构建列表叠加文本、详情页重置标签与两处锁定摘要；`GetSavedInstanceInfo` 第 14 个返回值按 mapID 处理。 |
| `C_EncounterJournal.GetDungeonEntrancesForMap(uiMapID)` | WoW 原生 API | 运行时查询地图上的副本入口，按 `journalInstanceID` 命中当前详情页副本。 |
| `C_Map.SetUserWaypoint` / `UiMapPoint.CreateFromVector2D` / `C_SuperTrack.SetSuperTrackedUserWaypoint` | WoW 原生 API | 打开入口地图后创建系统用户 waypoint，并启用系统导航追踪。 |

### 5.4 用户可见行为

- 当当前根页签处于地下城或团队副本列表时，列表上方出现“仅坐骑”复选框。
- 勾选后，仅保留当前列表中可掉落坐骑的副本。
- 开启“显示副本 CD”时，列表行内会直接显示重置时间；团队副本同时显示首领进度。
- 鼠标悬停副本列表项时，tooltip 会补充当前角色的锁定难度、进度、精确重置时间和延长状态。
- 在掉落页内可切换“仅坐骑”，只保留当前副本掉落列表中的坐骑物品。
- 详情页标题区会优先显示当前选中难度的重置时间；若当前难度未命中但该副本存在其他难度锁定，则回退显示最近重置时间；若该副本无任何锁定，显示“重置：无”。
- 副本列表条目右下角显示图钉按钮；点击后打开世界地图到入口地图，创建系统用户导航目标并开始追踪。
- 未勾选“定位图标常驻显示”时，只有当前焦点行或当前悬停行显示图钉。
- 勾选“定位图标常驻显示”后，所有可导航列表行都显示图钉。
- 单击某个副本列表行时，该行进入焦点态；双击同一行时进入该副本。
- 图钉资源替换为 Blizzard 已存在的高亮版图标，提高与列表文本、CD 叠加的区分度。
- 若当前副本没有可用入口数据、地图不允许设置 waypoint 或相关 API 不可用，按钮不可用或点击时给出聊天提示，且不抛 Lua 错误。
- 小地图飞出菜单中的“冒险手册”入口和 `EJMicroButton` tooltip 都会显示当前副本锁定摘要。

### 5.5 设置与存档

当前 `encounter_journal` 只使用以下模块存档键：

- `mountFilterEnabled`
- `lockoutOverlayEnabled`
- `detailMountOnlyEnabled`
- `listPinAlwaysVisible`

说明：

- 旧的任务浏览、Quest Inspector、根页签顺序与显隐字段已经迁移到 `quest` 模块或被清理，不再属于 `ToolboxDB.modules.encounter_journal`。
- `listPinAlwaysVisible` 默认值为 `false`；关闭时按“焦点或悬停显示”规则，开启时所有可导航条目常驻显示图钉。

## 6. 影响面

- 数据与存档：
  `ToolboxDB.modules.encounter_journal` 收敛为副本列表和详情页增强专用字段；本轮新增 `listPinAlwaysVisible` 控制图钉是否常驻显示。
- API 与模块边界：
  `encounter_journal` 只消费 `Toolbox.EJ`；任务浏览与任务运行时接口由 `quest` / `Toolbox.Questlines` 承接。副本入口查找与 waypoint 设置作为 `Toolbox.EJ` 的冒险指南领域能力暴露给详情页 UI。
- 文件与目录：
  关键代码文件为 `Toolbox/Modules/EncounterJournal.lua`、`Toolbox/Modules/EncounterJournal/DetailEnhancer.lua`、`Toolbox/Modules/EncounterJournal/LockoutOverlay.lua`、`Toolbox/Modules/MinimapButton.lua`、`Toolbox/Core/API/EncounterJournal.lua`。
- 文档回写：
  需要同步更新 `encounter-journal-features/spec/plan/test`、`quest-*` 文档、`FEATURES.md` 与 `Toolbox-addon-design.md`。

## 7. 风险与回退

- 风险：
  Blizzard 可能调整冒险指南 Frame 名称、函数名或 tooltip 行为，导致 hook 和控件锚点失效。
- 风险：
  锁定信息依赖原生 API，若 API 返回语义变化，列表叠加和摘要文本可能失准。
- 风险：
  `C_EncounterJournal.GetDungeonEntrancesForMap` 的入口覆盖率和 `journalInstanceID` 匹配在部分旧副本或特殊入口上可能不完整。
- 风险：
  `C_Map.CanSetUserWaypointOnMap(uiMapID)` 可能拒绝部分地图，需失败提示而不是报错。
- 回退或缓解方式：
  各子能力均受模块总开关和对应设置控制；若某项能力失效，可单独关闭该子能力而不影响其它模块。

## 8. 验证策略

- 逻辑验证：
  运行 `python tests/run_all.py --ci`，确认自动化校验继续通过。
- 游戏内验证：
  检查副本列表“仅坐骑”、单击焦点、双击进入、列表图钉焦点 / 悬停 / 常驻显示、CD 叠加、tooltip 详情、详情页“仅坐骑”、详情页重置标签、小地图与 `EJMicroButton` 锁定摘要是否均可用。
- 文档验证：
  `encounter-journal-features/spec/plan/test`、`quest-*`、`FEATURES.md` 与 `Toolbox-addon-design.md` 的模块边界必须一致。

## 9. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-12 | 初稿：按当时代码现状归并冒险指南全部能力 |
| 2026-04-15 | 对齐当前实现：移除已拆分到 `quest` 模块的任务能力，重写为副本列表、详情页与锁定摘要设计 |
| 2026-04-21 | 锁定映射策略改为运行时 API 优先（`C_EncounterJournal.GetInstanceForGameMap` + `EJ_GetInstanceInfo` mapID 对齐），`InstanceMapIDs` 仅做单向兜底；当 SavedInstances 的 mapID 不可判定时按副本名兜底匹配；详情页重置时间新增“当前难度未命中时回退可用锁定”规则 |
| 2026-04-27 | 确认副本入口导航方案：不新增模块 / 存档，扩展 `Toolbox.EJ` 查找入口并设置系统 waypoint |
| 2026-04-27 | 按用户反馈修正导航入口落点：从详情页按钮改为副本列表条目右下角图钉 |
| 2026-04-27 | 增补列表交互设计：单击焦点、双击进入、图钉高亮版与 `listPinAlwaysVisible` 设置 |
