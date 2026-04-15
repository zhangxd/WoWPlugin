# 任务模块现状基线与演进计划

- 文档类型：计划
- 状态：执行中
- 主题：quest
- 适用范围：`quest` 当前独立任务界面、导航、最近完成与 Quest Inspector 的文档基线
- 关联模块：`quest`、`minimap_button`
- 关联文档：
  - `docs/features/quest-features.md`
  - `docs/specs/quest-spec.md`
  - `docs/designs/quest-design.md`
  - `docs/tests/quest-test.md`
  - `docs/plans/encounter-journal-plan.md`
- 最后更新：2026-04-17

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
