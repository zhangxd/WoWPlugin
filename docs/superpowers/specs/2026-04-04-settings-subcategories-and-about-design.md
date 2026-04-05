# 设置树子页面化与关于页重构设计

**日期**：2026-04-04  
**状态**：已确认，可进入实现。  
**范围**：将当前单页 `Toolbox` 设置界面重构为“主类目总览页 + 真实子项页面”，为每个功能提供独立设置页面、统一的启用/调试/清理并重建公共区，并新增“关于”页面。

---

## 1. 已确认决策

本需求已由需求方明确以下方向：

1. `Toolbox` 设置应改为**主类目下每个功能一个真实子项**，而非单页内折叠分区。
2. **每个功能页面**都要提供：
   - 独立启用开关
   - 独立调试开关
   - 独立“清理并重建”入口
3. “清理并重建”的统一语义：
   - 普通模块：将 `ToolboxDB.modules.<moduleId>` 重置为默认值，并立刻重新应用当前模块状态；
   - 缓存型功能：在重置自身模块存档后，再执行真实重建。
4. `地下城 / 团队副本目录` 需要作为**单独子页面**存在，不并入 `ej_mount_filter` 页面。
5. 本轮由 AI **自主定稿并开发**，无需等待在线确认。

---

## 2. 目标与非目标

### 2.1 目标

- 让正式服 `Settings` 左侧树中出现清晰的 `Toolbox` 主类目与多个子页面。
- 将每个功能的公共设置行为统一为相同骨架，减少重复 UI 代码。
- 把目前 `SettingsHost` 中对 `DungeonRaidDirectory` 的特判区块收拢回模块化模型。
- 新增“关于”页，用于承载简介、版本、命令与支持说明。
- 允许后续新增模块时，以一致方式注册自己的子页面，而不再继续扩张总页。

### 2.2 非目标

- 本轮**不**改成按分组折叠的单页设置模型；此前 `settingsGroupId` 相关设计转为兼容遗留信息。
- 本轮**不**改变各功能的核心业务目标，例如 tooltip 锚点算法、微型菜单面板白名单策略、`ej_mount_filter` 的过滤规则。
- 本轮**不**引入新的配置型子系统（如通用表单库、事件总线）。

---

## 3. 信息架构

设置树目标结构如下：

```text
Toolbox
├─ 总览
├─ 聊天提示
├─ 窗口拖动
├─ 微型菜单面板
├─ 提示框位置
├─ 地下城 / 团队副本目录
├─ 冒险指南：仅坐骑筛选
└─ 关于
```

其中：

- **Toolbox 主类目页**：作为“总览”页存在；`/toolbox` 与 ESC 菜单按钮默认打开此页。
- **功能子页**：每个功能一页，负责该功能的公共区与专属设置区。
- **关于页**：非功能页，不含业务开关，用于提供说明性内容。

---

## 4. 页面职责

### 4.1 主类目总览页

主类目页保留为轻量总览，不再承载所有模块设置控件，仅显示：

- 插件简介
- 当前版本
- 支持客户端（Retail）
- 入口提示（ESC、`/toolbox`、设置树左侧子页）
- 各功能页的简短说明

### 4.2 功能子页统一骨架

所有功能子页使用统一顺序：

1. 页面标题
2. 功能简介
3. 启用开关
4. 调试开关
5. 清理并重建按钮
6. 功能专属设置区
7. 状态/提示/说明区

### 4.3 关于页

“关于”页建议承载：

- 插件名称与简介
- 版本号（来自 TOC metadata）
- 支持客户端与设置 API 说明
- 常用命令（`/toolbox`、`/toolbox instances`、`/toolbox mmadd`）
- 文档入口提示（README / 总设计 / AI-ONBOARDING）

---

## 5. 数据契约

### 5.1 模块公共键

每个设置页型功能模块统一拥有以下公共键：

```lua
ToolboxDB.modules.<moduleId> = {
  enabled = true or false,
  debug = true or false,
  -- 其余字段由该模块自己定义
}
```

要求：

- `enabled`：功能总开关；页面公共区统一读取。
- `debug`：该功能的调试开关；页面公共区统一读取。
- 模块专属数据继续放在同一模块子表下，不拆到其它位置。

