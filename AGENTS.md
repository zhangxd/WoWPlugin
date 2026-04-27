# WoWPlugin — Agent / AI 协作说明

## AI 行为规则（强制，每次对话优先读此节）

收到需求后，**按顺序过以下三关，任一不通则停在该关**：

```
关 1 · 需求是否明确？
  └─ 否（无模块 id / 无验收 / 无边界）
     → 提 1～3 个封闭式问题，等用户回答；不得进入关 2

关 2 · 数据来源 / 主方案是否已选定？
  └─ 否（静态表由谁生成？未知键行为？主键以哪个 ID 为准？……仍多选一）
     → 列待决项清单，等用户选定；不得进入关 3

关 3 · 是否触发"新功能门禁"？
  触发条件（满足任一）：
    • 新 RegisterModule 模块（新 moduleId）
    • 新玩家可见入口（新菜单项、新按钮、新 slash 命令）
    • Toolbox.toc 新增行
  注：在已有模块的 ToolboxDB 键下新增字段，不触发关 3，但须在 Config.lua defaults 中声明并写迁移
  └─ 触发 → 先给方案评估（领域归属 / 数据落点 / 与现有 API 关系 / 验收要点 / 待确认项）
           → 明确输出「请确认是否开动」
           → 等用户明确「开动」
           → 用户回复「开动」后，若前文存在“待确认项/已确认决策”，必须先把确认结果写入对应需求文档/计划文档（状态改为可执行）并回报落点，再允许修改业务代码
           → 在完成上述文档落地前，不得用编辑工具修改业务代码

三关全部通过 → 按下方「先读文档再写代码」执行
```

**API 查证规则（强制）**：
- 遇到未实际使用过、或记忆不确定的魔兽世界插件 API（含 `C_*` API、Frame 方法、事件参数/返回值）时，必须先查权威资料并核对用法后再实现；禁止凭经验猜测后直接写代码。
- 权威资料优先级：暴雪官方文档 / BlizzardInterfaceCode（FrameXML）/ Warcraft Wiki（API 页面）。

**AI 禁止行为**（与关卡无关，始终强制）：
- 未调用工具前说"我马上开始改"之类承诺性语句；要么直接行动，要么说"我先规划"
- 未经关 1/2/3 直接修改 `Toolbox/Core/**`、`Toolbox/Modules/**`、`Toolbox/UI/**`、`Toolbox/Toolbox.toc`
- 用「技术上能直接做」替代澄清步骤
- 数据来源未选定时以「是否现在实现」收尾
- 关 3 触发后，在方案评估的同一回复中调用任何写入类修改工具（含文件编辑、补丁应用、写盘命令）
- 用户已回复「开动」但未先把“确认规则”落入需求/计划文档就直接改业务代码

**例外**（不经三关可直接执行）：纯错别字、与行为无关的注释修正、仅文档内链接修正。

---

## 先读文档再写代码

1. **[docs/Toolbox-addon-design.md](docs/Toolbox-addon-design.md)** — 总架构、模块契约、`ToolboxDB`、扩展点与能力边界；新功能必须能嵌进此文档中的模型。
2. **[docs/AI-ONBOARDING.md](docs/AI-ONBOARDING.md)** — 读档顺序、文档分层、最小需求信息包、§1.2 含糊需求执行路径。

实现或修改本仓库前，默认已阅读上述两份文档。

**模糊需求时的检查清单（速查）**：辨领域（游戏提示框 / 设置与 Locales / `Toolbox.Chat` / 暴雪 UI 挂接 / 具体模块）→ 必要时澄清 → 执行 AI-ONBOARDING §1 必读表 → 点名文件阅读（不通读整个 `Modules/`）→ 按 §1.1 开动后再改业务代码 → 收尾按 AI-ONBOARDING §4 更新总设计。完整步骤见 **§1.2**。

**改动节奏**：触及模块行为、存档键、TOC、设置 UI 的修改，**须**先对齐设计与文档，并由需求方明确**「开动」**后再改业务代码。仅错别字或与行为无关的注释，不要求开动。

---

## 项目约束

