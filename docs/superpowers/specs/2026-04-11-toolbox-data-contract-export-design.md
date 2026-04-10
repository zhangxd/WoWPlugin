# Toolbox 静态数据契约导出规范

- 日期：2026-04-11
- 状态：设计已确认，待实现
- 范围：`WoWPlugin` / `WoWTools`
- 目标：为 `WoWTools -> WoWPlugin` 的静态 Lua 数据导出建立统一契约规范

## 1. 背景

当前 `WoWTools` 与 `WoWPlugin` 的静态数据协作方式，已经具备以下基础能力：

1. `WoWTools` 可以从 `wow.db` 查询数据并导出到 Lua。
2. `WoWPlugin` 通过 `Toolbox/Data/*.lua` 在运行时消费静态数据。
3. 现有导出规则部分依赖文件头说明、输出文件名和工具侧的手写导出逻辑。

现状问题在于：

1. 导出规则的“唯一权威来源”不明确。
2. 数据结构、查询定义、输出文件之间缺少稳定且可校验的契约层。
3. 插件消费端需要知道“某份静态数据的结构定义是什么、由哪份约定产生”，但目前主要靠人工记忆和文档说明。
4. `WoWTools` 在导出时仍需要内置较多手写规则，难以做到“只解析契约就知道导出内容与 Lua 结构”。

本规范要解决的问题是：

- 由 `WoWPlugin` 定义静态数据契约；
- 由 `WoWTools` 负责读取契约、校验契约、执行导出、保存快照；
- 每次导出需求都有唯一契约文件，对应唯一导出数据文件；
- 插件开发链路可以通过 `contract_id` 追踪该数据对应的契约。

## 2. 设计目标

### 2.1 核心目标

1. 每个由 `WoWTools` 导出的静态 Lua 数据文件，必须有且仅有一个权威契约文件。
2. `WoWPlugin` 是契约定义端，`WoWTools` 是契约执行端。
3. 契约文件必须足够声明式，能直接驱动导出，而不是只写自然语言说明。
4. Lua 文件头必须可定位、可校验、可追溯。
5. 契约升级必须有统一版本治理规则和强失败门禁。

### 2.2 非目标

1. 本规范不覆盖 `Toolbox/Data/*.lua` 中手工维护的数据文件。
2. 本规范不要求 WoW 运行时去读取 JSON 契约文件。
3. 本规范不在 v1 中引入完整 SQL DSL 或任意 Lua 模板引擎。
4. 本规范不改变 `WoWPlugin` 现有模块架构、TOC 加载模型和运行时数据读取方式。

## 3. 适用范围

本规范仅适用于以下对象：

- `WoWPlugin/Toolbox/Data/*.lua` 中由 `WoWTools` 基于 `wow.db` 生成的静态数据文件。

本规范不强制覆盖：

- 手工维护的 `Toolbox/Data/*.lua`
- 测试 fixtures
- 非 `Toolbox/Data/` 目录下的其他导出产物

## 4. 术语

### 4.1 `contract_id`

静态数据契约的唯一稳定标识。

规则：

1. 使用小写字母、数字、下划线。
2. 命名风格使用下划线平铺，例如：`instance_map_ids`。
3. 一旦创建，不允许重命名。
4. 一个 `contract_id` 只对应一种长期稳定的数据职责。

### 4.2 `schema_version`

结构版本号。

规则：

1. 只要 Lua 结构变化，就必须递增。
2. 数据内容刷新不视为结构变化。
3. 在同一个 `contract_id` 下严格单调递增，不允许回退或跳号。

### 4.3 契约文件

位于 `WoWPlugin/DataContracts/<contract_id>.json` 的 JSON 文件，是静态数据契约的唯一权威定义。

### 4.4 契约快照

`WoWTools` 在每次导出时保存的契约历史副本，仅用于追溯，不参与契约定义。

## 5. 总体方案

### 5.1 责任边界

#### `WoWPlugin`

负责：

1. 定义 `contract_id`
2. 定义 `schema_version`
3. 定义输出文件和 Lua 根表
4. 定义查询意图、SQL、结构化查询描述
5. 定义 Lua 结构和校验规则

不负责：

1. 执行数据库查询
2. 生成最终 Lua 文件
3. 保存导出快照

#### `WoWTools`

