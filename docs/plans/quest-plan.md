# 任务模块现状基线与演进计划

- 文档类型：计划
- 状态：可执行
- 主题：quest
- 适用范围：`quest` 当前独立任务界面、导航、最近完成与 Quest Inspector 的文档基线
- 关联模块：`quest`、`minimap_button`
- 关联文档：
  - `docs/features/quest-features.md`
  - `docs/specs/quest-spec.md`
  - `docs/designs/quest-design.md`
  - `docs/tests/quest-test.md`
  - `docs/plans/encounter-journal-plan.md`
- 最后更新：2026-04-18

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
| 2026-04-17 | 追加页签外置收口计划：确认底部分页签对齐 Blizzard 冒险指南根页签，挂在 `panelFrame` 外侧下沿并移除内容区底部占位 |

## 9. 2026-04-16 导航节点与双视图重构计划

### 9.1 目标

- 把 `quest` 模块内写死的左树导航状态收敛为“通用节点 + 当前选中节点 + 导航路径”模型。
- 保留底部 `当前任务` / `任务线` 两个视图页签，其中 `当前任务` 改为上下布局，`任务线` 保持左树 + 右区布局。

### 9.2 影响文件

- 修改：
  - `docs/specs/quest-spec.md`
  - `docs/designs/quest-design.md`
  - `docs/plans/quest-plan.md`
  - `docs/tests/quest-test.md`
  - `tests/logic/spec/quest_module_spec.lua`
  - `tests/logic/harness/harness.lua`
  - `Toolbox/Modules/Quest/QuestNavigation.lua`
- 验证：
  - `python tests/run_all.py --logic-only`
    说明：若仓库当前入口不支持 `--logic-only`，则退回执行具体 `busted` 目标或单文件逻辑测试命令。

### 9.3 执行步骤

- [ ] 步骤 1：先更新 `quest` 的 spec / design / plan，写入已确认的导航节点模型、通用导航路径和双视图布局。
- [ ] 步骤 2：在 `tests/logic/spec/quest_module_spec.lua` 先补失败测试，覆盖底部分页签、导航路径可回退、`active_log` 上下布局与历史完成折叠。
- [ ] 步骤 3：扩展测试 harness 暴露新 UI 结构所需的最小读取能力。
- [ ] 步骤 4：在 `Toolbox/Modules/Quest/QuestNavigation.lua` 实现模块内通用节点导航模型，并把 `map_questline` 左树切到节点驱动。
- [ ] 步骤 5：重构 `active_log` 视图布局为上下两段，保持最近完成与当前任务的数据来源不变。
- [ ] 步骤 6：运行 quest 相关逻辑测试，确认新测试先红后绿，再更新 `docs/tests/quest-test.md` 的结果与手工验证点。

### 9.4 风险与控制

- 风险：
  `QuestNavigation.lua` 当前状态、布局与详情弹框高度耦合，直接重构容易把现有 breadcrumb、搜索、详情弹框联动一起打坏。
- 控制方式：
  优先通过测试锁住视图页签、路径文本和关键布局容器，再做最小结构迁移。

### 9.5 当前决策

- 通用导航先只做在 `quest` 模块内部。
- 节点模型不承载回调式路由，只承载节点上下文。
- 左上角显示通用导航路径，路径祖先节点支持点击回退。
- `当前任务` 页签不做左右分栏，只做上下两块；历史完成可折叠，折叠后当前任务占满。
- 已确认底部分页签的最终落点：参照 Blizzard 冒险指南根页签实现，`当前任务` / `任务线` 两枚页签继续挂在 `ToolboxQuestFrame` 根级，并锚到宿主底边、位于唯一视图框 `panelFrame` 外侧下方；`QuestNavigation.lua` 的内容布局不再为页签预留内部 `bottomInset`。
- 已确认宿主与内容框样式目标：`ToolboxQuestFrame` 标题区对齐 Blizzard 冒险指南 `PortraitFrameTemplate`，`panelFrame` 锚点贴近宿主内框；`leftTree` / `rightContent` 退回布局容器角色，不再单独绘制整框边线。

