# 冒险指南需求规格

- 文档类型：需求
- 状态：可执行
- 主题：encounter-journal
- 适用范围：`encounter_journal` 当前副本列表、详情页、锁定摘要与副本列表入口导航增强
- 关联模块：`encounter_journal`、`minimap_button`
- 关联文档：
  - `docs/features/encounter-journal-features.md`
  - `docs/designs/encounter-journal-design.md`
  - `docs/tests/encounter-journal-test.md`
  - `docs/specs/quest-spec.md`
- 最后更新：2026-05-01

## 1. 背景

- `encounter_journal` 相关文档长期沿用了“任务页签仍挂在冒险指南里”的旧表述，但当前代码已经把任务浏览和 Quest Inspector 拆到了独立 `quest` 模块。
- 需要一份只描述当前 `encounter_journal` 真实边界的需求基线，作为后续继续演进副本列表和详情页增强时的验收对照。
- 2026-04-27 用户确认新增“副本列表入口导航”，并在后续反馈中修正落点：图钉按钮应显示在冒险指南地下城 / 团队副本列表条目的右下角，而不是副本详情页；点击后打开世界地图到该副本入口并设置系统导航目标。
- 2026-04-27 用户继续确认列表图钉增强：图钉替换为更高辨识度的高亮版，并新增“定位图标常驻显示”设置。未勾选时，图钉默认隐藏，鼠标悬停到可导航列表行时显示；勾选后所有可导航条目常驻显示。
- 2026-04-27 用户反馈 `厄运之槌 - 戈多克议会` 的运行时入口 API 无精确返回；经只读调查确认 `areapoi` / `C_EncounterJournal.GetDungeonEntrancesForMap` 只返回聚合入口 `230`，而 `journalinstanceentrance` 在 DB 中保留 `1276 / 1277` 的精确世界坐标。用户确认新增 DB 导出的静态副本入口数据，运行时在选中 / 点击副本图钉时按 `journalInstanceID` 读取静态表补足缺口。
- 2026-04-29 用户继续确认 `encounter_journal` 设置精简：设置页中删除“在冒险指南中筛选坐骑”“在冒险指南中显示副本CD”“仅坐骑”3 个选项，并要求不要残留对应存档键、迁移或设置分支。
- 2026-04-29 用户同时确认保留副本列表里的“仅坐骑”按钮与功能，且该按钮状态仍需记忆到下次打开；详情页“仅坐骑”按钮与功能则一并移除。
- 2026-05-01 只读审查确认：`斯坦索姆 - 仆从入口`（`journalInstanceID = 1292`）在源库中存在 `journalinstanceentrance` 行，但因 `MapID = 0` 且无精确 `areapoi`，会被当前 `instance_entrances` / `navigation_instance_entrances` 契约过滤掉；若运行时 API 继续把共享入口归并到 `236`，则现有按精确 `journalInstanceID` 的运行时兜底也会 miss。
- 2026-05-01 用户确认下一阶段主方案：从根本上把副本入口运行时消费收口到单一导出的规范化入口目标表；归并、坐标补全与冲突校验全部前移到导出层，运行时不再对 `1292` 这类条目做兜底、特判或共享入口猜测。

## 2. 目标

- 明确 `encounter_journal` 当前已经交付的能力范围。
- 明确哪些入口虽然通过其它模块呈现，但仍属于冒险指南增强能力链路。
- 明确任务相关能力已不再属于本主题，避免后续文档再次漂移。
- 在不新增独立模块的前提下，为当前副本详情页提供一键导航到副本入口的能力。
- 收口 `encounter_journal` 设置页，只保留仍然需要玩家配置的项，并删除已不再需要的 3 个设置项与其残留代码。
- 从导出层根治旧副本分入口缺失问题，让 `1292` 这类共享物理入口的 `journalInstanceID` 也能直接命中可导航目标。
- 将副本入口运行时消费收口为单一规范化导出表，移除业务层对多张入口表和运行时入口 API 的级联兜底依赖。

## 3. 范围

### 3.1 In Scope

