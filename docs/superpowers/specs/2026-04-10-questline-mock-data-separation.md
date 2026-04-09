# 任务线数据源分离规范（Mock / Live）

- 日期：2026-04-10
- 状态：已落地（含 live 数据容错策略）
- 范围：`Toolbox`（Retail）
- 关联模块：`encounter_journal`、`QuestlineProgress`

## 1. 背景与动机

`InstanceQuestlines.lua` 由 `WoWDB/scripts/toolbox_db_export.py` 全量生成（live 数据）。
测试阶段需要一份小型、可控的 mock 数据集，但不能与 live 文件共存于同一文件中，
原因：

1. 导出脚本每次运行会覆盖 live 文件，手写的 mock 内容会丢失。
2. 同文件切换（改 `sourceMode` 字段）无法防止误改 live 数据。
3. mock 数据应由测试框架显式注入，生产代码路径不应感知 mock 的存在。

## 2. 文件结构

```
WoWPlugin/
  Toolbox/
    Data/
      InstanceQuestlines.lua          ← live 数据（脚本生成，禁止手改）
    Core/
      API/
        QuestlineProgress.lua         ← 含注入点 SetDataOverride

tests/
  logic/
    fixtures/
      InstanceQuestlines_Mock.lua     ← mock 数据（测试专用，手写维护）
    spec/
      questline_progress_spec.lua     ← 使用 mock 数据的测试用例
      questline_progress_live_data_spec.lua ← live 数据容错用例
```

**关键约束：**

- `InstanceQuestlines_Mock.lua` 不在 `Toolbox.toc` 中出现。
- mock 文件只由测试框架通过 `dofile` 加载，生产环境不加载。
- live 文件由脚本生成，mock 文件独立手写维护，两者互不干扰。

## 3. 数据注入接口

`QuestlineProgress.lua` 暴露一个注入点，仅供测试框架调用：

```lua
--- 覆盖数据源（仅供测试框架调用）。传 nil 恢复 live 数据源。
---@param dataTable table|nil
function Toolbox.Questlines.SetDataOverride(dataTable)
  dataOverrideTable = dataTable
  resetRuntimeCache()
end
```

`getQuestlineDataTable()` 内部逻辑：

```lua
local function getQuestlineDataTable()
  if dataOverrideTable ~= nil then
    return dataOverrideTable
  end
  return Toolbox.Data and Toolbox.Data.InstanceQuestlines
end
```

生产代码路径中不存在任何 `mockMode` 判断或 `DevConfig` 依赖。

## 4. Mock 文件规范

### 4.1 位置与命名

```
tests/logic/fixtures/InstanceQuestlines_Mock.lua
```

### 4.2 Schema 要求

mock 文件必须与 live 文件使用完全相同的 schema（v3），通过同一套 `ValidateInstanceQuestlinesData` 校验。

```lua
-- tests/logic/fixtures/InstanceQuestlines_Mock.lua
-- 此文件为测试专用 mock 数据，不进入 Toolbox.toc，不由导出脚本生成。
-- schema 与 InstanceQuestlines.lua（live）完全一致。

local mockData = {
  schemaVersion = 3,
  sourceMode = "mock",
  generatedAt = "2026-01-01T00:00:00Z",

  quests = {
    [84956] = { ID = 84956, UiMapID = 2371 },
    [84957] = { ID = 84957, UiMapID = 2371 },
    [84958] = { ID = 84958, UiMapID = 2371 },
  },

  questLines = {
    [5531] = { ID = 5531, Name_lang = "Mock QuestLine A", UiMapID = 2371 },
  },

  questLineQuestIDs = {
    [5531] = { 84956, 84957, 84958 },
  },
}

return mockData
```

### 4.3 维护原则

1. 数据量保持最小（3-5 条任务线，每线 3-5 个任务），够覆盖测试场景即可。
2. 字段值可以是虚构的，但类型和结构必须合法（能通过 strict 校验）。
3. `sourceMode` 必须为 `"mock"`，`schemaVersion` 必须为 `3`。
4. 不得引用 live 文件中的真实 ID（防止测试结果依赖 live 数据变化）。

## 5. 测试框架使用约定

```lua
-- tests/logic/spec/questline_progress_spec.lua（示意）

local mockData = dofile("tests/logic/fixtures/InstanceQuestlines_Mock.lua")

describe("Toolbox.Questlines", function()
  before_each(function()
    Toolbox.Questlines.SetDataOverride(mockData)
  end)

  after_each(function()
    Toolbox.Questlines.SetDataOverride(nil)
  end)

  -- 测试用例...
end)
```

**约定：**

1. 每个 `describe` 块必须在 `before_each` 注入、`after_each` 清除，保证用例隔离。
2. 不得在用例内直接修改 `mockData` 表（防止用例间污染）；需要变体数据时，构造局部副本后注入。
3. 普通单元用例不得 `require` 或 `dofile` live 数据文件。
4. 例外：`questline_progress_live_data_spec.lua` 允许显式加载 live 文件，用于验证“线上数据异常时任务页签仍可降级可用”。

## 6. 与现有测试规划的关系

本规范是 `2026-04-09-logic-test-harness-backlog.md` 的补充，专门描述任务线数据源的分离策略。

- harness 文件（`fake_runtime.lua` 等）负责模拟 WoW 运行时 API。
- fixtures 文件（`InstanceQuestlines_Mock.lua`）负责提供静态数据。
- 两者独立，互不依赖。

## 7. 不做的事

1. 不在 `Toolbox.toc` 中加载 mock 文件。
2. 不在生产代码中添加 `mockMode` 开关或 `DevConfig`。
3. 不将 mock 数据内联到测试用例文件中（保持 fixtures 独立可复用）。
4. 不为 mock 文件建立导出脚本（mock 数据手写维护）。

## 8. 运行时容错（已落地）

在 `QuestlineProgress.buildQuestTabModel` 中：

1. 保留 strict 校验作为结构正确性防线。
2. 当错误码属于可恢复类型（`E_BAD_REF` / `E_DUPLICATE_REF`）时，不让整个任务页签失败。
3. 继续构建可用子集模型，避免 UI 直接进入“任务数据无效”。
4. 非可恢复结构错误（如根字段缺失、类型错误）仍按原逻辑返回错误对象。

## 9. 验证基线

1. `tests/logic/spec/questline_progress_spec.lua`：验证 mock 注入与回退 live。
2. `tests/logic/spec/questline_progress_live_data_spec.lua`：验证 live 数据存在坏引用时模型仍可用。
3. `python tests/run_all.py` 作为统一回归入口。
