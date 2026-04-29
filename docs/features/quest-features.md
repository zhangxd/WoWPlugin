# 任务模块功能说明

- 文档类型：功能
- 状态：已发布
- 主题：quest
- 适用范围：`quest` 当前已落地的独立任务界面、任务浏览与 Quest Inspector
- 关联模块：`quest`、`minimap_button`
- 关联文档：
  - `docs/FEATURES.md`
  - `docs/specs/quest-spec.md`
  - `docs/designs/quest-design.md`
  - `docs/tests/quest-test.md`
  - `docs/features/encounter-journal-features.md`
- 最后更新：2026-04-18

## 1. 定位

- 本文档说明 `quest` 模块当前已经实现并可直接使用的任务浏览能力。
- 当前代码里，任务相关入口、独立任务界面、任务详情弹框、聊天调试输出和 Quest Inspector 都归属 `quest` 模块，不再挂在 `encounter_journal` 下。

## 2. 适用场景

- 想用独立界面浏览当前任务与任务线，而不是依赖冒险指南里的任务页签。
- 想按资料片与地图查看任务线进度，并在同一界面展开对应任务列表。
- 想搜索任务线或任务名，快速缩小当前浏览范围。
- 想保留最近完成任务列表，方便回看刚交付过的任务。
- 想按 `QuestID` 查询运行时任务字段与任务线字段，并复制结果文本。

## 3. 当前能力

### 3.1 独立任务界面

- 提供独立 `ToolboxQuestFrame` 任务界面，不再依附冒险指南根框体。
- 左侧树固定提供“当前任务”入口与资料片列表。
- 选中资料片后，只展开 `地图任务线` 这一条浏览路径；子项按导航模型显示地图或直连任务线。

### 3.2 当前任务视图

- “当前任务”视图在同一页内同时展示“最近完成”和“当前任务”两段内容。
- “最近完成”数据由 `QUEST_TURNED_IN` 事件持续记录，并按时间倒序保留。
- 当前任务按状态排序，`ready`、`active`、`pending` 优先级依次降低。

### 3.3 任务线视图

- `地图任务线` 路径下，主区展示当前地图或直连任务线的任务线列表。
- 当前静态任务线数据已覆盖“所有带任务线的任务”；即使某个任务没有稳定地图，也仍会出现在任务线浏览结果中。
- 地图分组使用“玩家可见地图”口径，而不是直接显示 POI 子区域 / 洞穴等微地图；例如像 `图格尔的巢穴` 这类子区域任务，会归到玩家实际看到的父地图 `霜火岭`。
- 每条任务线独占一行；点击后在原地展开其任务列表，再次点击折叠。
- 任务线行会显示进度、任务数量和“下一步”提示。
- 任务列表会优先按当前角色的阵营、种族和职业过滤；当静态数据已给出 `FactionTags / RaceMaskValues / ClassMaskValues` 时，不匹配当前角色的任务不会进入展开列表。
- 任务线本身是否显示，也取决于过滤后的任务列表；若某条任务线在当前角色下没有任何可见任务，则不会出现在最终地图任务线列表中。
- 若某条任务线完全拿不到稳定地图，则它不会再挂到“未知地图”节点下，而是直接作为资料片分组下的直连任务线显示。
- 任务列表支持鼠标悬停 tooltip、点击详情弹框，以及从弹框回跳到对应地图 / 任务线。

### 3.4 搜索、导航与详情联动

- 主界面提供搜索框，可按任务线名或任务名过滤当前视图。
- 主区顶部提供 breadcrumb；`active_log` 视图不显示路径节点，`map_questline` 视图提供可点击回跳路径。
- 任务线显示名遵循“运行时 API 优先、静态导出回退”规则；当 `C_QuestLine.GetQuestLineInfo` 取不到 `questLineName` 时，会回退到静态导出的 `Name_lang`。
- 点击任务后，除了弹出详情框，还会通过 `Toolbox.Questlines.RequestAndDumpQuestDetailsToChat()` 将当前可读到的运行时详情分段输出到聊天框。

### 3.5 Quest Inspector

- `quest` 的“任务”设置页下半部分提供 Quest Inspector 低频工具区。
- 输入 `QuestID` 后，可在可复制结果区查看任务运行时字段、地图链和任务线字段。
- 若任务缓存未就绪，会先发起异步加载，并在 `QUEST_DATA_LOAD_RESULT` 返回后刷新结果区。

