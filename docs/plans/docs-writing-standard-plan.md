# docs 写作规范落地计划

- 文档类型：计划
- 状态：已完成
- 主题：docs-writing-standard
- 适用范围：`docs/**`
- 关联模块：无
- 关联文档：
  - `docs/designs/docs-writing-standard-design.md`
  - `docs/DOCS-STANDARD.md`
- 最后更新：2026-04-12

## 1. 目标

- 为 `docs/**` 落地统一的需求、设计、计划、测试文档规范，并把入口文档回写到强制使用该规范。

## 2. 输入文档

- 需求：用户当前对“文档规范 + 模板 + 目录规则”的明确要求。
- 设计：`docs/designs/docs-writing-standard-design.md`
- 其他约束：仅修改 `docs/**`，不处理业务代码与历史文档批量迁移。

## 3. 影响文件

- 新增：
  - `docs/DOCS-STANDARD.md`
  - `docs/templates/spec-template.md`
  - `docs/templates/design-template.md`
  - `docs/templates/plan-template.md`
  - `docs/templates/test-template.md`
  - `docs/designs/docs-writing-standard-design.md`
  - `docs/plans/docs-writing-standard-plan.md`
- 修改：
  - `docs/AI-ONBOARDING.md`
  - `docs/FEATURES.md`

## 4. 执行步骤

- [x] 梳理现有 `docs/**` 目录与文档类型混写问题。
- [x] 定义规范文档中的目录边界、命名规则、状态流转和禁止项。
- [x] 新增需求、设计、计划、测试四类模板。
- [x] 回写 `docs/AI-ONBOARDING.md`，把规范纳入读档路径与文档分层。
- [x] 回写 `docs/FEATURES.md`，声明其只承载产品功能总览。

## 5. 验证

- 检查 `docs/DOCS-STANDARD.md` 是否包含目录、命名、模板、状态、迁移规则。
- 检查 `docs/templates/` 是否已存在四类模板。
- 检查 `docs/AI-ONBOARDING.md` 是否引用 `DOCS-STANDARD.md` 并更新目录结构。
- 检查 `docs/FEATURES.md` 是否声明自身边界。

## 6. 风险与回滚

- 风险：历史目录仍会保留，短期内仓库中存在新旧规范并存。
- 回滚方式：如需回退，只需撤销本次新增规范与入口文档改写，不影响业务代码。

## 7. 执行记录

- 本次改动仅涉及 `docs/**`，未触碰当前工作区中的业务代码脏改动。
- 历史目录未批量迁移，按规范改为“禁止新增、后续续写时迁移”。

## 8. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-12 | 初稿并完成本轮规范落地 |
| 2026-04-12 | 文件名按新规则改为 `docs-writing-standard-plan.md`，关联引用同步调整 |
