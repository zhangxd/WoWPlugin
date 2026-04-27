# 冒险指南功能说明

- 文档类型：功能
- 状态：已发布
- 主题：encounter-journal
- 适用范围：`encounter_journal` 当前已落地的副本列表、详情页、入口导航与锁定摘要增强
- 关联模块：`encounter_journal`、`minimap_button`
- 关联文档：
  - `docs/FEATURES.md`
  - `docs/specs/encounter-journal-spec.md`
  - `docs/designs/encounter-journal-design.md`
  - `docs/tests/encounter-journal-test.md`
  - `docs/features/quest-features.md`
- 最后更新：2026-04-27

## 1. 定位

- 本文档只描述 `encounter_journal` 当前已经可直接使用的冒险指南增强能力。
- 当前代码里，任务浏览、任务详情弹框、Quest Inspector 和“任务”入口已经归属独立 `quest` 模块，不再属于 `encounter_journal`。

## 2. 适用场景

- 想在地下城 / 团队副本列表里快速筛出会掉落坐骑的副本。
- 想直接在冒险指南列表里看到当前角色的副本锁定和重置时间。
- 想在副本详情页只看坐骑掉落，并顺手确认当前难度的重置时间。
- 想从冒险指南副本列表直接打开地图，并导航到某个副本入口。
- 想在小地图“冒险手册”入口或右下角 `EJMicroButton` 上直接查看当前副本锁定摘要。

## 3. 当前能力

### 3.1 副本列表增强

- 在地下城 / 团队副本列表顶部提供“仅坐骑”筛选。
- 在副本列表行内显示当前角色的重置时间；团队副本同时显示首领进度。
- 鼠标悬停副本列表项时，可查看更详细的锁定信息，包括难度、进度、精确重置时间和延长状态。

### 3.2 副本详情页增强

- 在掉落页提供“仅坐骑”开关，只显示当前副本掉落中的坐骑物品。
- 在详情页标题区域显示当前所选难度的重置时间；没有锁定时显示“重置：无”。
- 在副本列表条目右下角提供图钉按钮；点击后打开世界地图到该副本入口所在地图，创建系统用户导航点并开始追踪。
- 当 Blizzard 运行时入口数据缺少当前条目的精确 `journalInstanceID` 时，会使用 DB 契约导出的静态入口表补足；例如 `厄运之槌 - 戈多克议会` 不再因只返回聚合入口而提示找不到入口。
- 若当前副本没有可用入口数据，点击后给出不可用提示，不抛 Lua 错误。

### 3.3 外部入口与锁定摘要联动

- 小地图飞出菜单内置“冒险手册”入口，可直接打开冒险指南。
- 小地图“冒险手册”入口 tooltip 会追加当前角色的副本锁定摘要。
- 右下角 `EJMicroButton` tooltip 也会追加同源锁定摘要。

说明：

- 上述外部入口通过 `minimap_button` 或 Blizzard 微型菜单呈现，但锁定摘要的数据与行为仍属于 `encounter_journal` + `Toolbox.EJ` 这一条能力链路。
- 任务浏览相关能力请改看 [quest-features.md](../features/quest-features.md)。

## 4. 入口与使用方式

- 命令：`/toolbox`
  用于打开插件设置页，再进入“冒险指南”模块设置。
- 冒险指南主界面：
  通过游戏内冒险指南打开后，可直接使用副本列表增强、列表图钉导航与详情页增强。
- 小地图按钮：
  悬停小地图按钮后，可从飞出菜单中点击“冒险手册”入口。
- 微型菜单：
  将鼠标悬停到 `EJMicroButton` 时，可查看当前角色的副本锁定摘要。

## 5. 设置项

当前主要设置项位于 `ToolboxDB.modules.encounter_journal`：

- `mountFilterEnabled`
  控制副本列表“仅坐骑”筛选是否启用。
- `lockoutOverlayEnabled`
  控制副本列表 CD 叠加、悬停锁定详情与相关刷新。
- `detailMountOnlyEnabled`
  控制详情页掉落列表中的“仅坐骑”过滤。

## 6. 已知限制

- 副本锁定信息依赖游戏原生 `GetSavedInstanceInfo` API。
- 坐骑筛选依赖静态数据表；若静态数据缺失或过期，结果会受影响。
- 部分增强行为需要 `Blizzard_EncounterJournal` 已加载后才会显示或刷新。
- “导航入口”按冒险指南条目的 `journalInstanceID` 直接读取 DB 导出的 `Toolbox.Data.InstanceEntrances`；静态入口数据采用精确 `areapoi` 优先、缺失时使用 `journalinstanceentrance` 的口径。Blizzard 运行时入口 API 只作为静态表缺失时的兜底；最终仍依赖系统 waypoint API，特殊入口或不允许设置 waypoint 的地图可能无法导航。
- `encounter_journal` 不再承载任务浏览与任务查询能力；这部分能力已经迁移到 `quest` 模块。

## 7. 关联文档

- 功能：
  [quest-features.md](../features/quest-features.md)
- 需求：
  [encounter-journal-spec.md](../specs/encounter-journal-spec.md)
- 设计：
  [encounter-journal-design.md](../designs/encounter-journal-design.md)
- 测试：
  [encounter-journal-test.md](../tests/encounter-journal-test.md)
- 总设计：
  [Toolbox-addon-design.md](../Toolbox-addon-design.md)

## 8. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-12 | 初稿：按当时代码现状整理 `encounter_journal` 已实现能力及其跨模块联动 |
| 2026-04-15 | 对齐当前实现：移除已拆分到 `quest` 模块的任务能力，只保留副本列表、详情页与锁定摘要联动 |
| 2026-04-27 | 新增副本列表图钉导航：打开目标地图并设置系统 waypoint / super tracking |
| 2026-04-27 | 副本入口导航接入 DB 静态入口，补足运行时 API 只返回聚合入口的旧副本分翼 |
| 2026-04-27 | 修正静态入口数据来源优先级：`厄运之槌 - 中心花园` 改用精确 `areapoi` 入口 |
| 2026-04-28 | 修正入口读取优先级：按 `journalInstanceID` 直接读取 DB 静态入口，运行时入口 API 仅作兜底 |
| 2026-04-28 | 修正静态入口目标区域地图：为 `areapoi` 来源补充 `HintUiMapID`，避免点击后打开错误层级地图 |
