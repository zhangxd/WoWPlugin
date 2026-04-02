# WoWPlugin — Agent / AI 协作说明

## 先读文档再写代码

1. **[docs/Toolbox-addon-design.md](docs/Toolbox-addon-design.md)** — 总架构、模块契约、`ToolboxDB`、扩展点与能力边界；新功能必须能嵌进此文档中的模型。
2. **[docs/AI-ONBOARDING.md](docs/AI-ONBOARDING.md)** — 读档顺序、文档分层、给 AI 的最小需求信息包、**模糊需求时的 AI 建议执行路径（§1.2）**、功能合并后应更新哪些章节。

实现或修改本仓库前，默认已阅读上述两份文档。

**模糊需求时的检查清单（摘要）**：需求未点名文件、未写验收时，建议按顺序：**辨领域**（游戏提示框 / 设置与 Locales / `Toolbox.Chat` / 暴雪 UI 挂接 / 具体模块）→ **必要时先澄清** 1～3 个问题 → **执行 [AI-ONBOARDING.md](docs/AI-ONBOARDING.md) §1 必读表** → **搜索并点名文件阅读**（不通读整个 `Modules/`）→ **按 §1.1 开动** 后再改业务代码 → **收尾按 [AI-ONBOARDING.md](docs/AI-ONBOARDING.md) §4** 更新总设计等处。完整步骤、示例与边界说明见 **§1.2**。

**改动节奏**：触及模块行为、存档键、TOC、设置 UI 的修改，**须**先对齐设计与文档，并由需求方明确 **「开动」** 后再改业务代码。细则见 [docs/AI-ONBOARDING.md](docs/AI-ONBOARDING.md) §1.1 与 [docs/specs/2026-04-02-design-workflow-and-settings-groups.md](docs/specs/2026-04-02-design-workflow-and-settings-groups.md)（其中 **§B** 为设置页分组需求，**未编码**）。仅错别字或与行为无关的注释，不要求开动。

## 项目约束

- **客户端**：魔兽世界 **正式服（Retail）**；以当前文档中的 `Settings` API 与 Interface 版本为准，不默认兼容怀旧服。
- **语言**：与用户沟通可用中文；代码与注释风格与现有文件一致。
- **界面文案**：玩家可见字符串放在 **[Toolbox/Core/Locales.lua](Toolbox/Core/Locales.lua)**（`enUS` / `zhCN`，按 `GetLocale()` 选用）；代码中引用 `Toolbox.L.键名`，勿在业务逻辑里硬编码某一语言句子。
- **扩展方式**：新能力通过 **模块**（`RegisterModule`）接入；持久化在 **`ToolboxDB.modules.<moduleId>`**；避免在 `Core` 里堆业务逻辑。
- **Lua**：注释、对外接口文档、文件与 TOC、作用域、存档、`pcall` 与 `nil` 等规定见 **§ Lua 开发规范**（本节不重复）。

## Lua 开发规范

### 注释与对外接口文档

- **注释**：新增与修改的 Lua 须带注释，使用**简体中文**（专有名词、API 名、Frame 名可保留英文）。每个文件须有**文件头**说明职责；非平凡逻辑、暴雪 API 坑、Frame 名与数据键含义须有简短说明。PowerShell 等脚本注释同样优先使用中文。
- **接口注释（强制）**：所有**对外接口**（`Toolbox.*` 上的函数、**领域对外 API**、功能模块中供外部调用的入口）**必须**带注释，说明用途及**各参数**含义（含可选/默认值、`nil` 语义）；有返回值时说明含义与类型约定。风格与仓库内 `---`、`@param`、`@return` 等一致。仅文件内使用的 `local function` 至少一行说明用途与关键参数。
- **术语**：**对外接口**指单函数的文档约定；**领域对外 API** 指 `Toolbox.Chat` 等按领域划分的稳定调用面（见下「新功能规划」）。

### 文件与加载