## 10. 2026-04-17 页签外置收口计划

### 10.1 目标

- 把 `当前任务` / `任务线` 页签从“占用视图内部底边距”的现状收口为“挂在宿主底边、位于唯一视图框外侧下方”的实现。
- 保持 `panelFrame` 为唯一视图框，内部内容区高度不再因底部分页签而缩短。

### 10.2 影响文件

- 修改：
  - `docs/designs/quest-design.md`
  - `docs/plans/quest-plan.md`
  - `tests/logic/harness/fake_frame.lua`
  - `tests/logic/spec/quest_module_spec.lua`
  - `Toolbox/Modules/Quest/QuestNavigation.lua`
- 验证：
  - `busted tests/logic/spec/quest_module_spec.lua`

### 10.3 执行步骤

- [x] 步骤 1：先把已确认的外置页签决策写入 `quest` 设计 / 计划文档。
- [x] 步骤 2：补失败测试，覆盖“页签父级仍是 `ToolboxQuestFrame`、锚在宿主底边、内容区不再保留底部页签占位”。
- [x] 步骤 3：扩展 fake frame 的最小锚点记录能力，供 quest 逻辑测试读取。
- [x] 步骤 4：在 `Toolbox/Modules/Quest/QuestNavigation.lua` 调整底部分页签锚点，并移除内容区的 `bottomInset` 预留。
- [x] 步骤 5：运行 quest 模块逻辑测试，确认新增回归测试先红后绿。

### 10.4 风险与控制

- 风险：
  `panelFrame` 当前底边距与宿主框体高度是联动关系，页签改到宿主底边后若仍保留旧的内容预留，会出现“页签下去了但内容区仍旧短一截”的假修复。
- 控制方式：
  测试同时锁住“页签锚点”和“内容区不再使用底部内缩”两项，避免只改一半。

## 11. 2026-04-17 标题样式与边框贴合收口计划

### 11.1 目标

- 把 `ToolboxQuestFrame` 从对话框式标题条收口为冒险指南同类 `PortraitFrame` 标题风格。
- 消除宿主框与唯一视图框、以及唯一视图框与内部布局容器之间多余的整框边线和大间距。

### 11.2 影响文件

- 修改：
  - `docs/designs/quest-design.md`
  - `docs/plans/quest-plan.md`
  - `tests/logic/harness/fake_frame.lua`
  - `tests/logic/spec/quest_module_spec.lua`
  - `Toolbox/Modules/Quest.lua`
  - `Toolbox/Modules/Quest/QuestNavigation.lua`
- 验证：
  - `busted tests/logic/spec/quest_module_spec.lua`

### 11.3 执行步骤

- [x] 步骤 1：把宿主标题样式和边框贴合目标写入 `quest` 设计 / 计划文档。
- [x] 步骤 2：补失败测试，覆盖“宿主为 `PortraitFrame` 风格、`panelFrame` 贴近宿主内框、`leftTree/rightContent` 不再绘制整框边线”。
- [x] 步骤 3：扩展 fake frame 的最小标题 / 头像记录能力，供逻辑测试读取。
- [x] 步骤 4：在 `Toolbox/Modules/Quest.lua` 把宿主框体切到 `PortraitFrame` 风格标题实现。
- [x] 步骤 5：在 `Toolbox/Modules/Quest/QuestNavigation.lua` 收紧 `panelFrame` 锚点，并去掉 `leftTree/rightContent` 的整框边线。
- [x] 步骤 6：运行 quest 模块逻辑测试，确认新增回归测试先红后绿。

## 12. 2026-04-16 顶部路径导航 NavBar 收口计划

### 12.1 状态

- 已确认
- 可执行

### 12.2 目标

- 把 `quest` 模块 `map_questline` 视图顶部路径导航从自绘 `UIPanelButtonTemplate` 按钮条收口为 Blizzard `NavBar` 组件。
- 视觉对齐冒险指南地下城页签的原生路径导航，同时修正当前路径被宿主左上角头像 / 图标盖住的问题。
- 保持现有路径层级与点击回退行为不变，不新增存档键。

