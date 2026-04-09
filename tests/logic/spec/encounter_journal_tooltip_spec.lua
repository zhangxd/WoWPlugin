local Harness = dofile("tests/logic/harness/harness.lua")

local function formatLinesForGolden(lineList)
  local normalized = {} -- 规范化行文本
  for _, lineText in ipairs(lineList) do
    if type(lineText) == "string" and lineText:match("^%s*$") then
      normalized[#normalized + 1] = "<BLANK>"
    else
      normalized[#normalized + 1] = lineText
    end
  end
  return table.concat(normalized, "\n")
end

local function readFileText(pathText)
  local fileRef = assert(io.open(pathText, "rb")) -- 文件句柄
  local content = fileRef:read("*a") -- 文件内容
  fileRef:close()
  content = content:gsub("\r\n", "\n")
  content = content:gsub("%s+$", "")
  return content
end

describe("EncounterJournal micro button tooltip", function()
  local harness = nil -- 测试 harness

  local function setupHarness(localeName)
    harness = Harness.new({
      locale = localeName,
      addonLoadedSeed = { Blizzard_EncounterJournal = false },
    })
    harness:loadEncounterJournalModule()
    harness:emit("PLAYER_ENTERING_WORLD")
  end

  after_each(function()
    if harness then
      harness:teardown()
    end
  end)

  it("micro_button_tooltip_empty_state_lines", function()
    setupHarness("zhCN")
    harness:setLockoutTooltipData({}, 0)
    harness:triggerMicroButtonOnEnter()

    local lines = harness:getTooltipLines() -- tooltip 行列表
    assert.are.same({
      " ",
      "当前锁定",
      "当前没有副本进度锁定。",
    }, lines)
  end)

  it("micro_button_tooltip_overflow_appends_more_line", function()
    setupHarness("zhCN")
    harness:setLockoutTooltipData({
      "副本一 · 史诗 · 2d 3h",
      "副本二 · 英雄 · 1d 5h",
    }, 3)
    harness:triggerMicroButtonOnEnter()

    local lines = harness:getTooltipLines() -- tooltip 行列表
    assert.are.same({
      " ",
      "当前锁定",
      "副本一 · 史诗 · 2d 3h",
      "副本二 · 英雄 · 1d 5h",
      "还有 3 条未显示",
    }, lines)
  end)

  it("tooltip_lines_match_golden_for_known_dataset", function()
    setupHarness("zhCN")
    harness:setLockoutTooltipData({
      "卡拉赞 · 史诗 · 2d 3h",
      "暗夜要塞 · 普通 · 1d 8h",
      "地狱火堡垒 · 英雄 · 5h",
    }, 2)
    harness:triggerMicroButtonOnEnter()

    local lines = harness:getTooltipLines() -- tooltip 行列表
    local actualText = formatLinesForGolden(lines) -- 规范化实际输出
    local goldenPath = "tests/logic/golden/zhCN/encounter_journal_tooltip_lockout_lines.golden.txt" -- golden 文件路径
    local expectedText = readFileText(goldenPath) -- 期望输出

    if os.getenv("UPDATE_GOLDEN") == "1" then
      local outputFile = assert(io.open(goldenPath, "wb"))
      outputFile:write(actualText)
      outputFile:close()
      expectedText = actualText
    end

    assert.equals(expectedText, actualText)
  end)
end)
