# 冒险手册任务页签重构设计

- 日期：2026-04-09
- 状态：已过时（schema 已升级至 v3，见 2026-04-10-questline-mock-data-separation.md）
- 范围：`Toolbox`（Retail）
- 关联模块：`encounter_journal`

## 0. 归档说明（当前实现差异）

本文档保留为 2026-04-09 历史草案，不再作为当前实现依据。当前代码以 `schema v3 + map 维度树` 为准，关键差异如下：

1. 树层级已收敛为：`地图 -> 任务线 -> 任务`，不再使用“资料片节点”作为运行时模型主层级。
2. 数据结构已切换为 `schemaVersion = 3`，核心字段为 `ID / Name_lang / UiMapID`，不再依赖 `expansionQuestLineIDs`。
3. `QuestlineProgress` 已支持测试注入接口 `SetDataOverride(dataTable|nil)`。
4. 任务页签运行时增加了可恢复容错：`E_BAD_REF / E_DUPLICATE_REF` 不再导致整页签不可用。
5. 详细规范与测试约束以 `2026-04-10-questline-mock-data-separation.md` 为准。

## 1. 目标

重构 `encounter_journal` 中的任务页签内容，先完成以下目标：

1. 以新静态表结构替换当前任务页签读取逻辑。
2. 保持树形浏览主逻辑不变，但将界面组织调整为“左导航树 + 右内容区”。
3. 第一阶段优先跑通“当前可导出字段 + 模拟数据补位”的数据链路与界面联调。
4. 不因 wow.db 当前字段尚未完全确认而阻塞第一阶段实现。

## 2. 范围边界

### 2.1 本期包含

1. 重构任务页签读取逻辑，直接切到新静态表结构。
2. 左侧树浏览：`资料片 -> 地图 -> 任务线`。
3. 右侧内容区：
   - 选中资料片/地图时显示任务线列表
   - 选中任务线时显示任务列表
   - 选中任务时显示任务详情
4. 使用 `mock/live` 同 schema 的导出数据进行联调。
5. 对当前已确认可用的静态字段做 strict 校验。

### 2.2 本期不包含

1. 旧结构兼容层。
2. 任务简介、字符串包、目标列表、地图静态表等额外静态字段。
3. 依赖尚未确认导出来源的点位字段：
   - `startPoint`
   - `turnInPoint`
   - `sourceType`
   - `sourceID`
4. 基于点位字段的地图点位联动交互。
5. 因 wow.db 字段未确认而提前扩展的 schema。

## 3. 数据原则

1. 能通过原生 API 稳定直接获取的数据，不进入静态表。
2. 不能通过 `questID` 稳定全量直取的数据，进入静态表。
3. 第一阶段允许真实可导出字段与模拟数据并存。
4. 后续若 wow.db 能提供更多稳定字段，再按需要扩展 schema。

## 4. 静态表结构

当前确认的静态表基线如下：

```lua
Toolbox.Data = Toolbox.Data or {}

Toolbox.Data.InstanceQuestlines = {
  schemaVersion = 2, -- 数据结构版本号
  sourceMode = "live", -- 导出模式：live 或 mock
  generatedAt = "2026-04-09T16:30:00Z", -- 导出时间（UTC）

  quests = { -- 全量任务主表（唯一任务数据源）
    [84956] = { -- 以 questID 为键
      questID = 84956, -- 任务ID（与外层键一致，保留便于读取）
      mapID = 2371, -- 任务归属地图ID

      startNpcID = 123456, -- 接取NPC ID；无法确认时为nil
      turnInNpcID = 123457, -- 交付NPC ID；无法确认时为nil

      prerequisiteQuestIDs = { 84955 }, -- 前置任务ID列表；无前置时为nil
      nextQuestIDs = { 84957 }, -- 后续任务ID列表；无后续时为nil

      unlockConditions = { -- 解锁条件；无额外条件时为nil
        minLevel = 80, -- 最低等级要求；无等级要求时为nil
        classIDs = { 1, 2 }, -- 职业ID列表；不限职业时为nil
        renown = { -- 名望要求列表；无名望要求时为nil
          {
            factionID = 2640, -- 名望阵营ID
            minLevel = 5, -- 最低名望等级
          },
        },
        worldStateFlags = { 1001, 1002 }, -- 世界状态标记列表；无要求时为nil
      },
    },
  },

  questLineQuestIDs = { -- 任务线到任务ID列表映射
    [100001] = { 84956, 84957, 85003 }, -- questLineID -> 有序 questID 列表
  },

  expansionQuestLineIDs = { -- 资料片到任务线ID列表映射
    [10] = { 100001, 100002 }, -- expansionID -> 有序 questLineID 列表
  },
}
```

