# 任务模块现状基线与演进计划

- 文档类型：计划
- 状态：已完成
- 主题：quest
- 适用范围：`quest` 当前独立任务界面、导航、最近完成与 Quest Inspector 的文档基线
- 关联模块：`quest`、`minimap_button`
- 关联文档：
  - `docs/features/quest-features.md`
  - `docs/specs/quest-spec.md`
  - `docs/designs/quest-design.md`
  - `docs/tests/quest-test.md`
  - `docs/plans/encounter-journal-plan.md`
- 最后更新：2026-04-15

## 1. 目标

- 为当前已经落地的 `quest` 模块补齐一套与实现一致的 feature/spec/design/plan/test 文档基线。

## 2. 输入文档

- 需求：
  `docs/specs/quest-spec.md`
- 设计：
  `docs/designs/quest-design.md`
- 其他约束：
  当前代码实现是唯一事实来源；任务能力已从 `encounter_journal` 独立出来。

## 3. 影响文件

- 新增：
  - `docs/features/quest-features.md`
  - `docs/specs/quest-spec.md`
  - `docs/designs/quest-design.md`
  - `docs/plans/quest-plan.md`
  - `docs/tests/quest-test.md`
- 修改：
  - `docs/FEATURES.md`
  - `docs/Toolbox-addon-design.md`
  - `docs/features/encounter-journal-features.md`
  - `docs/specs/encounter-journal-spec.md`
  - `docs/designs/encounter-journal-design.md`
- 验证：
  - `python tests/run_all.py --ci`
  - 文档引用与模块边界搜索

## 4. 执行步骤

- [x] 步骤 1：核对 `Toolbox/Modules/Quest*.lua`、`Toolbox/Core/API/QuestlineProgress.lua`、`Toolbox/Modules/MinimapButton.lua` 与 `Config.lua` 的当前实现。
- [x] 步骤 2：建立 `quest-features/spec/design/plan/test` 五份主文档。
- [x] 步骤 3：同步更新 `encounter-journal-*`、`FEATURES.md` 与 `Toolbox-addon-design.md`，恢复模块边界一致性。
- [x] 步骤 4：执行自动化验证并记录结果。

## 5. 验证

- 命令 / 检查点 1：
  `python tests/run_all.py --ci`
- 命令 / 检查点 2：
  搜索 `docs/**` 中 `quest`、`encounter_journal`、`Quest Inspector`、`任务页签` 的残留错位表述。
- 游戏内验证点：
  独立任务界面打开、左树导航、搜索、最近完成、任务详情弹框、聊天调试输出、Quest Inspector 与小地图“任务”入口。

## 6. 风险与回滚

- 风险：
  若只补 `quest` 文档、不同步收缩 `encounter_journal` 文档，会出现两边同时声明任务能力的冲突。
- 回滚方式：
  若描述与当前代码不符，应以当前模块注册、TOC 与配置结构为准重新修正文档，而不是回退到旧的冒险指南任务页签表述。

## 7. 执行记录

- 本轮已建立 `quest` 模块完整文档链，并同步收缩 `encounter_journal` 文档边界。
- `quest` 当前被视为独立模块基线，后续新增能力应直接续写 `quest-*` 五份主文档。

## 8. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-15 | 初稿：为当前 `quest` 模块补齐 feature/spec/design/plan/test 文档基线 |