- **客户端**：魔兽世界 **正式服（Retail）**；以当前文档中的 `Settings` API 与 Interface 版本为准，不默认兼容怀旧服。
- **语言**：与用户沟通可用中文；代码与注释风格与现有文件一致。
- **本地环境隔离（强制）**：严禁在任何仓库文件中硬编码本地路径、盘符、用户名或机器特定配置；路径配置一律通过环境变量（如 `WOW_RETAIL_ADDONS`）、命令行参数或运行时自动探测实现。
- **文档语言**：仓库内文档默认简体中文；文件名、外部协议名、API 名等保留必要英文。
- **界面文案**：玩家可见字符串放在 **[Toolbox/Core/Locales.lua](Toolbox/Core/Locales.lua)**（`enUS` / `zhCN`，按 `GetLocale()` 选用）；代码中引用 `Toolbox.L.键名`，勿在业务逻辑里硬编码语言句子。
- **扩展方式**：新能力通过 **模块**（`RegisterModule`）接入；持久化在 **`ToolboxDB.modules.<moduleId>`**；避免在 `Core` 里堆业务逻辑。
- **Lua**：注释、对外接口文档、文件与 TOC、作用域、存档、`pcall` 与 `nil` 等规定见 **§ Lua 开发规范**。

---

## WoWDB 静态数据导出规则（强制）

适用范围：`Toolbox/Data/*.lua` 中由数据库生成的静态数据文件。

### Navigation 数据源约束（强制）

- **所有 `navigation` 路径规划数据必须走导出契约**：凡会被 `Toolbox.Navigation` 路径图、目标规则、入口落点、公共交通、地图父链、区域归属、职业 / 阵营 / 技能可用性规则或路线成本模型消费的数据，均必须定义 `DataContracts/<contract_id>.json` 并由 `scripts/export/` 从权威数据源正式导出。
- **所有运行时路线边必须统一导出**：`Toolbox.Navigation` 构图只能消费统一运行时路线边表（当前为 `Toolbox.Data.NavigationRouteEdges` / `navigation_route_edges`），不得直接读取来源侧边表或手工边表。`NavigationTaxiEdges` 这类文件只能作为来源侧导出与追溯数据，后续传送门、职业技能、特殊交通等边必须先进入统一路线边导出后才能被运行时消费。
- 禁止在手工维护 Lua 中写 navigation 数据，包括但不限于 `uiMapID`、`journalInstanceID`、`areaPoiID`、Taxi 节点 / 路径 ID、入口地图 ID、目标规则、路径边、节点、候选枢纽、落点坐标、职业技能边、阵营限制、成本与标签。
- `Toolbox/Data/NavigationManualEdges.lua` 不得作为运行时数据源；后续新增、修正或迁移 navigation 数据时，必须改为新增或更新对应 DataContracts 契约并实跑导出。若历史文件仍存在，必须从 TOC 与 `Toolbox.Navigation` 消费链路中移除，不得继续追加数据。
- 若当前缺少可导出的源表或表关系未确认，必须先停在方案评估 / 契约设计阶段，列出待确认的数据源与字段，不得用“先手写一个 ID 顶上”的方式绕过导出契约。

### 权威源与目录

- 生成型静态数据的唯一权威源位于：`DataContracts/<contract_id>.json`
- `contract_id` 必须使用小写字母、数字、下划线，并与 JSON 文件名同名。
- 每个数据库生成文件必须独立契约、独立 `contract_id`、独立 `schema_version`。
- `Toolbox/Data/*.lua` 的文件头只负责引用契约，不再负责定义契约。

### 脚本位置与入口

- 导出脚本位于本仓库：`scripts/export/`
- 一键导出：`export_toolbox_all.py`
- 单项导出：`export_toolbox_one.py`
- `one` 的主选择器是 `contract_id`（示例：`instance_map_ids`）；可兼容输出文件名选择器（示例：`InstanceMapIDs.lua`）。
- `instance_questlines` 的**正式导出入口**：`export_quest_achievement_merged_from_db.py`
- `export_instance_questlines_runtime.py` 仅作为 `export_quest_achievement_merged_from_db.py` 的内部聚合写盘 helper，不作为人工主入口。
- 当 `one/all` 命中 `instance_questlines` 时，必须自动或显式切换到 `export_quest_achievement_merged_from_db.py`，禁止再走契约直写覆盖。
- 导出时必须显式或隐式指向：
  - `--contract-dir DataContracts`
  - `--data-dir Toolbox/Data`

