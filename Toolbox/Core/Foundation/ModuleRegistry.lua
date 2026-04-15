--[[
  RegisterModule：各 Modules/*.lua 在加载时调用，仅登记定义。
  Bootstrap 在 ADDON_LOADED 里 RunOnModuleLoad，PLAYER_LOGIN 里 RunOnModuleEnable。
  dependencies 用于拓扑排序：被依赖的模块先执行。
  模块定义可含 nameKey（对应 Toolbox.L 键），由 SettingsHost 显示本地化标题。
  设置页相关约定：
  - settingsIntroKey：页面简介文案键
  - settingsOrder：子页面顺序（数字越小越靠前）
  - RegisterSettings(box)：仅绘制模块专属设置区
  - GetSettingsPages()：返回额外设置子页面定义列表；每项至少含 `id`、`titleKey`、`build(page, box)`
  - OnEnabledSettingChanged(enabled)：公共启用开关变化后同步模块状态
  - OnDebugSettingChanged(enabled)：公共调试开关变化后同步模块状态
  - ResetToDefaultsAndRebuild()：公共“清理并重建”入口
]]

local list = {}

function Toolbox.RegisterModule(def)
  assert(type(def) == "table" and def.id, "Toolbox.RegisterModule: need def.id")
  list[#list + 1] = def
end

local function indexById()
  local t = {}
  for _, m in ipairs(list) do
    t[m.id] = m
  end
  return t
end

-- 依赖先出队：DFS + visiting 防环（环内依赖本实现不展开，仅防死循环）
local function topoSort()
  local byId = indexById()
  local sorted = {}
  local visiting = {}
  local visited = {}
  local circularDeps = {}

  local function visit(id)
    if visited[id] then
      return
    end
    local m = byId[id]
    if not m then
      return
    end
    if visiting[id] then
      -- 检测到环，记录警告
      if not circularDeps[id] then
        circularDeps[id] = true
      end
      return
    end
    visiting[id] = true
    if m.dependencies then
      for _, dep in ipairs(m.dependencies) do
        visit(dep)
      end
    end
    visiting[id] = nil
    visited[id] = true
    sorted[#sorted + 1] = m
  end

  for _, m in ipairs(list) do
    visit(m.id)
  end

  -- 输出环检测警告
  if next(circularDeps) then
    local g = Toolbox.Config and Toolbox.Config.GetGlobal and Toolbox.Config.GetGlobal()
    if g and g.debug then
      for id in pairs(circularDeps) do
        print(string.format("[Toolbox] Warning: circular dependency detected for module '%s'", id))
      end
    end
  end

  return sorted
end

Toolbox.ModuleRegistry = {}

function Toolbox.ModuleRegistry:GetSorted()
  return topoSort()
end

function Toolbox.ModuleRegistry:RunOnModuleLoad()
  Toolbox_NamespaceEnsure()
  for _, m in ipairs(self:GetSorted()) do
    if m.OnModuleLoad then
      m.OnModuleLoad()
    end
  end
end

function Toolbox.ModuleRegistry:RunOnModuleEnable()
  Toolbox_NamespaceEnsure()
  for _, m in ipairs(self:GetSorted()) do
    if m.OnModuleEnable then
      m.OnModuleEnable()
    end
  end
end