- 地下城 / 团队副本列表“仅坐骑”筛选。
- 副本列表锁定信息叠加与悬停详情。
- 副本详情页当前难度重置标签。
- 小地图“冒险手册”入口的锁定摘要联动。
- `EJMicroButton` tooltip 锁定摘要联动。
- 副本 / 地下城列表条目右下角图钉按钮：打开目标地图并设置系统用户导航点。
- 副本 / 地下城列表条目的进入详情页交互兼容，以及图钉悬停显示与常驻显示设置。
- 删除设置页里的“在冒险指南中筛选坐骑”“在冒险指南中显示副本CD”“仅坐骑”3 个选项。
- 保留副本列表“仅坐骑”按钮与功能，并继续使用账号级存档记忆上次开关状态。
- 删除 `lockoutOverlayEnabled`、`detailMountOnlyEnabled` 对应的默认值、迁移、读写与判断分支；列表 CD 叠加固定开启。
- 删除副本详情页“仅坐骑”按钮与过滤功能，仅保留详情页重置标签。
- 副本入口导出层的“物理入口簇 -> 每个 `journalInstanceID` 的规范化导航目标”归一化。
- 入口数据契约与自动化校验新增 `236 / 1292` 共享入口回归样本。
- `Toolbox.EJ` 的入口查找链路收口为单一导出表直读，不再依赖运行时入口 API 兜底。

### 3.2 Out of Scope

- 独立任务界面。
- 任务线浏览、任务搜索、任务详情弹框。
- Quest Inspector 设置子页面。
- “任务”小地图入口。
- Tooltip 锚点、窗口拖动、聊天 API 等与冒险指南无关的模块能力。
- 副本内部 boss、楼层、门、传送点或路径规划坐标。
- 手写静态入口坐标表；入口静态数据必须从 `wow.db` 通过契约导出生成。
- 删除副本列表里的“仅坐骑”按钮或其记忆状态。
- 删除列表 CD 叠加、悬停锁定详情、详情页重置标签、入口导航或图钉显示设置。
- 在业务代码里为 `1292`、`236` 或其它单个旧副本 ID 写死特判。
- 手工维护副本入口映射表或在 Lua 中补写静态坐标。
- 继续保留“静态入口表 -> 导航入口表 -> 运行时入口 API”的三级运行时兜底链路。

## 4. 已确认决策

- 主归属模块为 `encounter_journal`。
- 小地图“冒险手册”入口由 `minimap_button` 呈现，但其锁定摘要仍计入 `encounter_journal` 能力范围。
- 锁定与坐骑掉落相关数据统一由 `Toolbox.EJ` 提供。
- `encounter_journal` 当前只保留副本列表、详情页和锁定摘要相关逻辑；任务能力已经迁移到 `quest` 模块。
- `ToolboxDB.modules.encounter_journal.mountFilterEnabled` 继续保留，但只用于记忆副本列表“仅坐骑”按钮的上次状态，不再通过设置页暴露。
- `ToolboxDB.modules.encounter_journal.lockoutOverlayEnabled` 与 `detailMountOnlyEnabled` 本轮应彻底删除，包括默认值、迁移、读写与判断分支。
- 本轮新增 `ToolboxDB.modules.encounter_journal.listPinAlwaysVisible` 字段，默认关闭，用于控制副本列表图钉是否常驻显示。
- 入口数据来源收口为 DB 导出的 `Toolbox.Data.NavigationInstanceEntrances.entrancesByJournalInstanceID[journalInstanceID]`；选中 / 点击冒险指南条目时按该 `journalInstanceID` 直接读取规范化后的单表目标，不再串联静态 `InstanceEntrances` 或运行时 `C_EncounterJournal.GetDungeonEntrancesForMap(uiMapID)` 兜底。
- `Toolbox.Data.NavigationInstanceEntrances` 的来源为 `wow.db.journalinstanceentrance`、`journalinstance`、`uimapassignment`、`uimap` 与 `areapoi` 的正式导出结果；导出层必须直接产出 `TargetUiMapID + TargetX + TargetY`，并把共享物理入口的多个 `journalInstanceID` 展开为独立记录，例如 `236 / 1292` 同时存在且目标一致。
- `Toolbox.Data.InstanceEntrances` 可继续保留为追溯 / 审计数据，但不再承担 EJ 列表图钉导航的运行时查表职责；运行时导航逻辑也不再依赖 `C_Map.GetMapPosFromWorldPos` 进行世界坐标转换。
- 不因 `journalinstance.MapID` 相同、名称相近或同属一个副本组而自动共用入口；没有精确 `journalInstanceID` 来源时，不显示误导性静态导航。
- 下一阶段的正式运行时入口数据源改为单一规范化导出表；该表对每个可导航 `journalInstanceID` 都直接产出 `TargetUiMapID + TargetX + TargetY`，`Toolbox.EJ` 只消费这一张表。
- 规范化导出表的构建规则固定为：先按物理入口簇归并候选入口，再将簇内共享同一物理入口的每个 `journalInstanceID` 展开成独立导航目标行；不允许在运行时按 `MapID`、名称或其它弱关联再次猜测。
- 物理入口簇至少使用 `journalinstance.MapID`、`AreaTableID`、入口世界坐标和阵营字段参与归并；若同簇缺少可解析的外部地图上下文或出现多个冲突目标，导出必须失败，不允许静默丢行后交给运行时兜底。
- 现有 `Toolbox.Data.InstanceEntrances` 可保留为追溯 / 审计数据，但运行时副本入口导航不再直接消费它；运行时也不再调用 `C_EncounterJournal.GetDungeonEntrancesForMap` 作为 EJ 列表图钉兜底来源。
- 点击按钮后执行“打开世界地图 + 切到入口所在地图 + `C_Map.SetUserWaypoint` + `C_SuperTrack.SetSuperTrackedUserWaypoint(true)`”。
- 找不到入口或当前地图不允许设置 waypoint 时，不报 Lua 错误；按钮置灰或聊天提示说明不可导航。
- 副本列表里的“仅坐骑”按钮继续保留并写回 `mountFilterEnabled`；详情页“仅坐骑”按钮和功能整段删除，不保留隐藏式残留。
- 副本列表图钉显示规则固定为：
  - 勾选常驻显示：所有可导航列表行显示图钉；
  - 未勾选常驻显示：图钉默认隐藏；鼠标悬停任意可导航行时显示，移开后恢复隐藏。
