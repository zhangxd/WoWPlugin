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
  对应副本和坐骑掉落静态数据已导出并可被插件加载
- 工具与命令：
  `python tests/run_all.py`

## 4. 测试用例

| 编号 | 前置条件 | 操作 | 预期结果 |
|------|----------|------|----------|
| TC-AUTO-01 | 测试环境可运行 Python / busted | 执行 `python tests/run_all.py` | 静态校验与逻辑测试通过 |
| TC-AUTO-02 | 测试环境可运行 busted | 执行 `tests/logic/spec/encounter_journal_navigation_spec.lua` | `Toolbox.EJ` 能按 `journalInstanceID` 查找入口、设置 waypoint，并由副本列表行图钉调用 |
| TC-MANUAL-01 | 打开冒险指南地下城/团队副本列表 | 切换“仅坐骑” | 当前列表被筛选为可掉落坐骑的副本 |
| TC-MANUAL-02 | 角色存在副本锁定 | 浏览副本列表 | 列表行内显示重置时间；团队副本显示进度 |
| TC-MANUAL-03 | 角色存在副本锁定 | 悬停副本列表项 | tooltip 显示锁定详情 |
| TC-MANUAL-04 | 打开某个副本详情页掉落标签 | 切换“仅坐骑” | 仅显示当前副本掉落中的坐骑物品 |
| TC-MANUAL-05 | 打开某个副本详情页 | 查看标题区域 | 显示当前难度重置时间或“重置：无” |
| TC-MANUAL-06 | 显示小地图“冒险手册”入口或 `EJMicroButton` | 悬停相关入口 | tooltip 显示当前副本锁定摘要 |
| TC-MANUAL-07 | 打开有入口数据的副本 / 地下城列表 | 点击对应列表条目右下角图钉 | 世界地图打开到入口地图，创建系统用户导航点并开始追踪 |
| TC-MANUAL-08 | 打开无入口数据或不允许设置 waypoint 的副本列表 | 点击对应列表条目右下角图钉 | 插件给出不可用提示，不抛 Lua 错误 |

## 5. 执行结果

| 编号 | 实际结果 | 结论 | 备注 |
|------|----------|------|------|
| TC-AUTO-01 | `python tests/run_all.py`：数据契约、设置结构与逻辑测试通过；逻辑测试 92 successes / 0 failures / 0 errors | 通过 | 2026-04-27 执行 |
| TC-AUTO-02 | 已纳入 `python tests/run_all.py`，`encounter_journal_navigation_spec.lua` 覆盖入口查找、waypoint 设置、失败兜底与列表行图钉点击 | 通过 | 2026-04-27 执行 |
| TC-MANUAL-01 | 待执行 | 待执行 | 需游戏内验证 |
| TC-MANUAL-02 | 待执行 | 待执行 | 需游戏内验证 |
| TC-MANUAL-03 | 待执行 | 待执行 | 需游戏内验证 |
| TC-MANUAL-04 | 待执行 | 待执行 | 需游戏内验证 |
| TC-MANUAL-05 | 待执行 | 待执行 | 需游戏内验证 |
| TC-MANUAL-06 | 待执行 | 待执行 | 需游戏内验证 |
| TC-MANUAL-07 | 待执行 | 待执行 | 需游戏内验证 |
| TC-MANUAL-08 | 待执行 | 待执行 | 需游戏内验证 |

## 6. 问题与阻塞

- 自动化当前通过。
- 游戏内手工验证未在本轮执行环境中执行，因此仍需后续补齐。

## 7. 结论

- 当前结论：自动化已通过，游戏内手工验证待执行。
- 后续动作：
  - 在游戏内补齐本清单中的手工验证项，重点验证列表条目图钉能打开地图并设置系统导航目标

## 8. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-12 | 初稿：建立 `encounter_journal` 当前能力的测试基线与手工验证清单 |
| 2026-04-15 | 对齐当前实现：移除已拆分到 `quest` 模块的任务验证项，只保留副本列表、详情页与锁定摘要测试 |
| 2026-04-27 | 新增入口导航自动化与手工用例；记录 `python tests/run_all.py` 通过 |