### 12.3 影响文件

- 修改：
  - `docs/specs/quest-spec.md`
  - `docs/designs/quest-design.md`
  - `docs/plans/quest-plan.md`
  - `docs/tests/quest-test.md`
  - `tests/logic/harness/fake_frame.lua`
  - `tests/logic/harness/harness.lua`
  - `tests/logic/spec/quest_module_spec.lua`
  - `Toolbox/Modules/Quest/QuestNavigation.lua`
- 验证：
  - `lua tests/run_busted.lua tests/logic/spec/quest_module_spec.lua`
    说明：若仓库当前入口不存在该脚本，则退回到仓库可用的 quest 单文件逻辑测试命令。

### 12.4 已确认决策

- 选定方案 `B`：直接接入 Blizzard `NavBar` 组件，不再沿用自绘 breadcrumb 按钮条。
- `NavBar` 只替换渲染层与锚点，不改变现有 breadcrumb 数据来源。
- `NavBar` 锚到 `rightContent` 头部区域，左侧避让宿主头像 / 标题图标区，右侧避让搜索框。
- 祖先节点继续可点击回退，末级节点继续表示当前位置。

### 12.5 执行步骤

- [x] 步骤 1：先补失败测试，锁定“`map_questline` 使用 `NavBar`、祖先节点可点击、顶部路径不再锚到宿主左上角而是避让搜索框”的回归口径。
- [x] 步骤 2：按测试需要扩展 fake frame / harness 的最小 `NavBar` 记录能力。
- [x] 步骤 3：在 `Toolbox/Modules/Quest/QuestNavigation.lua` 接入 Blizzard `NavBar`，并移除旧的 breadcrumb 按钮条渲染。
- [x] 步骤 4：调整头部布局锚点，使 `NavBar` 与搜索框共存且不再被宿主头像 / 图标遮挡。
- [x] 步骤 5：运行 quest 逻辑测试，确认新增用例先红后绿，再更新 `docs/tests/quest-test.md` 记录。

### 12.6 风险与控制

- 风险：
  `NavBar` 接入若只替换按钮外观、不同步修正头部锚点，路径仍可能与头像区或搜索框冲突，形成“样式像了但布局没修好”的半成品。
- 控制方式：
  测试同时锁住 `NavBar` 的存在、祖先节点可点击，以及头部锚点必须落在右侧内容区 / 搜索框左侧三项约束。

### 12.7 执行结果

- `tests/logic/spec/quest_module_spec.lua` 已按 TDD 先红后绿。
- 使用 harness 的相关逻辑测试集（`encounter_journal_*` + `quest_module_spec`）已通过，确认本轮 `fake_frame` / `harness` 调整未引入回归。

## 13. 2026-04-16 名称显示与列表内展开计划

### 13.1 状态

- 已确认
- 可执行

### 13.2 目标

- 把 `quest` 模块任务列表中的任务名与任务线名统一为“运行时 API 优先、静态数据回退”的显示口径。
- 把点击任务后的主交互从“tooltip + 详情弹框 + 聊天调试输出”收口为“当前列表内展开详细信息”。
- 保留跳转到对应地图 / 任务线与切换到“当前任务”视图的动作，但将其搬到行内展开区。

### 13.3 影响文件

- 修改：
  - `docs/specs/quest-spec.md`
  - `docs/designs/quest-design.md`
  - `docs/plans/quest-plan.md`
  - `docs/tests/quest-test.md`
  - `tests/logic/spec/quest_module_spec.lua`
  - `tests/logic/harness/fake_frame.lua`
  - `tests/logic/harness/harness.lua`
  - `Toolbox/Core/API/QuestlineProgress.lua`
  - `Toolbox/Modules/Quest/QuestNavigation.lua`
- 验证：
  - `"%APPDATA%\\luarocks\\bin\\busted.cmd" tests/logic/spec/quest_module_spec.lua`
  - `python tests/run_all.py --ci`
    说明：若共享数据契约校验仍被既有 `instance_questlines` 头注释问题阻塞，应记录为外部已知阻塞，不把它误判为本轮 quest 交互改动回归。

