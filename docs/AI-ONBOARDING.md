# AI 协作开发：读档顺序与文档整理约定

面向「以后主要用 AI 加功能」时，减少重复说明、避免设计与实现漂移。

---

## 1. 每次加功能时，让 AI 必读（按顺序）

| 顺序 | 文件 | 作用 |
|------|------|------|
| ① | [Toolbox-addon-design.md](./Toolbox-addon-design.md) | **唯一总体方案**：架构、模块契约、数据约定、各能力边界；新功能必须能嵌进这套模型。 |
| ①′ | [AGENTS.md](../AGENTS.md) | **与 ① 同级必读**：AI 行为规则（三关判断树）、领域对外 API、模块边界、Lua 开发规范、暴雪 UI 挂接时机；全文以该文件为准。 |
| ①″ | [DOCS-STANDARD.md](./DOCS-STANDARD.md) | **触及 `docs/**` 时必读**：规定功能、需求、设计、计划、测试文档的目录、命名、模板、状态与迁移规则。 |
| ② | 仓库根 `README.md` | 安装方式、TOC 名、支持的客户端；避免 AI 假设错游戏版本。 |
| ③ | **本次任务** | 用户消息里写清：模块名 / 行为 / 验收标准；若复杂，附 `docs/specs/` 下当期规格。 |

**可选、按需打开**

| 情况 | 再读 |
|------|------|
| 改核心加载 / DB / 注册表 | `Core/` 下实际文件 + 设计文档「2.1 通用架构」 |
| 只加一个模块 | `Modules/` 里**一个**现有模块当模板 + 设计文档「2.2 映射表」 |
| 导出 `Toolbox/Data` 静态数据 | [AGENTS.md](../AGENTS.md) **「WoWDB 静态数据导出规则（强制）」** + 对应 Data 文件头注释 |
| 与暴雪 Frame 名相关 | `docs/specs/` 或模块内注释里的白名单、版本备注 |
| 向暴雪 UI 挂子控件、改锚点、换 DataProvider | [AGENTS.md](../AGENTS.md) **「暴雪 UI 挂接时机」** |
| 编写或修改 Lua | [AGENTS.md](../AGENTS.md) **「Lua 开发规范」** |

**不要**让 AI 先通读整个 `Modules/` 所有文件，除非在做重构；**点名文件**更高效。

**文档语言**：仓库内新增或修改的设计文档、规格、计划与协作文档默认简体中文；文件名、外部协议名、API 名等保留必要英文。与 [AGENTS.md](../AGENTS.md)「项目约束」一致。

**本地环境隔离**与**言行一致**原则：见 [AGENTS.md](../AGENTS.md)「AI 行为规则」与「项目约束」，本文不重复。

### 1.1 改动节奏（设计先行、审核、再编码）

触及模块行为、存档键、TOC、设置 UI 的修改，按三步：**对齐设计** → **审核文档**（总设计 + AGENTS）→ **需求方明确「开动」**后改业务 Lua / TOC。规格可写在 `docs/specs/<topic>-spec.md`。

新增或修改 `docs/**` 中的功能、需求、设计、计划、测试文档时，按三步：**先选文档类型** → **按 [DOCS-STANDARD.md](./DOCS-STANDARD.md) 选择目录与模板** → **再写内容**。禁止先写零散文档，再事后决定放到哪个目录。

同一功能若已有对应类型文档，后续重构、补充说明、状态推进与验证记录应直接更新原文档，不另起平行文件；只有主题边界发生实质变化时，才新建新 `topic` 文档。

若是同一功能下的子专题，例如导航重构、名称来源调整、额外测试补充，也应并回该功能现有主文档；不要继续新增 `encounter-journal-xxx-spec/design/plan/test` 这类平行文档。

未开动前不改业务代码；仅改文档与 `docs/**` 允许。

**例外**：错别字与**与行为无关**的注释；**hotfix**（提交说明注明原因）。与 [AGENTS.md](../AGENTS.md)「改动节奏」一致。

