# 冒险指南任务页签导航重构设计

- 文档类型：设计
- 状态：已落地
- 主题：encounter-journal-quest-navigation
- 适用范围：`encounter_journal` 任务页签导航重构、`Toolbox.Questlines` 任务导航模型、`instance_questlines` 资料片字段导出
- 关联模块：`encounter_journal`
- 关联文档：
  - `docs/specs/encounter-journal-quest-navigation-spec.md`
  - `docs/designs/encounter-journal-design.md`
  - `docs/plans/encounter-journal-quest-navigation-plan.md`
  - `docs/Toolbox-addon-design.md`
- 最后更新：2026-04-12

## 1. 背景

- 任务页签上一轮已改成顶部资料片 / 分类导航，但用户进一步确认资料片应固定为左侧一级导航，并把 `地图任务线 / 任务类型` 融入资料片展开树。
- 地图路径下的主区交互也已改口为“任务线单行列表 + 点击展开任务列表 + 再点折叠”，而不是先切到单独任务线页。
- 当前 `InstanceQuestlines` 导出只有任务、任务线、地图链路，没有“任务线所属资料片”稳定字段，因此需要先把数据来源收敛到契约层。

## 2. 设计目标

- 用左侧固定资料片树替代顶部资料片 / 分类导航，让导航层级更稳定。
- 让 `地图任务线` 与 `任务类型` 作为资料片下的两种浏览入口，而不是并列的顶部按钮。
- 地图路径下保留任务线层级，但由主区折叠列表承载，不把任务线塞进左侧树最终层级。
- 任务类型路径下直接落到任务列表，并通过详情弹框支持回跳到地图 / 任务线。
- 主区顶部补一条可点击 breadcrumb 路径，参考冒险指南原生 navBar 的层级表达。
- 把“任务线所属资料片”前移到导出契约，避免插件运行时临时推断。
- 用最小范围的代码改动完成重构，不新增模块、不新增 TOC 行。

## 3. 非目标

- 不重新设计冒险指南任务页签以外的副本列表和详情页增强功能。
- 不在本次改动中新增玩家可见入口、slash 命令或设置子页。
- 不把任务详情改成任务列表内联展开卡片。
- 不在本次改动中重做 `InstanceQuestlines` 的整体导出结构，只补本次导航所需字段。

## 4. 方案对比

### 4.1 方案 A：保留顶部切视图，只把资料片按钮改窄或改滚动

- 做法：延续顶部资料片 / 分类切换，只优化按钮排版和主区列表。
- 优点：改动集中在 UI 层。
- 风险 / 缺点：一级资料片导航仍然拥挤，地图与类型模式的层级关系也不如左侧树清晰。

### 4.2 方案 B：左侧资料片树 + 两个资料片子入口 + 契约驱动资料片字段

- 做法：在 `instance_questlines` 契约与导出结果中为 `questLines[*]` 增加 `ExpansionID`，左侧导航固定为资料片树；资料片下展开 `地图任务线` 与 `任务类型` 两个入口；地图路径下主区做任务线折叠列表，类型路径下主区直接显示任务列表。
- 优点：资料片层级稳定，地图与类型职责分离，回跳路径清晰，后续扩展新入口也容易。
- 风险 / 缺点：需要同时调整导出、运行时模型、左树状态和主区渲染逻辑。

### 4.3 方案 C：把任务线也继续塞进左侧树

- 做法：左侧树走到 `资料片 -> 地图任务线 -> 地图 -> 任务线`，主区仅显示任务列表。
- 优点：左树层级完整。
- 风险 / 缺点：左树过深且滚动压力大，任务线行无法承载进度和任务数，不利于后续类型视图保持一致。

### 4.4 选型结论

- 选定方案：方案 B。
- 选择原因：用户已经明确资料片必须固定为一级导航，同时不希望任务线继续塞进左侧树最终层级，因此需要契约驱动的资料片字段和“左树负责定位、主区负责展开”的组合方案。

