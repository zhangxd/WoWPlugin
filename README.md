# WoWPlugin（工具箱）

魔兽世界 **正式服（Retail）** 插件工程：统一入口、可扩展模块（`RegisterModule`）。

## 安装

将 [Toolbox](Toolbox) 文件夹复制到  
`_retail_\Interface\AddOns\Toolbox\`  
（与 `Toolbox.toc` 同级），游戏中启用 **Toolbox**。

### 若插件列表里显示「不兼容 / 过期」

这是 **`Toolbox.toc` 第一行 `## Interface:`** 与当前游戏 **TOC 接口版本**不一致导致的（大版本更新后很常见）。

1. **在游戏里**（任意角色）聊天框输入并回车：  
   `/run print(select(4, GetBuildInfo()))`  
   记下输出的**整数**（例如 `120000`）。
2. 用记事本打开 `Toolbox\Toolbox.toc`，把第一行改成：  
   `## Interface: 你记下的整数`  
3. 保存后 **`/reload`** 或重开游戏。

仓库里默认的 `## Interface:` 可能与你的客户端不完全一致，**一律以本条命令打印出的整数为准**修改 `Toolbox.toc` 第一行。

## 功能概览

- **窗口拖动**：本插件创建的窗口可拖、位置存 `ToolboxDB`；示例面板用于测试。
- **微型菜单面板**：白名单内从微型菜单打开的主界面可拖（见 `Modules/MicroMenuPanels.lua`）；可用 **`/toolbox mmadd <框架名>`** 追加顶层名。
- **Tooltip 位置**：默认 / 贴近鼠标 / 跟随（`TooltipAnchor` + `Core/Tooltip.lua`）。
- **聊天提示**：加载完成后在默认聊天框一行提示（可关）。
- **冒险手册**：**`/toolbox instances`**、**`/toolbox cd`**、**`/toolbox saved`** 会尝试打开冒险手册；资料片列表旁「仅坐骑」等挂接见 `Modules/SavedInstancesEJ.lua`（绑定暴雪 UI 生命周期，非独立副本进度面板模块）。
- **入口**：ESC 游戏菜单「工具箱」、系统 **选项 → 插件 → 工具箱**、命令 **`/toolbox`**（无参数打开设置）。

## 设置

- 界面语言：设置页顶部 **自动 / 简体中文 / English**，存于 `ToolboxDB.global.locale`。
- 各功能模块选项按 **分组** 折叠展示（`settingsGroupId`）；展开状态存 `ToolboxDB.global.settingsGroupsExpanded`。详见 [docs/Toolbox-addon-design.md](docs/Toolbox-addon-design.md)。

## 文档

| 文档 | 说明 |
|------|------|
| [AGENTS.md](AGENTS.md) | AI/协作者入口：Lua 规范、领域门面、暴雪 UI 挂接；文首含 **模糊需求时的检查清单（摘要）** |
| [docs/Toolbox-addon-design.md](docs/Toolbox-addon-design.md) | 总设计：架构、模块契约、`ToolboxDB`、能力边界 |
| [docs/AI-ONBOARDING.md](docs/AI-ONBOARDING.md) | 读档顺序、协作约定、**§1.2 含糊需求时的 AI 建议执行路径**、最小信息包 |
| [docs/specs/](docs/specs/) | 按需求归档的短期规格（如协作节奏、设置分组等） |

源码目录：`Toolbox/Core`（含 **Locales.lua** `enUS` / `zhCN`）、`Toolbox/UI`、`Toolbox/Modules`。玩家可见字符串集中在 `Locales.lua`，代码里用 `Toolbox.L.键名`。

## 发布

打包与发布：见 [docs/release.md](docs/release.md)。脚本 [scripts/Release.ps1](scripts/Release.ps1) —— **默认**打 zip 到 `dist/` 并**尝试**复制到正式服 `Interface\AddOns`；**仅打 zip** 用 `-SkipDeploy`。找不到游戏目录时设环境变量 `WOW_RETAIL_ADDONS` 或使用 `-AddonPath`。
