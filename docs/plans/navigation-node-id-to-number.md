# 导航节点不透明数字 ID 迁移计划

- 文档类型：计划
- 状态：已完成
- 主题：navigation-node-id-to-number
- 适用范围：`navigation` 模块运行时节点 ID；`navigation_route_edges` / `navigation_ability_templates` 导出链路；导航相关逻辑测试
- 关联模块：`navigation`
- 关联文档：
  - `docs/specs/navigation-spec.md`
  - `docs/designs/navigation-design.md`
  - `docs/plans/navigation-plan.md`
- 最后更新：2026-04-30

## 1. 目标

- 将导航运行时消费的节点引用从复合字符串（如 `"uimap_85"`）迁移为不透明数字 ID。
- 运行时不得再通过字符串拼接、范围判断或 offset 规则推导节点来源、节点类型或原始 ID。
- 需要按 `(来源, 原始 ID)` 定位节点时，统一走导出索引表，而不是临时拼接旧字符串键。

## 2. 输入文档

- 需求 / 设计基线：
  - `docs/specs/navigation-spec.md`
  - `docs/designs/navigation-design.md`
  - `docs/plans/navigation-plan.md`
- 用户确认：
  - 2026-04-30，需求方确认按“不透明数字 ID”方案推进。
- 执行约束：
  - 运行时导航数据只允许来自 DataContracts 导出。
  - 节点类型判断只能依赖 `nodes[id].Kind`。
  - 任何字符串字段只用于显示，不得重新回退为业务映射键。
- 文档门禁：
  - 在需求方明确回复“开动”前，只允许修改 `docs/**`；不得修改导航业务代码、导出脚本或生成数据。

## 3. 影响文件

- 预计修改：
  - `DataContracts/navigation_route_edges.json`
  - `DataContracts/navigation_ability_templates.json`
  - `scripts/export/toolbox_db_export.py`
  - `scripts/export/lua_contract_writer.py`
  - `Toolbox/Core/API/Navigation.lua`
  - `Toolbox/Modules/Navigation/WorldMap.lua`
  - `Toolbox/Data/NavigationRouteEdges.lua`（生成）
  - `Toolbox/Data/NavigationAbilityTemplates.lua`（生成）
  - `tests/logic/spec/navigation_api_spec.lua`
  - `tests/logic/spec/navigation_data_spec.lua`
  - `tests/logic/spec/navigation_worldmap_spec.lua`
  - `tests/logic/spec/navigation_routebar_spec.lua`
  - `tests/logic/spec/navigation_module_spec.lua`
- 后续文档回写：
  - `docs/designs/navigation-design.md`
  - `docs/tests/navigation-test.md`
  - `docs/Toolbox-addon-design.md`

## 4. 已确认决策

- 导出后的运行时节点主键、`NodeID`、边上的 `FromNodeID` / `ToNodeID`、能力模板上的 `ToNodeID` 全部改为不透明数字 ID。
- 数字 ID 只表示“导出快照内的节点索引”，不承载任何来源、类型或原始 ID 语义。
- `(source, source_id) -> node_id` 的定位由导出索引表承担；运行时禁止再拼 `uimap_*` / `taxi_*` / `portal_*` / `transport_*`。
- 节点类型、地图归属、飞行点关联等附加语义，统一从节点记录字段读取，不从数字 ID 反推。

## 5. 开工前必须补齐的前置项

- 统一真值源：
  - `navigation_ability_templates` 不能独立猜测或硬编码数字 node ID，必须消费与 `navigation_route_edges` 同一次导出生成的映射结果。
- `walkCluster` 语义收口：
  - 现有 `WalkClusterKey` 是“本地步行连通域锚点键”，不是“当前节点自身 ID”。
  - 迁移后不能直接把它替换成某个原始 `UiMapID` 数字；必须导出同源的锚点节点引用（建议显式新增 `WalkClusterNodeID` 或等价字段）。
- 合成节点策略：
  - 当前运行时的 `current` / `target` 是求解器内部临时哨兵节点，不属于导出数据。
  - 本计划默认继续保留这两个运行时字符串哨兵，不把它们并入导出数字 ID 空间；若后续要统一改为数字哨兵，需要单独扩展求解器与测试范围。
