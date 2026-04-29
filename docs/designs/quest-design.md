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
- 最后更新：2026-04-18

## 1. 背景

- 当前代码已经存在独立 `quest` 模块，但仓库内还没有与之对应的设计文档。
- 旧文档仍把任务浏览写成 `encounter_journal` 的一部分，导致模块归属与 UI 入口都与实际实现不一致。

## 2. 设计目标

- 明确 `quest` 模块的独立界面、导航、详情与设置结构。
- 明确任务名 / 任务线名的显示口径与任务列表内展开交互。
- 明确 `quest` 与 `Toolbox.Questlines`、`minimap_button` 的协作关系。
- 把任务能力从 `encounter_journal` 文档中剥离出来，恢复清晰边界。
- 把现有写死的任务导航状态收敛成 `quest` 模块内部可复用的节点导航模型。

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
| `Toolbox/Modules/Quest.lua` | 模块注册、独立宿主 Frame、设置页主页面、Quest Inspector 工具区、`QUEST_TURNED_IN` 事件接入。 |
| `Toolbox/Modules/Quest/Shared.lua` | 模块内部共享命名空间、模块 DB 访问、开关状态判断。 |
| `Toolbox/Modules/Quest/QuestNavigation.lua` | 左侧树导航、主区渲染、搜索、breadcrumb、列表内展开详情、最近完成列表与任务点击联动。 |

### 5.2 界面结构

- 宿主界面：
  使用独立 `ToolboxQuestFrame` 作为主容器，标题区样式对齐 Blizzard 冒险指南的 `PortraitFrameTemplate`：使用同类标题栏、关闭按钮和头像区域，而不是对话框式 `BackdropTemplate` 标题条。
  宿主框拖动不在 `quest` 模块内部重复实现，而是统一交给 `Toolbox.Mover.RegisterFrame()`；拖动命中区收口为宿主标题栏区域，以便与冒险指南的“点标题栏即可拖动”体验保持一致。
- 底部分页签：
  固定保留 `当前任务` 与 `任务线` 两个视图页签；默认打开逻辑保持现状，不额外改变首次进入的默认视图。
  已确认对齐 Blizzard 冒险指南的根页签实现：两枚页签继续挂在 `ToolboxQuestFrame` 根容器，而不是挂在任何内容视图下；视觉上锚在 `ToolboxQuestFrame` 宿主底边，并位于唯一视图框 `panelFrame` 的外侧下方，页签本身不占用视图内部高度。
- 唯一视图框：
  `panelFrame` 作为唯一整框视图，边框位置贴近宿主内框，参考冒险指南 `InsetFrameTemplate + instanceSelect` 的锚点关系；不得再保留旧的底部大间距，也不得在 `leftTree` / `rightContent` 上继续画第二层整框边线。
- 左上角导航路径：
  `map_questline` 视图顶部路径导航使用 Blizzard `NavBar` 组件承载，视觉对齐冒险指南地下城页签中“选中地下城页签后进入副本节点”的原生路径条；路径仍由当前选中节点的祖先链推导，祖先节点可点击回退，末级节点仅表示当前位置。
  `NavBar` 不再挂在正文内容区顶部，而是放到宿主标题栏与正文之间、直接隶属于宿主框体且与宿主标题区背景融合的独立头部带中；左侧需避让宿主头像 / 标题图标区，使路径显示在图标右侧，右侧需避让搜索框，避免路径被图标盖住或与搜索框重叠。`NavBar` 按钮在头部带内垂直居中，并尽量放大占满标题下这一整行高度；多级路径总宽度必须被限制在搜索框左侧，文本按可见区域左对齐显示，不能继续向右压到搜索框。
- `当前任务` 视图：
  不再沿用左树 + 右区布局；主区拆成上下两段。上段固定显示当前任务列表并支持内部滚动，下段显示历史完成列表，支持折叠；折叠后上段占满内容区。
  该视图仍会注册自己的根节点，用于左上角通用导航路径展示当前上下文，但不单独显示左侧树。
