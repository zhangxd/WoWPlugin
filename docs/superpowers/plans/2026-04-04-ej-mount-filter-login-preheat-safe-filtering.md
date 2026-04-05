# 冒险指南仅坐骑筛选（登录预热安全版）实施计划

> **给代理执行者：** 必须使用 `superpowers:subagent-driven-development`（若支持子代理）或 `superpowers:executing-plans` 执行本计划。步骤统一使用复选框语法（`- [ ]`）跟踪。

**目标：** 让冒险指南“仅坐骑”筛选依赖登录期预热完成的目录缓存，在玩家浏览 EJ 地下城/团队副本列表时暂停缓存扫描，并且只在当前列表所需数据全部就绪后才启用复选框。

**架构：** 保持 `Toolbox.DungeonRaidDirectory` 作为坐骑掉落事实源，但新增“EJ 交互暂停闸门”，确保玩家正在浏览地下城/团队副本列表时，不会再改写共享 EJ 选中状态。`Toolbox.Modules.EJMountFilter` 收敛为纯 UI/过滤层：当前列表还存在未决 `nil` 摘要时复选框置灰，数据齐后再沿用现有行折叠路径实现对齐安全的筛选。

**技术栈：** 魔兽世界正式服 Lua 插件、Blizzard Encounter Journal 挂接、ScrollBox 行高覆写、SavedVariables 缓存、`Toolbox.Chat`、`luaparser`

---

## 阶段 1：目录层暂停 / 恢复状态

### 任务 1：为 `DungeonRaidDirectory` 增加 EJ 安全暂停状态

**文件：**
- 修改：`Toolbox/Core/DungeonRaidDirectory.lua`
- 修改：`Toolbox/Core/Locales.lua`
- 测试：本地 `rg` + `luaparser`

- [ ] **步骤 1：先写失败验证**

运行：

```powershell
rg -n "PauseForEncounterJournal|ResumeForEncounterJournal|IsPausedForEncounterJournal|DRD_EJ_PAUSED" Toolbox/Core/DungeonRaidDirectory.lua Toolbox/Core/Locales.lua
```

期望实现前：无匹配。

- [ ] **步骤 2：增加运行时暂停字段与公开暂停 / 恢复接口**

在 `Toolbox/Core/DungeonRaidDirectory.lua` 中增加运行时字段与公开接口：

- `PauseForEncounterJournal()`
- `ResumeForEncounterJournal()`
- `IsPausedForEncounterJournal()`
- pause metadata used for one-shot pause/resume notifications

Requirements:

- 暂停只影响进行中的构建
- 暂停后保留当前进度，不重置缓存
- 恢复后继续当前构建，而不是重新开始
- 若某次构建曾因 EJ 交互被暂停，成功完成时允许额外输出一条成功聊天提示

- [ ] **步骤 3：暂停时停止推进扫描单元**

更新 driver 的 `OnUpdate` 路径：当 `runtime.state == "building"` 且“因 EJ 暂停”时，本帧不做任何推进。暂停期间不得调用 `SelectTier` / `SelectInstance` / `SetDifficulty`。

- [ ] **步骤 4：补暂停 / 恢复反馈文案**

在 `Toolbox/Core/Locales.lua` 中新增以下文案键：

- EJ 暂停原因 Tooltip
- 可选的暂停聊天提示
- 恢复完成 / 可用聊天提示

- [ ] **步骤 5：运行语法验证**

运行：

```powershell
@'
from luaparser import ast
ast.parse(open(r'd:\WoWPlugin\Toolbox\Core\DungeonRaidDirectory.lua', 'r', encoding='utf-8').read())
ast.parse(open(r'd:\WoWPlugin\Toolbox\Core\Locales.lua', 'r', encoding='utf-8').read())
print('OK DungeonRaidDirectory.lua')
print('OK Locales.lua')
'@ | python -
```

期望：两个文件均输出 `OK ...`。

## 阶段 2：仅坐骑复选框可用态与 Tooltip

### 任务 2：让 EJ 复选框具备“当前列表是否就绪”的感知能力

**文件：**
- 修改：`Toolbox/Modules/EJMountFilter.lua`
- 修改：`Toolbox/Core/Locales.lua`
- 测试：本地 `rg` + `luaparser`

- [ ] **步骤 1：先写失败验证**

运行：

```powershell
rg -n "GetCurrentListReadiness|RefreshMountFilterAvailability|EJ_MOUNT_FILTER_PAUSED_HINT|EJ_MOUNT_FILTER_READY" Toolbox/Modules/EJMountFilter.lua Toolbox/Core/Locales.lua
```

期望实现前：无匹配。

- [ ] **步骤 2：增加“当前列表是否已就绪”辅助函数**

在 `Toolbox/Modules/EJMountFilter.lua` 中新增辅助函数，用于：

- 收集当前地下城 / 团队副本列表的 JID
- 计算当前列表是否已全部就绪（即每个候选副本都满足 `HasAnyMountLoot(jid) ~= nil`）
- 返回供 Tooltip / 调试输出使用的统计数据

- [ ] **步骤 3：增加复选框可用态刷新逻辑**

实现一个刷新函数，要求：

- 只有当前列表已就绪，或现有缓存已能解析当前全部项时，才启用复选框
- 不可用时维持灰显 / 置灰视觉状态
- 在不可用期间保留已保存的勾选偏好，但不实际应用过滤