- Writer / Contract 能力：
  - `navigation_route_edges` 需要新增可表达嵌套索引表的导出结构（例如 `sourceIndex`），现有 document block 结构需先补齐表达能力，再进入实现。

## 6. 执行步骤

- [x] 步骤 1：调整 `navigation_route_edges` 补全逻辑，生成统一的数字 `node_id` 分配结果，并同步产出 `sourceIndex` 与 `walkCluster` 关联字段。
- [x] 步骤 2：调整 `navigation_ability_templates` 导出逻辑，让 `fixed_node` 模板目标在同一次导出流程中解析为数字 node ID，而不是独立拼接 `uimap_*`。
- [x] 步骤 3：扩展 `DataContracts/navigation_route_edges.json` 与 `DataContracts/navigation_ability_templates.json`，并补齐 writer / validator 对新增结构和 number node ref 的支持。
- [x] 步骤 4：修改 `Toolbox/Core/API/Navigation.lua` 与 `Toolbox/Modules/Navigation/WorldMap.lua`，把运行时 lookup 从字符串拼接改为显式索引查表。
- [x] 步骤 5：更新逻辑测试 fixture 与断言，覆盖 `sourceIndex`、`walkCluster` 接线、目标地图解析、炉石 / 传送 / 传送门模板展开。
- [x] 步骤 6：重跑导出、校验与逻辑测试，并回写设计 / 测试 / 总设计文档。

## 7. 验证

- 导出：
  - `python scripts/export/export_toolbox_one.py navigation_route_edges`
  - `python scripts/export/export_toolbox_one.py navigation_ability_templates`
- 校验：
  - `python tests/validate_data_contracts.py`
  - `python tests/validate_settings_subcategories.py`
- 测试：
  - `python tests/run_all.py --ci`
- 游戏内核对点：
  - 世界地图“规划路线”仍能把目标地图解析到正确节点。
  - 传送 / 传送门 / 炉石模板边仍能落到正确地图枢纽。
  - `walk_local` 仍能把交通落点接回本地连通域锚点。

## 8. 风险与回滚

- 风险：
  - 重导出后 `NavigationRouteEdges.lua` diff 会非常大，人工 review 成本高。
  - 若 `route_edges` 与 `ability_templates` 不共享同一映射真值，模板目标会直接失配。
  - 若把 `WalkClusterKey` 错当成普通数字字段迁移，`walk_local` 动态接线会静默失效。
  - 若提前把 `current` / `target` 并入数字空间，会扩大运行时与测试回归面。
- 回滚方式：
  - 以“契约 + 导出脚本 + 生成数据 + 运行时 + 测试”作为同一原子改动回滚。
  - 在完整迁移落地前，不做半迁移发布；保持字符串 node key 方案作为唯一已发布基线。

## 9. 执行记录

- 2026-04-30：需求方确认采用“不透明数字 ID”方案。
- 2026-04-30：需求方已明确继续推进；本计划自即刻起转入可执行状态，可开始修改导航业务代码、导出产物与逻辑测试。
- 2026-04-30：已完成 `navigation_route_edges` / `navigation_ability_templates` 正式重导出，并通过导出链路 Python 单元测试；当前阻塞点收口为 navigation 逻辑测试仍存在旧字符串 node ID / `WalkClusterKey` 断言，需继续对齐数字 node ID 新口径。
- 2026-04-30：已完成 `Navigation.lua` 炉石绑定兼容层、`navigation_api_spec` / `navigation_data_spec` 新口径迁移，并通过 `python tests/run_all.py --ci`（`144 successes / 0 failures / 0 errors / 0 pending`）。

## 10. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-30 | 将“采用不透明数字 ID”写入计划，并补齐共享映射、`walkCluster`、合成节点与 writer 能力等开工前前置项 |
| 2026-04-30 | 按需求方“继续”确认把计划状态切为可执行，并补记已完成的重导出与当前测试阻塞点 |
| 2026-04-30 | 数字 node ID 迁移收尾：计划状态改为已完成，并补记 runtime 兼容层、逻辑测试迁移与全量验证结果 |
