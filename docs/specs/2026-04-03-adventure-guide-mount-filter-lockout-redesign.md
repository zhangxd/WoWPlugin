# 冒险指南：坐骑筛选与副本 CD 展示（重新设计）

**状态**：设计稿（旧实现已移除，待评审通过后按 §1.1「开动」再编码）  
**日期**：2026-04-03  
**取代**：原 `Modules/SavedInstancesEJ.lua` 方案（`ToolboxDB.global.ejMountFilter` + 侧栏勾选 + 分帧扫 EJ 战利品隐藏列表行）。

**拆分规格**：仅「仅坐骑」列表筛选的定稿见 [superpowers/specs/2026-04-03-ej-mounts-only-filter-design.md](../superpowers/specs/2026-04-03-ej-mounts-only-filter-design.md)（未索引行策略 **A**）。

---

## 1. 背景与废弃原因

### 1.1 已删除的旧实现摘要

- 在冒险指南 `instanceSelect` 上挂 **全局勾选**「仅坐骑」，用 **`Toolbox.EJ` 多难度切换 + 扫首领/实例战利品** 判断是否含坐骑物品，结果写入 **`ToolboxDB.global.ejMountFilter`**。
- 通过 **隐藏列表行** 表达筛选；依赖 **`EncounterJournal_ListInstances` post-hook** 与 **OnShow** 创建控件。

### 1.2 为何抛弃并重做

| 问题 | 说明 |
|------|------|
| **架构** | 未走 `RegisterModule`，数据落在 `global.ejMountFilter`，与 [Toolbox-addon-design.md](../Toolbox-addon-design.md)「模块数据在 `modules.<id>`」不一致。 |
| **体验与成本** | 全量扫描可能卡顿/耗时；索引与 UI 强耦合在单文件，后续加「仅 CD」「列表行提示」等扩展困难。 |
| **产品未定** | 坐骑判定方式（仅战利品表 vs 静态表）、CD 展示位置与匹配规则，应在规格层先定再实现。 |

旧存档中若仍残留 `ToolboxDB.global.ejMountFilter`，客户端会保留该表；**新代码不应再读写**，可在未来迁移中删除或忽略。

---

## 2. 目标（新需求）

1. **坐骑筛选**：在冒险指南中，能筛出（或高亮）**有坐骑相关掉落**的副本/团本实例。  
2. **CD 信息**：在**副本界面**（与实例详情同一语境）展示当前角色对该副本的 **锁定/进度/重置** 等（数据来自 **`Toolbox.Lockouts`** 封装）。

---

## 3. 设计原则（必须遵守）

- **模块契约**：新能力以 **`RegisterModule`** 接入，模块 id 固定（建议 **`ej_instance_overlay`** 或经评审的命名），数据仅 **`ToolboxDB.modules.<id>`**。
- **领域 API**：仅通过 **`Toolbox.EJ`**、`Toolbox.Lockouts`、`Toolbox.MountJournal`、`Toolbox.Chat` 等已有门面访问客户端；业务模块不直接调用 `EJ_*`。
- **暴雪 UI 挂接**：控件创建与刷新绑定 **`OnShow` / `hooksecurefunc`** 等正式路径；**禁止**以固定秒级 `C_Timer.After` 作为「等布局」的主手段（见 [AGENTS.md](../../AGENTS.md)）。
- **文案**：玩家可见字符串集中在 **`Locales.lua`**（`Toolbox.L` 键名）。

---

## 4. 方案选项（待选型）

### 4.1 坐骑筛选 — 数据来源

| 方案 | 优点 | 缺点 |
|------|------|------|
| **A. 运行时扫 EJ 战利品**（与旧逻辑同类） | 随版本补丁自动反映手册数据 | 有 CPU/帧耗时，需严格分帧与缓存策略 |
| **B. 插件内置静态表**（journalInstanceID → 是否含坐骑） | 无扫描成本、可离线维护 | 需随版本更新表，易过期 |
| **C. 混合** | 静态覆盖常见本，其余懒加载扫描 | 实现复杂度较高 |

**建议**：规格评审时选定 A/B/C 之一，并写清 **缓存键、失效条件（如 `interfaceBuild`）、是否提供「强制重建」**。

### 4.2 坐骑筛选 — 交互

| 方案 | 说明 |
|------|------|
| **隐藏无坐骑行** | 与旧版类似，列表更干净；需处理「未索引」行的显示策略 |
| **仅灰显/标记图标** | 不破坏列表完整性，实现可能更稳 |
| **独立子筛选（下拉/Tab）** | 与暴雪 Tab 并存，需评估空间与 taint |

### 4.3 CD 展示 — 匹配逻辑

- **主键**：在可行范围内，用 **`GetSavedInstanceInfo` 返回的 `instanceId`** 与 **`C_EncounterJournal.GetInstanceInfo()`** 中可得的 **世界实例 `instanceID`** 对齐（见 `EncounterJournal.lua` 注释：与 journal 的 id 不一定一致）。  
- **兜底**：名称规范化匹配（需注意本地化与重名）。  
- **多难度多条锁定**：需约定显示 **合并摘要** 还是 **当前手册难度对应一条**。

### 4.4 CD 展示 — 界面位置

- **推荐首版**：实例**详情区**单行文字（难度、进度、重置剩余时间）；列表行 CD 为可选二期。  
- **刷新时机**：实例切换、`UPDATE_INSTANCE_INFO`、以及暴雪刷新实例详情的安全 hook（函数名以实机为准）。

### 4.5 设置

- 建议模块提供 **`RegisterSettings`**：**总开关**、坐骑筛选开关、CD 行开关、（若采用扫描）是否允许后台索引等；`settingsGroupId` 建议 **`misc`**。

---

## 5. 验收建议（实现阶段填写具体步骤）

- 打开冒险指南，切换资料片/团本地下城 Tab，**无 Lua 报错**；控件在 **OnShow / ListInstances** 路径下稳定出现。  
- 坐骑筛选行为与 §4.1、§4.2 选定一致；重载后缓存行为符合规格。  
- CD 行与游戏内 **地下城手册 / 锁定列表** 一致或差异在规格中说明原因。  
- 战斗中仅更新文本，不触发不安全控件路径。

---

## 6. 文档与代码变更清单（开动后）

- 更新 [Toolbox-addon-design.md](../Toolbox-addon-design.md) §2.2 映射表、TOC 顺序、里程碑（若模块落地）。  
- 新模块文件 + `Toolbox/Toolbox.toc` 条目。  
- 本文件可归档或合并至总设计「功能分述」一节。

---

## 7. 参考

- `Core/EncounterJournal.lua` — `Toolbox.EJ`  
- `Core/Lockouts.lua` — `Toolbox.Lockouts`  
- `Core/MountJournal.lua` — 坐骑物品解析  
- 旧面板向规格（独立窗口路线）：[2026-04-01-saved-instances-panel-design.md](../superpowers/specs/2026-04-01-saved-instances-panel-design.md)（与本案可并存或收敛，以总设计为准）