## 5. 选定方案

### 5.1 数据契约与导出

- 在 `DataContracts/instance_questlines.json` 中为 `questLines` 块增加 `ExpansionID` 字段。
- `ExpansionID` 的生成方式固定为：沿现有 `questline_best_map` 主归属地图链路，进一步关联 `Map.ExpansionID`，并作为任务线稳定字段导出。
- 因导出结构发生变化，本次需要提升 `instance_questlines` 契约版本，并同步提升插件侧 `InstanceQuestlines.schemaVersion` 校验逻辑。
- 生成后的 `Toolbox/Data/InstanceQuestlines.lua` 继续保持“静态关系 + 运行时字段后补”的结构，但 `questLines[*]` 增加 `ExpansionID`。

### 5.2 运行时模型

- `Toolbox.Questlines.GetQuestTabModel()` 保留现有基础对象，但补充任务导航所需索引：
  - `expansionList`
  - `expansionByID`
  - `expansionToMaps`
  - `expansionToTypeGroups`
- 新导航模型的核心职责是：
  - 给定资料片，返回两个固定子入口：`地图任务线` 与 `任务类型`；
  - 给定资料片 + 地图，返回任务线列表；
  - 给定资料片 + 类型大类，返回任务列表；
  - 给定任务，返回 tooltip / 弹框所需详情对象。
- 现有 `GetQuestTypeIndex()` 和 `GetQuestListByQuestLineID()` 继续复用，但类型视图展示分组要优先使用 `GetQuestTagInfo / Enum.QuestTagType` 做大类归并，`GetQuestType()` 仅做底层补充。

### 5.3 任务页签 UI

- 左侧导航树固定为资料片列表，可上下滚动。
- 资料片节点下固定展开两个子入口：
  - `地图任务线`
  - `任务类型`
- `地图任务线` 节点下显示当前资料片的地图列表。
- `任务类型` 节点下显示当前资料片下归并后的类型大类列表。
- 地图路径下，主区显示任务线单行列表；每条任务线独占一行，并显示名称、进度、任务数。
- 点击任务线行时，原地展开该任务线的任务列表；再次点击折叠；同一时刻只展开一条任务线。
- 类型路径下，主区直接显示任务列表，不增加任务线中间层。
- 主区顶部使用一条可点击 breadcrumb：
  - 地图路径：`资料片 > 地图任务线 > 地图`，若展开了任务线，再追加 `> 任务线`
  - 类型路径：`资料片 > 任务类型 > 类型大类`
- breadcrumb 中最后一段仅高亮显示，不提供回退；前面的段均可点击并同步恢复对应状态。
- 任务列表项仅显示任务名；悬停时用 `GameTooltip` 显示摘要；点击后弹出居中的任务详情框。
- 详情弹框使用任务页签面板内的自定义 overlay frame，不创建新的模块入口，也不写入独立持久化状态。

### 5.4 存档与迁移

- 新导航状态改为：
  - `questNavExpansionID`
  - `questNavModeKey`（`map_questline` / `quest_type`）
  - `questNavSelectedMapID`
  - `questNavSelectedTypeKey`
  - `questNavExpandedQuestLineID`
- 旧键迁移策略：
  - 顶部导航时代的 `questNavCategoryKey`：映射到新的 `questNavModeKey`
  - 顶部导航时代的 `questNavSelectedQuestLineID`：若仍存在有效地图归属，迁入 `questNavExpandedQuestLineID`
  - `questViewSelectedMapID`：优先迁入 `questNavSelectedMapID`
  - `questViewSelectedQuestID`：不迁移，因新交互不需要持久化选中任务
  - `questViewSelectedTypeID / 旧 questNavCategoryKey / questlineTreeCollapsed / questlineTreeSelection`：迁移完成后清理，不再驱动 UI
- 默认导航值由运行时首个可用资料片、默认模式 `map_questline` 与首个可用地图兜底。

