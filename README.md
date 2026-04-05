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

- **窗口拖动（mover）**：其它插件可通过 `Toolbox.Mover.RegisterFrame` 接入；本插件可选拖动暴雪顶层窗口（`ShowUIPanel` 路径 + 标题栏，接近 BlizzMove）；内置名单见 `Modules/Mover.lua` 中 `PANEL_KEYS`。旧「微型菜单面板」设置已迁移至 `modules.mover`。
- **Tooltip 位置**：默认 / 贴近鼠标 / 跟随（`TooltipAnchor` + `Core/Tooltip.lua`）。
- **聊天提示**：加载完成后在默认聊天框一行提示（可关）。
- **冒险手册**：**`/toolbox instances`**、**`/toolbox cd`**、**`/toolbox saved`** 会尝试打开冒险手册；在地下城/团队副本列表旁可勾选 **仅坐骑**（模块 `ej_mount_filter`），按手册战利品筛掉无坐骑掉落的副本。
- **入口**：ESC 游戏菜单「工具箱」、系统 **选项 → 插件 → 工具箱**、命令 **`/toolbox`**（无参数打开设置）。

## 设置

- 界面语言：设置页顶部 **自动 / 简体中文 / English**，存于 `ToolboxDB.global.locale`。
- `Toolbox` 在正式服 `Settings` 中注册为**主类目总览页**，各功能与“关于”均作为**真实子页面**显示。
- 每个功能页面统一提供：**启用开关**、**调试开关**、**清理并重建**，再加上该功能自己的专属设置区。

## 文档

| 文档 | 说明 |
|------|------|
| [docs/Toolbox-addon-design.md](docs/Toolbox-addon-design.md) | 总设计：架构、模块契约、`ToolboxDB`、能力边界 |
| [AGENTS.md](AGENTS.md) | AI / 协作者必读：行为规则、Lua 规范、领域 API、暴雪 UI 挂接 |
| [docs/AI-ONBOARDING.md](docs/AI-ONBOARDING.md) | 读档顺序、文档分层、最小信息包模板 |
| [docs/specs/](docs/specs/) | 按需求归档的短期规格 |

源码目录：`Toolbox/Core`（含 **Locales.lua** `enUS` / `zhCN`）、`Toolbox/UI`、`Toolbox/Modules`。玩家可见字符串集中在 `Locales.lua`，代码里用 `Toolbox.L.键名`。

## 发布

打包与发布：见 [docs/release.md](docs/release.md)。脚本 [scripts/Release.ps1](scripts/Release.ps1) —— **默认**打 zip 到 `dist/` 并**尝试**复制到正式服 `Interface\AddOns`；**仅打 zip** 用 `-SkipDeploy`。找不到游戏目录时设环境变量 `WOW_RETAIL_ADDONS` 或使用 `-AddonPath`。
