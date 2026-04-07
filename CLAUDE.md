# Claude AI 协作规范（精简版）

> 完整规范见 [AGENTS.md](AGENTS.md)

## 强制检查清单（每次收到需求必做）

### ✓ 三关检查（按顺序，任一不通则停）

```
□ 关 1 · 需求是否明确？
  - 有模块 id？有验收标准？有边界？
  - 否 → 提 1-3 个封闭式问题，等用户回答
  - 不得进入关 2

□ 关 2 · 数据来源/主方案是否已选定？
  - 静态表由谁生成？主键以哪个 ID 为准？
  - 否 → 列待决项清单，等用户选定
  - 不得进入关 3

□ 关 3 · 是否触发新功能门禁？
  触发条件（满足任一）：
    • 新 RegisterModule 模块（新 moduleId）
    • 新玩家可见入口（新菜单项、新按钮、新命令）
    • Toolbox.toc 新增行
  
  触发 → 先给方案评估：
    - 领域归属：[tooltip/chat/settings/...]
    - 数据落点：[ToolboxDB.modules.xxx]
    - 与现有 API 关系：[新建/扩展 Toolbox.Xxx]
    - 验收要点：[列表]
    - 待确认项：[列表]
  
  → 输出"请确认是否开动"
  → 等用户明确说「开动」
  → 禁止在方案评估的同一回复中调用 Write/Edit/TodoWrite

□ 三关全通过 → 才能修改业务代码
```

---

## 禁止行为（始终强制）

- ❌ 未经关 1/2/3 直接修改 `Toolbox/Core/**`、`Toolbox/Modules/**`、`Toolbox/UI/**`、`Toolbox.toc`
- ❌ 未调用工具前说"我马上开始改"之类承诺
- ❌ 用"技术上能直接做"替代澄清步骤
- ❌ 数据来源未选定时以"是否现在实现"收尾
- ❌ 关 3 触发后，在方案评估的同一回复中调用修改工具

---

## 快速参考

- **领域对外 API**：`Toolbox.Chat`、`Toolbox.Tooltip`、`Toolbox.Config` 等
- **模块注册**：`Toolbox.RegisterModule({ id, nameKey, ... })`
- **存档位置**：`ToolboxDB.modules.<moduleId>`
- **本地化**：`Toolbox.L.键名`（定义在 `Core/Locales.lua`）
- **完整规范**：[AGENTS.md](AGENTS.md)
- **架构文档**：[docs/Toolbox-addon-design.md](docs/Toolbox-addon-design.md)
- **协作流程**：[docs/AI-ONBOARDING.md](docs/AI-ONBOARDING.md)

---

## 例外

不经三关可直接执行：
- 纯错别字修正
- 与行为无关的注释修正
- 仅文档内链接修正
