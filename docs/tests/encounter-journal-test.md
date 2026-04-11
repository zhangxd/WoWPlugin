# 冒险指南测试基线

- 文档类型：测试
- 状态：执行中
- 主题：encounter-journal
- 适用范围：`encounter_journal` 当前已实现能力的自动化与手工验证基线
- 关联模块：`encounter_journal`、`minimap_button`
- 关联文档：
  - `docs/features/encounter-journal-features.md`
  - `docs/specs/encounter-journal-spec.md`
  - `docs/designs/encounter-journal-design.md`
  - `docs/plans/encounter-journal-plan.md`
- 最后更新：2026-04-12

## 1. 测试背景

- 本文档用于记录 `encounter_journal` 当前已实现能力的验证基线。
- 由于其中一部分能力依赖游戏内 UI、角色锁定和运行时任务状态，当前测试基线分为“自动化回归”和“手工游戏内验证”两部分。

## 2. 测试范围

- In Scope：
  - 静态校验与逻辑测试中覆盖到的冒险指南行为
  - 当前文档列出的手工验证场景
- Out of Scope：
  - 与冒险指南无关的 Tooltip、Mover、聊天提示能力
  - 未实现的未来功能

## 3. 测试环境

- 客户端 / 版本：WoW Retail，Interface 以仓库当前 `Toolbox.toc` 为准
- 自动化环境：本地 Python + busted 逻辑测试环境
- 关键命令：`python tests/run_all.py --ci`
- 游戏内前置条件：
  - 角色存在至少一条可观察的副本锁定时，可更完整验证锁定摘要
  - 角色任务日志中存在任务时，可验证状态视图联动

## 4. 测试用例

| 编号 | 前置条件 | 操作 | 预期结果 |
|------|----------|------|----------|
| TC-AUTO-01 | 测试环境可运行 Python / busted | 执行 `python tests/run_all.py --ci` | 静态校验与逻辑测试通过 |
| TC-MANUAL-01 | 打开冒险指南地下城/团队副本列表 | 切换“仅坐骑” | 当前列表被筛选为可掉落坐骑的副本 |
| TC-MANUAL-02 | 角色存在副本锁定 | 浏览副本列表 | 列表行内显示重置时间；团队副本显示进度 |
| TC-MANUAL-03 | 角色存在副本锁定 | 悬停副本列表项 | tooltip 显示锁定详情 |
| TC-MANUAL-04 | 打开某个副本详情页掉落标签 | 切换“仅坐骑” | 仅显示当前副本掉落中的坐骑物品 |
| TC-MANUAL-05 | 打开某个副本详情页 | 查看标题区域 | 显示当前难度重置时间或“重置：无” |
| TC-MANUAL-06 | 打开任务页签 | 在 `状态 / 类型 / 地图` 间切换 | 三视图均可正常切换 |
| TC-MANUAL-07 | 任务日志存在任务 | 在状态视图选择任务 | 右侧显示所属完整任务线，或在无映射时回退任务详情 |
| TC-MANUAL-08 | 打开设置页 | 调整根页签顺序与显隐 | 设置即时生效，冒险指南根页签更新 |
| TC-MANUAL-09 | 显示小地图按钮或 `EJMicroButton` | 悬停相关入口 | tooltip 显示当前副本锁定摘要 |

## 5. 执行结果

| 编号 | 实际结果 | 结论 | 备注 |
|------|----------|------|------|
| TC-AUTO-01 | `python tests/run_all.py --ci` 通过；静态校验通过，logic tests 为 `29 successes / 0 failures / 0 errors / 0 pending` | 通过 | 本轮已实际执行 |
| TC-MANUAL-01 | 待执行 | 待执行 | 需游戏内验证 |
| TC-MANUAL-02 | 待执行 | 待执行 | 需游戏内验证 |
| TC-MANUAL-03 | 待执行 | 待执行 | 需游戏内验证 |
| TC-MANUAL-04 | 待执行 | 待执行 | 需游戏内验证 |
| TC-MANUAL-05 | 待执行 | 待执行 | 需游戏内验证 |
| TC-MANUAL-06 | 待执行 | 待执行 | 需游戏内验证 |
| TC-MANUAL-07 | 待执行 | 待执行 | 需游戏内验证 |
| TC-MANUAL-08 | 待执行 | 待执行 | 需游戏内验证 |
| TC-MANUAL-09 | 待执行 | 待执行 | 需游戏内验证 |

## 6. 问题与阻塞

- 游戏内手工验证未在本轮文档整理中执行，因此仍需后续补齐。

## 7. 结论

- 当前结论：执行中
- 后续动作：
  - 在游戏内按本清单补齐手工验证

## 8. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-12 | 初稿：建立 `encounter_journal` 当前能力的测试基线与手工验证清单 |
