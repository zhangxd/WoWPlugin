describe("Navigation module", function()
  local originalToolbox = nil -- 原始 Toolbox 全局
  local registeredModule = nil -- 测试中捕获的模块定义

  before_each(function()
    originalToolbox = rawget(_G, "Toolbox")
    registeredModule = nil

    rawset(_G, "Toolbox", {
      L = {
        MODULE_NAVIGATION = "地图导航",
        MODULE_NAVIGATION_INTRO = "规划路线。",
        NAVIGATION_SETTINGS_HINT = "选择地图目标后显示路线。",
      },
      Config = {
        GetModule = function()
          return {
            enabled = true,
            debug = false,
          }
        end,
        ResetModule = function()
          return {}
        end,
      },
      Chat = {
        PrintAddonMessage = function() end,
      },
      RegisterModule = function(moduleDef)
        registeredModule = moduleDef
      end,
    })
  end)

  after_each(function()
    rawset(_G, "Toolbox", originalToolbox)
  end)

  it("registers_navigation_module_with_settings_contract", function()
    dofile("Toolbox/Modules/Navigation/Shared.lua")
    local moduleChunk = assert(loadfile("Toolbox/Modules/Navigation.lua")) -- navigation 模块 chunk
    moduleChunk()

    assert.is_table(registeredModule)
    assert.equals("navigation", registeredModule.id)
    assert.equals("MODULE_NAVIGATION", registeredModule.nameKey)
    assert.equals("MODULE_NAVIGATION_INTRO", registeredModule.settingsIntroKey)
    assert.is_function(registeredModule.RegisterSettings)
    assert.is_function(registeredModule.OnEnabledSettingChanged)
    assert.is_function(registeredModule.OnDebugSettingChanged)
    assert.is_function(registeredModule.ResetToDefaultsAndRebuild)
  end)

  it("installs_world_map_entry_on_enable_and_hides_ui_when_disabled", function()
    local installCount = 0 -- WorldMap 安装次数
    local hideCount = 0 -- WorldMap 隐藏次数
    local clearCount = 0 -- 路径条清除次数
    Toolbox.NavigationModule = {
      WorldMap = {
        Install = function()
          installCount = installCount + 1
        end,
        Hide = function()
          hideCount = hideCount + 1
        end,
      },
      RouteBar = {
        ClearRoute = function()
          clearCount = clearCount + 1
        end,
      },
    }

    dofile("Toolbox/Modules/Navigation/Shared.lua")
    local moduleChunk = assert(loadfile("Toolbox/Modules/Navigation.lua")) -- navigation 模块 chunk
    moduleChunk()

    registeredModule.OnModuleEnable()
    registeredModule.OnEnabledSettingChanged(false)

    assert.equals(1, installCount)
    assert.equals(1, hideCount)
    assert.equals(1, clearCount)
  end)

  it("shared_namespace_exposes_module_db_and_enabled_state", function()
    local moduleDb = {
      enabled = true,
      debug = false,
    } -- navigation 模块存档
    Toolbox.Config.GetModule = function(moduleId)
      assert.equals("navigation", moduleId)
      return moduleDb
    end

    dofile("Toolbox/Modules/Navigation/Shared.lua")

    assert.is_table(Toolbox.NavigationModule)
    assert.is_function(Toolbox.NavigationModule.GetModuleDb)
    assert.is_function(Toolbox.NavigationModule.IsEnabled)
    assert.is_true(Toolbox.NavigationModule.IsEnabled())

    moduleDb.enabled = false
    assert.is_false(Toolbox.NavigationModule.IsEnabled())
  end)
end)
