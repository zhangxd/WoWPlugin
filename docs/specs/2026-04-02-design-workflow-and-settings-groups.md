# 协作节奏规范 + 设置页可折叠分组

**日期**：2026-04-02  
**状态**：§B 为设置页分组需求（**未编码**）。协作节奏以 [AGENTS.md](../../AGENTS.md) 文首「改动节奏」、[AI-ONBOARDING.md](../AI-ONBOARDING.md) §1.1 为准，**不在此重复**。

---

## A. 协作节奏

见 [AGENTS.md](../../AGENTS.md)（文首「改动节奏」）、[AI-ONBOARDING.md](../AI-ONBOARDING.md) §1.1。

---

## B. 设置页可折叠分组（树状展开）

### B.1 目标

在 **单一 AddOn、单一 Settings 类目页** 内，将各 `RegisterModule` 的 `RegisterSettings` 区块归入 **可折叠分组**，支持 **展开/折叠**；**持久化**折叠状态；**新增模块**须声明所属分组并遵守分组注册规则。

### B.2 与现有架构的关系

- **不改变**：`RegisterModule`、`RegisterSettings(box)` 契约；`box.realHeight`；`ToolboxDB.modules.<moduleId>` 存模块业务数据。  
- **新增约定**（实现时落地）：  
  - 模块定义字段 **`settingsGroupId`**（字符串），取值须为 `SETTINGS_GROUP_ORDER` 中某一 **分组 id**。**新模块须填写**；存量未填写的模块，实现中按 **`misc`** 渲染。  
  - **`UI/SettingsHost.lua`** 内维护 **`SETTINGS_GROUP_ORDER`**：分组 **id**、**Locales 键**（分组标题）、**顺序**。  
  - **全局存档**（非 `modules.*`）：`ToolboxDB.global.settingsGroupsExpanded[groupId] = true/false`；键缺失或 `nil` 按 **展开** 处理；`DB.lua` 默认值全为 `true`。

#### B.2.1 页面结构（与现 `Build()` 一致，仅中间段替换为「分组」）

自上而下固定为：

1. **界面语言**（`BuildLanguageSection`）— 非分组。  
2. **重载界面**（`BuildReloadSection`）— 非分组。  
3. **模块设置** — **本需求唯一改动段**：由「按拓扑平铺」改为「按 `SETTINGS_GROUP_ORDER` 渲染可折叠组，组内再按拓扑顺序渲染各模块 `RegisterSettings`」。  
4. **效果预览**（`BuildPreviewSection`）— 非分组，仍置于最末。

**原则**：语言、重载、预览与「模块业务开关」无关，**不**塞进任何折叠组，避免玩家找不到全局入口。

### B.3 分组划分与 Locales 文案（对齐稿）

| 分组 id | Locales 键 | enUS | zhCN | 模块（当前仓库） |
|---------|------------|--------------|--------------|-------------------------|
| `general` | `SETTINGS_GROUP_GENERAL` | General | 常规 | `chat_notify` |
| `ui_windows` | `SETTINGS_GROUP_UI_WINDOWS` | Windows & UI | 窗口与界面 | `mover`、`micromenu_panels` |
| `tooltip` | `SETTINGS_GROUP_TOOLTIP` | Tooltip | 提示框 | `tooltip_anchor` |
| `misc` | `SETTINGS_GROUP_MISC` | Other | 其他 | 未声明 `settingsGroupId` 的模块（兜底） |

- **顺序**由 `SETTINGS_GROUP_ORDER` 数组决定；**空分组不渲染**（不显示组标题）。  
- **组内顺序**：与 `ModuleRegistry` 拓扑排序一致，**只保留**属于本组的模块（即先 `GetSorted()`，再按 `settingsGroupId` 分桶）。  
- **新模块**：在 `RegisterModule` 中**须**写 `settingsGroupId`，取值须为上表某一 **分组 id**。**存量**模块未写该字段时，实现中归入 **`misc`**（`SETTINGS_GROUP_ORDER` 须含 `misc` 行）。

### B.4 UI 行为

- 每组 **一行可点击标题**（左侧 ▼/▶ 或等价符号），点击切换展开并写回 `settingsGroupsExpanded`。  
- 组内模块区块相对组容器 **左侧缩进 16px**。  
- **折叠/展开**：点击后写档并调用 **`Toolbox.SettingsHost:Build()`**（全页重建）；与切换语言时一致，保证滚动高度正确。  
- **切换语言**：`Build()` 全页重建；展开状态从 **`ToolboxDB.global.settingsGroupsExpanded`** 读取，不因语言切换丢失。

### B.4.1 组标题可点区域

- 行高 **≥ 26px**，整行可点（`Button` 或等价）。

### B.5 数据契约（`ToolboxDB.global`）

```lua
-- 默认值（在 Core/DB.lua 的 global 默认表里合并）
settingsGroupsExpanded = {
  general = true,
  ui_windows = true,
  tooltip = true,
  misc = true,
}
```

- **语义**：`true` 展开，`false` 折叠；**键缺失**视为 `true`（与 `mergeTable` 及读档逻辑一致）。  
- **新增分组 id** 时：必须同时扩展 `SETTINGS_GROUP_ORDER`、Locales、`defaults.settingsGroupsExpanded` 中对应键（默认 `true`）。

### B.6 验收要点

- 四个分组标题在中英文 Locales 下显示正确。  
- 折叠后仅显示组标题，滚动区域高度正确。  
- 重载后展开状态保持。  
- 新模块文档：在 **总设计 §4 模块契约** 或 **AI-ONBOARDING** 中增加「须设置 `settingsGroupId` 并在 `SETTINGS_GROUP_ORDER` 登记」一句（实现时同步）。

### B.7 实现清单（供开动后逐项打勾）

| 序号 | 项 |
|------|-----|
| 1 | `Core/DB.lua`：`global.settingsGroupsExpanded` 默认值 |
| 2 | `Core/Locales.lua`：`SETTINGS_GROUP_*` 四键 enUS/zhCN |
| 3 | `Core/ModuleRegistry.lua`：文件头注释说明 `settingsGroupId` |
| 4 | `UI/SettingsHost.lua`：`SETTINGS_GROUP_ORDER` + 折叠 UI + `Build()` 中间段替换 |
| 5 | `Modules/*.lua`：各模块 `settingsGroupId` 与 B.3 表一致 |
| 6 | `docs/Toolbox-addon-design.md` §4 / §5.1：模块契约与设置页说明补一句 |
| 7 | 游戏内：切换语言、折叠、重载、滚动条自测 |

### B.8 编码门禁

编码须满足 [AGENTS.md](../../AGENTS.md)「改动节奏」（**开动**）。实现后合并结论至 [Toolbox-addon-design.md](../Toolbox-addon-design.md) 相应节。

---

## 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-02 | 初稿：协作节奏 A + 设置分组设计 B；代码层未实现 |
| 2026-04-02 | 对齐稿：§B.2.1 页面结构；B.3 Locales 草案；B.4 推荐全页 Build；B.5 数据契约；B.7 实现清单 |
| 2026-04-02 | 文首与 §B 标题去「草案」歧义；§A.3 补充 hotfix 与琐碎改动裁量 |
| 2026-04-02 | 审核：§A 合并为 A.1/A.2；与 AGENTS 对齐；§B 去「推荐/建议」；B.3 新模块须声明 settingsGroupId |
| 2026-04-02 | §A 改为指向 AGENTS/AI-ONBOARDING，删除重复正文；B.2 新/存量 settingsGroupId；B.3 表头去「草案」 |