- `任务线` 视图：
  继续采用左侧层级导航 + 右侧主区布局。左侧仅展示资料片 / 地图 / 任务线节点，不再出现“当前任务”入口；标题栏下方的独立头部带承载 `NavBar` 路径导航与搜索框，右侧主区仅保留标题和滚动列表。搜索框外层仅保留布局容器，不再自绘第二层边框，避免与 `InputBoxTemplate` 形成双框重叠。
- 列表内展开详情：
  点击任务后，不再弹出独立详情框，而是在当前列表中直接展开该任务的详细信息；再次点击同一任务时收起。
  展开区保留“跳回对应地图 / 任务线”与“切到当前任务视图定位该任务”两类动作，但它们改为行内动作，不再依赖独立弹框。
  详情中的“类型”显示采用“类型名字（ID）”格式，名字来源复用 `Toolbox.Questlines` 现有类型标签解析逻辑，解析失败时回退为纯 ID。

### 5.3 视图模式

#### `active_log`

- 由底部分页签直接进入，不再挂在左树内部。
- 主区拆为“当前任务”与“历史完成”两个独立面板。
- 最近完成列表来自 `QUEST_TURNED_IN` 事件维护的 `questRecentCompletedList`。
- 历史完成面板支持折叠；折叠后当前任务面板占满主区高度。
- 当前任务按状态排序，优先 `ready`，其次 `active`，最后 `pending`。
- 布局计算不得再为底部分页签预留 `bottomInset`；唯一视图框内部高度应全部让给当前任务 / 历史完成两段内容。

#### `map_questline`

- 从底部分页签进入后，左侧树显示当前视图注册出来的导航节点。
- 左侧树不再写死“模式”或“当前任务”语义，只按父子节点关系呈现资料片 / 地图 / 任务线层级。
- 主区显示任务线列表；每条任务线改为双行高度的主卡片，支持单展开、进度显示与任务数量显示。右侧状态区不再显示“下一步：xxx”长文案，仅在任务线已完成时显示短状态“已完成”；未完成时右侧状态区留空。
- 任务线展开后的任务行改回单行高度，不再显示任务线名称副标题；任务名仍采用运行时 API 优先、静态数据回退的口径。
- 任务点击后在当前列表内展开详细信息，不再弹出详情框，也不再触发聊天调试输出。
- 行内详情只保留“跳转到对应地图 / 任务线”动作；“在进行中视图查看”按钮从详情区移除。
- 左树与右侧主区同样填满 `panelFrame` 内部区域；底部分页签只贴在 `panelFrame` 外侧下沿，不压缩左右内容区高度。

### 5.4 导航节点模型

- 落点范围：
  本轮通用导航仅在 `quest` 模块内部实现，不上提到 `Core`。
- 节点职责：
  节点只描述父子关系、显示文本与上下文载荷，不直接承载页面跳转逻辑。
- 建议字段：
  `nodeId`、`parentNodeId`、`title`、`order`、`nodeType`、`payload`。
- 运行时状态：
  由“当前选中节点 + 导航路径 + 折叠状态”组成。左侧点击节点时，只更新当前选中节点并重算导航路径；右侧内容根据当前节点的 `nodeType + payload` 决定展示内容。
- 视图接入方式：
  每个视图都可以注册节点。`active_log` 注册根节点与可选子节点但不渲染左树；`map_questline` 注册资料片 / 地图 / 任务线节点并渲染左树。
- 持久化策略：
  本轮优先复用现有 `questNavModeKey`、`questNavExpansionID`、`questNavSelectedMapID`、`questNavExpandedQuestLineID`、`questlineTreeCollapsed` 等键，不新增 `Core` 级导航存档。

### 5.5 数据与 API

| 数据 / API | 来源 | 用途 |
|------------|------|------|
| `Toolbox.Data.InstanceQuestlines` | 静态数据 | 提供任务线、地图和资料片归属的稳定结构。 |
| `Toolbox.Questlines.GetQuestNavigationModel()` | 领域对外 API | 构建左侧树导航模型。 |
| `Toolbox.Questlines.GetQuestLinesForMap()` | 领域对外 API | 构建 `map_questline` 主区任务线列表。 |
| `Toolbox.Questlines.GetCurrentQuestLogEntries()` | 领域对外 API | 构建 `active_log` 当前任务列表。 |
| `Toolbox.Questlines.GetQuestLineDisplayName()` | 领域对外 API | 用 `C_QuestLine.GetQuestLineInfo` 优先解析任务线显示名，并在失败时回退静态名称。 |
| `Toolbox.Questlines.GetQuestDetailByID()` | 领域对外 API | 构建列表内展开详情所需字段，并返回任务线归属、地图与跳转上下文。 |
| `Toolbox.Questlines.RequestQuestInspectorSnapshot()` | 领域对外 API | Quest Inspector 异步查询与结果回填。 |