### 3.6 外部入口

- 小地图飞出菜单内置“任务”入口，可直接打开 `quest` 主界面。
- 若运行时无法直接打开任务主界面，会回退到 `quest` 模块设置页。

## 4. 入口与使用方式

- 命令：`/toolbox`
  打开设置页后进入“任务”叶子页，可从页面内点击“打开界面”。
- 小地图按钮：
  悬停小地图按钮后，可从飞出菜单点击“任务”入口直接打开独立任务界面。
- 设置页工具区：
  在“任务”叶子页下半部分的 Quest Inspector 区输入 `QuestID` 后点击查询。

## 5. 设置项

当前主要设置项位于 `ToolboxDB.modules.quest`：

- `questlineTreeEnabled`
  控制任务视图总开关。
- `questRecentCompletedMax`
  控制“最近完成”区保留条数，范围为 `1-30`。
- `questInspectorLastQuestID`
  记录 Quest Inspector 最近一次查询的 `QuestID`。
- `questNavExpansionID`
  记录当前资料片选择。
- `questNavModeKey`
  记录当前浏览模式；当前有效值为 `active_log` 或 `map_questline`。
- `questNavSelectedMapID`
  记录 `map_questline` 路径下当前选中的地图。
- `questNavSearchText`
  记录界面搜索关键词。
- `questNavExpandedQuestLineID`
  记录当前展开的任务线。
- `questlineTreeCollapsed`
  记录左侧树折叠状态。
- `questRecentCompletedList`
  记录最近完成任务列表。

说明：

- `questNavSelectedTypeKey` 与 `questNavSkinPreset` 当前仍保留在存档层做兼容或归一，但现有界面不再暴露 `quest_type` 视图，也没有提供皮肤切换设置。

## 6. 已知限制

- 任务导航与任务线列表依赖 `Toolbox.Questlines` 对 `Toolbox.Data.InstanceQuestlines` 和运行时任务 API 的聚合结果。
- 任务线过滤的准确性取决于静态导出里是否能稳定识别阵营 / 种族 / 职业限制；当前已补入 `PlayerCondition` 与 `QuestV2CliTask.FiltRaces / FiltClasses` 的联合规则，但没有掩码信息的任务仍会按共享任务处理。
- 个别任务若无法从运行时 API 解析到名称，会回退到 `Quest #<id>`；任务线若运行时 API 取不到名称，则优先回退到静态导出的 `Name_lang`，只有静态名也缺失时才回退 `QuestLine #<id>`。
- “最近完成”只会记录模块启用后收到的 `QUEST_TURNED_IN` 事件，不会回填更早历史。
- Quest Inspector 与聊天调试输出依赖运行时缓存；首次查询某些任务时可能先进入异步加载流程。

## 7. 关联文档

- 功能：
  [encounter-journal-features.md](../features/encounter-journal-features.md)
- 需求：
  [quest-spec.md](../specs/quest-spec.md)
- 设计：
  [quest-design.md](../designs/quest-design.md)
- 测试：
  [quest-test.md](../tests/quest-test.md)
- 总设计：
  [Toolbox-addon-design.md](../Toolbox-addon-design.md)

## 8. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-15 | 初稿：按当前 `quest` 模块实现补齐独立任务界面、设置与 Quest Inspector 功能说明 |
| 2026-04-17 | 补充任务线视图过滤规则：任务与任务线会按当前角色的阵营 / 种族 / 职业约束过滤，过滤后为空的任务线不再显示 |
| 2026-04-18 | 补充导出覆盖范围说明：当前静态数据覆盖所有带任务线的任务，地图缺失不再导致整条任务线缺席 |
| 2026-04-18 | 补充地图显示规则：任务线导航使用玩家可见地图层；拿不到稳定地图的任务线直接挂在资料片分组下 |
| 2026-04-18 | 补充任务线名称回退规则：`C_QuestLine.GetQuestLineInfo` 失败时，回退静态导出的 `Name_lang` |
| 2026-04-29 | 设置宿主重构对齐：Quest Inspector 改为并回“任务”叶子页的低频工具区，不再保留独立设置子页面描述 |
