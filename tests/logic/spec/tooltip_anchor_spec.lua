describe("Toolbox.Tooltip default anchor rollback", function()
  local originalToolbox = nil -- 原始 Toolbox 全局
  local originalNamespaceEnsure = nil -- 原始命名空间初始化函数
  local originalHooksecurefunc = nil -- 原始 hooksecurefunc
  local originalGetCVar = nil -- 原始 GetCVar
  local originalSetCVar = nil -- 原始 SetCVar
  local originalCCVar = nil -- 原始 C_CVar
  local installedHookName = nil -- 已安装 hook 名称
  local installedHookCallback = nil -- 已安装 hook 回调
  local moduleDb = nil -- tooltip_anchor 模块存档

  local function loadTooltipApi()
    local tooltipChunk = assert(loadfile("Toolbox/Core/API/Tooltip.lua")) -- Tooltip API chunk
    tooltipChunk()
    assert.is_function(Toolbox.Tooltip.InstallDefaultAnchorHook)
    assert.is_function(Toolbox.Tooltip.RefreshDriver)
  end

  local function newTooltipDouble()
    local tooltipDouble = {
      clearAllPointsCount = 0,
      setOwnerCall = nil,
    } -- tooltip 替身

    function tooltipDouble:ClearAllPoints()
      self.clearAllPointsCount = self.clearAllPointsCount + 1
    end

    function tooltipDouble:SetOwner(ownerFrame, anchorPoint, offsetX, offsetY)
      self.setOwnerCall = {
        ownerFrame = ownerFrame,
        anchorPoint = anchorPoint,
        offsetX = offsetX,
        offsetY = offsetY,
      }
    end

    return tooltipDouble
  end

  before_each(function()
    originalToolbox = rawget(_G, "Toolbox")
    originalNamespaceEnsure = rawget(_G, "Toolbox_NamespaceEnsure")
    originalHooksecurefunc = rawget(_G, "hooksecurefunc")
    originalGetCVar = rawget(_G, "GetCVar")
    originalSetCVar = rawget(_G, "SetCVar")
    originalCCVar = rawget(_G, "C_CVar")

    installedHookName = nil
    installedHookCallback = nil
    moduleDb = {
      enabled = true,
      debug = false,
      mode = "cursor",
      offsetX = 12,
      offsetY = -5,
    }

    rawset(_G, "Toolbox", {
      Tooltip = {},
      Config = {
        GetModule = function()
          return moduleDb
        end,
      },
      Chat = {
        PrintAddonMessage = function() end,
      },
      L = {},
    })
    rawset(_G, "Toolbox_NamespaceEnsure", function() end)
    rawset(_G, "hooksecurefunc", function(functionName, callbackFunction)
      installedHookName = functionName
      installedHookCallback = callbackFunction
    end)
    rawset(_G, "GetCVar", function()
      error("tooltip rollback path should not read GetCVar")
    end)
    rawset(_G, "SetCVar", function()
      error("tooltip rollback path should not write SetCVar")
    end)
    rawset(_G, "C_CVar", {
      GetCVar = function()
        error("tooltip rollback path should not read C_CVar.GetCVar")
      end,
      SetCVar = function()
        error("tooltip rollback path should not write C_CVar.SetCVar")
      end,
    })
  end)

  after_each(function()
    rawset(_G, "Toolbox", originalToolbox)
    rawset(_G, "Toolbox_NamespaceEnsure", originalNamespaceEnsure)
    rawset(_G, "hooksecurefunc", originalHooksecurefunc)
    rawset(_G, "GetCVar", originalGetCVar)
    rawset(_G, "SetCVar", originalSetCVar)
    rawset(_G, "C_CVar", originalCCVar)
  end)

  it("registers_global_gametooltip_default_anchor_hook", function()
    loadTooltipApi()

    Toolbox.Tooltip.InstallDefaultAnchorHook()

    assert.equals("GameTooltip_SetDefaultAnchor", installedHookName)
    assert.is_function(installedHookCallback)
  end)

  it("cursor_mode_overrides_anchor_near_cursor_without_uber_tooltips_state", function()
    loadTooltipApi()
    Toolbox.Tooltip.InstallDefaultAnchorHook()
    assert.is_function(installedHookCallback)

    local refreshSuccess, refreshError = pcall(Toolbox.Tooltip.RefreshDriver)
    assert.is_true(refreshSuccess, refreshError)
    assert.is_nil(moduleDb.managedUberTooltipsActive)
    assert.is_nil(moduleDb.managedUberTooltipsOriginal)

    local tooltipDouble = newTooltipDouble()
    local ownerFrame = {} -- 锚点来源 frame
    installedHookCallback(tooltipDouble, ownerFrame)

    assert.equals(1, tooltipDouble.clearAllPointsCount)
    assert.same({
      ownerFrame = ownerFrame,
      anchorPoint = "ANCHOR_CURSOR_LEFT",
      offsetX = 12,
      offsetY = -5,
    }, tooltipDouble.setOwnerCall)
  end)

  it("follow_mode_reuses_same_cursor_anchor_override", function()
    loadTooltipApi()
    Toolbox.Tooltip.InstallDefaultAnchorHook()
    assert.is_function(installedHookCallback)

    moduleDb.mode = "follow"
    moduleDb.offsetX = -8
    moduleDb.offsetY = 3

    local refreshSuccess, refreshError = pcall(Toolbox.Tooltip.RefreshDriver)
    assert.is_true(refreshSuccess, refreshError)

    local tooltipDouble = newTooltipDouble()
    local ownerFrame = {} -- 锚点来源 frame
    installedHookCallback(tooltipDouble, ownerFrame)

    assert.equals(1, tooltipDouble.clearAllPointsCount)
    assert.same({
      ownerFrame = ownerFrame,
      anchorPoint = "ANCHOR_CURSOR_LEFT",
      offsetX = -8,
      offsetY = 3,
    }, tooltipDouble.setOwnerCall)
  end)

  it("default_mode_keeps_original_anchor_behavior", function()
    loadTooltipApi()
    Toolbox.Tooltip.InstallDefaultAnchorHook()
    assert.is_function(installedHookCallback)

    moduleDb.mode = "default"

    local refreshSuccess, refreshError = pcall(Toolbox.Tooltip.RefreshDriver)
    assert.is_true(refreshSuccess, refreshError)

    local tooltipDouble = newTooltipDouble()
    installedHookCallback(tooltipDouble, {})

    assert.equals(0, tooltipDouble.clearAllPointsCount)
    assert.is_nil(tooltipDouble.setOwnerCall)
  end)

  it("disabled_module_keeps_original_anchor_behavior", function()
    loadTooltipApi()
    Toolbox.Tooltip.InstallDefaultAnchorHook()
    assert.is_function(installedHookCallback)

    moduleDb.enabled = false

    local refreshSuccess, refreshError = pcall(Toolbox.Tooltip.RefreshDriver)
    assert.is_true(refreshSuccess, refreshError)

    local tooltipDouble = newTooltipDouble()
    installedHookCallback(tooltipDouble, {})

    assert.equals(0, tooltipDouble.clearAllPointsCount)
    assert.is_nil(tooltipDouble.setOwnerCall)
  end)
end)
