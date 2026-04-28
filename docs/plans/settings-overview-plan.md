# 设置总览页移除效果预览计划

- 文档类型：计划
- 状态：已完成
- 主题：settings-overview
- 适用范围：`Toolbox/UI/SettingsHost.lua` 设置总览页效果预览区删除、相关本地化清理与验证
- 关联模块：无
- 关联文档：
  - `docs/specs/settings-overview-spec.md`
  - `docs/Toolbox-addon-design.md`
- 最后更新：2026-04-29

## 1. 目标

- 以测试先行的最小改动移除设置总览页中的整块“效果预览”，并清理对应死代码与文案。

## 2. 输入文档

- 需求：
  `docs/specs/settings-overview-spec.md`
- 设计：
  `docs/Toolbox-addon-design.md`
- 其他约束：
  - 只改设置总览页，不改 `tooltip_anchor` 与 `mover` 模块行为。
  - 先补失败测试，再删除业务代码。
  - 不新增模块、入口或 TOC。

## 3. 影响文件

- 新增：
  - `docs/specs/settings-overview-spec.md`
  - `docs/plans/settings-overview-plan.md`
- 修改：
  - `tests/validate_settings_subcategories.py`
  - `Toolbox/UI/SettingsHost.lua`
  - `Toolbox/Core/Foundation/Locales.lua`
- 验证：
  - `python tests/validate_settings_subcategories.py`
  - `python tests/run_all.py --ci`

## 4. 执行步骤

- [x] 步骤 1：把用户已确认的“主页整块删除效果预览”结果写入需求 / 计划文档。
- [x] 步骤 2：先修改 `tests/validate_settings_subcategories.py`，锁定总览页不再调用或保留“效果预览”相关实现。
- [x] 步骤 3：运行 `python tests/validate_settings_subcategories.py`，确认当前代码按预期失败。
- [x] 步骤 4：删除 `Toolbox/UI/SettingsHost.lua` 中的预览区构建函数与总览页调用。
- [x] 步骤 5：删除 `Toolbox/Core/Foundation/Locales.lua` 中仅供该预览区使用的文案键。
- [x] 步骤 6：运行 `python tests/validate_settings_subcategories.py` 与 `python tests/run_all.py --ci`，确认改动通过验证。

## 5. 验证

- 命令 / 检查点 1：
  `python tests/validate_settings_subcategories.py`
- 命令 / 检查点 2：
  `python tests/run_all.py --ci`
- 游戏内验证点：
  打开 `/toolbox` 后，总览页不再显示“效果预览”整块；左侧模块子页仍可正常进入。

## 6. 风险与回滚

- 风险：
  - 若只删总览页调用而不清理函数与文案，容易留下死代码与无用本地化键。
  - 若误删模块子页共用文案，可能影响其它设置页显示。
- 回滚方式：
  - 回退本次“设置总览页移除效果预览”提交，恢复总览页预览区与相关文案。

## 7. 执行记录

- 2026-04-29：用户确认需求是“设置主页移除提示框锚点”。
- 2026-04-29：进一步确认实际目标为“移除主页中的整块效果预览”。
- 2026-04-29：用户选定方案 B：删除总览页调用、删除构建函数并清理对应文案。
- 2026-04-29：用户回复“开动”，文档状态已转入可执行/执行中。
- 2026-04-29：`python tests/validate_settings_subcategories.py` 先按预期失败，失败点为 `SettingsHost` 仍保留 `BuildPreviewSection`。
- 2026-04-29：已删除 `SettingsHost` 预览区实现与 `Locales` 中对应 `SETTINGS_PREVIEW_*` 键。
- 2026-04-29：`python tests/run_all.py --ci` 最终通过，逻辑测试 `124 successes / 0 failures / 0 errors / 0 pending`。

## 8. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-29 | 初稿：记录本次设置总览页效果预览移除的执行步骤与验证命令 |
| 2026-04-29 | 执行完成：步骤全勾选，补记失败测试与最终通过结果 |
