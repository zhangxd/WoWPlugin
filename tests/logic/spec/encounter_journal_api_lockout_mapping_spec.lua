local Harness = dofile("tests/logic/harness/harness.lua")

describe("EncounterJournal lockout mapping", function()
  local harness = nil -- 测试 harness

  before_each(function()
    harness = Harness.new({
      locale = "zhCN",
      addonLoadedSeed = { Blizzard_EncounterJournal = false },
    })

    -- 覆盖为真实 API 实现（而非 harness 默认 stub）。
    local apiChunk = assert(loadfile("Toolbox/Core/API/EncounterJournal.lua"))
    apiChunk()
  end)

  after_each(function()
    if harness then
      harness:teardown()
    end
  end)

  it("matches_saved_lockout_by_instance_mapid_even_when_static_reverse_map_is_stale", function()
    Toolbox.Data.InstanceMapIDs = {
      [100] = 9001, -- 静态映射中仅存在错误/过时 journalID
    }

    _G.EJ_GetInstanceInfo = function(journalInstanceID)
      if journalInstanceID == 2001 then
        -- 第10个返回值是 mapID（参照 Blizzard AdventureGuideUtil 用法）。
        return "测试副本", "", 0, 0, 0, 0, 0, 0, 0, 9001
      end
      return nil
    end

    _G.GetNumSavedInstances = function()
      return 1
    end
    _G.GetSavedInstanceInfo = function(index)
      assert.equals(1, index)
      return "测试副本", 12345, 5400, 16, true, false, 0, true, 20, "史诗", 8, 0, false, 9001
    end

    _G.C_EncounterJournal = nil -- 强制走非 C_ API 的兜底路径，覆盖本次修复目标

    local lockouts = Toolbox.EJ.GetAllLockoutsForInstance(2001)
    assert.equals(1, #lockouts)
    assert.equals(16, lockouts[1].difficultyID)
    assert.equals(5400, lockouts[1].resetTime)
    assert.equals("史诗", lockouts[1].difficultyName)
  end)

  it("prefers_runtime_game_map_lookup_when_static_mapid_is_ambiguous", function()
    Toolbox.Data.InstanceMapIDs = {
      [100] = 9001,
      [2001] = 9001, -- 同 mapID 对应多个 journalID（静态反查歧义）
    }

    _G.EJ_GetInstanceInfo = function(journalInstanceID)
      if journalInstanceID == 2001 then
        return "测试副本", "", 0, 0, 0, 0, 0, 0, 0, 9001
      end
      return nil
    end

    _G.GetNumSavedInstances = function()
      return 1
    end
    _G.GetSavedInstanceInfo = function(index)
      assert.equals(1, index)
      return "测试副本", 12345, 5400, 16, true, false, 0, true, 20, "史诗", 8, 0, false, 9001
    end

    _G.C_EncounterJournal = {
      GetInstanceForGameMap = function(mapID)
        assert.equals(9001, mapID)
        return 100 -- 运行时映射明确指向另一个 journalID
      end,
    }

    local lockouts = Toolbox.EJ.GetAllLockoutsForInstance(2001)
    assert.equals(0, #lockouts)
  end)

  it("falls_back_to_instance_name_match_when_saved_mapid_is_unavailable", function()
    Toolbox.Data.InstanceMapIDs = {
      [2001] = 9001,
    }

    _G.EJ_GetInstanceInfo = function(journalInstanceID)
      if journalInstanceID == 2001 then
        return "测试副本", "", 0, 0, 0, 0, 0, 0, 0, 9001
      end
      return nil
    end

    _G.GetNumSavedInstances = function()
      return 1
    end
    _G.GetSavedInstanceInfo = function(index)
      assert.equals(1, index)
      -- 该场景模拟 instanceId 缺失（历史/特殊锁定记录），只能按副本名回退匹配。
      return "测试副本", 12345, 3600, 16, true, false, 0, true, 20, "史诗", 8, 0, false, nil
    end

    _G.C_EncounterJournal = nil

    local lockouts = Toolbox.EJ.GetAllLockoutsForInstance(2001)
    assert.equals(1, #lockouts)
    assert.equals(3600, lockouts[1].resetTime)
    assert.equals(16, lockouts[1].difficultyID)
  end)
end)