### 5.5 任务详情交互

- tooltip 用于轻量摘要，内容以任务名、状态、地图、任务线名和前后置链路为主。
- 点击任务后显示详情弹框，弹框中承载完整详情文本，替代当前 `detailText` 的内嵌展示方式。
- 若任务具备任务线归属，弹框中提供“跳转到对应地图 / 任务线”的动作，点击后切回地图路径并展开目标任务线。
- 弹框关闭不会改写导航路径，只清空当前弹框显示状态。

## 6. 影响面

- 数据与存档：
  `instance_questlines` 导出结构继续使用 `questLines[*].ExpansionID`；`ToolboxDB.modules.encounter_journal` 的导航状态从顶部分类模式切到左树模式与单展开任务线状态。
- API 与模块边界：
  `Toolbox.Questlines` 负责资料片导航模型与任务详情查询；`encounter_journal` 只负责任务页签 UI、导航切换和 tooltip / 弹框交互。
- 文件与目录：
  主要涉及 `Toolbox/Core/API/QuestlineProgress.lua`、`Toolbox/Core/Foundation/Config.lua`、`Toolbox/Core/Foundation/Locales.lua`、`Toolbox/Modules/EncounterJournal.lua` 与对应测试；若类型大类需要静态文案映射，也会同步改 `Toolbox/Data/QuestTypeNames.lua` 或对应本地化文案。
- 文档回写：
  落地后需要更新 `docs/designs/encounter-journal-design.md`、`docs/features/encounter-journal-features.md` 与 `docs/Toolbox-addon-design.md` 中关于任务页签结构的描述。

## 7. 风险与回退

- 风险：
  `EncounterJournal.lua` 当前任务页签实现集中在单文件内，重构时容易遗漏旧顶部导航、旧展开状态或旧详情区逻辑。
- 风险：
  基于 `QuestTagType` 的类型大类归并若处理不当，容易出现类型视图下“其它”过大或类型名不稳定的问题。
- 回退或缓解方式：
  先补逻辑测试覆盖左树模式、地图主区折叠展开和回跳，再重构 UI。
- 回退或缓解方式：
  若详情弹框在游戏内出现严重兼容问题，可临时保留弹框文本简化版，但不回退左树导航结构。

## 8. 验证策略

- 逻辑验证：
  补充 `Toolbox.Questlines` 的左树导航模型、地图主区单展开任务线逻辑、类型大类分组、breadcrumb 回退与 `Config` 迁移测试。
- 游戏内验证：
  检查左侧资料片树、资料片下两个入口、地图列表、类型列表、地图主区任务线展开 / 折叠、breadcrumb 路径显示与点击回退、任务 tooltip、任务详情弹框和回跳行为。
- 文档验证：
  确认本设计与 [encounter-journal-design.md](/D:/WoWProject/WoWPlugin/docs/designs/encounter-journal-design.md) 以及 [Toolbox-addon-design.md](/D:/WoWProject/WoWPlugin/docs/Toolbox-addon-design.md) 的描述保持一致。

## 9. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-12 | 初稿：确定任务页签改为“资料片 -> 分类 -> 任务线 -> 任务”统一路径，并选定契约驱动的资料片字段方案 |
| 2026-04-12 | 落地：资料片字段已进入 `instance_questlines` 导出，任务页签 UI 与存档迁移按本设计完成 |
| 2026-04-13 | 更新：导航改为左侧资料片树，资料片下收纳“地图任务线 / 任务类型”；地图主区改为任务线单行折叠展开 |
| 2026-04-13 | 落地：左侧树模式、类型视图与详情回跳按本设计完成，自动测试通过 |
| 2026-04-13 | 更新：补充主区 breadcrumb 路径导航设计，要求前级路径可点击回退 |
| 2026-04-13 | 落地：breadcrumb 已按层级按钮链实现，前级路径支持点击回退 |
