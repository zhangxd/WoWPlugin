# 冒险指南需求规格

- 文档类型：需求
- 状态：已完成
- 主题：encounter-journal
- 适用范围：`encounter_journal` 当前副本列表、详情页、锁定摘要与副本列表入口导航增强
- 关联模块：`encounter_journal`、`minimap_button`
- 关联文档：
  - `docs/features/encounter-journal-features.md`
  - `docs/designs/encounter-journal-design.md`
  - `docs/tests/encounter-journal-test.md`
  - `docs/specs/quest-spec.md`
- 最后更新：2026-04-27

## 1. 背景

- `encounter_journal` 相关文档长期沿用了“任务页签仍挂在冒险指南里”的旧表述，但当前代码已经把任务浏览和 Quest Inspector 拆到了独立 `quest` 模块。
- 需要一份只描述当前 `encounter_journal` 真实边界的需求基线，作为后续继续演进副本列表和详情页增强时的验收对照。
- 2026-04-27 用户确认新增“副本列表入口导航”，并在后续反馈中修正落点：图钉按钮应显示在冒险指南地下城 / 团队副本列表条目的右下角，而不是副本详情页；点击后打开世界地图到该副本入口并设置系统导航目标。

## 2. 目标

- 明确 `encounter_journal` 当前已经交付的能力范围。
- 明确哪些入口虽然通过其它模块呈现，但仍属于冒险指南增强能力链路。
- 明确任务相关能力已不再属于本主题，避免后续文档再次漂移。
- 在不新增独立模块的前提下，为当前副本详情页提供一键导航到副本入口的能力。

## 3. 范围

### 3.1 In Scope

- 地下城 / 团队副本列表“仅坐骑”筛选。
- 副本列表锁定信息叠加与悬停详情。
- 副本详情页“仅坐骑”筛选。
- 副本详情页当前难度重置标签。
- 小地图“冒险手册”入口的锁定摘要联动。
- `EJMicroButton` tooltip 锁定摘要联动。
- 副本 / 地下城列表条目右下角图钉按钮：打开目标地图并设置系统用户导航点。

### 3.2 Out of Scope

- 独立任务界面。
- 任务线浏览、任务搜索、任务详情弹框。
- Quest Inspector 设置子页面。
- “任务”小地图入口。
- Tooltip 锚点、窗口拖动、聊天 API 等与冒险指南无关的模块能力。
- 副本内部 boss、楼层、门、传送点或路径规划坐标。
- 手写静态入口坐标表；第一版只使用 Blizzard 运行时入口数据。

## 4. 已确认决策

- 主归属模块为 `encounter_journal`。
- 小地图“冒险手册”入口由 `minimap_button` 呈现，但其锁定摘要仍计入 `encounter_journal` 能力范围。
- 锁定与坐骑掉落相关数据统一由 `Toolbox.EJ` 提供。
- `encounter_journal` 当前只保留副本列表、详情页和锁定摘要相关逻辑；任务能力已经迁移到 `quest` 模块。
- `ToolboxDB.modules.encounter_journal` 当前只保留 `mountFilterEnabled`、`lockoutOverlayEnabled`、`detailMountOnlyEnabled` 等本模块独占字段；旧任务相关键已迁移或清理。
- “列表图钉导航”第一版不新增 SavedVariables 字段，跟随 `encounter_journal` 模块总开关显示与启用。
- 入口数据主来源为 `C_EncounterJournal.GetDungeonEntrancesForMap(uiMapID)`；不手写副本入口坐标。
- 点击按钮后执行“打开世界地图 + 切到入口所在地图 + `C_Map.SetUserWaypoint` + `C_SuperTrack.SetSuperTrackedUserWaypoint(true)`”。
- 找不到入口或当前地图不允许设置 waypoint 时，不报 Lua 错误；按钮置灰或聊天提示说明不可导航。

## 5. 待确认项

- 无。2026-04-27 已确认按本文件“导航入口”规则开动实现。

## 6. 验收标准

1. 在地下城 / 团队副本列表中，用户可以启用“仅坐骑”筛选并看到过滤结果。
2. 在副本列表中，用户可以直接看到当前角色的锁定重置时间；团队副本同时看到进度。
3. 鼠标悬停副本列表项时，用户可以看到更完整的锁定详情。
4. 在副本详情页中，用户可以切换“仅坐骑”并看到当前副本掉落中的坐骑物品。
5. 在副本详情页中，用户可以看到当前所选难度的重置标签。
6. 小地图“冒险手册”入口 tooltip 和 `EJMicroButton` tooltip 都能显示当前副本锁定摘要。
7. `ToolboxDB.modules.encounter_journal` 不再读写任务浏览、Quest Inspector 或根页签排序相关旧键。
8. 在有入口数据的副本 / 地下城列表条目右下角，用户能看到图钉按钮。
9. 点击某个列表条目的图钉按钮后，世界地图打开到该条目副本入口所在地图，并创建系统用户导航目标且开始追踪。
10. 对无入口数据、API 不可用或地图不允许设置导航的副本，插件不抛 Lua 错误，并给出可理解的不可用反馈。

## 7. 实施状态

- 当前状态：已完成
- 下一步：在游戏内补齐副本列表图钉导航手工验证。

## 8. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-12 | 初稿：建立 `encounter_journal` 当时代码对应的需求基线 |
| 2026-04-15 | 对齐当前实现：移除已拆分到 `quest` 模块的任务能力，仅保留副本列表、详情页与锁定摘要范围 |
| 2026-04-27 | 用户确认“开动”：新增副本入口导航需求，选定运行时入口数据与系统 waypoint 方案 |
| 2026-04-27 | 用户修正入口落点：从详情页按钮改为副本列表条目右下角图钉 |
