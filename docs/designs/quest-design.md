# 任务模块设计

- 文档类型：设计
- 状态：已落地
- 主题：quest
- 适用范围：`quest`、`Toolbox.Questlines`、`minimap_button` 的独立任务界面与 Quest Inspector
- 关联模块：`quest`、`minimap_button`
- 关联文档：
  - `docs/features/quest-features.md`
  - `docs/specs/quest-spec.md`
  - `docs/plans/quest-plan.md`
  - `docs/tests/quest-test.md`
  - `docs/designs/encounter-journal-design.md`
  - `docs/Toolbox-addon-design.md`
- 最后更新：2026-04-15

## 1. 背景

- 当前代码已经存在独立 `quest` 模块，但仓库内还没有与之对应的设计文档。
- 旧文档仍把任务浏览写成 `encounter_journal` 的一部分，导致模块归属与 UI 入口都与实际实现不一致。

## 2. 设计目标

- 明确 `quest` 模块的独立界面、导航、详情与设置结构。
- 明确 `quest` 与 `Toolbox.Questlines`、`minimap_button` 的协作关系。
- 把任务能力从 `encounter_journal` 文档中剥离出来，恢复清晰边界。

## 3. 非目标

- 不覆盖冒险指南副本列表、详情页与锁定摘要增强。
- 不重新设计任务静态数据导出流程。
- 不补充当前代码中尚未开放的皮肤切换或额外视图模式。

## 4. 方案对比

### 4.1 方案 A：继续把任务浏览挂在 `encounter_journal`

- 做法：把任务相关 UI 继续视为冒险指南子能力，只在实现层抽出部分代码。
- 优点：文档数量更少。
- 风险 / 缺点：与当前入口、存档和模块注册现状不一致，也会继续模糊 `quest` 与 `encounter_journal` 的边界。

### 4.2 方案 B：以独立 `quest` 模块为单一事实来源

- 做法：把独立任务界面、任务导航、最近完成、任务详情弹框和 Quest Inspector 统一归到 `quest` 文档链。
- 优点：与当前代码一致，入口、存档和模块边界清晰。
- 风险 / 缺点：需要同步补齐一套新的 feature/spec/plan/test 文档。

### 4.3 选型结论

- 选定方案：方案 B。
- 选择原因：这是唯一能与当前模块注册、TOC、存档和用户入口保持一致的方案。

## 5. 选定方案

### 5.1 模块结构

| 文件 | 职责 |
|------|------|
| `Toolbox/Modules/Quest.lua` | 模块注册、独立宿主 Frame、设置页主页面、Quest Inspector 子页面、`QUEST_TURNED_IN` 事件接入。 |
| `Toolbox/Modules/Quest/Shared.lua` | 模块内部共享命名空间、模块 DB 访问、开关状态判断。 |
| `Toolbox/Modules/Quest/QuestNavigation.lua` | 左侧树导航、主区渲染、搜索、breadcrumb、详情弹框、最近完成列表与任务点击联动。 |

### 5.2 界面结构

- 宿主界面：
  使用独立 `ToolboxQuestFrame` 作为主容器，提供标题和关闭按钮。
- 左侧树：
  顶部固定“当前任务”入口；其下按资料片组织导航，资料片展开后只保留 `map_questline` 路径，并按导航模型显示地图或直连任务线条目。
- 右侧主区：
  包含 breadcrumb、搜索框、标题和滚动列表。
- 详情弹框：
  点击任务后显示任务详情；若有任务线归属，可跳回对应地图 / 任务线，也可切到“当前任务”视图定位该任务。

### 5.3 视图模式

#### `active_log`

- 左侧树中通过“当前任务”入口进入。
- 主区同时显示“最近完成”和“当前任务”两个区块。
- 最近完成列表来自 `QUEST_TURNED_IN` 事件维护的 `questRecentCompletedList`。
- 当前任务按状态排序，优先 `ready`，其次 `active`，最后 `pending`。

#### `map_questline`

- 从资料片下的 `map_questline` 路径进入。
- 左侧树显示地图或直连任务线条目。
- 主区显示任务线列表；每条任务线独占一行，支持单展开、进度显示、任务数量显示和“下一步”提示。
- 任务点击后既弹出详情，也会触发聊天调试输出。

### 5.4 数据与 API