### 5.2 各模块目标形状

```lua
modules = {
  chat_notify = {
    enabled = true,
    debug = false,
  },
  mover = {
    enabled = true,
    debug = false,
    demoVisible = true,
    frames = {},
  },
  micromenu_panels = {
    enabled = true,
    debug = false,
    frames = {},
    extraFrameNames = {},
  },
  tooltip_anchor = {
    enabled = true,
    debug = false,
    mode = "cursor",
    offsetX = 0,
    offsetY = 0,
  },
  dungeon_raid_directory = {
    enabled = true,
    debug = false,
  },
  ej_mount_filter = {
    enabled = false,
    debug = false,
  },
}
```

### 5.3 共享目录缓存仍留在 `global`

`DungeonRaidDirectory` 的缓存数据与运行状态依旧由领域对外 API 持有：

```lua
ToolboxDB.global.dungeonRaidDirectory = {
  schemaVersion = 1,
  interfaceBuild = 0,
  lastBuildAt = 0,
  tierNames = {},
  difficultyMeta = {},
  records = {},
}
```

理由：

- 该缓存既供目录页自身使用，也供 `ej_mount_filter` 消费；
- 它是共享领域数据，不应挪入某个普通模块的 `modules.*` 私有表；
- 设置页型模块 `dungeon_raid_directory` 仅负责配置入口与生命周期，不拥有缓存主数据。

### 5.4 迁移规则

本轮需要在 `Core/DB.lua` 中做以下迁移：

1. `modules.ej_mount_filter.debugChat` → `modules.ej_mount_filter.debug`
2. `global.dungeonRaidDirectoryDebugChat` → `modules.dungeon_raid_directory.debug`
3. 为已有模块补默认 `debug = false`
4. 旧的 `global.settingsGroupsExpanded` 保留但不再被设置 UI 使用

---

## 6. 模块契约扩展

保留 `RegisterModule(def)` 模型，但将设置页相关契约扩展为以下字段：

| 字段 | 说明 |
|------|------|
| `id` | 稳定模块 id |
| `nameKey` | 页面标题 Locales 键 |
| `settingsIntroKey` | 页面简介 Locales 键 |
| `settingsOrder` | 设置树中子页面顺序 |
| `RegisterSettings(box)` | 仅渲染“专属设置区”，不再重复画公共区 |
| `OnModuleLoad` | 不依赖角色数据的初始化 |
| `OnModuleEnable` | `PLAYER_LOGIN` 后启用 |
| `OnEnabledSettingChanged(enabled)` | 公共启用开关变更后立即重应用 |
| `OnDebugSettingChanged(enabled)` | 公共调试开关变更后同步内部状态 |
| `ResetToDefaultsAndRebuild()` | 公共“清理并重建”按钮入口 |

### 6.1 新增轻量模块 `dungeon_raid_directory`

新增 `Modules/DungeonRaidDirectory.lua`，职责为：

- 注册设置页型功能模块
- 提供 `enabled/debug` 模块存档
- 代理调用 `Toolbox.DungeonRaidDirectory` 的启停、重建、调试开关与状态读取
- 渲染目录专属设置区（状态、进度、重建、快照）

核心领域 API `Core/DungeonRaidDirectory.lua` 继续保留，**不**迁移为业务模块。

---

## 7. 页面运行时行为

### 7.1 启用开关

- 页面公共区修改 `db.enabled`
- 若模块实现 `OnEnabledSettingChanged`，宿主立即调用
- 模块必须在该回调内完成“立刻应用当前状态”的工作，而不是要求用户 `/reload`

### 7.2 调试开关

- 页面公共区修改 `db.debug`
- 若模块实现 `OnDebugSettingChanged`，宿主立即调用
- 各模块可自行决定调试输出去向，但统一由 `debug` 控制

### 7.3 清理并重建

统一入口为 `ResetToDefaultsAndRebuild()`，具体行为如下：

- `chat_notify`：重置该模块存档到默认值
- `mover`：清空 `frames` 与演示状态，并重新应用示例窗
- `micromenu_panels`：清空 `frames`/`extraFrameNames`，重新安装 hooks
- `tooltip_anchor`：恢复默认锚点模式与偏移并刷新驱动
- `dungeon_raid_directory`：清空目录缓存与运行时状态后重新构建
- `ej_mount_filter`：重置模块存档与运行时会话状态，重新同步冒险手册挂件

