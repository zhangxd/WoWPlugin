# 冒险指南测试基线

- 文档类型：测试
- 状态：已通过
- 主题：encounter-journal
- 适用范围：`encounter_journal` 当前副本列表、详情页、入口导航与锁定摘要增强的自动化与手工验证基线
- 关联模块：`encounter_journal`、`minimap_button`
- 关联文档：
  - `docs/specs/encounter-journal-spec.md`
  - `docs/designs/encounter-journal-design.md`
  - `docs/plans/encounter-journal-plan.md`
- 最后更新：2026-04-27

## 1. 测试背景

- 本文档用于记录 `encounter_journal` 当前真实边界下的验证基线。
- 当前测试范围覆盖副本列表、详情页、入口导航与锁定摘要能力，不再覆盖已拆到 `quest` 模块的任务浏览能力。

## 2. 测试范围

- In Scope：
  - 静态校验与逻辑测试中覆盖到的 `encounter_journal` 相关行为
  - 当前文档列出的游戏内手工验证场景
- Out of Scope：
  - `quest` 模块独立任务界面与 Quest Inspector
  - 与冒险指南无关的 Tooltip、Mover、聊天提示能力

## 3. 测试环境

- 客户端 / 版本：
  WoW Retail，Interface 以仓库当前 `Toolbox.toc` 为准
- 账号或角色条件：
  角色存在至少一条可观察的副本锁定时，可更完整验证锁定摘要
- 数据前置条件：
  对应副本、坐骑掉落和 DB 静态入口数据已导出并可被插件加载
- 工具与命令：
  `python tests/run_all.py`

## 4. 测试用例

| 编号 | 前置条件 | 操作 | 预期结果 |
|------|----------|------|----------|
| TC-AUTO-01 | 测试环境可运行 Python / busted | 执行 `python tests/run_all.py` | 静态校验与逻辑测试通过 |
| TC-AUTO-02 | 测试环境可运行 busted | 执行 `tests/logic/spec/encounter_journal_navigation_spec.lua` | `Toolbox.EJ` 能按 `journalInstanceID` 查找入口、设置 waypoint，并由副本列表行图钉调用 |
| TC-AUTO-03 | 测试环境可运行 busted | 执行 `tests/logic/spec/encounter_journal_navigation_spec.lua` | 副本列表单击建立焦点、悬停临时显示图钉、常驻显示设置生效，双击触发进入行为 |
| TC-AUTO-04 | 测试环境可运行 busted | 执行 `tests/logic/spec/encounter_journal_navigation_spec.lua` | 当运行时入口 API 只返回聚合副本 ID 时，`Toolbox.EJ` 使用 `Toolbox.Data.InstanceEntrances` 的精确 `journalInstanceID` 记录转换地图坐标 |
| TC-AUTO-05 | 测试环境可运行 Python | 执行 `python tests/validate_data_contracts.py` | `instance_entrances` 契约、生成文件头和 Lua 根结构通过静态校验；`230 厄运之槌 - 中心花园` 使用 `areapoi` / `AreaPoiID=6501` / `HintUiMapID=69`，`1277` 保留 `journalinstanceentrance` |
| TC-AUTO-06 | 测试环境可运行 busted | 执行 `tests/logic/spec/encounter_journal_navigation_spec.lua` | 当 DB 静态入口存在时，`Toolbox.EJ` 不调用 `C_EncounterJournal.GetDungeonEntrancesForMap` 抢占静态数据 |
| TC-MANUAL-01 | 打开冒险指南地下城/团队副本列表 | 切换“仅坐骑” | 当前列表被筛选为可掉落坐骑的副本 |
| TC-MANUAL-02 | 角色存在副本锁定 | 浏览副本列表 | 列表行内显示重置时间；团队副本显示进度 |
| TC-MANUAL-03 | 角色存在副本锁定 | 悬停副本列表项 | tooltip 显示锁定详情 |
| TC-MANUAL-04 | 打开某个副本详情页掉落标签 | 切换“仅坐骑” | 仅显示当前副本掉落中的坐骑物品 |
| TC-MANUAL-05 | 打开某个副本详情页 | 查看标题区域 | 显示当前难度重置时间或“重置：无” |
| TC-MANUAL-06 | 显示小地图“冒险手册”入口或 `EJMicroButton` | 悬停相关入口 | tooltip 显示当前副本锁定摘要 |
| TC-MANUAL-07 | 打开未开启“定位图标常驻显示”的副本 / 地下城列表 | 单击某个可导航条目，再移开鼠标 | 该条目保持焦点态并显示图钉，其他未焦点条目不显示图钉 |
| TC-MANUAL-08 | 打开未开启“定位图标常驻显示”的副本 / 地下城列表 | 将鼠标移到非焦点但可导航的条目上 | 该条目在悬停期间显示图钉，移开后恢复隐藏 |
| TC-MANUAL-09 | 打开副本 / 地下城列表 | 双击某个条目 | 进入该副本，与 Blizzard 默认双击进入行为一致 |
| TC-MANUAL-10 | 在设置页开启“定位图标常驻显示” | 返回副本 / 地下城列表 | 所有可导航条目常驻显示图钉 |
| TC-MANUAL-11 | 打开有入口数据的副本 / 地下城列表 | 点击对应列表条目右下角图钉 | 世界地图打开到入口地图，创建系统用户导航点并开始追踪 |
| TC-MANUAL-12 | 打开无入口数据或不允许设置 waypoint 的副本列表 | 点击对应列表条目右下角图钉 | 插件给出不可用提示，不抛 Lua 错误 |
| TC-MANUAL-13 | 打开地下城列表并定位到“厄运之槌 - 戈多克议会” | 点击该条目右下角图钉 | 插件命中 DB 静态入口 `1277`，打开菲拉斯 / 厄运之槌入口所在地图并创建系统导航点；不得提示找不到副本入口 |

