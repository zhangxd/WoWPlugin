# 任务模块测试基线

- 文档类型：测试
- 状态：有问题
- 主题：quest
- 适用范围：`quest` 当前独立任务界面、导航、最近完成与 Quest Inspector 的自动化与手工验证基线
- 关联模块：`quest`、`minimap_button`
- 关联文档：
  - `docs/specs/quest-spec.md`
  - `docs/designs/quest-design.md`
  - `docs/plans/quest-plan.md`
- 最后更新：2026-04-16

## 1. 测试背景

- 本文档用于记录 `quest` 模块当前已落地能力的验证基线。
- 由于其中一部分能力依赖游戏内任务日志、任务缓存和实际任务交付事件，当前测试基线分为“自动化回归”和“手工游戏内验证”两部分。

## 2. 测试范围

- In Scope：
  - 静态校验与逻辑测试中覆盖到的 `quest` / `Toolbox.Questlines` 行为
  - 当前文档列出的游戏内手工验证场景
- Out of Scope：
  - 冒险指南副本列表、详情页与锁定摘要增强
  - 与任务模块无关的 Tooltip、Mover、聊天提示能力

## 3. 测试环境

- 客户端 / 版本：
  WoW Retail，Interface 以仓库当前 `Toolbox.toc` 为准
- 账号或角色条件：
  角色任务日志中存在任务；若需验证最近完成列表，需在模块启用后完成至少一条任务
- 数据前置条件：
  `Toolbox.Data.InstanceQuestlines` 已正确导出并可被插件加载
- 工具与命令：
  `python tests/run_all.py --ci`
  `"%APPDATA%\\luarocks\\bin\\busted.cmd" tests/logic/spec/quest_module_spec.lua`

## 4. 测试用例

| 编号 | 前置条件 | 操作 | 预期结果 |
|------|----------|------|----------|
| TC-AUTO-01 | 测试环境可运行 Python / busted | 执行 `python tests/run_all.py --ci` | 静态校验与逻辑测试通过 |
| TC-AUTO-02 | 已安装 `busted` 且 quest 逻辑测试可运行 | 执行 `"%APPDATA%\\luarocks\\bin\\busted.cmd" tests/logic/spec/quest_module_spec.lua` | `quest` 顶部路径导航 `NavBar` 回归用例通过 |
| TC-MANUAL-01 | 显示小地图按钮 | 点击飞出菜单“任务”入口 | 打开独立 `quest` 主界面 |
| TC-MANUAL-02 | 打开 `quest` 主界面 | 查看底部页签 | 底部显示“当前任务”“任务线”两个页签 |
| TC-MANUAL-03 | 打开 `quest` 主界面并位于“当前任务”页签 | 查看主区布局 | 不显示左树；主区改为上下两段，上方为当前任务，下方为历史完成 |
| TC-MANUAL-04 | 已启用 `quest` 模块且角色交付过任务 | 折叠 / 展开历史完成区 | 历史完成区可折叠；折叠后当前任务区占满主区 |
| TC-MANUAL-05 | 存在任务线数据 | 切到“任务线”页签并选择资料片 / 地图 / 任务线节点 | 左侧仅显示资料片 / 地图 / 任务线层级，不再混入“当前任务”；右侧显示任务线列表，点击任务线后可单展开任务列表 |
| TC-MANUAL-06 | 位于“任务线”页签且已选择某个地图或任务线节点 | 观察顶部路径导航并点击祖先节点 | 顶部路径使用 Blizzard `NavBar` 同类样式；祖先节点可点击回退，并同步刷新右侧内容 |
| TC-MANUAL-07 | 位于“任务线”页签 | 观察顶部路径导航与宿主头像 / 搜索框位置关系 | 顶部路径不会被宿主左上角头像 / 图标盖住，也不会与右上角搜索框重叠 |
| TC-MANUAL-08 | 主界面已有任务线或任务 | 在搜索框输入关键词 | 当前视图按任务线名或任务名过滤 |
| TC-MANUAL-09 | 主区存在任务项 | 悬停并点击任务 | 显示 tooltip 和详情弹框；聊天框输出运行时详情 |
| TC-MANUAL-10 | 任务详情弹框存在回跳条件 | 点击“跳转到对应地图/任务线”或“Open in Active View” | 主界面跳到目标视图并保持对应选择 |
| TC-MANUAL-11 | 打开设置页“任务详情查询”子页面 | 输入合法 `QuestID` 并点击查询 | 页面显示可复制结果文本；若需要异步加载，则在加载后自动刷新 |

## 5. 执行结果

| 编号 | 实际结果 | 结论 | 备注 |
|------|----------|------|------|
| TC-AUTO-01 | `python tests/run_all.py --ci` 失败，停在 `validate_data_contracts.py`：`instance_questlines: lua header contract_id mismatch` | 失败 | 当前为共享数据契约问题，直接影响任务数据链路验证 |
| TC-AUTO-02 | `"%APPDATA%\\luarocks\\bin\\busted.cmd" tests/logic/spec/quest_module_spec.lua` 通过；新增 `NavBarTemplate` 与锚点避让回归用例为红后转绿 | 通过 | 同轮补跑依赖 harness 的相关逻辑测试集也通过 |
| TC-MANUAL-01 | 待执行 | 待执行 | 需游戏内验证 |
| TC-MANUAL-02 | 待执行 | 待执行 | 需游戏内验证 |
| TC-MANUAL-03 | 待执行 | 待执行 | 需游戏内验证 |
| TC-MANUAL-04 | 待执行 | 待执行 | 需游戏内验证 |
| TC-MANUAL-05 | 待执行 | 待执行 | 需游戏内验证 |
| TC-MANUAL-06 | 待执行 | 待执行 | 需游戏内验证 |
| TC-MANUAL-07 | 待执行 | 待执行 | 需游戏内验证 |
| TC-MANUAL-08 | 待执行 | 待执行 | 需游戏内验证 |
| TC-MANUAL-09 | 待执行 | 待执行 | 需游戏内验证 |
| TC-MANUAL-10 | 待执行 | 待执行 | 需游戏内验证 |
| TC-MANUAL-11 | 待执行 | 待执行 | 需游戏内验证 |

## 6. 问题与阻塞

- 共享自动化校验当前失败：`validate_data_contracts.py` 报 `instance_questlines` 的 Lua 文件头 `contract_id` 与契约不一致。
- 游戏内手工验证未在本轮文档回写中执行，因此仍需后续补齐。

## 7. 结论

- 当前结论：有问题
- 后续动作：
  - 先修复 `instance_questlines` 的 Lua 文件头与契约不一致问题
  - 在游戏内补齐独立任务界面、最近完成和 Quest Inspector 的手工验证

## 8. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-15 | 初稿：建立 `quest` 模块当前实现的自动化与手工验证基线 |
| 2026-04-16 | 更新双视图与节点导航验证口径：补充底部页签、当前任务上下布局、历史完成折叠与通用导航路径回退场景 |
| 2026-04-16 | 补充顶部路径导航 `NavBar` 验证口径：要求对齐冒险指南地下城页签样式，并避让宿主头像 / 搜索框 |