### 契约驱动约定

- 除 `instance_questlines` 外，`WoWPlugin/scripts/export` 必须先读取 `DataContracts/<contract_id>.json`，再执行查询与导出。
- `all` 脚本必须从契约目录加载全部 `active` 契约，不再扫描 `Toolbox/Data/*.lua` 文件头决定导出范围。
- 契约必须同时定义：
  - `contract`：身份、版本、状态
  - `output`：目标 Lua 文件与根表
  - `source`：`sql` 与结构化 `query`
  - `structure`：Lua 根结构
  - `validation`：最小校验规则
  - `versioning`：版本记录

### Lua 文件头约定

数据库生成文件必须带统一 tagged header，至少包含：

- `@contract_id`
- `@schema_version`
- `@contract_file`
- `@contract_snapshot`
- `@generated_at`
- `@generated_by`
- `@data_source`
- `@summary`
- `@overwrite_notice`

要求：

- `@contract_id` 必须与契约文件名一致。
- `@schema_version` 必须与 JSON 契约一致。
- `@contract_file` 必须指向 `WoWPlugin/DataContracts/<contract_id>.json`。
- 头注释不再承担“是否纳入导出”的判定职责。

### 快照与追溯

- 每次导出必须在 `../WoWTools/outputs/toolbox/contract_snapshots/<contract_id>/` 下保存一份契约快照。
- 快照只用于回溯，不得反向覆盖 `DataContracts/` 中的权威契约。
- `instance_questlines` 走正式脚本时允许使用 `@contract_snapshot runtime-only (...)` 头注释标记，不要求写入 `contract_snapshots/<contract_id>/`。

### AI 执行约束

- 用户要求“导出 Data”时，AI 必须优先调用正式导出脚本，而非手写覆盖数据库生成文件。
- 默认优先 `export_toolbox_one.py <contract_id>` / `export_toolbox_all.py`；**但 `instance_questlines` 必须改用 `export_quest_achievement_merged_from_db.py`**。
- 若新增数据库导出文件，AI 必须同时完成三件事：
  - 在 `DataContracts/<contract_id>.json` 定义契约
  - 通过 `export_toolbox_one.py <contract_id>` 或 `export_toolbox_all.py` 实跑生成 `Toolbox/Data/<file>.lua`
  - 增加或更新插件侧契约/文件头校验
- 若修改导出结构，必须提升同一 `contract_id` 下的 `schema_version`，不得新造临时标识规避版本治理。

---

## Lua 开发规范

### 注释与对外接口文档

- **注释**：新增与修改的 Lua 须带注释，使用**简体中文**（专有名词、API 名、Frame 名可保留英文）。每个文件须有**文件头**说明职责；非平凡逻辑、暴雪 API 坑、Frame 名与数据键含义须有简短说明。
- **接口注释（强制）**：所有**对外接口**（`Toolbox.*` 上的函数、领域对外 API、功能模块中供外部调用的入口）**必须**带注释，说明用途及各参数含义（含可选/默认值、`nil` 语义）；有返回值时说明含义与类型约定。风格与仓库内 `---`、`@param`、`@return` 等一致。仅文件内使用的 `local function` 至少一行说明用途与关键参数。
- **术语**：**对外接口**指单函数的文档约定；**领域对外 API** 指 `Toolbox.Chat` 等按领域划分的稳定调用面。

### 文件与加载

- **路径**：`Core/` 放命名空间、DB、领域对外 API、引导；`Modules/` 放功能模块；`UI/` 放设置壳等表现层；与 [Toolbox-addon-design.md](docs/Toolbox-addon-design.md) 分层一致。
- **TOC**：新增 `.lua` 须在 **[Toolbox/Toolbox.toc](Toolbox/Toolbox.toc)** 中声明；依赖顺序满足「被依赖者先加载」（领域对外 API 先于使用它的模块；`Bootstrap.lua` 通常在末尾）。
- **编码**：文件使用 **UTF-8**（无 BOM）；换行与仓库现有文件一致。

### 命名与作用域