- **路径**：`Core/` 放命名空间、DB、领域对外 API、引导；`Modules/` 放功能模块；`UI/` 放设置壳等表现层；与 [Toolbox-addon-design.md](docs/Toolbox-addon-design.md) 分层一致。
- **TOC**：新增 `.lua` 须在 **[Toolbox/Toolbox.toc](Toolbox/Toolbox.toc)** 中声明；依赖顺序满足「被依赖者先加载」（领域对外 API 先于使用它的模块；`Bootstrap.lua` 通常在末尾）。
- **编码**：文件使用 **UTF-8**（无 BOM）；换行与仓库现有文件一致。

### 命名与作用域

- **优先 `local`**：模块内辅助函数、回调一律 `local function` 或 `local x`，避免向 `_G` 泄漏临时名。
- **`Toolbox` 表**：仅通过既有入口扩展（如 `Toolbox.Chat`、`RegisterModule`）；**禁止**在 `Modules/*.lua` 中随意 `Toolbox.Foo = {}` 造无文档的全局入口。
- **暴雪全局**：客户端提供的全局函数、Frame（如 `EncounterJournal`）从 **`_G`** 读取或保留全局名；勿假设未加载插件的子控件已存在。

### 数据与存档

- **模块数据**仅通过 **`ToolboxDB.modules.<moduleId>`** 访问，键名由该模块独占；**禁止**在模块内读写其他模块的 `modules.<其他 id>`，除非总设计明确约定。
- **全局杂项**（如 `ToolboxDB.global`）仅放与单模块无关的配置；新键须在 **DB 默认值**（`Core/DB.lua`）中声明并注释含义。

### 健壮性与客户端差异

- 对可能因版本或调用时机失败的暴雪 API，使用 **`pcall`**（或先判断 `C_Foo` / 全局是否存在），失败路径须有明确行为（静默、经 `Toolbox.Chat` 一行提示等），**禁止**裸调用导致整插件报错栈。
- **`nil` 与边界**：对索引、返回值做判断；若依赖多返回值顺序，须在注释中写明依据（官方文档或实机验证）。

### 安全与战斗

- 安全代码路径、taint、战斗中可执行的操作，遵守暴雪规则。**子控件创建与 hook 时机**见下文「暴雪 UI 挂接时机」。

## 暴雪 UI 挂接时机（强制）

**目的**：做 **UI 相关功能**时，**不得**依赖「延迟一段时间再操作」来让界面**看起来**时机正确；控件创建、重锚、刷新须走 **暴雪可验证的 UI 注册与绑定路径**（见下「必须优先采用」），而不是用定时器**模拟**「布局已就绪」。

向暴雪 Frame（冒险手册、设置面板等）**创建子控件、改锚点、替换 DataProvider** 时，**必须**绑定到上述生命周期。**严禁**以 **`C_Timer.After(正数秒, …)`**（或等价的固定时长延迟）作为**等待布局 / 等控件存在**的**唯一或主路径**。

**允许的例外（非「等布局」）**：`C_Timer.After(0, …)` 仅用于**下一帧合并**同一帧内多次调用等**与「等界面就绪」无关**的用途（如避免连续 `ClearAllPoints` 闪烁），**须在代码注释中写明目的**。不得把 `After(0)` 当作「多等一帧布局就好了」的通用替代方案。

### 必须优先采用

1. **Frame 脚本**：在**目标父级或祖先**上使用 `HookScript("OnShow", …)`（以及确有需要时的 `OnSizeChanged` 等），在**界面真正显示或布局更新之后**再创建或重锚。
2. **暴雪函数 post-hook**：使用 `hooksecurefunc` 挂到**在该 UI 填充或刷新之后**必然会调用的全局函数（例如冒险手册实例列表刷新用 `EncounterJournal_ListInstances`），在回调内执行创建或刷新。
3. **`ADDON_LOADED` 的含义**：仅表示对应插件**脚本已执行**，**不等于** `EncounterJournal.instanceSelect` 等子控件已存在或已布局；不得单靠「手册已 ADDON_LOADED」立刻假定可安全 `CreateFrame` 子控件。

### 严禁（除非文档写明例外与理由）

- **仅用** `C_Timer.After(正数秒, …)` 或固定时长延迟去「等布局 / 等控件」，且**没有**上述 OnShow / hooksecurefunc 等**正式绑定路径**作为**主路径**。
- 以「行数少」「少挂 hook」为由跳过生命周期绑定，导致竞态、偶发不显示、或与暴雪后续 `ListInstances` 互相覆盖。

