# WoWPlugin（工具箱）

魔兽世界 **正式服（Retail）** 插件工程：统一入口、可扩展模块。

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

- **窗口拖动**：示例面板可拖；存档在 `ToolboxDB`。
- **微型菜单面板**：白名单内暴雪主界面可拖（见 `Modules/MicroMenuPanels.lua`）。
- **Tooltip 位置**：默认 / 贴近鼠标 / 跟随鼠标。
- **聊天提示**：加载完成后默认聊天框一行提示（**聊天提示**模块，可关）。
- **副本进度**：锁定列表、首领、坐骑与掉落节选（`C_EncounterJournal`）；**`/toolbox instances`** 或 **`/toolbox cd`** 打开面板。
- **入口**：ESC 游戏菜单「工具箱」、系统 **选项 → 插件 → 工具箱**、命令 **`/toolbox`**。

## 文档

| 文档 | 说明 |
|------|------|
| [AGENTS.md](AGENTS.md) | AI/协作者入口（含 **代码须含注释** 等约束） |
| [docs/Toolbox-addon-design.md](docs/Toolbox-addon-design.md) | 总设计 |
| [docs/AI-ONBOARDING.md](docs/AI-ONBOARDING.md) | 读档与协作约定 |

源码目录：`Toolbox/Core`（含 **Locales.lua** 多语言）、`Toolbox/UI`、`Toolbox/Modules`。界面文案在 `Locales.lua` 的 `enUS` / `zhCN` 中维护。**设置页顶部**可选「自动 / 简体中文 / English」，存于 `ToolboxDB.global.locale`；选「自动」时按游戏客户端语言选用文案。

## 发布

打包与发布：见 [docs/release.md](docs/release.md)。脚本 [scripts/Release.ps1](scripts/Release.ps1) —— **默认**打 zip 到 `dist/` 并**尝试**复制到正式服 `Interface\AddOns`；**仅打 zip** 用 `-SkipDeploy`。找不到游戏目录时设环境变量 `WOW_RETAIL_ADDONS` 或使用 `-AddonPath`。
