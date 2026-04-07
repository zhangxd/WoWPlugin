# 版本发布记录

## v1.0.0 (2026-04-08)

### 首个正式版本

**核心功能**
- ✅ 冒险指南增强（坐骑筛选 + 副本 CD 显示）
- ✅ Tooltip 位置优化
- ✅ 聊天频道管理
- ✅ 小地图按钮快速访问
- ✅ 模块化架构，支持独立启用/禁用

**技术特性**
- 三层架构（Data → Core API → Modules）
- 事件驱动，无性能损耗
- 完整的本地化支持（简体中文/英文）
- 游戏内设置面板

**兼容性**
- WoW 版本：12.0+ (The War Within)
- 客户端：国服/美服/欧服

---

# 发布规划（Toolbox）

## 目标

- **产物**：单个 zip，解压到 `_retail_\Interface\AddOns\` 后目录为 `AddOns\Toolbox\`，且内含 `Toolbox.toc`（与战网/单体分发习惯一致）。
- **版本**：与 `Toolbox/Toolbox.toc` 中 `## Version:` 一致；发版前人工或脚本确认。
- **范围**：仅打包 **`Toolbox/`** 插件目录；仓库根部的 `docs/`、`AGENTS.md` 等**不**打入 zip（减小体积、避免无关文件进 AddOns）。

## 流程（建议）

1. **自测**：游戏内加载、设置页、`/toolbox`、各模块开关。
2. **改版本号**：编辑 `Toolbox/Toolbox.toc` 的 `## Version:`（必要时同步 `## Interface:`）。
3. **执行脚本**：在仓库根目录运行 `scripts\Release.ps1`（见下）。**默认会尝试复制到本机正式服 AddOns**；若未找到游戏目录会提示，可设环境变量 `WOW_RETAIL_ADDONS` 或使用 `-AddonPath`。仅打 zip、不上传本机游戏目录时用 **`-SkipDeploy`**。
4. **分发**：将 `dist/Toolbox-<版本>.zip` 上传 CurseForge / Wago / 网盘等；说明中写清 **正式服** 与 Interface 号。

## 脚本说明

| 项 | 说明 |
|----|------|
| 位置 | [scripts/Release.ps1](../scripts/Release.ps1) |
| 依赖 | Windows PowerShell 5.1+（自带 `Compress-Archive`） |
| 输出 | `dist/Toolbox-<Version>.zip` |
| 根目录 | zip 内顶层文件夹名为 `Toolbox`，符合 WoW 插件目录约定 |

### 用法

```powershell
cd d:\WoWPlugin
.\scripts\Release.ps1
```

默认即会尝试复制到本机正式服 AddOns（自动查找路径）。仅打 zip、不复制：

```powershell
.\scripts\Release.ps1 -SkipDeploy
```

仅快速覆盖游戏目录、不打 zip：

```powershell
.\scripts\Release.ps1 -SkipZip
```

指定 AddOns 路径（自动查找失败时）：

```powershell
.\scripts\Release.ps1 -AddonPath "<你的路径>\_retail_\Interface\AddOns"
```

**自动查找顺序**：环境变量 `WOW_RETAIL_ADDONS` → 注册表 `InstallPath`（若已指向 `_retail_` 则拼 `Interface\AddOns`）→ `Program Files` 下常见路径。

可在「用户环境变量」中设置 `WOW_RETAIL_ADDONS`，避免换机后找不到。

可选参数：

- `-OutputDir <路径>`：zip 输出目录，默认 `dist`。
- `-NoClean`：不删除同版本旧 zip。
- `-AddonPath`：手动指定 `...\Interface\AddOns`。
- `-SkipZip`：只复制，不打 zip。
- `-SkipDeploy`：只打 zip，不复制到游戏目录。

## 发布前检查清单

- [ ] `Toolbox.toc` 中 `## Version:`、`## Interface:` 已更新。
- [ ] 无仅开发用调试代码（如永久 `print`）留在默认路径。
- [ ] 新模块已列入 TOC 加载顺序。

## 为什么脚本会「找不到正式服 Interface\AddOns」？

脚本**不会**全盘搜索，只在下面几类位置探测；任一不满足就会失败：

| 原因 | 说明 |
|------|------|
| **本机没装正式服** | 只装了怀旧服时，路径是 `_classic_` 等，不是 `_retail_\Interface\AddOns`。 |
| **安装位置不在默认列表** | 脚本仅探测环境变量、注册表及常见标准路径。若安装位置特殊，请使用环境变量 `WOW_RETAIL_ADDONS` 或 `-AddonPath` 参数手动指定。 |
| **注册表没有 InstallPath** | 部分拷贝客户端、绿色版或从未用战网安装，可能没有暴雪标准注册表项。 |
| **路径存在但拼错** | 必须是**已存在**的文件夹，且路径以 `\AddOns` 结尾（大小写不敏感）。 |

**排查**：运行 `.\scripts\Release.ps1 -ShowAddonSearch -SkipDeploy`，看带 `[AddOns]` 前缀的尝试路径；再对照资源管理器里真实的 `_retail_\Interface\AddOns`，用 **`-AddonPath`** 或环境变量 **WOW_RETAIL_ADDONS** 写死。

## 后续可扩展（非必须）

- CI（GitHub Actions）在 tag 时自动跑 `Release.ps1` 并上传 Artifacts。
- 从 git tag 推导版本号写入 TOC（需约定流程，避免与手工不一致）。