- **优先 `local`**：模块内辅助函数、回调一律 `local function` 或 `local x`，避免向 `_G` 泄漏临时名。
- **`Toolbox` 表**：仅通过既有入口扩展（如 `Toolbox.Chat`、`RegisterModule`）；**禁止**在 `Modules/*.lua` 中随意 `Toolbox.Foo = {}` 造无文档的全局入口。
- **暴雪全局**：客户端提供的全局函数、Frame 从 `_G` 读取或保留全局名；勿假设未加载插件的子控件已存在。
- **缩写长度下限**：变量名、局部名、字段名中的缩写**不得少于 3 个字母**。禁止使用单字母（`L`、`i` 循环变量除外）或双字母缩写（`cb`、`dp`、`fs`、`ej`、`is`、`ok` 等）作为有语义的局部变量名；应写全称或至少 3 字母缩写（`loc`、`dataProv`、`fontStr`、`encJournal`、`instSel`、`success` 等）。循环计数器 `i`/`j`/`k` 不受此限。
- **变量定义须附中文注释**：每个有语义的局部变量定义行末须附中文行内注释，说明其含义或用途（`-- 本地化字符串表`、`-- 副本选择面板` 等）。循环计数器 `i`/`j`/`k` 及含义已由变量名完全自明的极简赋值（如 `local lines = {}`）可酌情省略。

### 数据与存档

- **模块数据**仅通过 **`ToolboxDB.modules.<moduleId>`** 访问，键名由该模块独占；**禁止**在模块内读写其他模块的 `modules.<其他 id>`，除非总设计明确约定。
- **全局杂项**（如 `ToolboxDB.global`）仅放与单模块无关的配置；新键须在 **DB 默认值**（`Core/Config.lua`）中声明并注释含义。
- **账号级 vs 角色级存档**：`ToolboxDB`（`SavedVariables`）为账号级，所有角色共享，适合窗口位置、UI 偏好、插件开关。如需角色级（`SavedVariablesPerCharacter`），须在 TOC 中声明独立变量名（如 `ToolboxDBChar`）并在 `Core/Config.lua` 中单独初始化。**当前版本不使用角色级存档**；若未来需要，须先更新总设计文档 §3 并经关 3 评审。

### 健壮性与客户端差异

- 对可能因版本或调用时机失败的暴雪 API，使用 **`pcall`**（或先判断 `C_Foo` / 全局是否存在），失败路径须有明确行为（静默、经 `Toolbox.Chat` 一行提示等），**禁止**裸调用导致整插件报错栈。
- **`nil` 与边界**：对索引、返回值做判断；若依赖多返回值顺序，须在注释中写明依据（官方文档或实机验证）。

### 安全与战斗

安全代码路径、taint、战斗中可执行的操作，遵守暴雪规则。**子控件创建与 hook 时机**见下文「暴雪 UI 挂接时机」。细则见下文「战斗锁定与 Taint」。

### pcall 使用边界

- **必须用 `pcall`**：① 存在版本差异的暴雪 API（如 `C_AddOns` vs 旧 `LoadAddOn`）；② 调用时机不确定的 API（Blizzard 子插件子控件尚未加载时）；③ `hooksecurefunc` 目标函数可能不存在时的挂接；④ 涉及玩家数据的请求（`RequestRaidInfo` 等）。
- **禁止用 `pcall`**：掩盖自己代码的逻辑错误；或为「以防万一」包裹一切调用——这会让真正的 bug 静默消失。
- **失败路径必须明确**：`pcall` 后若不看返回值，须在注释中说明为何可安全忽略；否则经 `Toolbox.Chat.PrintAddonMessage` 输出一行，或有其它明确处置。

### WoW 环境 Lua 陷阱

以下陷阱在 WoW Lua 环境中常见，新增或修改的 Lua 须主动规避：

