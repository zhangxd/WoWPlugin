# 冒险指南任务线树形查看设计（按资料片组织）

- 日期：2026-04-08
- 状态：待实现
- 范围：`Toolbox`（Retail）
- 关联模块：`encounter_journal`

## 1. 背景与目标

在冒险指南（Encounter Journal）中增加“任务线树形查看”，满足以下目标：

1. 展示结构为：`资料片 -> 类型 -> 节点 -> 任务线 -> 任务`。
2. 默认类型为 `map`，即按地图节点组织普通任务线。
3. 类型可扩展，后续支持 `campaign`、`feature` 等。
4. 初版不实现链式图，仅实现可折叠树形查看与任务状态进度。

## 2. 需求边界

### 2.1 本期包含

1. 在冒险指南详情页展示任务线树。
2. 任务线进度统计（总数、完成数、进行中、下一步任务）。
3. 折叠/展开交互与状态保存。
4. 数据结构支持未来扩展类型。

### 2.2 本期不包含

1. 链式图（节点连线视图）。
2. 自动抓取全量任务线数据管线。
3. 跨模块跳转到外部任务插件的深度联动。

## 3. 数据模型设计

新增静态数据文件：`Toolbox/Data/InstanceQuestlines.lua`。

```lua
Toolbox.Data = Toolbox.Data or {}

Toolbox.Data.InstanceQuestlines = {
  [10] = { -- expansionID
    name = "The War Within",
    types = {
      map = {
        ["isle_of_dorn"] = {
          name = "Isle of Dorn",
          maps = {2248},
          chains = {
            {
              id = "tww_dorn_intro",
              name = "Introduction",
              kind = "normal",
              journalInstances = {1270, 1271},
              quests = {78713, 78714, 78715}
            }
          }
        }
      }
    }
  }
}
```

约束：

1. 顶层必须按资料片分桶。
2. 每种类型下统一为“节点 -> chains[]”。
3. `journalInstances` 用于与冒险指南副本建立关联。
4. `quests` 为任务 ID 序列，供状态与进度计算。

## 4. API 设计（领域对外）

新增文件：`Toolbox/Core/API/QuestlineProgress.lua`，提供 `Toolbox.Questlines`。

### 4.1 对外接口

1. `Toolbox.Questlines.RegisterType(typeId, resolver)`
2. `Toolbox.Questlines.GetExpansionTree(expansionID)`
3. `Toolbox.Questlines.GetInstanceTree(journalInstanceID)`
4. `Toolbox.Questlines.GetChainProgress(chain)`
5. `Toolbox.Questlines.GetQuestStatus(questID)`

### 4.2 状态判定

1. 已完成：`C_QuestLog.IsQuestFlaggedCompleted(questID)`
2. 进行中：`C_QuestLog.GetLogIndexForQuestID(questID)` 返回有效日志索引
3. 待接取：以上两者都不满足

## 5. UI 设计（树形）

改造文件：`Toolbox/Modules/EncounterJournal.lua`。

层级渲染：

1. 资料片层（默认展开当前资料片）
2. 类型层（默认显示 `map`）
3. 节点层（地图）
4. 任务线层（显示 `完成/总数`）
5. 任务层（可选展开，显示单任务状态）

交互规则：

1. 每层可折叠。
2. 折叠状态保存到模块存档。
3. 当前副本无关联数据时显示空态提示。

## 6. 配置与文案

### 6.1 存档字段（`modules.encounter_journal`）

1. `questlineTreeEnabled = true`
2. `questlineTreeShowQuests = true`
3. `questlineTreeExpanded = {}`

### 6.2 Locales 键

1. `EJ_QUESTLINE_TREE_TITLE`
2. `EJ_QUESTLINE_TREE_EMPTY`
3. `EJ_QUESTLINE_PROGRESS_FMT`
4. `EJ_QUESTLINE_TYPE_MAP`

## 7. 文件变更清单

1. 新增：`Toolbox/Data/InstanceQuestlines.lua`
2. 新增：`Toolbox/Core/API/QuestlineProgress.lua`
3. 修改：`Toolbox/Modules/EncounterJournal.lua`
4. 修改：`Toolbox/Core/Foundation/Config.lua`
5. 修改：`Toolbox/Core/Foundation/Locales.lua`
6. 修改：`Toolbox/Toolbox.toc`
7. 修改：`tests/validate_settings_subcategories.py`

## 8. 验收标准

1. 可在冒险指南详情页看到任务线树形结构。
2. 展示层级符合 `资料片 -> 类型 -> 节点 -> 任务线 -> 任务`。
3. 默认类型为 `map`，且可通过注册机制扩展新类型。
4. 任务线进度与任务状态显示正确。
5. 折叠状态可持久化并在刷新后恢复。
6. 模块关闭后树形视图不渲染且无报错。

## 9. 里程碑建议

1. M1：数据层与 API 骨架（不渲染 UI）
2. M2：详情页树形面板与折叠交互
3. M3：进度统计、空态、文案与配置页开关
4. M4：回归测试与文档同步

