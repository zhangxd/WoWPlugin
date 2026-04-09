# 已落地：Logic Test Harness（离线逻辑测试）

- 日期：2026-04-09
- 状态：Phase 1 已落地（2026-04-10）

## 落地结果（2026-04-10）

1. 已提供统一入口：`python tests/run_all.py`（静态校验 + logic 测试）。
2. 已落地 `tests/logic/harness/**` fake runtime 能力（frame/timer/tooltip）。
3. 已落地 EncounterJournal 逻辑测试与 golden 对比。
4. 已新增 QuestlineProgress 逻辑测试：
   - `tests/logic/spec/questline_progress_spec.lua`（mock 注入链路）
   - `tests/logic/spec/questline_progress_live_data_spec.lua`（live 数据容错链路）
5. 当前基线：`python tests/run_all.py` 通过（12 successes）。

## 背景

当前仓库已有 `tests/validate_settings_subcategories.py`，主要做静态结构校验（字符串存在/不存在）。  
该方式无法验证插件在运行时的真实逻辑行为（事件驱动、状态变化、副作用调用）。

## 目标

建立可在离线环境运行的逻辑测试机制：通过模拟 WoW 运行时来驱动模块逻辑，并对输出与副作用进行断言，作为后续重构与功能迭代的回归保障。

## 第一阶段范围（Phase 1）

1. 聚焦 Encounter Journal 相关逻辑，不做全模块铺开。
2. 覆盖三类行为：
   - 事件驱动行为（注册/反注册、触发处理）
   - 业务结果行为（筛选、映射、返回值）
   - 展示文本行为（tooltip 行构建）
3. 保留现有静态校验脚本，不替换，只新增逻辑测试链路。

## 非目标（Phase 1 不做）

1. 游戏内全自动 UI 集成测试。
2. 一次性改造全部模块为可注入结构。
3. 大规模目录重构。

## 技术决策（Phase 1，开工基线）

### 1) 测试运行器与统一入口

1. 逻辑测试运行器选型：`Lua 5.1 + busted`（仅用于 `tests/logic/**`）。
2. 现有静态校验保留：`python tests/validate_settings_subcategories.py`。
3. 统一一键入口：新增 `python tests/run_all.py`，顺序执行：
   - 静态校验：`python tests/validate_settings_subcategories.py`
   - 逻辑测试：`busted tests/logic`
4. CI 与本地使用同一命令：`python tests/run_all.py --ci`。

### 2) 目录与文件约定

```text
tests/
  validate_settings_subcategories.py
  run_all.py
  logic/
    harness/
      fake_runtime.lua
      fake_frame.lua
      fake_timer.lua
      fake_tooltip.lua
    spec/
      encounter_journal_event_lifecycle_spec.lua
      encounter_journal_scheduler_spec.lua
      encounter_journal_tooltip_spec.lua
    golden/
      zhCN/
        encounter_journal_tooltip_lockout_lines.golden.txt
      enUS/
        encounter_journal_tooltip_lockout_lines.golden.txt
```

### 3) Runtime Adapter 落点与范围

1. 适配层落点：`Toolbox/Core/Foundation/Runtime.lua`，对外挂载 `Toolbox.Runtime`。
2. Phase 1 仅改造 Encounter Journal 直接依赖点，不做全仓库迁移。
3. Phase 1 最小接口（必须）：
   - `Runtime.CreateFrame(frameType, frameName, parentFrame, templateName)`
   - `Runtime.NewTimer(delaySeconds, callback)`（返回含 `Cancel()` 的句柄）
   - `Runtime.After(delaySeconds, callback)`（用于下一帧/延迟调度路径）
   - `Runtime.IsAddOnLoaded(addonName)`
   - `Runtime.LoadAddOn(addonName)`（与现有加载分支保持一致）
   - `Runtime.TooltipSetOwner(tooltipObject, ownerFrame, anchorType)`
   - `Runtime.TooltipClear(tooltipObject)`
   - `Runtime.TooltipSetText(tooltipObject, text)`
   - `Runtime.TooltipAddLine(tooltipObject, text, red, green, blue, wrapText)`
   - `Runtime.TooltipShow(tooltipObject)`
   - `Runtime.TooltipHide(tooltipObject)`