- **`#` 操作符**：只对序列表（整数键 1..n 且无 nil 间隔）可靠。`frames`、`records` 等以字符串为键的稀疏表禁止用 `#`，一律用显式计数变量或 `pairs` 遍历。
- **`pairs` vs `ipairs`**：字符串键表用 `pairs`；严格 1..n 序列才用 `ipairs`。禁止对稀疏表使用 `ipairs`（会在第一个 nil 处截断，不报错）。
- **`table.concat` 与 nil**：含 nil 的位置会静默截断；拼接前先过滤空值，或改用手动循环。
- **`string.format` 与 nil**：`%s` 遇 nil 会 error；一律写 `tostring(val)` 或 `(val or "")`。
- **`for` 循环内的闭包捕获**：循环体内定义的函数若捕获循环变量，循环结束后所有函数都持有最终值；需要捕获当前值时用 `local captured = loopVar` 再闭包。
- **标准库缺失**：WoW 无 `io`、`os`（用 `time()` / `GetTime()` 替代 `os.time`，用 `date()` 替代 `os.date`）；无 `require`；不可用 `dofile`。
- **`math.random` 共享状态**：各插件共享同一个全局随机种子；若需要确定性序列，不依赖 `math.random`；若需要随机，可接受与其他插件竞争种子的现实。
- **`wipe()` 是暴雪全局函数**：清空表内容但保留表引用，适合热路径复用（`wipe(buf)` 后重填）。标准 Lua 无此函数，**不可写 `table.wipe()`**。**禁止**在热路径（OnUpdate、高频回调）中用 `buf = {}` 替代——每次赋值产生新表，增大 GC 压力；非热路径（一次性初始化）两者均可。

---

## 事件时机速查（强制）

选错事件是初始化 bug 的最常见来源，新增与修改的 Lua 须对照此表选择正确事件。

| 事件 | 触发时机 | 适合做什么 | 不适合做什么 |
|------|----------|-----------|-------------|
| `ADDON_LOADED` | 插件脚本执行完毕 | 初始化 DB、注册模块、注册设置 | 读角色数据、操作 UI 控件 |
| `PLAYER_LOGIN` | 角色数据就绪（每次登录触发一次） | 读角色信息、启用模块、挂接 UI | 需在传送后重复执行的逻辑 |
| `PLAYER_ENTERING_WORLD` | 每次进入世界（含副本传送） | 懒加载补挂（已存在则早退）、刷新位置 | 一次性初始化（会重复执行） |
| `PLAYER_REGEN_ENABLED` | 离开战斗 | 执行战斗中排队的保护操作 | — |

**规则**：一次性初始化用 `PLAYER_LOGIN`；需要在传送后重新执行的逻辑用 `PLAYER_ENTERING_WORLD`，但函数内**必须**有"已初始化则早退"的幂等保护，防止重复执行。

---

## 战斗锁定与 Taint（强制）

### 禁止在战斗中执行的操作

以下操作在 `InCombatLockdown()` 返回 `true` 时会触发 Lua 错误或产生 taint，**新增与修改的 Lua 中不得裸调用**：

- 对**受保护框体**（Protected Frame）调用 `SetPoint`、`ClearAllPoints`、`Show`、`Hide`、`SetAttribute`、`RegisterForDrag`、`SetScript`
- 调用 `RegisterStateDriver`、`UnregisterStateDriver`、`RegisterUnitWatch`

**处置方式**：在触发前检查 `InCombatLockdown()`；若用户在战斗中触发了需要保护操作的行为，应静默排队（注册 `PLAYER_REGEN_ENABLED` 事件，离开战斗后执行）或经 `Toolbox.Chat.PrintAddonMessage` 给一行提示，**禁止**裸调用导致 Lua 错误。

### Taint 传播规则

- `hooksecurefunc` 回调中若发生 Lua error，会向上传播 taint 并污染后续安全调用；回调内**必须**做 nil 检查或用 `pcall` 包裹可能 error 的逻辑。
- 在 `hooksecurefunc` 钩住的函数回调里，**不得**对保护框体做上述禁止操作；只允许读取状态或更新自己的非保护 Frame。
- **非保护 Frame 的 `OnUpdate`**：可在战斗中运行，但不得在其中操作保护框体。禁止对保护框体挂 `SetScript("OnUpdate", …)`，否则会产生 taint。
- 受 `UIPanelWindows` / `FramePositionManager` 管理的暴雪顶层窗体在战斗中会拒绝 `StartMoving`；Mover 模块已改用光标 delta + `SetPoint` 绕过，新增拖动逻辑须遵循同一方式，不得直接 `StartMoving`。

