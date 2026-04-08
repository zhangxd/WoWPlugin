# Toolbox - 魔兽世界工具箱插件

魔兽世界**正式服（Retail）**可扩展插件框架，提供窗口拖动、提示框定位、冒险手册增强等实用功能。

## 特性

- **模块化架构**：基于 `RegisterModule` 的可扩展设计，易于添加新功能
- **统一设置界面**：集成到暴雪原生设置系统，支持中英文切换
- **窗口拖动**：支持拖动暴雪原生窗口（类似 BlizzMove）
- **提示框定位**：可选默认/贴近鼠标/跟随模式
- **冒险手册增强**：副本 CD 显示、仅坐骑筛选、快捷命令
- **小地图按钮**：快速访问设置和功能；冒险手册悬停项可直接预览当前副本 CD

## 安装

1. 下载或克隆本仓库
2. 将 `Toolbox` 文件夹复制到 `_retail_\Interface\AddOns\`
3. 启动游戏，在插件列表中启用 **Toolbox**

### TOC 版本兼容性

如果插件显示「不兼容/过期」：

```lua
-- 游戏内执行，获取当前 TOC 版本
/run print(select(4, GetBuildInfo()))
```

修改 `Toolbox.toc` 第一行 `## Interface:` 为输出的数字，然后 `/reload`。

## 使用

### 命令

- `/toolbox` - 打开设置界面
- `/toolbox instances` - 打开冒险手册副本列表
- `/toolbox cd` - 打开冒险手册并显示副本 CD
- `/toolbox saved` - 打开冒险手册已保存副本

### 设置入口

- ESC 菜单 → 工具箱
- 系统设置 → 插件 → 工具箱
- 小地图按钮（右键菜单）

### 小地图悬停菜单（含副本 CD 预览）

- 将鼠标移到小地图按钮可展开悬停菜单
- 悬停“冒险手册”项时，tooltip 会显示当前角色的副本锁定摘要（副本名、难度、剩余时间；团队本含进度）
- 条目过多时会显示“还有 N 条未显示”

## 架构

```
Toolbox/
├── Core/
│   ├── Foundation/     # 基础设施（命名空间、本地化、存档、模块注册、启动）
│   └── API/           # 领域对外 API（聊天、提示框、锁定、冒险手册等）
├── UI/                # 表现层（设置界面）
├── Modules/           # 功能模块（Mover、TooltipAnchor、EncounterJournal 等）
├── Data/              # 静态数据（副本 ID 映射、坐骑掉落表）
└── Debug/             # 调试工具

Toolbox.toc            # 插件清单
```

### 核心概念

- **Foundation**：插件生命周期、SavedVariables 管理、模块注册系统
- **API**：稳定的领域接口，封装暴雪 API，供模块调用
- **Modules**：独立功能单元，通过 `Toolbox.RegisterModule` 注册
- **ToolboxDB**：统一存档结构，支持版本迁移

## 开发

### 文档

| 文档 | 说明 |
|------|------|
| [docs/Toolbox-addon-design.md](docs/Toolbox-addon-design.md) | 架构设计、模块契约、数据约定 |
| [AGENTS.md](AGENTS.md) | AI 协作规范、Lua 开发规范、暴雪 UI 挂接时机 |
| [docs/AI-ONBOARDING.md](docs/AI-ONBOARDING.md) | 文档读取顺序、协作流程 |
| [CLAUDE.md](CLAUDE.md) | Claude AI 协作快速参考 |

### 添加新模块

```lua
Toolbox.RegisterModule({
  id = “my_module”,              -- 模块唯一标识
  nameKey = “MY_MODULE_NAME”,    -- 本地化键名
  descKey = “MY_MODULE_DESC”,    -- 描述键名
  OnModuleLoad = function(db)    -- 模块加载回调
    -- 初始化逻辑
  end,
  OnModuleEnable = function(db)  -- 模块启用回调
    -- 启用逻辑
  end,
  RegisterSettings = function(category, db)  -- 注册设置
    -- 设置界面
  end
})
```

### 本地化

在 `Core/Foundation/Locales.lua` 添加键值对：

```lua
L.MY_MODULE_NAME = “我的模块”
L.MY_MODULE_DESC = “模块描述”
```

代码中使用 `Toolbox.L.MY_MODULE_NAME` 引用。

### 调试

Debug 目录提供调试工具：

- `DumpSavedInstances.lua` - 转储副本锁定数据
- `TestEJReverseLookup.lua` - 测试冒险手册 API
- `TestMapIDMatch.lua` - 测试副本 ID 映射
- `ParseInstanceID.lua` - 解析实例 ID

游戏内执行对应函数（如 `/run DumpAllSavedInstances()`）。

## 发布

使用 Python 脚本打包（跨平台）：

```bash
# 打包并部署到游戏目录
python scripts/release.py

# 仅打包到 dist/ 目录
python scripts/release.py --skip-deploy

# 指定游戏目录
python scripts/release.py --addon-path “<游戏安装路径>/_retail_/Interface/AddOns”

# 显示路径查找过程
python scripts/release.py --show-search
```

Windows 用户也可使用 PowerShell 脚本：

```powershell
.\scripts\Release.ps1
.\scripts\Release.ps1 -SkipDeploy
.\scripts\Release.ps1 -AddonPath “<游戏安装路径>\_retail_\Interface\AddOns”
```

详见 [docs/release.md](docs/release.md)。

## 协作规范

本项目主要通过 AI 协作开发，遵循严格的三关检查流程：

1. **关 1**：需求是否明确（模块 id、验收标准、边界）
2. **关 2**：数据来源/主方案是否选定
3. **关 3**：新功能门禁（新模块、新入口需评估）

详见 [AGENTS.md](AGENTS.md) 和 [CLAUDE.md](CLAUDE.md)。

## 许可

本项目仅供学习交流使用。
