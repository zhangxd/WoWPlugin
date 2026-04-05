# Settings Subcategories And About Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Toolbox 的单页设置重构为“主类目总览 + 各功能真实子页面 + 关于页”，并为每个功能统一提供启用、调试、清理并重建入口。

**Architecture:** 保持 `RegisterModule` 作为模块接入点，但把设置页宿主改成“分类注册器”。宿主统一渲染每个功能页的公共区，模块只渲染专属设置区；`DungeonRaidDirectory` 继续保留为 `Core` 领域 API，同时新增一个轻量设置模块承载其子页面与模块级开关。

**Tech Stack:** WoW Retail Lua、Blizzard Settings API、PowerShell、Python 3.10（最小静态校验脚本）

---

## Chunk 1: 规格落地与最小校验脚手架

### Task 1: 增加最小静态校验脚本

**Files:**
- Create: `tests/validate_settings_subcategories.py`

- [ ] **Step 1: 写一个先失败的校验脚本**

```python
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
settings_host = (ROOT / "Toolbox" / "UI" / "SettingsHost.lua").read_text(encoding="utf-8")

required = [
    "RegisterCanvasLayoutSubcategory",
    "BuildOverviewPage",
    "BuildAboutPage",
]

missing = [item for item in required if item not in settings_host]
if not missing:
    raise SystemExit("expected settings host to be missing new subcategory structure before implementation")

print("RED: missing new settings subcategory structure:", ", ".join(missing))
sys.exit(1)
```

- [ ] **Step 2: 运行脚本，确认它先失败**

Run: `python tests/validate_settings_subcategories.py`  
Expected: exit code 非 0，并提示当前代码还缺少新的子页面结构。

- [ ] **Step 3: 预留后续断言位**

在同一脚本里预留后续会用到的断言函数，覆盖：

- `SettingsHost.lua` 是否注册总览页、关于页、模块子页
- `DB.lua` 是否为所有模块定义 `debug`
- `Toolbox.toc` 是否加载新增 `Modules/DungeonRaidDirectory.lua`
- `Locales.lua` 是否包含新增公共文案键

---

## Chunk 2: 数据契约与模块公共接口

### Task 2: 统一 DB 默认值与迁移

**Files:**
- Modify: `Toolbox/Core/DB.lua`
- Test: `tests/validate_settings_subcategories.py`

- [ ] **Step 1: 先补一个失败断言，要求所有功能模块具备 `debug`**

在 `tests/validate_settings_subcategories.py` 中加入最小断言：

```python
db_lua = (ROOT / "Toolbox" / "Core" / "DB.lua").read_text(encoding="utf-8")
for needle in [
    "chat_notify = {",
    "mover = {",
    "micromenu_panels = {",
    "tooltip_anchor = {",
    "dungeon_raid_directory = {",
    "ej_mount_filter = {",
]:
    assert needle in db_lua, needle

assert "debug = false" in db_lua
```

- [ ] **Step 2: 运行脚本，确认因 `dungeon_raid_directory` / 统一 debug 缺失而失败**

Run: `python tests/validate_settings_subcategories.py`  
Expected: exit code 非 0，提示 DB 契约尚未完成。

- [ ] **Step 3: 修改 `DB.lua`**

实现以下内容：

- 为现有各模块补 `debug = false`
- 新增 `modules.dungeon_raid_directory`
- 增加旧键迁移：
  - `ej_mount_filter.debugChat -> ej_mount_filter.debug`
  - `global.dungeonRaidDirectoryDebugChat -> modules.dungeon_raid_directory.debug`

- [ ] **Step 4: 再次运行静态校验**

Run: `python tests/validate_settings_subcategories.py`  
Expected: 与 DB 契约相关的断言通过，整体仍可能因后续任务未完成而失败。

### Task 3: 扩展模块契约注释与宿主调用面

**Files:**
- Modify: `Toolbox/Core/ModuleRegistry.lua`
- Test: `tests/validate_settings_subcategories.py`

- [ ] **Step 1: 先补失败断言，要求契约中出现公共设置回调名**

在校验脚本中要求出现：

- `OnEnabledSettingChanged`
- `OnDebugSettingChanged`
- `ResetToDefaultsAndRebuild`
- `settingsIntroKey`
- `settingsOrder`

- [ ] **Step 2: 运行脚本确认失败**

Run: `python tests/validate_settings_subcategories.py`  
Expected: exit code 非 0。

