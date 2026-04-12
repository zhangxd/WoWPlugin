# 冒险指南任务页签导航重构计划

- 文档类型：计划
- 状态：已完成
- 主题：encounter-journal-quest-navigation
- 适用范围：`encounter_journal` 任务页签左侧树导航重构、地图主区折叠列表、任务类型入口、任务详情回跳与存档迁移
- 关联模块：`encounter_journal`
- 关联文档：
  - `docs/specs/encounter-journal-quest-navigation-spec.md`
  - `docs/designs/encounter-journal-quest-navigation-design.md`
- 最后更新：2026-04-12

## 1. 目标

- 交付一套新的任务页签结构：左侧固定资料片树，资料片下展开“地图任务线 / 任务类型”，地图主区使用任务线单行折叠展开，任务详情支持回跳到对应地图 / 任务线。

## 2. 输入文档

- 需求：
  `docs/specs/encounter-journal-quest-navigation-spec.md`
- 设计：
  `docs/designs/encounter-journal-quest-navigation-design.md`
- 其他约束：
  `AGENTS.md` 中的三关规则、任务页签资料片数据来源约束、Data 契约导出规则、Lua 开发规范与 TDD 要求

## 3. 影响文件

- 新增：
  - `docs/specs/encounter-journal-quest-navigation-spec.md`
  - `docs/designs/encounter-journal-quest-navigation-design.md`
  - `docs/plans/encounter-journal-quest-navigation-plan.md`
- 修改：
  - `Toolbox/Core/API/QuestlineProgress.lua`
  - `Toolbox/Core/Foundation/Config.lua`
  - `Toolbox/Core/Foundation/Locales.lua`
  - `Toolbox/Modules/EncounterJournal.lua`
  - `docs/specs/encounter-journal-quest-navigation-spec.md`
  - `docs/designs/encounter-journal-quest-navigation-design.md`
  - `docs/designs/encounter-journal-design.md`
  - `docs/features/encounter-journal-features.md`
  - `docs/Toolbox-addon-design.md`
- 验证：
  - `tests/logic/spec/questline_progress_spec.lua`
  - `tests/logic/spec/questline_progress_live_data_spec.lua`
  - 视需要新增 `tests/logic/spec/encounter_journal_quest_tab_spec.lua`
  - `tests/validate_data_contracts.py`

## 4. 执行步骤

- [ ] 步骤 1：先为左树导航模型、地图主区单展开任务线逻辑、类型大类分组和新存档迁移补测试，并先看到失败结果。
- [ ] 步骤 2：扩展 `Toolbox.Questlines` 运行时模型，输出资料片树子入口、地图列表、类型大类列表和任务详情回跳所需数据。
- [ ] 步骤 3：在 `Config.lua` 中新增左树模式状态键与迁移逻辑，把旧顶部分类状态迁到新树状态。
- [ ] 步骤 4：重构 `EncounterJournal.lua` 任务页签 UI，移除顶部资料片 / 分类按钮，改为左侧资料片树与两个子入口。
- [ ] 步骤 5：实现地图主区的任务线单行折叠展开、类型主区的直接任务列表，以及任务详情弹框内的“跳转到对应地图 / 任务线”动作。
- [ ] 步骤 6：补主区 breadcrumb 路径与点击回退交互，并补对应测试。
- [ ] 步骤 7：运行自动验证并回写总设计、功能说明与冒险指南专题文档。

## 5. 验证

- 命令 / 检查点 1：
  `python tests/run_all.py --ci`
- 命令 / 检查点 2：
  `python tests/validate_data_contracts.py`
- 命令 / 检查点 3：
  视变更范围单独运行任务相关逻辑测试文件，确认先红后绿
- 游戏内验证点：
  检查左侧资料片树、资料片下两个入口、地图列表、类型列表、任务线折叠展开、任务 tooltip、详情弹框与回跳行为，以及旧存档升级行为

## 6. 风险与回滚

- 风险：
  `EncounterJournal.lua` 任务页签逻辑集中，重构时容易把旧按钮、旧状态、旧详情区残留在运行路径中。
- 风险：
  Data 契约升级后，若 `ExpansionID` 缺失或 schema 校验未同步，任务页签可能直接空白。
- 回滚方式：
  保留单次提交内的文档、数据、运行时模型和 UI 改动边界；若 UI 层失败，可先回退任务详情弹框与导航按钮实现，保留数据契约与模型测试。

## 7. 执行记录

- 2026-04-13：已确认新一轮导航结构：左侧资料片树 + 两个子入口、地图主区任务线单展开、类型视图直接任务列表、详情弹框支持回跳。
- 2026-04-13：已完成左树模式导航模型、Config 迁移、任务页签 UI 重构、类型视图任务列表和详情回跳；`python tests/run_all.py --ci` 通过。
- 2026-04-13：新增主区 breadcrumb 路径导航需求，待补测试与实现。
 - 2026-04-13：已完成 breadcrumb 路径导航与点击回退；`python tests/run_all.py --ci` 通过。

## 8. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-12 | 初稿：按已确认需求拆分任务导航重构的导出、模型、迁移、UI 与验证步骤 |
| 2026-04-12 | 完成：计划内步骤已全部执行并通过自动验证 |
| 2026-04-13 | 更新：进入新一轮实现前，将计划改为左侧资料片树与地图主区单展开任务线方案 |
| 2026-04-13 | 完成：左侧资料片树方案已实现并通过自动验证 |
| 2026-04-13 | 更新：补入 breadcrumb 路径导航与回退交互步骤 |
| 2026-04-13 | 完成：breadcrumb 路径导航与回退交互已实现并通过自动验证 |