### 1.2 AI 收到含糊需求时的执行路径

> **判断树强制规则见 [AGENTS.md](../AGENTS.md)「AI 行为规则」**（三关），本节仅提供背景理解与辨领域速查；两处有出入时以 AGENTS.md 为准。

**为什么需要三关**

| 关 | 防止的问题 |
|----|-----------|
| 关 1（需求明确？） | AI 凭猜测实现，结果不符合用户预期 |
| 关 2（主方案选定？） | 数据来源 / 未知键策略悬空，实现后需大改 |
| 关 3（新功能门禁？） | 未经评估就写新模块 / 新入口，架构漂移 |

**何时视为「需求含糊」**

- 仅一句话（如「优化 tips」「修一下菜单」「实现某某功能」），无模块 id、无复现、无验收。
- 一词多义：`tips` 可能指 GameTooltip 锚点/表现、设置页说明文案、某业务模块自绘提示，或 SavedVariables / 调试提示。

**辨领域（先归类，再打开编辑器）**

- **浮动游戏提示**：`Toolbox.Tooltip`、`Modules/TooltipAnchor.lua`、`GameTooltip` / `hooksecurefunc`。
- **设置界面字符串**：`Toolbox/Core/Foundation/Locales.lua` + 各模块 `RegisterSettings`；勿在业务里硬编码中文/英文句子。
- **聊天输出**：须经 **`Toolbox.Chat`**（见 AGENTS「领域对外 API 优先」）。
- **暴雪窗口挂接 / 子控件**：AGENTS「暴雪 UI 挂接时机」；禁止以固定秒级 `C_Timer` 作为等布局的唯一手段。
- **模块专属玩法逻辑**：对应 `Modules/<name>.lua` + `ToolboxDB.modules.<moduleId>`；不先假设要改 `Core`。

---

## 2. 文档分层

```
docs/
├── DOCS-STANDARD.md          # docs/** 写作唯一规范：目录、命名、模板、状态
├── Toolbox-addon-design.md   # 总设计：架构 + 约定 + 已有模块说明（随功能迭代更新「映射表」）
├── AI-ONBOARDING.md          # 本文件：读档顺序与文档分层
├── FEATURES.md               # 产品功能总览与全局入口索引
├── release.md                # 发布记录与发版流程
├── features/                 # 模块/主题级功能文档：<topic>-features.md
├── specs/                    # 需求规格：<topic>-spec.md
├── designs/                  # 设计方案：<topic>-design.md
├── plans/                    # 实施计划：<topic>-plan.md
├── tests/                    # 测试计划与测试记录：<topic>-test.md
├── templates/                # 标准模板：features/spec/design/plan/test
└── superpowers/              # 历史遗留目录，禁止新增 specs/plans 同类文档
```

