# Toolbox 功能说明

## 核心功能

### 1. 冒险指南增强（EncounterJournal）

**坐骑筛选**
- 在冒险指南副本列表中添加"仅坐骑"复选框
- 快速筛选掉落坐骑的副本
- 支持所有资料片的副本

**副本 CD 显示**
- 在副本列表中直接显示锁定信息
- 显示难度、进度、剩余重置时间
- 鼠标悬停显示详细信息：
  - 已击杀的首领列表
  - 精确的重置时间
  - 扩展状态

**技术特性**
- 事件驱动架构，无性能损耗
- 自动过滤已过期的锁定
- 支持多难度副本

### 2. Tooltip 增强

**位置优化**
- 智能定位，避免遮挡游戏界面
- 支持自定义锚点位置
- 自动调整显示位置

### 3. 聊天增强

**频道管理**
- 快速切换聊天频道
- 自定义频道快捷键
- 频道历史记录

### 4. 小地图按钮

**快速访问**
- 一键打开设置面板
- 显示模块启用状态
- 支持拖拽调整位置
- 悬停“冒险手册”菜单项时，tooltip 显示当前副本 CD 摘要（实例、难度、重置时间；团队本含进度）

## 模块化架构

### 三层架构

```
Data（数据层）
  ↓
Core API（核心 API 层）
  ↓
Modules（功能模块层）
```

**Data 层**
- 静态数据表（副本映射、掉落数据）
- 只读，不包含逻辑

**Core API 层**
- 封装 WoW 原生 API
- 提供统一的高层接口
- 命名空间：`Toolbox.EJ`、`Toolbox.Chat`、`Toolbox.Tooltip`

**Modules 层**
- 独立的功能模块
- 可单独启用/禁用
- 通过 `Toolbox.RegisterModule` 注册

## 配置系统

### 存档结构

```lua
ToolboxDB = {
  modules = {
    encounter_journal = {
      enabled = true,
      mountFilterEnabled = true,
      lockoutOverlayEnabled = true
    },
    -- 其他模块...
  }
}
```

### 设置界面

- 游戏内设置面板：`/toolbox`
- 每个模块独立的设置页
- 支持重置为默认值

## 性能优化

### 事件驱动
- 使用游戏事件触发更新
- 移除 OnUpdate 轮询
- 防抖机制避免重复刷新

### 缓存机制
- ScrollBox 缓存（5 秒 TTL）
- 减少重复查询
- 智能失效策略

### 内存管理
- 弱引用表管理 Hook
- 自动清理过期数据
- 最小化全局变量

## 开发指南

### 添加新模块

1. 在 `Toolbox/Modules/` 创建模块文件
2. 使用 `Toolbox.RegisterModule` 注册
3. 在 `Toolbox.toc` 中添加文件引用

```lua
Toolbox.RegisterModule({
  id = "my_module",
  nameKey = "MODULE_MY_MODULE",
  settingsIntroKey = "MODULE_MY_MODULE_INTRO",
  settingsOrder = 100,
  
  OnModuleLoad = function()
    -- 初始化逻辑
  end,
  
  OnModuleEnable = function()
    -- 启用逻辑
  end,
  
  RegisterSettings = function(box)
    -- 创建设置 UI
  end,
})
```

### 使用 Core API

```lua
-- 查询副本锁定
local lockouts = Toolbox.EJ.GetAllLockoutsForInstance(journalInstanceID)

-- 查询已击杀首领
local bosses = Toolbox.EJ.GetKilledBosses(journalInstanceID)

-- 检查副本是否掉落坐骑
local hasMounts = Toolbox.EJ.HasMountDrops(journalInstanceID)

-- 获取当前角色的副本锁定摘要（按剩余时间排序）
local summary = Toolbox.EJ.GetSavedInstanceLockoutSummary()

-- 构建用于 tooltip 展示的锁定行文本
local lines, overflow = Toolbox.EJ.BuildSavedInstanceLockoutTooltipLines(8)

-- 打印消息到聊天
Toolbox.Chat.PrintAddonMessage("消息内容")
```

## 本地化

### 添加新字符串

在 `Toolbox/Core/Locales.lua` 中添加：

```lua
Toolbox.L = {
  -- 英文（默认）
  MY_STRING = "My String",
  
  -- 简体中文
  ["zhCN"] = {
    MY_STRING = "我的字符串",
  },
}
```

### 使用本地化字符串

```lua
local loc = Toolbox.L or {}
print(loc.MY_STRING)
```

## 兼容性

- **WoW 版本**: 12.0+ (The War Within)
- **客户端**: 国服/美服/欧服
- **语言**: 简体中文、英文

## 已知限制

1. 副本 CD 显示依赖 `GetSavedInstanceInfo` API
2. 坐骑筛选需要静态数据表维护
3. 部分功能需要 `Blizzard_EncounterJournal` 插件加载

## 更新日志

见 [release.md](release.md)
