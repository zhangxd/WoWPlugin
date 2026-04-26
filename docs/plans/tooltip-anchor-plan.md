# Tooltip 锚点全局默认锚点回退计划

- 文档类型：计划
- 状态：可执行
- 主题：tooltip-anchor
- 适用范围：`tooltip_anchor` 模块回退到全局 `GameTooltip_SetDefaultAnchor` hook 的实现、旧 `UberTooltips` 托管残留清理与相关验证
- 关联模块：`tooltip_anchor`
- 关联文档：
  - `docs/specs/tooltip-anchor-spec.md`
  - `docs/Toolbox-addon-design.md`
- 最后更新：2026-04-27

## 1. 目标

- 通过测试先行的最小改动，把 `tooltip_anchor` 从 `UberTooltips` 托管方案回退到 WoWTools 式全局默认锚点 hook。
- 在回退时一并清理旧方案的运行时逻辑、存档字段、测试断言与文档说明，不留代码残留。

## 2. 输入文档

- 需求：
  `docs/specs/tooltip-anchor-spec.md`
- 设计：
  `docs/Toolbox-addon-design.md` 第 5.4 节
- 其他约束：
  - 不新增模块、入口或 TOC。
  - 先补失败测试，再修改业务代码。
  - 用户已接受正式服 12.0 secret-value taint 风险，本轮不以“无 taint”作为验收条件。
  - 旧 `UberTooltips` 托管方案不得有残留，包括代码路径、默认值/迁移字段、测试口径与文档描述。

## 3. 影响文件

- 修改：
  - `docs/specs/tooltip-anchor-spec.md`
  - `docs/plans/tooltip-anchor-plan.md`
  - `docs/Toolbox-addon-design.md`
  - `Toolbox/Core/Foundation/Config.lua`
  - `Toolbox/Core/API/Tooltip.lua`
  - `tests/logic/spec/tooltip_anchor_spec.lua`
- 按需修改：
  - `tests/logic/harness/fake_tooltip.lua`
- 验证：
  - `busted tests/logic/spec/tooltip_anchor_spec.lua`
  - `python tests/run_all.py --ci`

## 4. 执行步骤

- [x] 步骤 1：把用户已确认的“完全回退 + 接受 taint 风险 + 不得有代码残留”写入需求 / 计划 / 总设计文档，并把状态改为 `可执行`。
- [ ] 步骤 2：先修改 `tests/logic/spec/tooltip_anchor_spec.lua`，锁定“注册全局 hook”“`cursor/follow` 改写为鼠标附近锚点”“`default/禁用` 不接管”“旧 `UberTooltips` 残留被移除”四条行为。
- [ ] 步骤 3：运行 `busted tests/logic/spec/tooltip_anchor_spec.lua`，确认当前代码按预期失败。
- [ ] 步骤 4：在 `Toolbox/Core/API/Tooltip.lua` 中恢复 `GameTooltip_SetDefaultAnchor` 全局 hook，并移除 `UberTooltips` 托管逻辑。
- [ ] 步骤 5：在 `Toolbox/Core/Foundation/Config.lua` 中清理旧 `UberTooltips` 托管字段的默认值与迁移残留。
- [ ] 步骤 6：重新运行 `busted tests/logic/spec/tooltip_anchor_spec.lua` 与 `python tests/run_all.py --ci`，确认回退后的行为与回归测试结果。

## 5. 验证

- 命令 / 检查点 1：
  `busted tests/logic/spec/tooltip_anchor_spec.lua`
- 命令 / 检查点 2：
  `python tests/run_all.py --ci`
- 游戏内验证点：
  在正式服里，把 `tooltip_anchor` 设为 `cursor` 或 `follow` 后，系统 tooltip 恢复到鼠标附近；切回 `default` 或禁用模块后，恢复默认锚点行为。

## 6. 风险与回滚

- 风险：
  - 正式服 12.0 secret values / secure delegates 场景下，背包物品、世界任务等系统 tooltip 可能重新出现 `execution tainted by 'Toolbox'`。
  - 删除旧 `UberTooltips` 方案时若清理不完整，容易留下无用存档键、死代码或失效测试。
- 回滚方式：
  - 若需要恢复到安全方案，整体回退本轮“全局 hook 回退”提交，而不是只局部恢复 CVar 逻辑，避免仓库同时残留两套驱动。

## 7. 执行记录

- 2026-04-27：用户确认模块归属仍为 `tooltip_anchor`。
- 2026-04-27：用户确认主方案为“完全回退到 WoWTools 式全局 `GameTooltip_SetDefaultAnchor` hook”。
- 2026-04-27：用户确认验收以“行为回退”为准，正式服 12.0 taint 风险接受。
- 2026-04-27：用户补充硬约束“不要有代码残留”，计划据此要求同步清理旧 `UberTooltips` 托管方案。

## 8. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-26 | 历史版本：曾用于执行 secret values 热修复与 `UberTooltips` 托管方案 |
| 2026-04-27 | 重写为“全局默认锚点回退计划”，同步写入用户确认结果并将状态改为 `可执行` |