### `hooksecurefunc` vs `HookScript` 选择

| 场景 | 用哪个 |
|------|--------|
| 暴雪全局函数（`EncounterJournal_ListInstances`、`GameTooltip_SetDefaultAnchor` 等） | `hooksecurefunc("FuncName", cb)` |
| 已知 Frame 对象的脚本事件 | `frame:HookScript("OnShow", cb)`（优先；不污染全局） |

- **禁止对同一目标重复 hook**：用 `local hooked = false` 标记，已 hook 则跳过。
- `hooksecurefunc` 回调在原函数返回**后**执行，不可阻断调用，不可修改返回值；若需要拦截，走独立 Frame 事件或 `SetScript` 覆盖（仅限非保护框体）。

---

## 事件监听生命周期（强制）

创建 Frame 并 `RegisterEvent` 时，**必须**明确选择以下两种模式之一：

1. **一次性触发器**：触发后在回调内 `self:UnregisterEvent(event)` 自行注销。适合懒加载补挂（等待某插件的 `ADDON_LOADED`）。
2. **持久监听**：模块启用时 `RegisterEvent`，在 `OnEnabledSettingChanged(false)` 时 `UnregisterEvent`。适合需要随模块开关的业务逻辑。

**禁止**：注册事件后既不自行注销、也不在模块禁用时注销——模块禁用后回调仍会触发，是难以排查的逻辑泄漏。

---

## OnUpdate 使用规范

`OnUpdate` 每帧触发（约 60 次/秒），使用不当是帧率最常见的杀手。

### 必须节流

凡**非实时响应**（非鼠标拖动坐标跟随）的 `OnUpdate` 逻辑，必须用 `elapsed` 累计节流，典型周期 0.1～0.5 秒按场景定：

```lua
frame:SetScript("OnUpdate", function(self, elapsed)
  self._t = (self._t or 0) + elapsed
  if self._t < 0.25 then return end
  self._t = 0
  -- 实际逻辑
end)
```

### OnUpdate 内禁止的操作

- **创建新 table**：用模块级复用表（提前声明 `local buf = {}`，用前 `wipe(buf)`）。
- **字符串拼接**（`..` 操作）：热路径每帧产生大量短命字符串，增大 GC 压力；拼接结果若不变则缓存。
- **聊天 API**（`GetNumMessages`、`GetMessageInfo` 等）：不应在 OnUpdate 里轮询聊天内容。
- **`pcall` 包全部逻辑**：`pcall` 本身有开销，不得在每帧路径中无差别使用。

### 必须清理

- Frame 不再需要每帧更新时，**必须** `frame:SetScript("OnUpdate", nil)` 或 `frame:Hide()`（Hide 会停止 OnUpdate）；泄漏的 OnUpdate 在 `hide` 之后仍然运行，难以排查。
- 模块禁用时（`OnEnabledSettingChanged(false)`）须同步停止所有 OnUpdate；重启时重挂。

### 与 C_Timer 的分工

| 需求 | 用法 |
|------|------|
| 持续轮询 / 实时拖动跟随 | `OnUpdate` + 节流 |
| 单次下一帧延迟（合并同帧多次调用） | `C_Timer.After(0, cb)`，须注释说明目的 |
| 单次固定延迟（非「等布局」） | `C_Timer.After(秒, cb)`，须注释说明依据 |
| 重复定时任务 | `C_Timer.NewTicker(间隔, cb, 次数)` |

`C_Timer.After(0)` 不得作为「多等一帧布局就好了」的通用替代，见「暴雪 UI 挂接时机」。

**`C_Timer` 句柄生命周期管理（强制）**：
- `C_Timer.NewTicker(interval, cb, n)` 返回 ticker 对象；**必须**保存在模块级变量（如 `local scanTicker`）。模块禁用时（`OnEnabledSettingChanged(false)`）**必须**调用 `ticker:Cancel()`；重启时重建。
- `C_Timer.After(秒, cb)` 返回 timer 对象；若需要在禁用时取消，同样须保存句柄并调用 `:Cancel()`。
- **例外**：`C_Timer.After(0, cb)` 的下一帧合并用途，帧过即失效，无需保存句柄。

---