- [ ] **步骤 4：更新 Tooltip 行为**

当因构建未完成 / 已暂停而不可用时：

- Tooltip 说明刷新已暂停，以避免和当前 EJ 浏览操作打架
- 明确提示：关闭或离开当前 EJ 列表语境后，后台会自动继续刷新

当可用时：

- Tooltip 显示正常的“仅坐骑”说明文案

- [ ] **步骤 5：保持筛选后的排版对齐安全**

筛选逻辑继续使用：

- `GetElementExtent(...) -> 0` 作为主布局路径
- `row:Hide()` 仅作视觉兜底

并且只在以下条件都满足时才应用：

- 当前筛选挂件可见
- 复选框处于可用状态
- 复选框已勾选

- [ ] **步骤 6：运行语法验证**

运行：

```powershell
@'
from luaparser import ast
ast.parse(open(r'd:\WoWPlugin\Toolbox\Modules\EJMountFilter.lua', 'r', encoding='utf-8').read())
print('OK EJMountFilter.lua')
'@ | python -
```

期望：`OK EJMountFilter.lua`

## 阶段 3：挂接整合与聊天提示

### 任务 3：浏览 EJ 时暂停，离开后恢复，并自动刷新 UI

**文件：**
- 修改：`Toolbox/Modules/EJMountFilter.lua`
- 修改：`Toolbox/Core/DungeonRaidDirectory.lua`
- 测试：本地 `rg` + `luaparser`

- [ ] **步骤 1：先写失败验证**

运行：

```powershell
rg -n "PauseForEncounterJournal|ResumeForEncounterJournal|OnUpdate.*applyMountFilterVisibility|paused.*Adventure Guide|筛选已可用" Toolbox/Modules/EJMountFilter.lua Toolbox/Core/DungeonRaidDirectory.lua
```

期望实现前：无匹配或仅部分匹配。

- [ ] **步骤 2：在 EJ 列表浏览语境中暂停目录构建**

把 `Toolbox.Modules.EJMountFilter` 现有挂点接上：当玩家进入地下城 / 团队副本列表浏览语境，且目录构建仍在进行时，调用 `Toolbox.DungeonRaidDirectory.PauseForEncounterJournal()`。

- [ ] **步骤 3：离开冲突语境时恢复构建**

当 EJ 关闭，或离开地下城 / 团队副本列表语境时，调用 `Toolbox.DungeonRaidDirectory.ResumeForEncounterJournal()`。

- [ ] **步骤 4：增加低频 UI 刷新**

在模块宿主 frame 上增加一个轻量 `OnUpdate`，用于：

- 刷新复选框可用态
- 当构建状态变化时重新应用过滤
- 用低频间隔避免频繁抖动 / 重算

- [ ] **步骤 5：在“曾暂停”的构建成功完成后输出一次聊天提示**

如果某次构建曾因 EJ 浏览被暂停，之后恢复并成功完成，则通过 `Toolbox.Chat` 输出一条本地化成功提示。

- [ ] **步骤 6：运行语法验证**

运行：

```powershell
@'
from luaparser import ast
ast.parse(open(r'd:\WoWPlugin\Toolbox\Core\DungeonRaidDirectory.lua', 'r', encoding='utf-8').read())
ast.parse(open(r'd:\WoWPlugin\Toolbox\Modules\EJMountFilter.lua', 'r', encoding='utf-8').read())
print('OK DungeonRaidDirectory.lua')
print('OK EJMountFilter.lua')
'@ | python -
```

期望：两个文件均输出 `OK ...`。

## 阶段 4：规格 / 文档更新与最终验证

### 任务 4：更新设计文档并完成最终校验

**文件：**
- 修改：`docs/superpowers/specs/2026-04-03-ej-mounts-only-filter-design.md`
- 修改：`docs/Toolbox-addon-design.md`
- 测试：`rg` + `git diff --check`

- [ ] **步骤 1：更新 EJ 仅坐骑筛选规格**

把已确认的新行为写回规格文档：

- 登录预热缓存策略
- 浏览 EJ 列表时暂停构建
- 当前列表全部就绪前复选框置灰
- 因暂停而恢复的构建成功完成后，仅输出一次聊天提示

- [ ] **步骤 2：必要时更新长期总设计文档**

在总设计里补充：冒险指南仅坐骑筛选现依赖预热完成的目录缓存，并通过在玩家浏览副本列表时暂停实时扫描来避免与 EJ 共享状态争用。

- [ ] **步骤 3：运行最终验证**

运行：

```powershell
@'
from luaparser import ast
for path in [
    r'd:\WoWPlugin\Toolbox\Core\DungeonRaidDirectory.lua',
    r'd:\WoWPlugin\Toolbox\Core\Locales.lua',
    r'd:\WoWPlugin\Toolbox\Modules\EJMountFilter.lua',
]:
    ast.parse(open(path, 'r', encoding='utf-8').read())
    print('OK', path)
'@ | python -
git diff --check -- Toolbox/Core/DungeonRaidDirectory.lua Toolbox/Core/Locales.lua Toolbox/Modules/EJMountFilter.lua docs/superpowers/specs/2026-04-03-ej-mounts-only-filter-design.md docs/Toolbox-addon-design.md
```

期望：

- 所有 Lua 文件均成功解析
- `git diff --check` 不返回尾随空格或 patch 级错误
