# 设置宿主重构计划

- 文档类型：计划
- 状态：执行中
- 主题：settings-host-redesign
- 适用范围：`Toolbox/UI/SettingsHost.lua` 的第二阶段设置控件统一、模块 `RegisterSettings(box)` 迁移、战斗内独立宿主兼容，以及相关测试 / 文档回写
- 关联模块：`mover`、`tooltip_anchor`、`navigation`、`quest`、`encounter_journal`、`minimap_button`、`chat_notify`
- 关联文档：
  - `docs/specs/settings-host-redesign-spec.md`
  - `docs/designs/settings-host-redesign-design.md`
  - `docs/Toolbox-addon-design.md`
- 最后更新：2026-05-02

> 本计划承接 `settings-host-redesign` 第一阶段已完成的纯叶子页结构重构，覆盖第二阶段页内控件统一，以及 2026-05-02 新增的“现代化视觉收口”。上一轮自动化实现虽然通过，但实机暴露出“非动作项被按钮化”的偏差，因此本计划重新进入执行中状态，先修正宿主控件观感，再做新一轮自动化与游戏内验证。

## 1. 目标

- 以测试先行的方式，把现有 6 个叶子页内部的旧式设置控件统一为宿主级原生列表式设置行，同时保持 `ToolboxDB` 兼容、模块行为不变，并覆盖行级依赖、局部刷新、自定义内容块高度收口，以及战斗内独立宿主模式。

## 2. 输入文档

- 需求：
  - `docs/specs/settings-host-redesign-spec.md`
- 设计：
  - `docs/designs/settings-host-redesign-design.md`
- 其他约束：
  - 不新增模块、不新增玩家可见入口、不修改 `Toolbox/Toolbox.toc`。
  - 保留 6 个叶子页和模块归属，不回退到总览页模型。
  - `RegisterSettings(box)` 继续作为唯一模块设置入口，不新增独立内容块注册接口。
  - `ToolboxDB` 键名、取值语义与模块归属保持不变；非法枚举值允许在页面构建阶段归一为默认值并写回。
  - 页面注册只在宿主初始化阶段执行一次；语言切换走 `RefreshAllPages()`；局部状态变化优先局部刷新；影响显隐 / 行数 / 高度时才走 `BuildPage()`。
  - 战斗内独立宿主模式的打开优先级为：显式目标页 > `settingsLastLeafPage` > `通用`；宿主内切页后要更新 `settingsLastLeafPage`，且不得重新注册类目、不得调用 `Settings.OpenToCategory`。
  - 用户 2026-05-02 明确确认采用“保留 helper、重写行控件观感”的方案 A；实施必须在隔离 worktree 分支 `codex/settings-ui-modernize` 中进行，避免影响当前主工作区未提交改动。

## 3. 影响文件

- 新增：
  - `tests/logic/spec/settings_host_spec.lua`
- 修改：
  - `tests/validate_settings_subcategories.py`
  - `Toolbox/UI/SettingsHost.lua`
  - `Toolbox/Core/Foundation/Locales.lua`
  - `Toolbox/Modules/ChatNotify.lua`
  - `Toolbox/Modules/TooltipAnchor.lua`
  - `Toolbox/Modules/Mover.lua`
  - `Toolbox/Modules/MinimapButton.lua`
  - `Toolbox/Modules/Quest.lua`
  - `Toolbox/Modules/EncounterJournal.lua`
  - `Toolbox/Modules/Navigation.lua`
  - `docs/Toolbox-addon-design.md`
  - `docs/specs/settings-host-redesign-spec.md`
  - `docs/designs/settings-host-redesign-design.md`
  - `docs/plans/settings-host-redesign-plan.md`
- 视实现需要可补充：
  - `tests/logic/spec/config_spec.lua`
  - `tests/logic/spec/quest_module_spec.lua`
  - `docs/features/*.md`
- 验证：
  - `python tests/validate_settings_subcategories.py`
  - `python tests/run_all.py --ci`
  - 定向：`busted tests/logic/spec/settings_host_spec.lua`
  - 基线：在隔离 worktree 中先运行一次 `python tests/run_all.py --ci`，预期全绿后再开始改代码