### 13.4 已确认决策

- 选定方案 `B`：任务名与任务线名改为运行时 API 优先，点击任务改为列表内展开详情。
- `quest` 模块中所有玩家可见的任务行都遵循同一名称来源口径。
- 悬停任务时不再显示 tooltip。
- 点击任务后不再调用聊天调试输出。
- 原详情弹框退出主交互路径；如需保留跳转动作，则改为放在行内展开区。

### 13.5 执行步骤

- [x] 步骤 1：先更新 `quest` 的 spec / design / plan / test，写入 API 名称优先、列表内展开、关闭 tooltip、关闭聊天输出的确认结果，并把状态改为可执行。
- [x] 步骤 2：在 `tests/logic/spec/quest_module_spec.lua` 先补失败测试，覆盖任务名 / 任务线名显示口径、点击任务后的列表内展开、tooltip 不再出现、聊天输出不再触发。
- [x] 步骤 3：确认现有 `fake_frame.lua` / `harness.lua` 已能承载本轮断言，无需额外扩展即可读取行内展开区与 tooltip / 聊天调用情况。
- [x] 步骤 4：在 `Toolbox/Core/API/QuestlineProgress.lua` 收口任务名 / 任务线名解析口径，使 `GetCurrentQuestLogEntries()` 与 `GetQuestDetailByID()` 返回一致的 API 优先名称。
- [x] 步骤 5：在 `Toolbox/Modules/Quest/QuestNavigation.lua` 移除任务行 tooltip / 聊天输出路径，并把详情弹框改为列表内展开实现。
- [x] 步骤 6：运行 quest 逻辑测试，确认新增用例先红后绿；再补跑仓库自动化入口并记录外部阻塞。

### 13.6 风险与控制

- 风险：
  `QuestNavigation.lua` 当前把任务点击、副作用输出与详情展示耦合在同一条路径里，直接替换成行内展开时容易漏掉 `active_log`、最近完成与 `map_questline` 的一种或多种任务行。
- 控制方式：
  测试同时锁住三件事：名称显示口径一致、点击后展开详情、tooltip / 聊天副作用不再发生，避免只修掉表面交互而遗留旧副作用。

### 13.7 执行结果

- `tests/logic/spec/quest_module_spec.lua` 已通过，覆盖任务行显示任务线名、点击后列表内展开详情、tooltip 不再出现，以及聊天调试输出不再触发。
- `tests/logic/spec/questline_progress_spec.lua` 中与本轮直接相关的名称口径用例已转绿；文件内仍存在一个既有失败：`quest_navigation_model_groups_questlines_by_expansion_and_category`，与本轮任务行交互改动无直接关系。
- `python tests/run_all.py --ci` 仍被仓库既有的数据契约问题阻塞：`instance_questlines: lua header contract_id mismatch`。

## 14. 2026-04-16 行内详情类型名显示计划

### 14.1 状态

- 已确认
- 可执行

### 14.2 目标

- 把 quest 行内展开详情里的“类型”从纯 `typeID` 收口为“类型名字（ID）”格式。
- 继续复用现有类型映射与本地化口径，不引入新的类型数据源。

### 14.3 影响文件

- 修改：
  - `docs/specs/quest-spec.md`
  - `docs/designs/quest-design.md`
  - `docs/plans/quest-plan.md`
  - `docs/tests/quest-test.md`
  - `tests/logic/spec/quest_module_spec.lua`
  - `tests/logic/spec/questline_progress_spec.lua`
  - `Toolbox/Core/API/QuestlineProgress.lua`
  - `Toolbox/Modules/Quest/QuestNavigation.lua`
- 验证：
  - `"%APPDATA%\\luarocks\\bin\\busted.cmd" tests/logic/spec/questline_progress_spec.lua`
  - `"%APPDATA%\\luarocks\\bin\\busted.cmd" tests/logic/spec/quest_module_spec.lua`

### 14.4 已确认决策

- 行内详情中的“类型”显示为“类型名字（ID）”。
- 名字优先使用现有类型标签解析逻辑。
- 当类型名字无法解析时，回退为纯 ID，避免显示空白。
- 本轮只调整 quest 行内详情显示，不扩大到 Quest Inspector 文本格式。