| 数据 / API | 来源 | 用途 |
|------------|------|------|
| `Toolbox.Data.InstanceQuestlines` | 静态数据 | 提供任务线、地图和资料片归属的稳定结构。 |
| `Toolbox.Questlines.GetQuestNavigationModel()` | 领域对外 API | 构建左侧树导航模型。 |
| `Toolbox.Questlines.GetQuestLinesForMap()` | 领域对外 API | 构建 `map_questline` 主区任务线列表。 |
| `Toolbox.Questlines.GetCurrentQuestLogEntries()` | 领域对外 API | 构建 `active_log` 当前任务列表。 |
| `Toolbox.Questlines.GetQuestDetailByID()` | 领域对外 API | 构建 tooltip 与详情弹框。 |
| `Toolbox.Questlines.RequestAndDumpQuestDetailsToChat()` | 领域对外 API | 点击任务时输出运行时调试详情。 |
| `Toolbox.Questlines.RequestQuestInspectorSnapshot()` | 领域对外 API | Quest Inspector 异步查询与结果回填。 |

### 5.5 设置与存档

当前 `ToolboxDB.modules.quest` 主要字段包括：

- `questlineTreeEnabled`
- `questNavExpansionID`
- `questNavModeKey`
- `questNavSelectedMapID`
- `questNavSearchText`
- `questNavExpandedQuestLineID`
- `questlineTreeCollapsed`
- `questInspectorLastQuestID`
- `questRecentCompletedList`
- `questRecentCompletedMax`

说明：

- `questNavSelectedTypeKey` 与 `questNavSkinPreset` 仍在配置层保留，但当前界面不再暴露 `quest_type` 视图，也没有皮肤切换设置。
- `Config.lua` 会把旧 `encounter_journal.quest*` 字段迁移或清理到 `modules.quest`。

### 5.6 外部入口

- `Toolbox.MinimapButton.RegisterFlyoutEntry()` 注册“任务”飞出项。
- 点击飞出项时优先调用 `Toolbox.Quest.OpenMainFrame()`；若当前环境不能直接打开，则回退到 `quest` 设置页。
- Quest Inspector 作为 `quest` 模块设置子页面注册，不新增独立模块和额外 slash 命令。

## 6. 影响面

- 数据与存档：
  任务浏览相关状态全部落在 `ToolboxDB.modules.quest`。
- API 与模块边界：
  `quest` 负责界面、入口和事件接入；`Toolbox.Questlines` 负责任务导航、任务详情与异步查询；`minimap_button` 只负责呈现入口。
- 文件与目录：
  关键代码文件为 `Toolbox/Modules/Quest.lua`、`Toolbox/Modules/Quest/Shared.lua`、`Toolbox/Modules/Quest/QuestNavigation.lua`、`Toolbox/Core/API/QuestlineProgress.lua`、`Toolbox/Modules/MinimapButton.lua`、`Toolbox/Core/Foundation/Config.lua`。
- 文档回写：
  需要补齐 `quest-features/spec/plan/test`，并同步更新 `encounter-journal-*`、`FEATURES.md` 与 `Toolbox-addon-design.md`。

## 7. 风险与回退

- 风险：
  `quest` 强依赖运行时任务 API 与静态任务线数据，若任一侧返回缺失，界面会出现兜底名称或空态。
- 风险：
  最近完成列表只在模块启用后接收事件，不能回填历史完成记录。
- 风险：
  Quest Inspector 依赖异步加载，个别任务可能先显示加载中，再回填结果。
- 回退或缓解方式：
  若 `quest` 模块被禁用，可通过设置页关闭；若某个视图异常，可优先保留独立界面与 Quest Inspector，再逐步排查 `Toolbox.Questlines` 返回值。

## 8. 验证策略

- 逻辑验证：
  运行 `python tests/run_all.py --ci`，确认自动化校验继续通过。
- 游戏内验证：
  检查独立任务界面打开、左树导航、搜索、最近完成、任务详情弹框、聊天调试输出、Quest Inspector 和小地图入口是否均可用。
- 文档验证：
  `quest-features/spec/plan/test`、`encounter-journal-*`、`FEATURES.md` 与 `Toolbox-addon-design.md` 必须使用同一模块边界。

## 9. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-15 | 初稿：按当前 `quest` 模块实现补齐独立任务界面、导航、设置与 Quest Inspector 设计 |
