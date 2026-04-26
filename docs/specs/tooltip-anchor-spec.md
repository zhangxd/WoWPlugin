# Tooltip 锚点默认锚点回退需求

- 文档类型：需求
- 状态：可执行
- 主题：tooltip-anchor
- 适用范围：`tooltip_anchor` 模块恢复 WoWTools 式 `GameTooltip_SetDefaultAnchor` 全局 hook、鼠标附近锚点行为与相关回归验证
- 关联模块：`tooltip_anchor`
- 关联文档：
  - `docs/plans/tooltip-anchor-plan.md`
  - `docs/Toolbox-addon-design.md`
- 最后更新：2026-04-27

## 1. 背景

- 当前仓库里的 `tooltip_anchor` 已改为 `UberTooltips` CVar 托管方案，用来规避正式服 12.0 secret values / secure delegates 下的 tooltip taint。
- 用户现已明确要求：放弃这条安全方案，**完全回退**到 WoWTools 现用的实现思路，即继续全局接管 `GameTooltip_SetDefaultAnchor`。
- 用户同时明确确认新的验收口径：本轮以“跟随鼠标行为回退”为先，正式服 12.0 的 secret-value taint 风险**接受**，不作为本轮失败标准。
- 用户补充约束：本轮回退不得留下 `UberTooltips` 托管方案的旧逻辑、旧字段、旧测试口径或旧文档说明残留。

## 2. 目标

- 恢复 `tooltip_anchor` 的全局默认锚点 hook 行为，让系统 tooltip 重新按鼠标附近方式显示。
- 保留现有模块归属与设置入口，不新增模块、不新增玩家可见入口、不改 TOC。
- 清理 `UberTooltips` 托管方案留下的旧实现与旧口径，避免代码残留。
- 为回退后的行为补上或改写自动化测试，锁定回退口径。

## 3. 范围

### 3.1 In Scope

- 在 `Toolbox/Core/API/Tooltip.lua` 中恢复 `GameTooltip_SetDefaultAnchor` 的全局 post-hook。
- `tooltip_anchor` 继续使用现有 `default` / `cursor` / `follow` 设置值；本轮不扩展新的玩家可见模式。
- 沿用 `modules.tooltip_anchor` 现有数据落点；如存在 `UberTooltips` 托管遗留字段，须在 `Core/Foundation/Config.lua` 迁移中清理。
- 新增或改写逻辑测试，覆盖“注册全局 hook”“`cursor/follow` 时改为鼠标附近锚点”“`default` 或模块禁用时不接管”“旧 `UberTooltips` 方案残留被移除”。
- 同步更新需求、计划与总设计文档，使文档与代码口径一致。

### 3.2 Out of Scope

- 不新增 `RegisterModule`、不新增玩家入口、不修改 `Toolbox/Toolbox.toc`。
- 不保证正式服 12.0 的 secret-value taint 被修复；该风险已由用户接受。
- 不在本轮引入额外的 per-frame 跟随算法或新的 tooltip 驱动层。

## 4. 已确认决策

- 本次变更归属模块为 `tooltip_anchor`。
- 主方案选定为：恢复 WoWTools 式 `GameTooltip_SetDefaultAnchor` 全局 hook，而不是继续使用 `UberTooltips` 托管。
- 验收以“行为回退”为准：tooltip 跟随鼠标恢复即可；即使重新出现正式服 12.0 的 taint，也不作为本轮失败。
- 本轮不允许有代码残留：`UberTooltips` 托管逻辑、原值缓存字段、相关测试断言与文档说明都须一起清理。
- 改动边界限定为：只修改现有模块、核心实现、测试与必要文档；不新增模块、不新增入口、不改 TOC。

## 5. 待确认项

- 无。用户已确认模块归属、主方案、验收标准与“无代码残留”约束，可以进入实现。

## 6. 验收标准

1. `tooltip_anchor` 在 `cursor` 或 `follow` 模式时，会通过 `GameTooltip_SetDefaultAnchor` 全局 post-hook 把 tooltip 接管到鼠标附近锚点。
2. `tooltip_anchor` 在 `default` 模式或模块禁用时，不再覆写默认锚点行为。
3. 仓库中不再保留 `UberTooltips` 托管方案的运行时逻辑、原值缓存字段或以该方案为前提的测试口径。
4. 与本次回退相关的逻辑测试能够先在当前代码上失败，再在回退实现完成后通过。
5. 若正式服 12.0 下重新出现 `execution tainted by 'Toolbox'`，不视为本轮验收失败。

## 7. 实施状态

- 当前状态：可执行
- 下一步：先更新测试使其锁定“全局 hook 回退”口径并验证失败，再修改业务代码。

## 8. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-26 | 历史版本：曾记录 secret values 热修复与 `UberTooltips` 托管方案 |
| 2026-04-27 | 用户重新选定主方案：完全回退到全局 `GameTooltip_SetDefaultAnchor` hook，并接受 taint 风险 |
| 2026-04-27 | 补充硬约束：不得留下 `UberTooltips` 托管方案的代码、测试或文档残留；状态改为 `可执行` |