### 14.5 执行步骤

- [x] 步骤 1：先更新 `quest` 的 spec / design / plan / test，写入“类型名字（ID）”显示口径。
- [x] 步骤 2：在 `tests/logic/spec/questline_progress_spec.lua` 与 `tests/logic/spec/quest_module_spec.lua` 先补失败测试，覆盖详情对象提供 `typeLabel` 以及界面按“类型名字（ID）”渲染。
- [x] 步骤 3：在 `Toolbox/Core/API/QuestlineProgress.lua` 收口详情对象的类型展示字段，确保 `GetQuestDetailByID()` 直接返回 `typeLabel`。
- [x] 步骤 4：在 `Toolbox/Modules/Quest/QuestNavigation.lua` 把详情中的类型文本改为“类型名字（ID）”，并保留纯 ID 兜底。
- [x] 步骤 5：运行相关逻辑测试，确认新增用例先红后绿。

### 14.6 执行结果

- `tests/logic/spec/quest_module_spec.lua` 已通过，新增断言确认行内详情中的类型文本显示为“Campaign(12)”这类“类型名字（ID）”格式。
- `tests/logic/spec/questline_progress_spec.lua` 中与本轮直接相关的新用例已转绿，确认 `GetQuestDetailByID()` 现在直接返回 `typeLabel`。
- `tests/logic/spec/questline_progress_spec.lua` 仍保留一个既有失败：`quest_navigation_model_groups_questlines_by_expansion_and_category`，与本轮类型文本显示改动无直接关系。

## 15. 2026-04-17 标题栏下导航带收口计划

### 15.1 状态

- 已确认
- 可执行

### 15.2 目标

- 把 `quest` 模块顶部路径导航从“正文内容区第一行”收口为“宿主标题栏下方、正文上方”的独立头部带。
- 让导航栏显示在宿主头像 / 标题图标区右侧，视觉参考冒险手册地下城页签进入副本节点后的路径区。
- 保持搜索框与导航栏位于同一头部带中，正文区整体下移，不改变存档键与模块边界。

### 15.3 影响文件

- 修改：
  - `docs/specs/quest-spec.md`
  - `docs/designs/quest-design.md`
  - `docs/plans/quest-plan.md`
  - `docs/tests/quest-test.md`
  - `tests/logic/spec/quest_module_spec.lua`
  - `Toolbox/Modules/Quest/QuestNavigation.lua`
- 验证：
  - `"%APPDATA%\\luarocks\\bin\\busted.cmd" tests/logic/spec/quest_module_spec.lua`

### 15.4 已确认决策

- 顶部路径导航最终落点不是 `rightContent` 内部，而是宿主标题栏与正文之间的独立头部带。
- 导航栏显示在宿主头像 / 标题图标区右侧。
- 搜索框继续位于同一条头部带的右侧。
- 正文内容区整体下移，避免导航栏继续占用正文框第一行。

### 15.5 执行步骤

- [x] 步骤 1：先补失败测试，锁定“导航栏父级 / 锚点进入独立头部带、位于标题栏下方且在图标右侧、正文区整体下移”的回归口径。
- [x] 步骤 2：在 `Toolbox/Modules/Quest/QuestNavigation.lua` 中新增或复用头部容器，承载 `NavBar` 与搜索框。
- [x] 步骤 3：调整 `map_questline` 与 `active_log` 的正文区锚点，使头部带与正文区分层清晰。
- [x] 步骤 4：运行 quest 模块逻辑测试，确认新增用例先红后绿，再更新测试文档结果。

### 15.6 风险与控制

- 风险：
  只改 `NavBar` 锚点、不下移正文区时，会出现“导航栏挪出来了但正文标题 / 列表仍顶上去”的半修状态。
- 控制方式：
  测试同时锁住导航栏父级、导航栏左右避让和正文区顶部锚点三项约束，避免只改一半。

### 15.7 执行结果