- **总设计**：唯一长期架构；模块列表、扩展点、`ToolboxDB`、里程碑只维护这一份。
- **FEATURES.md**：只做全局产品功能总览；模块级功能说明写到 `docs/features/`。
- **features/specs/designs/plans/tests**：分别承载功能、需求、设计、计划、测试；目录职责与模板统一见 [DOCS-STANDARD.md](./DOCS-STANDARD.md)。
- **superpowers/**：仅保留历史文档；后续新增文档不再进入这些目录。
- **Lua 注释与 Locales**：以 [AGENTS.md](../AGENTS.md)「Lua 开发规范」与「项目约束」为准。

---

## 3. 加新功能时，人要补什么（给 AI 的最小信息包）

在对话里或 `docs/specs/xxx.md` 里尽量包含：

1. **文档类型**：本次要写的是功能、需求、设计、计划还是测试；按 [DOCS-STANDARD.md](./DOCS-STANDARD.md) 选目录与模板。
2. **模块 id**（如 `cooldown_overlay`）是否与设计文档映射表已预留一致。
3. **客户端**：正式服（本仓库默认）。
4. **数据**：存在 `ToolboxDB.modules.<id>` 哪些键；是否要迁移。
5. **设置**：是否需要 `RegisterSettings`、大致控件（开关 / 滑条 / 下拉）。
6. **边界**：不做什么（避免 AI 扩大范围）。
7. **验收**：例如「重载后位置保留」「战斗中不报错」。
8. **若涉及静态数据、外部生成或多种数据来源**：**主方案须唯一**（谁生成、谁维护、未知键策略）；避免仅写「用静态表」而不定来源与边界。

---

## 4. 功能做完后，文档谁更新

| 变更 | 更新哪里 |
|------|----------|
| 新模块上线 | `Toolbox-addon-design.md`：鸟瞰图、§2.2 映射表、§3 数据示例、§6 TOC、§7 里程碑 |
| 仅修 bug、未改行为 | 一般不改总设计；除非发现原约定错误，再改文档 |
| 架构级变更 | 先改 `Toolbox-addon-design.md`，再写代码 |

---

## 5. 权威性说明

- **实现约束**以仓库根 [AGENTS.md](../AGENTS.md) 为准（AI 行为规则 + Lua 规范 + 暴雪 UI 挂接时机）。
- **本文**（AI-ONBOARDING.md）提供背景、分层说明与最小信息包模板；不重复 AGENTS.md 的强制规则。
- 两处有出入时，以 **AGENTS.md** 为准并应修正本文。

---

## 6. 不建议的做法

- 多份「总架构」互不同步（只保留 **Toolbox-addon-design.md** 为总纲）。
- 在 `docs/superpowers/specs/`、`docs/superpowers/plans/` 继续新增需求/设计/计划文档（新文档统一走 [DOCS-STANDARD.md](./DOCS-STANDARD.md) 定义的目录）。
- 把大段 API 教程复制进仓库（链到 [warcraft.wiki.gg](https://warcraft.wiki.gg) 或官方文档即可）。
- 无日期、无主题的零碎 `notes.md` 长期堆在根目录。
- AI 在需求仍含糊时跳过三关、直接改业务 Lua / TOC（见 AGENTS.md「AI 行为规则」）。
- AI 在数据来源 / 主方案未定时以「是否要实现」收尾（见三关·关 2）。

---

## 7. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-01 | 首版：读档顺序、分层、最小信息包、收尾更新表 |
| 2026-04-02 | 必读表增加 `AGENTS.md`；§1.1 改动节奏；§1.2 AI 建议执行路径；§1.2 硬约束×2 |
| 2026-04-03 | §1.2 增加「防未选定主方案就问是否实现」硬约束；§3 最小信息包增第 7 条 |
| 2026-04-05 | 重构：§1.2 改为判断树背景说明（判断树移至 AGENTS.md「AI 行为规则」）；去重「言行一致」「本地隔离」等原则（统一在 AGENTS.md）；§5 明确权威性归属 |
| 2026-04-09 | 可选阅读补充「Data 静态数据导出」入口：统一指向 AGENTS.md 的 WoWDB 导出强制规则与文件头驱动约定 |
| 2026-04-09 | AGENTS.md 补充 Data 文件头标准模板（数据库导出模板 / 手工维护模板），用于 AI 自动识别导出范围 |
| 2026-04-12 | 新增 `DOCS-STANDARD.md` 作为 `docs/**` 写作规范；文档分层收口为 `specs/designs/plans/tests/templates`，并将 `features/`、`superpowers/` 标为历史遗留目录 |
| 2026-04-12 | 文档命名规则改为 `<topic>-<type>.md`；同一类型只保留一份文档，变更追溯依赖 Git 历史 |
| 2026-04-12 | `docs/features/` 改为现行有效目录，用于模块/主题级功能文档；`FEATURES.md` 保留为全局总览入口 |
| 2026-04-13 | 明确单功能单文档续写原则：功能已存在对应文档时，重构与补充直接修改原文档，不另起平行文件 |
