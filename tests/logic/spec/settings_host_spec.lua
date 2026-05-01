local function deepCopyTable(sourceTable)
  if type(sourceTable) ~= "table" then
    return sourceTable
  end

  local copiedTable = {} -- 深拷贝结果
  for keyName, valueObject in pairs(sourceTable) do
    copiedTable[keyName] = deepCopyTable(valueObject)
  end
  return copiedTable
end

describe("Toolbox.SettingsHost", function()
  local originalToolbox = nil -- 原始 Toolbox 全局
  local originalToolboxDB = nil -- 原始 ToolboxDB 全局
  local originalCopyTable = nil -- 原始 CopyTable 全局
  local originalCreateFrame = nil -- 原始 CreateFrame 全局
  local originalUIParent = nil -- 原始 UIParent 全局
  local originalSettings = nil -- 原始 Settings 全局
  local originalHideUIPanel = nil -- 原始 HideUIPanel 全局
  local originalInCombatLockdown = nil -- 原始 InCombatLockdown 全局
  local originalReloadUI = nil -- 原始 ReloadUI 全局
  local originalToolboxNamespaceEnsure = nil -- 原始 Toolbox_NamespaceEnsure 全局
  local originalGameMenuFrame = nil -- 原始 GameMenuFrame 全局

  local runtime = nil -- fake runtime
  local settingsApi = nil -- fake Settings API
  local combatLocked = false -- 是否处于战斗锁定
  local moduleList = nil -- 当前模块列表

  local function decorateFrame(frameObject)
    if type(frameObject) ~= "table" or frameObject._settingsHostDecorated == true then
      return frameObject
    end

    frameObject._settingsHostDecorated = true

    if type(frameObject.SetAllPoints) ~= "function" then
      function frameObject:SetAllPoints(relativeFrame)
        self._allPoints = relativeFrame or true
      end
    end
    if type(frameObject.EnableKeyboard) ~= "function" then
      function frameObject:EnableKeyboard(enabled)
        self._keyboardEnabled = enabled == true
      end
    end
    if type(frameObject.SetScale) ~= "function" then
      function frameObject:SetScale(scaleValue)
        self._scale = scaleValue
      end
    end
    if type(frameObject.GetScale) ~= "function" then
      function frameObject:GetScale()
        return self._scale or 1
      end
    end
    if type(frameObject.SetPropagateKeyboardInput) ~= "function" then
      function frameObject:SetPropagateKeyboardInput(enabled)
        self._propagateKeyboardInput = enabled == true
      end
    end
    if type(frameObject.GetName) ~= "function" then
      function frameObject:GetName()
        return self.frameName
      end
    end

    local originalCreateFontString = frameObject.CreateFontString
    if type(originalCreateFontString) == "function" then
      frameObject.CreateFontString = function(self, ...)
        local childObject = originalCreateFontString(self, ...)
        return decorateFrame(childObject)
      end
    end

    local originalCreateTexture = frameObject.CreateTexture
    if type(originalCreateTexture) == "function" then
      frameObject.CreateTexture = function(self, ...)
        local childObject = originalCreateTexture(self, ...)
        return decorateFrame(childObject)
      end
    end

    return frameObject
  end

  local function installEnvironment()
    local newFakeRuntime = dofile("tests/logic/harness/fake_runtime.lua")
    runtime = newFakeRuntime({})
    combatLocked = false
    moduleList = {}

    settingsApi = {
      categoryRegisterCount = 0,
      subcategoryRegisterCount = 0,
      openCategoryCalls = {},
      categoryList = {},
      subcategoryList = {},
    }

    local nextCategoryId = 0 -- 新类目 id
    local function makeCategory(nameText, panelObject, parentCategory)
      nextCategoryId = nextCategoryId + 1
      local categoryObject = {
        id = nextCategoryId,
        name = nameText,
        panel = panelObject,
        parent = parentCategory,
      }
      function categoryObject:GetID()
        return self.id
      end
      function categoryObject:SetName(newName)
        self.name = newName
      end
      return categoryObject
    end

    function settingsApi.RegisterCanvasLayoutCategory(panelObject, nameText)
      settingsApi.categoryRegisterCount = settingsApi.categoryRegisterCount + 1
      local categoryObject = makeCategory(nameText, panelObject, nil)
      settingsApi.categoryList[#settingsApi.categoryList + 1] = categoryObject
      return categoryObject
    end

    function settingsApi.RegisterCanvasLayoutSubcategory(parentCategory, panelObject, nameText)
      settingsApi.subcategoryRegisterCount = settingsApi.subcategoryRegisterCount + 1
      local categoryObject = makeCategory(nameText, panelObject, parentCategory)
      settingsApi.subcategoryList[#settingsApi.subcategoryList + 1] = categoryObject
      return categoryObject
    end

    function settingsApi.RegisterAddOnCategory(categoryObject)
      return categoryObject
    end

    function settingsApi.OpenToCategory(categoryId)
      settingsApi.openCategoryCalls[#settingsApi.openCategoryCalls + 1] = categoryId
    end

    rawset(_G, "Toolbox", {
      Config = {},
      L = {
        SETTINGS_CATEGORY_TITLE = "Toolbox",
        SETTINGS_PAGE_GENERAL_TITLE = "通用",
        SETTINGS_PAGE_GENERAL_INTRO = "General",
        SETTINGS_PAGE_INTERFACE_TITLE = "界面",
        SETTINGS_PAGE_INTERFACE_INTRO = "Interface",
        SETTINGS_PAGE_MAP_TITLE = "地图",
        SETTINGS_PAGE_MAP_INTRO = "Map",
        SETTINGS_PAGE_QUEST_TITLE = "任务",
        SETTINGS_PAGE_QUEST_INTRO = "Quest",
        SETTINGS_PAGE_ENCOUNTER_JOURNAL_TITLE = "冒险手册",
        SETTINGS_PAGE_ENCOUNTER_JOURNAL_INTRO = "EJ",
        SETTINGS_PAGE_ABOUT_TITLE = "关于",
        SETTINGS_PAGE_ABOUT_INTRO = "About",
        SETTINGS_MODULE_ENABLE = "启用",
        SETTINGS_MODULE_DEBUG = "调试",
        SETTINGS_MODULE_RESET_REBUILD = "重置",
        SETTINGS_MODULE_RESET_HINT = "重置提示",
        SETTINGS_MODULE_SECTION_TITLE = "设置",
        LOCALE_SECTION_TITLE = "语言",
        LOCALE_OPTION_AUTO = "自动",
        LOCALE_OPTION_ZHCN = "简中",
        LOCALE_OPTION_ENUS = "English",
        LOCALE_HINT = "语言说明",
        SETTINGS_RELOAD_UI = "重载",
        SETTINGS_RELOAD_HINT = "重载说明",
      },
      Chat = {
        PrintAddonMessage = function() end,
        GetAddOnMetadata = function()
          return "test"
        end,
      },
      ModuleRegistry = {
        GetSorted = function()
          return moduleList
        end,
      },
      Locale_Apply = function() end,
      SettingsHost = nil,
    })
    rawset(_G, "CopyTable", deepCopyTable)
    rawset(_G, "Toolbox_NamespaceEnsure", function() end)
    rawset(_G, "Settings", settingsApi)
    rawset(_G, "HideUIPanel", function() end)
    rawset(_G, "InCombatLockdown", function()
      return combatLocked == true
    end)
    rawset(_G, "ReloadUI", function() end)
    rawset(_G, "UIParent", decorateFrame(runtime.CreateFrame("Frame", "UIParent")))
    rawset(_G, "GameMenuFrame", decorateFrame(runtime.CreateFrame("Frame", "GameMenuFrame")))
    rawset(_G, "CreateFrame", function(frameType, frameName, parentFrame, templateName)
      local frameObject = decorateFrame(runtime.CreateFrame(frameType, frameName, parentFrame, templateName))
      if type(templateName) == "string" and string.find(templateName, "CheckButton", 1, true) ~= nil then
        frameObject.Text = decorateFrame(runtime.CreateFrame("FontString", nil, frameObject))
      end
      return frameObject
    end)
  end

  local function loadConfigAndHost()
    local configChunk = assert(loadfile("Toolbox/Core/Foundation/Config.lua")) -- Config chunk
    configChunk()
    Toolbox.Config.Init()

    local hostChunk = assert(loadfile("Toolbox/UI/SettingsHost.lua")) -- SettingsHost chunk
    hostChunk()
    Toolbox.SettingsHost:EnsureCreated()
  end

  before_each(function()
    originalToolbox = rawget(_G, "Toolbox")
    originalToolboxDB = rawget(_G, "ToolboxDB")
    originalCopyTable = rawget(_G, "CopyTable")
    originalCreateFrame = rawget(_G, "CreateFrame")
    originalUIParent = rawget(_G, "UIParent")
    originalSettings = rawget(_G, "Settings")
    originalHideUIPanel = rawget(_G, "HideUIPanel")
    originalInCombatLockdown = rawget(_G, "InCombatLockdown")
    originalReloadUI = rawget(_G, "ReloadUI")
    originalToolboxNamespaceEnsure = rawget(_G, "Toolbox_NamespaceEnsure")
    originalGameMenuFrame = rawget(_G, "GameMenuFrame")
  end)

  after_each(function()
    rawset(_G, "Toolbox", originalToolbox)
    rawset(_G, "ToolboxDB", originalToolboxDB)
    rawset(_G, "CopyTable", originalCopyTable)
    rawset(_G, "CreateFrame", originalCreateFrame)
    rawset(_G, "UIParent", originalUIParent)
    rawset(_G, "Settings", originalSettings)
    rawset(_G, "HideUIPanel", originalHideUIPanel)
    rawset(_G, "InCombatLockdown", originalInCombatLockdown)
    rawset(_G, "ReloadUI", originalReloadUI)
    rawset(_G, "Toolbox_NamespaceEnsure", originalToolboxNamespaceEnsure)
    rawset(_G, "GameMenuFrame", originalGameMenuFrame)
  end)

  it("invalid_saved_page_falls_back_to_general", function()
    installEnvironment()
    rawset(_G, "ToolboxDB", {
      version = 2,
      global = {
        settingsLastLeafPage = "invalid_page",
      },
      modules = {},
    })

    loadConfigAndHost()

    assert.equals("general", Toolbox.SettingsHost:GetPreferredLeafPageKey())
  end)

  it("open_to_page_in_combat_skips_settings_api_and_remembers_page_key", function()
    installEnvironment()
    rawset(_G, "ToolboxDB", nil)
    loadConfigAndHost()

    combatLocked = true
    Toolbox.SettingsHost:OpenToPageKey("map")

    assert.equals("map", Toolbox.Config.GetGlobal().settingsLastLeafPage)
    assert.equals(0, #settingsApi.openCategoryCalls)
  end)

  it("build_page_exposes_box_helpers_and_normalizes_invalid_choice_values", function()
    installEnvironment()
    rawset(_G, "ToolboxDB", nil)
    local capturedBox = nil -- 当前设置 box

    moduleList = {
      {
        id = "mover",
        nameKey = "MODULE_MOVER",
        settingsIntroKey = "MODULE_MOVER_INTRO",
        settingsOrder = 20,
        OnEnabledSettingChanged = function() end,
        OnDebugSettingChanged = function() end,
        ResetToDefaultsAndRebuild = function() end,
        RegisterSettings = function(box)
          capturedBox = box
          local moduleDb = Toolbox.Config.GetModule("mover") -- mover 模块存档
          assert.is_function(box.AddToggleRow)
          assert.is_function(box.AddChoiceRow)
          assert.is_function(box.AddMenuRow)
          assert.is_function(box.AddCustomBlock)
          assert.is_function(box.RequestLocalRefresh)
          assert.is_function(box.RequestPageRebuild)

          box:AddChoiceRow({
            label = "命中模式",
            description = "测试非法值归一",
            getValue = function()
              return moduleDb.blizzardDragHitMode
            end,
            setValue = function(value)
              moduleDb.blizzardDragHitMode = value
            end,
            defaultValue = "titlebar",
            options = {
              { value = "titlebar", label = "标题栏" },
              { value = "titlebar_and_empty", label = "标题栏与空白区" },
            },
          })

          box:AddCustomBlock(function(blockFrame)
            blockFrame:SetHeight(72)
            return 72
          end)
        end,
      },
    }

    loadConfigAndHost()
    local moduleDb = Toolbox.Config.GetModule("mover") -- mover 模块存档
    moduleDb.blizzardDragHitMode = "broken"

    assert.has_no.errors(function()
      Toolbox.SettingsHost:BuildPage("interface")
    end)
    assert.equals("titlebar", moduleDb.blizzardDragHitMode)
    assert.is_true((capturedBox and capturedBox.realHeight or 0) >= 72)
  end)

  it("menu_row_normalizes_invalid_values_to_default", function()
    installEnvironment()
    rawset(_G, "ToolboxDB", nil)

    local menuButton = nil -- 菜单按钮
    moduleList = {
      {
        id = "tooltip_anchor",
        nameKey = "MODULE_TOOLTIP",
        settingsIntroKey = "MODULE_TOOLTIP_INTRO",
        settingsOrder = 40,
        OnEnabledSettingChanged = function() end,
        OnDebugSettingChanged = function() end,
        ResetToDefaultsAndRebuild = function() end,
        RegisterSettings = function(box)
          local moduleDb = Toolbox.Config.GetModule("tooltip_anchor") -- tooltip 模块存档
          menuButton = box:AddMenuRow({
            label = "提示框模式",
            description = "测试菜单默认值归一",
            defaultValue = "default",
            getValue = function()
              return moduleDb.mode
            end,
            setValue = function(value)
              moduleDb.mode = value
            end,
            options = {
              { value = "default", label = "默认" },
              { value = "cursor", label = "光标" },
              { value = "follow", label = "跟随" },
            },
          })
        end,
      },
    }

    loadConfigAndHost()
    local moduleDb = Toolbox.Config.GetModule("tooltip_anchor") -- tooltip 模块存档
    moduleDb.mode = "broken"

    Toolbox.SettingsHost:BuildPage("interface")

    assert.equals("default", moduleDb.mode)
    assert.is_truthy(menuButton)
    assert.is_truthy(menuButton._toolboxPopupFrame)
    assert.is_false(menuButton._toolboxPopupFrame:IsShown())
    assert.equals("默认 v", menuButton:GetText())
    menuButton:RunScript("OnClick")
    assert.is_true(menuButton._toolboxPopupFrame:IsShown())
    menuButton:RunScript("OnClick")
    assert.is_false(menuButton._toolboxPopupFrame:IsShown())
  end)

  it("toggle_row_normalizes_missing_values_to_default", function()
    installEnvironment()
    rawset(_G, "ToolboxDB", nil)

    moduleList = {
      {
        id = "mover",
        nameKey = "MODULE_MOVER",
        settingsIntroKey = "MODULE_MOVER_INTRO",
        settingsOrder = 20,
        OnEnabledSettingChanged = function() end,
        OnDebugSettingChanged = function() end,
        ResetToDefaultsAndRebuild = function() end,
        RegisterSettings = function(box)
          local moduleDb = Toolbox.Config.GetModule("mover") -- mover 模块存档
          box:AddToggleRow({
            label = "默认启用",
            defaultValue = true,
            getValue = function()
              return moduleDb.enabled
            end,
            setValue = function(value)
              moduleDb.enabled = value == true
            end,
          })
        end,
      },
    }

    loadConfigAndHost()
    local moduleDb = Toolbox.Config.GetModule("mover") -- mover 模块存档
    moduleDb.enabled = nil
    Toolbox.SettingsHost:BuildPage("interface")
    assert.is_true(moduleDb.enabled)
  end)

  it("local_refresh_updates_dependent_rows_without_calling_build_page", function()
    installEnvironment()
    rawset(_G, "ToolboxDB", nil)

    local toggleButton = nil -- 依赖父开关按钮
    local choiceButtons = nil -- 依赖子项按钮
    moduleList = {
      {
        id = "mover",
        nameKey = "MODULE_MOVER",
        settingsIntroKey = "MODULE_MOVER_INTRO",
        settingsOrder = 20,
        OnEnabledSettingChanged = function() end,
        OnDebugSettingChanged = function() end,
        ResetToDefaultsAndRebuild = function() end,
        RegisterSettings = function(box)
          local moduleDb = Toolbox.Config.GetModule("mover") -- mover 模块存档
          toggleButton = box:AddToggleRow({
            label = "高级选项",
            defaultValue = false,
            refreshMode = "local",
            getValue = function()
              return moduleDb.allowDragInCombat
            end,
            setValue = function(value)
              moduleDb.allowDragInCombat = value == true
            end,
          })
          choiceButtons = box:AddChoiceRow({
            label = "依赖项",
            defaultValue = "titlebar",
            enabledWhen = function()
              return moduleDb.allowDragInCombat == true
            end,
            getValue = function()
              return moduleDb.blizzardDragHitMode
            end,
            setValue = function(value)
              moduleDb.blizzardDragHitMode = value
            end,
            options = {
              { value = "titlebar", label = "标题栏" },
              { value = "titlebar_and_empty", label = "标题栏与空白区" },
            },
          })
        end,
      },
    }

    loadConfigAndHost()
    local originalBuildPage = Toolbox.SettingsHost.BuildPage -- 原始 BuildPage
    local buildPageCallCount = 0 -- BuildPage 调用次数
    Toolbox.SettingsHost.BuildPage = function(self, pageKey)
      buildPageCallCount = buildPageCallCount + 1
      return originalBuildPage(self, pageKey)
    end

    local success, err = pcall(function()
      Toolbox.SettingsHost:BuildPage("interface")
      assert.is_truthy(toggleButton)
      assert.is_truthy(choiceButtons)
      assert.is_false(choiceButtons[2]:IsEnabled())
      toggleButton:RunScript("OnClick")
      assert.equals(1, buildPageCallCount)
      assert.is_true(choiceButtons[2]:IsEnabled())
    end)

    Toolbox.SettingsHost.BuildPage = originalBuildPage
    assert.is_true(success, err)
  end)

  it("refresh_all_pages_does_not_register_categories_again", function()
    installEnvironment()
    rawset(_G, "ToolboxDB", nil)
    loadConfigAndHost()

    local categoryCount = settingsApi.categoryRegisterCount -- 根类目注册次数
    local subcategoryCount = settingsApi.subcategoryRegisterCount -- 叶子页注册次数
    Toolbox.SettingsHost:RefreshAllPages()

    assert.equals(categoryCount, settingsApi.categoryRegisterCount)
    assert.equals(subcategoryCount, settingsApi.subcategoryRegisterCount)
  end)

  it("combat_reopen_updates_last_leaf_page_without_using_settings_api", function()
    installEnvironment()
    rawset(_G, "ToolboxDB", nil)
    loadConfigAndHost()

    combatLocked = true
    Toolbox.SettingsHost:OpenToPageKey("map")
    Toolbox.SettingsHost:OpenToPageKey("quest")

    assert.equals("quest", Toolbox.Config.GetGlobal().settingsLastLeafPage)
    assert.equals(0, #settingsApi.openCategoryCalls)
  end)
end)