- `tests/logic/spec/quest_module_spec.lua` 已按 TDD 先红后绿：先暴露“缺少独立头部带、正文区顶部未下移、`map_questline` 路径条仍挂旧位置”三处失败，再在 `QuestNavigation.lua` 中修正。
- 当前实现已把顶部路径导航与搜索框收口到宿主 `ToolboxQuestFrame` 标题区下方、与标题区背景融合的独立头部带；`NavBar` 按钮改为在该头部带内垂直居中并放大占满可用高度，`active_log` 与 `map_questline` 的正文区重新回到 `panelFrame` 内部起排，避免导航条继续混入正文区。

## 16. 2026-04-17 quest 标题栏拖动接入计划

### 16.1 状态

- 已确认
- 可执行

### 16.2 目标

- 让 `ToolboxQuestFrame` 像冒险指南一样，点击标题栏即可拖动。
- 复用 `Toolbox.Mover.RegisterFrame()` 的自建窗体路径，不在 `quest` 模块里复制拖动逻辑。
- 把拖动命中区限定在宿主标题栏，而不是放大到正文内容区。

### 16.3 影响文件

- 修改：
  - `docs/specs/quest-spec.md`
  - `docs/designs/quest-design.md`
  - `docs/plans/quest-plan.md`
  - `docs/tests/quest-test.md`
  - `tests/logic/harness/fake_runtime.lua`
  - `tests/logic/harness/harness.lua`
  - `tests/logic/spec/quest_module_spec.lua`
  - `Toolbox/Modules/Quest.lua`
- 验证：
  - `"%APPDATA%\\luarocks\\bin\\busted.cmd" tests/logic/spec/quest_module_spec.lua`

### 16.4 已确认决策

- `quest` 宿主框拖动统一通过 `Toolbox.Mover.RegisterFrame()` 接入。
- 拖动命中区优先使用 `ToolboxQuestFrame.TitleContainer`；若运行时缺失该区域，再回退到宿主框体本身。
- 本轮不新增 quest 自己的拖动存档键，沿用 `mover` 模块现有自建窗体存档机制。

### 16.5 执行步骤

- [x] 步骤 1：先补失败测试，锁定“`quest` 宿主框在模块加载时向 `Toolbox.Mover.RegisterFrame()` 完成登记，且拖动命中区位于标题栏”的回归口径。
- [x] 步骤 2：扩展测试 harness / fake runtime，记录 `Toolbox.Mover.RegisterFrame()` 调用以及 `PortraitFrameTemplate` 的标题栏替身。
- [x] 步骤 3：在 `Toolbox/Modules/Quest.lua` 把宿主框接入 `Toolbox.Mover.RegisterFrame()`，并传入标题栏命中区。
- [x] 步骤 4：运行 quest 模块逻辑测试，确认新增用例先红后绿，再更新测试文档结果。

### 16.6 执行结果

- `tests/logic/spec/quest_module_spec.lua` 已按 TDD 先红后绿：先暴露“`quest` 未向 `Toolbox.Mover.RegisterFrame()` 完成登记”的失败，再在 `Quest.lua` 中接入 mover。
- 当前实现会在宿主框创建后调用 `Toolbox.Mover.RegisterFrame(questHostFrame, "ToolboxQuestFrame", { dragRegion = questHostFrame.TitleContainer or questHostFrame })`，拖动与位置记忆统一走 mover 模块的自建窗体路径。

## 17. 2026-04-18 任务线状态区与行高收口计划

### 17.1 状态

- 已确认
- 可执行

### 17.2 目标

- 让 `map_questline` 主视图右侧状态区不再显示“下一步：xxx”长文案。
- 仅在任务线已完成时保留短状态“已完成”；未完成任务线不显示右侧状态词。
- 把任务线主卡片改成双行高度；展开后的任务行改回单行高度，并隐藏任务线名称副标题。
- 删除行内详情中的“在进行中视图查看”按钮。

### 17.3 影响文件

- 修改：
  - `docs/specs/quest-spec.md`
  - `docs/designs/quest-design.md`
  - `docs/plans/quest-plan.md`
  - `docs/tests/quest-test.md`
  - `tests/logic/harness/fake_frame.lua`
  - `tests/logic/spec/quest_module_spec.lua`
  - `Toolbox/Modules/Quest/QuestNavigation.lua`