补充说明：

- `GetCurrentQuestLogEntries()` 返回给界面的任务行数据需要直接携带 API 优先的任务名与任务线名，避免界面层再次重复拼装名称来源。
- `GetQuestDetailByID()` 返回的 `questLineName` 也必须与列表口径一致，即优先使用运行时任务线名称，再回退静态名称。
- `GetQuestDetailByID()` 返回给界面的详情对象应直接包含 `typeLabel`；界面层按“类型名字（ID）”格式渲染，避免在 `QuestNavigation` 重复做类型名解析。

### 5.6 设置与存档

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
- 本轮导航重构默认不新增新的持久化键，避免把模块内通用导航模型外溢到全局契约。

### 5.7 外部入口

- `Toolbox.MinimapButton.RegisterFlyoutEntry()` 注册“任务”飞出项。
- 点击飞出项时优先调用 `Toolbox.Quest.OpenMainFrame()`；若当前环境不能直接打开，则回退到 `quest` 设置页。
- Quest Inspector 并回 `quest` 的“任务”叶子页低频工具区，不新增独立模块、额外设置入口或额外 slash 命令。

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
  详情展示从独立弹框改为列表内展开后，`active_log`、最近完成与 `map_questline` 三种任务行需要共享同一展开状态模型，否则容易出现展开错位或切换视图后残留旧状态。
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
  检查独立任务界面打开、左树导航、搜索、最近完成、任务名 / 任务线名显示、列表内展开详情、Quest Inspector 和小地图入口是否均可用；同时确认任务悬停不再显示 tooltip、点击任务后不再输出聊天调试信息。
- 文档验证：
  `quest-features/spec/plan/test`、`encounter-journal-*`、`FEATURES.md` 与 `Toolbox-addon-design.md` 必须使用同一模块边界。

## 9. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-15 | 初稿：按当前 `quest` 模块实现补齐独立任务界面、导航、设置与 Quest Inspector 设计 |
| 2026-04-16 | 导航与布局重构：底部双视图固定、左上角改为通用导航路径、`active_log` 改上下布局、`map_questline` 左树改为节点驱动并去掉“当前任务”入口 |
| 2026-04-16 | 确认 `map_questline` 顶部路径导航改用 Blizzard `NavBar` 组件，并将其锚到右侧内容区头部以避让宿主头像 / 搜索框 |
| 2026-04-16 | 确认任务列表交互收口：任务名 / 任务线名采用运行时 API 优先；点击任务改为列表内展开详情；tooltip 与聊天调试输出退出主交互 |
| 2026-04-16 | 确认行内详情类型显示：使用“类型名字（ID）”格式，类型名来源统一复用 `Toolbox.Questlines` 的类型标签解析 |
| 2026-04-17 | 确认顶部路径导航最终布局：导航栏上移到宿主标题栏下方的独立头部带，并显示在头像 / 图标右侧，正文区整体下移，视觉参考冒险手册副本节点页 |
| 2026-04-18 | 确认任务线主视图状态区与行高收口：移除“下一步”长文案，仅保留“已完成”；任务线卡片改双行高度；展开任务行改回单行并隐藏任务线名称；移除“在进行中视图查看”按钮 |
| 2026-04-29 | 设置宿主重构对齐：Quest Inspector 改为“任务”叶子页内低频工具区，不再描述独立设置子页面 |

## 10. 2026-04-26 渲染与缓存架构收口

### 10.1 状态

- 已确认
- 可执行

### 10.2 目标

