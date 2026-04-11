# 冒险指南任务线运行时名称实施计划

- 文档类型：计划
- 状态：已完成
- 主题：encounter-journal-questline-runtime-name
- 适用范围：`encounter_journal` 任务页签任务线名称显示改造
- 关联模块：`encounter_journal`
- 关联文档：
  - `docs/specs/encounter-journal-questline-runtime-name-spec.md`
  - `docs/designs/encounter-journal-questline-runtime-name-design.md`
- 最后更新：2026-04-12

## 1. 目标

- 让任务页签中的任务线名称改为“运行时 API 优先、`QuestLine #<id>` 兜底”，同时把 `InstanceQuestlines.questLines` 的 `Name_lang` 改为 Lua 尾注释输出。

## 2. 输入文档

- 需求：`docs/specs/encounter-journal-questline-runtime-name-spec.md`
- 设计：`docs/designs/encounter-journal-questline-runtime-name-design.md`
- 其他约束：
  - 遵守 `AGENTS.md` 的三关门禁、领域 API 边界和 TDD 要求。
  - `InstanceQuestlines` 结构块不变，但 `questLines` 中的 `Name_lang` 需要改为尾注释输出。

## 3. 影响文件

- 修改：
  - `../WoWTools/scripts/export/lua_contract_writer.py`
  - `../WoWTools/scripts/export/toolbox_db_export.py`
  - `../WoWTools/scripts/export/tests/test_lua_contract_writer.py`
  - `DataContracts/instance_questlines.json`
  - `Toolbox/Core/API/QuestlineProgress.lua`
  - `Toolbox/Modules/EncounterJournal.lua`
  - `tests/logic/spec/encounter_journal_event_lifecycle_spec.lua`
  - `tests/logic/spec/questline_progress_spec.lua`
- 文档回写：
  - `docs/designs/encounter-journal-design.md`
  - `docs/Toolbox-addon-design.md`
- 验证：
  - `python tests/run_all.py --ci`

## 4. 执行步骤

- [x] 步骤 1：在逻辑测试中新增“运行时任务线名称覆盖静态名”的失败用例。
- [x] 步骤 2：运行对应用例，确认当前实现按预期失败，且失败点是任务线名称仍为静态名。
- [x] 步骤 3：在 `QuestlineProgress.lua` 中实现任务线显示名访问器与轻量缓存。
- [x] 步骤 4：把 `EncounterJournal.lua` 中直接读取任务线静态名的显示点切到统一访问器。
- [x] 步骤 5：运行新增用例与相关冒险指南逻辑测试，确认全部通过。
- [x] 步骤 6：回写总设计文档中的任务线名称来源说明。
- [x] 步骤 7：扩展导出器，让 `questLines` 块支持 `Name_lang` 尾注释输出，并用契约脚本重跑导出。

## 5. 验证

- 失败验证：
  运行目标逻辑测试，确认新增用例先红灯。
- 通过验证：
  运行 `python tests/run_all.py --ci`
- 导出验证：
  运行 `python ../WoWTools/scripts/export/export_toolbox_one.py instance_questlines --contract-dir DataContracts --data-dir Toolbox/Data`
- 游戏内验证点：
  打开冒险指南任务页签，检查左侧树和状态视图右侧标题中的任务线名称显示一致，且在 API 不可用时回退为 `QuestLine #<id>`。

## 6. 风险与回滚

- 风险：
  运行时 API 不能覆盖所有任务线，导致部分任务线显示 `QuestLine #<id>`。
- 风险：
  名称解析若未缓存，可能在渲染时重复调用 API。
- 回滚方式：
  若实现后出现兼容问题，可恢复 `Name_lang` 结构化字段导出，并在 `Toolbox.Questlines` 访问器内继续优先走运行时名称。

## 7. 执行记录

- 2026-04-12：用户已明确“开动”，并按推荐方案确认采用“运行时 API 优先、静态名兜底”，本计划进入待执行状态。
- 2026-04-12：已补充 `questline_progress_spec.lua` 与 `encounter_journal_event_lifecycle_spec.lua` 红灯用例，并确认当前实现失败点正确。
- 2026-04-12：已实现 `Toolbox.Questlines.GetQuestLineDisplayName` 与秒级运行时缓存，`EncounterJournal` 显示点已切到统一访问器。
- 2026-04-12：已运行 `python tests/run_all.py --ci`，整套校验通过。
- 2026-04-12：已扩展 `WoWTools` 导出器的 `map_object` 尾注释能力，`instance_questlines` 契约升到 schema v3，并重跑生成 `Toolbox/Data/InstanceQuestlines.lua`。

## 8. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-12 | 初稿：拆解任务线运行时名称改造步骤 |
| 2026-04-12 | 执行完成：所有步骤已落地并通过整套测试 |
| 2026-04-12 | 调整：计划纳入 `InstanceQuestlines` 契约裁剪与导出器尾注释输出 |
