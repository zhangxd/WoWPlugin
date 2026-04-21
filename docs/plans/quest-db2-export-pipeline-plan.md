# quest_db2_export_pipeline 分层收敛实施计划

- 文档类型：计划
- 状态：待执行
- 主题：quest-db2-export-pipeline
- 适用范围：`scripts/export/**`、`../WoWTools/outputs/toolbox/**`、`Toolbox/Data/InstanceQuestlines.lua`
- 关联模块：quest
- 关联文档：
  - `docs/designs/quest-db2-export-pipeline-design.md`
  - `docs/plans/instance-questlines-runtime-extension-plan.md`
- 最后更新：2026-04-15

> 使用说明：本计划只处理导出分层和职责收敛，不直接决定插件运行时消费细节；运行时接入见 `instance-questlines-runtime-extension-plan.md`。

## 1. 目标

- 固定 `DB -> CSV -> Lua` 三层导出职责，并把现有脚本、目录、文件的角色收敛为稳定规则，避免后续在“直接 DB 导 Lua”与“先 CSV 再 Lua”之间反复摇摆。

## 2. 输入文档

- 设计：
  - `docs/designs/quest-db2-export-pipeline-design.md`
- 其他约束：
  - 仓库根 `AGENTS.md`
  - `docs/AI-ONBOARDING.md`
  - `docs/DOCS-STANDARD.md`

## 3. 影响文件

- 新增：
  - `docs/plans/quest-db2-export-pipeline-plan.md`
- 修改：
  - `docs/designs/quest-db2-export-pipeline-design.md`
  - `scripts/export/quest_db2_export_pipeline.py`（后续若需补注释或命令帮助）
  - `scripts/export/questline_runtime_preview_export.py`（后续若需补注释或命令帮助）
  - `scripts/export/export_quest_achievement_merged_from_db.py`（正式入口说明与命令帮助）
- 验证：
  - `scripts/export/tests/*`

## 4. 执行步骤

- [ ] 步骤 1：确认设计文档中已固定 `DB -> CSV -> Lua` 三层职责。
- [ ] 步骤 2：明确 `quest_db2_export_pipeline.py` 只负责分析中间层，不直接负责正式插件静态表。
- [ ] 步骤 3：明确 `questline_runtime_preview_export.py` 只负责临时轻量验证，不进入正式契约路径。
- [ ] 步骤 4：明确 `toolbox_db_export.py` 仍是通用契约导出入口，但 `instance_questlines` 正式落地固定由 `export_quest_achievement_merged_from_db.py` 完成。
- [ ] 步骤 5：列出 `outputs/toolbox/` 各文件的生命周期和覆盖规则，避免把临时预览文件误当正式数据。
- [ ] 步骤 6：补充脚本帮助文本或注释，写清“分析中间层 / 预览层 / 正式层”的边界。
- [ ] 步骤 7：在正式接入 `instance_questlines` 前，先以 `runtime_preview` 验证字段收敛是否满足 `quest` / `Toolbox.Questlines` 需要。
- [ ] 步骤 8：待字段和消费逻辑定版后，仅评估是否需要补充契约侧校验，不再要求把正式写盘链路并回 `toolbox_db_export.py`。

## 5. 验证

- 命令 / 检查点 1：
  - `python scripts/export/quest_db2_export_pipeline.py`
- 命令 / 检查点 2：
  - `python scripts/export/questline_runtime_preview_export.py`
- 命令 / 检查点 3：
  - `python scripts/export/export_quest_achievement_merged_from_db.py --skip-csv`
- 命令 / 检查点 4：
  - `python -m unittest scripts.export.tests.test_quest_db2_export_pipeline scripts.export.tests.test_questline_runtime_preview_export -v`
- 检查点 5：
  - 设计文档中必须清楚区分“分析中间层”“临时预览层”“正式运行时层”

## 6. 风险与回滚

- 风险：
  - 若不固定分层职责，后续字段迭代会同时污染 CSV 与正式 Lua，导致运行时与分析层双向耦合。
  - 若把 `runtime_preview` 误当正式结构，会绕开正式导出测试。
- 回滚方式：
  - 若分层方案不成立，仅回退文档和临时预览脚本，不影响正式 `instance_questlines` 专门导出链路与插件运行时。

## 7. 执行记录

- 2026-04-15：已完成口头方案对齐，确认 `quest_expansion_map.csv` 定位为分析中间层，`InstanceQuestlines.runtime_preview.lua` 定位为临时预览层。

## 8. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-15 | 初稿：固定 `DB -> CSV -> Lua` 三层导出职责，并梳理脚本、目录、文件的角色边界 |

