# 冒险指南功能说明

- 文档类型：功能
- 状态：已发布
- 主题：encounter-journal
- 适用范围：`encounter_journal` 及其相关联动能力
- 关联模块：`encounter_journal`、`minimap_button`
- 关联文档：
  - `docs/FEATURES.md`
  - `docs/specs/encounter-journal-spec.md`
  - `docs/designs/encounter-journal-design.md`
  - `docs/tests/encounter-journal-test.md`
- 最后更新：2026-04-12

## 1. 定位

- 本文档用于说明 `encounter_journal` 当前已经实现并可直接使用的能力，面向玩家、需求方和后续维护者阅读。
- 这里描述的是“现在已经能用什么”，不是未来方案，也不是开发接入说明。

## 2. 适用场景

- 想快速找出当前列表里会掉落坐骑的副本。
- 想在冒险指南里直接看到当前角色的副本锁定和重置时间。
- 想在冒险指南里按任务状态、任务类型或地图浏览任务线。
- 想通过小地图入口或微型菜单更快进入冒险指南，并顺手查看当前锁定摘要。

## 3. 当前能力

### 3.1 副本列表增强

- 在地下城 / 团队副本列表顶部提供“仅坐骑”筛选。
- 在副本列表行内显示当前角色的重置时间；团队副本同时显示首领进度。
- 鼠标悬停副本列表项时，可查看更详细的锁定信息，包括难度、进度、精确重置时间和延长状态。

### 3.2 副本详情页增强

- 在掉落页提供“仅坐骑”开关，只显示当前副本掉落中的坐骑物品。
- 在详情页标题区域显示当前所选难度的重置时间；没有锁定时显示“重置：无”。

### 3.3 任务页签增强

- 在冒险指南根页签中增加“任务”页签。
- 支持 `状态 / 类型 / 地图` 三视图。
- `状态` 视图左侧显示当前任务日志中的当前任务，右侧联动显示所属完整任务线；没有任务线映射时回退为任务详情。
- 任务线名称优先使用运行时 API，拿不到时回退为 `QuestLine #<id>`；静态导出只保留同名 Lua 注释供排查。
- 会记住视图模式、选中项和部分树节点折叠状态。
- 设置页支持调整冒险指南根页签顺序与显隐。

### 3.4 相关入口与联动

- 小地图飞出菜单内置“冒险手册”入口，可直接打开冒险指南。
- 小地图“冒险手册”入口的 tooltip 会追加当前副本锁定摘要。
- 右下角 `EJMicroButton` 的 tooltip 也会追加同源锁定摘要。

说明：

- 上述入口与摘要能力虽然会通过 `minimap_button` 或 `EJMicroButton` 呈现，但其数据与行为仍属于冒险指南整体能力链路的一部分。
- 主归属模块为 `encounter_journal`，协作模块为 `minimap_button`，协作 API 为 `Toolbox.EJ`。

## 4. 入口与使用方式

- 命令：`/toolbox`
  用于打开插件设置页，再进入“冒险指南”模块设置。
- 冒险指南主界面：
  通过游戏内冒险指南打开后，可直接使用副本列表增强、详情页增强和任务页签。
- 小地图按钮：
  悬停小地图按钮后，可从飞出菜单中点击“冒险手册”入口。
- 微型菜单：
  将鼠标悬停到 `EJMicroButton` 时，可查看当前角色的副本锁定摘要。

## 5. 设置项

当前主要设置项位于 `ToolboxDB.modules.encounter_journal`：

- `mountFilterEnabled`
  控制副本列表“仅坐骑”筛选是否启用。
- `lockoutOverlayEnabled`
  控制副本列表 CD 叠加与相关锁定刷新。
- `detailMountOnlyEnabled`
  控制详情页掉落列表中的“仅坐骑”过滤。
- `questlineTreeEnabled`
  控制任务页签总开关。
- `questlineTreeCollapsed`
  记录树节点折叠状态。
- `questlineTreeSelection`
  记录任务页签左树和右侧内容区的选择状态。
- `questViewMode`
  记录当前三视图模式。
- `questViewSelectedMapID` / `questViewSelectedTypeID` / `questViewSelectedQuestLineID` / `questViewSelectedQuestID`
  记录任务页签的已选中对象。
- `rootTabOrderIds` / `rootTabHiddenIds`
  记录冒险指南根页签顺序与显隐配置。

## 6. 已知限制

- 副本锁定信息依赖游戏原生 `GetSavedInstanceInfo` API。
- 坐骑筛选依赖静态数据表，若静态数据缺失或过期，结果会受影响。
- 任务页签中的类型信息依赖运行时任务数据，个别任务可能没有可识别类型。
- 部分当前任务可能没有任务线映射，此时状态视图会回退为任务详情。
- 部分功能需要 `Blizzard_EncounterJournal` 已加载后才会显示或刷新。

## 7. 关联文档

- 需求：`docs/specs/encounter-journal-spec.md`
- 设计：`docs/designs/encounter-journal-design.md`
- 计划：`docs/plans/encounter-journal-plan.md`
- 测试：`docs/tests/encounter-journal-test.md`
- 总设计：`docs/Toolbox-addon-design.md`
- 全局入口：`docs/FEATURES.md`

## 8. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-12 | 初稿：按当前代码现状整理 `encounter_journal` 已实现能力及其跨模块联动 |
| 2026-04-12 | 补充：任务页签中的任务线名称来源改为运行时 API 优先、静态名称兜底 |
| 2026-04-12 | 调整：任务线名称的导出字段移除，仅保留 Lua 注释；显示失败时回退为 `QuestLine #<id>` |
