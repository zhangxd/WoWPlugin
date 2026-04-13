# 冒险指南现状基线与演进计划

- 文档类型：计划
- 状态：进行中
- 主题：encounter-journal
- 适用范围：`encounter_journal` 当前能力基线整理与后续增量演进入口
- 关联模块：`encounter_journal`、`minimap_button`
- 关联文档：
  - `docs/features/encounter-journal-features.md`
  - `docs/specs/encounter-journal-spec.md`
  - `docs/designs/encounter-journal-design.md`
  - `docs/tests/encounter-journal-test.md`
- 最后更新：2026-04-14

## 1. 目标

- 把 `encounter_journal` 当前已实现能力整理成可持续维护的文档基线，并明确后续新增功能时应沿用的更新路径。

## 2. 输入文档

- 功能：`docs/features/encounter-journal-features.md`
- 需求：`docs/specs/encounter-journal-spec.md`
- 设计：`docs/designs/encounter-journal-design.md`
- 测试：`docs/tests/encounter-journal-test.md`
- 其他约束：当前代码实现是唯一事实来源；历史阶段文档仅保留追溯作用。

## 3. 影响文件

- 当前实现主文件：
  - `Toolbox/Modules/EncounterJournal.lua`
  - `Toolbox/Modules/MinimapButton.lua`
  - `Toolbox/Core/API/EncounterJournal.lua`
  - `Toolbox/Core/API/QuestlineProgress.lua`
- 当前文档基线：
  - `docs/features/encounter-journal-features.md`
  - `docs/specs/encounter-journal-spec.md`
  - `docs/designs/encounter-journal-design.md`
  - `docs/plans/encounter-journal-plan.md`
  - `docs/tests/encounter-journal-test.md`
- 历史并回项：
  - 任务页签导航重构
  - 任务线运行时名称
  - 任务类型运行时名称

## 4. 执行步骤

- [x] 梳理当前代码中已经落地的冒险指南能力。
- [x] 建立模块级功能文档，记录用户视角的当前能力。
- [x] 建立需求基线文档，记录现阶段范围与验收口径。
- [x] 建立设计文档，统一模块归属、数据来源与边界。
- [x] 建立测试基线文档，记录现有自动化验证与手工检查清单。
- [x] 覆盖旧的阶段性文档，使其只作为历史入口，不再作为并行事实来源。
- [x] 将 `encounter-journal-*` 子专题中的仍有效内容并回主文档，仅保留 `encounter-journal` 五份主文档。

## 5. 验证

- 目录验证：
  `encounter_journal` 已具备 `features / spec / design / plan / test` 五类配套文档，且不再保留继续维护的 `encounter-journal-*` 子专题平行文档。
- 一致性验证：
  文档中的模块归属、数据来源、入口说明必须与当前代码一致。
- 自动化验证：
  运行 `python tests/run_all.py --ci`，确认当前逻辑与静态校验仍然通过。

## 6. 风险与回滚

- 风险：
  若未来只改代码而不回写本套文档，会再次出现“功能存在但说明分散”的漂移。
- 风险：
  若跨模块联动只写在单模块文档中，容易让边界再次混乱。
- 回滚方式：
  若本计划中的整理结论需要调整，应优先修改 `spec / design / features / test` 四类文档，再回写 `Toolbox-addon-design.md` 与 `FEATURES.md`。

## 7. 执行记录

- 本计划记录的不是“待开发任务”，而是“当前实现的整理与未来演进入口”。
- 后续新增冒险手册 / 冒险指南能力时，以 `encounter-journal-features / spec / design / plan / test` 这一组文档为统一基线：
  - 先更新 `encounter-journal-spec.md`
  - 再更新 `encounter-journal-design.md`
  - 若功能已对外可见，同步更新 `encounter-journal-features.md`
  - 补充或更新 `encounter-journal-test.md`
  - 最后回写 `FEATURES.md` 与 `Toolbox-addon-design.md`
- 同一功能下的导航重构、名称来源调整、验证补充等子专题，也统一落在这五份主文档中，不再单独新建 `encounter-journal-xxx-plan.md` 等文件。

## 8. 当前执行任务：EncounterJournal 结构重构

- 当前目标：
  在**不改变现有行为**的前提下，将 `Toolbox/Modules/EncounterJournal.lua` 按职责拆分为主入口 + 私有实现文件，降低单文件复杂度与后续回归风险。
- 已确认主方案：
  - 允许新增 `Toolbox/Modules/EncounterJournal/` 子目录。
  - 允许更新 `Toolbox/Toolbox.toc` 加载顺序。
  - 不新增 `ToolboxDB.modules.encounter_journal` 键。
  - 不改变 `Toolbox.EJ`、`Toolbox.Questlines`、`Toolbox.Tooltip` 的对外契约。
- 推荐拆分边界：
  - `EncounterJournal.lua`：模块注册、事件入口、总协调。
  - `EncounterJournal/QuestNavigation.lua`：任务页签主对象与外部入口。
  - `EncounterJournal/QuestNavigationView.lua`：任务页签 widgets、左树、主区、breadcrumb、popup 渲染。
  - `EncounterJournal/QuestNavigationState.lua`：`questNav*` 状态读写与归一化。
  - `EncounterJournal/LockoutOverlay.lua`：副本列表 CD 叠加与相关 tooltip。
  - `EncounterJournal/DetailEnhancer.lua`：详情页“仅坐骑”和重置时间标签。
- 验收标准：
  - 副本列表“仅坐骑”、列表 CD、详情页增强、任务页签、`EJMicroButton` / 小地图锁定摘要行为保持不变。
  - 不再保留被后续实现覆盖的重复方法、空声明、无引用状态字段。
  - `python tests/run_all.py` 全绿。

## 9. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-12 | 初稿：建立 `encounter_journal` 的现状基线与后续演进计划 |
| 2026-04-13 | 文档收口：明确仅保留 `encounter-journal` 五份主文档，子专题执行记录统一并回主计划 |
| 2026-04-14 | 状态改为进行中：记录 `EncounterJournal.lua` 结构重构的已确认主方案、拆分边界与验收标准 |

## 10. 2026-04-13 执行补充（任务页签 UI + 浏览/做任务优化）

- 执行状态：可执行（用户已确认“开动”）。
- 已确认输入：
  - 主视觉：`方案D（A+C融合：古典档案馆）`。
  - 交付范围：`P1 + P2` 同步交付。
- 本轮实施清单：
  1. 左侧列表：分区化卡片样式、层级缩进优化、折叠/展开交互与状态持久化。
  2. 主显示区：任务线卡片化展示、任务状态徽记与进度可视化。
  3. 浏览效率：页签内搜索过滤、刷新后保持左右滚动位置。
  4. 做任务效率：详情动作区（跳转/追踪）、任务线下一步提示、当前进行中任务快捷视图。
- 非目标：不新增模块、不改入口、不改 TOC 装载结构。

## 11. 2026-04-13 执行补充（皮肤设置下拉接入）

- 执行状态：可执行（用户确认 `1A/2B/3A`）。
- 本轮新增事项：
  1. 在 `encounter_journal` 设置页新增任务页签皮肤模式下拉。
  2. 皮肤模式仅影响任务页签自定义 UI（容器/列表/弹层）。
  3. 模式切换后即时刷新任务页签，不新增菜单入口与模块。