- 验证：
  - `"%APPDATA%\\luarocks\\bin\\busted.cmd" tests/logic/spec/quest_module_spec.lua`

### 17.4 已确认决策

- 未完成任务线右侧不再显示“下一步：xxx”。
- 已完成任务线右侧仅显示短状态“已完成”。
- 任务线主卡片使用双行高度。
- 展开任务行使用单行高度，并且不显示任务线名称。
- 行内详情删除“在进行中视图查看”按钮。

### 17.5 执行步骤

- [x] 步骤 1：先补失败测试，锁定“未完成任务线右侧状态清空、已完成任务线保留短状态、任务线行双行高度、展开任务行单行且无任务线名称、详情按钮移除”的回归口径。
- [x] 步骤 2：在 `Toolbox/Modules/Quest/QuestNavigation.lua` 中收口状态文案生成逻辑与任务线 / 任务行高度逻辑。
- [x] 步骤 3：在 `Toolbox/Modules/Quest/QuestNavigation.lua` 中移除任务行副标题渲染和“在进行中视图查看”按钮。
- [x] 步骤 4：运行 quest 逻辑测试，确认新增用例先红后绿，再更新测试文档结果。

### 17.6 执行结果

- `tests/logic/spec/quest_module_spec.lua` 已按 TDD 先红后绿：先暴露“未完成任务线仍显示 Next 文案、展开任务行仍为双行高度”的失败，再在 `QuestNavigation.lua` 中收口状态生成与行高逻辑。
- 当前实现已移除任务线主视图右侧的“下一步”长文案，仅在任务线已完成时保留短状态“已完成”；任务线卡片改为双行高度，展开后的任务行改回单行并隐藏任务线名称副标题，同时移除了行内详情中的“在进行中视图查看”按钮。

## 18. 2026-04-18 头部多级导航宽度收口计划

### 18.1 状态

- 已确认
- 可执行

### 18.2 目标

- 让 `quest` 头部多级导航整体宽度受搜索框左边界约束，不再越过搜索框。
- 多级导航文本按可见区域左对齐显示。
- 不改变现有 breadcrumb 数据来源与点击回退行为。

### 18.3 影响文件

- 修改：
  - `docs/specs/quest-spec.md`
  - `docs/designs/quest-design.md`
  - `docs/plans/quest-plan.md`
  - `docs/tests/quest-test.md`
  - `tests/logic/spec/quest_module_spec.lua`
  - `Toolbox/Modules/Quest/QuestNavigation.lua`
- 验证：
  - `"%APPDATA%\\luarocks\\bin\\busted.cmd" tests/logic/spec/quest_module_spec.lua`

### 18.4 已确认决策

- 导航栏整体宽度必须止于搜索框左边界。
- 超出可见宽度的多级路径不得继续覆盖搜索框。
- 导航文本按可见区域左对齐显示。

### 18.5 执行步骤

- [x] 步骤 1：先补失败测试，锁定“breadcrumbFrame 右边界仍锚到搜索框左侧，且导航文本左对齐并不再越过搜索框”的回归口径。
- [x] 步骤 2：在 `Toolbox/Modules/Quest/QuestNavigation.lua` 中收口多级导航按钮宽度与容器内显示宽度。
- [x] 步骤 3：运行 quest 逻辑测试，确认新增用例先红后绿，再更新测试文档结果。

### 18.6 执行结果

- `tests/logic/spec/quest_module_spec.lua` 已按 TDD 先红后绿：先暴露“导航按钮文本未显式左对齐”的失败，再在 `QuestNavigation.lua` 中补齐按钮文本左对齐与右边界约束验证。
- 当前实现继续通过 `breadcrumbFrame:SetPoint("TOPRIGHT", self.searchBoxFrame, "TOPLEFT", -10, 0)` 将导航容器止于搜索框左侧，同时导航按钮文本显式左对齐显示，不再把搜索框覆盖为主要视觉问题。