## 5. 字段与约束

### 5.1 ID 与顺序

1. `questID`、`questLineID`、`expansionID` 全部为 `number`。
2. `questLineID` 使用 Blizzard 原生 `questLineID`。
3. `expansionID` 使用 Blizzard 原生资料片 ID。
4. `questLineQuestIDs`、`expansionQuestLineIDs` 都是有序稳定数组。

### 5.2 已明确不纳入当前静态表

1. 任务简介。
2. 字符串包。
3. `maps`。
4. `relatedNpcIDs`。
5. `objectives`。
6. `quests.questLineID`。
7. `unlockConditions.faction`。
8. `questClassification`。
9. `startPoint`。
10. `turnInPoint`。
11. `sourceType`。
12. `sourceID`。

### 5.3 `mapID` 语义

1. `quests[questID].mapID` 表示任务归属地图。
2. 该字段用于树中地图节点归类，而不是运行时导航点。

### 5.4 任务线主归属地图

1. 左侧树的固定层级为：`资料片 -> 地图 -> 任务线`。
2. 跨地图任务线只挂到一个主归属地图下。
3. 第一阶段允许主归属地图由模拟数据或导出侧规则给出。
4. 后续若 wow.db 能稳定推导，再将该规则固化到导出逻辑。

## 6. 界面与交互

### 6.1 左侧树

1. 树层级固定为：`资料片 -> 地图 -> 任务线`。
2. 点击标题逐级展开/收起。
3. 左侧默认展开当前资料片和当前地图。
4. 展开状态需要持久化记忆。
5. 左侧默认选中当前资料片节点。
6. 地图顺序不新增独立字段，按 `expansionQuestLineIDs` 中天然顺序推导：
   - 某资料片下任务线首次出现该地图的顺序，就是地图顺序。
7. 任务线节点显示进度摘要。
8. 地图节点显示聚合进度摘要。
9. 资料片节点不显示聚合进度摘要。

### 6.2 右侧内容区

1. 选中资料片或地图节点时，显示该节点下的任务线列表。
2. 任务线列表显示：
   - 地图名
   - 进度摘要
   - 任务数量
3. 点击任务线列表项时：
   - 同步切换左侧树选中到该任务线
   - 右侧切换到该任务线任务列表
4. 任务列表按 `questLineQuestIDs` 中的顺序显示。
5. 任务完成状态只用图标或颜色标记，不额外显示文字。
6. 任务列表只显示任务名与完成标记。
7. 点击任务后，在右侧详情区显示该任务详情。
8. 详情区按现有数据自然分组组织，使用“标题 + 逐级展开”的方式表达。
9. `nil` 字段不显示。

## 7. 导出与校验

1. `mock` 与 `live` 必须输出同一 schema。
2. strict 校验开启。
3. 以下情况直接失败，不静默跳过：
   - 字段缺失
   - 类型错误
   - `questLineQuestIDs` 引用不存在的 `questID`
   - `expansionQuestLineIDs` 引用不存在的 `questLineID`

## 8. 第一阶段落地策略

1. 先按当前已确认 schema 完成读取与界面联调。
2. wow.db 当前能导出的字段直接接入。
3. 暂时不能导出的字段，使用模拟数据补位。
4. 后续当真实导出字段明确后，再调整静态表字段与导出规则。

## 9. 后续扩展入口

以下内容明确留到后续阶段再评估，不作为第一阶段前置：

1. `startPoint` / `turnInPoint`
2. 目标点位与目标列表
3. 任务简介或字符串包
4. 基于点位字段的地图联动
5. 独立地图静态表