负责：

1. 读取 `WoWPlugin/DataContracts/<contract_id>.json`
2. 校验契约文件和导出目标
3. 执行查询并生成 Lua
4. 写入统一文件头
5. 保存契约历史快照

不负责：

1. 反向定义契约
2. 绕过契约私自创建新导出规则
3. 修改契约快照后再作为权威源使用

### 5.2 作用链路

标准链路固定为：

1. 在 `WoWPlugin/DataContracts/` 新增或更新契约文件。
2. `WoWTools` 按 `contract_id` 读取契约文件。
3. `WoWTools` 校验契约、执行 SQL、按结构定义渲染 Lua。
4. `WoWTools` 写入 `WoWPlugin/Toolbox/Data/<file>.lua`。
5. `WoWTools` 为本次导出保存一份契约快照。
6. `WoWPlugin` 继续按原有方式消费导出的 Lua 数据文件。

## 6. 目录规范

### 6.1 契约目录

权威契约目录固定为：

```text
WoWPlugin/DataContracts/
```

### 6.2 契约文件命名

契约文件命名规则固定为：

```text
WoWPlugin/DataContracts/<contract_id>.json
```

例如：

```text
WoWPlugin/DataContracts/instance_map_ids.json
WoWPlugin/DataContracts/instance_drops_mount.json
WoWPlugin/DataContracts/encounter_journal_questlines.json
```

要求：

1. 文件名必须等于 `contract_id + ".json"`。
2. 不额外维护 `index.json`。
3. 由 `contract_id` 直接推导文件路径，不允许扫描目录反查。

## 7. 契约文件顶层结构

每份契约文件至少包含以下 5 个顶层区块：

1. `contract`
2. `output`
3. `source`
4. `structure`
5. `validation`

建议同时包含：

6. `versioning`

### 7.1 `contract`

最小字段：

- `contract_id`
- `schema_version`
- `summary`
- `source_of_truth`
- `status`

说明：

- `source_of_truth` 固定为 `WoWPlugin`
- `status` 枚举见 §11

### 7.2 `output`

最小字段：

- `lua_file`
- `lua_table`
- `write_header`

说明：

- `lua_file` 必须落在 `Toolbox/Data/` 下
- `lua_table` 为最终导出的 Lua 根表路径

### 7.3 `source`

最小字段：

- `database`
- `tables`
- `sql`
- `query`

说明：

- `sql` 是 v1 唯一执行主路径
- `query` 是结构化语义定义，用于审查和校验

### 7.4 `structure`

最小字段：

- `root_type`
- `lua_shape`
- `fields`

按不同 `root_type` 可追加：

- `key_field`
- `value_field`
- `comment_field`
- `document_blocks`

### 7.5 `validation`

最小字段：

- `required_fields`
- `unique_keys`
- `non_null_fields`
- `sort_rules`

### 7.6 `versioning`

最小字段：

- `current_schema_version`
- `change_log`

说明：

- `current_schema_version` 必须等于 `contract.schema_version`
- `change_log` 最后一项必须对应当前版本

## 8. 契约执行模型

### 8.1 `source.sql`

职责：

- 负责“怎么取出行数据”

规则：

1. 是 v1 唯一执行主路径。
2. 必须返回标准化结果列。
3. 不负责定义最终 Lua 结构。

### 8.2 `source.query`

职责：

- 负责“查询语义是什么”

规则：

1. 是必填项。
2. 在 v1 中不直接执行。
3. 用于审查、lint 和一致性校验。

最小建议字段：

- `from`
- `joins`
- `select`
- `where`
- `group_by`
- `order_by`
- `row_granularity`

### 8.3 `structure`

职责：

- 负责“结果行如何被渲染成 Lua”

规则：

1. 是唯一输出结构主路径。
2. 只能引用 SQL 结果中的标准化字段别名。
3. 不允许直接引用数据库原始列名作为结构层绑定。

### 8.4 结果字段别名规则

推荐规则：

1. SQL 先将数据库字段标准化为契约内部字段别名。
2. `structure` 与 `validation` 只引用这些标准化字段别名。

例如：

```sql
SELECT
  ID AS journal_instance_id,
  MapID AS map_id,
  Name_lang AS comment_name
FROM journalinstance
```

此时结构层只允许引用：

