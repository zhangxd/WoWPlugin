# Toolbox · AGENTS 合规与架构审查（规格）

**日期**：2026-04-02  
**状态**：已定稿（选项 A：单份当期规格，后续再出实现计划）  
**依据**：[AGENTS.md](../../../AGENTS.md)、[docs/Toolbox-addon-design.md](../../../docs/Toolbox-addon-design.md)

---

## 1. 目标

在**一次连贯的审查周期**内，对照 **AGENTS.md** 与总设计，从**架构与合规**两方面盘点代码与文档，形成**可执行的违规清单与修复顺序**，并在实现阶段逐项收口，使**新增与修改的 Lua**均符合仓库约定（存量允许分步迁移，但本周期应对齐「高风险」路径）。

**节奏约定**：与前期脑暴一致，采用 **「尽量一轮扫完」**（大 diff 可接受），但仍按依赖**自下而上**安排实现顺序（见 §6），避免无次序改动导致反复冲突。

---

## 2. 范围

### 2.1 纳入

| 类别 | 说明 |
|------|------|
| **暴雪 UI 挂接** | 子控件创建、改锚点、DataProvider；**禁止**以固定秒数 `C_Timer.After` 作为**唯一或主路径**等布局；须 `OnShow` / `hooksecurefunc` 等与生命周期对齐（见 AGENTS 专节）。 |
| **领域对外 API** | 聊天经 `Toolbox.Chat`；提示默认锚点经 `Toolbox.Tooltip`；手册经 `Toolbox.EJ`；锁定 / 坐骑 / 物品 / 地图经 `Core` 下对应表；**禁止**在 `Modules/*.lua` 中新增 `DEFAULT_CHAT_FRAME` / 业务侧直调 `EJ_*` 等绕过约定。 |
| **模块与数据** | `RegisterModule`、`ToolboxDB.modules.<moduleId>`、设置经 `RegisterSettings`；Core 不堆单功能业务。 |
| **引导与生命周期** | `Bootstrap` 顺序、`OnModuleLoad` / `OnModuleEnable` 边界不被模块侧绕开。 |
| **文档一致性** | [Toolbox-addon-design.md](../../../docs/Toolbox-addon-design.md) 鸟瞰图、§2.2 映射、TOC、里程碑与**当前 TOC/模块集合**一致。 |

### 2.2 不强制纳入（可选债）

- 纯文案润色、与行为无关的注释措辞（除非与对外 API 文档冲突）。
- 与本次合规**无关**的新功能设计。

---

## 3. 审阅维度（合规矩阵）

评审时对每个**相关文件**勾选 **通过 / 待改 / 例外（须注理由）**。

1. **分层**：`Modules` → 领域对外 API → WoW API；`UI/SettingsHost` 不含业务分支。
2. **领域对外 API**：无重复 hook、无模块侧应集中却在多处直调的低层 API。
3. **暴雪 UI 适配**：生命周期挂接符合 AGENTS；无「仅靠定时器等布局」作为主路径。
4. **数据**：仅读写本模块 `modules.<id>`；全局迁移仅在 `DB.lua`。
5. **玩家可见字符串**：`Locales.lua`，业务中 `Toolbox.L.*`。
6. **文档**：总设计与 TOC、模块列表一致。

---

## 4. 发现方法（可重复执行）

1. **静态检索**（示例模式，随实现补充）  
   - `C_Timer.After`：区分 **`After(0)` 下一帧合并**（须有注释说明目的）与 **固定秒数**。  
   - `DEFAULT_CHAT_FRAME`、`AddMessage`：应仅出现在 **`Core/Chat.lua`**（领域对外 API 实现）。  
   - `EJ_`：业务模块中不应出现；**允许**出现在 `Core/EncounterJournal.lua` 兜底分支。  
2. **人工走读**：`Bootstrap`、`ModuleRegistry`、各 `Modules/*.lua` 的注册与依赖。  
3. **游戏内抽检**：改动涉及的手册、设置壳、微型菜单面板等路径（以实际修改为准）。

---

## 5. 已知热点（盘点起点，非最终结论）

以下路径在静态检索中已露出**需对照 AGENTS 复核**的实现，**实现阶段**须逐条判定「保留例外 / 改为事件或 hook 驱动」：

| 文件 | 现象 | 复核要点 |
|------|------|----------|
| [Toolbox/Modules/MicroMenuPanels.lua](../../../Toolbox/Modules/MicroMenuPanels.lua) | `runHooks()` 内 `C_Timer.After(1)` 与 `C_Timer.After(5)` | 是否仍属「等布局」主路径；能否改为面板 `OnShow`、已列出的全局刷新 hook、或 `PLAYER_ENTERING_WORLD` 等可验证时机 + 幂等重试。 |
| [Toolbox/UI/SettingsHost.lua](../../../Toolbox/UI/SettingsHost.lua) | `PLAYER_ENTERING_WORLD` 后多段 `C_Timer.After(i * 0.5, tick)` | 是否可收敛为 `GameMenuFrame` 的 `OnShow` + 单次 `tick`，或保留须有**文档化例外理由**。 |
| [Toolbox/Core/Tooltip.lua](../../../Toolbox/Core/Tooltip.lua) | `C_Timer.After(0, …)` | **已具备**文件头与行内说明：下一帧合并、防闪烁；属**已认可模式**，非「固定秒数等布局」。 |

`Core/EncounterJournal.lua` 中的 `EJ_*` 调用属于 **领域对外 API 内兜底**，不视为模块违规。

---

## 6. 修复策略与推荐顺序

1. **先文档与契约**：校正总设计中 §2.2、鸟瞰图、TOC 与**当前模块集合**（例如独立窗口类模块若已移除，映射表与示例须一致）。  
2. **再 UI 生命周期**：`MicroMenuPanels`、`SettingsHost` 等待复核的定时器逻辑。  
3. **再模块与 API 走读**：确认无新增绕过 `Toolbox.Chat` / `Toolbox.EJ` 等。  
4. **最后**：Locales、注释与对外 API 文档一致性（与 §2.2 可选债区分，以 PR 规模为准）。

---

## 7. 验收标准

- 合规矩阵中 **「待改」** 均有对应提交或明确 **例外**（理由写在代码注释或本文档修订记录）。  
- **新增/修改的 Lua** 不引入：模块侧直聊、业务侧 `EJ_*`、以固定延迟为**唯一**手册/面板挂接手段（与 AGENTS 一致）。  
- 总设计与 TOC **与仓库现状一致**。  
- 相关路径经 **游戏内 smoke**（若该次 PR 触及对应 UI）。

---

## 8. 文档与收尾义务

- 若模块集合或架构边界有变：更新 [Toolbox-addon-design.md](../../../docs/Toolbox-addon-design.md) 相应节（见 AGENTS「收尾」）。  
- 本规格在实现完成后可 **压缩结论** 回总设计「里程碑」或「风险」小节，避免 specs 长期与代码漂移。

---

## 9. 后续步骤（非本文件执行）

1. 用户审阅本规格。  
2. 调用 **writing-plans** 生成实现计划（任务拆分、文件级勾选、与 Git 分支策略）。  
3. 编码与验证；必要时增量更新本文件「修订记录」。

---

## 10. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-02 | 初稿：选项 A 定稿；范围、矩阵、方法、已知热点、顺序与验收 |