### 4) Golden 快照与稳定性策略

1. 快照文件按 locale 分目录（`zhCN` / `enUS`），防止语言切换导致误报。
2. 逻辑测试默认“只读比对”；更新快照需显式开启：
   - `UPDATE_GOLDEN=1 busted tests/logic`（Windows 可由 `run_all.py` 负责兼容环境变量写法）。
3. Golden 用例输入必须固定：
   - 固定锁定数据顺序
   - 固定 `GetLocale()` 返回
   - 固定时间相关文本源（若涉及）

### 5) 缺陷注入验收机制（可重复）

1. 新增一条“验收演示”脚本（仅测试阶段使用，不进入生产 TOC）：
   - 对 `appendAdventureGuideMicroButtonLockoutLines` 的“overflow 行”分支做临时破坏（例如注释掉 `moreFormat` 行追加）。
2. 预期：`encounter_journal_tooltip_spec.lua` 至少 1 条用例稳定失败并给出行级差异。
3. 回滚后再次运行，测试恢复通过。

## 需求明细

### 1) 运行时接口抽象（Runtime Adapter）

1. 业务层不再散落直调 `_G` / `C_*`，统一经运行时适配层调用。
2. 生产环境绑定真实 WoW API；测试环境允许注入 fake 实现。
3. Phase 1 至少抽象以下能力（按最小可测接口实现）：
   - `CreateFrame`
   - `C_Timer.NewTimer`（及取消句柄）
   - `C_Timer.After`
   - `C_AddOns.IsAddOnLoaded` / `LoadAddOn`
   - tooltip 追加/刷新所需调用点

### 2) 离线测试 Harness

1. 提供可复用 fake 环境：
   - fake frame（含 `RegisterEvent` / `UnregisterEvent` / `HookScript` 等）
   - fake timer（可记录创建、取消、触发）
   - fake tooltip（可记录行内容）
2. 支持“驱动-断言”模式：
   - 输入：事件序列、配置状态、模拟 API 返回
   - 执行：模块逻辑调用
   - 断言：状态、输出、副作用调用序列

### 2.1) Harness API 契约（Phase 1 最小集）

1. `Harness.new(options)`：
   - 输入：`locale`、`moduleDbSeed`、`addonLoadedSeed`、`lockoutRowsSeed`。
   - 输出：`harness` 对象（包含 fake runtime、trace 与断言辅助）。
2. `harness:loadEncounterJournalModule()`：
   - 加载目标模块并触发 `OnModuleLoad` 初始化路径。
3. `harness:emit(eventName, ...)`：
   - 向 fake event frame 投递事件（如 `ADDON_LOADED`、`UPDATE_INSTANCE_INFO`）。
4. `harness:advance(seconds)`：
   - 推进 fake timer 时钟，触发到期回调。
5. `harness:runAllTimers()`：
   - 直接冲刷所有已创建且未取消 timer。
6. `harness:getTrace()`：
   - 返回副作用调用序列（事件注册/反注册、RequestRaidInfo、tooltip 行追加、timer 创建/取消）。
7. `harness:getTooltipLines()`：
   - 返回当前 tooltip 文本行数组（供 golden 比对）。
8. `harness:resetState()`：
   - 清空 trace、tooltip、timer 队列，便于同文件多用例隔离。

### 2.2) Fake 对象行为约定（用于稳定断言）

1. fake frame：
   - 必须记录 `RegisterEvent` / `UnregisterEvent` 调用历史。
   - `SetScript("OnEvent", cb)` 后支持 `emit` 触发。
   - `HookScript(scriptName, cb)` 需支持同脚本多回调链式执行。
2. fake timer：
   - `NewTimer` 返回句柄带 `Cancel()`。
   - 被取消 timer 不得执行回调，且 trace 可见 `cancel` 行为。
   - 支持同一时间戳多个 timer 的稳定执行顺序（按创建顺序）。
3. fake tooltip：
   - 记录 `SetText` 与每次 `AddLine` 的文本内容。
   - `Show()` 不改变内容，仅记录展示调用次数。
   - 支持 `_toolboxEJMicroLockoutsAdded` 这类状态位读写。