- [ ] **Step 3: 更新 `ModuleRegistry.lua` 文件头与契约说明**

补充新增字段注释，不改变注册表核心逻辑。

- [ ] **Step 4: 重新运行校验**

Run: `python tests/validate_settings_subcategories.py`  
Expected: 契约注释断言通过。

---

## Chunk 3: SettingsHost 子页面化

### Task 4: 先重构 SettingsHost 为总览页 + 子页面注册器

**Files:**
- Modify: `Toolbox/UI/SettingsHost.lua`
- Test: `tests/validate_settings_subcategories.py`

- [ ] **Step 1: 先写失败断言**

在校验脚本中断言 `SettingsHost.lua` 至少包含：

- `RegisterCanvasLayoutCategory`
- `RegisterCanvasLayoutSubcategory`
- `BuildOverviewPage`
- `BuildAboutPage`
- `BuildModulePage`
- `BuildSharedModuleControls`

- [ ] **Step 2: 运行脚本确认失败**

Run: `python tests/validate_settings_subcategories.py`  
Expected: exit code 非 0。

- [ ] **Step 3: 用最小实现重构 `SettingsHost.lua`**

要求：

- 保留 `GameMenu_Init()` 与 `Open()` 能力
- 主类目页只显示总览
- 为各模块创建独立页面
- 宿主统一绘制简介、启用、调试、清理并重建
- 单独注册“关于”页

- [ ] **Step 4: 运行校验**

Run: `python tests/validate_settings_subcategories.py`  
Expected: 与 SettingsHost 结构相关的断言通过。

### Task 5: 把 `DungeonRaidDirectory` 从 SettingsHost 特判迁出

**Files:**
- Create: `Toolbox/Modules/DungeonRaidDirectory.lua`
- Modify: `Toolbox/UI/SettingsHost.lua`
- Modify: `Toolbox/Toolbox.toc`
- Test: `tests/validate_settings_subcategories.py`

- [ ] **Step 1: 先补失败断言**

在校验脚本中新增断言：

- `Toolbox/Modules/DungeonRaidDirectory.lua` 存在
- `Toolbox.toc` 包含 `Modules\\DungeonRaidDirectory.lua`
- `SettingsHost.lua` 不再包含 `BuildDungeonRaidDirectorySection`

- [ ] **Step 2: 运行脚本确认失败**

Run: `python tests/validate_settings_subcategories.py`  
Expected: exit code 非 0。

- [ ] **Step 3: 实现最小目录模块**

要求：

- 模块 id 为 `dungeon_raid_directory`
- 页面简介、启用、调试、清理并重建由宿主绘制
- 模块专属区承载状态、进度、手动重建、快照查看器
- 调试开关与 `Toolbox.DungeonRaidDirectory.SetDebugChatEnabled()` 同步
- 启用开关可控制目录初始化后的后台构建/重建入口是否可用

- [ ] **Step 4: 更新 TOC 并删除宿主内旧特判区块**

- [ ] **Step 5: 运行校验**

Run: `python tests/validate_settings_subcategories.py`  
Expected: 目录模块接入相关断言通过。

---

## Chunk 4: 各模块接入公共设置骨架

### Task 6: 改造现有模块的设置入口

**Files:**
- Modify: `Toolbox/Modules/ChatNotify.lua`
- Modify: `Toolbox/Modules/Mover.lua`
- Modify: `Toolbox/Modules/MicroMenuPanels.lua`
- Modify: `Toolbox/Modules/TooltipAnchor.lua`
- Modify: `Toolbox/Modules/EJMountFilter.lua`
- Test: `tests/validate_settings_subcategories.py`

- [ ] **Step 1: 先补失败断言**

在校验脚本中要求上述模块文件中出现：

- `settingsIntroKey`
- `settingsOrder`
- `OnEnabledSettingChanged`
- `OnDebugSettingChanged`
- `ResetToDefaultsAndRebuild`

- [ ] **Step 2: 运行脚本确认失败**

Run: `python tests/validate_settings_subcategories.py`  
Expected: exit code 非 0。

- [ ] **Step 3: 逐个模块改造**

要求：

- `RegisterSettings(box)` 仅保留专属区
- 把公共启用逻辑迁到 `OnEnabledSettingChanged`
- 把公共调试逻辑迁到 `OnDebugSettingChanged`
- 实现模块级 `ResetToDefaultsAndRebuild`
- 为 `ej_mount_filter` 增加设置页，并展示目录依赖说明

- [ ] **Step 4: 运行校验**