- `journal_instance_id`
- `map_id`
- `comment_name`

### 8.5 支持的渲染模式

v1 只支持受限固定模式：

1. `map_scalar`
2. `map_object`
3. `map_array`
4. `document`

不支持：

- 任意 Lua 模板
- 在契约中嵌入可执行 Lua 脚本

## 9. Lua 文件头规范

### 9.1 作用

Lua 文件头只承担以下职责：

1. 标识该文件对应的 `contract_id`
2. 标识该文件对应的 `schema_version`
3. 指向权威契约文件
4. 指向本次导出的契约快照
5. 明确这是工具生成文件

文件头不是主契约定义来源。

### 9.2 必填字段

每个导出的 `Toolbox/Data/*.lua` 文件头必须包含：

- `@contract_id`
- `@schema_version`
- `@contract_file`
- `@contract_snapshot`
- `@generated_at`
- `@generated_by`
- `@data_source`
- `@summary`
- `@overwrite_notice`

### 9.3 推荐模板

```lua
--[[
@contract_id instance_map_ids
@schema_version 1
@contract_file WoWPlugin/DataContracts/instance_map_ids.json
@contract_snapshot WoWTools/outputs/toolbox/contract_snapshots/instance_map_ids/instance_map_ids__schema_v1__20260411T102233Z.json
@generated_at 2026-04-11T10:22:33Z
@generated_by WoWTools/scripts/export_contract.py
@data_source wow.db
@summary 副本 journalInstanceID 到 MapID 的静态映射
@overwrite_notice 此文件由工具生成，手改会被覆盖
]]
```

### 9.4 校验规则

以下情况必须失败：

1. 文件头缺失
2. 任一必填标签缺失
3. `@contract_id` 与契约文件名不一致
4. `@schema_version` 与契约版本不一致
5. `@contract_file` 与权威契约路径不一致
6. 字段重复、未知或格式非法

## 10. 契约快照规范

### 10.1 快照目录

快照目录固定为：

```text
WoWTools/outputs/toolbox/contract_snapshots/<contract_id>/
```

### 10.2 快照文件命名

命名规则：

```text
<contract_id>__schema_v<schema_version>__<YYYYMMDDTHHMMSSZ>.json
```

例如：

```text
WoWTools/outputs/toolbox/contract_snapshots/instance_map_ids/instance_map_ids__schema_v1__20260411T102233Z.json
```

### 10.3 快照内容

规则：

1. 原样复制 `WoWPlugin/DataContracts/<contract_id>.json`
2. 不在快照文件内注入额外字段
3. 不允许人工修改
4. 仅用于回溯和问题排查

快照不是权威事实来源，不允许反向覆盖 `WoWPlugin/DataContracts/`。

## 11. 版本治理

### 11.1 `contract_id` 规则

1. 一旦创建，不允许重命名。
2. 一旦绑定某种数据职责，不允许改作他用。
3. 所有结构演进都在同一个 `contract_id` 下进行。

### 11.2 `schema_version` 递增规则

只要 Lua 结构发生变化，就必须提升 `schema_version`。

结构变化包括：

1. 根结构类型变化
2. 字段新增、删除、重命名
3. 字段类型变化
4. key/value 规则变化
5. 嵌套层级变化
6. 会影响稳定输出的排序规则变化
7. `document` 结构中的块定义变化

以下情况默认不升版本：

1. 仅数据内容变化
2. SQL 优化但输出结构不变
3. 注释变化
4. 时间戳、快照路径变化
5. 不影响结构的校验增强

### 11.3 版本状态

`contract.status` 支持：

- `draft`
- `active`
- `deprecated`
- `retired`

规则：

1. `draft`：草稿，不进入正式导出
2. `active`：正式可导出
3. `deprecated`：仍可导出，但不建议新增依赖
4. `retired`：不允许继续正式导出，仅保留历史记录

### 11.4 升级流程

标准流程：

1. 更新 `WoWPlugin/DataContracts/<contract_id>.json`
2. `schema_version + 1`
3. 更新 `versioning.change_log`
4. 更新 `source` / `structure` / `validation`
5. 执行导出
6. 生成新的 Lua 文件和快照
7. 更新插件消费端测试

## 12. 门禁与校验

### 12.1 契约静态校验

