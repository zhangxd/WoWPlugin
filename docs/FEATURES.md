# Toolbox 可用功能

> 定位：本文件只维护插件当前已经可用、可直接使用的功能说明，面向玩家与需求方阅读。
>
> 边界：单次需求、设计方案、实施计划、测试记录、架构细节、开发接入说明与示例代码不得写入本文件；这些内容分别写入对应文档，并遵循 [DOCS-STANDARD.md](./DOCS-STANDARD.md)。
>
> 相关文档：
> 架构与模块映射见 [Toolbox-addon-design.md](./Toolbox-addon-design.md)
> 文档写作规范见 [DOCS-STANDARD.md](./DOCS-STANDARD.md)
> 冒险指南功能说明见 [features/encounter-journal-features.md](./features/encounter-journal-features.md)
> 任务模块功能说明见 [features/quest-features.md](./features/quest-features.md)
> 地图导航功能说明见 [features/navigation-features.md](./features/navigation-features.md)
> 冒险指南详细设计见 [designs/encounter-journal-design.md](./designs/encounter-journal-design.md)
> 任务模块详细设计见 [designs/quest-design.md](./designs/quest-design.md)
> 地图导航详细设计见 [designs/navigation-design.md](./designs/navigation-design.md)

## 这是什么

`Toolbox` 是一个面向魔兽世界正式服的工具箱插件，当前重点增强以下几类体验：

- 冒险指南浏览
- 独立任务浏览
- 地图导航路线规划
- Tooltip 显示位置
- 插件消息输出
- 小地图快捷入口
- 插件设置与模块开关

## 怎么打开

你可以通过以下方式使用或进入设置：

- 输入命令：`/toolbox`
- 从游戏设置面板打开插件配置
- 使用小地图按钮快速进入

## 当前可用功能

### 冒险指南增强

适用场景：想更快查看副本坐骑、锁定信息和副本入口导航时。

当前包含：

- **副本列表增强**
  支持“仅坐骑”筛选、列表行内 CD 叠加，以及悬停查看更详细的锁定信息。
- **副本详情页增强**
  在详情区显示当前难度的重置时间；详情页不再提供“仅坐骑”过滤。
- **副本入口导航**
  在副本列表条目右下角提供图钉；点击后打开入口地图并设置系统 waypoint。运行时入口缺精确副本 ID 时，会使用 DB 契约导出的静态入口数据补足。
- **外部入口联动**
  小地图飞出菜单内置“冒险手册”入口；其 tooltip 与右下角 `EJMicroButton` tooltip 都会追加当前副本锁定摘要。

详见 [features/encounter-journal-features.md](./features/encounter-journal-features.md)。

### 独立任务浏览

适用场景：想用独立界面浏览当前任务、任务线和任务详情时。

当前包含：

- **独立任务界面**
  提供单独的 `quest` 主界面，不再依赖冒险指南任务页签。
- **当前任务视图**
  在同一页里展示“最近完成”和“当前任务”两段内容。
- **任务线视图**
  按资料片和地图浏览任务线，并在主区展开对应任务列表。
- **搜索与详情联动**
  支持搜索任务线 / 任务名称；点击任务后可查看弹框详情，并输出运行时调试信息到聊天框。
- **Quest Inspector**
  在“任务”设置页下半部分的低频工具区里按 `QuestID` 查询运行时任务与任务线字段，结果文本可复制。

详见 [features/quest-features.md](./features/quest-features.md)。

### 地图导航

适用场景：希望从世界地图目标生成当前角色可用旅行路线时。

当前包含：

- **世界地图入口**
  世界地图显示时提供“规划路线”按钮，点击后读取当前地图与鼠标目标坐标。
- **当前角色能力过滤**
  路线只使用当前角色已确认可用的能力；未知技能或不满足职业 / 阵营要求的路径不会参与推荐。
- **顶部路径条**
  规划结果会显示在屏幕顶部中间，按顺序列出路线步骤。
- **多枢纽旅行图**
  支持当前地点、Taxi 公共交通候选边、部落主城公共传送门、奥格瑞玛传送门房、法师主城传送，以及死亡骑士 / 德鲁伊 / 武僧的职业位移能力。

详见 [features/navigation-features.md](./features/navigation-features.md)。

### Tooltip 增强

适用场景：默认提示框容易挡住界面，或者希望提示框跟随更稳定时。

当前包含：

- 支持自定义提示框锚点位置
- 优化提示框显示位置，尽量减少遮挡
- 支持更稳定的提示框跟随与偏移控制

### 聊天增强

适用场景：希望插件消息输出更统一、加载提示更清晰时。

当前包含：

- 插件加载完成后可在默认聊天框输出提示
- 插件消息走统一样式与前缀
- 中英文文案统一走本地化表

### 小地图按钮

适用场景：希望快速进入插件设置、冒险指南或任务界面时。

当前包含：

- 一键打开插件设置
- 支持拖拽调整按钮位置
- 悬停可查看扩展功能项
- 内置“冒险手册”入口，可直接打开冒险指南
- 内置“任务”入口，可直接打开独立任务界面
- 悬停“冒险手册”相关入口时，可查看当前副本 CD 摘要

### 设置与模块开关

适用场景：希望按需启用、关闭或调整各项功能时。

当前包含：

- 设置左侧树固定为 `通用`、`界面`、`地图`、`任务`、`冒险手册`、`关于` 6 个叶子页
- 支持公共启用/禁用开关
- 支持恢复默认值或重建相关配置
- Quest Inspector 已并回“任务”页，不再单独占一条左侧设置入口

## 适用环境

- **WoW 版本**：12.0+（The War Within）
- **客户端**：国服 / 美服 / 欧服
- **语言**：简体中文、英文

## 当前限制

- 副本 CD 显示依赖游戏原生 `GetSavedInstanceInfo` API
- 坐骑筛选依赖静态数据表维护
- 任务浏览依赖 `Toolbox.Data.InstanceQuestlines` 与运行时任务 API 聚合结果
- 地图导航第一版已覆盖部分高频传送门、Taxi 公共交通候选边与职业位移，但玩具、炉石、节日传送和全职业特殊交通仍需继续扩充
- 部分功能需要 `Blizzard_EncounterJournal` 插件已加载

## 更新日志

详见 [release.md](./release.md)