Run: `python tests/validate_settings_subcategories.py`  
Expected: 模块设置入口断言通过。

### Task 7: 补齐 Locales 与页面文案

**Files:**
- Modify: `Toolbox/Core/Locales.lua`
- Test: `tests/validate_settings_subcategories.py`

- [ ] **Step 1: 先补失败断言**

在校验脚本中断言新增文案键存在，例如：

- `SETTINGS_OVERVIEW_TITLE`
- `SETTINGS_ABOUT_TITLE`
- `SETTINGS_MODULE_ENABLE`
- `SETTINGS_MODULE_DEBUG`
- `SETTINGS_MODULE_RESET_REBUILD`
- `MODULE_DUNGEON_RAID_DIRECTORY`
- `MODULE_EJ_MOUNT_FILTER`

- [ ] **Step 2: 运行脚本确认失败**

Run: `python tests/validate_settings_subcategories.py`  
Expected: exit code 非 0。

- [ ] **Step 3: 修改 `Locales.lua`**

要求：

- 为总览页、关于页、公共区、目录页、依赖提示补齐 `enUS` / `zhCN`
- 清理或降级旧的分组文案，至少不再由当前设置宿主主路径使用

- [ ] **Step 4: 重新运行校验**

Run: `python tests/validate_settings_subcategories.py`  
Expected: 文案键断言通过。

---

## Chunk 5: 启动链路、文档与验证

### Task 8: 调整启动链路与打开逻辑

**Files:**
- Modify: `Toolbox/Core/Bootstrap.lua`
- Modify: `Toolbox/UI/SettingsHost.lua`
- Test: `tests/validate_settings_subcategories.py`

- [ ] **Step 1: 先补失败断言**

在校验脚本中要求：

- `Bootstrap.lua` 仍调用 `Toolbox.SettingsHost`
- `Open()` 仍存在
- `GameMenu_Init()` 仍存在

- [ ] **Step 2: 运行脚本确认当前失败或待后续实现补齐**

- [ ] **Step 3: 调整启动与首次构建策略**

要求：

- `ADDON_LOADED` 时创建并注册所有页面
- 避免只针对单一大页调用旧 `Build()`
- 保证 `/toolbox`、ESC 按钮仍能打开总览页

- [ ] **Step 4: 运行校验**

Run: `python tests/validate_settings_subcategories.py`  
Expected: 启动链路断言通过。

### Task 9: 更新文档

**Files:**
- Modify: `README.md`
- Modify: `docs/Toolbox-addon-design.md`

- [ ] **Step 1: 更新 README 设置说明**

将“按分组折叠展示”改为“主类目 + 子页面”模型。

- [ ] **Step 2: 更新总设计**

同步更新：

- 鸟瞰图中的 SettingsHost 说明
- 模块映射中新增 `dungeon_raid_directory`
- 数据模型中的统一 `debug`
- 设置结构从折叠组改为子页面

- [ ] **Step 3: 运行全文搜索复查**

Run: `rg -n "settingsGroupsExpanded|BuildDungeonRaidDirectorySection|按分组折叠|settingsGroupId" README.md docs Toolbox`
Expected: 仅剩遗留注释或明确历史说明，不应把它们写成当前设置页主结构。

### Task 10: 最终校验

**Files:**
- Test: `tests/validate_settings_subcategories.py`

- [ ] **Step 1: 运行静态校验脚本**

Run: `python tests/validate_settings_subcategories.py`  
Expected: exit code 0，并输出所有结构校验通过。

- [ ] **Step 2: 运行 diff 基本检查**

Run: `git diff --check`
Expected: exit code 0，无空白错误。

- [ ] **Step 3: 运行关键文本搜索，确认树结构落地**

Run: `rg -n "RegisterCanvasLayoutSubcategory|BuildOverviewPage|BuildAboutPage|ResetToDefaultsAndRebuild|OnEnabledSettingChanged|OnDebugSettingChanged" Toolbox`
Expected: 能看到宿主与模块均已接入新的公共设置契约。

- [ ] **Step 4: 记录仍需游戏内手工验证的项目**

至少列出：

- 设置树中的实际显示顺序
- ESC 菜单按钮跳转到总览页
- `DungeonRaidDirectory` 快照滚动区高度
- `ej_mount_filter` 在目录未就绪时的依赖提示与按钮可用态

---

Plan complete and saved to `docs/superpowers/plans/2026-04-04-settings-subcategories-and-about.md`. Ready to execute?