## Frame 全局命名规范

WoW 中所有带名字的 Frame 进入全局 `_G`，命名冲突会导致难以排查的 nil 覆盖或 UI 错误。

- **需要全局名的 Frame**（跨文件引用、暴雪 XML 模板等）统一格式：`Toolbox<模块驼峰><用途>`  
  例：`ToolboxMinimapBtn`、`ToolboxChatCopyFrame`、`ToolboxTooltipDriver`
- **不需要跨文件引用的 Frame 一律不给全局名**：`CreateFrame` 第二参传 `nil`。
- **禁止用 `_G["Toolbox" .. someVar]` 动态拼接全局名**：难以追踪、难以 grep。
- 已有全局名的 Frame 创建后同时写 `_G[name] = f`；后续引用用局部变量 `f`，不重复读 `_G`（见 `Core/Chat.lua openCopyTextFallbackWindow` 的缓存模式）。

---

## 暴雪 UI 挂接时机

**目的**：做 UI 相关功能时，**不得**依赖「延迟一段时间再操作」来让界面看起来时机正确；控件创建、重锚、刷新须走**暴雪可验证的 UI 注册与绑定路径**，而不是用定时器模拟「布局已就绪」。

向暴雪 Frame（冒险手册、设置面板等）**创建子控件、改锚点、替换 DataProvider** 时，**必须**绑定到以下生命周期。**严禁**以 **`C_Timer.After(正数秒, …)`**（或等价的固定时长延迟）作为等布局/等控件存在的**唯一或主路径**。

**允许的例外**：`C_Timer.After(0, …)` 仅用于**下一帧合并**（如避免连续 `ClearAllPoints` 闪烁），**须在代码注释中写明目的**。不得把 `After(0)` 当作「多等一帧布局就好了」的通用替代。

### 必须优先采用

1. **Frame 脚本**：在目标父级或祖先上使用 `HookScript("OnShow", …)`（及确有需要时的 `OnSizeChanged` 等），在界面真正显示或布局更新之后再创建或重锚。
2. **暴雪函数 post-hook**：使用 `hooksecurefunc` 挂到在该 UI 填充或刷新之后必然调用的全局函数（例如冒险手册实例列表刷新用 `EncounterJournal_ListInstances`），在回调内执行创建或刷新。
3. **`ADDON_LOADED` 的含义**：仅表示对应插件脚本已执行，**不等于** `EncounterJournal.instanceSelect` 等子控件已存在或已布局；不得单靠「手册已 ADDON_LOADED」立刻假定可安全 `CreateFrame` 子控件。

### 严禁

- **仅用** `C_Timer.After(正数秒, …)` 或固定时长延迟去「等布局 / 等控件」，且**没有** OnShow / hooksecurefunc 等正式绑定路径作为主路径。
- 以「行数少」「少挂 hook」为由跳过生命周期绑定，导致竞态、偶发不显示、或与暴雪后续 `ListInstances` 互相覆盖。

### 反面案例与正确做法（本仓库已发生，禁止复现）

- **错误**：在 `Blizzard_EncounterJournal` 的 `ADDON_LOADED` 之后只用 `C_Timer.After(0.1, …)` 创建「资料片」旁的控件；延迟长度无 API 依据，首帧失败则控件可能永久不出现。
- **正确**：对 `instanceSelect`（及 Landing 内嵌的同类面板）各挂一次 `HookScript("OnShow", …)`，并对 **`EncounterJournal_ListInstances`** 做 post-hook，在回调与 OnShow 中调用创建函数（内部仅创建一次，已存在则早退）。

实现或评审时若发现「用延迟凑 UI 时机」，**必须**改为 OnShow / hooksecurefunc / 事件等正式路径；新增与修改的 Lua 不得再引入以固定时长延迟为唯一手段的写法。

---

## 新功能规划：领域与模块（强制）

以下规则**必须**遵守；与 **[docs/Toolbox-addon-design.md](docs/Toolbox-addon-design.md)** 中的模块模型一致，冲突时以**更严格**者为准。

### 领域对外 API 与功能模块