### 反面案例与正确做法（本仓库已发生，禁止复现）

- **错误**：在 `Blizzard_EncounterJournal` 的 `ADDON_LOADED` 之后**只**用 `C_Timer.After(0.1, …)` 创建「资料片」旁的控件；延迟长度无 API 依据，首帧失败则控件可能永久不出现。
- **正确**：对 `instanceSelect`（及 Landing 内嵌的同类面板）**各挂一次** `HookScript("OnShow", …)`，并对 **`EncounterJournal_ListInstances`** 做 **post-hook**，在回调与 OnShow 中调用创建函数（内部**仅创建一次**，已存在则早退）。

实现或评审时若发现「用延迟凑 UI 时机」，**必须**改为 **OnShow / hooksecurefunc / 事件** 等正式路径；存量代码迁移可分步，**新增与修改的 Lua 不得再引入以固定时长延迟为唯一手段的写法**。

## 新功能规划：领域与模块（强制）

以下规则**必须**遵守；与 **[docs/Toolbox-addon-design.md](docs/Toolbox-addon-design.md)** 中的模块模型一致，冲突时以**更严格**者为准。

### 领域对外 API 与功能模块

- **领域对外 API**：按领域划分的、对暴雪客户端能力的**稳定调用面**（如 `Toolbox.Chat` 提供的聊天输出、统一前缀与颜色、版本差异分支）。实现放在 **`Core/`**（如 `Chat.lua`、`EncounterJournal.lua` 等），**不得**承载某一具体玩法的业务分支与专属存档逻辑。
- **功能模块（Feature Module）**：通过 **`RegisterModule`** 注册，负责**何时做、是否启用、文案键、`ToolboxDB.modules.<id>`**；通过调用**领域对外 API**完成「怎么做」。

### 强制规则

1. **先辨领域，再写功能**：实现前必须明确功能属于哪个领域（聊天、提示框、窗口布局等）。若该领域已有对外 API，**必须**经领域对外 API 调用；**禁止**在功能模块或 `Core` 中**新增**与该领域重复的底层 API 直调（例如多处直接 `DEFAULT_CHAT_FRAME:AddMessage`）。
2. **领域对外 API 优先**：若计划增加的能力属于某领域、且会在多处复用或已有同类调用，**必须先扩展或新增对应领域对外 API**，再在功能模块中使用；**禁止**为赶工在单个模块内复制一套同类客户端调用。
3. **聊天输出**：凡面向玩家的聊天框输出，**必须**通过 **`Toolbox.Chat`**（或当前仓库内等价的聊天领域对外 API）实现；**禁止**在 `Modules/*.lua` 中新增对 `DEFAULT_CHAT_FRAME` / `AddMessage` 等的直接调用（`Toolbox.Chat` 自身实现除外）。若尚不存在对应领域对外 API，**必须先**实现该 API，再实现依赖它的功能模块。
4. **Core 保持薄**：`Core` **不得**堆叠仅某一功能才需要的业务逻辑；此类逻辑放在对应 **功能模块** 或领域对外 API 收敛后的实现中。
5. **模块边界**：需要独立开关、独立设置区或独立持久化键时，**必须**新建独立 `moduleId`；仅扩展某领域通用行为时，**只**扩展领域对外 API，**不**新建模块。

### 提需求时的自检（必做）

合并或评审前，确认已回答：数据是否落在合适的 `modules.*`？是否复用已有领域对外 API？是否仍有个别文件绕过领域对外 API？是否需要更新 **Toolbox-addon-design.md** §2.2 与能力说明？**暴雪 UI 挂接**是否采用 **OnShow / hooksecurefunc** 等正式路径，而非以 **`C_Timer.After(正数秒, …)`** 等固定时长延迟作为等布局的主路径（见上文 **暴雪 UI 挂接时机**）？

**存量代码**允许分步迁移；**凡本仓库内新增或修改的 Lua**，均须符合本节，不得新增违反上述约定的实现。

## 收尾

合并新模块或改架构后，更新 **Toolbox-addon-design.md** 中的鸟瞰图、§2.2 映射表、数据示例、TOC 与里程碑；不必重复粘贴整段架构到别处。