## 4. 执行步骤

## Chunk 1: 锁定测试与宿主契约

- [x] 步骤 1：收到用户明确“开动”后，将 `docs/specs/settings-host-redesign-spec.md` 状态改为 `可执行`，并把本计划状态改为 `执行中`。
- [x] 步骤 2：更新 `tests/validate_settings_subcategories.py`，先写失败校验，锁定以下口径：
  - `SettingsHost.lua` 不再出现 `UIDropDownMenu_*`、`InterfaceOptionsCheckButtonTemplate`、`UICheckButtonTemplate` 旧链路。
  - 宿主存在统一 helper / row builder / 局部刷新入口 / 自定义块高度回报入口关键标识。
  - 叶子页与 `settingsLastLeafPage` 逻辑仍保留，战斗内独立宿主路径不通过系统类目重复注册完成切页。
- [x] 步骤 3：新增 `tests/logic/spec/settings_host_spec.lua`，先写失败测试，覆盖以下最小逻辑：
  - 非法叶子页 key 会回退到 `通用`。
  - 非法单选 / 下拉值会在宿主构建阶段归一为默认值，并写回 DB。
  - 行级依赖变化只触发当前行 / 当前组局部刷新；只有显隐、行数、`realHeight` 或自定义块高度变化时才走 `BuildPage()`。
  - 自定义内容块可通过 `RegisterSettings(box)` 挂入宿主，并向宿主回报实际高度。
  - 语言切换触发 `RefreshAllPages()` 全量重建，而不是重新注册类目。
  - 战斗内独立宿主模式的 direct-open 优先级为“显式目标页 > `settingsLastLeafPage` > `通用`”。
  - 战斗内宿主内切页会更新 `settingsLastLeafPage`，且不会调用 `Settings.OpenToCategory`。
- [x] 步骤 4：视落地方式扩展 `tests/logic/spec/config_spec.lua` 或等价测试，先写失败用例，锁定“经设置宿主写回的代表性设置值在模拟重载后仍保值”。
- [x] 步骤 5：运行定向失败验证。
  - `python tests/validate_settings_subcategories.py`
  - `busted tests/logic/spec/settings_host_spec.lua`
  - 如新增：`busted tests/logic/spec/config_spec.lua`
  - 预期：按新口径失败，失败点对应第二阶段改造目标。

## Chunk 2: 宿主 helper 层、刷新策略与独立宿主约束

- [x] 步骤 6：重构 `Toolbox/UI/SettingsHost.lua`，显式建立宿主 helper 契约，至少收口以下能力：
  - 分节标题
  - toggle 行
  - 单值选择行
  - 多选列表
  - 菜单 / 下拉按钮行
  - 操作按钮行
  - 简短说明块
  - 自定义内容块入口与高度回报
  - 行级依赖声明与局部刷新入口
- [x] 步骤 7：在 `SettingsHost.lua` 中落实宿主 / 模块职责边界：
  - 宿主统一承载语言、reload、`enabled / debug / reset` 等公共区块。
  - 普通模块的 `RegisterSettings(box)` 只负责模块专属设置项与必要自定义块。
  - 页面注册只执行一次；`RefreshAllPages()` 和 `BuildPage()` 分工与设计文档一致。
- [x] 步骤 8：在 `SettingsHost.lua` 中实现刷新分层规则：
  - 仅影响勾选态、标题文案、辅助说明或禁用态时，优先局部刷新当前行或当前组。
  - 仅当依赖切换会改变区块显隐、行数、`realHeight` 或自定义块高度时，才重建当前叶子页。
  - `MinimapButton`、`Quest` 现有依赖较强路径如仍需整页重建，必须通过统一入口触发，避免退化成任意变更都全页重建。
- [x] 步骤 9：在 `SettingsHost.lua` 中补齐自定义块承载规则：
  - 复杂内容块仍通过 `RegisterSettings(box)` 进入宿主。
  - 宿主为内容块提供稳定锚点、刷新时机与高度回报路径。
  - `Quest` 现有自定义块迁移到该路径时，不再自行收口整页高度。
