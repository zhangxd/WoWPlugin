describe("Toolbox.Chat copy default chat", function()
  local originalToolbox = nil -- 原始 Toolbox 全局
  local originalDefaultChatFrame = nil -- 原始默认聊天框
  local originalCopyText = nil -- 原始 C_CopyText
  local originalCanAccessValue = nil -- 原始 canaccessvalue

  local copiedText = nil -- 最近一次复制文本
  local inaccessibleValue = nil -- 模拟不可访问值

  local function loadChatApi()
    local chatChunk = assert(loadfile("Toolbox/Core/API/Chat.lua")) -- Chat API chunk
    chatChunk()
    assert.is_function(Toolbox.Chat.CopyDefaultChatToClipboard)
  end

  before_each(function()
    originalToolbox = rawget(_G, "Toolbox")
    originalDefaultChatFrame = rawget(_G, "DEFAULT_CHAT_FRAME")
    originalCopyText = rawget(_G, "C_CopyText")
    originalCanAccessValue = rawget(_G, "canaccessvalue")

    copiedText = nil
    inaccessibleValue = setmetatable({}, {
      __tostring = function()
        error("secret value should not be stringified by Toolbox.Chat")
      end,
    })

    rawset(_G, "Toolbox", {
      Chat = {},
      L = {},
    })
    rawset(_G, "DEFAULT_CHAT_FRAME", {
      GetNumMessages = function()
        return 3
      end,
      GetMessageInfo = function(_, indexNumber)
        if indexNumber == 1 then
          return "|cff00ff00第一条|r"
        end
        if indexNumber == 2 then
          return inaccessibleValue
        end
        return "|Hitem:1|h[测试物品]|h"
      end,
    })
    rawset(_G, "C_CopyText", function(text)
      copiedText = text
    end)
    rawset(_G, "canaccessvalue", function(value)
      return value ~= inaccessibleValue
    end)
  end)

  after_each(function()
    rawset(_G, "Toolbox", originalToolbox)
    rawset(_G, "DEFAULT_CHAT_FRAME", originalDefaultChatFrame)
    rawset(_G, "C_CopyText", originalCopyText)
    rawset(_G, "canaccessvalue", originalCanAccessValue)
  end)

  it("skips_inaccessible_chat_values_when_copying_recent_lines", function()
    loadChatApi()

    local success, resultKey = Toolbox.Chat.CopyDefaultChatToClipboard(30)

    assert.is_true(success)
    assert.equals("CHAT_COPY_SUCCESS", resultKey)
    assert.equals("第一条\n[测试物品]", copiedText)
  end)
end)