- 副本列表进入详情页规则固定为：
  - 单击列表行继续沿用 Blizzard 当前默认“进入详情页”行为；
  - 插件不再接管自定义双击进入或单击焦点逻辑；
  - 图钉图标替换为 Blizzard 已存在的高亮版资源，需先核对可用 atlas / 贴图名后实现。

## 5. 待确认项

- 无。2026-04-27 已确认按本文件“DB 静态入口按 `journalInstanceID` 直接读取 + 列表图钉显示规则”开动实现。
- 无。2026-04-29 已确认设置页精简后的保留口径：列表“仅坐骑”保留并记忆状态；列表 CD 叠加固定开启；详情页“仅坐骑”删除。
- 无新的业务方案待确认。2026-05-01 已确认“导出层归一化入口目标表”方向；待需求方明确回复“开动”后，将本文件状态改为 `可执行` 并进入代码实施。

## 6. 验收标准

1. 在地下城 / 团队副本列表中，用户可以启用“仅坐骑”筛选并看到过滤结果。
2. 在副本列表中，用户可以直接看到当前角色的锁定重置时间；团队副本同时看到进度。
3. 鼠标悬停副本列表项时，用户可以看到更完整的锁定详情。
4. 副本详情页中不再出现“仅坐骑”按钮或相关过滤功能，但仍会显示当前所选难度的重置标签。
5. 设置页中不再出现“在冒险指南中筛选坐骑”“在冒险指南中显示副本CD”“仅坐骑”3 个选项。
6. `ToolboxDB.modules.encounter_journal.mountFilterEnabled` 仍然会记忆副本列表“仅坐骑”按钮的上次开关状态；重开冒险指南后继续沿用该状态。
7. `ToolboxDB.modules.encounter_journal` 不再声明、迁移、读写 `lockoutOverlayEnabled` 与 `detailMountOnlyEnabled`。
8. 未开启“定位图标常驻显示”时，副本列表图钉默认隐藏，不额外占用列表点击区域。
9. 未开启“定位图标常驻显示”时，鼠标悬停任意可导航副本列表条目时会显示图钉；移开后恢复隐藏。
10. 单击某个副本列表条目后，会继续进入该副本详情页，沿用 Blizzard 当前默认进入详情页行为，不依赖插件自定义双击处理。
11. 开启“定位图标常驻显示”后，所有可导航副本列表条目都显示图钉。
12. 小地图“冒险手册”入口 tooltip 和 `EJMicroButton` tooltip 都能显示当前副本锁定摘要。
13. `ToolboxDB.modules.encounter_journal` 不再读写任务浏览、Quest Inspector 或根页签排序相关旧键。
14. 在有入口数据的副本 / 地下城列表条目右下角，用户能看到更高辨识度的高亮图钉按钮。
17. 点击某个列表条目的图钉按钮后，世界地图打开到该条目副本入口所在地图，并创建系统用户导航目标且开始追踪。
18. 对无入口数据、API 不可用或地图不允许设置导航的副本，插件不抛 Lua 错误，并给出可理解的不可用反馈。
19. 当运行时入口 API 未返回当前 `journalInstanceID` 的精确入口，但 DB 静态表存在该 ID 的入口记录时，图钉导航使用静态入口数据；`厄运之槌 - 戈多克议会` 应能从静态数据命中自身记录，而不是兜到聚合入口 `230`。
20. 新增 `Toolbox/Data/InstanceEntrances.lua` 必须由 `DataContracts/instance_entrances.json` 和正式导出脚本生成，文件头满足数据库生成文件规范。
21. `Toolbox.Data.NavigationInstanceEntrances`（或同职责的唯一运行时入口导出表）中，`236` 与 `1292` 都必须存在独立记录，且二者导航目标一致、可直接消费。
22. `Toolbox.EJ.FindDungeonEntranceForJournalInstance(1292)` 命中入口时，不依赖运行时 `C_EncounterJournal.GetDungeonEntrancesForMap` 返回 `1292` 或 `236`；运行时副本入口导航不再保留三段式兜底链路。
23. 数据契约校验新增 `236 / 1292` 共享物理入口回归：若任一条目缺失、目标不一致或归并冲突未被导出阶段拦截，则验证失败。
24. 对缺少足够地图上下文、无法生成唯一导航目标的入口簇，导出阶段必须报错并阻塞生成；不得静默跳过后留给游戏内提示“未找到该副本的入口位置”。