- [x] 步骤 10：在 `SettingsHost.lua` 中补齐异常值回退与战斗内独立宿主规则：
  - 非法值归一、`settingsLastLeafPage` 回退和 direct-open 优先级。
  - 独立宿主内切页成功后更新 `settingsLastLeafPage`。
  - 独立宿主路径不得重新注册类目，不得调用 `Settings.OpenToCategory`。
  - 若系统 Settings 专属控件在独立宿主中不稳定，宿主需提供等价封装。
- [x] 步骤 11：定向运行宿主相关测试，确认 helper 层、刷新策略、自定义块契约和独立宿主约束转绿。
  - `busted tests/logic/spec/settings_host_spec.lua`
  - 如新增：`busted tests/logic/spec/config_spec.lua`
  - `python tests/validate_settings_subcategories.py`

## Chunk 3: 迁移复杂控件与依赖较强模块

- [x] 步骤 12：迁移 `Toolbox/Modules/ChatNotify.lua`：
  - 将两个颜色下拉从 `UIDropDownMenuTemplate` 改为宿主菜单按钮行。
  - 保持颜色值语义不变；若彩色标签不稳定，则改为“文字名 + 当前效果预览”。
- [x] 步骤 13：迁移 `Toolbox/Modules/TooltipAnchor.lua` 与 `Toolbox/Modules/Mover.lua`：
  - 将互斥勾选改为单值选择 / segmented 行。
  - 保持原有即时生效逻辑。
- [x] 步骤 14：迁移 `Toolbox/Modules/MinimapButton.lua`：
  - 普通开关改为统一 toggle 行。
  - 坐标锚点改为双项 segmented 行。
  - flyout 项改为统一多选列表。
  - 保持现有依赖驱动的局部刷新 / 重建语义，不退化为统一全页重建。
- [x] 步骤 15：运行复杂控件迁移后的定向验证。
  - `python tests/validate_settings_subcategories.py`
  - `busted tests/logic/spec/settings_host_spec.lua`
  - `python tests/run_all.py --ci`（允许先失败，用于观察回归面）

## Chunk 4: 迁移简单模块、收文案与全量验证

- [x] 步骤 16：迁移 `Toolbox/Modules/Quest.lua`、`EncounterJournal.lua`、`Navigation.lua`，把现有简单设置项统一到新的 toggle / action / note 节奏；Quest 自定义块改走宿主自定义块入口，并通过高度回报纳入统一布局。
- [x] 步骤 17：更新 `Toolbox/Core/Foundation/Locales.lua`，删减冗余说明文案，补齐新的短文案与必要标签。
- [x] 步骤 18：运行全量自动化验证。
  - `python tests/validate_settings_subcategories.py`
  - `busted tests/logic/spec/settings_host_spec.lua`
  - 如新增：`busted tests/logic/spec/config_spec.lua`
  - `python tests/run_all.py --ci`
  - 预期：全部通过。
- [ ] 步骤 19：执行系统设置页路径的人工验证。
  - 从 `/toolbox`、ESC 菜单按钮和小地图按钮分别打开设置页。
  - 修改至少一组 toggle、一组单选、一组多选和一组菜单选择后执行 `/reload`。
  - 预期：界面回到同一叶子页，值与控件状态保留，非法值不会复现。
- [ ] 步骤 20：执行战斗内独立宿主路径的人工验证。
  - 以显式目标页、最近叶子页和默认 `通用` 三种方式打开独立宿主。
  - 在独立宿主内切换叶子页并确认 `settingsLastLeafPage` 更新。
  - 验证切页与控件交互过程中不会重新注册类目，也不会走 `Settings.OpenToCategory`。
  - 预期：新控件在独立宿主中与系统设置页保持等价可操作。
- [x] 步骤 21：回写 `docs/Toolbox-addon-design.md`，同步第二阶段 helper 模型、控件统一口径、局部刷新规则和战斗内独立宿主约束；如某模块功能说明的设置项描述已失真，再同步对应 `docs/features/*.md`。
- [ ] 步骤 22：补记 `docs/specs/settings-host-redesign-spec.md`、`docs/designs/settings-host-redesign-design.md`、`docs/plans/settings-host-redesign-plan.md` 执行结果与验证结论。

