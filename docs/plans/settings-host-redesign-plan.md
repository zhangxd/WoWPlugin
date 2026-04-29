# 设置宿主重构计划

- 文档类型：计划
- 状态：已完成
- 主题：settings-host-redesign
- 适用范围：`Toolbox/UI/SettingsHost.lua` 的纯叶子页重构、Quest Inspector 设置承载迁移、默认打开规则统一，以及相关本地化/文档/静态校验更新
- 关联模块：`mover`、`tooltip_anchor`、`navigation`、`quest`、`encounter_journal`、`minimap_button`、`chat_notify`
- 关联文档：
  - `docs/specs/settings-host-redesign-spec.md`
  - `docs/designs/settings-host-redesign-design.md`
  - `docs/Toolbox-addon-design.md`
- 最后更新：2026-04-29

## 1. 目标

- 以测试先行的方式，把 `SettingsHost` 从“总览页 + 模块页”重构为“6 个纯叶子页 + 宿主组合内容块”的设置结构，并保持模块行为语义不变。

## 2. 输入文档

- 需求：
  - `docs/specs/settings-host-redesign-spec.md`
- 设计：
  - `docs/designs/settings-host-redesign-design.md`
- 其他约束：
  - 不新增模块、不新增玩家可见入口、不修改 `Toolbox/Toolbox.toc`。
- 仅在 `ToolboxDB.global` 增加宿主级状态；不得改动现有 `ToolboxDB.modules.*` 归属和语义。
- 先补失败校验，再重构宿主与页面承载。
- Quest Inspector 只改设置承载位置，不改查询能力与数据语义。
- 小地图按钮设置收口沿用现有 `minimap_button` 模块，不新增入口；需先写失败测试，再移除展开方式 / 款式 / 预览 / 拖放功能池。

## 3. 影响文件

- 新增：
  - `docs/specs/settings-host-redesign-spec.md`
  - `docs/plans/settings-host-redesign-plan.md`
- 修改：
  - `tests/validate_settings_subcategories.py`
  - `Toolbox/UI/SettingsHost.lua`
  - `Toolbox/Core/Foundation/Config.lua`
  - `Toolbox/Core/Foundation/Locales.lua`
  - `Toolbox/Modules/Quest.lua`
  - `docs/Toolbox-addon-design.md`
  - `docs/features/quest-features.md`
  - `docs/FEATURES.md`
- 视实现需要可能调整：
  - `Toolbox/Modules/MinimapButton.lua`
  - `Toolbox/Modules/ChatNotify.lua`
  - `docs/specs/settings-host-redesign-spec.md`
  - `docs/designs/settings-host-redesign-design.md`
- 验证：
  - `python tests/validate_settings_subcategories.py`
  - `python tests/run_all.py --ci`

## 4. 执行步骤

- [x] 步骤 1：收到用户明确“开动”后，将需求文档状态改为“可执行”，并把本计划状态改为“执行中”。
- [x] 步骤 2：先更新 `tests/validate_settings_subcategories.py`，锁定新的 6 叶子页结构、默认打开规则、Quest Inspector 不再作为独立设置子页，以及旧总览/模块平铺模型应被移除。
- [x] 步骤 3：运行 `python tests/validate_settings_subcategories.py`，确认旧实现按预期失败，失败点与本轮重构目标一致。
- [x] 步骤 4：更新 `Toolbox/Core/Foundation/Config.lua`，为宿主级“上次停留叶子页”状态补默认值与幂等迁移，并保持现有 `modules.*` 结构不变。
- [x] 步骤 5：重构 `Toolbox/UI/SettingsHost.lua` 的页面注册与构建模型：去掉总览页与模块平铺注册，改为宿主显式声明 `通用`、`界面`、`地图`、`任务`、`冒险手册`、`关于` 6 个叶子页，并保留战斗内独立宿主模式与三种入口统一打开逻辑。
- [x] 步骤 6：将语言设置、重载界面、`minimap_button` 和 `chat_notify` 组合进“通用”页；将 `mover`、`tooltip_anchor`、`navigation`、`encounter_journal` 分别迁入对应叶子页，并把 `debug` / `重置并重建` 统一压到各页低频区域。
- [x] 步骤 7：调整 `Toolbox/Modules/Quest.lua` 与 `SettingsHost` 的协作方式，使 Quest Inspector 改为“任务”页内部内容块，并删除旧的 `GetSettingsPages()` 左侧子页承载链路。
- [x] 步骤 8：更新 `Toolbox/Core/Foundation/Locales.lua` 与必要模块代码，补齐新的叶子页标题/说明文案，移除与旧总览/旧子页结构不再匹配的设置文案引用。
- [x] 步骤 9：运行 `python tests/validate_settings_subcategories.py` 与 `python tests/run_all.py --ci`，确认静态校验和全量自动化验证通过。
- [x] 步骤 10：回写 `docs/Toolbox-addon-design.md`、`docs/features/quest-features.md`、`docs/FEATURES.md`，同步新的设置结构、Quest Inspector 承载方式和入口口径，并记录可直接恢复的执行落点。
- [x] 步骤 11：把用户已确认的小地图按钮设置收口决策写回需求 / 计划 / 设计文档，满足“开动”后的文档先行门禁。
- [x] 步骤 12：先更新 `tests/validate_settings_subcategories.py`，锁定 `minimap_button` 不再保留展开方式、按钮款式、预览窗口、拖放功能池与相关残留键 / 文案。
- [x] 步骤 13：运行 `python tests/validate_settings_subcategories.py`，确认当前实现按预期失败，失败点与小地图按钮设置收口目标一致。
- [x] 步骤 14：更新 `Toolbox/Core/Foundation/Config.lua`、`Toolbox/Core/Foundation/Locales.lua` 与 `Toolbox/Modules/MinimapButton.lua`，固定圆形 + 横向悬停菜单，改为勾选式悬停菜单，并清理废弃存档键与预览专用逻辑。
- [x] 步骤 15：回写 `docs/Toolbox-addon-design.md` 等相关文档，改写小地图按钮设置口径后，再执行静态校验与全量测试收口。