### 7.4 依赖行为

`ej_mount_filter` 子页需要显式展示与目录页的依赖关系：

- 若 `modules.dungeon_raid_directory.enabled ~= true`，则提示“目录功能已关闭，筛选不可用”
- 若目录构建未就绪，则显示“等待目录构建完成”
- 模块页面仍保留自己的启用、调试、重建公共区

---

## 8. SettingsHost 重构方式

### 8.1 从单页构建改为分类注册器

`UI/SettingsHost.lua` 需要从现有“单页滚动拼装”改为：

- 创建主类目总览页
- 为每个设置页型模块创建一个独立 Canvas 页面
- 将这些页面注册为 `Toolbox` 下的真实子类目
- 单独创建 `关于` 页

### 8.2 宿主负责公共区

设置宿主新增一组通用构建函数：

- 构建简介
- 构建启用开关
- 构建调试开关
- 构建清理并重建按钮
- 包裹模块 `RegisterSettings(box)` 的专属区

`SettingsHost` 不再内嵌 `BuildDungeonRaidDirectorySection()` 这类只服务于某个功能的特化函数；这类 UI 收敛到对应模块文件。

### 8.3 旧分组设计的处置

当前 `settingsGroupId` 与折叠分组设计不再作为主渲染路径，但可暂时保留字段本身，以免一次性大删文档与旧注释造成额外噪音。后续总设计中应改写为“历史设计，不再是当前设置页主结构”。

---

## 9. 文案要求

需在 `Core/Locales.lua` 中新增或调整以下类文案：

- 总览页标题与简介
- 每个功能页简介
- 公共区文案：
  - 启用
  - 调试
  - 清理并重建
  - 重建说明
  - 成功/失败提示
- 关于页文案
- 目录页与 `ej_mount_filter` 依赖提示

所有玩家可见文字继续集中在 `Toolbox.L`，禁止在模块内硬编码。

---

## 10. 验收

### 10.1 结构验收

- `Toolbox` 主类目在正式服设置树中可见
- 左侧树出现所有功能子项与“关于”子项
- `/toolbox` 与 ESC 菜单按钮能打开 `Toolbox` 总览页

### 10.2 页面验收

- 每个功能页都能看到简介、启用、调试、清理并重建、专属设置
- `地下城 / 团队副本目录` 为独立子页，不再出现在总览页
- “关于”页展示版本、命令与简介

### 10.3 行为验收

- 切换启用开关后，对应功能立刻重应用
- 切换调试开关后，对应功能立刻切换调试状态
- 点击“清理并重建”后，对应模块回到默认值并重新应用
- `ej_mount_filter` 能正确展示对目录页的依赖提示

### 10.4 文档验收

- `docs/Toolbox-addon-design.md` 中设置结构、模块映射、数据模型同步更新
- `README.md` 中设置说明同步为“子页面”模型

---

## 11. 影响文件

预期修改范围：

- `Toolbox/Core/DB.lua`
- `Toolbox/Core/Locales.lua`
- `Toolbox/Core/ModuleRegistry.lua`
- `Toolbox/Core/Bootstrap.lua`
- `Toolbox/UI/SettingsHost.lua`
- `Toolbox/Modules/ChatNotify.lua`
- `Toolbox/Modules/Mover.lua`
- `Toolbox/Modules/MicroMenuPanels.lua`
- `Toolbox/Modules/TooltipAnchor.lua`
- `Toolbox/Modules/EJMountFilter.lua`
- `Toolbox/Modules/DungeonRaidDirectory.lua`（新增）
- `Toolbox/Toolbox.toc`
- `README.md`
- `docs/Toolbox-addon-design.md`

---

## 12. 实现备注

- 由于当前仓库无现成 Lua 自动化测试框架，本轮实现需补最小静态校验脚本，用于对设置树注册形状、模块公共契约与关键文案键做回归检查。
- 该校验脚本仅作为本仓库当前阶段的最小测试闭环，不替代游戏内手工验证。