## Chunk 5: 现代化视觉收口（2026-05-02）

- [x] 步骤 23：在隔离 worktree `codex/settings-ui-modernize` 中复核基线，并把用户确认结果写回现有 spec / design / plan。
  - 已完成：`python tests/run_all.py --ci` 基线全绿。
- [x] 步骤 24：先写失败约束，锁定“非动作项不得再以 `UIPanelButtonTemplate` 红底按钮作为主视觉”。
  - 修改：
    - `tests/validate_settings_subcategories.py`
    - 如需更细粒度行为约束：`tests/logic/spec/settings_host_spec.lua`
  - 目标：
    - `AddToggleRow`、`AddChoiceRow`、`AddMenuRow`、`AddMultiSelectRow` 不再以普通动作按钮模板作为主承载
    - `AddActionRow` 继续允许使用按钮模板
- [x] 步骤 25：按 TDD 方式重构 `Toolbox/UI/SettingsHost.lua` 行控件实现。
  - toggle：
    - 改为更接近 Retail Settings 的 checkbox / switch 观感
    - 去掉 `ON / OFF` 文本按钮主视觉
  - choice：
    - 两项选中态改为 segmented / pill 风格
  - menu：
    - 触发器保留可点击入口，但观感改为现代 dropdown，而不是通用红底按钮
  - multi-select：
    - 改为 checkbox 列表，不再使用 `[x]` / `[ ]` 按钮文本
  - action：
    - 继续保留按钮观感，仅用于真正执行动作的设置行
- [x] 步骤 26：如控件现代化只需宿主层即可完成，则不要顺手修改模块行为代码；仅在 helper 参数或短文案必须调整时，最小化修改相关模块或本地化文件。
  - 优先保持变更集中在：
    - `Toolbox/UI/SettingsHost.lua`
    - `tests/validate_settings_subcategories.py`
    - `tests/logic/spec/settings_host_spec.lua`
    - 必要时：`Toolbox/Core/Foundation/Locales.lua`
- [x] 步骤 27：运行现代化收口后的自动化验证。
  - `python tests/validate_settings_subcategories.py`
  - `busted tests/logic/spec/settings_host_spec.lua`
  - `python tests/run_all.py --ci`
  - 结果：已通过
- [ ] 步骤 28：补记本轮实现结果，并把计划状态推进到“待人工验证”或“已完成”。

## 5. 验证

- 自动化检查 1：
  - `python tests/validate_settings_subcategories.py`
  - 预期：旧式控件链路与旧布局口径被移除，宿主 helper / 局部刷新 / 自定义块 / 独立宿主关键口径存在。
- 自动化检查 2：
  - `busted tests/logic/spec/settings_host_spec.lua`
  - 预期：非法值归一、叶子页回退、局部刷新分层、自定义块高度回报、语言切换重建，以及战斗内 direct-open / 宿主内切页规则通过。
- 自动化检查 3：
  - 如新增：`busted tests/logic/spec/config_spec.lua`
  - 预期：代表性设置值经宿主写回后，在模拟重载初始化后仍保值。
- 自动化检查 4：
  - `python tests/run_all.py --ci`
  - 预期：全量自动化通过，无新增回归。
- 自动化检查 5：现代化视觉约束
  - `python tests/validate_settings_subcategories.py`
  - 预期：toggle / choice / menu / multi-select 不再落回 `UIPanelButtonTemplate` 主视觉，只有 action row 继续允许按钮模板。
- 游戏内验证 A：系统 Settings 路径
  - `/toolbox`、ESC 菜单按钮和小地图按钮仍会打开同一套叶子页结构。
  - 系统设置页可使用新的 toggle / 单选 / 菜单 / 多选交互。
  - 修改代表性设置后 `/reload`，页面与值都保持一致。
  - 语言切换后，当前页与其它叶子页文案会完整重建，且不会重复注册类目。