## 5. 执行结果

| 编号 | 实际结果 | 结论 | 备注 |
|------|----------|------|------|
| TC-AUTO-01 | `python tests/run_all.py --ci`：数据契约、设置结构与逻辑测试通过；逻辑测试 116 successes / 0 failures / 0 errors | 通过 | 2026-04-28 执行 |
| TC-AUTO-02 | `busted tests/logic/spec/encounter_journal_navigation_spec.lua`：10 successes / 0 failures / 0 errors | 通过 | 2026-04-28 执行 |
| TC-AUTO-03 | `busted tests/logic/spec/encounter_journal_navigation_spec.lua`：覆盖单击焦点、悬停图钉、常驻显示与双击进入 | 通过 | 2026-04-27 执行 |
| TC-AUTO-04 | `busted tests/logic/spec/encounter_journal_navigation_spec.lua`：覆盖运行时只返回聚合 `230` 时，`1277` 从 `InstanceEntrances` 转换坐标并成功设置 waypoint | 通过 | 2026-04-27 执行 |
| TC-AUTO-05 | `python tests/validate_data_contracts.py`：OK: data contracts validated；覆盖 `230` 不再使用分翼门候选坐标，且导出 `HintUiMapID=69` | 通过 | 2026-04-28 执行 |
| TC-AUTO-06 | `busted tests/logic/spec/encounter_journal_navigation_spec.lua`：覆盖静态入口存在时运行时入口 API 调用次数为 0 | 通过 | 2026-04-28 执行 |
| TC-MANUAL-01 | 待执行 | 待执行 | 需游戏内验证 |
| TC-MANUAL-02 | 待执行 | 待执行 | 需游戏内验证 |
| TC-MANUAL-03 | 待执行 | 待执行 | 需游戏内验证 |
| TC-MANUAL-04 | 待执行 | 待执行 | 需游戏内验证 |
| TC-MANUAL-05 | 待执行 | 待执行 | 需游戏内验证 |
| TC-MANUAL-06 | 待执行 | 待执行 | 需游戏内验证 |
| TC-MANUAL-07 | 待执行 | 待执行 | 需游戏内验证 |
| TC-MANUAL-08 | 待执行 | 待执行 | 需游戏内验证 |
| TC-MANUAL-09 | 待执行 | 待执行 | 需游戏内验证 |
| TC-MANUAL-10 | 待执行 | 待执行 | 需游戏内验证 |
| TC-MANUAL-11 | 待执行 | 待执行 | 需游戏内验证 |
| TC-MANUAL-12 | 待执行 | 待执行 | 需游戏内验证 |

## 6. 问题与阻塞

- 自动化当前通过。
- 游戏内手工验证未在本轮执行环境中执行，因此仍需后续补齐。

## 7. 结论

- 当前结论：自动化已通过，游戏内手工验证待执行。
- 后续动作：
  - 在游戏内补齐本清单中的手工验证项，重点验证列表交互、条目图钉和 `厄运之槌 - 戈多克议会` 静态入口导航

## 8. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-12 | 初稿：建立 `encounter_journal` 当前能力的测试基线与手工验证清单 |
| 2026-04-15 | 对齐当前实现：移除已拆分到 `quest` 模块的任务验证项，只保留副本列表、详情页与锁定摘要测试 |
| 2026-04-27 | 新增入口导航自动化与手工用例；记录 `python tests/run_all.py` 通过 |
| 2026-04-27 | 新增列表交互测试项：单击焦点、悬停显钉、常驻显示与双击进入 |
| 2026-04-27 | 新增 DB 静态入口验证项：覆盖 `instance_entrances` 契约校验与 `厄运之槌 - 戈多克议会` 静态 fallback |
| 2026-04-27 | 新增 `厄运之槌 - 中心花园` 数据回归：`230` 必须使用 `areapoi` 精确 POI，不能混入分翼门坐标 |
| 2026-04-28 | 新增入口读取优先级回归：静态入口存在时不调用运行时入口 API |
| 2026-04-28 | 新增目标区域地图回归：`230` 必须导出 `HintUiMapID=69`，确保打开菲拉斯区域地图 |