- 彻底消除 `quest` 主界面首次打开时因重复渲染、导航模型整包重建与右侧列表一次性建控件而触发的 `script ran too long`。
- 把 `active_log` 与 `map_questline / campaign / achievement` 的数据路径解耦，避免“当前任务”视图继续承担资料片导航计算成本。
- 把 quest 运行时数据读取从“按秒失效 + 视图层重复补查询”收口为“事件驱动失效 + API 层一次组装”。
- 把右侧滚动列表从“按总行数建 Button”收口为“固定按钮池 + 滚动复用”的虚拟列表实现。

### 10.3 选定方案

- 选定方案：分三层同时重构，而不是只在 `QuestNavigation.lua` 某一处加节流或延时。
- 三层边界如下：
  - `Toolbox/Modules/Quest.lua`：只负责打开 / 关闭宿主、事件接入与模块生命周期，不再主动重复触发视图层 `setSelected + refresh`。
  - `Toolbox/Modules/Quest/QuestNavigation.lua`：负责视图状态到 UI 的映射、渲染调度与列表池化，不直接承担运行时缓存策略。
  - `Toolbox/Core/API/QuestlineProgress.lua`：负责导航模型缓存、当前任务快照、任务详情缓存与失效时机；界面层只消费已组装好的结果。

### 10.4 已确认决策

- 打开链路必须收口为“单入口、单次完整渲染”。
  `Toolbox.Quest.OpenMainFrame()` 只负责显示宿主框体；`OnShow` 作为唯一激活入口；若视图已处于相同选中状态，不再重复触发 `updateVisibility()`。
- `active_log` 必须走快路径。
  当 `selectedModeKey == "active_log"` 时，`QuestNavigation` 不再调用资料片导航模型构建与默认资料片修正逻辑，只构建当前任务 / 最近完成两块内容和对应 breadcrumb。
- quest 运行时缓存必须改为事件驱动失效。
  当前基于 `GetTime()` 的整秒缓存键不再作为导航模型与 Quest Log 快照的主失效条件；后续改为由任务日志变化事件、任务交付事件或测试注入重置显式推进 revision。
- 当前任务视图所需数据必须由 `Toolbox.Questlines` 一次组装。
  `GetCurrentQuestLogEntries()` 返回值需要直接携带界面渲染所需的任务名、任务线名、状态、类型、上下文等字段；`QuestNavigation` 不再为筛选而逐条二次补 `GetQuestDetailByID()`。
- 最近完成列表允许按需补详情，但必须复用同一批详情缓存，不得在同一轮 render 中重复解析相同 questID。
- 右侧主区、当前任务区、最近完成区必须统一采用固定按钮池渲染。
  Button 总数应与可见区高度相关，而不是与数据总行数相关；滚动时只复用按钮并换绑 `rowData`。
- 渲染调度必须支持同帧合并。
  任务点击、模式切换、搜索、最近完成更新等入口不再层层直接 `self:render()`，而是统一经渲染调度入口收口，避免一次用户动作触发多轮全量渲染。

### 10.5 非目标

- 不通过降低 `questRecentCompletedMax`、隐藏行内详情、移除现有视图模式等方式掩盖问题。
- 不用 `C_Timer.After(正数秒)` 等固定延时作为“等布局”或“避开超时”的主路径。
- 不新增新的玩家入口、slash 命令或额外模块。

### 10.6 影响文件

- 修改：
  - `Toolbox/Modules/Quest.lua`
  - `Toolbox/Modules/Quest/QuestNavigation.lua`
  - `Toolbox/Core/API/QuestlineProgress.lua`
  - `docs/designs/quest-design.md`
  - `docs/plans/quest-plan.md`
  - `docs/tests/quest-test.md`
  - `tests/logic/spec/quest_module_spec.lua`
  - `tests/logic/spec/questline_progress_spec.lua`
  - 如按钮池行为需要读取滚动信息，按最小范围调整 `tests/logic/harness/fake_frame.lua` / `harness.lua`

### 10.7 验证重点

- 首次打开 quest 主界面时，只出现一次完整渲染提交。
- `active_log` 打开与切回时，不再依赖资料片导航模型。
- Quest Log 与最近完成数据在同一轮渲染中不再对同一任务重复补详情。
- 右侧 / 当前任务 / 最近完成三类滚动区的按钮数量与可见区相关，而不是与总行数线性增长。
- 既有行内详情、跳转到对应地图 / 任务线、Quest Inspector 等行为保持不变。