## 7. 实施状态

- 当前状态：可执行
- 下一步：2026-05-01 用户已明确回复“开动”；后续按本文件已确认的“导出层归一化入口目标表 + 运行时单表直读”方案进入契约、导出与运行时代码实施。

## 8. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-12 | 初稿：建立 `encounter_journal` 当时代码对应的需求基线 |
| 2026-04-15 | 对齐当前实现：移除已拆分到 `quest` 模块的任务能力，仅保留副本列表、详情页与锁定摘要范围 |
| 2026-04-27 | 用户确认“开动”：新增副本入口导航需求，选定运行时入口数据与系统 waypoint 方案 |
| 2026-04-27 | 用户修正入口落点：从详情页按钮改为副本列表条目右下角图钉 |
| 2026-04-27 | 用户确认列表图钉增强：图钉高亮版与“定位图标常驻显示”设置 |
| 2026-04-29 | 点击回归修正：副本列表恢复 Blizzard 原生单击进入详情，插件不再接管自定义双击 / 单击焦点逻辑 |
| 2026-04-27 | 用户确认新增 DB 静态入口数据：从 `journalinstanceentrance` 导出精确入口，运行时按 `journalInstanceID` 读取静态表补足入口 API 缺口 |
| 2026-04-27 | 修正 `厄运之槌 - 中心花园` 数据源优先级：`areapoi` 精确 POI 优先，避免使用分翼门候选坐标 |
| 2026-04-28 | 修正入口读取优先级：选中冒险指南条目时直接按 `journalInstanceID` 读取 DB 静态表，运行时入口 API 仅作缺数据兜底 |
| 2026-04-28 | 修正静态入口目标地图：`areapoi` 来源也必须导出 `HintUiMapID`，确保导航后打开对应区域地图 |
| 2026-04-29 | 用户确认设置页精简方案：删除 3 个设置项；保留并记忆列表“仅坐骑”；固定开启列表 CD 叠加；删除详情页“仅坐骑”按钮与功能 |
| 2026-04-29 | 本轮实现完成：设置页删项、列表“仅坐骑”记忆状态保留、详情页“仅坐骑”移除，并通过全量自动化验证 |
| 2026-05-01 | 只读审查确认 `1292` 因导出契约过滤与运行时 exact-match 兜底失效而必然漏导航；用户确认下一阶段改为“导出层归一化入口目标表 + 运行时单表直读”方向，待明确“开动”后执行 |
| 2026-05-01 | 用户已明确回复“开动”；本文件状态推进为 `可执行`，允许进入契约、导出与运行时代码实施 |