- **领域对外 API**：按领域划分的、对暴雪客户端能力的稳定调用面（如 `Toolbox.Chat` 提供的聊天输出、统一前缀与颜色、版本差异分支）。实现放在 `Core/`，**不得**承载某一具体玩法的业务分支与专属存档逻辑。`Toolbox.MinimapButton`（`Modules/MinimapButton.lua`）是例外：它是表现层模块，但通过 `RegisterFlyoutEntry` 对外暴露稳定调用面，其他模块须经此 API 追加悬停菜单项，禁止直接操作内部注册表。
- **功能模块（Feature Module）**：通过 `RegisterModule` 注册，负责何时做、是否启用、文案键、`ToolboxDB.modules.<id>`；通过调用领域对外 API 完成「怎么做」。

### 强制规则

1. **先辨领域，再写功能**：实现前必须明确功能属于哪个领域。若该领域已有对外 API，**必须**经领域对外 API 调用；**禁止**在功能模块或 `Core` 中新增与该领域重复的底层 API 直调（例如多处直接 `DEFAULT_CHAT_FRAME:AddMessage`）。
2. **领域对外 API 优先**：若计划增加的能力属于某领域且会在多处复用，**必须先扩展或新增对应领域对外 API**，再在功能模块中使用；**禁止**为赶工在单个模块内复制一套同类客户端调用。
3. **聊天输出**：凡面向玩家的聊天框输出，**必须**通过 **`Toolbox.Chat`** 实现；**禁止**在 `Modules/*.lua` 中新增对 `DEFAULT_CHAT_FRAME` / `AddMessage` 等的直接调用。
4. **Core 保持薄**：`Core` **不得**堆叠仅某一功能才需要的业务逻辑；此类逻辑放在对应功能模块或领域对外 API 收敛后的实现中。
5. **模块边界**：需要独立开关、独立设置区或独立持久化键时，**必须**新建独立 `moduleId`；仅扩展某领域通用行为时，**只**扩展领域对外 API，**不**新建模块。

### 提需求时的自检（必做）

合并或评审前确认：数据是否落在合适的 `modules.*`？是否复用已有领域对外 API？是否仍有个别文件绕过领域对外 API？是否需要更新 **Toolbox-addon-design.md** §2.2？暴雪 UI 挂接是否采用 OnShow / hooksecurefunc 等正式路径，而非固定时长延迟？

---

## Git 提交规范（强制）

### 提交信息语言与结构

- **提交标题必须使用中文**，简明描述本次改动主目的。
- 提交信息应包含**说明体**（body），写清改动背景、主要变更与影响范围。
- 建议结构：
  - 标题：`<类型>: <中文摘要>`
  - 说明体：`为什么改`、`改了什么`、`影响哪里`

### 多功能点 / Bug 同次提交规则

- 若一次提交包含多个功能点或 bug 修复，说明体必须**逐项列出**，禁止只写笼统一句。
- 每项建议带前缀，便于检索与回溯：
  - `[功能] <模块或能力>: <改动说明>`
  - `[修复] <问题或模块>: <修复说明>`
  - `[文档] <文档名>: <更新说明>`
- 涉及行为变化时，需在说明体补一行“兼容性/迁移影响”。

### 示例

```text
文档: 补充 AGENTS 提交规范

- [文档] AGENTS: 新增 Git 提交规范，要求标题与说明体使用中文
- [文档] AGENTS: 增加多功能点/bug 同次提交的逐项记录格式
- 影响: 仅协作规范更新，不影响插件运行时行为
```

---

## 调试速查

| 需求 | 方法 |
|------|------|
| 查 Frame 全局名 | `/fstack` 悬停目标 Frame |
| 执行 Lua 片段 | `/run Toolbox.Chat.PrintAddonMessage("test")` |
| 查看当前存档值 | `/run DevTools_Dump(ToolboxDB)` |
| 查看 Lua 错误 | 默认错误弹窗，或安装 BugSack + BugGrabber |
| 重载 UI | `/reload` 或设置页「重载」按钮 |
| 查看模块注册状态 | `/run DevTools_Dump(Toolbox.Registry)` |

---

## 收尾

合并新模块或改架构后，更新 **Toolbox-addon-design.md** 中的鸟瞰图、§2.2 映射表、数据示例、TOC 与里程碑；不必重复粘贴整段架构到别处。
