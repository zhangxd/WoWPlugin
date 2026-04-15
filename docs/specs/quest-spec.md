# 任务模块需求规格

- 文档类型：需求
- 状态：已完成
- 主题：quest
- 适用范围：`quest` 当前已实现的独立任务界面、任务浏览与 Quest Inspector 基线
- 关联模块：`quest`、`minimap_button`
- 关联文档：
  - `docs/features/quest-features.md`
  - `docs/designs/quest-design.md`
  - `docs/tests/quest-test.md`
  - `docs/specs/encounter-journal-spec.md`
- 最后更新：2026-04-15

## 1. 背景

- 当前代码已经把原先挂在冒险指南里的任务能力拆成独立 `quest` 模块，但仓库内还没有与之对应的需求基线文档。
- 需要一份按当前实现整理的规格文档，明确 `quest` 模块的边界、入口和验收口径。

## 2. 目标

- 明确 `quest` 当前已经交付的能力范围。
- 明确 `quest` 与 `encounter_journal` 的职责分界。
- 为后续继续扩展独立任务界面时提供稳定的历史对照面。

## 3. 范围

### 3.1 In Scope

- 独立任务界面 `ToolboxQuestFrame`。
- 左侧树中的“当前任务”入口与资料片导航。
- `active_log` 当前任务视图。
- `map_questline` 任务线浏览视图。
- 搜索框过滤任务线与任务名称。
- 最近完成任务记录与展示。
- 任务 tooltip、任务详情弹框、弹框回跳。
- 点击任务后触发的聊天调试输出。
- `quest` 设置页中的 Quest Inspector 子页面。
- 小地图飞出菜单“任务”入口。

### 3.2 Out of Scope

- 冒险指南副本列表、详情页和锁定摘要增强。
- `quest_type` 视图。
- 冒险指南根页签顺序与显隐管理。
- 额外 slash 命令、额外菜单按钮或额外 TOC 行之外的隐藏入口。
- 任务数据导出链路本身的设计与实现。

## 4. 已确认决策

- 主归属模块为 `quest`。
- 主界面宿主为独立 `ToolboxQuestFrame`，不再依附 `EncounterJournal` 根框体。
- 当前有效浏览模式只有 `active_log` 和 `map_questline`。
- 左侧树固定提供“当前任务”入口；资料片展开后只保留 `map_questline` 这一条路径。
- 任务导航、任务列表、任务详情与 Quest Inspector 数据统一通过 `Toolbox.Questlines` 领域 API 获取。
- 最近完成任务通过 `QUEST_TURNED_IN` 事件维护，保存在 `ToolboxDB.modules.quest.questRecentCompletedList`。
- Quest Inspector 归属 `quest` 模块设置页，不再属于 `encounter_journal`。
- 小地图飞出菜单中的“任务”入口用于打开 `quest` 主界面；打不开时回退到 `quest` 设置页。

## 5. 待确认项

- 无。本文件只描述当前已实现内容，不新增待决设计选项。

## 6. 验收标准

1. 小地图飞出菜单中的“任务”入口可以打开独立 `quest` 主界面。
2. 设置页“任务”模块中可以点击按钮打开同一主界面。
3. 左侧树中可以进入“当前任务”视图，并看到“最近完成”和“当前任务”两段内容。
4. 最近完成列表条数受 `questRecentCompletedMax` 控制，并在任务交付后持续更新。
5. 在资料片路径下可以进入 `map_questline` 视图，并查看地图或直连任务线条目。
6. 点击任务线后会在主区展开对应任务列表，再次点击可折叠。
7. 搜索框可以按任务线名或任务名过滤当前视图。
8. 点击任务后会显示详情弹框；若存在任务线归属，可回跳到对应地图 / 任务线。
9. 点击任务后会将当前可解析到的运行时详情分段输出到聊天框。
10. 在 Quest Inspector 子页面输入合法 `QuestID` 后，可看到可复制的结果文本；若任务缓存未就绪，页面会在异步加载完成后刷新。
11. 当前实现中不再暴露 `quest_type` 视图，也不再依赖 `encounter_journal` 作为任务浏览入口。

## 7. 实施状态

- 当前状态：已完成
- 下一步：后续若继续扩展独立任务界面、最近完成区或 Quest Inspector，以本文件为基线续写。

## 8. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-15 | 初稿：按当前 `quest` 模块实现建立独立任务界面与 Quest Inspector 的需求基线 |