- 游戏内验证 B：战斗内独立宿主路径
  - 显式目标页、`settingsLastLeafPage` 和 `通用` 回退优先级符合设计。
  - 宿主内切页会更新 `settingsLastLeafPage`，且不通过重新注册类目实现。
  - 切页与控件交互时不调用系统 `Settings.OpenToCategory`。
  - 新控件在独立宿主中保持等价可操作，无“可见但不可稳定交互”的退化。
- 游戏内验证 C：布局与即时生效
  - `ChatNotify`、`TooltipAnchor`、`Mover`、`MinimapButton` 的设置改动后，保持原有即时生效或原有生效时机。
  - 页面滚动区无截断、重叠或明显间距错乱。

## 6. 风险与回滚

- 风险：
  - `SettingsHost.lua` 同时承担宿主、helper、局部刷新和战斗内独立模式四类职责，若一次性改太多，容易让文件局部变得难以验证。
  - `MinimapButton` 和 `Quest` 现有的依赖与重建链路较强，迁移时最容易引入刷新过度、刷新不及时或高度收口不准。
  - `ChatNotify` 的颜色菜单和战斗内独立宿主模式是两条最容易出现“可见但不可稳定交互”的路径。
- 回滚方式：
  - 按 chunk 提交，优先保持宿主 helper 层和模块迁移分开；若复杂模块回归过多，可先保留 helper 层，局部回退某一模块的 UI 迁移。
  - 若局部刷新规则验证不过，优先停在 helper 契约提交点，避免把模块迁移和刷新策略问题混在一起排查。
  - 若战斗内独立宿主模式验证不过，优先为该模式补等价封装，不通过时不推进全量替换。
  - 若全量验证显示范围过大，可先停在复杂模块迁移完成的提交点，避免把文档回写和代码回归混在同一提交内。

## 7. 执行记录

- 2026-04-29：第一阶段（纯叶子页结构重构）已落地，旧计划已完成。
- 2026-05-01：第二阶段需求与设计已更新，计划已补齐并通过复审。
- 2026-05-01：用户明确回复“开动”，需求状态已改为可执行，计划状态改为执行中，开始进入 Chunk 1。
- 2026-05-01：自动化实现完成；`TooltipAnchor` 收口为 3 项菜单按钮，`SettingsHost` 菜单弹层抬到 `DIALOG` strata，`python tests/run_all.py --ci` 通过，当前待游戏内手工验证系统设置页与战斗内独立宿主路径。
- 2026-05-02：用户确认继续按方案 A 收口“红底按钮”视觉偏差，并要求在隔离 worktree `codex/settings-ui-modernize` 中实施；该 worktree 基线 `python tests/run_all.py --ci` 已通过。
- 2026-05-02：Chunk 5 自动化完成；`SettingsHost` 非动作项已改为自绘现代控件，新增“仅 action row 保留按钮模板”的测试约束，`python tests/run_all.py --ci` 再次通过。

## 8. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-29 | 初稿：第一阶段纯叶子页结构与 Quest Inspector 承载迁移计划 |
| 2026-04-29 | 第一阶段完成：计划状态改为已完成 |
| 2026-05-01 | 第二阶段续写：补充宿主 helper 层、模块控件迁移、战斗内独立宿主兼容与测试先行步骤 |
| 2026-05-01 | 根据计划评审补充行级依赖 / 局部刷新、自定义块高度回报、独立宿主切页约束与 `/reload` 保值验证 |
| 2026-05-01 | 自动化实现完成：状态更新为待人工验证，补记菜单弹层层级修正与 `run_all.py --ci` 通过结果 |
| 2026-05-02 | 因实机发现“非动作项被按钮化”为红底按钮墙，计划重新进入执行中，新增 Chunk 5 处理现代化视觉收口 |
| 2026-05-02 | 记录用户确认的方案 A 与隔离 worktree 分支 `codex/settings-ui-modernize`，并补记基线测试通过 |
| 2026-05-02 | Chunk 5 自动化完成：`SettingsHost` 非动作项改为现代自绘控件，模板约束测试与 `run_all.py --ci` 通过 |