### 3) 用例建设

1. 为 Encounter Journal 增加不少于 8 条逻辑测试。
2. 至少覆盖：
   - 模块启停时事件注册生命周期
   - 锁定信息摘要构建与过滤逻辑
   - tooltip 文本行增补逻辑
3. 引入快照断言（golden）用于文本结果回归。

### 3.1) 首批 8 条用例清单（输入 / 触发 / 断言）

1. `load_registers_expected_events`
   - 输入：模块启用，`Blizzard_EncounterJournal` 未加载。
   - 触发：`OnModuleLoad`。
   - 断言：注册 `ADDON_LOADED`、`PLAYER_ENTERING_WORLD`，并按启用态决定 `UPDATE_INSTANCE_INFO`。
2. `disable_unregisters_lockout_event_and_cancels_scheduler`
   - 输入：模块先启用并已有待执行刷新 timer。
   - 触发：`OnEnabledSettingChanged(false)`。
   - 断言：`UnregisterEvent("UPDATE_INSTANCE_INFO")`、timer 被取消、清理选择态与 overlay。
3. `addon_loaded_blizzard_encounterjournal_init_once`
   - 输入：已注册事件，`name = "Blizzard_EncounterJournal"`。
   - 触发：`emit("ADDON_LOADED", "Blizzard_EncounterJournal")` 两次。
   - 断言：初始化 hook 仅执行一次，且 `ADDON_LOADED` 在首次后被反注册。
4. `player_entering_world_requests_raidinfo_once`
   - 输入：模块已加载，世界进入事件可触发。
   - 触发：`emit("PLAYER_ENTERING_WORLD")` 两次。
   - 断言：首次调用 `RequestRaidInfo` 且随后反注册该事件，第二次不重复执行。
5. `refresh_scheduler_debounce_keeps_latest_token`
   - 输入：连续两次 `schedule`（不同 reason，第二次更晚触发）。
   - 触发：`advance()` 到两个 timer 都到期。
   - 断言：仅最新 token 对应刷新真正执行一次，旧 token 回调被丢弃。
6. `micro_button_tooltip_empty_state_lines`
   - 输入：锁定摘要为空，tooltip 已 owned。
   - 触发：调用微型菜单 tooltip 增补路径。
   - 断言：出现“标题 + 空状态文案”，且不出现具体副本行。
7. `micro_button_tooltip_overflow_appends_more_line`
   - 输入：锁定摘要数量超上限，`moreFormat` 可用。
   - 触发：调用 tooltip 增补路径。
   - 断言：除可见行外，末尾追加“还有 N 条未显示”提示。
8. `tooltip_lines_match_golden_for_known_dataset`
   - 输入：固定锁定数据样本（含普通本/团队本/首领进度）。
   - 触发：执行一次完整 tooltip 构建。
   - 断言：输出行与 `golden/<locale>/encounter_journal_tooltip_lockout_lines.golden.txt` 完全一致。

### 4) 执行与集成

1. 本地可一键运行逻辑测试。
2. CI 可执行同一命令并产出失败信息。
3. 与现有 `validate_settings_subcategories.py` 并行保留。

### 4.1) 命令与失败输出约定

1. 本地：
   - `python tests/run_all.py`
2. CI：
   - `python tests/run_all.py --ci`
3. 失败输出必须包含：
   - 用例名（spec + case）
   - 断言类型（事件生命周期 / 副作用序列 / golden diff）
   - 关键信息（期望值 vs 实际值）

## 验收标准

1. 无游戏客户端环境下可运行并稳定通过。
2. 人为注入一个已知逻辑缺陷时，至少 1 条逻辑测试可稳定失败。
3. 测试失败信息可定位到具体行为（不是“字符串缺失”）。
4. 不改变线上功能表现（仅可测试性改造 + 测试补齐）。

## 后续扩展（Phase 2+）

1. 逐模块推广 Runtime Adapter。
2. 增加差分测试（旧实现 vs 新实现）与性质测试（property-based）。
3. 视收益评估是否补充游戏内回放验证。
