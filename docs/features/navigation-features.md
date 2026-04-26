# 地图导航功能说明

- 文档类型：功能
- 状态：已发布
- 主题：navigation
- 适用范围：`navigation` 模块第一版地图目标路线规划
- 关联模块：`navigation`
- 关联文档：
  - `docs/specs/navigation-spec.md`
  - `docs/designs/navigation-design.md`
  - `docs/plans/navigation-plan.md`
  - `docs/tests/navigation-test.md`
  - `docs/Toolbox-addon-design.md`
- 最后更新：2026-04-27

## 1. 定位

- `navigation` 是独立地图导航模块，用于从世界地图目标生成当前角色可用的旅行路线。
- 第一版已把当前地点、公共传送门、主城 / 资料片枢纽和部分职业位移能力纳入同一张旅行图，并把路线显示在屏幕顶部中间。

## 2. 适用场景

- 玩家打开世界地图，把鼠标放在目标位置后，希望插件按当前角色能力给出路线步骤。
- 典型场景：当前角色位于银月城时，可先使用银月城到奥格瑞玛的公共传送门，再经奥格瑞玛传送门房前往海加尔山；若当前角色是部落法师且已确认拥有相关主城传送，也会优先使用已知传送技能。

## 3. 当前能力

- 在 `navigation` 模块启用后，世界地图显示时会创建“规划路线”按钮。
- 点击“规划路线”会读取当前世界地图 `uiMapID` 与鼠标归一化坐标。
- 路径规划会按当前角色职业、阵营、当前位置和已确认技能过滤不可用路径边。
- 顶部路径条 `ToolboxNavigationRouteBar` 会在屏幕顶部中间显示路线步骤。
- 当前静态数据分两层：
  - `Toolbox.Data.NavigationMapNodes`：由 `DataContracts/navigation_map_nodes.json` 通过正式导出脚本生成的 UiMap 基础节点。
  - `Toolbox.Data.NavigationManualEdges`：手工维护的玩法路径边，包含部落主城公共传送门、奥格瑞玛传送门房、法师主城传送、死亡骑士死亡之门、德鲁伊梦境行者 / 月光林地传送、武僧禅宗朝圣等第一批高价值路线。

## 4. 入口与使用方式

- 打开世界地图。
- 将鼠标放在目标地图位置。
- 点击世界地图上的“规划路线”按钮。
- 查看屏幕顶部中间显示的路线步骤。

## 5. 设置项

- 模块设置页提供公共启用 / 调试 / 重置入口。
- 顶部路径条第一版固定在屏幕顶部中间，不开放拖动设置。
- 最近目标调试字段保存在 `ToolboxDB.modules.navigation.lastTargetUiMapID / lastTargetX / lastTargetY`。

## 6. 已知限制

- 第一版不纳入飞行点 / 飞行管理员。
- 第一版不做账号其他角色能力推断，只看当前角色。
- 第一版不实现真实地形寻路、避障或逐米移动路线。
- 当前人工路径边仍不是全量交通数据库；玩具、炉石、节日传送、战役阶段限定传送门、联盟侧完整传送门网络和更多职业特殊交通需要继续扩充。
- 当前不拦截世界地图原生点击；目标坐标由“鼠标指向 + 点击规划按钮”确定。

## 7. 关联文档

- 需求：`docs/specs/navigation-spec.md`
- 设计：`docs/designs/navigation-design.md`
- 计划：`docs/plans/navigation-plan.md`
- 测试：`docs/tests/navigation-test.md`
- 总设计：`docs/Toolbox-addon-design.md`

## 8. 修订记录

| 日期 | 内容 |
|------|------|
| 2026-04-27 | 初稿：发布 `navigation` 第一版地图目标路线规划功能说明 |
| 2026-04-27 | 扩充为多枢纽旅行图：纳入当前位置、部落公共传送门、奥格瑞玛传送门房与部分非 mage 职业位移 |