新增或修改契约文件时，至少校验：

1. 文件名与 `contract_id` 一致
2. `contract_id` 字符集合法
3. `schema_version` 为正整数
4. `status` 枚举合法
5. `output.lua_file` 位于 `Toolbox/Data/`
6. `source.sql` 非空
7. `source.query` 非空
8. `structure` 非空
9. `validation` 非空
10. `versioning.current_schema_version` 与当前版本一致

### 12.2 导出执行校验

导出时至少校验：

1. 契约状态允许导出
2. SQL 可执行
3. 结果列名满足 `structure`
4. 结果列名满足 `validation`
5. `source.query` 与实际结果不冲突
6. 结构可完整渲染为 Lua

### 12.3 结果一致性校验

Lua 文件写出后至少校验：

1. 文件头存在且完整
2. 文件头中的 `contract_id` 一致
3. 文件头中的 `schema_version` 一致
4. 根表名与 `output.lua_table` 一致
5. 文件路径与 `output.lua_file` 一致
6. 快照路径存在

### 12.4 插件消费端校验

只要某契约被插件消费，就必须至少有最小消费校验，验证：

1. Lua 文件可加载
2. 根表存在
3. 关键字段存在
4. 关键结构满足预期
5. 若消费端要求特定结构版本，应显式断言

### 12.5 强失败清单

以下情况必须失败：

1. 契约文件缺字段
2. `contract_id` 与文件名不一致
3. `schema_version` 非法
4. `source.sql` 执行失败
5. `structure` 引用不存在字段
6. `validation` 失败
7. Lua 文件头缺失或不一致
8. 契约状态不允许导出
9. 结构变化但未提升 `schema_version`
10. 插件消费端校验失败

## 13. 新增与修改流程

### 13.1 新增契约

新增导出契约的完成门禁：

1. 已创建 `WoWPlugin/DataContracts/<contract_id>.json`
2. 静态校验通过
3. 导出执行成功
4. 已写入目标 Lua 文件
5. 已生成契约快照
6. Lua 文件头完整且一致
7. 插件侧已有最小消费校验

### 13.2 修改契约

修改现有契约时的完成门禁：

1. 静态校验通过
2. 若结构变化，已提升 `schema_version`
3. `change_log` 已更新
4. 导出执行成功
5. 新 Lua 文件与契约一致
6. 相关消费校验已更新并通过

### 13.3 退役契约

退役流程：

1. 将状态改为 `deprecated` 或 `retired`
2. 更新 `change_log`
3. 检查插件是否仍有消费代码
4. 若仍被消费，不允许进入 `retired`
5. `retired` 契约默认拒绝继续正式导出

## 14. 推荐实现分层

本设计采用：

- 规范目标：强契约规范
- 表达方式：分层契约规范

含义是：

1. 规范上要求契约足够强，可直接驱动导出。
2. 契约 JSON 结构上分层表达，避免将身份、查询、结构、门禁混杂在一起。

这比“只写说明文档 + 工具侧手写导出规则”更强，也比“一开始引入完整 DSL 和任意模板脚本”更稳。

## 15. 推荐落地顺序

建议分阶段实现：

### 阶段 1

1. 固定目录和命名规则
2. 定义契约 JSON 基础字段
3. 定义 Lua 文件头模板
4. 支持单契约导出

### 阶段 2

1. 支持契约静态校验
2. 支持导出快照留档
3. 支持 `structure` 驱动基础渲染模式
4. 支持强失败门禁

### 阶段 3

1. 支持全量契约导出
2. 支持插件消费端契约校验
3. 对既有导出规则逐步迁移

## 16. 设计结论

本规范的最终结论是：

1. `WoWPlugin/DataContracts/<contract_id>.json` 是唯一权威契约文件。
2. 每个导出数据文件必须独立契约、独立文件、独立版本治理。
3. `contract_id` 稳定不变，结构变化统一通过 `schema_version` 递增。
4. `WoWTools` 只负责解析契约、导出结果、保存快照，不负责定义契约。
5. 导出的 Lua 文件头必须携带 `contract_id`、`schema_version` 和快照信息。
6. 所有契约新增、修改、退役都必须经过静态校验、导出校验、结果一致性校验和消费端校验。

该设计作为后续 implementation plan 的基线。
