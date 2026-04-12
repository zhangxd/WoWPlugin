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
- 最后更新：2026-04-13

## 1. 定位

- 本文档用于说明 `encounter_journal` 当前已经实现并可直接使用的能力，面向玩家、需求方和后续维护者阅读。
- 这里描述的是“现在已经能用什么”，不是未来方案，也不是开发接入说明。

## 2. 适用场景

- 想快速找出当前列表里会掉落坐骑的副本。
- 想在冒险指南里直接看到当前角色的副本锁定和重置时间。
- 想在冒险指南里按资料片切换，并在资料片下按“地图任务线”或“任务类型”两条路径浏览任务。
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
- 左侧固定显示资料片列表；选中资料片后，展开 `地图任务线` 与 `任务类型` 两个子入口。
- 进入 `地图任务线` 后，左侧显示当前资料片的地图列表；选中地图后，主区显示任务线单行列表。
- 每条任务线独占一行；点击后在原地展开其任务列表，再次点击折叠；同一时刻只展开一条任务线。
- 进入 `任务类型` 后，左侧显示归并后的类型大类；选中某个类型后，主区直接显示任务列表。
- 任务列表只显示任务名称；鼠标悬停显示 tooltip；点击任务后弹框显示详细信息。
- 任务线名称优先使用运行时 API，拿不到时回退为 `QuestLine #<id>`；静态导出只保留同名 Lua 注释供排查。
- 若任务具备任务线归属，详情弹框会提供“跳转到对应地图 / 任务线”入口。
- 会记住当前资料片、当前模式、当前地图 / 类型大类和当前展开任务线。
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
- `questNavExpansionID`
  记录当前资料片导航选择。
- `questNavModeKey`
  记录当前浏览模式（`地图任务线` / `任务类型`）。
- `questNavSelectedMapID`
  记录地图路径下当前选中的地图。
- `questNavSelectedTypeKey`
  记录类型路径下当前选中的类型大类。
- `questNavExpandedQuestLineID`
  记录地图路径下当前展开的任务线；为 `0` 时表示任务线全部折叠。
- `rootTabOrderIds` / `rootTabHiddenIds`
  记录冒险指南根页签顺序与显隐配置。

## 6. 已知限制

- 副本锁定信息依赖游戏原生 `GetSavedInstanceInfo` API。
- 坐骑筛选依赖静态数据表，若静态数据缺失或过期，结果会受影响。
- 任务页签中的类型信息依赖运行时任务数据，个别任务可能没有可识别类型。
- 任务页签中的资料片导航依赖 `InstanceQuestlines.questLines[*].ExpansionID`；缺失时会回退到未归类资料片名。
- 任务类型视图依赖 `GetQuestTagInfo` 与运行时任务标签；个别任务可能被归入“其它”。
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
| 2026-04-12 | 更新：任务页签改为资料片 / 分类顶部导航，任务详情改为 tooltip + 弹框 |
| 2026-04-13 | 更新：任务页签最终改为左侧资料片树与两个子入口，地图主区采用任务线单展开列表 |
