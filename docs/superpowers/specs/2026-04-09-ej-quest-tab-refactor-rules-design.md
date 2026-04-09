# 冒险手册任务页签重构规则补全（B档）

- 日期：2026-04-09
- 状态：需求补全稿（可落地）
- 范围：`Toolbox`（Retail）
- 关联模块：`encounter_journal`
- 关联需求：`2026-04-09-ej-quest-tab-refactor-design.md`

## 1. 目标

在不改变原需求边界的前提下，补齐可直接实现所需的规则空白：

1. 字段级数据契约（含必填/可空/引用约束）。
2. 左树 + 右内容区的状态机与联动规则。
3. strict 校验口径与 `mock/live` 一致性口径。
4. 进度聚合、空值显示、回退策略等实现细则。

## 2. 数据契约（Schema v2）

### 2.1 根结构（必填）

`Toolbox.Data.InstanceQuestlines` 必须包含以下字段：

1. `schemaVersion: number`，固定值 `2`。
2. `sourceMode: string`，仅允许 `mock | live`。
3. `generatedAt: string`，UTC ISO8601 时间串。
4. `quests: table`。
5. `questLines: table`。
6. `questLineQuestIDs: table`。
7. `expansionQuestLineIDs: table`。

### 2.2 quest 主表（`quests[questID]`）

1. key 必须为 `questID(number)`。
2. `questID` 必填且必须等于外层 key。
3. `mapID` 必填，`number`，`> 0`。
4. `startNpcID`、`turnInNpcID` 可空；非空时为 `number`。
5. `prerequisiteQuestIDs`、`nextQuestIDs` 可空；非空时为 `number[]` 且元素唯一。
6. `unlockConditions` 可空；非空时为 `table`，允许字段：
   - `minLevel: number|nil`（非空时 `>= 1`）
   - `classIDs: number[]|nil`（非空时元素唯一）
   - `renown: { factionID:number, minLevel:number }[]|nil`
   - `worldStateFlags: number[]|nil`（非空时元素唯一）

### 2.3 任务线主表（`questLines[questLineID]`）

新增 `questLines` 作为任务线元数据唯一来源，字段如下：

1. `questLineID`：必填，`number`，等于外层 key。
2. `name`：必填，非空 `string`。
3. `expansionID`：必填，`number`。
4. `primaryMapID`：必填，`number`，`> 0`。

约束：

1. 不引入 `quests.questLineID`。
2. 任务线归属只由 `questLineQuestIDs` 表达。

### 2.4 映射表约束

1. `questLineQuestIDs[questLineID]`：
   - 必须是非空有序 `number[]`。
   - `questLineID` 必须存在于 `questLines`。
   - 每个 `questID` 必须存在于 `quests`。
2. `expansionQuestLineIDs[expansionID]`：
   - 必须是非空有序 `number[]`。
   - 每个 `questLineID` 必须存在于 `questLines`。
   - `questLines[questLineID].expansionID` 必须等于该 `expansionID`。
3. 全局唯一性：
   - 同一 `questID` 不得挂到多个 `questLineID`（避免重复进度聚合）。

## 3. 主归属地图与名称来源

### 3.1 主归属地图规则

1. `primaryMapID` 以导出侧产出为准。
2. 若导出侧缺失 `primaryMapID`，strict 直接失败，不在 UI 层兜底推导。
3. 若导出侧需要兜底推导，统一规则为：
   - 先按该任务线内 `mapID` 出现频次降序；
   - 频次并列时取在 `questLineQuestIDs` 中首次出现的 `mapID`。

### 3.2 名称来源优先级

1. 地图名：运行时 API 名称 > 导出名称 > `Map #<mapID>`。
2. 资料片名：运行时 API/常量 > 导出名称 > `Expansion #<expansionID>`。
3. 名称缺失不得导致渲染失败。

## 4. UI 状态机（左树 + 右内容区）

### 4.1 单一状态源

统一使用以下状态：

1. `selectedKind`：`expansion | map | questline | quest`
2. `selectedExpansionID`：必填
3. `selectedMapID`：可选
4. `selectedQuestLineID`：可选
5. `selectedQuestID`：可选

### 4.2 默认行为

1. 打开任务页签时默认选中当前资料片节点。
2. 默认展开当前资料片与当前地图。
3. 展开状态持久化：
   - `expansion:<expansionID>`
   - `map:<expansionID>:<mapID>`

### 4.3 左树交互

1. 点 `expansion`：右侧显示该资料片任务线列表。
2. 点 `map`：右侧显示该地图任务线列表。
3. 点 `questline`：右侧显示该任务线任务列表。
4. 点 `quest`：右侧显示该任务详情。

### 4.4 右侧反向联动

1. 点任务线列表项：左树同步选中对应任务线并定位。
2. 点任务列表项：左树同步选中对应任务并展开其父任务线。

### 4.5 失效回退

数据刷新后若当前选中对象不存在：

1. 优先回退到同资料片节点。
2. 同资料片不存在时回退到首个资料片节点。
3. 禁止出现“左树高亮与右侧内容不一致”。

## 5. 进度聚合与显示规则

### 5.1 状态口径

任务状态保持三态：`completed | active | pending`（沿用现有 API 判定口径）。

### 5.2 聚合口径

1. 任务线进度：
   - `completed = 已完成任务数`
   - `total = questLineQuestIDs[questLineID]` 长度
2. 地图聚合进度：
   - 对该地图下任务线任务去重后再聚合。
3. 资料片节点不显示聚合进度。
4. 地图节点与任务线节点显示 `completed/total` 摘要。

### 5.3 右侧显示

1. 任务线列表显示：地图名、进度摘要、任务数量。
2. 任务列表只显示：任务名 + 完成标记（图标/颜色），不显示状态文字。
3. 详情区分组顺序固定：
   - 基础信息
   - NPC
   - 前后置任务
   - 解锁条件
4. `nil` 字段不显示；空数组/空表分组不显示。

## 6. strict 校验规则

strict 开启时，任一失败立即中止，不静默跳过。

### 6.1 必检项

1. 字段存在性（必填字段缺失）。
2. 字段类型（含数组元素类型）。
3. key-value 一致性（如 `quests[key].questID == key`）。
4. 引用完整性（映射表引用对象必须存在）。
5. 非空数组约束（`questLineQuestIDs`、`expansionQuestLineIDs`）。
6. 根字段合法值（`schemaVersion`、`sourceMode`、`generatedAt`）。

### 6.2 典型错误码建议

1. `E_MISSING_FIELD`
2. `E_TYPE_MISMATCH`
3. `E_BAD_REF`
4. `E_EMPTY_ARRAY`
5. `E_INVALID_ENUM`
6. `E_INVALID_TIMESTAMP`

## 7. mock/live 一致性口径

`mock` 与 `live` 必须满足：

1. 根字段集合一致。
2. 必填字段集合一致。
3. 字段类型一致。
4. 引用关系规则一致。
5. 排序规则一致（数组有序语义一致）。

允许差异：

1. 字段取值可不同（如 NPC、解锁条件具体值）。
2. 但不得破坏 schema 结构和引用完整性。

## 8. 验收补充

在原需求验收基础上追加：

1. 任意点击后，左树选中状态与右侧内容 100% 同步。
2. 数据热刷新后无“悬挂选中”或“错位显示”。
3. 任意 `nil` 字段不渲染为文本。
4. strict 下坏数据必须失败并给出可定位错误信息。