## 5. 验证

- 命令 / 检查点 1：
  - `python tests/validate_settings_subcategories.py`
  - 预期：静态校验通过，新的叶子页结构与旧模型移除口径成立。
- 命令 / 检查点 2：
  - `python tests/run_all.py --ci`
  - 预期：现有自动化测试全量通过，无新增回归。
- 当前环境补充：
  - 若本机 `busted` 以 Lua 脚本形式安装在 `%APPDATA%\\luarocks\\bin\\busted`，需先执行 `luarocks path --lua-version 5.4` 注入 `LUA_PATH` / `LUA_CPATH` / `PATH`，再用 `lua %APPDATA%\\luarocks\\bin\\busted tests/logic/spec` 跑逻辑测试。
- 游戏内验证点：
  - `/toolbox`、ESC 菜单按钮和小地图按钮都会打开同一套叶子页结构。
  - 首次打开回退 `通用`，再次打开优先落到上次停留叶子页。
  - “任务”页内可直接使用 Quest Inspector，且左侧不再出现独立子页。
  - 战斗内独立宿主模式仍能直接打开指定叶子页，不报错、不退化。

## 6. 风险与回滚

- 风险：
  - `SettingsHost` 从“模块页宿主”改为“叶子页组合宿主”后，容易出现页面内容漏挂、顺序错乱或旧入口残留。
  - Quest Inspector 并回“任务”页后，如果布局或刷新顺序处理不当，可能造成页面过长或查询区重建异常。
  - 默认打开规则改为“上次停留页优先”后，若存档键或失效回退处理不严谨，可能出现打开空页或跳错页。
- 回滚方式：
  - 先以单次提交集中重构 `SettingsHost` 与相关设置承载；若验证失败，整体回退本次重构提交，恢复“总览页 + 模块页”旧模型。
  - 若问题只出现在 Quest Inspector 并回链路，可先保留新叶子页结构，局部回退 `quest` 的设置承载改动，再单独重做。

## 7. 执行记录

- 2026-04-29：已根据已确认设计补写需求与计划文档，当前等待用户明确“开动”后进入业务代码修改。
- 2026-04-29：用户已明确回复“开动”，计划状态转为执行中，可开始业务代码修改。
- 2026-04-29：`tests/validate_settings_subcategories.py` 已通过，`SettingsHost.lua` / `Config.lua` / `Locales.lua` / `Quest.lua` 当前实现已对齐“6 个叶子页 + Quest Inspector 并回任务页”的静态校验口径。
- 2026-04-29：`tests/logic/spec/quest_module_spec.lua` 已补齐新口径，明确 `quest` 模块保留 `RegisterSettings`、不再暴露 `GetSettingsPages()`；定向逻辑测试通过（`21 successes / 0 failures`）。
- 2026-04-29：按 `luarocks path --lua-version 5.4` 注入环境后，整套 Lua 逻辑测试当前为 `123 successes / 1 failure`；剩余失败位于 `tests/logic/spec/navigation_api_spec.lua:588`，期望导航 `transport` 段标签为“交通工具，目标”，而当前返回“乘坐交通工具前往目标”。该失败来自当前工作树中的导航主线改动，不属于本次 `settings-host-redesign` 引入的回归。
- 2026-04-29：已回写 `docs/Toolbox-addon-design.md`、`docs/FEATURES.md`、`docs/features/quest-features.md` 以及 quest 文档链中的 Quest Inspector 承载描述，后续恢复工作时可直接从“步骤 9：验证收口 / 分流导航失败”继续。
- 2026-04-29：用户确认小地图按钮设置收口采用方案 A：固定圆形、固定横向展开、移除预览与拖放功能池、悬停菜单改为逐项勾选加入；该确认结果已先写回需求 / 计划 / 设计文档，满足业务代码修改门禁。
- 2026-04-29：`python tests/validate_settings_subcategories.py` 先按预期失败，失败点为 `Config.lua` 仍保留 `buttonShape = "round"` 默认值。
- 2026-04-29：`busted tests/logic/spec/config_spec.lua` 先按预期失败，失败点为 `Toolbox.Config.Init()` 尚未清理 `minimap_button.buttonShape` 旧键。
- 2026-04-29：小地图按钮设置收口已完成：运行时固定为圆形主按钮 + 横向悬停菜单，设置页移除预览与拖放功能池，改为勾选加入悬停菜单。
- 2026-04-29：`python tests/run_all.py --ci` 最终通过，结果为 `129 successes / 0 failures / 0 errors / 0 pending`；游戏内手工验证尚未执行。

## 8. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-29 | 初稿：补写设置宿主重构计划，锁定执行顺序、影响文件与验证口径 |
| 2026-04-29 | 用户确认开动：计划状态改为执行中 |
| 2026-04-29 | 进度回写：静态校验通过、Quest 相关逻辑测试转绿；全量逻辑测试仅剩与导航主线相关的非本轮失败，恢复点记录在执行记录 |
| 2026-04-29 | 增补小地图按钮设置收口步骤：补记方案 A、失败测试与后续代码收口步骤 |
| 2026-04-29 | 执行完成：小地图按钮设置收口已落地并通过自动化验证，计划状态改为已完成 |
